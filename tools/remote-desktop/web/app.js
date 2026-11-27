/* BookStark Remote Desktop — Unified RDP (Rust IronRDP WASM) + VNC (noVNC) Application */
(function () {
  "use strict";

  const PROFILES_KEY = "bookstark.remoteDesktop.profiles.v1";
  const TLS_TRUST_KEY = "bookstark.remoteDesktop.tlsTrust.v1";

  // RDP FastPath PointerFlags bitmask (MS-RDPBCGR 2.2.8.1.1.3.1.1.3)
  const PTR_MOVE = 0x0800;
  const PTR_DOWN = 0x8000;
  const PTR_BUTTON1 = 0x1000; // Left
  const PTR_BUTTON2 = 0x2000; // Right
  const PTR_BUTTON3 = 0x4000; // Middle

  const $ = (id) => document.getElementById(id);

  // =========================================================================
  // Storage & Secrets Helpers
  // =========================================================================
  function loadJson(key, fallback) {
    try {
      const raw = localStorage.getItem(key);
      return raw ? JSON.parse(raw) : fallback;
    } catch (_) {
      return fallback;
    }
  }

  function saveJson(key, val) {
    try {
      localStorage.setItem(key, JSON.stringify(val));
    } catch (_) {}
  }

  async function secretSet(name, value) {
    if (window.BookStark && window.BookStark.secrets) {
      return window.BookStark.secrets.set(name, value);
    }
    sessionStorage.setItem("fallback_secret_" + name, value);
  }

  async function secretGet(name) {
    if (window.BookStark && window.BookStark.secrets) {
      try {
        const val = await window.BookStark.secrets.get(name);
        return typeof val === "string" ? val : "";
      } catch (_) {
        return "";
      }
    }
    return sessionStorage.getItem("fallback_secret_" + name) || "";
  }

  async function secretRemove(name) {
    if (window.BookStark && window.BookStark.secrets) {
      try { await window.BookStark.secrets.remove(name); } catch (_) {}
    }
    sessionStorage.removeItem("fallback_secret_" + name);
  }

  function formatBytes(n) {
    const num = Number(n) || 0;
    if (num < 1024) return num + " B";
    if (num < 1024 * 1024) return (num / 1024).toFixed(1) + " KB";
    if (num < 1024 * 1024 * 1024) return (num / (1024 * 1024)).toFixed(1) + " MB";
    return (num / (1024 * 1024 * 1024)).toFixed(2) + " GB";
  }

  function toast(msg, kind = "info") {
    const el = document.createElement("div");
    el.className = "toast " + (kind === "ok" ? "ok" : kind === "err" ? "err" : "");
    el.textContent = msg;
    $("toastRoot").appendChild(el);
    setTimeout(() => {
      el.style.opacity = "0";
      el.style.transition = "opacity .25s";
      setTimeout(() => el.remove(), 260);
    }, 3200);
  }

  function uid() {
    return (
      "rd_" +
      Date.now().toString(36) +
      "_" +
      Math.random().toString(36).slice(2, 8)
    );
  }

  // =========================================================================
  // Shared Rust IronRDP WASM Worker Pool
  // =========================================================================
  let rdpWorker = null;
  let rdpWorkerReady = false;
  const rdpWorkerListeners = new Map();

  function ensureRdpWorker() {
    if (rdpWorker) return rdpWorker;
    rdpWorker = new Worker("rdp-worker.js");
    rdpWorker.onmessage = (ev) => {
      const msg = ev.data;
      if (!msg) return;
      if (msg.type === "ready") {
        rdpWorkerReady = true;
        return;
      }
      if (msg.type === "fatal") {
        toast(msg.reason || "Rust RDP 引擎异常", "err");
        for (const sess of rdpWorkerListeners.values()) {
          sess.onWorkerFatal(msg.reason || "RDP 引擎崩溃");
        }
        return;
      }
      const listener = rdpWorkerListeners.get(msg.sessionId);
      if (listener) listener.onWorkerMessage(msg);
    };
    rdpWorker.onerror = (err) => {
      toast("RDP Worker 运行异常: " + (err.message || "unknown"), "err");
    };
    return rdpWorker;
  }

  // =========================================================================
  // BookStark.sockets -> noVNC Raw Channel Adapter
  // =========================================================================
  function createVncSocketAdapter() {
    const adapter = {
      protocol: "binary",
      binaryType: "arraybuffer",
      readyState: WebSocket.CONNECTING,
      onopen: null,
      onmessage: null,
      onerror: null,
      onclose: null,
      _sock: null,
      send(data) {
        if (!this._sock || this.readyState !== WebSocket.OPEN) return;
        this._sock.send(data).catch(() => {});
      },
      close() {
        this.readyState = WebSocket.CLOSING;
        if (this._sock) {
          try { this._sock.close(); } catch (_) {}
        }
      },
      attachToolSocket(toolSock) {
        this._sock = toolSock;
        toolSock.binaryType = "arraybuffer";
        toolSock.onmessage = (ev) => {
          if (typeof this.onmessage === "function") this.onmessage(ev);
        };
        toolSock.onerror = (ev) => {
          if (typeof this.onerror === "function") this.onerror(ev);
        };
        toolSock.onclose = (ev) => {
          this.readyState = WebSocket.CLOSED;
          if (typeof this.onclose === "function") this.onclose(ev);
        };
        this.readyState = WebSocket.OPEN;
        if (typeof this.onopen === "function") {
          this.onopen(new Event("open"));
        }
      },
      fail(reason) {
        this.readyState = WebSocket.CLOSED;
        if (typeof this.onerror === "function") this.onerror(new Event("error"));
        if (typeof this.onclose === "function") {
          this.onclose(new CloseEvent("close", { code: 1006, reason: reason || "connect_failed" }));
        }
      },
    };
    return adapter;
  }

  // =========================================================================
  // RDP Session Controller (Rust IronRDP WASM + BookStark.sockets)
  // =========================================================================
  class RdpSession {
    constructor(profile, creds, app) {
      this.id = uid();
      this.protocol = "rdp";
      this.profile = profile;
      this.creds = creds;
      this.app = app;
      this.status = "connecting";
      this.statusDetail = "正在建立 TCP 隧道…";
      this.tlsInfo = "";
      this.width = 1280;
      this.height = 800;
      this.socket = null;
      this.destroyed = false;

      // Audio state
      this.audioEnabled = profile.rdpAudio !== false;
      this.audioFormat = "通道: RDPSND · 等待音频流";
      this.audioPlayer = new window.RdpAudioPlayer({
        onVu: (l, r) => this.app.onSessionAudioVu(this, l, r),
        onSuspended: () => this.app.onSessionAudioSuspended(this, true),
        onActive: () => this.app.onSessionAudioSuspended(this, false),
      });

      // Clipboard & File Transfer state
      this.remoteClipText = "";
      this.remoteFiles = [];
      this.remoteClipDataId = null;
      this.localFiles = []; // Browser File objects registered for remote Ctrl+V
      this.downloads = new Map(); // fileIndex -> { file, chunks, received, total, streamId, active }
      this.streamToDownload = new Map(); // streamId -> fileIndex
      this.pendingReqCounter = 1;
      this.pendingStreamReq = new Map();

      // Virtual Drive state
      this.vdriveMounted = false;
      this.vdriveFiles = [];
      this.pendingVdriveGet = new Map();

      // Virtual pointer pos (for touchpad mode)
      this.cursorX = 640;
      this.cursorY = 400;

      // DOM elements
      this.viewportEl = document.createElement("div");
      this.viewportEl.className = "session-viewport scale-fit";
      this.viewportEl.tabIndex = 0;

      this.canvas = document.createElement("canvas");
      this.canvas.className = "rdp-canvas";
      this.canvas.width = this.width;
      this.canvas.height = this.height;
      this.ctx = this.canvas.getContext("2d", { alpha: false });
      this.ctx.fillStyle = "#080d18";
      this.ctx.fillRect(0, 0, this.width, this.height);

      this.overlayEl = document.createElement("div");
      this.overlayEl.className = "session-overlay-msg";
      this.viewportEl.appendChild(this.canvas);
      this.viewportEl.appendChild(this.overlayEl);

      this.bindInputEvents();
      this.updateOverlay("正在连接 " + profile.host + ":" + profile.port, this.statusDetail, true);
    }

    getResolution() {
      const preset = this.profile.resolution || "auto";
      if (preset !== "auto" && preset.includes("x")) {
        const [w, h] = preset.split("x").map(Number);
        if (w >= 640 && h >= 480) return { width: w & ~1, height: h & ~1 };
      }
      const rect = $("viewportHost").getBoundingClientRect();
      const w = Math.max(800, Math.min(2560, Math.floor(rect.width || window.innerWidth - 280))) & ~1;
      const h = Math.max(600, Math.min(1440, Math.floor(rect.height || window.innerHeight - 60))) & ~1;
      return { width: w, height: h };
    }

    async connect() {
      if (!window.BookStark || !window.BookStark.sockets) {
        this.setError("当前环境未提供 BookStark.sockets TCP 能力，请在 BookStark 运行时打开本工具。");
        return;
      }
      const { width, height } = this.getResolution();
      this.width = width;
      this.height = height;
      this.canvas.width = width;
      this.canvas.height = height;
      this.cursorX = Math.floor(width / 2);
      this.cursorY = Math.floor(height / 2);

      const worker = ensureRdpWorker();
      rdpWorkerListeners.set(this.id, this);

      try {
        this.status = "connecting";
        this.updateOverlay("正在连接 " + this.profile.host + ":" + this.profile.port, "正在建立 BookStark TCP 隧道…", true);
        this.app.refreshChrome();

        this.socket = await window.BookStark.sockets.connect(this.profile.host, Number(this.profile.port) || 3389);
        if (this.destroyed) {
          this.socket.close();
          return;
        }
        this.socket.binaryType = "arraybuffer";
        this.socket.onmessage = (ev) => {
          if (this.destroyed || !(ev.data instanceof ArrayBuffer)) return;
          const buf = ev.data;
          worker.postMessage({ type: "tcp_rx", sessionId: this.id, data: buf }, [buf]);
        };
        this.socket.onerror = () => {
          if (!this.destroyed) this.setError("TCP 隧道通信错误，连接中断。");
        };
        this.socket.onclose = (ev) => {
          if (!this.destroyed && this.status !== "error" && this.status !== "disconnected") {
            this.status = "disconnected";
            this.updateOverlay("会话已断开", ev.reason || "TCP 连接已关闭，可点击上方重连按钮恢复。", false);
            this.app.refreshChrome();
          }
        };

        const trustKey = this.profile.host + ":" + (Number(this.profile.port) || 3389);
        const trustMap = loadJson(TLS_TRUST_KEY, {});
        const trustedFingerprint = trustMap[trustKey] || null;

        worker.postMessage({
          type: "create",
          sessionId: this.id,
          options: {
            host: this.profile.host,
            username: this.creds.username || "",
            password: this.creds.password || "",
            domain: this.profile.domain || "",
            width: this.width,
            height: this.height,
            enable_audio: this.audioEnabled,
            enable_vdrive: this.profile.rdpVdrive !== false,
            enable_nla: this.profile.rdpNla !== false,
            trusted_fingerprint: trustedFingerprint,
          },
        });
      } catch (err) {
        const reason = (err && (err.code || err.message)) || String(err);
        this.setError("无法连接到 " + this.profile.host + ":" + this.profile.port + "（" + reason + "）");
      }
    }

    onWorkerFatal(reason) {
      this.setError(reason);
    }

    onWorkerMessage(msg) {
      if (this.destroyed) return;
      if (msg.type === "clip_file_stream_started") {
        const fileIndex = this.pendingStreamReq.get(msg.reqId);
        this.pendingStreamReq.delete(msg.reqId);
        if (fileIndex !== undefined) {
          this.streamToDownload.set(msg.streamId, fileIndex);
        }
        return;
      }
      if (msg.type === "vdrive_list") {
        try { this.vdriveFiles = JSON.parse(msg.filesJson || "[]"); } catch (_) {}
        this.app.renderFileDrawer();
        return;
      }
      if (msg.type === "vdrive_file_data") {
        const cb = this.pendingVdriveGet.get(msg.reqId);
        this.pendingVdriveGet.delete(msg.reqId);
        if (cb) cb(msg);
        return;
      }
      if (msg.type !== "events" || !Array.isArray(msg.events)) return;

      for (const ev of msg.events) {
        this.handleRdpEvent(ev);
      }
    }

    handleRdpEvent(ev) {
      switch (ev.type) {
        case "tcp_send": {
          if (this.socket && this.socket.readyState === 1 && ev.data) {
            this.socket.send(ev.data).catch(() => {});
          }
          break;
        }
        case "state": {
          this.statusDetail = ev.detail || ev.status;
          if (this.status !== "connected") {
            this.updateOverlay("正在连接 " + this.profile.name, this.statusDetail, true);
          }
          this.app.refreshChrome();
          break;
        }
        case "tls_verify": {
          this.status = "verifying";
          this.updateOverlay("等待核对 RDP TLS 证书指纹", "请在弹窗中确认服务器身份后继续。", false);
          this.app.showTlsVerifyModal(this, ev);
          this.app.refreshChrome();
          break;
        }
        case "connected": {
          this.status = "connected";
          this.width = ev.width || this.width;
          this.height = ev.height || this.height;
          this.tlsInfo = ev.tls_info || "TLS";
          if (this.canvas.width !== this.width || this.canvas.height !== this.height) {
            this.canvas.width = this.width;
            this.canvas.height = this.height;
          }
          this.overlayEl.hidden = true;
          this.viewportEl.focus();
          this.app.refreshChrome();
          this.app.renderFileDrawer();
          toast("已连接 RDP：" + this.profile.name + " (" + this.width + "×" + this.height + ")", "ok");
          break;
        }
        case "frame_rect": {
          if (!ev.rgba || ev.w <= 0 || ev.h <= 0) break;
          const clamped = new Uint8ClampedArray(ev.rgba);
          if (clamped.length === ev.w * ev.h * 4) {
            const imgData = new ImageData(clamped, ev.w, ev.h);
            this.ctx.putImageData(imgData, ev.x, ev.y);
          }
          break;
        }
        case "resize": {
          if (ev.width > 0 && ev.height > 0) {
            this.width = ev.width;
            this.height = ev.height;
            this.canvas.width = ev.width;
            this.canvas.height = ev.height;
            this.app.refreshChrome();
          }
          break;
        }
        case "audio_pcm": {
          this.audioFormat = "通道: RDPSND · " + (ev.format_label || "PCM");
          this.app.onSessionAudioPacket(this, ev);
          if (this.audioEnabled && ev.data) {
            this.audioPlayer.feedPcm(ev.sample_rate || 44100, ev.channels || 2, ev.bits_per_sample || 16, ev.data);
          }
          break;
        }
        case "clip_text": {
          this.remoteClipText = ev.text || "";
          this.app.onSessionRemoteClipboard(this, this.remoteClipText);
          break;
        }
        case "clip_files": {
          try {
            this.remoteFiles = JSON.parse(ev.files_json || "[]");
          } catch (_) {
            this.remoteFiles = [];
          }
          this.remoteClipDataId = ev.clip_data_id ?? null;
          this.app.renderFileDrawer();
          this.app.refreshChrome();
          if (this.remoteFiles.length > 0) {
            toast("远端复制了 " + this.remoteFiles.length + " 个文件，可在「文件传输」抽屉下载", "ok");
          }
          break;
        }
        case "clip_file_chunk": {
          this.handleRemoteFileChunk(ev);
          break;
        }
        case "clip_file_upload_req": {
          this.handleRemoteUploadRequest(ev);
          break;
        }
        case "vdrive_state": {
          this.vdriveMounted = !!ev.mounted;
          try { this.vdriveFiles = JSON.parse(ev.files_json || "[]"); } catch (_) {}
          this.app.renderFileDrawer();
          break;
        }
        case "disconnected": {
          this.status = "disconnected";
          this.updateOverlay("会话已断开", ev.reason || "远端已关闭会话", false);
          this.app.refreshChrome();
          break;
        }
        case "error": {
          this.setError(ev.message || "RDP 协议错误");
          break;
        }
      }
    }

    approveTls(trusted, saveFingerprint, fingerprint) {
      if (trusted && saveFingerprint && fingerprint) {
        const trustKey = this.profile.host + ":" + (Number(this.profile.port) || 3389);
        const trustMap = loadJson(TLS_TRUST_KEY, {});
        trustMap[trustKey] = fingerprint;
        saveJson(TLS_TRUST_KEY, trustMap);
      }
      if (!trusted) {
        this.status = "disconnected";
        this.updateOverlay("已取消连接", "未信任该主机的 TLS 证书指纹。", false);
        this.app.refreshChrome();
      } else {
        this.status = "connecting";
        this.updateOverlay("正在完成 RDP 认证", "已信任证书，正在登录远端桌面…", true);
      }
      if (rdpWorker) {
        rdpWorker.postMessage({ type: "approve_tls", sessionId: this.id, trusted });
      }
    }

    setError(message) {
      this.status = "error";
      this.statusDetail = message;
      this.updateOverlay("连接失败", message, false);
      this.app.refreshChrome();
      toast(message, "err");
    }

    updateOverlay(title, detail, spinning) {
      this.overlayEl.hidden = false;
      this.overlayEl.innerHTML =
        (spinning ? '<div class="spinner"></div>' : '<i class="fa fa-plug" style="font-size:28px;color:#64748b;"></i>') +
        "<strong>" + escapeHtml(title) + "</strong>" +
        "<span>" + escapeHtml(detail) + "</span>" +
        (!spinning
          ? '<button type="button" class="btn btn-pri btn-sm js-reconnect-inline"><i class="fa fa-refresh"></i> 重新连接</button>'
          : "");
      const btn = this.overlayEl.querySelector(".js-reconnect-inline");
      if (btn) btn.onclick = () => this.app.reconnectSession(this.id);
    }

    mapCanvasCoords(clientX, clientY) {
      const rect = this.canvas.getBoundingClientRect();
      if (!rect.width || !rect.height) return { x: 0, y: 0 };
      const rx = (clientX - rect.left) / rect.width;
      const ry = (clientY - rect.top) / rect.height;
      const x = Math.max(0, Math.min(this.width - 1, Math.round(rx * this.width)));
      const y = Math.max(0, Math.min(this.height - 1, Math.round(ry * this.height)));
      this.cursorX = x;
      this.cursorY = y;
      return { x, y };
    }

    sendMouse(x, y, flags) {
      if (this.status !== "connected" || !rdpWorker) return;
      rdpWorker.postMessage({ type: "mouse", sessionId: this.id, x, y, flags });
    }

    sendWheel(x, y, delta, horizontal) {
      if (this.status !== "connected" || !rdpWorker) return;
      rdpWorker.postMessage({ type: "wheel", sessionId: this.id, x, y, delta, horizontal });
    }

    sendKeyCode(code, pressed) {
      if (this.status !== "connected" || !rdpWorker) return;
      const entry = window.RemoteKeymaps.CODE_MAP[code];
      if (!entry) return;
      rdpWorker.postMessage({
        type: "scancode",
        sessionId: this.id,
        scancode: entry.sc,
        extended: !!entry.ext,
        pressed: !!pressed,
      });
    }

    sendText(text) {
      if (this.status !== "connected" || !rdpWorker || !text) return;
      rdpWorker.postMessage({ type: "unicode", sessionId: this.id, text });
    }

    sendClipboardText(text) {
      if (this.status !== "connected" || !rdpWorker) return;
      rdpWorker.postMessage({ type: "clip_text", sessionId: this.id, text });
    }

    advertiseLocalFiles(files) {
      if (this.status !== "connected" || !rdpWorker || !files.length) return;
      this.localFiles = Array.from(files);
      const descriptors = this.localFiles.map((f) => ({ name: f.name, size: f.size }));
      rdpWorker.postMessage({ type: "clip_files_advertise", sessionId: this.id, files: descriptors });
      this.app.renderFileDrawer();
    }

    async handleRemoteUploadRequest(ev) {
      const file = this.localFiles[ev.file_index];
      if (!file) {
        rdpWorker.postMessage({
          type: "clip_file_chunk_reply",
          sessionId: this.id,
          streamId: ev.stream_id,
          isSize: ev.is_size,
          fileSize: 0,
          isError: true,
        });
        return;
      }
      if (ev.is_size) {
        rdpWorker.postMessage({
          type: "clip_file_chunk_reply",
          sessionId: this.id,
          streamId: ev.stream_id,
          isSize: true,
          fileSize: file.size,
          isError: false,
        });
        return;
      }
      try {
        const end = Math.min(file.size, ev.offset + ev.length);
        const buf = await file.slice(ev.offset, end).arrayBuffer();
        rdpWorker.postMessage(
          {
            type: "clip_file_chunk_reply",
            sessionId: this.id,
            streamId: ev.stream_id,
            isSize: false,
            fileSize: file.size,
            data: buf,
            isError: false,
          },
          [buf]
        );
      } catch (_) {
        rdpWorker.postMessage({
          type: "clip_file_chunk_reply",
          sessionId: this.id,
          streamId: ev.stream_id,
          isSize: false,
          fileSize: 0,
          isError: true,
        });
      }
    }

    startDownloadRemoteFile(fileIndex) {
      const meta = this.remoteFiles.find((f) => f.index === fileIndex);
      if (!meta || meta.is_dir || !rdpWorker) return;
      const dl = {
        file: meta,
        chunks: [],
        received: 0,
        total: meta.size || 0,
        active: true,
      };
      this.downloads.set(fileIndex, dl);
      this.requestNextChunk(fileIndex);
      this.app.renderFileDrawer();
    }

    requestNextChunk(fileIndex) {
      const dl = this.downloads.get(fileIndex);
      if (!dl || !dl.active || !rdpWorker) return;
      const chunkSize = 65536;
      const remaining = dl.total > 0 ? Math.min(chunkSize, dl.total - dl.received) : chunkSize;
      if (dl.total > 0 && remaining <= 0) {
        this.finishDownload(fileIndex);
        return;
      }
      const reqId = this.pendingReqCounter++;
      this.pendingStreamReq.set(reqId, fileIndex);
      rdpWorker.postMessage({
        type: "clip_file_request",
        sessionId: this.id,
        reqId,
        fileIndex,
        offset: dl.received,
        length: remaining,
        clipDataId: this.remoteClipDataId,
      });
    }

    handleRemoteFileChunk(ev) {
      const fileIndex = this.streamToDownload.get(ev.stream_id);
      this.streamToDownload.delete(ev.stream_id);
      if (fileIndex === undefined) return;
      const dl = this.downloads.get(fileIndex);
      if (!dl || !dl.active) return;

      if (ev.is_error) {
        dl.active = false;
        this.downloads.delete(fileIndex);
        toast("下载远端文件失败：" + dl.file.name, "err");
        this.app.renderFileDrawer();
        return;
      }
      const bytes = new Uint8Array(ev.data || 0);
      if (bytes.byteLength > 0) {
        dl.chunks.push(bytes);
        dl.received += bytes.byteLength;
      }
      this.app.renderFileDrawer();
      if ((dl.total > 0 && dl.received >= dl.total) || bytes.byteLength === 0) {
        this.finishDownload(fileIndex);
      } else {
        this.requestNextChunk(fileIndex);
      }
    }

    finishDownload(fileIndex) {
      const dl = this.downloads.get(fileIndex);
      if (!dl) return;
      dl.active = false;
      const blob = new Blob(dl.chunks);
      triggerBrowserDownload(blob, dl.file.name);
      this.downloads.delete(fileIndex);
      toast("已下载文件：" + dl.file.name, "ok");
      this.app.renderFileDrawer();
    }

    async uploadToVdrive(files) {
      if (!rdpWorker) return;
      for (const file of Array.from(files)) {
        const buf = await file.arrayBuffer();
        rdpWorker.postMessage({ type: "vdrive_put", sessionId: this.id, name: file.name, data: buf }, [buf]);
      }
      toast("已上传 " + files.length + " 个文件到虚拟共享盘", "ok");
    }

    downloadFromVdrive(name) {
      if (!rdpWorker) return;
      const reqId = this.pendingReqCounter++;
      this.pendingVdriveGet.set(reqId, (msg) => {
        if (msg.error || !msg.data) {
          toast("读取共享盘文件失败：" + name, "err");
          return;
        }
        triggerBrowserDownload(new Blob([msg.data]), name);
      });
      rdpWorker.postMessage({ type: "vdrive_get", sessionId: this.id, reqId, name });
    }

    deleteFromVdrive(name) {
      if (!rdpWorker) return;
      rdpWorker.postMessage({ type: "vdrive_delete", sessionId: this.id, name });
    }

    refreshVdrive() {
      if (!rdpWorker) return;
      rdpWorker.postMessage({ type: "vdrive_list", sessionId: this.id });
    }

    setAudioEnabled(enabled) {
      this.audioEnabled = !!enabled;
      this.audioPlayer.setMuted(!enabled);
      if (rdpWorker) {
        rdpWorker.postMessage({ type: "audio_enabled", sessionId: this.id, enabled: this.audioEnabled });
      }
    }

    bindInputEvents() {
      const btnFlag = (button) => (button === 0 ? PTR_BUTTON1 : button === 2 ? PTR_BUTTON2 : button === 1 ? PTR_BUTTON3 : 0);

      this.canvas.addEventListener("contextmenu", (e) => e.preventDefault());
      this.canvas.addEventListener("pointerdown", (e) => {
        if (this.app.touchpadEnabled && e.pointerType === "touch") return;
        this.viewportEl.focus();
        this.audioPlayer.unlock().catch(() => {});
        const { x, y } = this.mapCanvasCoords(e.clientX, e.clientY);
        const f = btnFlag(e.button);
        if (f) this.sendMouse(x, y, PTR_DOWN | f);
      });
      this.canvas.addEventListener("pointermove", (e) => {
        if (this.app.touchpadEnabled && e.pointerType === "touch") return;
        const { x, y } = this.mapCanvasCoords(e.clientX, e.clientY);
        this.sendMouse(x, y, PTR_MOVE);
      });
      this.canvas.addEventListener("pointerup", (e) => {
        if (this.app.touchpadEnabled && e.pointerType === "touch") return;
        const { x, y } = this.mapCanvasCoords(e.clientX, e.clientY);
        const f = btnFlag(e.button);
        if (f) this.sendMouse(x, y, f);
      });
      this.canvas.addEventListener(
        "wheel",
        (e) => {
          e.preventDefault();
          const { x, y } = this.mapCanvasCoords(e.clientX, e.clientY);
          if (Math.abs(e.deltaY) >= Math.abs(e.deltaX)) {
            const delta = e.deltaY > 0 ? -120 : 120;
            this.sendWheel(x, y, delta, false);
          } else {
            const delta = e.deltaX > 0 ? 120 : -120;
            this.sendWheel(x, y, delta, true);
          }
        },
        { passive: false }
      );

      this.viewportEl.addEventListener("keydown", (e) => {
        if (this.status !== "connected") return;
        if (e.isComposing || e.keyCode === 229) return;
        e.preventDefault();
        this.app.handlePhysicalKey(this, e.code, true);
      });
      this.viewportEl.addEventListener("keyup", (e) => {
        if (this.status !== "connected") return;
        e.preventDefault();
        this.app.handlePhysicalKey(this, e.code, false);
      });
    }

    getCanvasForScreenshot() {
      return this.canvas;
    }

    destroy() {
      this.destroyed = true;
      rdpWorkerListeners.delete(this.id);
      if (rdpWorker) {
        rdpWorker.postMessage({ type: "destroy", sessionId: this.id });
      }
      if (this.socket) {
        try { this.socket.close(); } catch (_) {}
        this.socket = null;
      }
      this.audioPlayer.destroy();
      this.viewportEl.remove();
    }
  }

  // =========================================================================
  // VNC Session Controller (noVNC RFB + BookStark.sockets)
  // =========================================================================
  class VncSession {
    constructor(profile, creds, app) {
      this.id = uid();
      this.protocol = "vnc";
      this.profile = profile;
      this.creds = creds;
      this.app = app;
      this.status = "connecting";
      this.statusDetail = "正在建立 VNC TCP 隧道…";
      this.width = 0;
      this.height = 0;
      this.rfb = null;
      this.adapter = null;
      this.socket = null;
      this.destroyed = false;
      this.remoteClipText = "";
      this.cursorX = 400;
      this.cursorY = 300;

      this.viewportEl = document.createElement("div");
      this.viewportEl.className = "session-viewport scale-fit";
      this.mountEl = document.createElement("div");
      this.mountEl.className = "vnc-mount";
      this.overlayEl = document.createElement("div");
      this.overlayEl.className = "session-overlay-msg";
      this.viewportEl.appendChild(this.mountEl);
      this.viewportEl.appendChild(this.overlayEl);

      this.updateOverlay("正在连接 " + profile.host + ":" + profile.port, this.statusDetail, true);
    }

    async connect() {
      if (!window.BookStark || !window.BookStark.sockets) {
        this.setError("当前环境未提供 BookStark.sockets TCP 能力。");
        return;
      }
      // Wait briefly if ES module novnc-rfb.js is still finishing top-level await
      for (let i = 0; i < 40 && !window.NoVNCRFB; i++) {
        await new Promise((r) => setTimeout(r, 50));
      }
      if (!window.NoVNCRFB) {
        this.setError("noVNC 协议引擎尚未加载完成，请稍后重试。");
        return;
      }

      try {
        this.status = "connecting";
        this.updateOverlay("正在连接 " + this.profile.host + ":" + this.profile.port, "正在建立 BookStark TCP 隧道…", true);
        this.app.refreshChrome();

        this.adapter = createVncSocketAdapter();
        const rfbOpts = { shared: true };
        if (this.creds.password) {
          rfbOpts.credentials = {
            password: this.creds.password,
            ...(this.creds.username ? { username: this.creds.username } : {}),
          };
        }
        this.rfb = new window.NoVNCRFB(this.mountEl, this.adapter, rfbOpts);
        this.rfb.scaleViewport = true;
        this.rfb.resizeSession = false;
        this.rfb.viewOnly = !!this.profile.vncViewOnly;
        this.rfb.qualityLevel = Number(this.profile.vncQuality || 6);
        this.rfb.compressionLevel = 2;

        this.rfb.addEventListener("connect", () => {
          this.status = "connected";
          this.overlayEl.hidden = true;
          const c = this.getCanvasForScreenshot();
          if (c) {
            this.width = c.width;
            this.height = c.height;
          }
          this.rfb.focus();
          this.app.refreshChrome();
          toast("已连接 VNC：" + this.profile.name, "ok");
        });

        this.rfb.addEventListener("desktopname", () => {
          const c = this.getCanvasForScreenshot();
          if (c) {
            this.width = c.width;
            this.height = c.height;
            this.app.refreshChrome();
          }
        });

        this.rfb.addEventListener("credentialsrequired", async () => {
          const prompted = await this.app.promptAuthModal(
            "VNC 密码认证 · " + this.profile.name,
            false,
            this.creds.username || ""
          );
          if (!prompted) {
            this.destroy();
            return;
          }
          this.creds.password = prompted.password;
          this.rfb.sendCredentials({ password: prompted.password, username: this.creds.username || "" });
        });

        this.rfb.addEventListener("securityfailure", (ev) => {
          this.setError("VNC 认证失败：" + ((ev.detail && ev.detail.reason) || "密码错误或安全类型不支持"));
        });

        this.rfb.addEventListener("clipboard", (ev) => {
          const text = (ev.detail && ev.detail.text) || "";
          this.remoteClipText = text;
          this.app.onSessionRemoteClipboard(this, text);
        });

        this.rfb.addEventListener("disconnect", (ev) => {
          if (this.destroyed) return;
          const clean = ev.detail && ev.detail.clean;
          if (this.status !== "error") {
            this.status = "disconnected";
            this.updateOverlay(
              clean ? "VNC 会话已断开" : "VNC 连接意外中断",
              clean ? "已正常退出连接，可点击重新连接恢复。" : "远端关闭了连接或网络超时。",
              false
            );
            this.app.refreshChrome();
          }
        });

        this.socket = await window.BookStark.sockets.connect(this.profile.host, Number(this.profile.port) || 5900);
        if (this.destroyed) {
          this.socket.close();
          return;
        }
        this.adapter.attachToolSocket(this.socket);
      } catch (err) {
        const reason = (err && (err.code || err.message)) || String(err);
        if (this.adapter) this.adapter.fail(reason);
        this.setError("无法连接 VNC " + this.profile.host + ":" + this.profile.port + "（" + reason + "）");
      }
    }

    setError(message) {
      this.status = "error";
      this.statusDetail = message;
      this.updateOverlay("连接失败", message, false);
      this.app.refreshChrome();
      toast(message, "err");
    }

    updateOverlay(title, detail, spinning) {
      this.overlayEl.hidden = false;
      this.overlayEl.innerHTML =
        (spinning ? '<div class="spinner"></div>' : '<i class="fa fa-plug" style="font-size:28px;color:#64748b;"></i>') +
        "<strong>" + escapeHtml(title) + "</strong>" +
        "<span>" + escapeHtml(detail) + "</span>" +
        (!spinning
          ? '<button type="button" class="btn btn-pri btn-sm js-reconnect-inline"><i class="fa fa-refresh"></i> 重新连接</button>'
          : "");
      const btn = this.overlayEl.querySelector(".js-reconnect-inline");
      if (btn) btn.onclick = () => this.app.reconnectSession(this.id);
    }

    setScaleMode(mode) {
      if (!this.rfb) return;
      this.rfb.scaleViewport = mode === "fit" || mode === "stretch";
      this.rfb.clipViewport = mode === "actual";
    }

    sendKeyCode(code, pressed) {
      if (this.status !== "connected" || !this.rfb) return;
      const entry = window.RemoteKeymaps.CODE_MAP[code];
      if (!entry) return;
      this.rfb.sendKey(entry.ks, code, !!pressed);
    }

    sendText(text) {
      if (this.status !== "connected" || !this.rfb || !text) return;
      for (const ch of text) {
        const ks = window.RemoteKeymaps.charToX11Keysym(ch);
        if (ks != null) {
          this.rfb.sendKey(ks, null, true);
          this.rfb.sendKey(ks, null, false);
        }
      }
    }

    sendClipboardText(text) {
      if (this.status !== "connected" || !this.rfb) return;
      this.rfb.clipboardPasteFrom(text);
    }

    sendMouse(x, y, flags) {
      // Translate touchpad pointer events to synthetic mouse events on noVNC's canvas
      const c = this.getCanvasForScreenshot();
      if (!c) return;
      const rect = c.getBoundingClientRect();
      const cw = c.width || 1024;
      const ch = c.height || 768;
      const clientX = rect.left + (x / cw) * rect.width;
      const clientY = rect.top + (y / ch) * rect.height;
      if (flags & PTR_MOVE) {
        c.dispatchEvent(new MouseEvent("mousemove", { clientX, clientY, bubbles: true }));
      }
      const btn = flags & PTR_BUTTON1 ? 0 : flags & PTR_BUTTON2 ? 2 : flags & PTR_BUTTON3 ? 1 : -1;
      if (btn >= 0) {
        const evType = flags & PTR_DOWN ? "mousedown" : "mouseup";
        c.dispatchEvent(new MouseEvent(evType, { clientX, clientY, button: btn, bubbles: true }));
      }
    }

    sendWheel(x, y, delta, horizontal) {
      const c = this.getCanvasForScreenshot();
      if (!c) return;
      const rect = c.getBoundingClientRect();
      const clientX = rect.left + (x / (c.width || 1024)) * rect.width;
      const clientY = rect.top + (y / (c.height || 768)) * rect.height;
      c.dispatchEvent(
        new WheelEvent("wheel", {
          clientX,
          clientY,
          deltaY: horizontal ? 0 : -delta,
          deltaX: horizontal ? delta : 0,
          bubbles: true,
        })
      );
    }

    getCanvasForScreenshot() {
      return this.mountEl.querySelector("canvas");
    }

    destroy() {
      this.destroyed = true;
      if (this.rfb) {
        try { this.rfb.disconnect(); } catch (_) {}
        this.rfb = null;
      }
      if (this.socket) {
        try { this.socket.close(); } catch (_) {}
        this.socket = null;
      }
      this.viewportEl.remove();
    }
  }

  // =========================================================================
  // Android Session Controller (Tango ADB + Scrcpy v3.3.3 + WebCodecs)
  // =========================================================================
  class AndroidSession {
    constructor(profile, app) {
      this.id = uid();
      this.protocol = "android";
      this.profile = profile;
      this.app = app;
      this.status = "connecting";
      this.statusDetail = "正在建立 ADB TCP 隧道…";
      this.width = 0;
      this.height = 0;
      this.deviceName = profile.name;
      this.socket = null;
      this.handle = null;
      this.destroyed = false;
      this.remoteClipText = "";
      this.cursorX = 360;
      this.cursorY = 640;

      // Audio
      this.audioEnabled = profile.androidAudio !== false;
      this.audioFormat = "Scrcpy RAW PCM · 等待音频流";
      this.audioPlayer = new window.RdpAudioPlayer({
        onVu: (l, r) => this.app.onSessionAudioVu(this, l, r),
        onSuspended: () => this.app.onSessionAudioSuspended(this, true),
        onActive: () => this.app.onSessionAudioSuspended(this, false),
      });

      // ADB File Manager state
      this.adbPath = "/sdcard/Download";
      this.adbFiles = [];
      this.adbLoading = false;

      // DOM elements
      this.viewportEl = document.createElement("div");
      this.viewportEl.className = "session-viewport scale-fit";
      this.viewportEl.tabIndex = 0;

      this.canvas = document.createElement("canvas");
      this.canvas.className = "rdp-canvas android-canvas";
      this.canvas.width = 720;
      this.canvas.height = 1280;

      this.overlayEl = document.createElement("div");
      this.overlayEl.className = "session-overlay-msg";
      this.viewportEl.appendChild(this.canvas);
      this.viewportEl.appendChild(this.overlayEl);

      this.bindInputEvents();
      this.updateOverlay("正在连接 Android " + profile.host + ":" + profile.port, this.statusDetail, true);
    }

    async connect() {
      if (!window.BookStark || !window.BookStark.sockets) {
        this.setError("当前环境未提供 BookStark.sockets TCP 能力。");
        return;
      }
      if (!window.BookStarkAndroid) {
        this.setError("Android ADB/Scrcpy 引擎尚未加载，请刷新重试。");
        return;
      }
      try {
        this.status = "connecting";
        this.updateOverlay("正在连接 " + this.profile.host + ":" + this.profile.port, "正在建立 BookStark TCP 隧道…", true);
        this.app.refreshChrome();

        const port = Number(this.profile.port) || 5555;
        this.socket = await window.BookStark.sockets.connect(this.profile.host, port);
        if (this.destroyed) {
          this.socket.close();
          return;
        }

        const [bitRateStr, fpsStr] = String(this.profile.androidBitrate || "4000000:60").split(":");
        this.handle = await window.BookStarkAndroid.connect({
          toolSocket: this.socket,
          serial: this.profile.host + ":" + port,
          secretGet,
          secretSet,
          canvas: this.canvas,
          maxSize: Number(this.profile.androidMaxSize ?? 1280),
          bitRate: Number(bitRateStr) || 4000000,
          maxFps: Number(fpsStr) || 60,
          enableAudio: this.audioEnabled,
          onStatus: (detail) => {
            if (this.destroyed || this.status === "connected") return;
            this.statusDetail = detail;
            this.updateOverlay("正在连接 " + this.profile.name, detail, true);
          },
          onSize: (w, h) => {
            this.width = w;
            this.height = h;
            this.cursorX = Math.floor(w / 2);
            this.cursorY = Math.floor(h / 2);
            this.app.refreshChrome();
          },
          onClipboard: (text) => {
            this.remoteClipText = text || "";
            this.app.onSessionRemoteClipboard(this, this.remoteClipText);
          },
          onAudioState: (ok, label) => {
            this.audioFormat = label || (ok ? "Scrcpy RAW PCM" : "音频未启用");
            this.app.refreshAudioUi();
          },
          onAudioPcm: (buf, sr, ch, bps) => {
            this.app.onSessionAudioPacket(this);
            if (this.audioEnabled) {
              this.audioPlayer.feedPcm(sr, ch, bps, buf);
            }
          },
          onDisconnected: (reason) => {
            if (this.destroyed || this.status === "error") return;
            this.status = "disconnected";
            this.updateOverlay("Android 会话已断开", reason || "ADB 连接已关闭", false);
            this.app.refreshChrome();
          },
        });

        if (this.destroyed) {
          this.handle.close();
          return;
        }

        this.status = "connected";
        this.deviceName = this.handle.deviceName || this.profile.name;
        this.width = this.handle.width || this.width;
        this.height = this.handle.height || this.height;
        this.overlayEl.hidden = true;
        this.viewportEl.focus();
        this.app.refreshChrome();
        toast("已连接 Android：" + this.deviceName, "ok");
      } catch (err) {
        const msg = (err && (err.message || err.code)) || String(err);
        this.setError("Android 连接失败：" + msg);
      }
    }

    setError(message) {
      this.status = "error";
      this.statusDetail = message;
      this.updateOverlay("连接失败", message, false);
      this.app.refreshChrome();
      toast(message, "err");
    }

    updateOverlay(title, detail, spinning) {
      this.overlayEl.hidden = false;
      this.overlayEl.innerHTML =
        (spinning ? '<div class="spinner"></div>' : '<i class="fa fa-mobile" style="font-size:32px;color:#64748b;"></i>') +
        "<strong>" + escapeHtml(title) + "</strong>" +
        "<span>" + escapeHtml(detail) + "</span>" +
        (!spinning
          ? '<button type="button" class="btn btn-pri btn-sm js-reconnect-inline"><i class="fa fa-refresh"></i> 重新连接</button>'
          : "");
      const btn = this.overlayEl.querySelector(".js-reconnect-inline");
      if (btn) btn.onclick = () => this.app.reconnectSession(this.id);
    }

    mapCanvasCoords(clientX, clientY) {
      const rect = this.canvas.getBoundingClientRect();
      const w = this.width || this.canvas.width || 720;
      const h = this.height || this.canvas.height || 1280;
      if (!rect.width || !rect.height) return { x: 0, y: 0 };
      const rx = (clientX - rect.left) / rect.width;
      const ry = (clientY - rect.top) / rect.height;
      const x = Math.max(0, Math.min(w - 1, Math.round(rx * w)));
      const y = Math.max(0, Math.min(h - 1, Math.round(ry * h)));
      this.cursorX = x;
      this.cursorY = y;
      return { x, y };
    }

    bindInputEvents() {
      let dragging = false;
      this.canvas.addEventListener("contextmenu", (e) => {
        e.preventDefault();
        // Right click acts as Android Back button
        if (this.status === "connected" && this.handle) {
          this.handle.sendAndroidAction("back").catch(() => {});
        }
      });
      this.canvas.addEventListener("pointerdown", (e) => {
        if (e.button === 2) return;
        if (this.app.touchpadEnabled && e.pointerType === "touch") return;
        this.viewportEl.focus();
        this.audioPlayer.unlock().catch(() => {});
        if (this.status !== "connected" || !this.handle) return;
        dragging = true;
        this.canvas.setPointerCapture?.(e.pointerId);
        const { x, y } = this.mapCanvasCoords(e.clientX, e.clientY);
        this.handle.injectTouch("down", x, y, 1).catch(() => {});
      });
      this.canvas.addEventListener("pointermove", (e) => {
        if (!dragging || this.status !== "connected" || !this.handle) return;
        const { x, y } = this.mapCanvasCoords(e.clientX, e.clientY);
        this.handle.injectTouch("move", x, y, 1).catch(() => {});
      });
      const endDrag = (e) => {
        if (!dragging) return;
        dragging = false;
        if (this.status !== "connected" || !this.handle) return;
        const { x, y } = this.mapCanvasCoords(e.clientX, e.clientY);
        this.handle.injectTouch("up", x, y, 0).catch(() => {});
      };
      this.canvas.addEventListener("pointerup", endDrag);
      this.canvas.addEventListener("pointercancel", endDrag);
      this.canvas.addEventListener(
        "wheel",
        (e) => {
          e.preventDefault();
          if (this.status !== "connected" || !this.handle) return;
          const { x, y } = this.mapCanvasCoords(e.clientX, e.clientY);
          const sx = Math.max(-1, Math.min(1, -e.deltaX / 120));
          const sy = Math.max(-1, Math.min(1, -e.deltaY / 120));
          this.handle.injectScroll(x, y, sx, sy).catch(() => {});
        },
        { passive: false }
      );
      this.viewportEl.addEventListener("keydown", (e) => {
        if (this.status !== "connected") return;
        if (e.isComposing || e.keyCode === 229) return;
        e.preventDefault();
        this.app.handlePhysicalKey(this, e.code, true);
      });
      this.viewportEl.addEventListener("keyup", (e) => {
        if (this.status !== "connected") return;
        e.preventDefault();
        this.app.handlePhysicalKey(this, e.code, false);
      });
    }

    sendMouse(x, y, flags) {
      if (this.status !== "connected" || !this.handle) return;
      if (flags & PTR_DOWN) {
        if (flags & PTR_BUTTON2) {
          this.handle.sendAndroidAction("back").catch(() => {});
        } else {
          this.handle.injectTouch("down", x, y, 1).catch(() => {});
        }
      } else if (flags & (PTR_BUTTON1 | PTR_BUTTON3)) {
        this.handle.injectTouch("up", x, y, 0).catch(() => {});
      } else if (flags & PTR_MOVE) {
        this.handle.injectTouch("move", x, y, 0).catch(() => {});
      }
    }

    sendWheel(x, y, delta, horizontal) {
      if (this.status !== "connected" || !this.handle) return;
      const v = Math.max(-1, Math.min(1, delta / 120));
      this.handle.injectScroll(x, y, horizontal ? v : 0, horizontal ? 0 : v).catch(() => {});
    }

    sendKeyCode(code, pressed) {
      if (this.status !== "connected" || !this.handle) return;
      this.handle.injectKeyCode(code, pressed, 0).catch(() => {});
    }

    sendText(text) {
      if (this.status !== "connected" || !this.handle || !text) return;
      // Scrcpy setClipboard with paste=true seamlessly injects Chinese & Unicode into Android!
      this.handle.setClipboard(text, true).catch(() => {});
    }

    sendClipboardText(text) {
      if (this.status !== "connected" || !this.handle) return;
      this.handle.setClipboard(text, false).catch(() => {});
    }

    sendAction(act) {
      if (this.status !== "connected" || !this.handle) return;
      this.handle.sendAndroidAction(act).catch(() => {});
    }

    setAudioEnabled(enabled) {
      this.audioEnabled = !!enabled;
      this.audioPlayer.setMuted(!enabled);
    }

    async loadAdbDir(dirPath) {
      if (this.status !== "connected" || !this.handle) return;
      this.adbPath = (dirPath || "/sdcard/Download").replace(/\/+$/, "") || "/";
      this.adbLoading = true;
      this.app.renderFileDrawer();
      try {
        this.adbFiles = await this.handle.listDir(this.adbPath);
      } catch (err) {
        this.adbFiles = [];
        toast("读取手机目录失败：" + ((err && err.message) || err), "err");
      } finally {
        this.adbLoading = false;
        this.app.renderFileDrawer();
      }
    }

    async handleUploadOrApk(files) {
      if (this.status !== "connected" || !this.handle || !files.length) return;
      for (const file of Array.from(files)) {
        const bytes = new Uint8Array(await file.arrayBuffer());
        if (/\.apk$/i.test(file.name)) {
          toast("正在推送并安装 APK：" + file.name + "…");
          try {
            const out = await this.handle.installApk(file.name, bytes);
            if (/Success/i.test(String(out))) {
              toast("APK 安装成功：" + file.name, "ok");
            } else {
              toast("APK 安装结果：" + String(out).trim().slice(0, 80), "err");
            }
          } catch (err) {
            toast("APK 安装失败：" + ((err && err.message) || err), "err");
          }
        } else {
          const target = (this.adbPath === "/" ? "" : this.adbPath) + "/" + file.name;
          try {
            await this.handle.pushFile(target, bytes);
            toast("已上传到手机：" + target, "ok");
          } catch (err) {
            toast("上传失败：" + ((err && err.message) || err), "err");
          }
        }
      }
      await this.loadAdbDir(this.adbPath);
    }

    async downloadAdbFile(name) {
      if (this.status !== "connected" || !this.handle) return;
      const fullPath = (this.adbPath === "/" ? "" : this.adbPath) + "/" + name;
      try {
        toast("正在从手机拉取：" + name + "…");
        const bytes = await this.handle.pullFile(fullPath);
        triggerBrowserDownload(new Blob([bytes]), name);
        toast("已下载到本地：" + name, "ok");
      } catch (err) {
        toast("拉取文件失败：" + ((err && err.message) || err), "err");
      }
    }

    getCanvasForScreenshot() {
      return this.canvas;
    }

    destroy() {
      this.destroyed = true;
      if (this.handle) {
        this.handle.close().catch(() => {});
        this.handle = null;
      }
      if (this.socket) {
        try { this.socket.close(); } catch (_) {}
        this.socket = null;
      }
      this.audioPlayer.destroy();
      this.viewportEl.remove();
    }
  }

  // =========================================================================
  // Main Application Controller
  // =========================================================================
  class RemoteDesktopApp {
    constructor() {
      this.profiles = loadJson(PROFILES_KEY, []);
      this.filterProto = "all";
      this.searchQuery = "";
      this.sessions = new Map();
      this.activeSessionId = null;
      this.scaleMode = "fit";

      // Virtual Keyboard & Sticky Modifiers
      this.vkbdVisible = false;
      this.vkbdFullVisible = false;
      this.vkbdFloating = false;
      this.stickyMods = new Set();

      // Touchpad mode
      this.touchpadEnabled = false;

      // File Drawer tab
      this.fileDrawerTab = "clip";

      // Picture-in-Picture state (In-App multi-PiP + OS-level PiP)
      this.inAppPips = new Map(); // sessionId -> { winEl, bodyEl }
      this.pipZCounter = 40;
      this.osPip = null; // { sessionId, video, stream, rafId, mirror }

      // Pending modal resolvers
      this.tlsResolveSession = null;
      this.tlsPendingData = null;
      this.authResolve = null;

      this.initUI();
      this.renderHostList();
      this.refreshChrome();
    }

    activeSession() {
      return this.activeSessionId ? this.sessions.get(this.activeSessionId) || null : null;
    }

    initUI() {
      // Sidebar controls
      $("btnNewConn").onclick = () => this.openConnModal(null, "rdp");
      $("btnWelcomeNewRdp").onclick = () => this.openConnModal(null, "rdp");
      $("btnWelcomeNewVnc").onclick = () => this.openConnModal(null, "vnc");
      $("btnWelcomeNewAndroid").onclick = () => this.openConnModal(null, "android");
      $("btnCollapseSidebar").onclick = () => this.toggleSidebar(false);
      $("btnExpandSidebar").onclick = () => this.toggleSidebar();
      $("sidebarBackdrop").onclick = () => this.toggleSidebar(false);

      $("searchInput").addEventListener("input", (e) => {
        this.searchQuery = e.target.value.trim().toLowerCase();
        this.renderHostList();
      });

      document.querySelectorAll(".filter-pills .pill").forEach((btn) => {
        btn.onclick = () => {
          document.querySelectorAll(".filter-pills .pill").forEach((b) => b.classList.remove("active"));
          btn.classList.add("active");
          this.filterProto = btn.dataset.filter || "all";
          this.renderHostList();
        };
      });

      // Connection Modal
      $("btnCloseConnModal").onclick = () => ($("connModal").hidden = true);
      $("btnCancelConn").onclick = () => ($("connModal").hidden = true);
      document.querySelectorAll(".proto-opt").forEach((btn) => {
        btn.onclick = () => this.setModalProtocol(btn.dataset.proto, true);
      });
      $("btnSaveOnly").onclick = () => this.submitConnForm(false);
      $("connForm").onsubmit = (e) => {
        e.preventDefault();
        this.submitConnForm(true);
      };

      // TLS Modal
      $("btnTlsReject").onclick = () => this.resolveTlsModal(false, false);
      $("btnTlsOnce").onclick = () => this.resolveTlsModal(true, false);
      $("btnTlsSave").onclick = () => this.resolveTlsModal(true, true);

      // Auth Modal
      $("btnCloseAuthModal").onclick = () => this.closeAuthModal(null);
      $("btnAuthCancel").onclick = () => this.closeAuthModal(null);
      $("authForm").onsubmit = (e) => {
        e.preventDefault();
        this.closeAuthModal({
          username: $("authUser").value,
          password: $("authPass").value,
        });
      };

      // Floating Toolbar: Combos
      const comboMenu = $("comboMenu");
      comboMenu.innerHTML = "";
      for (const combo of window.RemoteKeymaps.PRESET_COMBOS) {
        const item = document.createElement("button");
        item.type = "button";
        item.className = "combo-item";
        item.innerHTML = "<span>" + escapeHtml(combo.label) + "</span><kbd>" + escapeHtml(combo.keysLabel) + "</kbd>";
        item.onclick = () => {
          comboMenu.hidden = true;
          this.sendCombo(combo.codes);
        };
        comboMenu.appendChild(item);
      }

      $("btnCombos").onclick = (e) => {
        e.stopPropagation();
        this.togglePopover("comboMenu");
      };
      $("btnClipboard").onclick = (e) => {
        e.stopPropagation();
        this.togglePopover("clipboardPopover");
      };
      $("btnAudio").onclick = (e) => {
        e.stopPropagation();
        const s = this.activeSession();
        if (s && s.protocol === "rdp") s.audioPlayer.unlock().catch(() => {});
        this.togglePopover("audioPopover");
      };
      $("btnScale").onclick = (e) => {
        e.stopPropagation();
        this.togglePopover("scaleMenu");
      };
      $("btnPip").onclick = (e) => {
        e.stopPropagation();
        this.togglePopover("pipMenu");
      };
      $("btnPipInApp").onclick = () => {
        $("pipMenu").hidden = true;
        if (this.activeSessionId) this.openInAppPip(this.activeSessionId);
      };
      $("btnPipSystem").onclick = () => {
        $("pipMenu").hidden = true;
        if (this.activeSessionId) this.startOsPip(this.activeSessionId);
      };

      document.addEventListener("click", (e) => {
        if (!e.target.closest(".dropdown-wrap")) {
          this.closeAllPopovers();
        }
      });

      // Clipboard Popover actions
      $("btnClipSync").onclick = () => {
        const s = this.activeSession();
        const text = $("clipTextarea").value;
        if (!s || s.status !== "connected") return;
        s.sendClipboardText(text);
        toast("已同步文本到远端剪贴板", "ok");
      };
      $("btnClipType").onclick = () => {
        const s = this.activeSession();
        const text = $("clipTextarea").value;
        if (!s || s.status !== "connected" || !text) return;
        s.sendText(text);
        $("clipboardPopover").hidden = true;
        toast("已向远端光标处输入文本", "ok");
      };

      // Audio Popover controls
      $("audioEnabledToggle").onchange = (e) => {
        const s = this.activeSession();
        if (s && (s.protocol === "rdp" || s.protocol === "android")) {
          s.setAudioEnabled(e.target.checked);
          if (e.target.checked) s.audioPlayer.unlock().catch(() => {});
          this.refreshAudioUi();
        }
      };
      $("audioVolumeSlider").oninput = (e) => {
        const val = Number(e.target.value);
        $("audioVolumeVal").textContent = val + "%";
        const s = this.activeSession();
        if (s && s.audioPlayer) s.audioPlayer.setVolume(val / 100);
      };
      $("audioBufferGroup").querySelectorAll(".seg-btn").forEach((btn) => {
        btn.onclick = () => {
          $("audioBufferGroup").querySelectorAll(".seg-btn").forEach((b) => b.classList.remove("active"));
          btn.classList.add("active");
          const s = this.activeSession();
          if (s && s.audioPlayer) s.audioPlayer.setBufferMs(Number(btn.dataset.ms));
        };
      });
      $("btnUnlockAudio").onclick = () => {
        const s = this.activeSession();
        if (s && s.audioPlayer) s.audioPlayer.unlock().catch(() => {});
        $("audioUnlockBanner").hidden = true;
      };

      // Scale Menu
      $("scaleMenu").querySelectorAll(".menu-item").forEach((item) => {
        item.onclick = () => {
          this.setScaleMode(item.dataset.scale);
          $("scaleMenu").hidden = true;
        };
      });

      // File Transfer Drawer
      $("btnFiles").onclick = () => {
        const drawer = $("fileDrawer");
        drawer.hidden = !drawer.hidden;
        $("btnFiles").classList.toggle("active", !drawer.hidden);
        $("stage").classList.toggle("drawer-open", !drawer.hidden);
        if (!drawer.hidden) {
          const s = this.activeSession();
          if (s && s.protocol === "rdp") s.refreshVdrive();
          if (s && s.protocol === "android") s.loadAdbDir(s.adbPath);
          this.renderFileDrawer();
        }
      };
      $("btnCloseFileDrawer").onclick = () => {
        $("fileDrawer").hidden = true;
        $("btnFiles").classList.remove("active");
        $("stage").classList.remove("drawer-open");
      };
      $("fdTabClip").onclick = () => this.setFileDrawerTab("clip");
      $("fdTabVdrive").onclick = () => this.setFileDrawerTab("vdrive");
      $("clipDropArea").onclick = () => $("clipFileInput").click();
      $("clipFileInput").onchange = (e) => {
        const s = this.activeSession();
        if (s && s.protocol === "rdp" && e.target.files.length) {
          s.advertiseLocalFiles(e.target.files);
          toast("已注入远端剪贴板，在 Windows 按 Ctrl+V 粘贴", "ok");
        }
        e.target.value = "";
      };
      $("btnVdriveUpload").onclick = () => $("vdriveFileInput").click();
      $("vdriveFileInput").onchange = (e) => {
        const s = this.activeSession();
        if (s && s.protocol === "rdp" && e.target.files.length) {
          s.uploadToVdrive(e.target.files);
        }
        e.target.value = "";
      };
      $("btnVdriveRefresh").onclick = () => {
        const s = this.activeSession();
        if (s && s.protocol === "rdp") s.refreshVdrive();
      };

      // Android File Browser & Nav Bar controls
      $("androidDropArea").onclick = () => $("androidFileInput").click();
      $("androidFileInput").onchange = (e) => {
        const s = this.activeSession();
        if (s && s.protocol === "android" && e.target.files.length) {
          s.handleUploadOrApk(e.target.files);
        }
        e.target.value = "";
      };
      $("btnAdbGo").onclick = () => {
        const s = this.activeSession();
        if (s && s.protocol === "android") s.loadAdbDir($("adbPathInput").value.trim() || "/sdcard");
      };
      $("adbPathInput").addEventListener("keydown", (e) => {
        if (e.key === "Enter") {
          e.preventDefault();
          const s = this.activeSession();
          if (s && s.protocol === "android") s.loadAdbDir($("adbPathInput").value.trim() || "/sdcard");
        }
      });
      $("btnAdbUp").onclick = () => {
        const s = this.activeSession();
        if (!s || s.protocol !== "android") return;
        const parts = s.adbPath.split("/").filter(Boolean);
        parts.pop();
        s.loadAdbDir("/" + parts.join("/"));
      };
      document.querySelectorAll(".js-adb-path").forEach((btn) => {
        btn.onclick = () => {
          const s = this.activeSession();
          if (s && s.protocol === "android") s.loadAdbDir(btn.dataset.path);
        };
      });
      $("androidNavBar").querySelectorAll(".anav-btn").forEach((btn) => {
        btn.onclick = () => {
          const s = this.activeSession();
          if (s && s.protocol === "android") s.sendAction(btn.dataset.act);
        };
      });

      // Stage Drag & Drop (RDP + Android)
      let dragDepth = 0;
      const stage = $("stage");
      stage.addEventListener("dragenter", (e) => {
        const s = this.activeSession();
        if (!s || (s.protocol !== "rdp" && s.protocol !== "android") || s.status !== "connected") return;
        e.preventDefault();
        dragDepth++;
        $("dropOverlay").hidden = false;
      });
      stage.addEventListener("dragover", (e) => {
        if (!$("dropOverlay").hidden) e.preventDefault();
      });
      stage.addEventListener("dragleave", () => {
        if (dragDepth > 0) dragDepth--;
        if (dragDepth === 0) $("dropOverlay").hidden = true;
      });
      stage.addEventListener("drop", (e) => {
        e.preventDefault();
        dragDepth = 0;
        $("dropOverlay").hidden = true;
        const s = this.activeSession();
        if (!s || s.status !== "connected") return;
        const files = e.dataTransfer && e.dataTransfer.files;
        if (!files || !files.length) return;
        if (s.protocol === "rdp") {
          s.advertiseLocalFiles(files);
          if (s.profile.rdpVdrive !== false) s.uploadToVdrive(files);
          toast("已上传 " + files.length + " 个文件（可在远端按 Ctrl+V 或打开 BookStark 共享盘）", "ok");
        } else if (s.protocol === "android") {
          s.handleUploadOrApk(files);
        }
      });

      // Screenshot, Fullscreen, Touchpad, Reconnect, Disconnect
      $("btnScreenshot").onclick = () => this.takeScreenshot();
      $("btnFullscreen").onclick = () => this.toggleFullscreen();
      $("btnTouchMode").onclick = () => this.toggleTouchpad();
      $("btnCloseTouchpad").onclick = () => this.toggleTouchpad(false);
      $("btnReconnect").onclick = () => {
        if (this.activeSessionId) this.reconnectSession(this.activeSessionId);
      };
      $("btnDisconnect").onclick = () => {
        if (this.activeSessionId) this.closeSession(this.activeSessionId);
      };

      // Virtual Keyboard
      this.initVirtualKeyboard();
      this.initTouchpad();
    }

    // =========================================================================
    // Virtual Keyboard & Sticky Modifiers
    // =========================================================================
    initVirtualKeyboard() {
      $("btnVkbd").onclick = () => {
        this.vkbdVisible = !this.vkbdVisible;
        $("vkbdContainer").hidden = !this.vkbdVisible;
        $("btnVkbd").classList.toggle("active", this.vkbdVisible);
      };
      $("btnCloseVkbd").onclick = () => {
        this.vkbdVisible = false;
        $("vkbdContainer").hidden = true;
        $("btnVkbd").classList.remove("active");
        this.releaseAllStickyMods();
      };
      $("btnToggleFullKbd").onclick = () => {
        this.vkbdFullVisible = !this.vkbdFullVisible;
        $("vkbdFull").hidden = !this.vkbdFullVisible;
        $("btnToggleFullKbd").innerHTML = this.vkbdFullVisible
          ? '<i class="fa fa-chevron-down"></i> 收起'
          : '<i class="fa fa-chevron-up"></i> 全键盘';
      };
      $("btnVkbdFloatToggle").onclick = () => {
        this.vkbdFloating = !this.vkbdFloating;
        $("vkbdContainer").classList.toggle("floating", this.vkbdFloating);
      };

      const sendImeText = () => {
        const s = this.activeSession();
        const inp = $("vkbdImeInput");
        const text = inp.value;
        if (!s || s.status !== "connected" || !text) return;
        s.sendText(text);
        inp.value = "";
        toast("已发送文本到远端光标处", "ok");
      };
      $("btnVkbdSendText").onclick = sendImeText;
      $("vkbdImeInput").addEventListener("keydown", (e) => {
        e.stopPropagation();
        if (e.key === "Enter" && !e.isComposing) {
          e.preventDefault();
          sendImeText();
        }
      });

      // Build Mode 2 Full Keyboard Grid
      const grid = $("vkbdGrid");
      grid.innerHTML = "";
      for (const row of window.RemoteKeymaps.FULL_KEYBOARD_ROWS) {
        const rowEl = document.createElement("div");
        rowEl.className = "vkbd-row";
        for (const key of row) {
          const btn = document.createElement("button");
          btn.type = "button";
          btn.className = "vk-key" + (key.mod ? " vk-mod" : "") + (key.accent ? " vk-accent" : "");
          btn.dataset.code = key.code;
          if (key.w) btn.style.flex = String(key.w);
          btn.textContent = key.label;
          rowEl.appendChild(btn);
        }
        grid.appendChild(rowEl);
      }

      // Bind clicks on ALL virtual keyboard keys (Mode 1 + Mode 2)
      $("vkbdContainer").addEventListener("click", (e) => {
        const btn = e.target.closest(".vk-key");
        if (!btn) return;
        const comboId = btn.dataset.combo;
        if (comboId) {
          const combo = window.RemoteKeymaps.PRESET_COMBOS.find((c) => c.id === comboId);
          if (combo) this.sendCombo(combo.codes);
          return;
        }
        const code = btn.dataset.code;
        if (!code) return;
        if (btn.classList.contains("vk-mod")) {
          this.toggleStickyMod(code);
        } else {
          this.tapVirtualKey(code);
        }
      });
    }

    toggleStickyMod(code) {
      const s = this.activeSession();
      if (!s || s.status !== "connected") return;
      if (this.stickyMods.has(code)) {
        this.stickyMods.delete(code);
        s.sendKeyCode(code, false);
      } else {
        this.stickyMods.add(code);
        s.sendKeyCode(code, true);
      }
      this.syncStickyModUi();
    }

    releaseAllStickyMods() {
      const s = this.activeSession();
      for (const code of this.stickyMods) {
        if (s && s.status === "connected") s.sendKeyCode(code, false);
      }
      this.stickyMods.clear();
      this.syncStickyModUi();
    }

    syncStickyModUi() {
      $("vkbdContainer").querySelectorAll(".vk-mod").forEach((btn) => {
        btn.classList.toggle("sticky-on", this.stickyMods.has(btn.dataset.code));
      });
    }

    tapVirtualKey(code) {
      const s = this.activeSession();
      if (!s || s.status !== "connected") return;
      s.sendKeyCode(code, true);
      setTimeout(() => {
        s.sendKeyCode(code, false);
        if (this.stickyMods.size > 0) this.releaseAllStickyMods();
      }, 30);
    }

    handlePhysicalKey(session, code, pressed) {
      session.sendKeyCode(code, pressed);
      // If user held a sticky modifier on screen and pressed a regular key on physical keyboard, auto-release!
      if (!pressed && this.stickyMods.size > 0 && !this.stickyMods.has(code)) {
        this.releaseAllStickyMods();
      }
    }

    sendCombo(codes) {
      const s = this.activeSession();
      if (!s || s.status !== "connected") {
        toast("请先连接远程桌面", "err");
        return;
      }
      if (s.protocol === "vnc" && codes.join("+") === "ControlLeft+AltLeft+Delete" && s.rfb) {
        s.rfb.sendCtrlAltDel();
        return;
      }
      for (const c of codes) s.sendKeyCode(c, true);
      setTimeout(() => {
        for (let i = codes.length - 1; i >= 0; i--) s.sendKeyCode(codes[i], false);
      }, 50);
    }

    // =========================================================================
    // Mobile Virtual Touchpad
    // =========================================================================
    initTouchpad() {
      const surface = $("touchpadSurface");
      let lastX = 0;
      let lastY = 0;
      let startTime = 0;
      let moved = false;
      let touchCount = 0;

      surface.addEventListener(
        "touchstart",
        (e) => {
          e.preventDefault();
          touchCount = e.touches.length;
          lastX = e.touches[0].clientX;
          lastY = e.touches[0].clientY;
          startTime = Date.now();
          moved = false;
        },
        { passive: false }
      );

      surface.addEventListener(
        "touchmove",
        (e) => {
          e.preventDefault();
          const s = this.activeSession();
          if (!s || s.status !== "connected") return;
          const t = e.touches[0];
          const dx = t.clientX - lastX;
          const dy = t.clientY - lastY;
          lastX = t.clientX;
          lastY = t.clientY;
          if (Math.hypot(dx, dy) > 2) moved = true;

          if (e.touches.length >= 2) {
            // Two-finger scroll
            if (Math.abs(dy) >= 4) {
              s.sendWheel(s.cursorX, s.cursorY, dy > 0 ? -60 : 60, false);
            }
            return;
          }
          // One-finger relative pointer glide (1.6x acceleration)
          const maxW = s.width || 1280;
          const maxH = s.height || 800;
          s.cursorX = Math.max(0, Math.min(maxW - 1, Math.round(s.cursorX + dx * 1.6)));
          s.cursorY = Math.max(0, Math.min(maxH - 1, Math.round(s.cursorY + dy * 1.6)));
          s.sendMouse(s.cursorX, s.cursorY, PTR_MOVE);
        },
        { passive: false }
      );

      surface.addEventListener("touchend", () => {
        const s = this.activeSession();
        if (!s || s.status !== "connected") return;
        const dt = Date.now() - startTime;
        if (!moved && dt < 240) {
          const btn = touchCount >= 2 ? PTR_BUTTON2 : PTR_BUTTON1;
          s.sendMouse(s.cursorX, s.cursorY, PTR_DOWN | btn);
          setTimeout(() => s.sendMouse(s.cursorX, s.cursorY, btn), 35);
        }
      });

      const bindTpBtn = (el, flag) => {
        el.addEventListener("pointerdown", (e) => {
          e.preventDefault();
          const s = this.activeSession();
          if (s && s.status === "connected") s.sendMouse(s.cursorX, s.cursorY, PTR_DOWN | flag);
        });
        el.addEventListener("pointerup", (e) => {
          e.preventDefault();
          const s = this.activeSession();
          if (s && s.status === "connected") s.sendMouse(s.cursorX, s.cursorY, flag);
        });
      };
      bindTpBtn($("tpBtnLeft"), PTR_BUTTON1);
      bindTpBtn($("tpBtnMiddle"), PTR_BUTTON3);
      bindTpBtn($("tpBtnRight"), PTR_BUTTON2);
    }

    toggleTouchpad(force) {
      this.touchpadEnabled = typeof force === "boolean" ? force : !this.touchpadEnabled;
      $("touchpadDeck").hidden = !this.touchpadEnabled;
      $("btnTouchMode").classList.toggle("active", this.touchpadEnabled);
    }

    // =========================================================================
    // Profiles CRUD & Host List Rendering
    // =========================================================================
    renderHostList() {
      const rdpCount = this.profiles.filter((p) => p.protocol === "rdp").length;
      const vncCount = this.profiles.filter((p) => p.protocol === "vnc").length;
      const androidCount = this.profiles.filter((p) => p.protocol === "android").length;
      $("cntAll").textContent = String(this.profiles.length);
      $("cntRdp").textContent = String(rdpCount);
      $("cntVnc").textContent = String(vncCount);
      $("cntAndroid").textContent = String(androidCount);

      const list = $("hostList");
      const filtered = this.profiles.filter((p) => {
        if (this.filterProto !== "all" && p.protocol !== this.filterProto) return false;
        if (this.searchQuery) {
          const hay = (p.name + " " + p.host + " " + p.port + " " + p.protocol + " " + (p.username || "")).toLowerCase();
          if (!hay.includes(this.searchQuery)) return false;
        }
        return true;
      });

      if (!filtered.length) {
        list.innerHTML =
          '<div class="host-empty">' +
          (this.profiles.length === 0
            ? '暂无保存的主机。<br>点击上方 <strong>+ 新建</strong> 添加 Windows RDP 或 Linux VNC 主机。'
            : "没有匹配的主机。") +
          "</div>";
        return;
      }

      list.innerHTML = "";
      for (const p of filtered) {
        const activeSess = Array.from(this.sessions.values()).find((s) => s.profile.id === p.id);
        const card = document.createElement("div");
        card.className = "host-card" + (activeSess && activeSess.id === this.activeSessionId ? " connected" : "");
        const dotClass = !activeSess
          ? ""
          : activeSess.status === "connected"
          ? "ok"
          : activeSess.status === "error"
          ? "err"
          : "busy";
        const protoBadgeClass = p.protocol === "rdp" ? "proto-rdp" : p.protocol === "android" ? "proto-android" : "proto-vnc";
        const protoLabel = p.protocol === "android" ? "ADB" : p.protocol.toUpperCase();
        card.innerHTML =
          '<div class="hc-top">' +
          '<div class="hc-name"><span class="status-dot ' + dotClass + '"></span><span>' + escapeHtml(p.name) + "</span></div>" +
          '<span class="proto-tag ' + protoBadgeClass + '">' + protoLabel + "</span>" +
          "</div>" +
          '<div class="hc-addr">' + escapeHtml(p.host + ":" + p.port) + (p.username ? " · " + escapeHtml(p.username) : "") + "</div>" +
          '<div class="hc-foot">' +
          (p.protocol === "android"
            ? '<span class="hc-secret"><i class="fa fa-lock"></i> ADB RSA 托管</span>'
            : p.hasSecret
            ? '<span class="hc-secret"><i class="fa fa-lock"></i> 凭据已加密</span>'
            : "<span>连接时输入密码</span>") +
          '<div class="hc-actions">' +
          '<button type="button" class="hc-act-btn js-edit" title="编辑"><i class="fa fa-pencil"></i></button>' +
          '<button type="button" class="hc-act-btn del js-del" title="删除"><i class="fa fa-trash"></i></button>' +
          "</div></div>";

        card.onclick = (e) => {
          if (e.target.closest(".js-edit")) {
            this.openConnModal(p);
            return;
          }
          if (e.target.closest(".js-del")) {
            this.deleteProfile(p.id);
            return;
          }
          if (activeSess) {
            this.selectSession(activeSess.id);
          } else {
            this.connectProfile(p);
          }
          if (window.innerWidth <= 860) this.toggleSidebar(false);
        };
        list.appendChild(card);
      }
    }

    openConnModal(profile, defaultProto = "rdp") {
      $("connModalTitle").textContent = profile ? "编辑远程桌面连接" : "新建远程桌面连接";
      $("fId").value = profile ? profile.id : "";
      const proto = profile ? profile.protocol : defaultProto;
      this.setModalProtocol(proto, false);
      $("fName").value = profile ? profile.name : "";
      $("fHost").value = profile ? profile.host : "";
      $("fPort").value = profile ? profile.port : proto === "rdp" ? 3389 : proto === "android" ? 5555 : 5900;
      $("fUsername").value = profile ? profile.username || "" : "";
      $("fPassword").value = "";
      $("fPassword").placeholder = profile && profile.hasSecret ? "已加密保存（留空保持不变）" : "••••••••";
      $("fDomain").value = profile ? profile.domain || "" : "";
      $("fResolution").value = profile ? profile.resolution || "auto" : "auto";
      $("fVncQuality").value = profile ? String(profile.vncQuality || 6) : "6";
      $("fVncViewOnly").checked = !!(profile && profile.vncViewOnly);
      $("fRdpNla").checked = profile ? profile.rdpNla !== false : true;
      $("fRdpAudio").checked = profile ? profile.rdpAudio !== false : true;
      $("fRdpVdrive").checked = profile ? profile.rdpVdrive !== false : true;
      $("fAndroidMaxSize").value = profile ? String(profile.androidMaxSize ?? 1280) : "1280";
      $("fAndroidBitrate").value = profile ? profile.androidBitrate || "4000000:60" : "4000000:60";
      $("fAndroidAudio").checked = profile ? profile.androidAudio !== false : true;
      $("fSaveSecret").checked = profile ? !!profile.hasSecret : true;
      $("connModal").hidden = false;
      $("fName").focus();
    }

    setModalProtocol(proto, updateDefaultPort) {
      document.querySelectorAll(".proto-opt").forEach((b) => {
        b.classList.toggle("active", b.dataset.proto === proto);
      });
      const isRdp = proto === "rdp";
      const isVnc = proto === "vnc";
      const isAndroid = proto === "android";
      document.querySelectorAll(".rdp-only").forEach((el) => (el.hidden = !isRdp));
      document.querySelectorAll(".vnc-only").forEach((el) => (el.hidden = !isVnc));
      document.querySelectorAll(".android-only").forEach((el) => (el.hidden = !isAndroid));
      document.querySelectorAll(".cred-only").forEach((el) => (el.hidden = isAndroid));
      $("fUsername").placeholder = isRdp ? "Windows / Linux 用户名" : "留空（大多数 VNC 仅需密码）";
      if (updateDefaultPort) {
        const cur = Number($("fPort").value);
        if (!cur || cur === 3389 || cur === 5900 || cur === 5555) {
          $("fPort").value = isRdp ? 3389 : isAndroid ? 5555 : 5900;
        }
      }
    }

    async submitConnForm(connectImmediately) {
      const activeProtoBtn = document.querySelector(".proto-opt.active");
      const protocol = (activeProtoBtn && activeProtoBtn.dataset.proto) || "rdp";
      const name = $("fName").value.trim();
      const host = $("fHost").value.trim();
      const port = Number($("fPort").value) || (protocol === "rdp" ? 3389 : protocol === "android" ? 5555 : 5900);
      if (!name || !host) {
        toast("请填写连接名称和主机地址", "err");
        return;
      }

      const existingId = $("fId").value;
      const existing = this.profiles.find((p) => p.id === existingId);
      const id = existing ? existing.id : uid();
      const passwordInput = protocol === "android" ? "" : $("fPassword").value;
      const saveSecret = protocol !== "android" && $("fSaveSecret").checked;

      let hasSecret = existing ? !!existing.hasSecret : false;
      if (saveSecret) {
        if (passwordInput) {
          await secretSet("rdp_pw_" + id, passwordInput);
          hasSecret = true;
        }
      } else {
        await secretRemove("rdp_pw_" + id);
        hasSecret = false;
      }

      const profile = {
        id,
        protocol,
        name,
        host,
        port,
        username: protocol === "android" ? "" : $("fUsername").value.trim(),
        domain: $("fDomain").value.trim(),
        resolution: $("fResolution").value,
        vncQuality: Number($("fVncQuality").value || 6),
        vncViewOnly: $("fVncViewOnly").checked,
        rdpNla: $("fRdpNla").checked,
        rdpAudio: $("fRdpAudio").checked,
        rdpVdrive: $("fRdpVdrive").checked,
        androidMaxSize: Number($("fAndroidMaxSize").value ?? 1280),
        androidBitrate: $("fAndroidBitrate").value || "4000000:60",
        androidAudio: $("fAndroidAudio").checked,
        hasSecret,
        updatedAt: Date.now(),
      };

      if (existing) {
        const idx = this.profiles.indexOf(existing);
        this.profiles[idx] = profile;
      } else {
        this.profiles.unshift(profile);
      }
      saveJson(PROFILES_KEY, this.profiles);
      $("connModal").hidden = true;
      this.renderHostList();
      toast("已保存连接：" + name, "ok");

      if (connectImmediately) {
        await this.connectProfile(profile, passwordInput || null);
      }
    }

    async deleteProfile(id) {
      this.profiles = this.profiles.filter((p) => p.id !== id);
      saveJson(PROFILES_KEY, this.profiles);
      await secretRemove("rdp_pw_" + id);
      this.renderHostList();
      toast("已删除主机配置");
    }

    // =========================================================================
    // Session Lifecycle & Chrome Sync
    // =========================================================================
    async connectProfile(profile, overridePassword = null) {
      let password = overridePassword;
      if (password === null && profile.hasSecret) {
        password = await secretGet("rdp_pw_" + profile.id);
      }
      if (password === null) password = "";

      const creds = { username: profile.username || "", password };
      const session =
        profile.protocol === "rdp"
          ? new RdpSession(profile, creds, this)
          : profile.protocol === "android"
          ? new AndroidSession(profile, this)
          : new VncSession(profile, creds, this);

      this.sessions.set(session.id, session);
      $("viewportHost").appendChild(session.viewportEl);
      this.selectSession(session.id);
      session.connect();
    }

    selectSession(sessionId) {
      if (this.inAppPips.has(sessionId)) {
        this.restoreInAppPip(sessionId, false);
      }
      this.activeSessionId = sessionId;
      for (const [id, sess] of this.sessions.entries()) {
        if (this.inAppPips.has(id)) {
          sess.viewportEl.hidden = false;
        } else {
          sess.viewportEl.hidden = id !== sessionId;
        }
      }
      this.applyScaleMode();
      this.refreshChrome();
      this.renderHostList();
      this.renderFileDrawer();
      const s = this.activeSession();
      if (s) {
        $("clipTextarea").value = s.remoteClipText || "";
      }
    }

    async reconnectSession(sessionId) {
      const old = this.sessions.get(sessionId);
      if (!old) return;
      const profile = old.profile;
      const pw = old.creds ? old.creds.password : null;
      this.closeSession(sessionId);
      await this.connectProfile(profile, pw);
    }

    closeSession(sessionId) {
      if (this.inAppPips.has(sessionId)) {
        this.restoreInAppPip(sessionId, false);
      }
      if (this.osPip && this.osPip.sessionId === sessionId) {
        this.stopOsPip();
      }
      const sess = this.sessions.get(sessionId);
      if (!sess) return;
      sess.destroy();
      this.sessions.delete(sessionId);
      if (this.activeSessionId === sessionId) {
        const next = Array.from(this.sessions.keys()).find((k) => !this.inAppPips.has(k)) || null;
        this.activeSessionId = next;
        if (next) this.selectSession(next);
      }
      this.refreshChrome();
      this.renderHostList();
    }

    // =========================================================================
    // Picture-in-Picture: In-App Interactive Multi-PiP + OS-Level Desktop PiP
    // =========================================================================
    openInAppPip(sessionId) {
      const sess = this.sessions.get(sessionId);
      if (!sess) return;
      if (this.inAppPips.has(sessionId)) {
        const existing = this.inAppPips.get(sessionId);
        existing.winEl.style.zIndex = String(++this.pipZCounter);
        return;
      }

      const stageRect = $("stage").getBoundingClientRect();
      const isPortrait = sess.protocol === "android" && (sess.height || 1280) > (sess.width || 720);
      const w = Math.min(isPortrait ? 268 : 420, Math.max(220, Math.floor(stageRect.width * 0.44)));
      const h = Math.min(isPortrait ? 500 : 286, Math.max(180, Math.floor(stageRect.height * 0.68)));
      const offset = this.inAppPips.size * 28;
      const drawerShift = !$("fileDrawer").hidden && window.innerWidth > 860 ? 364 : 16;
      const left = Math.max(12, Math.floor(stageRect.width - w - drawerShift - offset));
      const top = Math.max(54, Math.floor(stageRect.height - h - 18 - offset));

      const winEl = document.createElement("div");
      winEl.className = "pip-win pip-" + sess.protocol;
      winEl.dataset.sessionId = sessionId;
      winEl.style.width = w + "px";
      winEl.style.height = h + "px";
      winEl.style.left = left + "px";
      winEl.style.top = top + "px";
      winEl.style.zIndex = String(++this.pipZCounter);

      const badgeCls = sess.protocol === "rdp" ? "proto-rdp" : sess.protocol === "android" ? "proto-android" : "proto-vnc";
      const badgeTxt = sess.protocol === "android" ? "ADB" : sess.protocol.toUpperCase();
      winEl.innerHTML =
        '<div class="pip-head">' +
        '<div class="pip-title"><span class="proto-tag ' + badgeCls + '">' + badgeTxt + "</span><span>" + escapeHtml(sess.profile.name) + "</span></div>" +
        '<div class="pip-actions">' +
        '<button type="button" class="pip-act js-pip-swap" title="与主画面互换"><i class="fa fa-exchange"></i></button>' +
        '<button type="button" class="pip-act js-pip-os" title="弹出系统桌面画中画"><i class="fa fa-external-link"></i></button>' +
        '<button type="button" class="pip-act js-pip-restore" title="还原为标签页"><i class="fa fa-window-maximize"></i></button>' +
        '<button type="button" class="pip-act close js-pip-close" title="收起小窗"><i class="fa fa-times"></i></button>' +
        "</div></div>" +
        '<div class="pip-body"></div>' +
        (sess.protocol === "android"
          ? '<div class="pip-android-bar">' +
            '<button type="button" data-act="back" title="返回"><i class="fa fa-chevron-left"></i></button>' +
            '<button type="button" data-act="home" title="主页"><i class="fa fa-home"></i></button>' +
            '<button type="button" data-act="recents" title="多任务"><i class="fa fa-clone"></i></button>' +
            '<button type="button" data-act="power" title="电源"><i class="fa fa-power-off"></i></button>' +
            "</div>"
          : "") +
        '<div class="pip-resize" title="拖拽缩放大小"></div>';

      const bodyEl = winEl.querySelector(".pip-body");
      sess.viewportEl.classList.add("is-pip");
      sess.viewportEl.hidden = false;
      bodyEl.appendChild(sess.viewportEl);
      if (sess.protocol === "vnc") sess.setScaleMode("fit");

      // Focus bump
      winEl.addEventListener("pointerdown", () => {
        winEl.style.zIndex = String(++this.pipZCounter);
      });

      // Header drag
      const headEl = winEl.querySelector(".pip-head");
      headEl.addEventListener("pointerdown", (e) => {
        if (e.target.closest(".pip-act")) return;
        e.preventDefault();
        headEl.setPointerCapture?.(e.pointerId);
        const startX = e.clientX;
        const startY = e.clientY;
        const origL = winEl.offsetLeft;
        const origT = winEl.offsetTop;
        const onMove = (ev) => {
          const sr = $("stage").getBoundingClientRect();
          const nl = Math.max(0, Math.min(sr.width - 80, origL + (ev.clientX - startX)));
          const nt = Math.max(0, Math.min(sr.height - 40, origT + (ev.clientY - startY)));
          winEl.style.left = nl + "px";
          winEl.style.top = nt + "px";
        };
        const onUp = () => {
          headEl.removeEventListener("pointermove", onMove);
          headEl.removeEventListener("pointerup", onUp);
          headEl.removeEventListener("pointercancel", onUp);
        };
        headEl.addEventListener("pointermove", onMove);
        headEl.addEventListener("pointerup", onUp);
        headEl.addEventListener("pointercancel", onUp);
      });

      // Corner resize
      const resizeEl = winEl.querySelector(".pip-resize");
      resizeEl.addEventListener("pointerdown", (e) => {
        e.preventDefault();
        e.stopPropagation();
        resizeEl.setPointerCapture?.(e.pointerId);
        const startX = e.clientX;
        const startY = e.clientY;
        const origW = winEl.offsetWidth;
        const origH = winEl.offsetHeight;
        const onMove = (ev) => {
          const nw = Math.max(210, Math.min(820, origW + (ev.clientX - startX)));
          const nh = Math.max(170, Math.min(760, origH + (ev.clientY - startY)));
          winEl.style.width = nw + "px";
          winEl.style.height = nh + "px";
        };
        const onUp = () => {
          resizeEl.removeEventListener("pointermove", onMove);
          resizeEl.removeEventListener("pointerup", onUp);
          resizeEl.removeEventListener("pointercancel", onUp);
        };
        resizeEl.addEventListener("pointermove", onMove);
        resizeEl.addEventListener("pointerup", onUp);
        resizeEl.addEventListener("pointercancel", onUp);
      });

      winEl.querySelector(".js-pip-swap").onclick = () => this.swapPipWithMain(sessionId);
      winEl.querySelector(".js-pip-os").onclick = () => this.startOsPip(sessionId);
      winEl.querySelector(".js-pip-restore").onclick = () => this.restoreInAppPip(sessionId, true);
      winEl.querySelector(".js-pip-close").onclick = () => this.restoreInAppPip(sessionId, true);
      winEl.querySelectorAll(".pip-android-bar button").forEach((btn) => {
        btn.onclick = () => sess.sendAction(btn.dataset.act);
      });

      $("pipLayer").appendChild(winEl);
      this.inAppPips.set(sessionId, { winEl, bodyEl });

      // If we just popped the active main session, activate another non-PiP session behind it
      if (this.activeSessionId === sessionId) {
        const nextMain = Array.from(this.sessions.keys()).find((k) => k !== sessionId && !this.inAppPips.has(k)) || null;
        this.activeSessionId = nextMain;
        if (nextMain) {
          this.selectSession(nextMain);
        } else {
          this.refreshChrome();
        }
      } else {
        this.refreshChrome();
      }
      toast("已开启工作台画中画（可直接拖拽缩放与点击操控）：" + sess.profile.name, "ok");
    }

    restoreInAppPip(sessionId, selectAfter = true) {
      const pip = this.inAppPips.get(sessionId);
      if (!pip) return;
      this.inAppPips.delete(sessionId);
      const sess = this.sessions.get(sessionId);
      if (sess) {
        sess.viewportEl.classList.remove("is-pip");
        $("viewportHost").appendChild(sess.viewportEl);
        sess.viewportEl.hidden = this.activeSessionId !== sessionId;
      }
      pip.winEl.remove();
      if (selectAfter && sess) {
        this.selectSession(sessionId);
      } else {
        this.refreshChrome();
      }
    }

    swapPipWithMain(pipSessionId) {
      const prevMainId = this.activeSessionId;
      this.restoreInAppPip(pipSessionId, true);
      if (prevMainId && prevMainId !== pipSessionId && this.sessions.has(prevMainId)) {
        this.openInAppPip(prevMainId);
      }
    }

    async startOsPip(sessionId) {
      const sess = this.sessions.get(sessionId);
      if (!sess) return;
      const srcCanvas = sess.getCanvasForScreenshot();
      if (!srcCanvas || !srcCanvas.width || !srcCanvas.height) {
        toast("当前画面尚未就绪，请等待连接出画后再开启系统画中画", "err");
        return;
      }
      if (!document.pictureInPictureEnabled || typeof HTMLVideoElement.prototype.requestPictureInPicture !== "function") {
        toast("当前浏览器不支持系统级画中画，已为你切换为工作台悬浮小窗", "err");
        this.openInAppPip(sessionId);
        return;
      }

      try {
        if (this.osPip) await this.stopOsPip();

        // Mirror canvas guarantees consistent 30fps captureStream across 2D (RDP/VNC) AND bitmaprenderer (Android WebCodecs)
        const mirror = document.createElement("canvas");
        mirror.width = srcCanvas.width;
        mirror.height = srcCanvas.height;
        const mctx = mirror.getContext("2d", { alpha: false });
        mctx.drawImage(srcCanvas, 0, 0);

        const stream = mirror.captureStream(30);
        const video = document.createElement("video");
        video.muted = true;
        video.playsInline = true;
        video.autoplay = true;
        video.style.cssText = "position:fixed;width:2px;height:2px;opacity:0;pointer-events:none;bottom:0;right:0;";
        video.srcObject = stream;
        document.body.appendChild(video);

        let alive = true;
        let lastDraw = 0;
        const pump = (ts) => {
          if (!alive) return;
          if (ts - lastDraw >= 32) {
            lastDraw = ts;
            const liveCanvas = sess.getCanvasForScreenshot();
            if (liveCanvas && liveCanvas.width > 0 && liveCanvas.height > 0) {
              if (mirror.width !== liveCanvas.width || mirror.height !== liveCanvas.height) {
                mirror.width = liveCanvas.width;
                mirror.height = liveCanvas.height;
              }
              try { mctx.drawImage(liveCanvas, 0, 0); } catch (_) {}
            }
          }
          if (this.osPip) this.osPip.rafId = requestAnimationFrame(pump);
        };

        this.osPip = { sessionId, video, stream, rafId: requestAnimationFrame(pump), mirror, stopFlag: () => { alive = false; } };

        await video.play();
        await video.requestPictureInPicture();

        video.addEventListener(
          "leavepictureinpicture",
          () => {
            this.stopOsPip();
          },
          { once: true }
        );
        this.refreshChrome();
        toast("已开启系统桌面画中画（切出浏览器也可置顶监控）：" + sess.profile.name, "ok");
      } catch (err) {
        await this.stopOsPip();
        toast("无法打开系统画中画（" + ((err && err.message) || err) + "），建议使用工作台悬浮小窗", "err");
      }
    }

    async stopOsPip() {
      const pip = this.osPip;
      this.osPip = null;
      if (!pip) return;
      try { pip.stopFlag && pip.stopFlag(); } catch (_) {}
      try { if (pip.rafId) cancelAnimationFrame(pip.rafId); } catch (_) {}
      try {
        if (document.pictureInPictureElement === pip.video) {
          await document.exitPictureInPicture();
        }
      } catch (_) {}
      try {
        pip.stream.getTracks().forEach((t) => t.stop());
      } catch (_) {}
      try { pip.video.remove(); } catch (_) {}
      this.refreshChrome();
    }

    refreshChrome() {
      const tabsEl = $("sessionTabs");
      tabsEl.innerHTML = "";
      for (const sess of this.sessions.values()) {
        const tab = document.createElement("div");
        tab.className = "s-tab" + (sess.id === this.activeSessionId ? " active" : "");
        const dotClass = sess.status === "connected" ? "ok" : sess.status === "error" ? "err" : "busy";
        const badgeCls = sess.protocol === "rdp" ? "proto-rdp" : sess.protocol === "android" ? "proto-android" : "proto-vnc";
        const badgeTxt = sess.protocol === "android" ? "ADB" : sess.protocol.toUpperCase();
        const isInPip = this.inAppPips.has(sess.id);
        const isOsPip = this.osPip && this.osPip.sessionId === sess.id;
        tab.innerHTML =
          '<span class="status-dot ' + dotClass + '"></span>' +
          '<span class="proto-tag ' + badgeCls + '">' + badgeTxt + "</span>" +
          '<span class="s-tab-name">' + escapeHtml(sess.profile.name) + "</span>" +
          (isInPip || isOsPip
            ? '<span class="s-tab-pip-badge">' + (isOsPip ? "桌面PiP" : "小窗") + "</span>"
            : '<button type="button" class="s-tab-pip-btn" title="缩为悬浮画中画小窗"><i class="fa fa-clone"></i></button>') +
          '<button type="button" class="s-tab-close" title="关闭会话">×</button>';
        tab.onclick = (e) => {
          if (e.target.closest(".s-tab-close")) {
            this.closeSession(sess.id);
            return;
          }
          if (e.target.closest(".s-tab-pip-btn")) {
            this.openInAppPip(sess.id);
            return;
          }
          this.selectSession(sess.id);
        };
        tabsEl.appendChild(tab);
      }

      const active = this.activeSession();
      const hasActive = !!active;
      $("welcomeView").hidden = hasActive;
      $("viewportHost").hidden = !hasActive;
      $("floatingToolbar").hidden = !hasActive;
      $("telemetryPill").hidden = !hasActive;

      if (!hasActive) {
        $("fileDrawer").hidden = true;
        $("audioUnlockBanner").hidden = true;
        $("androidNavBar").hidden = true;
        return;
      }

      const isRdp = active.protocol === "rdp";
      const isAndroid = active.protocol === "android";
      $("audioControlWrap").hidden = !(isRdp || isAndroid);
      $("btnFiles").hidden = !(isRdp || isAndroid);
      $("androidNavBar").hidden = !isAndroid;
      if (!isRdp && !isAndroid) {
        $("fileDrawer").hidden = true;
        $("audioUnlockBanner").hidden = true;
        $("stage").classList.remove("drawer-open");
      }

      // Telemetry Pill
      const dot = $("telemetryDot");
      dot.className = "status-dot " + (active.status === "connected" ? "ok" : active.status === "error" ? "err" : "busy");
      const engineLabel = isRdp ? "Rust IronRDP WASM" : isAndroid ? "ADB Scrcpy WebCodecs" : "noVNC";
      const dim = active.width && active.height ? active.width + "×" + active.height : "";
      const extra = isRdp && active.tlsInfo ? active.tlsInfo.split(" ")[0] : isAndroid ? active.deviceName || "" : "";
      $("telemetryText").textContent = [engineLabel, dim, extra].filter(Boolean).join(" · ");

      if (isRdp) {
        const badge = $("fileBadge");
        const count = active.remoteFiles.length + active.downloads.size;
        badge.textContent = String(count);
        badge.hidden = count === 0;
        this.refreshAudioUi();
      } else if (isAndroid) {
        $("fileBadge").hidden = true;
        this.refreshAudioUi();
      }
    }

    refreshAudioUi() {
      const s = this.activeSession();
      if (!s || (s.protocol !== "rdp" && s.protocol !== "android")) return;
      $("audioEnabledToggle").checked = s.audioEnabled;
      $("audioFormatMeta").textContent = s.audioFormat;
      $("audioBtnIco").className = s.audioEnabled ? "fa fa-volume-up" : "fa fa-volume-off";
      $("btnAudio").classList.toggle("audio-live", s.audioEnabled && s.status === "connected");
    }

    onSessionAudioPacket(sess) {
      if (sess.id !== this.activeSessionId) return;
      $("audioFormatMeta").textContent = sess.audioFormat;
      $("audioWaveBars").hidden = !sess.audioEnabled;
    }

    onSessionAudioVu(sess, left, right) {
      if (sess.id !== this.activeSessionId) return;
      $("vuFillL").style.width = Math.min(100, Math.round(left * 140)) + "%";
      $("vuFillR").style.width = Math.min(100, Math.round(right * 140)) + "%";
    }

    onSessionAudioSuspended(sess, suspended) {
      if (sess.id !== this.activeSessionId) return;
      $("audioUnlockBanner").hidden = !(suspended && sess.audioEnabled);
    }

    onSessionRemoteClipboard(sess, text) {
      if (sess.id !== this.activeSessionId) return;
      $("clipTextarea").value = text;
      $("clipStatusBadge").textContent = "已同步";
      if (navigator.clipboard && navigator.clipboard.writeText && text) {
        navigator.clipboard.writeText(text).catch(() => {});
      }
    }

    // =========================================================================
    // File Transfer & Virtual Drive Drawer
    // =========================================================================
    setFileDrawerTab(tab) {
      this.fileDrawerTab = tab;
      $("fdTabClip").classList.toggle("active", tab === "clip");
      $("fdTabVdrive").classList.toggle("active", tab === "vdrive");
      $("fdPaneClip").hidden = tab !== "clip";
      $("fdPaneVdrive").hidden = tab !== "vdrive";
      this.renderFileDrawer();
    }

    renderFileDrawer() {
      const s = this.activeSession();
      if (!s) return;

      const isAndroid = s.protocol === "android";
      $("fdRdpTabs").hidden = isAndroid;
      $("fdPaneAndroid").hidden = !isAndroid;
      if (isAndroid) {
        $("fdPaneClip").hidden = true;
        $("fdPaneVdrive").hidden = true;
        $("adbPathInput").value = s.adbPath;
        const aList = $("androidFilesList");
        if (s.adbLoading) {
          aList.innerHTML = '<div class="fd-empty">正在读取手机目录…</div>';
        } else if (!s.adbFiles.length) {
          aList.innerHTML = '<div class="fd-empty">当前目录为空。可拖放文件上传，拖入 .apk 将自动安装。</div>';
        } else {
          aList.innerHTML = "";
          for (const f of s.adbFiles) {
            const item = document.createElement("div");
            item.className = "fd-item";
            item.innerHTML =
              '<div class="fd-item-top">' +
              '<span class="fd-item-name" title="' + escapeHtml(f.name) + '">' + (f.isDir ? "📁 " : "📄 ") + escapeHtml(f.name) + "</span>" +
              (f.isDir
                ? '<button type="button" class="btn btn-sec btn-xs js-adb-open">打开</button>'
                : '<button type="button" class="btn btn-ok btn-xs js-adb-dl"><i class="fa fa-download"></i> 拉取</button>') +
              "</div>" +
              '<div class="fd-item-meta"><span>' + (f.isDir ? "文件夹" : formatBytes(f.size)) + "</span><span>ADB Sync</span></div>";
            if (f.isDir) {
              item.querySelector(".js-adb-open").onclick = () => {
                const next = (s.adbPath === "/" ? "" : s.adbPath) + "/" + f.name;
                s.loadAdbDir(next);
              };
            } else {
              item.querySelector(".js-adb-dl").onclick = () => s.downloadAdbFile(f.name);
            }
            aList.appendChild(item);
          }
        }
        return;
      }

      if (s.protocol !== "rdp") return;
      $("fdPaneClip").hidden = this.fileDrawerTab !== "clip";
      $("fdPaneVdrive").hidden = this.fileDrawerTab !== "vdrive";

      // Remote copied files (Ctrl+C on Windows)
      $("remoteFilesCount").textContent = s.remoteFiles.length + " 个";
      const rList = $("remoteFilesList");
      if (!s.remoteFiles.length) {
        rList.innerHTML = '<div class="fd-empty">在远端 Windows 选中文件按 Ctrl+C，这里会自动出现下载卡片。</div>';
      } else {
        rList.innerHTML = "";
        for (const f of s.remoteFiles) {
          const dl = s.downloads.get(f.index);
          const pct = dl && dl.total > 0 ? Math.min(100, Math.round((dl.received / dl.total) * 100)) : 0;
          const item = document.createElement("div");
          item.className = "fd-item";
          item.innerHTML =
            '<div class="fd-item-top">' +
            '<span class="fd-item-name" title="' + escapeHtml(f.name) + '">' + (f.is_dir ? "📁 " : "📄 ") + escapeHtml(f.name) + "</span>" +
            (f.is_dir
              ? '<span class="btn btn-sec btn-xs">文件夹</span>'
              : dl && dl.active
              ? '<span class="btn btn-sec btn-xs">' + pct + "%</span>"
              : '<button type="button" class="btn btn-ok btn-xs js-dl"><i class="fa fa-download"></i> 下载</button>') +
            "</div>" +
            (dl && dl.active ? '<div class="fd-pbar"><div class="fd-pbar-fill" style="width:' + pct + '%"></div></div>' : "") +
            '<div class="fd-item-meta"><span>' + formatBytes(f.size) + "</span><span>CLIPRDR 按需拉取</span></div>";
          const btn = item.querySelector(".js-dl");
          if (btn) btn.onclick = () => s.startDownloadRemoteFile(f.index);
          rList.appendChild(item);
        }
      }

      // Local files injected for remote Ctrl+V
      $("localFilesCount").textContent = s.localFiles.length + " 个";
      const lList = $("localFilesList");
      if (!s.localFiles.length) {
        lList.innerHTML = '<div class="fd-empty">暂未注入本地文件。</div>';
      } else {
        lList.innerHTML = "";
        for (const f of s.localFiles) {
          const item = document.createElement("div");
          item.className = "fd-item";
          item.innerHTML =
            '<div class="fd-item-top"><span class="fd-item-name">📄 ' + escapeHtml(f.name) + '</span><span class="badge-ok">已就绪</span></div>' +
            '<div class="fd-item-meta"><span>' + formatBytes(f.size) + "</span><span>远端按 Ctrl+V 粘贴</span></div>";
          lList.appendChild(item);
        }
      }

      // Virtual Drive files (RDPDR \\tsclient\BookStark)
      $("vdriveStatusBadge").textContent = s.vdriveMounted ? "● 已挂载" : "已注册通道";
      const vList = $("vdriveFilesList");
      if (!s.vdriveFiles.length) {
        vList.innerHTML = '<div class="fd-empty">共享盘暂无文件。</div>';
      } else {
        vList.innerHTML = "";
        for (const f of s.vdriveFiles) {
          const item = document.createElement("div");
          item.className = "fd-item";
          item.innerHTML =
            '<div class="fd-item-top">' +
            '<span class="fd-item-name" title="' + escapeHtml(f.name) + '">📄 ' + escapeHtml(f.name) + "</span>" +
            '<div style="display:flex;gap:4px;">' +
            '<button type="button" class="btn btn-sec btn-xs js-vdl" title="下载"><i class="fa fa-download"></i></button>' +
            '<button type="button" class="btn btn-sec btn-xs js-vdel" title="删除"><i class="fa fa-trash"></i></button>' +
            "</div></div>" +
            '<div class="fd-item-meta"><span>' + formatBytes(f.size) + "</span><span>\\\\tsclient\\BookStark</span></div>";
          item.querySelector(".js-vdl").onclick = () => s.downloadFromVdrive(f.name);
          item.querySelector(".js-vdel").onclick = () => s.deleteFromVdrive(f.name);
          vList.appendChild(item);
        }
      }
    }

    // =========================================================================
    // Modals, Popovers, Scale, Screenshot, Fullscreen
    // =========================================================================
    showTlsVerifyModal(session, ev) {
      this.tlsResolveSession = session;
      this.tlsPendingData = ev;
      const trustKey = session.profile.host + ":" + (Number(session.profile.port) || 3389);
      const saved = loadJson(TLS_TRUST_KEY, {})[trustKey];
      const changed = !!(saved && saved !== ev.fingerprint);

      $("tlsHost").textContent = trustKey;
      $("tlsSubject").textContent = ev.subject || "CN=Unknown";
      $("tlsProtocol").textContent = ev.protocol || "TLS";
      $("tlsFingerprint").textContent = ev.fingerprint || "";
      $("tlsAlertBox").classList.toggle("danger", changed);
      $("tlsWarnTitle").textContent = changed
        ? "⚠️ 远端主机 TLS 证书指纹发生变化！请确认是否可信"
        : "首次连接该主机，请核对服务器 TLS 证书指纹";
      $("tlsOldFpWrap").hidden = !changed;
      if (changed) $("tlsOldFingerprint").textContent = "此前信任指纹：" + saved;
      $("tlsModal").hidden = false;
    }

    resolveTlsModal(trusted, saveFingerprint) {
      $("tlsModal").hidden = true;
      const s = this.tlsResolveSession;
      const data = this.tlsPendingData;
      this.tlsResolveSession = null;
      this.tlsPendingData = null;
      if (s) s.approveTls(trusted, saveFingerprint, data && data.fingerprint);
    }

    promptAuthModal(title, askUser, defaultUser) {
      return new Promise((resolve) => {
        this.authResolve = resolve;
        $("authModalTitle").textContent = title;
        $("authUserWrap").hidden = !askUser;
        $("authUser").value = defaultUser || "";
        $("authPass").value = "";
        $("authModal").hidden = false;
        $("authPass").focus();
      });
    }

    closeAuthModal(result) {
      $("authModal").hidden = true;
      const r = this.authResolve;
      this.authResolve = null;
      if (r) r(result);
    }

    togglePopover(id) {
      const target = $(id);
      const willOpen = target.hidden;
      this.closeAllPopovers();
      if (willOpen) target.hidden = false;
    }

    closeAllPopovers() {
      ["comboMenu", "clipboardPopover", "audioPopover", "scaleMenu", "pipMenu"].forEach((id) => {
        const el = $(id);
        if (el) el.hidden = true;
      });
    }

    setScaleMode(mode) {
      this.scaleMode = mode;
      const labels = { fit: "自适应", actual: "1:1 像素", stretch: "铺满" };
      $("scaleLabel").textContent = labels[mode] || "自适应";
      $("scaleMenu").querySelectorAll(".menu-item").forEach((el) => {
        el.classList.toggle("active", el.dataset.scale === mode);
      });
      this.applyScaleMode();
    }

    applyScaleMode() {
      const s = this.activeSession();
      if (!s) return;
      s.viewportEl.classList.remove("scale-fit", "scale-actual", "scale-stretch");
      s.viewportEl.classList.add("scale-" + this.scaleMode);
      if (s.protocol === "vnc") s.setScaleMode(this.scaleMode);
    }

    takeScreenshot() {
      const s = this.activeSession();
      if (!s) return;
      const canvas = s.getCanvasForScreenshot();
      if (!canvas) {
        toast("当前画面尚未就绪", "err");
        return;
      }
      canvas.toBlob((blob) => {
        if (!blob) return;
        const ts = new Date().toISOString().replace(/[:.]/g, "-").slice(0, 19);
        triggerBrowserDownload(blob, "remote-" + s.profile.name + "-" + ts + ".png");
        toast("已保存远程桌面截图 PNG", "ok");
      }, "image/png");
    }

    toggleFullscreen() {
      if (!document.fullscreenElement) {
        $("stage").requestFullscreen?.().catch(() => {});
      } else {
        document.exitFullscreen?.().catch(() => {});
      }
    }

    toggleSidebar(force) {
      const sb = $("sidebar");
      const mobile = window.innerWidth <= 860;
      if (mobile) {
        const open = typeof force === "boolean" ? force : !sb.classList.contains("mobile-open");
        sb.classList.toggle("mobile-open", open);
        $("sidebarBackdrop").hidden = !open;
      } else {
        const collapse = typeof force === "boolean" ? !force : !sb.classList.contains("collapsed");
        sb.classList.toggle("collapsed", collapse);
      }
    }
  }

  function triggerBrowserDownload(blob, filename) {
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 10000);
  }

  function escapeHtml(str) {
    return String(str || "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  // Boot app
  window.__remoteDesktopApp = new RemoteDesktopApp();
})();
