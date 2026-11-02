"""Single-call website adapter based on the earlier working coaching design."""
from pathlib import Path
import copy,json,uuid
ROOT=Path(__file__).resolve().parent
base=json.loads((ROOT.parent/'fast/Fast Orchestrator.json').read_text(encoding='utf-8'))
by={n['name']:n for n in base['nodes']}
def uid(name):return str(uuid.uuid5(uuid.NAMESPACE_URL,'firstrole-simple:'+name))
wire=r"""
// Parse the actual HTTP JSON-RPC/SSE protocol, not an MCP client's private wrapper.
function rpc(response,id) {
 assert(response&&!response.error,'mcp_tool_failed');
 assert(Number.isInteger(response.statusCode),'mcp_response_missing_status');
 if(response.statusCode!==200)fail('mcp_http_'+response.statusCode);
 const body=response.body??response.data;let frames=[];
 if(body&&typeof body==='object')frames=[body];
 else {
  assert(typeof body==='string'&&body.length<=200000,'mcp_invalid_envelope');
  try {frames=[JSON.parse(body)];} catch {
   const events=body.replace(/\r\n?/g,'\n').split(/\n\s*\n/);
   for(const event of events){
    const data=event.split('\n').filter(l=>l.startsWith('data:')).map(l=>l.slice(5).trimStart()).join('\n');
    if(!data)continue;let frame;try{frame=JSON.parse(data);}catch{fail('mcp_invalid_json');}frames.push(frame);
   }
  }
 }
 const found=frames.filter(x=>x&&x.jsonrpc==='2.0'&&x.id===id);
 assert(found.length===1,'mcp_invalid_envelope');
 const r=found[0];assert(!r.error&&r.result&&typeof r.result==='object','mcp_tool_failed');return r.result;
}
function mcpTool(response,id) {
 const r=rpc(response,id);assert(!r.isError,'mcp_tool_failed');
 assert(Array.isArray(r.content)&&r.content.length===1&&r.content[0]?.type==='text','mcp_invalid_envelope');
 let payload=r.content[0].text;
 if(typeof payload==='string'){try{payload=JSON.parse(payload);}catch{fail('mcp_invalid_json');}}
 if(Array.isArray(payload)){assert(payload.length===1,'mcp_ambiguous_result');payload=payload[0];}
 assert(payload&&typeof payload==='object'&&!payload.error&&!payload.isError&&typeof payload.ok==='boolean','mcp_invalid_envelope');
 return payload;
}
"""
common=by['Validate and Protect Input']['parameters']['jsCode'].rsplit('\ntry {',1)[0]
a=common.index('function mcpObject(');b=common.index('function httpBody(',a);common=common[:a]+wire+common[b:]
def inner(name):return by[name]['parameters']['jsCode'].rsplit('\ntry {',1)[1].rsplit('} catch (e)',1)[0].strip()
def code(name,body):
 return {'id':uid(name),'name':name,'type':'n8n-nodes-base.code','typeVersion':2,'position':[0,0],
  'parameters':{'jsCode':common+'\n'+body},'onError':'continueErrorOutput'}
def clone(name):
 n=copy.deepcopy(by[name]);n['id']=uid(name);n.pop('credentials',None);n['position']=[0,0];return n
nodes=[];edges={}
def link(a,b,output=0):
 ports=edges.setdefault(a,{'main':[]})['main']
 while len(ports)<=output:ports.append([])
 ports[output].append({'node':b,'type':'main','index':0})
def add(n,error=True):
 i=len(nodes);row=i//6;col=i%6;n['position']=[220+col*280 if row%2==0 else 1620-col*280,220+row*300]
 if nodes:link(nodes[-1]['name'],n['name'])
 if error:
  n['onError']='continueErrorOutput';link(n['name'],'Finalize Response',1)
 nodes.append(n)
