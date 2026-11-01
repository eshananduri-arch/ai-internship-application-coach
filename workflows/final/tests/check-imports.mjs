import {readFileSync,readdirSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {join,dirname} from 'node:path';
import assert from 'node:assert/strict';
const root=join(dirname(fileURLToPath(import.meta.url)),'..');
const files=readdirSync(root).filter(x=>x.endsWith('.json'));assert.equal(files.length,6);
let scripts=0,parser;
for(const file of files){
 const workflow=JSON.parse(readFileSync(join(root,file),'utf8'));assert.equal(workflow.active,false);
 const names=new Set(workflow.nodes.map(x=>x.name));assert.equal(names.size,workflow.nodes.length);
 for(const node of workflow.nodes){
  assert.equal(node.credentials,undefined,'Portable imports must not reference another account credential');
  for(const key of ['jsCode'])if(typeof node.parameters?.[key]==='string'){
   new Function(node.parameters[key]);scripts++;
   if(!parser&&node.parameters[key].includes('function mcpObject(')){
    const code=node.parameters[key];const start=code.indexOf('function mcpObject('),end=code.indexOf('function httpBody(',start);
    parser=new Function("function assert(c,m){if(!c)throw new Error(m)}function fail(m){throw new Error(m)}"+code.slice(start,end)+';return mcpObject;')();
   }
  }
 }
 for(const [source,ports] of Object.entries(workflow.connections)){
  assert(names.has(source));for(const arrays of Object.values(ports))for(const targets of arrays)for(const target of targets)assert(names.has(target.node));
 }
}
const value={ok:true,role_id:'MICROSOFT-01',documents:[{text:'Role ID: MICROSOFT-01'}]};
for(const wrap of [x=>x,x=>[x],x=>JSON.stringify([x]),x=>({content:[{type:'text',text:JSON.stringify([x])}]}),x=>({structuredContent:x}),x=>({response:JSON.stringify(x)}),x=>({type:'text',text:JSON.stringify(x)})])assert.deepEqual(parser(wrap(value)),value);
assert.throws(()=>parser({isError:true,content:[{type:'text',text:'Unavailable'}]}),/mcp_tool_failed/);
assert.throws(()=>parser(JSON.stringify({isError:true})),/mcp_tool_failed/,'Nested errors must keep their real classification');
assert.throws(()=>parser({content:[{type:'text',text:'Not JSON'}]}),/mcp_invalid_json/);
assert.throws(()=>parser([value,value]),/mcp_ambiguous_result/);
assert.throws(()=>parser({content:[{type:'text',text:'{}'},{type:'text',text:'{}'}]}),/mcp_ambiguous_result/);
console.log(`Validated ${files.length} workflow imports, ${scripts} Code scripts and 12 MCP response cases.`);
