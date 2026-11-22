const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const englishLabels = JSON.parse(fs.readFileSync(path.join(__dirname, 'admin_settings_visual_labels.json'), 'utf8'));
const {chromium} = require(process.env.PLAYWRIGHT_MODULE);

(async () => {
  assert.ok(process.env.BOOKSTARK_BROWSER_PROFILE);
  const browser = await chromium.launchPersistentContext(process.env.BOOKSTARK_BROWSER_PROFILE, {
    headless: true, executablePath: process.env.CHROMIUM_PATH, deviceScaleFactor: 2,
    args: ['--no-sandbox'],
  });
  const report = [];
  try {
    const out = process.env.BOOKSTARK_SETTINGS_VISUAL_OUT;
    assert.ok(out);
    fs.mkdirSync(out, {recursive: true});
    for (const scenario of [{large: false, english: false}, {large: true, english: false}, {large: true, english: true}]) {
      const {large, english} = scenario;
      const translated = text => english ? (englishLabels[text] || text) : text;
      const name = english ? 'en-320-200' : large ? 'zh-320-200' : 'zh-390';
      const page = await browser.newPage();
      await page.setViewportSize({width: large ? 320 : 390, height: large ? 900 : 844});
      const errors = [];
      let apiRequests = 0;
      page.on('pageerror', error => errors.push(error.message));
      page.on('console', message => {
        if (/RenderFlex overflowed|EXCEPTION CAUGHT|Bad state:/.test(message.text())) {
          errors.push(message.text());
        }
      });
      page.on('request', request => {
        if (new URL(request.url()).pathname.includes('/api/')) apiRequests++;
      });
      const label = text => page.getByText(translated(text), {exact: false})
          .or(page.getByLabel(translated(text), {exact: false})).last();
      const wheel = async amount => {
        await page.mouse.move(24, page.viewportSize().height * 0.6);
        await page.mouse.wheel(0, amount);
        await page.waitForTimeout(100);
      };
      async function locate(text, reset = false, targetOverride = null) {
        if (reset) await wheel(-10000);
        const target = targetOverride || label(text);
        for (let i = 0; i < 90; i++) {
          const box = await target.count() ? await target.boundingBox({timeout: 500}).catch(() => null) : null;
          if (box && box.width > 0 && box.height > 0 &&
              box.y >= 50 && box.y + box.height < page.viewportSize().height - 65) {
            return box;
          }
          await wheel(150);
        }
        throw new Error('Cannot reach fixture control: ' + text);
      }
      async function tap(text) {
        const escaped = translated(text).replace(/[.*+?^$\{\}()|[\]\\]/g, '\\$&');
        const button = page.getByRole('button', {name: new RegExp('^' + escaped + '(?:\\s|$)')}).last();
        const box = await locate(text, true, button);
        await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2);
        await page.waitForTimeout(400);
      }
      async function back() {
        await page.mouse.move(0, 0);
        await page.waitForTimeout(200);
        const target = page.getByRole('button', {name: translated('返回'), exact: true}).last();
        const box = await target.boundingBox({timeout: 3000});
        assert.ok(box);
        await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2);
        await page.waitForTimeout(400);
      }
      async function capture(screen, marker, bottom) {
        await wheel(-10000);
        await label(marker).waitFor({timeout: 15000});
        const save = page.getByRole('button', {name: new RegExp(english ? '^Save' : '^保存')}).last();
        if (await save.count()) assert.equal(await save.isDisabled(), true, 'Readonly visual navigation unexpectedly changed a draft');
        await page.waitForTimeout(200);
        const top = out + '/' + name + '-' + screen + '-top.png';
        assert.ok(!fs.existsSync(top));
        await page.mouse.move(0, 0);
        await page.waitForTimeout(100);
        await page.screenshot({path: top});
        if (bottom) {
          await locate(bottom);
          await page.waitForTimeout(150);
          await page.mouse.move(0, 0);
          await page.waitForTimeout(100);
          await page.screenshot({path: out + '/' + name + '-' + screen + '-bottom.png'});
        }
        report.push({layout: name, screen, marker});
      }
      try {
        await page.goto(process.env.BOOKSTARK_VISUAL_URL +
            (english ? '/?lang=en&scale=2' : large ? '/?scale=2' : '/'), {waitUntil: 'networkidle', timeout: 60000});
        const placeholder = page.locator('flt-semantics-placeholder');
        await placeholder.waitFor({state: 'attached'});
        await placeholder.dispatchEvent('click');
        await capture('hub', '基础配置', '终端策略');
        await tap('通用设置');
        await capture('general', '会话与编辑', '分页与列表');
        await tap('分页与列表');
        await capture('pagination', '分页大小', '标签列表上限');
        await back(); await back();
        await tap('内容与上传');
        await capture('content', '上传限制', '公开页面标签');
        await tap('标签推荐');
        await capture('recommendations', '推荐数量', '手动精选标签');
        await back();
        await tap('公开页面标签');
        await capture('public-tags', '展示方式', '高级原始配置');
        await back(); await back();
        await tap('访问与注册');
        await capture('registration', '注册邀请码', '协作信令');
        await tap('协作信令');
        await capture('signaling', 'WebRTC 信令', 'TURN 服务');
        await back(); await back();
        await tap('AI 模型与提示词');
        await capture('ai', '连接配置', 'AI 累计用量');
        await tap('系统提示词');
        await capture('prompts', '提示词原文', '恢复当前场景默认值');
        await back();
        await tap('编辑动作');
        await capture('actions', '动作原文', '恢复当前场景默认值');
        await back(); await back();
        await tap('邮件服务');
        await capture('mail', '功能设置', '发送状态');
        await tap('SMTP 连接');
        await capture('smtp', '连接配置', '发件人');
        await back(); await back();
        await tap('WebDAV 服务');
        await capture('webdav', '容量与传输', '基础地址');
        await back();
        await tap('终端策略');
        await capture('terminal', '会话策略', '终端显示');
        assert.equal(apiRequests, 0);
        assert.deepEqual(errors, []);
      } catch (error) {
        await page.screenshot({path: out + '/debug-' + name + '.png'});
        fs.writeFileSync(out + '/debug-' + name + '.json', JSON.stringify({
          errors, apiRequests, completed: report,
          semantics: await page.locator('flt-semantics').allTextContents(),
        }, null, 2));
        throw error;
      } finally {
        await page.close();
      }
      console.log('PASS settings visual navigation ' + name + ': 15 real Flutter routes, readonly synthetic transport');
    }
    fs.writeFileSync(out + '/visual-navigation-proof.json',
        JSON.stringify({screens: report, count: report.length, nativeRegression: false}, null, 2));
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
