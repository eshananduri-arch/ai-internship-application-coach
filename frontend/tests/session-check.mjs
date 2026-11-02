import assert from 'node:assert/strict';
globalThis.document={querySelector:()=>({content:'/api'})};
const original={fetch:globalThis.fetch,setTimeout:globalThis.setTimeout,now:Date.now};
let elapsed=0,calls=[],plan=[],waits=0;
Date.now=()=>elapsed;
globalThis.setTimeout=(fn,ms)=>{elapsed+=ms;queueMicrotask(fn);return 0;};
globalThis.fetch=async (url,options)=>{
 calls.push({url,...options});const item=plan.shift();
 if(item instanceof Error)throw item;
 assert.ok(item,'Unexpected extra request');
 return item;
};
const api=await import('../assets/js/api.js');
const json=(data,status=200)=>new Response(JSON.stringify(data),{status,headers:{'Content-Type':'application/json'}});
const bad=status=>new Response('<h1>Bad Gateway</h1>',{status});
function reset(items){calls=[];plan=items;elapsed=0;waits=0;}
let checks=0;const check=(value,message)=>{assert.ok(value,message);checks++;};
try {
 reset([bad(502),bad(504),json({csrf_token:'current-session'})]);
 await api.session(()=>waits++);
 check(calls.length===3&&calls.every(c=>c.method==='GET'),'only session GET requests retry');
 check(waits===2&&elapsed===3000,'startup recovery reports bounded exponential waits');
 reset([new TypeError('network down'),json({csrf_token:'new-session'})]);await api.session();
 check(calls.length===2,'a transient network failure can recover');
 reset(Array.from({length:10},()=>bad(502)));
 await assert.rejects(()=>api.session(),e=>e.status===503&&e.message.includes('has not been submitted'));checks++;
 check(calls.length===10&&elapsed<=90000,'persistent gateway failures stop within the session budget');
 for(const [status,data] of [[403,{message:'Forbidden'}],[429,{message:'Slow down'}],[503,{message:'Database not configured',code:'database_unconfigured'}],[503,{message:'Coaching not configured',code:'coaching_unconfigured'}]]){
  reset([json(data,status)]);await assert.rejects(()=>api.session(),e=>e.status===status);checks++;
  check(calls.length===1,'auth, rate-limit and missing configuration errors are not retried');
 }
 reset([json({})]);await assert.rejects(()=>api.session(),/did not create/);checks++;
 check(calls.length===1,'invalid CSRF session output is not retried or accepted');
 reset([new Response('<html>Not JSON</html>',{status:200})]);await assert.rejects(()=>api.session(),/unreadable/);checks++;
 check(calls.length===1,'malformed successful responses are not retried');
 reset([json({csrf_token:'last-valid-session'})]);await api.session();
 reset([bad(502)]);
 await assert.rejects(()=>api.generate({request_id:'synthetic-key'},new File(['sample'],'sample.docx'),'synthetic-key'),e=>e.status===502);checks++;
 check(calls.length===1&&calls[0].method==='POST','resume uploads are never automatically replayed');
 check(calls[0].headers['X-CSRF-Token']==='last-valid-session','recovered CSRF is used for the next upload');
 reset([bad(502)]);
 await assert.rejects(()=>api.decide('analysis',{decision:'approve'},'decision-key'),e=>e.status===502);checks++;
 check(calls.length===1,'approval decisions are never automatically replayed');
 console.log(`Session recovery checks passed: ${checks}. No automatic upload or decision retry.`);
} finally {globalThis.fetch=original.fetch;globalThis.setTimeout=original.setTimeout;Date.now=original.now;}
