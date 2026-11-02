// Supports raw MCP, JSON-RPC, n8n parsed text blocks and explicit single-result wrappers.
// No payload is accepted without the downstream role/date/hash evidence checks.
function mcpObject(value,depth=0) {
  assert(depth<12,'mcp_invalid_envelope');
  if(typeof value==='string') {
    assert(value.length<=200000,'mcp_invalid_envelope');
    let parsed;try {parsed=JSON.parse(value);} catch {fail('mcp_invalid_json');}
    return mcpObject(parsed,depth+1);
  }
  assert(value&&typeof value==='object'&&!value.isError&&!value.error,'mcp_tool_failed');
  if(Array.isArray(value)) {
    assert(value.length===1,'mcp_ambiguous_result');
    return mcpObject(value[0],depth+1);
  }
  if(typeof value.ok==='boolean')return value;
  if(value.type==='text'&&Object.hasOwn(value,'text'))return mcpObject(value.text,depth+1);
  if(Object.hasOwn(value,'structuredContent')&&value.structuredContent!=null)
    return mcpObject(value.structuredContent,depth+1);
  if(Object.hasOwn(value,'content')) {
    const blocks=Array.isArray(value.content)?value.content:[value.content];
    const text=blocks.filter(c=>c&&c.type==='text'&&Object.hasOwn(c,'text'));
    assert(text.length===1&&blocks.length===1,'mcp_ambiguous_result');
    return mcpObject(text[0].text,depth+1);
  }
  const wrappers=['json','response','result','output','data'].filter(k=>Object.hasOwn(value,k)&&value[k]!=null);
  assert(wrappers.length<=1,'mcp_ambiguous_result');
  if(wrappers.length===1)return mcpObject(value[wrappers[0]],depth+1);
  fail('mcp_invalid_envelope');
}
