const assert=require('node:assert/strict');
const fs=require('node:fs');
const {chromium}=require(process.env.PLAYWRIGHT_MODULE);
(async()=>{
 const browser=await chromium.launch({headless:true,executablePath:process.env.CHROMIUM_PATH,args:['--no-sandbox']});
 try {
  const out=process.env.BOOKSTARK_ADMIN_VISUAL_OUT;assert.ok(out);fs.mkdirSync(out,{recursive:true});
  for(const english of [false,true]){
   const page=await browser.newPage({viewport:english?{width:320,height:568}:{width:390,height:844},deviceScaleFactor:2});
   const errors=[];let api=0;
   page.on('pageerror',e=>errors.push(e.message));
   page.on('request',r=>{if(new URL(r.url()).pathname.startsWith('/api/'))api++;});
   const name=english?'en-small':'zh';
   await page.goto(process.env.BOOKSTARK_VISUAL_URL+(english?'/?lang=en&scale=2':'/'),{waitUntil:'networkidle',timeout:60000});
   const placeholder=page.locator('flt-semantics-placeholder');await placeholder.waitFor({state:'attached'});await placeholder.dispatchEvent('click');
   await page.getByText('12,480',{exact:false}).or(page.getByLabel('12,480',{exact:false})).last().waitFor({timeout:10000}).catch(async error=>{
    await page.screenshot({path:out+'/debug-'+name+'.png'});
    fs.writeFileSync(out+'/debug-'+name+'.json',JSON.stringify({errors,texts:await page.locator('flt-semantics').allTextContents()},null,2));
    throw error;
   });
   await page.waitForTimeout(300);
   const initial=out+'/dashboard-'+name+'.png';assert.ok(!fs.existsSync(initial));await page.screenshot({path:initial});
   const legend=page.getByText(english?'Daily UV':'日 UV',{exact:false}).or(page.getByLabel(english?'Daily UV':'日 UV',{exact:false})).last();
   for(let i=0;i<60;i++){
    const b=await legend.boundingBox().catch(()=>null);
    if(b&&b.y>=60&&b.y+b.height<page.viewportSize().height-40)break;
    await page.mouse.move(24,page.viewportSize().height*.6);await page.mouse.wheel(0,100);await page.waitForTimeout(90);
   }
   await legend.waitFor();
   const chart=out+'/chart-'+name+'.png';assert.ok(!fs.existsSync(chart));await page.screenshot({path:chart});
   assert.equal(api,0);assert.deepEqual(errors,[]);
   assert.equal(await page.getByText(/RenderFlex overflowed|Exception:|Bad state:/).count(),0);
   await page.close();
   console.log('PASS dashboard synthetic visual '+name+': actual Flutter rendering, metrics, legend, no API requests/page errors');
  }
 } finally {await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});