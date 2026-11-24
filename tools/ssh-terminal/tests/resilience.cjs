const { chromium } = require("playwright"),
  assert = require("node:assert/strict"),
  fs = require("node:fs"),
  path = require("node:path");
(async () => {
  const out =
      process.env.BOOKSTARK_SSH_ARTIFACTS ||
      path.resolve(__dirname, "../../../../artifacts/ssh-terminal"),
    origin = process.env.BOOKSTARK_TEST_ORIGIN || "http://127.0.0.1:18281",
    id = JSON.parse(fs.readFileSync(out + "/local-install.json")).id;
  const browser = await chromium.launch({ args: ["--no-sandbox"] }),
    context = await browser.newContext({
      viewport: { width: 1280, height: 900 },
    }),
    page = await context.newPage(),
    errors = [];
  page.on("pageerror", (e) => errors.push(e.message));
  page.on("dialog", (d) => d.accept());
  await context.addInitScript(() => {
    if (window === top && navigator.serviceWorker)
      navigator.serviceWorker.register = () => new Promise(() => {});
  });
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
  async function load() {
    await page.goto(origin + "/tools/run/" + id);
    const f = page.frameLocator("#marketFrameHost iframe");
    await f.locator("#host").waitFor();
    await f.locator("body").evaluate(() => {
      const Native = window.Terminal;
      window.Terminal = class extends Native {
        constructor(o) {
          super(o);
          window.__qaTerm = this;
        }
      };
    });
    return f;
  }
  async function fill(f, user = "tester") {
    await f.locator("#host").fill("127.0.0.1");
    await f.locator("#port").fill("18222");
    await f.locator("#username").fill(user);
    await f.locator("#password").fill("terminal-test-only");
  }
  async function command(f, text, marker) {
    await f
      .locator(".terminal-panel:not([hidden]) .xterm-helper-textarea")
      .focus();
    await page.keyboard.type(text);
    await page.keyboard.press("Enter");
    await f.locator("body").evaluate(async (body, marker) => {
      for (let n = 0; n < 150; n++) {
        const t = window.__qaTerm;
        let text = "";
        for (let i = 0; i < t.buffer.active.length; i++)
          text += t.buffer.active.getLine(i).translateToString(true) + "\n";
        if (text.includes(marker)) return;
        await new Promise((r) => setTimeout(r, 100));
      }
      throw Error("Missing output " + marker);
    }, marker);
  }
  try {
    await context.request.post(origin + "/api/login", {
      data: { account: "admin", password: "admin" },
    });
    let f = await load();
    await f.locator("body").evaluate(() => {
      const connect = BookStark.sockets.connect.bind(BookStark.sockets);
      let first = true;
      BookStark.sockets.connect = async (options) => {
        const socket = await connect(options);
        if (first) {
          first = false;
          window.__qaHeldSocket = socket;
          await new Promise((resolve) => (window.__qaRelease = resolve));
        }
        return socket;
      };
    });
    await fill(f, "ignored-old-user");
    await f.locator("#connect").click();
    await f.locator("body").evaluate(async () => {
      for (let n = 0; n < 100 && !window.__qaRelease; n++)
        await new Promise((r) => setTimeout(r, 50));
      if (!window.__qaRelease) throw Error("First socket not held");
    });
    await f.locator("#disconnect").click();
    await f.locator("#bs-confirm-ok").click();
    await f.locator("#reconnect").click();
    await fill(f);
    assert.ok(await f.locator("#connect").isEnabled());
    await f.locator("#connect").click();
    await f
      .locator("#sessionStatus")
      .filter({ hasText: /已连接|Connected/ })
      .waitFor({ timeout: 30000 });
    await command(f, "printf 'RACE_%s_OK\\n' NEW", "RACE_NEW_OK");
    await f.locator("body").evaluate(() => window.__qaRelease());
    await f.locator("body").evaluate(async () => {
      const closed = await window.__qaHeldSocket.closed;
      if (!closed) throw Error("Stale socket not closed");
    });
    await command(f, "printf 'RACE_%s_OK\\n' SURVIVED", "RACE_SURVIVED_OK");
    console.log("STALE CONNECT CANNOT OVERWRITE RECONNECT");
    await command(
      f,
      "printf '中文 MATCH_7F MATCH_7F\\n'",
      "中文 MATCH_7F MATCH_7F",
    );
    await f.locator("#searchTerminal").click();
    await f.locator("#terminalQuery").fill("MATCH_7F");
    const positions = [];
    for (let i = 0; i < 4; i++) {
      await f.locator("#findNext").click();
      const result = await f
        .locator("body")
        .evaluate(() => ({
          selection: window.__qaTerm.getSelection(),
          position: window.__qaTerm.getSelectionPosition(),
        }));
      assert.equal(result.selection, "MATCH_7F");
      positions.push(result.position);
    }
    assert.ok(
      positions.some((p, i) =>
        positions.some(
          (other, j) =>
            i !== j &&
            p.start.y === other.start.y &&
            p.start.x !== other.start.x,
        ),
      ),
    );
    console.log("SEARCH SAME LINE AND CJK COLUMNS VERIFIED");
    let settings = await api("/api/tool-market/settings");
    await api("/api/tool-market/settings", "PUT", {
      ...settings,
      socket_proxy: false,
    });
    try {
      f = await load();
      await fill(f);
      await f.locator("#connect").click();
      await f.locator("#reconnect").waitFor({ timeout: 30000 });
      assert.match(
        await f.locator("#connectionMessage").textContent(),
        /TCP 代理|TCP proxy/,
      );
      console.log("DISABLED PROXY ERROR VERIFIED");
    } finally {
      await api("/api/tool-market/settings", "PUT", settings);
    }
    await f.locator("body").evaluate(()=>localStorage.setItem("ssh.language","en"));await page.waitForTimeout(250);
    await page.route("**/ssh.wasm", (route) => route.abort());
    f = await load();
    await fill(f);
    await f.locator("#connect").click();
    await f.locator("#reconnect").waitFor({ timeout: 30000 });
    assert.match(
      await f.locator("#connectionMessage").textContent(),
      /SSH module failed to load/,
    );
    await page.unroute("**/ssh.wasm");
    console.log("MODULE LOAD FAILURE VERIFIED");
    await page.screenshot({ path: out + "/11-module-error.png" });
    assert.deepEqual(errors, []);
    fs.writeFileSync(
      out + "/resilience-result.json",
      JSON.stringify(
        {
          id,
          staleConnectIsolation: true,
          searchSameLine: true,
          searchWideCharacters: true,
          proxyDisabled: true,
          moduleFailure: true,
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
