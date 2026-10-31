import hmac
import logging
import re
from contextlib import asynccontextmanager
from typing import Literal
from uuid import UUID
from fastapi import FastAPI, Request, Response, Depends
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, ConfigDict, Field
from psycopg import Error as DatabaseError, IntegrityError
from psycopg_pool import PoolTimeout
from starlette.concurrency import run_in_threadpool
from starlette.exceptions import HTTPException as StarletteHTTPException
from .config import ROOT, get_settings
from .db import Database
from .documents import inspect_upload
from .errors import AppError
from .exports import export
from .repository import Repository
from .middleware import BodyLimitMiddleware
from .security import COOKIE, Sessions, Encryption, csrf_for, opaque_key

logger=logging.getLogger('firstrole')

class Decision(BaseModel):
    model_config=ConfigDict(extra='forbid')
    decision: Literal['approve','reject']
    final_letter: str=Field(min_length=1,max_length=20000)
    draft_version: int=Field(ge=1)

class Controls(BaseModel):
    model_config=ConfigDict(extra='forbid')
    paused: bool | None=None
    auto_manage: bool | None=None
    target_concurrency: int | None=Field(default=None,ge=0,le=16)
    max_concurrency: int | None=Field(default=None,ge=1,le=16)
    daily_token_budget: int | None=Field(default=None,ge=0,le=100000000)

