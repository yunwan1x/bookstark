const assert=require('node:assert/strict');
const fs=require('node:fs');
const {chromium}=require(process.env.PLAYWRIGHT_MODULE||'/vol1/1000/wy/photos-apk-test/bookstark-flutter/browser-tools/node_modules/playwright-core');
(async()=>{
 const browser=await chromium.launch({headless:true,executablePath:process.env.CHROMIUM_PATH||'/root/.cache/ms-playwright/chromium-1243/chrome-linux64/chrome',args:['--no-sandbox']});
 try {
  const page=await browser.newPage({viewport:{width:390,height:844},deviceScaleFactor:2});
  const errors=[];page.on('pageerror',e=>errors.push(e.message));
  const api=[];await page.route('**/api/**',route=>{api.push(new URL(route.request().url()).pathname);return route.abort();});
  await page.goto((process.env.BOOKSTARK_VISUAL_URL||'http://127.0.0.1:8098')+'/',{waitUntil:'networkidle',timeout:60000});
  const semantics=page.locator('flt-semantics-placeholder');if(await semantics.count())await semantics.dispatchEvent('click');
  const out=process.env.SCREENSHOT_DIR||'/vol1/1000/wy/photos-apk-test/bookstark-flutter/screenshots';fs.mkdirSync(out,{recursive:true});
  async function capture(title,filename) {
   await page.getByText(title,{exact:false}).or(page.getByLabel(title,{exact:false})).first().waitFor();await page.mouse.move(0,0);await page.waitForTimeout(1500);
   await page.screenshot({path:out+'/'+filename});
  }
  await capture('连接你的知识库','01-connection-actual.png');
  await page.getByRole('button',{name:'注册账号',exact:true}).click();
  await capture('创建你的账号','02-register-actual.png');
  await page.getByRole('button',{name:'返回',exact:true}).click();
  await page.getByRole('button',{name:'忘记密码',exact:true}).click();
  await capture('找回你的账号','03-forgot-actual.png');
  await page.mouse.wheel(0,500);await page.waitForTimeout(1500);
  await page.getByRole('button',{name:/已有重置链接/}).click();
  await capture('设置新密码','04-reset-actual.png');
  assert.equal(api.length,0,'Opening account pages must not submit APIs or send mail');
  assert.equal(errors.length,0,errors.join('\n'));
  console.log('PASS app connection/register/forgot/reset routes; screenshots saved; no API submissions or page errors');
 } finally {await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1});
