const assert=require('node:assert/strict');
const fs=require('node:fs');
const {chromium}=require(process.env.PLAYWRIGHT_MODULE);
(async()=>{
 const browser=await chromium.launch({headless:true,executablePath:process.env.CHROMIUM_PATH,args:['--no-sandbox']});
 try{
  const out='/vol1/1000/wy/photos-apk-test/bookstark-flutter/screenshots';fs.mkdirSync(out,{recursive:true});
  for(const english of [false,true]){
   const page=await browser.newPage({viewport:english?{width:320,height:568}:{width:390,height:844},deviceScaleFactor:2});
   const errors=[];let api=0;page.on('pageerror',e=>errors.push(e.message));page.on('request',r=>{if(new URL(r.url()).pathname.startsWith('/api/'))api++});
   async function open(route,title){
    await page.goto(process.env.BOOKSTARK_VISUAL_URL+'/?page='+route+(english?'&lang=en&scale=2':''),{waitUntil:'networkidle',timeout:60000});
    const semantics=page.locator('flt-semantics-placeholder');if(await semantics.count())await semantics.dispatchEvent('click');
    await page.getByText(title,{exact:true}).first().waitFor();await page.waitForTimeout(350);
    await page.screenshot({path:out+'/18-'+route+(english?'-english-small':'')+'-fixture-actual.png'});
   }
   await open('labels',english?'Labels':'标签管理');
   await open('label-editor',english?'Edit label':'编辑标签');
   await open('label-detail','阅读');
   await open('label-merge',english?'Merge labels':'合并标签');
   await open('label-recommendations',english?'Recommendations':'推荐设置');
   const preview=page.getByRole('button',{name:english?'Preview recommendations':'预览推荐',exact:true});
   for(let i=0;i<15&&!await preview.isVisible();i++){await page.mouse.move(150,400);await page.mouse.wheel(0,300);await page.waitForTimeout(100);}
   await preview.click();await page.waitForTimeout(350);await page.mouse.move(150,400);await page.mouse.wheel(0,500);await page.waitForTimeout(200);
   await page.screenshot({path:out+'/18-label-preview'+(english?'-english-small':'')+'-fixture-actual.png'});
   assert.equal(api,0);assert.deepEqual(errors,[]);assert.equal(await page.getByText(/Null check operator|Bad state:|Exception:|Error:/).count(),0);
   await page.close();console.log('PASS labels '+(english?'English 320dp 200%':'Chinese')+' list, editor, detail, merge, read-only recommendation preview; fixture only');
  }
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1});