def create_app(settings=None):
    settings=settings or get_settings()
    database=Database(settings.database_url.get_secret_value(),settings.db_pool_max,'firstrole-api')
    operator=Database(settings.operator_database_url.get_secret_value(),2,'firstrole-operator')
    sessions=Sessions(database,settings)
    repo=Repository(database,Encryption(settings),settings)
    @asynccontextmanager
    async def lifespan(app):
        database.open(); operator.open()
        yield
        database.close(); operator.close()
    app=FastAPI(title='Firstrole API',version='1.0.0',lifespan=lifespan,
        docs_url='/api/docs' if settings.app_env=='development' else None,redoc_url=None)
    app.state.db=database; app.state.repo=repo; app.state.settings=settings

    @app.exception_handler(AppError)
    async def app_error(request,error):
        return JSONResponse({'message':error.message,'code':error.code},status_code=error.status)
    @app.exception_handler(RequestValidationError)
    async def validation_error(request,error):
        return JSONResponse({'message':'Check the submitted fields and try again.','code':'validation_error'},status_code=422)
    @app.exception_handler(StarletteHTTPException)
    async def http_error(request,error):
        return JSONResponse({'message':str(error.detail)[:300]},status_code=error.status_code)
    @app.exception_handler(IntegrityError)
    async def conflict(request,error):
        return JSONResponse({'message':'This record changed or conflicts with an earlier request. Reload its status.','code':'record_conflict'},status_code=409)
    @app.exception_handler(DatabaseError)
    @app.exception_handler(PoolTimeout)
    async def unavailable(request,error):
        logger.warning('database_unavailable type=%s',type(error).__name__)
        return JSONResponse({'message':'The database is temporarily unavailable. Your request was not confirmed.','code':'database_unavailable'},status_code=503)

    @app.middleware('http')
    async def boundaries(request,call_next):
        if request.url.path.startswith('/api/'):
            length=request.headers.get('content-length','0')
            if not length.isdigit() or int(length)>settings.max_upload_bytes+65536:
                return JSONResponse({'message':'Request exceeds the upload limit.'},status_code=413)
        response=await call_next(request)
        response.headers['X-Content-Type-Options']='nosniff'
        response.headers['Referrer-Policy']='same-origin'
        response.headers['X-Frame-Options']='DENY'
        if request.url.path.startswith('/api/'):
            response.headers['Cache-Control']='no-store'
        return response

    def visitor(request: Request):
        return sessions.require(request.cookies.get(COOKIE))
    def mutation(request: Request):
        return sessions.validate_mutation(request,request.cookies.get(COOKIE))
    def admin(request: Request):
        token=settings.admin_token.get_secret_value()
        supplied=request.headers.get('authorization','')
        if not token or not hmac.compare_digest(supplied.encode(),('Bearer '+token).encode()):
            raise AppError('Administrator access is required.',403,'admin_required')

    @app.get('/health/live')
    def live(): return {'status':'alive','version':'1.0.0'}
    @app.get('/health/ready')
    def ready(response: Response):
        try: database.ready(); db_ok=True
        except Exception: db_ok=False
        configured=bool(settings.session_signing_key.get_secret_value() and settings.resume_encryption_key.get_secret_value())
        okay=db_ok and configured and settings.coaching_configured
        response.status_code=200 if okay else 503
        return {'ready':okay,'database':db_ok,'private_sessions':configured,'coaching':settings.coaching_configured}

    @app.get('/api/session')
    def session(request: Request,response: Response):
        # Deliberately ignore untrusted forwarded IP headers; configure a trusted
        # reverse proxy before relying on client IPs behind Cloudflare/Render.
        ip=request.client.host if request.client else 'unknown'
        key=opaque_key(settings.session_signing_key.get_secret_value(),'ip',ip)
        repo.rate_limit(key,'session',30,60)
        owner,raw=sessions.establish(request.cookies.get(COOKIE))
        response.set_cookie(COOKIE,raw,max_age=settings.session_days*86400,httponly=True,
            secure=settings.cookie_secure,samesite='lax',path='/')
        return {'csrf_token':csrf_for(raw,settings.session_signing_key.get_secret_value())}

    @app.get('/api/companies')
    def companies(): return repo.companies()
    @app.get('/api/roles')
    def roles(company: str): return repo.roles(company[:100])
    @app.get('/api/analyses')
    def recent(owner=Depends(visitor)): return repo.recent(owner.id)

    @app.post('/api/analyses',status_code=202)
    async def submit(request: Request,owner=Depends(mutation)):
        if not settings.coaching_configured:
            raise AppError('The backend is running, but its n8n coaching workflow is not connected yet.',503,'coaching_unconfigured')
        async with request.form(max_files=1,max_fields=5,max_part_size=8192) as form:
            expected={'resume','request_id','candidate_name','company','role_id','role_title'}
            if set(form.keys())!=expected or any(len(form.getlist(k))!=1 for k in expected):
                raise AppError('Submit exactly one resume and each required field once.',422,'invalid_form')
            fields={k:form[k] for k in expected-{'resume'}}
            if not all(isinstance(v,str) and 1<=len(v)<=200 for v in fields.values()):
                raise AppError('Check your name, company and role.',422)
            try: UUID(fields['request_id'])
            except (ValueError,TypeError): raise AppError('Invalid request identifier.',422) from None
            if not 2<=len(fields['candidate_name'])<=100 or any(ord(x)<32 for x in fields['candidate_name']):
                raise AppError('Enter your full name without control characters.',422)
            if request.headers.get('idempotency-key')!=fields['request_id']:
                raise AppError('The submission key does not match its request.',422)
            file=form['resume']
            if not hasattr(file,'read'): raise AppError('Upload one resume file.',422)
            data=bytearray()
            while chunk:=await file.read(65536):
                data.extend(chunk)
                if len(data)>settings.max_upload_bytes: raise AppError('Resume exceeds 5 MB.',413)
            name,file_type=await run_in_threadpool(inspect_upload,file.filename,bytes(data),settings.max_upload_bytes)
        signing=settings.session_signing_key.get_secret_value()
        await run_in_threadpool(repo.rate_limit,opaque_key(signing,'owner',str(owner.id)),'upload_owner',5,3600)
        await run_in_threadpool(repo.rate_limit,opaque_key(signing,'ip',request.client.host if request.client else 'unknown'),'upload_ip',20,3600)
        return await run_in_threadpool(repo.submit,owner.id,fields,name,file_type,bytes(data))

    @app.get('/api/analyses/{analysis_id}')
    def status(analysis_id: UUID,owner=Depends(visitor)): return repo.status(owner.id,analysis_id)
    @app.post('/api/analyses/{analysis_id}/decision')
    def decide(analysis_id: UUID,body: Decision,request: Request,owner=Depends(mutation)):
        key=request.headers.get('idempotency-key','')
        if not re.fullmatch(r'[a-zA-Z0-9_-]{8,100}',key): raise AppError('A valid decision key is required.',422)
        return repo.decide(owner.id,analysis_id,body.model_dump(),key)

    @app.get('/api/applications/{application_id}/download')
    def download(application_id: UUID,format: Literal['docx','pdf','txt']='docx',owner=Depends(visitor)):
        record=repo.application(owner.id,application_id)
        data,mime=export(record['final_letter'],format)
        return Response(data,media_type=mime,headers={'Content-Disposition':f'attachment; filename="cover-letter-{application_id}.{format}"'})

    @app.get('/api/operations',dependencies=[Depends(admin)])
    def operations():
        with operator.transaction() as c:
            return c.execute('SELECT app.operations_snapshot() value').fetchone()['value']
    @app.patch('/api/operations/settings',dependencies=[Depends(admin)])
    def settings_patch(body: Controls):
        changes=body.model_dump(exclude_none=True)
        if not changes: raise AppError('Provide at least one setting.',422)
        if any(changes.get(k,0)>settings.max_worker_concurrency for k in ('target_concurrency','max_concurrency')):
            raise AppError('Requested concurrency exceeds the configured deployment cap.',422)
        with operator.transaction() as c:
            before=c.execute('SELECT * FROM app.worker_settings WHERE singleton FOR UPDATE').fetchone()
            after={**before,**changes}
            if not 0<=after['min_concurrency']<=after['target_concurrency']<=after['max_concurrency']<=settings.max_worker_concurrency:
                raise AppError('Target concurrency must fit the current minimum and maximum.',422)
            if 'target_concurrency' in changes and 'auto_manage' not in changes:
                changes['auto_manage']=False
            # Column identifiers come only from the closed Pydantic model above.
            assignments=','.join(k+'=%s' for k in changes)
            c.execute('UPDATE app.worker_settings SET '+assignments+',updated_at=now(),last_scaled_at=now() WHERE singleton',tuple(changes.values()))
            return c.execute('SELECT app.operations_snapshot() value').fetchone()['value']

    @app.api_route('/api/{path:path}',methods=['GET','POST','PUT','PATCH','DELETE'])
    def no_api(path: str): missing=AppError('API route not found.',404); raise missing
    app.add_middleware(BodyLimitMiddleware,maximum=settings.max_upload_bytes+65536)
    app.mount('/',StaticFiles(directory=ROOT.parent/'frontend',html=True),name='frontend')
    return app

app=create_app()
