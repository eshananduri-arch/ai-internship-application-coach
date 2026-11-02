// Real n8n expression/data-proxy runtime; live MCP; mocked native Gemini and sanitizer.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'..'),repo=path.resolve(root,'../..');
const modulePath=process.env.N8N_WORKFLOW_MODULE||path.join(repo,'backend/test-artifacts/n8n-runtime/node_modules/n8n-workflow');
const {Workflow,WorkflowDataProxy,createRunExecutionData}=require(modulePath);
const original=JSON.parse(fs.readFileSync(path.join(root,'Final Orchestrator.json')));
const nodeTypes={getByNameAndVersion:(name,version)=>({description:{name,version,properties:[],inputs:['main'],outputs:['main'],defaults:{name}}})};
const workflow=new Workflow({id:'runtime-check',nodes:structuredClone(original.nodes),connections:original.connections,active:false,nodeTypes,settings:original.settings});
const runs=createRunExecutionData({resultData:{runData:{}}});
const allowedUrl='https://zeeshan1786.app.n8n.cloud/mcp/final-career-tools';
const key=process.env.MCP_SHARED_SECRET;assert.ok(key,'MCP key required through environment, never print it');
let expressions=0,gemini=0,session=null;const stages=[];
function execData(node,previous){return {node:workflow.getNode(node.name),data:{},source:previous?{main:[{previousNode:previous,previousNodeOutput:0,previousNodeRun:0}]}:null};}
function evaluate(value,node,input,previous){
 if(typeof value==='string'&&value.startsWith('=')){
  expressions++;return workflow.expression.getParameterValue(value,runs,0,0,node.name,[{json:input}],'integrated',{},execData(node,previous));
 }
 if(Array.isArray(value))return value.map(v=>evaluate(v,node,input,previous));
 if(value&&typeof value==='object')return Object.fromEntries(Object.entries(value).map(([k,v])=>[k,evaluate(v,node,input,previous)]));
 return value;
}
function remember(node,output,previous){runs.resultData.runData[node.name]=[{startTime:Date.now(),executionTime:1,executionStatus:'success',source:previous?[{previousNode:previous,previousNodeOutput:0,previousNodeRun:0}]:[],data:{main:[[{json:output}]]}}];}
function code(node,input,previous){
 const proxy=new WorkflowDataProxy(workflow,runs,0,0,node.name,[{json:input}],'integrated',{},execData(node,previous)).getDataProxy();
 const result=new Function('$json','$input','$',node.parameters.jsCode)(proxy.$json,proxy.$input,proxy.$);
 assert.equal(result.length,1);return JSON.parse(JSON.stringify(result[0].json));
}
async function request(node,input,previous){
 const p=evaluate(node.parameters,node,input,previous);assert.equal(p.url,allowedUrl,'only the owned MCP endpoint may receive its key');
 const headers=Object.fromEntries(p.headerParameters.parameters.map(h=>[h.name,h.value]));headers['X-Internship-MCP-Key']=key;
 let body;
 if(p.sendBody){body=typeof p.jsonBody==='string'?p.jsonBody:JSON.stringify(p.jsonBody);headers['Content-Type']='application/json';JSON.parse(body);}
 const result=await fetch(p.url,{method:p.method,headers,body,redirect:'manual',signal:AbortSignal.timeout(25000)});
 const text=await result.text();const response={statusCode:result.status,headers:Object.fromEntries(result.headers),statusMessage:result.statusText};
 response[p.options.response.response.outputPropertyName||'data']=text;
 if(node.name==='Open MCP Session')session=result.headers.get('mcp-session-id');
 if(node.name==='Close MCP Session'&&result.ok)session=null;
 if(!p.options.response.response.neverError&&!result.ok)throw new Error('mcp_http_'+result.status);
 return response;
}
function provider(node,input,previous){
 const p=evaluate(node.parameters,node,input,previous);
 assert.equal(p.url,'https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash-lite:generateContent');
 assert.equal(p.authentication,'predefinedCredentialType');assert.equal(p.nodeCredentialType,'googlePalmApi');assert.equal(node.retryOnFail,false);
 const request=p.jsonBody,config=request.generationConfig;
 assert.equal(config.candidateCount,1);assert.equal(config.maxOutputTokens,1536);assert.equal(config.responseFormat.text.mimeType,'APPLICATION_JSON');
 assert.equal(config.responseFormat.text.schema.additionalProperties,false);assert.equal(config.responseFormat.text.schema.required.length,6);
 const context=JSON.parse(request.contents[0].parts[0].text);assert.equal(context.role_id,'MICROSOFT-01');assert.ok(!JSON.stringify(context).includes('Test Candidate'));
 const quote='Built a Python library-management project with SQLite and unit tests for borrowing and returns.';assert.ok(input.safe_resume.includes(quote));
 const draft={strengths:['Python and SQL project exposure'],gaps:['No professional software experience demonstrated'],fit:'moderate',evidence:[{claim:'Python project experience',quote}],body:'I am applying for the Software Engineering Intern role at Microsoft. Through my academic project, I built a Python library-management application using SQLite and wrote unit tests for borrowing and returns. My coursework introduced me to Java, SQL, object-oriented programming and data structures.\n\nI also created a FastAPI REST API for study tasks, maintained the code with Git and documented project setup and endpoints for classmates. These activities gave me practical exposure to developing and explaining software. I would welcome the opportunity to contribute these foundations while learning from your team. Thank you for considering my application.',self_review:{passed:true,feedback:[]}};
 gemini++;return {statusCode:200,body:{candidates:[{finishReason:'STOP',content:{parts:[{text:JSON.stringify(draft)}]}}],usageMetadata:{promptTokenCount:200,candidatesTokenCount:300,totalTokenCount:500}}};
}
(async()=>{
 const start=performance.now();await workflow.expression.acquireIsolate();
 let previous=null,node=original.nodes.find(n=>n.name==='Build Explicit Test Request'),input={};
 try{
  for(let step=0;step<50;step++){
   let output,branch=0;
   try{
    if(node.type==='n8n-nodes-base.code')output=code(node,input,previous);
    else if(node.type==='n8n-nodes-base.httpRequest'&&node.parameters.nodeCredentialType==='googlePalmApi')output=provider(node,input,previous);
    else if(node.type==='n8n-nodes-base.httpRequest')output=await request(node,input,previous);
    else if(node.type==='@n8n/n8n-nodes-langchain.guardrails')output={guardrailsInput:input.resume_text};
    else if(node.type==='@n8n/n8n-nodes-langchain.googleGemini')output=provider(node,input,previous);
    else if(node.type==='n8n-nodes-base.respondToWebhook'){
     const p=evaluate(node.parameters,node,input,previous);assert.equal(p.options.responseCode,200,JSON.stringify(p.responseBody));assert.equal(gemini,1);
     const directory=path.join(repo,'backend/test-artifacts/runtime-verified');fs.mkdirSync(directory,{recursive:true});fs.writeFileSync(path.join(directory,'response.json'),JSON.stringify(p.responseBody,null,2));
     assert.equal(stages.find(x=>x.node==='Close MCP Session')?.http_status,200,'session cleanup must complete with the finalizer/error branches present');
     assert.ok(stages.every(x=>!x.error),'no stage error allowed on the success path');
     const baseline=JSON.parse(fs.readFileSync(path.join(root,'tests/expression-regressions.json')));
     const search=original.nodes.find(n=>n.name==='Search Selected Role');
     assert.throws(()=>evaluate(baseline['Search Selected Role'].jsonBody,search,{statusCode:202},'Mark MCP Ready'),/invalid syntax/);
     const report={n8n_workflow_version:require(path.join(modulePath,'package.json')).version,expressions_evaluated:expressions,original_search_failure_reproduced:true,corrected_request_passed:true,live_mcp_session_and_tools_passed:true,live_mcp_word_count:p.responseBody.tool_evidence.find(x=>x.tool==='word_count').word_count,gemini_response_mocked:true,sanitizer_node_mocked:true,real_model_calls:0,gemini_nodes_simulated:gemini,transport_and_runtime_test_seconds:Math.round(performance.now()-start)/1000,stages};
     fs.writeFileSync(path.join(directory,'report.json'),JSON.stringify(report,null,2));console.log(JSON.stringify(report,null,2));return;
    } else throw new Error('Unexpected node '+node.type);
   }catch(e){
    if(node.onError==='continueErrorOutput'){output={...input,error:e.message};branch=1;}
    else if(node.onError==='continueRegularOutput')output={...input,error:e.message};
    else throw e;
   }
   remember(node,output,previous);stages.push({node:node.name,http_status:output.statusCode||null,error:output.error?String(output.error).slice(0,100):null});
   const next=original.connections[node.name]?.main?.[branch]?.[0]?.node;assert.ok(next,'Missing route from '+node.name);previous=node.name;input=output;node=original.nodes.find(n=>n.name===next);
  }
  throw new Error('Unexpected workflow loop');
 }finally{
  if(session){await fetch(allowedUrl,{method:'DELETE',headers:{'X-Internship-MCP-Key':key,'Mcp-Session-Id':session,'Accept':'application/json, text/event-stream'},signal:AbortSignal.timeout(10000)}).catch(()=>{});}
  await workflow.expression.releaseIsolate();
 }
})().catch(e=>{console.error(e.name+': '+e.message);process.exitCode=1;});