def http(name,body,session=True):
 headers=[{'name':'Accept','value':'application/json, text/event-stream'}, {'name':'MCP-Protocol-Version','value':'2025-03-26'}]
 if session:headers.append({'name':'Mcp-Session-Id','value':"={{ $('Validate MCP Session').first().json.session_id }}"})
 return {'id':uid(name),'name':name,'type':'n8n-nodes-base.httpRequest','typeVersion':4.2,'position':[0,0],
  'parameters':{'method':'POST','url':"={{ $('Workflow Settings').first().json.mcp_url }}",
   'authentication':'genericCredentialType','genericAuthType':'httpHeaderAuth','sendHeaders':True,'headerParameters':{'parameters':headers},
   'sendBody':True,'specifyBody':'json','jsonBody':body if isinstance(body,str) else json.dumps(body),
   'options':{'timeout':20000,'redirect':{'redirect':{'followRedirects':False}},'response':{'response':{'responseFormat':'text','outputPropertyName':'body','fullResponse':True,'neverError':True}}}}}
trigger=clone('Receive Coach Request');trigger['parameters']['path']='final-internship-coach';trigger['webhookId']=uid('final-internship-coach');add(trigger,False)
add(clone('Workflow Settings'))
add(code('Validate and Protect Input',inner('Validate and Protect Input')))
add(clone('Sanitize Resume'))
safe=inner('Use Sanitized Resume')
add(code('Use Sanitized Resume',"const context=(()=>{\n"+safe+"\n})()[0].json;\n"+r"""
context.search_rpc={jsonrpc:'2.0',id:1,method:'tools/call',params:{name:'search_internship_roles',arguments:{input:context.search_query,role_id:context.role_id,catalog_version:context.catalog_version}}};
return one(context);
"""))
add(http('Open MCP Session',{'jsonrpc':'2.0','id':0,'method':'initialize','params':{'protocolVersion':'2025-03-26','capabilities':{},'clientInfo':{'name':'Firstrole Simple Coach','version':'1'}}},False))
add(code('Validate MCP Session',r"""
const result=rpc($json,0);assert(result.protocolVersion==='2025-03-26','mcp_invalid_envelope');
const headers=Object.fromEntries(Object.entries($json.headers||{}).map(([k,v])=>[k.toLowerCase(),v]));
const session_id=headers['mcp-session-id'];
assert(typeof session_id==='string'&&/^[\x21-\x7e]{1,256}$/.test(session_id),'mcp_invalid_envelope');
return one({session_id});
"""))
add(http('Mark MCP Ready',{'jsonrpc':'2.0','method':'notifications/initialized'}))
nodes[-1]['parameters']['options']['response']['response']['neverError']=False
add(http('Search Selected Role',"={{ $('Use Sanitized Resume').first().json.search_rpc }}"))
role_check=inner('Validate Role Evidence').replace('mcpObject($json)','mcpTool($json,1)')
add(code('Validate Role Evidence',"const context=(()=>{\n"+role_check+"\n})()[0].json;\n"+r"""
context.deadline_rpc={jsonrpc:'2.0',id:2,method:'tools/call',params:{name:'days_until',arguments:{input:context.deadline}}};
return one(context);
"""))
add(http('Check Deadline',"={{ $json.deadline_rpc }}"))
deadline=inner('Validate Deadline').replace('mcpObject($json)','mcpTool($json,2)')
prepare=inner('Prepare One Call').replace('const s=$json;','const s=prepared;').replace('},schema,1000)', '},schema,1536)')
# Keep the earlier complete matching/writing/self-check in one response.
prepare=prepare.replace('You are an internship coach using ONE model call.','You are an internship application coach. Do the entire comparison, letter writing and self-check in ONE response. Do not describe a plan or ask questions. Preserve qualifiers such as concepts, coursework and project exposure. Do not infer skill proficiency from a certificate title or a related skill.')
prompt_build='const prepared=(()=>{\n'+deadline+'\n})()[0].json;\n'+prepare
add(code('Prepare One Call',"const context=(()=>{\n"+prompt_build+"\n})()[0].json;\n"+r"""
// Send the schema to Gemini itself; JSON-only prompting does not constrain fields.
const schema=JSON.parse(JSON.stringify(context.model_request.generationConfig.responseSchema));
function toJsonSchema(value) {
 if(Array.isArray(value))return value.map(toJsonSchema);
 if(value&&typeof value==='object'){
  const out={};for(const [key,child] of Object.entries(value))out[key]=key==='type'?child.toLowerCase():toJsonSchema(child);
  if(out.type==='object')out.additionalProperties=false;
  return out;
 }
 return value;
}
const strict=toJsonSchema(schema);
Object.assign(strict.properties.strengths,{minItems:1,maxItems:2,description:'One or two brief strengths supported by the current resume.'});
Object.assign(strict.properties.gaps,{minItems:0,maxItems:3,description:'Up to three honest gaps against the selected role.'});
Object.assign(strict.properties.evidence,{minItems:1,maxItems:2});
strict.properties.evidence.items.properties.quote.description='A short contiguous verbatim quote from resume_evidence; whitespace normalization only.';
strict.properties.body.description='Professional 100-140 word cover-letter body, in 2-3 paragraphs, mentioning the exact selected company and role title. No greeting, signature or placeholders.';
Object.assign(strict.properties.self_review.properties.feedback,{minItems:0,maxItems:2});
context.model_request.generationConfig={candidateCount:1,maxOutputTokens:1536,responseFormat:{text:{mimeType:'APPLICATION_JSON',schema:strict}}};
return one(context);
"""))

