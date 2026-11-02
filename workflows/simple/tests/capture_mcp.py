"""Read-only live MCP protocol check. Uses only public educational role data."""
from pathlib import Path
import json,time,sys,httpx
from dotenv import dotenv_values
ROOT=Path(__file__).resolve().parents[1]
REPO=ROOT.parents[1]
cfg=dotenv_values(REPO/'backend/.env.n8n-setup')
url='https://zeeshan1786.app.n8n.cloud/mcp/final-career-tools'
headers={'X-Internship-MCP-Key':cfg['MCP_SHARED_SECRET'],'Accept':'application/json, text/event-stream','MCP-Protocol-Version':'2025-03-26'}
def parse(body):
 try:return json.loads(body)
 except ValueError:return json.loads(next(l[5:] for l in body.splitlines() if l.startswith('data:')))
def fixture(r):return {'statusCode':r.status_code,'headers':{},'body':r.text}
report={};times=[]
with httpx.Client(timeout=25) as c:
 start=time.perf_counter()
 r=c.post(url,headers=headers,json={'jsonrpc':'2.0','id':0,'method':'initialize','params':{'protocolVersion':'2025-03-26','capabilities':{},'clientInfo':{'name':'simple-coach-verification','version':'1'}}})
 r.raise_for_status();assert parse(r.text)['result']['protocolVersion']=='2025-03-26'
 report['initialize']=fixture(r);report['initialize']['headers']={'mcp-session-id':'synthetic-fixture-session'}
 headers['Mcp-Session-Id']=r.headers['mcp-session-id']
 try:
  r=c.post(url,headers=headers,json={'jsonrpc':'2.0','method':'notifications/initialized'});assert r.status_code==202;report['notification']=fixture(r)
  roles={}
  for company in ['AMAZON','MICROSOFT','GOOGLE','NVIDIA','DELOITTE']:
   for number in range(1,4):
    ident=f'{company}-{number:02}';t=time.perf_counter()
    r=c.post(url,headers=headers,json={'jsonrpc':'2.0','id':1,'method':'tools/call','params':{'name':'search_internship_roles','arguments':{'input':ident+' internship requirements','role_id':ident,'catalog_version':1}}})
    r.raise_for_status();response=parse(r.text);assert not response.get('error') and not response['result'].get('isError');payload=json.loads(response['result']['content'][0]['text']);payload=payload[0] if isinstance(payload,list) else payload
    assert payload['ok'] is True and payload['role_id']==ident and payload['source_version']==1
    assert all(d['metadata']['role_id']==ident and d['metadata']['catalog_version']==1 for d in payload['documents'])
    roles[ident]=fixture(r);times.append(round(time.perf_counter()-t,3))
  report['roles']=roles
  for key,args,i in [('days_until',{'input':'2026-12-20'},2),('word_count',{'input':'This is a synthetic test letter.'},3)]:
   r=c.post(url,headers=headers,json={'jsonrpc':'2.0','id':i,'method':'tools/call','params':{'name':key,'arguments':args}});r.raise_for_status();assert not parse(r.text).get('error');report[key]=fixture(r)
 finally:
  r=c.delete(url,headers=headers);report['delete_status']=r.status_code;assert r.status_code in [200,202,204]
 report['transport_test_seconds']=round(time.perf_counter()-start,3)
 report['role_lookup_seconds']=times
(ROOT/'tests/live-mcp-fixture.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print(json.dumps({'live_roles_passed':len(roles),'session_initialized':True,'notification_accepted':True,'deadline_and_count_passed':True,'session_deleted':True,'transport_test_seconds':report['transport_test_seconds'],'gemini_called':False}),flush=True)
