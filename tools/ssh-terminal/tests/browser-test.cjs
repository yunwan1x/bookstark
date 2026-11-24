const { chromium } = require("playwright"),
  assert = require("node:assert/strict"),
  fs = require("node:fs"),
  path = require("node:path");
(async () => {
  const out =
      process.env.BOOKSTARK_SSH_ARTIFACTS ||
      require("node:path").resolve(
        __dirname,
        "../../../../artifacts/ssh-terminal",
      ),
    origin = process.env.BOOKSTARK_TEST_ORIGIN || "http://127.0.0.1:18281";
  const browser = await chromium.launch({ args: ["--no-sandbox"] }),
    context = await browser.newContext({
      viewport: { width: 1440, height: 1000 },
    }),
    page = await context.newPage();
  const errors = [];
  page.on("pageerror", (e) => {
    errors.push(e.message);
    console.log("ERROR", e.message);
  });
  page.on("console", (m) => {
    if (m.type() === "error") console.log("CONSOLE", m.text());
  });
  await context.addInitScript(() => {
    if (window === top && navigator.serviceWorker)
      navigator.serviceWorker.register = () => new Promise(() => {});
  });
  await context.addCookies([{ name: "lang", value: "zh", url: origin }]);
  async function api(p, method = "GET", data) {
    const csrf = (
        await (await context.request.get(origin + "/api/csrf-token")).json()
      ).csrf_token,
      r = await context.request.fetch(origin + p, {
        method,
        data,
        headers: { "X-CSRF-Token": csrf },
      });
    assert.ok(r.ok(), p + ": " + (await r.text()));
    return r.json();
  }
  try {
    assert.equal(
      (
        await context.request.post(origin + "/api/login", {
          data: { account: "admin", password: "admin" },
        })
      ).status(),
      200,
    );
    const settings = await api("/api/tool-market/settings");
    await api("/api/tool-market/settings", "PUT", {
      ...settings,
      socket_proxy: true,
      public_url: origin + "/market",
    });
    const csrf = (
      await (await context.request.get(origin + "/api/csrf-token")).json()
    ).csrf_token;
    const upload = await context.request.post(origin + "/api/tool-packages", {
      multipart: {
        file: {
          name: "ssh-terminal.zip",
          mimeType: "application/zip",
          buffer: fs.readFileSync(
            path.join(out, "bookstark-ssh-terminal-1.0.1.zip"),
          ),
        },
      },
      headers: { "X-CSRF-Token": csrf },
    });
    assert.equal(upload.status(), 200, await upload.text());
    const { id, package: pkg } = await upload.json(),
      config = JSON.parse(pkg.config ? JSON.stringify(pkg.config) : "{}");
    console.log("UPLOADED", id, pkg.files.length);
    const payload = {
      ...config,
      title: "SSH 终端",
      version: config.version || "1.0.1",
      category: "development",
      access: "login",
      package: pkg.token,
      entry: "index.html",
      permissions: {
        socket_tcp: true,
        network: false,
        forms: true,
        clipboard_read: true,
        clipboard_write: true,
      },
    };
    await api("/api/tool-publications/" + id, "POST", payload);
    const tool = await api("/api/tool-market/" + id);
    await api("/api/tool-installs/" + id, "PUT", {
      revision: tool.revision,
      hash: tool.hash,
    });
    fs.writeFileSync(
      path.join(out, "local-install.json"),
      JSON.stringify({ id, toolRevision: tool.revision }),
    );
    await page.goto(origin + "/tools/run/" + id);
    const f = page.frameLocator("#marketFrameHost iframe");
    await f.locator("#host").waitFor();
    await f.locator("body").evaluate(() => {
      const Native = window.Terminal;
      window.__qaTerms = [];
      window.Terminal = class extends Native {
        constructor(options) {
          super(options);
          window.__qaTerms.push(this);
        }
      };
    });
    await f.locator("#language").click();
    if ((await f.locator("#formTitle").textContent()) === "New connection")
      await f.locator("#language").click();
    await f.locator("#hostName").fill("BookStark 测试服务器");
    await f.locator("#host").fill("127.0.0.1");
    await f.locator("#port").fill("18222");
    await f.locator("#username").fill("tester");
    await f.locator("#password").fill("terminal-test-only");
    await f.locator("#saveHost").click();
    await page.screenshot({ path: out + "/01-connection.png" });
    await f.locator("#connect").click();
    await f.locator("#hostFingerprint").waitFor({ timeout: 40000 });
    await page.screenshot({ path: out + "/02-host-key.png" });
    await f.locator("[data-trust=save]").click();
    await f
      .locator("#sessionStatus")
      .filter({ hasText: "已连接" })
      .waitFor({ timeout: 30000 });
    console.log("PASSWORD CONNECTED");
    async function command(text, marker) {
      await f
        .locator(".terminal-panel:not([hidden]) .xterm-helper-textarea")
        .focus();
      await page.keyboard.type(text);
      await page.keyboard.press("Enter");
      await f.locator("body").evaluate(async (body, marker) => {
        const term = window.__qaTerms.find(
          (t) => !t.element.parentElement.hidden,
        );
        for (let n = 0; n < 150; n++) {
          let text = "";
          for (let i = 0; i < term.buffer.active.length; i++)
            text +=
              term.buffer.active.getLine(i).translateToString(true) + "\n";
          if (text.includes(marker)) return;
          await new Promise((r) => setTimeout(r, 100));
        }
        let text = "";
        for (let i = 0; i < term.buffer.active.length; i++)
          text += term.buffer.active.getLine(i).translateToString(true) + "\n";
        throw Error("Missing marker: " + marker + " transcript: " + text);
      }, marker);
    }
    await command("printf 'SSH_%s_OK\\n' PASSWORD", "SSH_PASSWORD_OK");
    await page.screenshot({ path: out + "/03-terminal.png" });
    await f.locator("#sidebarToggle").click();
    await page.waitForTimeout(220);
    assert.equal(
      await f
        .locator("#sidebar")
        .evaluate((el) => el.getBoundingClientRect().width),
      52,
    );
    await command("printf 'SSH_%s_OK\\n' COLLAPSED", "SSH_COLLAPSED_OK");
    await page.screenshot({ path: out + "/04-collapsed.png" });
    await f.locator("#sidebarToggle").click();
    await f.locator("#newConnection").click();
    await f.locator("#hostName").fill("私钥会话");
    await f.locator("#host").fill("127.0.0.1");
    await f.locator("#port").fill("18222");
    await f.locator("#username").fill("tester");
    await f.locator("[name=auth][value=key]").check();
    await f.locator("#privateKey").setInputFiles(out + "/test-key");
    await f.locator("#keyName").filter({ hasText: "test-key" }).waitFor();
    await f.locator("#connect").click();
    await f
      .locator("#sessionStatus")
      .filter({ hasText: "已连接" })
      .waitFor({ timeout: 30000 });
    await command("printf 'SSH_%s_OK\\n' KEY", "SSH_KEY_OK");
    assert.equal(await f.locator("[role=tab]").count(), 2);
    console.log("KEY CONNECTED");
    await f.locator("#largerFont").click();
    await command("printf 'SSH_%s_OK\\n' RESIZED", "SSH_RESIZED_OK");
    await f.locator("#searchTerminal").click();
    await f.locator("#terminalQuery").fill("SSH_KEY_OK");
    await f.locator("#findNext").click();
    assert.match(await f.locator("#searchResult").textContent(), /\d+ \/ \d+/);
    await f.locator("#closeSearch").click();
    await f.locator("#disconnect").click();
    await f.locator("#bs-dialog-overlay.active").waitFor();
    await f.locator("#bs-dialog-overlay button").last().click();
    await f.locator("#sessionStatus").filter({ hasText: "已断开" }).waitFor();
    await f.locator("#reconnect").click();
    assert.equal(await f.locator("#password").inputValue(), "");
    assert.equal(await f.locator("#privateKey").inputValue(), "");
    await f.locator("#privateKey").setInputFiles(out + "/test-key");
    await f.locator("#keyName").filter({ hasText: "test-key" }).waitFor();
    await f.locator("#connect").click();
    await f
      .locator("#sessionStatus")
      .filter({ hasText: "已连接" })
      .waitFor({ timeout: 30000 });
    await command("printf 'SSH_%s_OK\\n' RECONNECTED", "SSH_RECONNECTED_OK");
    assert.equal(await f.locator("[role=tab]").count(), 2);
    console.log("RECONNECTED");
    for (const [width, name] of [
      [390, "05-mobile"],
      [320, "06-mobile-small"],
    ]) {
      await page.setViewportSize({ width, height: 844 });
      assert.equal(
        await f
          .locator("body")
          .evaluate(() => document.documentElement.scrollWidth > innerWidth),
        false,
      );
      await f.locator("#mobileToggle").click();
      await page.screenshot({ path: out + "/" + name + "-sidebar.png" });
      await f.locator("#sidebarToggle").click();
      await command("printf 'SSH_%s_OK\\n' MOBILE", "SSH_MOBILE_OK");
      await page.screenshot({ path: out + "/" + name + ".png" });
    }
    await page.setViewportSize({ width: 1440, height: 1000 });
    const stored = await f
      .locator("body")
      .evaluate(() =>
        Object.fromEntries(
          Object.keys(localStorage).map((k) => [k, localStorage.getItem(k)]),
        ),
      );
    assert.ok(!JSON.stringify(stored).includes("terminal-test-only"));
    assert.ok(!JSON.stringify(stored).includes("PRIVATE KEY"));
    console.log("NO SECRET STORAGE");
    await page
      .locator("#toolRuntimeMore [data-bs-action-dropdown-toggle]")
      .click();
    const download = page.waitForEvent("download");
    await page.locator("#toolRuntimeExportPackage").click();
    await (await download).saveAs(out + "/exported-ssh-terminal.zip");
    console.log("EXPORTED");
    assert.deepEqual(errors, []);
    fs.writeFileSync(
      out + "/browser-result.json",
      JSON.stringify(
        {
          id,
          password: true,
          key: true,
          reconnect: true,
          collapse: true,
          mobile320: true,
          noSecretStorage: true,
          export: true,
          errors,
        },
        null,
        2,
      ),
    );
  } finally {
    page.removeAllListeners("dialog");
    page.on("dialog", (d) => d.accept());
    await browser.close();
  }
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
