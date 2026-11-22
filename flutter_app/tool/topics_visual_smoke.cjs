const assert=require('node:assert/strict');
const fs=require('node:fs');
const {chromium}=require(process.env.PLAYWRIGHT_MODULE);
(async()=>{
 const browser=await chromium.launch({headless:true,executablePath:process.env.CHROMIUM_PATH,args:['--no-sandbox']});
 try {
  const out='/vol1/1000/wy/photos-apk-test/bookstark-flutter/screenshots';fs.mkdirSync(out,{recursive:true});
  for(const english of [false,true]) {
   const page=await browser.newPage({viewport:english?{width:320,height:568}:{width:390,height:844},deviceScaleFactor:2});
   const errors=[];let apiCalls=0;page.on('pageerror',error=>errors.push(error.message));
   page.on('request',request=>{if(new URL(request.url()).pathname.startsWith('/api/'))apiCalls++});
   async function open(route,label) {
    await page.goto(process.env.BOOKSTARK_VISUAL_URL+'/?page='+route+(english?'&lang=en&scale=2':''),{waitUntil:'networkidle',timeout:60000});
    const semantics=page.locator('flt-semantics-placeholder');if(await semantics.count())await semantics.dispatchEvent('click');
    await page.getByText(label,{exact:true}).first().waitFor();
    await page.mouse.move(0,0);await page.waitForTimeout(350);
    await page.screenshot({path:out+'/17-'+route+(english?'-english-small':'')+'-fixture-actual.png'});
   }
   await open('topics',english?'Topics':'主题');
   await open('topic-detail','阅读与知识整理');
   await open('topic-summary-editor',english?'Edit summary':'编辑小结');
   await open('topic-comment-editor',english?'Edit comment':'编辑评论');
   await open('topic-ai-draft',english?'AI draft':'AI草拟');
   await page.getByRole('button',{name:english?'Generate':'开始生成',exact:true}).click();
   await page.getByRole('group',{name:english?'Completed':'生成完成',exact:true}).waitFor();
   if(english){await page.mouse.move(150,400);await page.mouse.wheel(0,450);await page.waitForTimeout(300);}
   await page.screenshot({path:out+'/17-topic-ai-completed'+(english?'-english-small':'')+'-fixture-actual.png'});
   await open('topic-editor',english?'Save':'保存');
   await open('topic-comments',english?'Comments':'评论');
   await open('topic-picker',english?'Add resources':'添加资料');
   await open('topic-calendar',english?'Topic calendar':'主题日历');
   assert.equal(apiCalls,0);assert.equal(errors.length,0,errors.join('\n'));
   assert.equal(await page.getByText(/Null check operator|Bad state:|Exception:|Error:/).count(),0);
   await page.close();console.log('PASS topics '+(english?'English 320dp 200%':'Chinese')+' native routes, Markdown editors, AI draft completion, comments and calendar; no HTTP');
  }
 } finally {await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1});