gemini=clone('Gemini One Call')
gemini['name']='Gemini One Call - Structured JSON';gemini['id']=uid(gemini['name'])
gemini['typeVersion']=4.2;gemini['retryOnFail']=False
# One POST, the existing Google credential, no retries, no tools or fallback models.
gemini['parameters']['url']='https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash-lite:generateContent'
gemini['parameters']['jsonBody']='={{ $json.model_request }}'
gemini['parameters']['options']['timeout']=25000
gemini['notes']='One real Gemini 3.5 Flash-Lite generation call. Sends the required JSON schema in generationConfig.responseFormat.text.schema. Select the existing Google Gemini(PaLM) API credential. HTTP Request is used because the native Message a Model operation omits the response schema.'
gemini['notesInFlow']=True
add(gemini)
# Keep real provider HTTP status and usageMetadata; never estimate token usage.
review=inner('Validate One Call')
add(code('Validate One Call',"const context=(()=>{\n"+review+"\n})()[0].json;\n"+r"""
context.count_rpc={jsonrpc:'2.0',id:3,method:'tools/call',params:{name:'word_count',arguments:{input:context.final_letter}}};
return one(context);
"""))
add(http('Count Exact Final Letter',"={{ $json.count_rpc }}"))
add(code('Build Backend Response',inner('Build Backend Response').replace('mcpObject($json)','mcpTool($json,3)')))
# One shared finalizer preserves a verified result or a redacted failure before cleanup.
finalize=code('Finalize Response',r"""
const incoming=$json;
const success=!incoming.error&&typeof incoming.analysis_id==='string'&&typeof incoming.final_letter==='string'&&Array.isArray(incoming.tool_evidence)&&incoming.tool_evidence.length===3;
if(success)return [{json:{http_status:200,body:incoming}}];
const raw=typeof incoming.error==='string'?incoming.error:(incoming.error?.message||incoming.message||'');
const cleaned=raw.replace(/\s*\[line \d+\]\s*$/,'');
const allowed=/^(invalid_|missing_|blocked_|role_|source_|provider_|model_|usage_|critic_|letter_|mcp_|configuration_)[a-z0-9_]+$/;
const error_code=allowed.test(cleaned)?cleaned:'workflow_stage_failed';
const http_status=error_code==='provider_throttled'?429:/^(invalid_|blocked_|role_expired|role_not_found)/.test(error_code)?422:503;
const mcp_status={};
for(const name of ['Open MCP Session','Mark MCP Ready','Search Selected Role','Check Deadline','Count Exact Final Letter']){
 try {
  const value=$(name).first().json;
  mcp_status[name]={http_status:Number.isInteger(value.statusCode)?value.statusCode:null,body_type:typeof value.body,data_type:typeof value.data,error_present:Boolean(value.error)};
 } catch {mcp_status[name]={executed:false};}
}
return [{json:{http_status,body:{status:'failed',error_code,message:'The coaching request could not complete. No application was approved or saved.',mcp_status}}}];

""")
add(finalize,False);finalize.pop('onError',None)
close=http('Close MCP Session',{})
close['parameters']['method']='DELETE'
for key in ['sendBody','specifyBody','jsonBody']:close['parameters'].pop(key,None)
for header in close['parameters']['headerParameters']['parameters']:
 if header['name']=='Mcp-Session-Id':header['value']="={{ $('Validate MCP Session').first().json.session_id }}"
