const assert = require('node:assert/strict');
const fs = require('node:fs');
const {chromium} = require(process.env.PLAYWRIGHT_MODULE);
(async()=>{
 const browser = await chromium.launch({headless:true,executablePath:process.env.CHROMIUM_PATH,args:['--no-sandbox']});
 try {
  const out='/vol1/1000/wy/photos-apk-test/bookstark-flutter/screenshots'; fs.mkdirSync(out,{recursive:true});
  const page=await browser.newPage({viewport:{width:390,height:844},deviceScaleFactor:2});
  const errors=[];let api=0;page.on('pageerror',e=>errors.push(e.message));page.on('request',r=>{if(new URL(r.url()).pathname.startsWith('/api/'))api++;});
  async function open(route){await page.goto(process.env.BOOKSTARK_VISUAL_URL+'/?page='+route,{waitUntil:'networkidle',timeout:60000});const sem=page.locator('flt-semantics-placeholder');if(await sem.count())await sem.dispatchEvent('click');await page.waitForTimeout(600);}
  await open('drive');await page.getByText('网盘',{exact:true}).waitFor();
  await page.screenshot({path:out+'/21-files-fixture-actual.png'});
  await page.getByLabel(/^阅读资料/).first().click();await page.getByLabel(/学习资料.pdf/).first().waitFor();
  await open('drive-editor');const input=page.getByRole('textbox').first();await input.click();await input.press('ControlOrMeta+A');await page.keyboard.insertText('# 浏览器编辑\n\n**真实Markdown**');await page.waitForTimeout(700);
  await page.getByRole('button',{name:'预览',exact:true}).click();await page.waitForTimeout(300);
  await page.screenshot({path:out+'/21-file-editor-fixture-actual.png'});
  await page.getByRole('button',{name:'保存',exact:true}).click();await page.getByText('UTF-8 · 37 字节 · 已保存',{exact:true}).waitFor();
  await open('drive-upload');const chooser=page.waitForEvent('filechooser');await page.getByRole('button',{name:'选择文件（可多选）',exact:true}).click();await (await chooser).setFiles({name:'浏览器实际选择.txt',mimeType:'text/plain',buffer:Buffer.from('actual browser file bytes')});
  await page.getByRole('button',{name:'开始上传',exact:true}).click();await page.waitForTimeout(800); await page.screenshot({path:out+'/21-file-upload-diagnostic.png'});  await page.getByLabel(/已确认保存|已复用并确认保存/).first().waitFor();
  await page.screenshot({path:out+'/21-file-upload-fixture-actual.png'});
  assert.equal(api,0);assert.deepEqual(errors,[]);
  console.log('PASS drive directory navigation, native editor Markdown/save, actual browser file picker and confirmed upload; isolated fixture, no API requests');
  await page.close();
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
