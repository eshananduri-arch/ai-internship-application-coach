"""Opt-in real PostgreSQL HTTP tests. No SQLite, live AI calls or real resumes."""
import os
from uuid import uuid4
import pytest
from fastapi.testclient import TestClient
from psycopg.types.json import Jsonb
from app.config import Settings
from app.main import create_app
from app.security import Sessions,Encryption,COOKIE,digest
from test_backend import LETTER,make_docx

@pytest.mark.integration
@pytest.mark.parametrize('decision',['approve','reject'])
def test_private_decisions_and_downloads(decision):
    settings=Settings()
    if os.environ.get('FIRSTROLE_INTEGRATION')!='1' or not settings.database_url.get_secret_value():
        pytest.skip('Set FIRSTROLE_INTEGRATION=1 and an existing restricted development DATABASE_URL.')
    assert settings.app_env=='development','Integration fixtures are forbidden in production.'
    app=create_app(settings)
    owners=[]
    with TestClient(app) as first,TestClient(app) as second:
        try:
            csrf=first.get('/api/session').json()['csrf_token']
            second.get('/api/session').raise_for_status()
            sessions=Sessions(app.state.db,settings)
            owner=sessions.require(first.cookies.get(COOKIE)).id
            other=sessions.require(second.cookies.get(COOKIE)).id
            owners.extend([owner,other])
            data=make_docx()
            with app.state.db.transaction(owner) as c:
                resume=c.execute('''INSERT INTO app.resumes(visitor_id,file_name,file_type,byte_size,file_sha256,encrypted_original,encryption_key_version)
                    VALUES(%s,'synthetic.docx','docx',%s,%s,%s,%s) RETURNING id''',(owner,len(data),digest(data),Encryption(settings).encrypt(data),settings.encryption_key_version)).fetchone()['id']
                analysis=c.execute('''INSERT INTO app.analyses(visitor_id,resume_id,request_id,company_id,role_id,role_snapshot,candidate_name,status,draft_version,final_letter,approval_allowed)
                    VALUES(%s,%s,%s,'microsoft','MICROSOFT-01',%s,'Test Candidate','ready',1,%s,true) RETURNING id''',
                    (owner,resume,'integration-'+str(uuid4()),Jsonb({'role_id':'MICROSOFT-01','company':'Microsoft','role_title':'Software Engineering Intern'}),LETTER)).fetchone()['id']
            url=f'/api/analyses/{analysis}'
            assert first.get(url).status_code==200
            assert second.get(url).status_code==404
            key=str(uuid4()); body={'decision':decision,'final_letter':LETTER,'draft_version':1}
            headers={'Origin':settings.app_origin,'X-CSRF-Token':csrf,'Idempotency-Key':key}
            assert first.post(url+'/decision',json=body,headers={**headers,'X-CSRF-Token':'bad'}).status_code==403
            assert first.post(url+'/decision',json={**body,'draft_version':2},headers=headers).status_code==409
            response=first.post(url+'/decision',json=body,headers=headers)
            assert response.status_code==200,response.text
            receipt=response.json()
            assert first.post(url+'/decision',json=body,headers=headers).json()==receipt
            assert first.post(url+'/decision',json={**body,'final_letter':LETTER+' Changed.'},headers=headers).status_code==409
            if decision=='approve':
                download=f"/api/applications/{receipt['application_id']}/download?format=txt"
                assert receipt['final_letter']==LETTER
                assert first.get(download).text==LETTER
                assert second.get(download).status_code==404
                assert first.get(download.replace('txt','docx')).content.startswith(b'PK')
                assert first.get(download.replace('txt','pdf')).content.startswith(b'%PDF-')
            else:
                assert receipt=={'status':'rejected'}
                with app.state.db.transaction(owner) as c:
                    assert c.execute('SELECT count(*) total FROM app.applications WHERE analysis_id=%s',(analysis,)).fetchone()['total']==0
        finally:
            if owners:
                with app.state.db.transaction() as c:
                    c.execute('DELETE FROM app.visitors WHERE id=ANY(%s)',(owners,))
