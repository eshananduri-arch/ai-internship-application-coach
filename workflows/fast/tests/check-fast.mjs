import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const orchestration=JSON.parse(fs.readFileSync(path.join(root,'Fast Orchestrator.json')));
const search=JSON.parse(fs.readFileSync(path.join(root,'Fast Role Search.json')));
let checks=0;function check(value,label){assert.ok(value,label);checks++;}
for(const workflow of [orchestration,search]){
 const names=new Set(workflow.nodes.map(n=>n.name));check(names.size===workflow.nodes.length,'unique node names');
 check(workflow.active===false,'inactive imports');
 for(const node of workflow.nodes){
  check(!node.credentials,'no credential binding');
  for(const [key,value] of Object.entries(node.parameters)){
   if(key==='jsCode')new Function('$json','$input','$',value);
   if(typeof value==='string')for(const match of value.matchAll(/(?:first|\$)\(['"]([^'"]+)['"]\)/g))check(names.has(match[1]),'referenced node exists: '+match[1]);
  }
 }
 for(const [source,ports] of Object.entries(workflow.connections)){
  check(names.has(source),'source node exists');for(const arrays of Object.values(ports))for(const array of arrays)for(const target of array)check(names.has(target.node),'destination node exists');
 }
}
check(orchestration.nodes.filter(n=>n.type==='n8n-nodes-base.httpRequest').length===1,'exactly one model HTTP call');
check(search.nodes.every(n=>n.type!=='n8n-nodes-base.httpRequest'),'no embedding API request');
check(search.nodes.filter(n=>n.type==='n8n-nodes-base.postgres').length===1,'one role database lookup');
check(orchestration.nodes.filter(n=>n.type.endsWith('.mcpClient')).length===3,'real search/date/count MCP steps retained');
check(orchestration.nodes.find(n=>n.type==='n8n-nodes-base.webhook').parameters.path==='fast-internship-coach','separate production path');
function run(workflow,name,input,state={}){
 const code=workflow.nodes.find(n=>n.name===name).parameters.jsCode;
 return new Function('$json','$input','$',code)(input,{all:()=>[{json:input}]},name=>({first:()=>({json:state[name]}),all:()=>[{json:state[name]}]}))[0].json;
}
check(search.nodes.some(n=>n.type==='n8n-nodes-base.manualTrigger'),'manual test trigger available');
check(search.connections['Receive Search'].main[0][0].node==='Validate Search','production input stays direct and strict');
check(search.connections['Test Search Manually'].main[0][0].node==='Manual Test Input','manual samples isolated from production');
check(search.connections['Manual Test Input'].main[0][0].node==='Validate Search','manual case uses real validation');
const manual=run(search,'Manual Test Input',{});
check(run(search,'Validate Search',manual).role_id==='MICROSOFT-01','Execute manual path has valid explicit input');
assert.throws(()=>run(search,'Validate Search',{input:null,role_id:null,catalog_version:null}),/invalid_role_id/,'empty MCP requests must not inherit test data');
const current={role_id:'MICROSOFT-01',catalog_version:1,input:'Software engineering internship'};
check(run(search,'Validate Search',current).role_id===current.role_id,'valid role input');
for(const bad of [{...current,role_id:"MICROSOFT-01' OR 1=1 --"},{...current,catalog_version:0},{...current,input:'x'}])assert.throws(()=>run(search,'Validate Search',bad));
const safe='My Python\nand SQL project included tests and Git version control.';
const state={analysis_id:'synthetic-fast-test',role_id:current.role_id,company:'Microsoft',candidate_name:'Test Candidate',
 role:{role_title:'Software Engineering Intern',required_skills:['Python','SQL'],preferred_skills:['Git']},
 safe_resume:safe,role_context:'Role ID: MICROSOFT-01',sources:[{title:'Microsoft roles',version:1,document_key:'microsoft_internships'}],
 resume_excerpted:false,usage:{input_tokens:0,output_tokens:0,model:'gemini-3.5-flash-lite'},deadline_info:{expired:false},
 tool_evidence:[{tool:'search_internship_roles',role_id:current.role_id,source_version:1},{tool:'days_until',role_id:current.role_id}]};
const request=run(orchestration,'Prepare One Call',state);
check(request.model_request.generationConfig.maxOutputTokens===1000,'bounded generation');
check(!('thinkingBudget' in request.model_request.generationConfig),'uses supported model defaults');
check(!JSON.stringify(request.model_request).includes('Test Candidate'),'signature name not sent to model');
const model={strengths:['Python and SQL project exposure'],gaps:[],fit:'moderate',evidence:[{claim:'Project experience using Python and SQL',quote:'Python and SQL project included tests'}],
 body:'I am applying for the Software Engineering Intern role at Microsoft. My academic project used Python and SQL, and I wrote tests while managing the code with Git. This work helped me practice building and checking software. I would welcome the opportunity to contribute these foundations to your team and continue learning from experienced engineers.',self_review:{passed:true,feedback:[]}};
const provider=value=>({statusCode:200,body:{candidates:[{finishReason:'STOP',content:{parts:[{text:JSON.stringify(value)}]}}],usageMetadata:{promptTokenCount:100,candidatesTokenCount:150,totalTokenCount:250}}});
const states={'Prepare One Call':request};
const result=run(orchestration,'Validate One Call',provider(model),states);
check(!result.failed,'valid output accepted with whitespace-normalized evidence');
check(result.critic_review.independent_reviewer===false,'self-review explicitly labelled');
check(result.usage.model_invocations===1,'one-call usage recorded');
const checksum=createHash('sha256').update(result.final_letter).digest('hex');const count={ok:true,within_limit:true,word_count:result.final_letter.split(/\s+/u).length,text_sha256:checksum};
const response=run(orchestration,'Build Backend Response',{content:[{type:'text',text:JSON.stringify([count])}]},{'Validate One Call':result});
check(!response.failed&&response.final_letter===result.final_letter,'actual count/hash envelope validates');
check(run(orchestration,'Build Backend Response',{...count,text_sha256:'0'.repeat(64)},{'Validate One Call':result}).failed,'wrong final-letter hash blocked');
for(const [change,expected] of [
 [m=>m.evidence[0].quote='Invented professional Kubernetes deployment','model_unsupported_evidence'],
 [m=>m.self_review.passed=false,'critic_requires_changes'],
 [m=>m.body+=' [your email]','letter_placeholders'],
 [m=>m.body='word '.repeat(251),'letter_invalid_length'],
 [m=>m.body=m.body.replaceAll('Microsoft','Google'),'letter_missing_role']]){
 const value=structuredClone(model);change(value);const failure=run(orchestration,'Validate One Call',provider(value),states);
 check(failure.failed&&failure.body.error_code===expected,'invalid draft rejected: '+expected);
}
const truncated=provider(model);truncated.body.candidates[0].finishReason='MAX_TOKENS';check(run(orchestration,'Validate One Call',truncated,states).body.error_code==='model_incomplete_output','truncated response blocked');
const directory=process.env.FAST_TEST_ARTIFACTS;
if(directory){fs.mkdirSync(directory,{recursive:true});fs.writeFileSync(path.join(directory,'fast-response.json'),JSON.stringify(response,null,2));}
console.log(`Fast workflow checks passed: ${checks}. One model call; no query embedding; real MCP evidence required.`);
