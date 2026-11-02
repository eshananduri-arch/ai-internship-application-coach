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
