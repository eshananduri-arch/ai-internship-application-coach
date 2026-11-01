import hashlib
import io
import json
import zipfile
from uuid import uuid4
import httpx
import pytest
from cryptography.fernet import Fernet
from docx import Document
from docx.enum.text import WD_ALIGN_PARAGRAPH
from fastapi.testclient import TestClient
from pypdf import PdfReader
from pydantic import SecretStr
from app.config import Settings
from app.coaching import Coach,validate_letter
from app.documents import inspect_upload,extract_text,safe_filename
from app.errors import AppError,PipelineError
from app.exports import export
from app.main import create_app
from app.security import Encryption,csrf_for,digest,Sessions

LETTER='Dear Hiring Team,\n\nI am applying for the simulated software engineering internship. My Python project involved implementing data structures, writing automated tests and documenting the results. I would welcome the opportunity to contribute these skills while learning from your team.\n\nSincerely,\nTest Candidate'
RESUME='Test Candidate\nPython student with a project implementing data structures and writing automated tests. Experience documenting results and reviewing code.'

@pytest.fixture
def settings():
    return Settings(_env_file=None,session_signing_key=SecretStr('s'*48),resume_encryption_key=SecretStr(Fernet.generate_key().decode()),
        admin_token=SecretStr('admin-test-token'),n8n_webhook_url='http://127.0.0.1:9999/webhook',n8n_webhook_token=SecretStr('test-secret'))

def make_docx(text=RESUME):
    doc=Document(); doc.add_paragraph(text); stream=io.BytesIO(); doc.save(stream); return stream.getvalue()

def test_current_upload_docx_extraction():
    one=make_docx(); two=make_docx(RESUME.replace('Python','Kotlin'))
    assert inspect_upload('resume.docx',one)==('resume.docx','docx')
    assert 'Python' in extract_text(one,'docx')
    assert 'Kotlin' in extract_text(two,'docx')
    assert extract_text(one,'docx')!=extract_text(two,'docx')

@pytest.mark.parametrize('name,data',[('resume.pdf',b'bad'),('resume.docx',b'%PDF-1.4'),('resume.exe',b'PK\x03\x04'),('resume.docx',b'PK\x03\x04bad'),('resume.pdf',b'')])
def test_reject_mislabeled_or_invalid_uploads(name,data):
    with pytest.raises(AppError): inspect_upload(name,data)

def test_archive_bomb_and_traversal():
    for member,content in [('../word/document.xml',b'bad'),('word/document.xml',b'A'*(21*1024*1024))]:
        stream=io.BytesIO()
        with zipfile.ZipFile(stream,'w',zipfile.ZIP_DEFLATED) as z:
            z.writestr('[Content_Types].xml','<Types/>'); z.writestr(member,content)
        with pytest.raises(AppError): inspect_upload('resume.docx',stream.getvalue())

def test_docx_dtd_rejected():
    stream=io.BytesIO()
    with zipfile.ZipFile(stream,'w') as z:
        z.writestr('[Content_Types].xml','<Types/>')
        z.writestr('word/document.xml','<!DOCTYPE a [<!ENTITY x "bad">]><a>&x;</a>')
    with pytest.raises(AppError): inspect_upload('resume.docx',stream.getvalue())

def test_limits_and_names():
    with pytest.raises(AppError): inspect_upload('a.pdf',b'%PDF-'+b'x'*5242880)
    assert safe_filename('C:\\uploads\\resume.docx')=='resume.docx'
    assert safe_filename('../../resume\x00.docx')=='resume.docx'

def test_authenticated_encryption(settings):
    cipher=Encryption(settings); plain=RESUME.encode()
    first=cipher.encrypt(plain); second=cipher.encrypt(plain)
    assert first!=second and plain not in first and cipher.decrypt(first)==plain
    damaged=bytearray(first); damaged[-1]^=1
    with pytest.raises(AppError): cipher.decrypt(damaged)
    assert len(cipher.encrypt(b'x'*5242880))<=6291456

def test_csrf_bound_to_cookie_and_key():
    assert csrf_for('a','key')!=csrf_for('b','key')
    assert csrf_for('a','key')!=csrf_for('a','other')
    assert digest('secret')==hashlib.sha256(b'secret').hexdigest()

@pytest.mark.parametrize('text',[LETTER+' [your email]', 'Too short',LETTER+'\n'+'word '*260,LETTER.replace('Sincerely','Thanks')])
def test_letter_checks(text):
    with pytest.raises(AppError): validate_letter(text,'Test Candidate')

def result(analysis):
    return {'analysis_id':str(analysis['id']),'role_id':analysis['role_id'],'final_letter':LETTER,
        'match_report':{'strengths':['Python project']},'critic_review':{'approved':True,'feedback':[]},'deadline_info':{'expired':False},
        'tool_evidence':[{'tool':'search_internship_roles','role_id':analysis['role_id'],'source_version':1},
            {'tool':'days_until','role_id':analysis['role_id']},
            {'tool':'word_count','letter_sha256':digest(LETTER),'word_count':len(LETTER.split())}],
        'usage':{'input_tokens':100,'output_tokens':100,'model':'test-only'}}