add(close,False)
close['onError']='continueRegularOutput' # Cleanup failure must not discard the finalized response.
response=clone('Return Career Review')
response['parameters']['responseBody']="={{ $('Finalize Response').first().json.body }}"
response['parameters']['options']['responseCode']="={{ $('Finalize Response').first().json.http_status }}"
add(response,False)
# No private payloads, resumes or letters retained in execution history.
# Explicit manual-only sample entry. Webhook requests never receive fallback sample data.
manual={'id':uid('Test With Sample Resume'),'name':'Test With Sample Resume','type':'n8n-nodes-base.manualTrigger','typeVersion':1,'position':[220,-180],'parameters':{}}
sample=code('Build Explicit Test Request',r"""
const id='manual-'+Date.now();
const parts=Object.fromEntries(new Intl.DateTimeFormat('en-US',{timeZone:'Asia/Kolkata',year:'numeric',month:'2-digit',day:'2-digit'}).formatToParts(new Date()).map(p=>[p.type,p.value]));
const role={company:'Microsoft',role_id:'MICROSOFT-01',role_title:'Software Engineering Intern',required_skills:['C++ or C# or Java or Python','DSA','OOP','SQL','software fundamentals'],preferred_skills:['Azure','GitHub','REST APIs','unit testing','CI/CD'],deadline:'2026-12-20',catalog_version:1};
return [{json:{headers:{'idempotency-key':id},body:{analysis_id:id,request_id:id,attempt_id:id+':1',company:role.company,role_id:role.role_id,role,candidate_name:'Test Candidate',resume_text:'Test Candidate\nB.Tech Computer Science student. Built a Python library-management project with SQLite and unit tests for borrowing and returns. Created a FastAPI REST API for study tasks and maintained the code with Git. Coursework includes Java, SQL, object-oriented programming and data structures. Documented project setup and API endpoints for classmates.',today:`${parts.year}-${parts.month}-${parts.day}`,max_words:250,token_budget:12000}}}];
""")
sample['position']=[500,-180];nodes.extend([manual,sample]);link(manual['name'],sample['name']);link(sample['name'],'Workflow Settings');link(sample['name'],'Finalize Response',1)
settings=copy.deepcopy(base['settings']);settings['executionTimeout']=120
w={'name':'Final Orchestrator','nodes':nodes,'connections':edges,'settings':settings,'active':False,'pinData':{}}
# Error routes share a finalizer: n8n may infer its ancestors' error output as branch 1.
# Always read the known main output/run explicitly for this single-item, single-run flow.
def explicit_output(value):
 if isinstance(value,str):return value.replace('.first()', '.first(0, 0)')
 if isinstance(value,list):return [explicit_output(v) for v in value]
 if isinstance(value,dict):return {k:explicit_output(v) for k,v in value.items()}
 return value
for n in w['nodes']:n['parameters']=explicit_output(n['parameters'])
(ROOT/'Final Orchestrator.json').write_text(json.dumps(w,indent=2,ensure_ascii=False),encoding='utf-8')
(ROOT/'mcp-http.js').write_text(wire.strip()+'\n',encoding='utf-8')
print('Built Final Orchestrator:',len(nodes),'nodes; one schema-constrained Gemini request; one shared MCP session; isolated manual test; existing backend path.')
