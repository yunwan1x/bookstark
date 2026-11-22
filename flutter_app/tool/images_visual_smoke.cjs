const assert=require('node:assert/strict');
const fs=require('node:fs');
const {chromium}=require(process.env.PLAYWRIGHT_MODULE);
(async()=>{
 const browser=await chromium.launch({headless:true,executablePath:process.env.CHROMIUM_PATH,args:['--no-sandbox']});
 try {
  const out='/vol1/1000/wy/photos-apk-test/bookstark-flutter/screenshots';fs.mkdirSync(out,{recursive:true});
  for(const english of [false,true]) {
   const page=await browser.newPage({viewport:english?{width:320,height:568}:{width:390,height:844},deviceScaleFactor:2});
   const errors=[];let api=0;page.on('pageerror',e=>errors.push(e.message));page.on('request',r=>{if(new URL(r.url()).pathname.startsWith('/api/'))api++});
   const base=process.env.BOOKSTARK_VISUAL_URL,query=english?'&lang=en&scale=2':'';
   async function open(route) {
    await page.goto(base+'/?page='+route+query,{waitUntil:'networkidle',timeout:60000});
    const semantics=page.locator('flt-semantics-placeholder');if(await semantics.count())await semantics.dispatchEvent('click');await page.waitForTimeout(500);
   }
   await open('images');await page.getByText(english?'Images':'图片库',{exact:true}).waitFor();
   await page.screenshot({path:out+'/20-images'+(english?'-english-small':'')+'-fixture-actual.png'});
   await page.getByRole('button',{name:english?'List view':'列表视图',exact:true}).click();await page.waitForTimeout(300);
   await page.getByRole('button',{name:english?'Grid view':'网格视图',exact:true}).click();
   await open('image-preview');await page.getByRole('button',{name:english?'Share image file':'分享图片文件',exact:true}).waitFor();
   await page.screenshot({path:out+'/20-image-preview'+(english?'-english-small':'')+'-fixture-actual.png'});
   await open('image-upload');
   const choose=page.getByRole('button',{name:english?'Choose images (multiple)':'选择图片（可多选）',exact:true});
   for(let i=0;i<20&&!await choose.isVisible();i++){await page.mouse.move(150,400);await page.mouse.wheel(0,200);await page.waitForTimeout(100);}
   const chooser=page.waitForEvent('filechooser');await choose.click();
   await (await chooser).setFiles({name:'真实选择.svg',mimeType:'image/svg+xml',buffer:Buffer.from('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20"><rect width="20" height="20" fill="blue"/></svg>')});
   const processButton=page.getByRole('button',{name:english?'Process 1 items':'开始处理1项',exact:true});
   for(let i=0;i<20&&!await processButton.isVisible();i++){await page.mouse.move(150,400);await page.mouse.wheel(0,200);await page.waitForTimeout(100);}
   await processButton.click();await page.waitForTimeout(500);
   const confirmed=page.getByLabel(/Confirmed file:|已确认文件：/).last();
   for(let i=0;i<20&&!await confirmed.isVisible();i++){await page.mouse.move(150,350);await page.mouse.wheel(0,-160);await page.waitForTimeout(100);}
   await confirmed.waitFor();
   await page.screenshot({path:out+'/20-image-upload'+(english?'-english-small':'')+'-fixture-actual.png'});
   assert.equal(api,0);assert.deepEqual(errors,[]);assert.equal(await page.getByText(/Null check operator|Bad state:|Exception:|Error:/).count(),0);
   console.log('PASS image library '+(english?'English 320dp 200%':'Chinese')+' grid/list, native preview, actual file chooser and confirmed fixture upload; no HTTP');await page.close();
  }
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1});
