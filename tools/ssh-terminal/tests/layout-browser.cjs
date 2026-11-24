const { chromium } = require("playwright"),
  assert = require("node:assert/strict"),
  fs = require("node:fs");
(async () => {
  const out =
      process.env.BOOKSTARK_SSH_ARTIFACTS ||
      require("node:path").resolve(
        __dirname,
        "../../../../artifacts/ssh-terminal",
      ),
    origin = process.env.BOOKSTARK_TEST_ORIGIN || "http://127.0.0.2:18281",
    id = JSON.parse(fs.readFileSync(out + "/local-install.json")).id,
    browser = await chromium.launch({ args: ["--no-sandbox"] }),
    context = await browser.newContext({
      viewport: { width: 1280, height: 900 },
      locale: "zh-CN",
    }),
    page = await context.newPage(),
    errors = [];
  page.on("pageerror", (e) => errors.push(e.message));
  page.on("dialog", (d) => d.accept());
  await context.request.post(origin + "/api/login", {
    data: { account: "admin", password: "admin" },
  });
  await page.goto(origin + "/tools/run/" + id);
  const f = page.frameLocator("#marketFrameHost iframe");
  await f.locator("#host").waitFor();
  await f.locator("body").evaluate(() => {
    const Native = Terminal;
    window.Terminal = class extends Native {
      constructor(o) {
        super(o);
        window.__qaTerm = this;
      }
    };
  });
  await f.locator("#host").fill("127.0.0.1");
  await f.locator("#port").fill("18222");
  await f.locator("#username").fill("tester");
  await f.locator("#password").fill("terminal-test-only");
  await f.locator("#connect").click();
  await f.locator(".xterm-screen").waitFor();
  if (await f.locator("#hostFingerprint").isVisible())
    await f.locator("[data-trust=once]").click();
  const results = [];
  async function check(label) {
    await page.waitForTimeout(300);
    const result = await f.locator("body").evaluate(async () => {
      const t = window.__qaTerm;
      await new Promise((resolve) =>
        t.write(
          "\x1b[2J\x1b[H" +
            Array.from(
              { length: t.rows },
              (_, i) => "ROW_" + String(i + 1).padStart(3, "0"),
            ).join("\r\n"),
          resolve,
        ),
      );
      const rect = (s) => {
        const r = document.querySelector(s).getBoundingClientRect();
        return { top: r.top, bottom: r.bottom, height: r.height };
      };
      return {
        rows: t.rows,
        stack: rect(".terminal-stack"),
        screen: rect(".xterm-screen"),
        panel: rect(".terminal-panel"),
        status: rect(".terminal-status"),
        keys:
          document.querySelector(".extra-keys").getBoundingClientRect().height >
          0
            ? rect(".extra-keys")
            : null,
      };
    });
    results.push({ label, ...result });
    console.log(JSON.stringify(results.at(-1)));
    const boundary = result.keys?.top ?? result.status.top;
    assert.ok(
      result.screen.bottom <= boundary + 0.5,
      `${label}: terminal bottom ${result.screen.bottom} overlaps footer area ${boundary}`,
    );
    assert.ok(
      result.screen.bottom <= result.stack.bottom + 0.5,
      `${label}: terminal exceeds stack`,
    );
    await page.screenshot({ path: out + "/layout-" + label + ".png" });
  }
  try {
    await check("desktop");
    for (const [width, height, label] of [
      [390, 844, "mobile"],
      [320, 568, "small"],
      [1280, 650, "short-desktop"],
    ]) {
      await page.setViewportSize({ width, height });
      await check(label);
    }
    for (let i = 0; i < 6; i++) await f.locator("#largerFont").click();
    await check("large-font");
    assert.deepEqual(errors, []);
    fs.writeFileSync(
      out + "/layout-result.json",
      JSON.stringify({ id, results, errors }, null, 2),
    );
  } finally {
    await browser.close();
  }
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
