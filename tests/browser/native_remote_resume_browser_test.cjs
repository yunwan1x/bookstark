const {chromium}=require('playwright');
const assert=require('node:assert/strict');
(async()=>{
 const browser=await chromium.launch({args:['--no-sandbox']});
 try {
  const context=await browser.newContext({locale:'en-US'}),page=await context.newPage();
  await page.goto(process.env.NATIVE_START_URL);
  await page.getByText('Could not open your last workspace',{exact:true}).waitFor();
  await page.getByRole('button',{name:'Retry',exact:true}).waitFor({state:'visible'});
  assert.equal(new URL(page.url()).origin,new URL(process.env.NATIVE_START_URL).origin);
  assert.equal(await page.getByRole('button',{name:'Local workspace',exact:false}).count(),0);
  await context.request.post(process.env.NATIVE_REMOTE_URL+'/ready');
  await page.getByRole('button',{name:'Retry',exact:true}).click();
  await page.waitForURL(url=>url.origin===process.env.NATIVE_REMOTE_URL);
  assert.equal(await page.locator('h1').textContent(),'Remote workspace ready');
  console.log('PASS: saved remote auto-connect, recoverable failure, retry, no silent local fallback');
 }finally{await browser.close()}
})().catch(error=>{console.error(error);process.exit(1)});
