import http from "node:http";
import net from "node:net";
import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const { chromium } = require("/root/.agents/skills/gstack/node_modules/playwright");

const PKG_DIR = "/root/changhui/poc/bookstark/artifacts/remote-desktop/package";
const OUT_DIR = "/root/changhui/poc/bookstark/artifacts/remote-desktop-e2e";
fs.mkdirSync(OUT_DIR, { recursive: true });

const MIME = {
  ".html": "text/html; charset=utf-8",
  ".js": "application/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".wasm": "application/wasm",
  ".woff2": "font/woff2",
  ".json": "application/json; charset=utf-8",
  ".txt": "text/plain; charset=utf-8",
};

// Minimal RFC6455 WebSocket-to-raw-TCP relay mirroring BookStark's /api/tool-installs/:id/socket
function startTestServer() {
  return new Promise((resolve) => {
    const server = http.createServer((req, res) => {
      const urlPath = (req.url || "/").split("?")[0];
      const file = urlPath === "/" ? "index.html" : urlPath.replace(/^\/+/, "");
      const full = path.join(PKG_DIR, file);
      if (!full.startsWith(PKG_DIR) || !fs.existsSync(full) || fs.statSync(full).isDirectory()) {
        res.writeHead(404);
        res.end("Not found");
        return;
      }
      const ext = path.extname(full);
      res.writeHead(200, { "Content-Type": MIME[ext] || "application/octet-stream" });
      fs.createReadStream(full).pipe(res);
    });

    server.on("upgrade", (req, socket) => {
      const u = new URL(req.url, "http://127.0.0.1");
      const host = u.searchParams.get("host") || "127.0.0.1";
      const port = Number(u.searchParams.get("port") || 0);
      const key = req.headers["sec-websocket-key"];
      const accept = crypto
        .createHash("sha1")
        .update(key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11")
        .digest("base64");

      socket.write(
        "HTTP/1.1 101 Switching Protocols\r\n" +
          "Upgrade: websocket\r\n" +
          "Connection: Upgrade\r\n" +
          `Sec-WebSocket-Accept: ${accept}\r\n\r\n`
      );

      const sendWsFrame = (opcode, payload) => {
        const len = payload.length;
        let header;
        if (len < 126) {
          header = Buffer.from([0x80 | opcode, len]);
        } else if (len < 65536) {
          header = Buffer.alloc(4);
          header[0] = 0x80 | opcode;
          header[1] = 126;
          header.writeUInt16BE(len, 2);
        } else {
          header = Buffer.alloc(10);
          header[0] = 0x80 | opcode;
          header[1] = 127;
          header.writeBigUInt64BE(BigInt(len), 2);
        }
        try {
          socket.write(Buffer.concat([header, payload]));
        } catch (_) {}
      };

      const tcp = net.createConnection({ host, port }, () => {
        sendWsFrame(0x1, Buffer.from(JSON.stringify({ connected: true })));
      });

      tcp.on("data", (chunk) => sendWsFrame(0x2, chunk));
      tcp.on("error", () => {
        sendWsFrame(0x8, Buffer.alloc(0));
        socket.end();
      });
      tcp.on("close", () => {
        sendWsFrame(0x8, Buffer.alloc(0));
        socket.end();
      });

      let wsBuf = Buffer.alloc(0);
      socket.on("data", (chunk) => {
        wsBuf = Buffer.concat([wsBuf, chunk]);
        while (wsBuf.length >= 2) {
          const opcode = wsBuf[0] & 0x0f;
          const masked = (wsBuf[1] & 0x80) !== 0;
          let len = wsBuf[1] & 0x7f;
          let off = 2;
          if (len === 126) {
            if (wsBuf.length < 4) return;
            len = wsBuf.readUInt16BE(2);
            off = 4;
          } else if (len === 127) {
            if (wsBuf.length < 10) return;
            len = Number(wsBuf.readBigUInt64BE(2));
            off = 10;
          }
          const maskLen = masked ? 4 : 0;
          if (wsBuf.length < off + maskLen + len) return;
          const mask = masked ? wsBuf.subarray(off, off + 4) : null;
          const payload = Buffer.from(wsBuf.subarray(off + maskLen, off + maskLen + len));
          wsBuf = wsBuf.subarray(off + maskLen + len);
          if (mask) {
            for (let i = 0; i < payload.length; i++) payload[i] ^= mask[i & 3];
          }
          if (opcode === 0x8) {
            tcp.destroy();
            socket.end();
            return;
          }
          if (opcode === 0x9) {
            sendWsFrame(0xa, payload);
            continue;
          }
          if (opcode === 0x2 || opcode === 0x1) {
            tcp.write(payload);
          }
        }
      });
      socket.on("close", () => tcp.destroy());
      socket.on("error", () => tcp.destroy());
    });

    server.listen(0, "127.0.0.1", () => {
      resolve({ server, port: server.address().port });
    });
  });
}

(async () => {
  const { server, port } = await startTestServer();
  const baseUrl = `http://127.0.0.1:${port}`;
  const browser = await chromium.launch({ headless: true });

  const consoleErrors = [];
  const pageErrors = [];

  try {
    const context = await browser.newContext({ viewport: { width: 1440, height: 900 }, deviceScaleFactor: 2 });
    const page = await context.newPage();

    // Inject BookStark.sockets + BookStark.secrets shim pointing to our localhost WS<->TCP relay
    await page.addInitScript((wsPort) => {
      const memSecrets = new Map();
      window.BookStark = {
        secrets: {
          async set(k, v) { memSecrets.set(k, v); },
          async get(k) { return memSecrets.get(k) || null; },
          async remove(k) { memSecrets.delete(k); },
        },
        sockets: {
          connect(host, tcpPort) {
            return new Promise((resolve, reject) => {
              const ws = new WebSocket(`ws://127.0.0.1:${wsPort}/socket?host=${encodeURIComponent(host)}&port=${tcpPort}`);
              ws.binaryType = "arraybuffer";
              let opened = false;
              const toolSock = {
                readyState: 0,
                binaryType: "arraybuffer",
                onopen: null,
                onmessage: null,
                onerror: null,
                onclose: null,
                send(data) {
                  if (ws.readyState !== WebSocket.OPEN) return Promise.reject(new Error("socket_closed"));
                  ws.send(data);
                  return Promise.resolve();
                },
                close() {
                  toolSock.readyState = 2;
                  ws.close();
                },
              };
              ws.onmessage = (ev) => {
                if (!opened && typeof ev.data === "string") {
                  opened = true;
                  toolSock.readyState = 1;
                  resolve(toolSock);
                  if (typeof toolSock.onopen === "function") toolSock.onopen(new Event("open"));
                  return;
                }
                if (ev.data instanceof ArrayBuffer && typeof toolSock.onmessage === "function") {
                  toolSock.onmessage(new MessageEvent("message", { data: ev.data }));
                }
              };
              ws.onerror = () => {
                if (!opened) reject(new Error("connect_failed"));
                if (typeof toolSock.onerror === "function") toolSock.onerror(new Event("error"));
              };
              ws.onclose = (ev) => {
                toolSock.readyState = 3;
                if (!opened) reject(new Error("connect_closed"));
                if (typeof toolSock.onclose === "function") toolSock.onclose(ev);
              };
            });
          },
        },
      };
    }, port);

    page.on("console", (msg) => {
      if (msg.type() === "error") consoleErrors.push(msg.text());
    });
    page.on("pageerror", (err) => pageErrors.push(String(err)));

    await page.goto(baseUrl, { waitUntil: "networkidle" });
    console.log("1. Page loaded cleanly");

    // ---------------------------------------------------------
    // TEST 1: Live RDP against localhost xrdp (127.0.0.1:3389)
    // ---------------------------------------------------------
    await page.click("#btnWelcomeNewRdp");
    await page.fill("#fName", "本机 xrdp 测试机");
    await page.fill("#fHost", "127.0.0.1");
    await page.fill("#fPort", "3389");
    await page.selectOption("#fResolution", "1280x800");
    // Keep NLA checkbox ON to verify automatic TLS fallback against xrdp!
    await page.click("#btnSaveConnect");

    // Wait for TLS fingerprint verification modal
    await page.waitForSelector("#tlsModal:not([hidden])", { timeout: 15000 });
    const tlsSubject = await page.textContent("#tlsSubject");
    const tlsFp = await page.textContent("#tlsFingerprint");
    const tlsProto = await page.textContent("#tlsProtocol");
    console.log("2. RDP TLS Modal appeared:", { tlsSubject, tlsProto, fpPrefix: tlsFp.slice(0, 29) });

    // Trust and save fingerprint
    await page.click("#btnTlsSave");

    // Wait for RDP session connected & non-black bitmap painted from live xrdp!
    await page.waitForFunction(() => {
      const app = window.__remoteDesktopApp;
      const s = app && app.activeSession();
      if (!s || s.status !== "connected") return false;
      const c = s.canvas;
      const data = c.getContext("2d").getImageData(0, 0, c.width, c.height).data;
      let nonDark = 0;
      for (let i = 0; i < data.length; i += 400) {
        if (data[i] + data[i + 1] + data[i + 2] > 60) nonDark++;
      }
      return nonDark > 30;
    }, { timeout: 15000 });
    await page.waitForTimeout(500);
    console.log("3. Live RDP connected & real xrdp pixels rendered on canvas!");

    // Open Virtual Keyboard strip + File Transfer Drawer to verify full UI over live RDP
    await page.click("#btnVkbd");
    await page.click("#btnFiles");
    await page.waitForTimeout(300);
    await page.screenshot({ path: path.join(OUT_DIR, "01-live-rdp-xrdp.png") });
    await page.click("#btnCloseFileDrawer");
    await page.click("#btnCloseVkbd");

    // ---------------------------------------------------------
    // TEST 2: Live VNC against localhost Xtigervnc (127.0.0.1:5901) in Tab 2!
    // ---------------------------------------------------------
    await page.click("#btnNewConn");
    await page.click('.proto-opt[data-proto="vnc"]');
    await page.fill("#fName", "本机 TigerVNC 桌面");
    await page.fill("#fHost", "127.0.0.1");
    await page.fill("#fPort", "5901");
    await page.click("#btnSaveConnect");

    // Wait until either VNC connects directly OR asks for VNC password (both prove live RFB handshake!)
    const vncState = await page.waitForFunction(() => {
      const authVisible = !document.getElementById("authModal").hidden;
      const app = window.__remoteDesktopApp;
      const s = app && app.activeSession();
      if (authVisible) return "auth_prompt";
      if (s && s.protocol === "vnc" && s.status === "connected") return "connected";
      if (s && s.protocol === "vnc" && s.status === "error") return "error:" + s.statusDetail;
      return null;
    }, { timeout: 12000 });
    const vncResult = await vncState.jsonValue();
    console.log("4. Live VNC handshake result against 127.0.0.1:5901:", vncResult);
    await page.waitForTimeout(400);
    await page.screenshot({ path: path.join(OUT_DIR, "02-live-vnc-multitab.png") });

    // Switch back to Tab 1 (RDP) and verify it stayed connected!
    if (vncResult === "auth_prompt") {
      await page.click("#btnAuthCancel");
    }
    const tabCount = await page.locator(".s-tab").count();
    await page.locator(".s-tab").first().click();
    await page.waitForTimeout(250);
    const rdpStillConnected = await page.evaluate(() => {
      const s = window.__remoteDesktopApp.activeSession();
      return s && s.protocol === "rdp" && s.status === "connected";
    });
    console.log("5. Multi-tab check:", { tabCount, rdpStillConnected });

    // ---------------------------------------------------------
    // TEST 3: Mobile Viewport (390x844) + Touchpad + Full Virtual Keyboard
    // ---------------------------------------------------------
    await page.setViewportSize({ width: 390, height: 844 });
    await page.waitForTimeout(250);
    await page.click("#btnTouchMode");
    await page.click("#btnVkbd");
    await page.click("#btnToggleFullKbd");
    await page.waitForTimeout(300);
    await page.screenshot({ path: path.join(OUT_DIR, "03-mobile-touchpad-vkbd.png") });

    console.log("Console errors:", consoleErrors);
    console.log("Page errors:", pageErrors);
    if (consoleErrors.length > 0 || pageErrors.length > 0) {
      process.exitCode = 1;
    }
    if (!rdpStillConnected) {
      throw new Error("RDP session did not stay connected across tab switch");
    }
  } finally {
    await browser.close();
    server.close();
  }
})();