def analysis():
    return {'id':uuid4(),'request_id':str(uuid4()),'role_id':'MICROSOFT-01','candidate_name':'Test Candidate',
        'role_snapshot':{'company':'Microsoft','catalog_version':1}}

def test_coach_current_resume_and_contract(settings):
    a=analysis(); captured={}
    def respond(request):
        captured.update(json.loads(request.content))
        assert request.headers['authorization']=='Bearer test-secret'
        return httpx.Response(200,json=result(a))
    actual=Coach(settings,httpx.MockTransport(respond)).generate(a,RESUME,1)
    assert actual['final_letter']==LETTER and captured['resume_text']==RESUME
    assert captured['role_id']==a['role_id'] and captured['candidate_name']=='Test Candidate'

@pytest.mark.parametrize('problem',['role','search','count','json','usage','critic'])
def test_pipeline_rejects_bad_results(settings,problem):
    a=analysis(); data=result(a)
    if problem=='role': data['role_id']='GOOGLE-01'
    if problem=='search': data['tool_evidence']=data['tool_evidence'][1:]
    if problem=='count': data['tool_evidence'][-1]['letter_sha256']='wrong'
    if problem=='usage': data['usage']={}
    if problem=='critic': data['critic_review']['approved']=False
    def respond(request):
        return httpx.Response(200,content=b'{"truncated":' if problem=='json' else json.dumps(data).encode())
    with pytest.raises(PipelineError) as error:
        Coach(settings,httpx.MockTransport(respond)).generate(a,RESUME,1)
    assert error.value.uncertain

def test_rate_limit_safe_retry(settings):
    coach=Coach(settings,httpx.MockTransport(lambda _:httpx.Response(429,headers={'Retry-After':'12'})))
    with pytest.raises(PipelineError) as error: coach.generate(analysis(),RESUME,1)
    assert error.value.retryable and error.value.retry_after==12

def test_timeouts_not_blindly_retried(settings):
    def timeout(request): raise httpx.ReadTimeout('test')
    with pytest.raises(PipelineError) as error: Coach(settings,httpx.MockTransport(timeout)).generate(analysis(),RESUME,1)
    assert not error.value.retryable and error.value.uncertain

def test_genuine_exports_and_exact_text():
    txt,mime=export(LETTER,'txt'); assert txt.decode()==LETTER
    docx,mime=export(LETTER,'docx')
    doc=Document(io.BytesIO(docx))
    assert '\n\n'.join(p.text for p in doc.paragraphs)==LETTER
    assert doc.paragraphs[0].alignment==WD_ALIGN_PARAGRAPH.LEFT
    assert doc.paragraphs[1].alignment==WD_ALIGN_PARAGRAPH.JUSTIFY
    assert doc.paragraphs[-1].alignment==WD_ALIGN_PARAGRAPH.LEFT
    pdf,mime=export(LETTER,'pdf'); assert pdf.startswith(b'%PDF-')
    text=' '.join(p.extract_text() for p in PdfReader(io.BytesIO(pdf)).pages)
    assert ' '.join(LETTER.split())==' '.join(text.split())
    assert inspect_upload('letter.pdf',pdf)[1]=='pdf'
    assert 'Test Candidate' in extract_text(pdf,'pdf')

def test_live_health_without_fake_database(settings):
    with TestClient(create_app(settings)) as client:
        assert client.get('/health/live').status_code==200
        ready=client.get('/health/ready')
        assert ready.status_code==503 and ready.json()['database'] is False
        assert client.get('/').status_code==200
        assert client.get('/api/session').status_code==503
        assert client.get('/api/operations').status_code==403
        assert client.get('/api/analyses/'+str(uuid4())).status_code==401
        assert client.post('/api/analyses',headers={'Content-Length':str(8*1024*1024)}).status_code==413

def test_chunked_body_limit(settings):
    with TestClient(create_app(settings)) as client:
        r=client.post('/api/analyses/'+str(uuid4())+'/decision',content=iter([b'x'*1024]*6000),headers={'Content-Type':'application/json'})
        assert r.status_code==413


@pytest.mark.parametrize('code,expected', [('model_unsupported_evidence','model_unsupported_evidence'),('untrusted_provider_message','coaching_unavailable')])
def test_remote_failures_keep_only_known_codes(settings,code,expected):
    coach=Coach(settings,httpx.MockTransport(lambda _:httpx.Response(502,json={'status':'failed','error_code':code,'message':'Private provider payload must not become a diagnostic.'})))
    with pytest.raises(PipelineError) as failure:
        coach.generate(analysis(),RESUME,1)
    assert failure.value.code==expected and failure.value.uncertain and not failure.value.retryable

def test_missing_database_ca_fails_before_connection(tmp_path):
    with pytest.raises(ValueError,match='DB_SSLROOTCERT'):
        Settings(_env_file=None,db_sslrootcert=tmp_path/'missing.crt')
