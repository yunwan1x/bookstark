const { chromium } = require("playwright"),
  assert = require("node:assert/strict"),
  fs = require("node:fs"),
  path = require("node:path"),
  { execFileSync } = require("node:child_process");
(async () => {
  const out =
      process.env.BOOKSTARK_SSH_ARTIFACTS ||
      path.resolve(__dirname, "../../../../artifacts/ssh-terminal"),
    origin = process.env.BOOKSTARK_TEST_ORIGIN || "http://127.0.0.1:18281",
    id = JSON.parse(fs.readFileSync(out + "/local-install.json")).id,
    host = process.env.BOOKSTARK_SSH_REAL_HOST,
    port = process.env.BOOKSTARK_SSH_REAL_PORT || "22",
    user = process.env.BOOKSTARK_SSH_REAL_USER,
    key = process.env.BOOKSTARK_SSH_REAL_KEY;
  assert.ok(
    host && user && key,
    "Set SSH test host, user and private key environment variables",
  );
  const cli = (command) =>
    execFileSync(
      "ssh",
      ["-p", port, "-o", "BatchMode=yes", user + "@" + host, command],
      { encoding: "utf8" },
    ).trim();
  const fingerprints = cli(
    'for key in /etc/ssh/ssh_host_*_key.pub; do ssh-keygen -lf "$key" -E sha256; done',
  )
    .split("\n")
    .map((line) => line.split(/\s+/)[1]);
  const expectedBash = cli('readlink -f "$(command -v bash)"'),
    expectedSh = cli("readlink -f /bin/sh");
  const browser = await chromium.launch({ args: ["--no-sandbox"] }),
    context = await browser.newContext({
      viewport: { width: 1440, height: 1100 },
      locale: "zh-CN",
    }),
    page = await context.newPage(),
    errors = [];
  page.on("pageerror", (e) => errors.push(e.message));
  page.on("dialog", (d) => d.accept());
  await context.addInitScript(() => {
    if (window === top && navigator.serviceWorker)
      navigator.serviceWorker.register = () => new Promise(() => {});
  });
  await context.addCookies([{ name: "lang", value: "zh", url: origin }]);
  async function command(f, cmd, marker) {
    await f
      .locator(".terminal-panel:not([hidden]) .xterm-helper-textarea")
      .focus();
    await page.keyboard.type(cmd);
    await page.keyboard.press("Enter");
    await f.locator("body").evaluate(async (body, marker) => {
      const t = window.__qaTerms.find(
        (t) => !t.element.closest(".terminal-panel").hidden,
      );
      for (let n = 0; n < 150; n++) {
        let text = "";
        for (let i = 0; i < t.buffer.active.length; i++)
          text += t.buffer.active.getLine(i).translateToString(true) + "\n";
        if (text.includes(marker)) return;
        await new Promise((r) => setTimeout(r, 100));
      }
      throw Error("Selected shell did not produce " + marker);
    }, marker);
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
    await page.goto(origin + "/tools/run/" + id);
    const f = page.frameLocator("#marketFrameHost iframe");
    await f.locator("#shell").waitFor();
    await f.locator("body").evaluate(() => {
      const Native = window.Terminal;
      window.__qaTerms = [];
      window.Terminal = class extends Native {
        constructor(opts) {
          super(opts);
          window.__qaTerms.push(this);
        }
      };
    });
    assert.deepEqual(
      await f
        .locator("#shell option")
        .evaluateAll((options) => options.map((o) => o.value)),
      ["", "sh", "bash", "zsh", "fish", "custom"],
    );
    async function setup(selection, custom = "") {
      await f.locator("#newConnection").click();
      await f
        .locator("#hostName")
        .fill(selection === "bash" ? "Bash 服务器" : "自定义 Shell");
      await f.locator("#host").fill(host);
      await f.locator("#port").fill(port);
      await f.locator("#username").fill(user);
      await f.locator("#shell").selectOption(selection);
      if (selection === "custom") await f.locator("#customShell").fill(custom);
      await f.locator("[name=auth][value=key]").check();
    }
    async function connect() {
      await f.locator("#privateKey").setInputFiles(key);
      await f
        .locator("#keyName")
        .filter({ hasText: path.basename(key) })
        .waitFor();
      await f.locator("#connect").click();
      await f.locator("#hostFingerprint").waitFor({ timeout: 40000 });
      assert.ok(
        fingerprints.includes(
          await f.locator("#hostFingerprint").textContent(),
        ),
      );
      await page.setViewportSize({ width: 1280, height: 900 });
      await page.waitForTimeout(250);
      await f.locator("[data-trust=once]").click();
    }
    await setup("bash");
    await f.locator("#saveHost").click();
    await f.locator("#newConnection").click();
    await f.locator(".host-row").filter({ hasText: "Bash 服务器" }).click();
    assert.equal(await f.locator("#shell").inputValue(), "bash");
    await page.screenshot({ path: out + "/12-shell-form.png" });
    await connect();
    await f
      .locator("#sessionStatus")
      .filter({ hasText: "已连接" })
      .waitFor({ timeout: 30000 });
    await command(
      f,
      "printf 'BASH_%s_END\\n' \"$(readlink /proc/$$/exe)\"",
      "BASH_" + expectedBash + "_END",
    );
    const dimensions = await f.locator("body").evaluate(() => {
      const t = window.__qaTerms.find(
        (t) => !t.element.closest(".terminal-panel").hidden,
      );
      return t.rows + " " + t.cols;
    });
    await command(
      f,
      "printf 'CONNECT_PTY_%s_END\\n' \"$(stty size)\"",
      "CONNECT_PTY_" + dimensions + "_END",
    );
    console.log("RESIZE DURING HOST KEY CONFIRM VERIFIED", dimensions);
    console.log("REAL PRESET BASH VERIFIED", expectedBash);
    await setup("custom", "/bin/sh");
    await f.locator("#saveHost").click();
    await f.locator("#newConnection").click();
    await f.locator(".host-row").filter({ hasText: "自定义 Shell" }).click();
    assert.equal(await f.locator("#shell").inputValue(), "custom");
    assert.equal(await f.locator("#customShell").inputValue(), "/bin/sh");
    await connect();
    await f
      .locator("#sessionStatus")
      .filter({ hasText: "已连接" })
      .waitFor({ timeout: 30000 });
    await command(
      f,
      "printf 'CUSTOM_%s_END\\n' \"$(readlink /proc/$$/exe)\"",
      "CUSTOM_" + expectedSh + "_END",
    );
    console.log("REAL CUSTOM /bin/sh VERIFIED", expectedSh);
    await page.screenshot({ path: out + "/13-custom-shell-terminal.png" });
    await setup("custom", "relative/program");
    await f.locator("#privateKey").setInputFiles(key);
    await f
      .locator("#keyName")
      .filter({ hasText: path.basename(key) })
      .waitFor();
    await f.locator("#connect").click();
    assert.match(await f.locator("#formError").textContent(), /绝对路径/);
    console.log("RELATIVE CUSTOM PROGRAM REJECTED");
    await setup("custom", "/bookstark-qa-shell-does-not-exist");
    await connect();
    await f.locator("#reconnect").waitFor({ timeout: 30000 });
    assert.match(
      await f.locator("#connectionMessage").textContent(),
      /127|Shell 已退出/,
    );
    console.log("MISSING SHELL HAS EXIT ERROR");
    await setup("custom", "/usr/local/bin/fish");
    await page.setViewportSize({ width: 320, height: 844 });
    assert.equal(
      await f
        .locator("body")
        .evaluate(() => document.documentElement.scrollWidth > innerWidth),
      false,
    );
    await f.locator("#shell").scrollIntoViewIfNeeded();
    await page.screenshot({ path: out + "/14-shell-mobile.png" });
    assert.deepEqual(errors, []);
    fs.writeFileSync(
      out + "/shell-result.json",
      JSON.stringify(
        {
          id,
          presetBash: true,
          customSh: true,
          shellSettingsPersisted: true,
          invalidRelativeRejected: true,
          unavailableProgramError: true,
          mobile320: true,
          errors,
        },
        null,
        2,
      ),
    );
  } finally {
    await browser.close();
  }
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
