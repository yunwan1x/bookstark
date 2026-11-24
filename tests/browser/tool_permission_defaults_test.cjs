const{test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs'),root=require('./repo-root.cjs');
const source=fs.readFileSync(root+'/static/js/tool-permissions.js','utf8');
const catalog=[{key:'read_files',managed:true,zh:'读取工具文件'},{key:'save_files',managed:true,zh:'保存工具文件'},{key:'socket_tcp',managed:true,zh:'TCP连接'},{key:'network',managed:false},{key:'camera',managed:false,policy:'camera'},{key:'forms',managed:false,sandbox:'allow-forms'},{key:'popups',managed:false,sandbox:'allow-popups'}];
function setup(){const context={window:{BookStarkPermissionCatalog:catalog},document:{documentElement:{lang:'zh'},featurePolicy:{features:()=>['camera']}},escHtml:x=>x};vm.runInNewContext(source,context);return context.window.BookStarkToolPermissions;}
test('browser defaults override legacy denials without granting platform bridges',()=>{const p=setup(),flags=p.effective({camera:false,network:false,forms:false});for(const key of ['camera','network','forms','popups'])assert.equal(flags[key],true);for(const key of ['read_files','save_files','socket_tcp'])assert.notEqual(flags[key],true);assert.equal(p.allow({},false),'camera *');assert.equal(p.allow({},true),"camera 'src'");assert.ok(!p.sandbox({},false).includes('allow-same-origin'));assert.ok(p.sandbox({},true).includes('allow-same-origin'));assert.ok(p.sandbox({},false).includes('allow-popups'));});
test('form submits only selected bridge flags; review and upgrade lists omit browser capabilities',()=>{const p=setup(),form={querySelectorAll:()=>[{dataset:{toolPermission:'read_files'},checked:true},{dataset:{toolPermission:'save_files'},checked:false},{dataset:{toolPermission:'socket_tcp'},checked:false}]};const value=p.collect(form);assert.equal(JSON.stringify(value),'{"schema":1,"read_files":true,"save_files":false,"socket_tcp":false}');assert.equal(p.selected({...value,camera:true}).length,1);assert.equal(p.added({camera:false},{camera:true}).length,0);assert.equal(p.added({}, {socket_tcp:true})[0].key,'socket_tcp');assert.ok(!p.list({camera:true,network:false}).includes('摄像头'));assert.ok(!p.list({camera:true,network:false}).includes('网络'));});

test('cached old catalogs without managed metadata keep bridges opt-in',()=>{const context={window:{BookStarkPermissionCatalog:catalog.map(({managed,...spec})=>spec)},document:{documentElement:{lang:'en'}},escHtml:x=>x};vm.runInNewContext(source,context);const p=context.window.BookStarkToolPermissions;assert.notEqual(p.effective({}).read_files,true);assert.notEqual(p.effective({}).socket_tcp,true);assert.equal(p.selected({read_files:true}).length,1);assert.equal(p.collect({querySelectorAll:()=>[{dataset:{toolPermission:'camera'},checked:true}]}).camera,undefined);});

async function autoUpdate(previous,next){
 const updates=[],storage=new Map();let pending;
 const context={window:{addEventListener(){},dispatchEvent(){}},document:{getElementById:()=>({}),readyState:'complete'},location:new URL('https://workspace.test/'),URL,Date,CustomEvent:class{},Event:class{},sessionStorage:{getItem:k=>storage.get(k),setItem:(k,v)=>storage.set(k,v)},setTimeout:fn=>{pending=fn();},fetchWithCurrentCSRF:async(path,options)=>{let data;
  if(options.method==='PUT'){updates.push(path);data={};}
  else if(path==='/api/tool-market/client')data={url:'https://workspace.test/market',check_updates:true,auto_update:true};
  else if(path==='/api/tool-installs')data={tools:[{id:1,revision:'old',instance:'installation',permissions:previous}]};
  else if(path==='/api/tool-market')data={tools:[{id:1,revision:'new'}]};
  else data={revision:'new',hash:'verified',permissions:next};
  return {ok:true,json:async()=>data};
 }};
 vm.runInNewContext(fs.readFileSync(root+'/static/js/tool-market-background.js','utf8'),context);await pending;return updates;
}
test('automatic updates ignore browser default changes but never add bridge grants silently',async()=>{
 assert.equal((await autoUpdate({schema:1,camera:false,network:false},{schema:1,camera:true,network:true})).length,1);
 for(const key of ['read_files','save_files','socket_tcp'])assert.equal((await autoUpdate({}, {[key]:true})).length,0,key);
 assert.equal((await autoUpdate({read_files:true},{read_files:true,camera:true})).length,1);
});
