// Offline behavior tests; inject emulator + Gamepad API, no ROMs or network.
const {chromium}=require(process.env.PLAYWRIGHT_MODULE||'playwright');
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const html=fs.readFileSync(path.join(__dirname,'article.html'),'utf8'),origin='https://retro.test';
const runtime=String.raw`
window.calls=[];window.sizes=[];window.Nostalgist={launch:async(options)=>{
window.launchOptions=options;
const resize=size=>{sizes.push(size);options.element.width=size.width;options.element.height=size.height};
resize(options.size);
return {resize,pressDown:k=>calls.push(['down',k]),pressUp:k=>calls.push(['up',k]),pause:()=>calls.push(['pause']),resume:()=>calls.push(['resume']),exit:()=>calls.push(['exit']),saveState:async()=>({state:new Blob(['state'])}),loadState:async()=>{}}}};
`;
(async()=>{
const browser=await chromium.launch({executablePath:process.env.CHROMIUM_PATH,args:['--no-sandbox']});
try{
const page=await browser.newPage({viewport:{width:1280,height:900}}),errors=[];
page.on('pageerror',e=>errors.push(e.message));
await page.addInitScript(()=>{window.testPads=[];Object.defineProperty(navigator,'getGamepads',{value:()=>window.testPads})});
await page.route('**/*',r=>{
const url=r.request().url();
if(url===origin+'/')return r.fulfill({contentType:'text/html',body:html});
if(url.includes('nostalgist-'))return r.fulfill({contentType:'application/javascript',body:runtime});
if(url.includes('fflate-'))return r.fulfill({contentType:'application/javascript',body:'window.fflate={unzipSync:()=>({"core.js":new Uint8Array(),"core.wasm":new Uint8Array()})}'});
if(url.includes('/static/css/'))return r.fulfill({contentType:'text/css',body:fs.readFileSync(path.join(__dirname,'../..',new URL(url).pathname),'utf8')});
return r.fulfill({body:'test'});
});
await page.goto(origin);
const menu=page.locator('#game-menu'),settings=page.locator('#controller-settings');
const openMenu=async()=>{if(!await menu.evaluate(e=>e.open))await page.locator('#game-menu > summary').click()};
const openSettings=async()=>{await openMenu();if(!await settings.evaluate(e=>e.open))await page.locator('#controller-settings > summary').click()};
const pick=async p=>{await openSettings();await page.locator('#player-tabs [data-player="'+p+'"]').click()};
const bind=(a,type='keys')=>page.locator('[data-action="'+a+'"][data-binding="'+type+'"]');
const bindKey=async(p,a,key)=>{await pick(p);await bind(a).click();await page.keyboard.press(key)};
await openSettings();assert.equal(await bind('a','pad').isEnabled(),false);
await bindKey(2,'b','z');await pick(1);assert.equal(await bind('b').innerText(),'—');
await bindKey(1,'b','c');await bindKey(2,'b','v');await bindKey(3,'b','b');await bindKey(4,'b','n');
await bind('a').click();await page.keyboard.press('Escape');assert.equal(await bind('a').innerText(),'—');
await page.reload();await pick(4);assert.equal(await bind('b').innerText(),'N');
await page.click('#close-menu');await page.selectOption('#platform','mgba',{force:true});await pick(4);assert.equal(await bind('b').innerText(),'—');
await page.click('#close-menu');await page.selectOption('#platform','fceumm',{force:true});await pick(4);assert.equal(await bind('b').innerText(),'N');
console.log('P1–P4 PERSISTENCE / CROSS-PLAYER CONFLICT / PLATFORM ISOLATION OK');
await page.evaluate(()=>testPads=Array.from({length:4},(_,index)=>({id:'Identical Pad',mapping:'standard',index,connected:true,buttons:Array.from({length:16},()=>({pressed:false,value:0})),axes:[0,0,0,0]})));
await page.waitForFunction(()=>document.querySelectorAll('#controller-device option').length===6);
const key=i=>JSON.stringify(['Identical Pad','standard',i]);
await pick(1);await page.selectOption('#controller-device',key(0));
await pick(2);await page.selectOption('#controller-device',key(0));await pick(1);
assert.equal(await page.inputValue('#controller-device'),'none');
for(let p=1;p<=4;p++){await pick(p);await page.selectOption('#controller-device',key(p-1))}
await pick(3);await bind('a','pad').click();await page.waitForTimeout(100);
await page.evaluate(()=>testPads[2].axes[2]=.9);
await page.waitForFunction(()=>document.querySelector('[data-action="a"][data-binding="pad"]').textContent.includes('2+'));
await page.evaluate(()=>testPads[2].axes[2]=0);
await page.click('#done-controls');
await page.setInputFiles('#rom',{name:'test.nes',mimeType:'application/octet-stream',buffer:Buffer.from('test')});await page.click('#start');
await page.waitForFunction(()=>document.body.classList.contains('playing'));
const cfg=await page.evaluate(()=>launchOptions.retroarchConfig);assert.equal(cfg.input_max_users,4);
assert.equal(cfg.video_force_aspect,true);assert.equal(cfg.aspect_ratio_index,22);
for(let p=1;p<=4;p++)assert.equal(cfg['input_player'+p+'_a_btn'],'nul');
const keyCount=new Set();for(let p=1;p<=4;p++)for(const a of ['up','down','left','right','b','a','y','x','l','r','l2','r2','l3','r3','select','start'])keyCount.add(cfg['input_player'+p+'_'+a]);
assert.equal(keyCount.size,64);
for(const [i,k] of ['c','v','b','n'].entries()){
await page.keyboard.press(k);
assert.deepEqual(await page.evaluate(()=>calls.slice(-2)),[['down',{player:i+1,button:'b'}],['up',{player:i+1,button:'b'}]]);
}
await page.evaluate(()=>{calls.length=0;testPads.forEach(p=>p.buttons[0]={pressed:true,value:1})});
await page.waitForFunction(()=>calls.filter(c=>c[0]==='down').length===4);
assert.deepEqual(await page.evaluate(()=>calls.map(c=>c[1].player).sort()),[1,2,3,4]);
await page.keyboard.down('c');await page.keyboard.up('c');
assert.equal(await page.evaluate(()=>calls.filter(c=>c[0]==='up').length),0);
await page.evaluate(()=>testPads.forEach(p=>p.buttons[0]={pressed:false,value:0}));
await page.waitForFunction(()=>calls.filter(c=>c[0]==='up').length===4);
await page.evaluate(()=>{calls.length=0;testPads[2].axes[2]=.9});
await page.waitForFunction(()=>calls.length>0);assert.deepEqual(await page.evaluate(()=>calls.at(-1)),['down',{player:3,button:'a'}]);
await page.evaluate(()=>testPads[2].axes[2]=.1);await page.waitForFunction(()=>calls.at(-1)?.[0]==='up');
await page.evaluate(()=>{calls.length=0;testPads[3].buttons[0]={pressed:true,value:1}});
await page.waitForFunction(()=>calls.at(-1)?.[0]==='down');
await page.evaluate(()=>testPads=testPads.slice(0,3));await page.waitForFunction(()=>calls.at(-1)?.[0]==='up');
assert.deepEqual(await page.evaluate(()=>calls.at(-1)),['up',{player:4,button:'b'}]);
console.log('FOUR SIMULTANEOUS PADS / IDENTICAL PAD IDS / KEYBOARD / AXIS / DISCONNECT OK');
await openSettings();await page.waitForTimeout(50);assert.equal(await page.innerText('#pause'),'继续');
const before=await page.evaluate(()=>calls.length);await pick(2);await bind('start').click();await page.keyboard.press('h');assert.equal(await page.evaluate(()=>calls.length),before);
await page.click('#done-controls');await page.waitForTimeout(50);await page.keyboard.press('h');
assert.deepEqual(await page.evaluate(()=>calls.slice(-2)),[['down',{player:2,button:'start'}],['up',{player:2,button:'start'}]]);
await openMenu();await page.selectOption('#pad-mode','on');await page.selectOption('#touch-player','4');await page.click('#close-menu');await page.waitForTimeout(50);
// Use a real pointer so pointer capture follows the browser's normal behavior.
const button=await page.locator('#pad-zone [data-key="a"]').boundingBox();await page.mouse.move(button.x+10,button.y+10);await page.mouse.down();await page.mouse.up();
assert.deepEqual(await page.evaluate(()=>calls.slice(-2)),[['down',{player:4,button:'a'}],['up',{player:4,button:'a'}]]);
await openMenu();await page.click('#fullscreen');await page.waitForFunction(()=>!!document.fullscreenElement);
await openMenu();await page.click('#fullscreen');await page.waitForFunction(()=>!document.fullscreenElement);
for(const size of [{width:390,height:844},{width:844,height:390},{width:1280,height:720}]){
await page.setViewportSize(size);await page.waitForFunction(s=>sizes.at(-1)?.width===s.width&&sizes.at(-1)?.height===s.height,size);
const rect=await page.locator('#canvas').boundingBox();assert(rect.x>=0&&rect.y>=0&&rect.x+rect.width<=size.width+1&&rect.y+rect.height<=size.height+1);
assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true);
}
await pick(4);await page.selectOption('#lang','en');assert.match(await bind('select').getAttribute('aria-label'),/^P4 · Coin/);
await page.setViewportSize({width:390,height:844});const panel=await page.locator('#menu-items').boundingBox();assert(panel.x>=0&&panel.y+panel.height<=844);
await page.click('#reset-controls');assert.equal(await bind('b').innerText(),'—');
await page.click('#fit-screen');await page.waitForTimeout(50);
page.on('dialog',d=>d.accept());await openMenu();await page.click('#stop');await page.waitForFunction(()=>!document.body.classList.contains('playing'));assert(await page.locator('#setup').isVisible());
assert.deepEqual(errors,[]);
console.log('MENU PAUSE / CAPTURE ISOLATION / TOUCH P4 / FIT / FULLSCREEN / MOBILE / EN / STOP OK');
}finally{await browser.close()}
})().catch(e=>{console.error(e);process.exitCode=1});
