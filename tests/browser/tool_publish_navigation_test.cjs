const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const path=require('node:path');

function fixture(){
 const data=new Map(),scrolls=[];
 const context={URL,URLSearchParams,window:{},location:new URL('https://book.test/market?status=installed&page=2'),document:{body:{dataset:{marketWorkspace:'member-1'}},documentElement:{lang:'zh'}},escHtml:String,escAttr:String,scrollY:420,requestAnimationFrame:callback=>callback(),scrollTo:(x,y)=>scrolls.push([x,y]),sessionStorage:{setItem:(k,v)=>data.set(k,v),getItem:k=>data.get(k)||null,removeItem:k=>data.delete(k)}};
 vm.runInNewContext(fs.readFileSync(path.join(__dirname,'../../static/js/tool-market-ui.js'),'utf8'),context);
 return {context,ui:context.window.ToolMarketUI,scrolls};
}

test('publication navigation only returns to local market and selection pages',()=>{
 const {ui}=fixture();
 for(const url of ['https://evil.test/market','//evil.test/market','javascript:alert(1)','/market?open=5','/api/profile'])assert.equal(ui.marketReturn(url),'/market');
 assert.equal(ui.marketReturn('/market?status=installed&page=2'),'/market?status=installed&page=2');
 const back=new URL(ui.selectionReturn('https://evil.test/market/publish',7),'https://book.test');
 assert.equal(back.pathname,'/market/publish');assert.equal(back.searchParams.get('selected'),'7');assert.equal(back.searchParams.get('return'),'/market');
 const restored=new URL(ui.selectionReturn('/market/publish?q=PDF&page=3&return=%2Fmarket%3Fstatus%3Dinstalled',9),'https://book.test');
 assert.equal(restored.searchParams.get('q'),'PDF');assert.equal(restored.searchParams.get('page'),'3');assert.equal(restored.searchParams.get('selected'),'9');assert.equal(restored.searchParams.get('return'),'/market?status=installed');
});

test('market scroll restoration is scoped to workspace and exact list state',()=>{
 const {ui,context,scrolls}=fixture();ui.rememberMarketPosition();
 context.document.body.dataset.marketWorkspace='member-2';ui.restoreMarketPosition();assert.equal(scrolls.length,0);
 context.document.body.dataset.marketWorkspace='member-1';context.location=new URL('https://book.test/market');ui.restoreMarketPosition();assert.equal(scrolls.length,0);
 context.location=new URL('https://book.test/market?status=installed&page=2');ui.restoreMarketPosition();assert.deepEqual(scrolls,[[0,420]]);
 ui.restoreMarketPosition();assert.equal(scrolls.length,1,'restoration is consumed after returning');
});

test('native defaults do not override an explicitly saved workspace marketplace',async()=>{
 const official='https://cloud.vs2010wy.top/market';
 for(const [saved,native,expected]of [
  [{url:'https://custom.test/market',configured:true},{url:official,configured:false},'https://custom.test/market'],
  [{url:official,configured:false},{url:official,configured:false},official],
  [{url:'https://custom.test/market',configured:true},{url:'https://native.test/market',configured:true},'https://native.test/market'],
  [{url:official,configured:false},{url:'https://legacy.test/market'},'https://legacy.test/market']
 ]){
  const {context,ui}=fixture();
  context.fetchWithCurrentCSRF=async path=>({ok:true,json:async()=>path.includes('?server=')?{account:'native-account'}:{...saved,check_updates:false,auto_update:true,account:'workspace-account'}});
  context.BookStarkClient=context.window.BookStarkClient={ready:Promise.resolve(true),marketSettings:async()=>({...native,check_updates:true,auto_update:false})};
  const result=await ui.config();assert.equal(result.url,expected);
  if(native.configured===false&&saved.configured){assert.equal(result.check_updates,false);assert.equal(result.auto_update,true);assert.equal(result.account,'workspace-account');}
 }
});

test('installed tool URLs use a standalone page and safe market return',()=>{const {ui}=fixture();const url=new URL(ui.toolURL(-27),'https://book.test');assert.equal(url.pathname,'/tools/run/-27');assert.equal(url.searchParams.get('return'),'/market?status=installed&page=2');for(const back of ['https://evil.test/market','//evil.test/market','/market?open=7','/tools/run/9'])assert.equal(new URL(ui.toolURL(7,back),'https://book.test').searchParams.get('return'),'/market');});
