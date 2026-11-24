const { chromium } = require("playwright"),
  assert = require("node:assert/strict"),
  fs = require("node:fs"),
  path = require("node:path"),
  { execFileSync } = require("node:child_process");
(async () => {
  const out =
      process.env.BOOKSTARK_SSH_ARTIFACTS ||
      require("node:path").resolve(
        __dirname,
        "../../../../artifacts/ssh-terminal",
      ),
    origin = process.env.BOOKSTARK_TEST_ORIGIN || "http://127.0.0.1:18281",
    previous = JSON.parse(fs.readFileSync(out + "/local-install.json")),
    browser = await chromium.launch({ args: ["--no-sandbox"] }),
    context = await browser.newContext({
      viewport: { width: 1440, height: 1000 },
    }),
    page = await context.newPage(),
    errors = [];
  page.on("pageerror", (e) => {
    errors.push(e.message);
    console.log("ERROR", e.message);
  });
  page.on("dialog", (d) => d.accept());
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
  let id = previous.id;
  async function load() {
    await page.goto(origin + "/tools/run/" + id);
    const f = page.frameLocator("#marketFrameHost iframe");
    await f.locator("#host").waitFor();
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
    return f;
  }
  async function editor(
    f,
    auth = "password",
    cfg = { host: "127.0.0.1", port: "18222", user: "tester" },
  ) {
    await f.locator("#newConnection").click();
    await f.locator("#hostName").fill("SSH 测试");
    await f.locator("#host").fill(cfg.host);
    await f.locator("#port").fill(cfg.port);
    await f.locator("#username").fill(cfg.user);
    await f.locator("[name=auth][value=" + auth + "]").check();
  }
  async function closed(f, match) {
    await f.locator("#reconnect").waitFor({ state: "visible", timeout: 30000 });
    assert.match(await f.locator("#connectionMessage").textContent(), match);
  }
  async function connected(f) {
    await f
      .locator("#sessionStatus")
      .filter({ hasText: /已连接|Connected/ })
      .waitFor({ timeout: 30000 });
  }
  async function command(f, cmd, marker) {
    await f
      .locator(".terminal-panel:not([hidden]) .xterm-helper-textarea")
      .focus();
    await page.keyboard.type(cmd);
    await page.keyboard.press("Enter");
    await f.locator("body").evaluate(
      async (body, { marker }) => {
        const term = window.__qaTerms.find(
          (t) => !t.element.closest(".terminal-panel").hidden,
        );
        for (let n = 0; n < 200; n++) {
          let text = "";
          for (let i = 0; i < term.buffer.active.length; i++)
            text +=
              term.buffer.active.getLine(i).translateToString(true) + "\n";
          if (text.includes(marker)) return;
          await new Promise((r) => setTimeout(r, 100));
        }
        throw Error("Missing SSH output: " + marker);
      },
      { marker },
    );
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
    let f = await load();
    // Changed trusted key must show both fingerprints and refuse cancellation.
    await f.locator("body").evaluate(() => {
      const known = JSON.parse(localStorage.getItem("ssh.known-hosts") || "{}");
      known[JSON.stringify(["127.0.0.1", 18222])] = {
        key: "deliberately-replaced-key",
        fingerprint: "SHA256:QA-previous-host-key",
      };
      localStorage.setItem("ssh.known-hosts", JSON.stringify(known));
    });
    await page.waitForTimeout(300);
    f = await load();
    await editor(f);
    await f.locator("#password").fill("terminal-test-only");
    await f.locator("#connect").click();
    await f.locator("#hostFingerprint").waitFor();
    assert.match(
      await f.locator("dialog").textContent(),
      /主机密钥已变化|Host key changed/,
    );
    assert.match(
      await f.locator("dialog").textContent(),
      /SHA256:QA-previous-host-key/,
    );
    await page.screenshot({ path: out + "/07-changed-key.png" });
    await f.locator("[data-trust=cancel]").click();
    await closed(f, /主机密钥|Host key/);
    assert.ok(
      (
        await f
          .locator("body")
          .evaluate(() => localStorage.getItem("ssh.known-hosts"))
      ).includes("deliberately-replaced-key"),
    );
    console.log("CHANGED KEY CANCEL PASSED");
    await f.locator("#reconnect").click();
    await f.locator("#password").fill("terminal-test-only");
    await f.locator("#connect").click();
    await f.locator("#hostFingerprint").waitFor();
    await f.locator("[data-trust=once]").click();
    await connected(f);
    assert.ok(
      (
        await f
          .locator("body")
          .evaluate(() => localStorage.getItem("ssh.known-hosts"))
      ).includes("deliberately-replaced-key"),
    );
    await command(f, "printf 'ONCE_%s_OK\\n' TRUST", "ONCE_TRUST_OK");
    console.log("ONCE TRUST NOT SAVED");
    await f.locator("#disconnect").click();
    await f.locator("#bs-confirm-ok").click();
    await closed(f, /连接已断开|Disconnected/);
    // Wrong password with a freshly verified key, then encrypted-key failures.
    await editor(f);
    await f.locator("#password").fill("wrong-password-test");
    await f.locator("#connect").click();
    await f.locator("#hostFingerprint").waitFor();
    await f.locator("[data-trust=save]").click();
    await closed(f, /authenticate|认证/);
    console.log("WRONG PASSWORD REJECTED");
    await editor(f, "key");
    await f.locator("#privateKey").setInputFiles({
      name: "invalid-key",
      mimeType: "application/octet-stream",
      buffer: Buffer.from("this is not a private key"),
    });
    await f.locator("#keyName").filter({ hasText: "invalid-key" }).waitFor();
    await f.locator("#connect").click();
    await closed(f, /无法解析私钥|Cannot parse/);
    console.log("INVALID KEY REJECTED");
    await f.locator("#language").click();
    if ((await f.locator("#language").textContent()) === "EN")
      await f.locator("#language").click();
    await editor(f, "key");
    await f.locator("#privateKey").setInputFiles(out + "/test-key-encrypted");
    await f.locator("#keyName").filter({ hasText: "encrypted" }).waitFor();
    await f.locator("#passphrase").fill("wrong-passphrase");
    await f.locator("#connect").click();
    await closed(f, /Cannot parse the private key/);
    console.log("ENCRYPTED KEY WRONG PASSPHRASE REJECTED IN ENGLISH");
    await f.locator("#reconnect").click();
    await f.locator("#privateKey").setInputFiles(out + "/test-key-encrypted");
    await f.locator("#keyName").filter({ hasText: "encrypted" }).waitFor();
    await f.locator("#passphrase").fill("test-key-passphrase");
    await f.locator("#connect").click();
    await connected(f);
    await command(f, "printf 'ENCRYPTED_%s_OK\\n' KEY", "ENCRYPTED_KEY_OK");
    console.log("ENCRYPTED KEY CONNECTED");
    // Exercise a real server, compare host key to a public key read over trusted SSH.
    const realSSH = Boolean(
      process.env.BOOKSTARK_SSH_REAL_HOST &&
        process.env.BOOKSTARK_SSH_REAL_USER &&
        process.env.BOOKSTARK_SSH_REAL_KEY,
    );
    if (realSSH) {
      const fingerprints = execFileSync(
        "ssh",
        [
          "-p",
          process.env.BOOKSTARK_SSH_REAL_PORT || "22",
          "-o",
          "BatchMode=yes",
          process.env.BOOKSTARK_SSH_REAL_USER +
            "@" +
            process.env.BOOKSTARK_SSH_REAL_HOST,
          'for key in /etc/ssh/ssh_host_*_key.pub; do ssh-keygen -lf \"$key\" -E sha256; done',
        ],
        { encoding: "utf8" },
      )
        .trim()
        .split("\n")
        .map((line) => line.trim().split(/\s+/)[1]);
      await editor(f, "key", {
        host: process.env.BOOKSTARK_SSH_REAL_HOST,
        port: process.env.BOOKSTARK_SSH_REAL_PORT || "22",
        user: process.env.BOOKSTARK_SSH_REAL_USER,
      });
      await f
        .locator("#privateKey")
        .setInputFiles(process.env.BOOKSTARK_SSH_REAL_KEY);
      await f
        .locator("#keyName")
        .filter({ hasText: path.basename(process.env.BOOKSTARK_SSH_REAL_KEY) })
        .waitFor();
      await f.locator("#connect").click();
      await f.locator("#hostFingerprint").waitFor({ timeout: 40000 });
      assert.ok(
        fingerprints.includes(
          await f.locator("#hostFingerprint").textContent(),
        ),
        "Host fingerprint must match a public key read through trusted SSH",
      );
      await f.locator("[data-trust=once]").click();
      await connected(f);
      await command(f, "printf 'REAL_%s_OK\\n' SSH", "REAL_SSH_OK");
      console.log("REAL SERVER SSH CONNECTED");
      for (const [width, height] of [
        [1280, 900],
        [800, 650],
        [390, 844],
      ]) {
        await page.setViewportSize({ width, height });
        await page.waitForTimeout(350);
        const dimensions = await f.locator("body").evaluate(() => {
          const t = window.__qaTerms.find(
            (t) => !t.element.closest(".terminal-panel").hidden,
          );
          return { cols: t.cols, rows: t.rows };
        });
        const size = dimensions.rows + " " + dimensions.cols;
        await command(
          f,
          "printf 'PTY_%s_END\\n' \"$(stty size)\"",
          "PTY_" + size + "_END",
        );
        console.log("REAL PTY SIZE VERIFIED", size);
      }
      await f
        .locator(".terminal-panel:not([hidden]) .xterm-helper-textarea")
        .focus();
      await page.keyboard.type("sleep 30");
      await page.keyboard.press("Enter");
      await page.waitForTimeout(300);
      await page.keyboard.press("Control+c");
      await command(f, "printf 'CTRL_%s_OK\\n' C", "CTRL_C_OK");
      console.log("REAL CTRL C VERIFIED");
      await page.screenshot({ path: out + "/08-real-server-mobile.png" });
      await page.setViewportSize({ width: 1440, height: 1000 });
      await command(
        f,
        "printf 'ORDER_%s_OK\\n' 0123456789abcdefghijklmnopqrstuvwxyz",
        "ORDER_0123456789abcdefghijklmnopqrstuvwxyz_OK",
      );
      await page.screenshot({ path: out + "/09-real-server-terminal.png" });
    }
    // Re-import the ZIP downloaded from the installed tool, not the build ZIP.
    const csrf = (
      await (await context.request.get(origin + "/api/csrf-token")).json()
    ).csrf_token;
    const upload = await context.request.post(origin + "/api/tool-packages", {
      multipart: {
        file: {
          name: "exported-terminal.zip",
          mimeType: "application/zip",
          buffer: fs.readFileSync(out + "/exported-ssh-terminal.zip"),
        },
      },
      headers: { "X-CSRF-Token": csrf },
    });
    assert.equal(upload.status(), 200, await upload.text());
    const { id: restoredID, package: pkg } = await upload.json(),
      config = pkg.config;
    await api("/api/tool-publications/" + restoredID, "POST", {
      ...config,
      title: "SSH 终端（导出恢复验证）",
      package: pkg.token,
      entry: pkg.entry,
      category: "development",
      access: "login",
    });
    const restored = await api("/api/tool-market/" + restoredID);
    await api("/api/tool-installs/" + restoredID, "PUT", {
      revision: restored.revision,
      hash: restored.hash,
    });
    id = restoredID;
    f = await load();
    assert.equal(
      await f
        .locator("body")
        .evaluate(() => localStorage.getItem("ssh.known-hosts")),
      null,
    );
    assert.equal(
      await f.locator("body").evaluate(() => localStorage.getItem("ssh.hosts")),
      null,
    );
    await editor(f);
    await f.locator("#password").fill("terminal-test-only");
    await f.locator("#connect").click();
    await f.locator("#hostFingerprint").waitFor();
    await f.locator("[data-trust=once]").click();
    await connected(f);
    await command(f, "printf 'ZIP_%s_OK\\n' REINSTALLED", "ZIP_REINSTALLED_OK");
    await page.screenshot({ path: out + "/10-zip-reinstalled.png" });
    console.log("EXPORTED ZIP REINSTALLED AND SSH VERIFIED");
    assert.deepEqual(errors, []);
    fs.writeFileSync(
      out + "/edge-result.json",
      JSON.stringify(
        {
          sourceID: previous.id,
          restoredID,
          changedKeyCancel: true,
          onceNotSaved: true,
          wrongPasswordRejected: true,
          invalidKeyRejected: true,
          encryptedKey: true,
          englishErrors: true,
          realSSH,
          realPTY: realSSH,
          controlC: realSSH,
          orderedInput: realSSH,
          zipReinstalledSSH: true,
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
