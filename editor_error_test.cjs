const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const source=fs.readFileSync(__dirname+'/static/js/utils.js','utf8');
const start=source.indexOf('window.BookStarkErrors = (function()');
const end=source.indexOf('\n})();',start)+7;
const context={window:{}};
vm.runInNewContext(source.slice(start,end),context);
const check=context.window.BookStarkErrors.requireSaveSuccess;
test('save errors retain server messages and HTTP status',async()=>{
 for(const [status,payload,message] of [
  [401,{message:'登录已过期'},'登录已过期'],
  [403,{error:'没有修改权限'},'没有修改权限'],
  [200,{code:1,message:'密码不正确'},'密码不正确'],
  [500,{message:'数据库写入失败'},'数据库写入失败'],
 ]) await assert.rejects(check(new Response(JSON.stringify(payload),{status})),e=>e.message===message&&e.status===status);
});
test('save rejects non-JSON errors, unexpected success bodies, and offline acknowledgements',async()=>{
 await assert.rejects(check(new Response('<html>too large</html>',{status:413})),/HTTP 413/);
 await assert.rejects(check(new Response('<html>login</html>')),/保存响应异常/);
 await assert.rejects(check(new Response('{}')),/保存响应异常/);
 await assert.rejects(check(new Response('{"code":0}',{status:202,headers:{'X-Offline-Queued':'true'}})),/尚未保存到服务器/);
});
test('successful save is accepted',async()=>{
 const response=new Response('{"code":0,"message":"ok"}');
 assert.equal(await check(response),response);
});
test('autosave reports failure, retains draft, and recovers without marking failed content saved',async()=>{
 const common=fs.readFileSync(__dirname+'/static/js/editor-common.js','utf8');
 const start=common.indexOf('  function setupAutoSave(opts)');
 const end=common.indexOf('  // Keyboard shortcuts',start);
 let draft=null,fail=true;
 const statuses=[];
 const ctx={SAVE_INTERVAL:30000,setTimeout:()=>1,clearTimeout:()=>{},
  writeStoredDraft:(_key,value)=>{draft=value;},deleteStoredDraft:()=>{draft=null;},readStoredDraft:()=>draft};
 vm.runInNewContext(common.slice(start,end),ctx);
 const error=new Error('登录已过期');
 const manager=ctx.setupAutoSave({getContent:()=>'new content',draftKey:'test',saveFn:()=>fail?Promise.reject(error):Promise.resolve(),onStatusChange:(status,error)=>statuses.push({status,error})});
 manager.setLastSaved('old content');
 manager.onContentChange();
 await assert.rejects(manager.autoSave(),/登录已过期/);
 assert.equal(manager._lastSaved,'old content');
 assert.equal(draft,'new content');
 assert.deepEqual(statuses.at(-1),{status:'unsaved',error});
 manager.onContentChange();
 assert.deepEqual(statuses.at(-1),{status:'unsaved',error});
 fail=false;
 await manager.manualSave();
 assert.equal(manager._lastSaved,'new content');
 assert.equal(draft,null);
 assert.deepEqual(statuses.at(-1),{status:'saved',error:undefined});
 manager.destroy();
});
