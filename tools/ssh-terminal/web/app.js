/* Standalone BookStark SSH terminal. No administration endpoints or credentials. */
(function () {
  "use strict";
  const $ = (id) => document.getElementById(id),
    e = escHtml;
  const labels = {
    shell: ["Shell 程序", "Shell program"],
    defaultShell: ["服务器账户默认 Shell", "Account default shell"],
    customShell: ["自定义路径", "Custom path"],
    shellPath: ["Shell 程序路径", "Shell program path"],
    invalidShell: [
      "请输入 Shell 程序名或绝对路径，不要附加参数。",
      "Choose a shell program or enter an absolute path without arguments.",
    ],
    connections: ["连接", "Connections"],
    searchHosts: ["搜索连接", "Search connections"],
    savedLocally: ["配置保存到当前工具", "Saved in this tool"],
    newConnection: ["新建连接", "New connection"],
    editConnection: ["编辑连接", "Edit connection"],
    connectHint: [
      "连接你的服务器，开始终端会话。",
      "Connect to your server and start a terminal session.",
    ],
    name: ["连接名称", "Connection name"],
    host: ["主机地址", "Host"],
    port: ["端口", "Port"],
    user: ["用户名", "Username"],
    authentication: ["登录凭据", "Authentication"],
    passwordAuth: ["密码", "Password"],
    keyAuth: ["私钥", "Private key"],
    password: ["密码", "Password"],
    privateKey: ["私钥文件（PEM / OpenSSH）", "Private key (PEM / OpenSSH)"],
    passphrase: ["私钥口令（可选）", "Passphrase (optional)"],
    secretHint: [
      "密码、私钥及口令仅用于本次会话，不随连接配置保存。",
      "Passwords, private keys and passphrases are used only for this session and are never saved with connections.",
    ],
    delete: ["删除连接", "Delete connection"],
    save: ["保存连接", "Save connection"],
    connect: ["连接", "Connect"],
    disconnect: ["断开", "Disconnect"],
    search: ["搜索", "Search"],
    next: ["下一处", "Next"],
    reconnect: ["重新连接", "Reconnect"],
    connecting: ["正在连接…", "Connecting…"],
    connected: ["已连接", "Connected"],
    closed: ["已断开", "Disconnected"],
    saved: ["连接已保存", "Connection saved"],
    noHosts: ["暂无连接，点击 ＋ 新建", "No connections. Select + to add one."],
    noMatches: ["未找到连接", "No matching connections"],
    cancel: ["取消", "Cancel"],
    close: ["关闭", "Close"],
    confirmHost: ["确认主机密钥", "Verify host key"],
    changedHost: ["主机密钥已变化", "Host key changed"],
    hostWarning: [
      "请通过可信渠道核对服务器指纹后再连接。",
      "Verify the fingerprint through a trusted channel before connecting.",
    ],
    changedWarning: [
      "此主机的密钥与已保存记录不同。请核实服务器是否更换密钥。",
      "This host key differs from the saved key. Verify the change before connecting.",
    ],
    algorithm: ["算法", "Algorithm"],
    fingerprint: ["SHA256 指纹", "SHA256 fingerprint"],
    oldFingerprint: ["原指纹", "Previous fingerprint"],
    once: ["仅此一次", "Connect once"],
    trust: ["保存信任并连接", "Trust and connect"],
    confirmDelete: [
      "删除这个连接？已打开的会话不受影响。",
      "Delete this saved connection? Open sessions will continue.",
    ],
    confirmDisconnect: [
      "断开当前 SSH 会话？远端正在运行的进程可能会结束。",
      "Disconnect this SSH session? Remote processes may terminate.",
    ],
    confirmClose: [
      "关闭此会话？连接将断开。",
      "Close this session and disconnect?",
    ],
    keyRequired: ["请选择私钥文件", "Choose a private key file"],
    keyTooLarge: ["私钥文件不能超过 1 MB", "Private key must be under 1 MB"],
    bridgeMissing: [
      "当前运行环境未提供 TCP 桥接，请更新客户端。",
      "TCP bridge is unavailable. Update the client.",
    ],
    proxyDisabled: [
      "服务器未开启工具 TCP 代理，请在工具市场设置中开启。",
      "Tool TCP proxy is disabled. Enable it in market settings.",
    ],
    permissionDenied: [
      "此工具没有 TCP 连接权限，请重新安装并授权。",
      "TCP permission is missing. Reinstall and grant it.",
    ],
    connectFailed: [
      "无法连接目标主机，请检查地址、端口和服务器 TCP 代理设置。",
      "Cannot connect. Check the host, port and server TCP proxy settings.",
    ],
    moduleFailed: [
      "SSH 模块加载失败，请刷新或重新安装工具。",
      "SSH module failed to load. Reload or reinstall the tool.",
    ],
    copyHint: [
      "请先选中终端文本。也可以使用 Ctrl/Cmd + Shift + C 复制。",
      "Select terminal text first. You can also use Ctrl/Cmd + Shift + C.",
    ],
    copyFallback: [
      "浏览器未允许复制，请使用键盘快捷键复制选中文本。",
      "Clipboard unavailable. Use the keyboard shortcut to copy selected text.",
    ],
    copied: ["已复制", "Copied"],
    paste: ["粘贴到终端", "Paste into terminal"],
    pasteHint: [
      "在这里粘贴文本，确认后发送到当前终端。",
      "Paste text here, then confirm to send it to the terminal.",
    ],
    send: ["发送", "Send"],
    pasteWarning: [
      "文本含有换行，发送可能立即执行命令。确认发送？",
      "Text contains newlines and may execute commands immediately. Send it?",
    ],
    noResult: ["没有匹配", "No matches"],
    reconnectHint: [
      "连接已断开，输出已保留。重新连接需要再次提供凭据。",
      "Disconnected. Output is retained. Enter credentials again to reconnect.",
    ],
    invalidHost: [
      "请输入有效主机名或 IP，不包含协议、路径或端口。",
      "Enter a hostname or IP without a protocol, path or port.",
    ],
    storageError: [
      "无法保存配置，请检查工具存储空间。",
      "Cannot save configuration. Check tool storage.",
    ],
  };
  let lang =
    localStorage.getItem("ssh.language") ||
    ((navigator.language || "").startsWith("zh") ? "zh" : "en");
  const t = (k) => labels[k]?.[lang === "zh" ? 0 : 1] || k;
  window.__ = (key) =>
    key === "dialog.cancel"
      ? t("cancel")
      : key === "dialog.confirm"
        ? lang === "zh"
          ? "确认"
          : "Confirm"
        : "";
  function read(key, fallback) {
    try {
      return JSON.parse(localStorage.getItem(key)) || fallback;
    } catch (_) {
      return fallback;
    }
  }
  let hosts = read("ssh.hosts", []);
  if (!Array.isArray(hosts)) hosts = [];
  hosts = hosts.filter((h) => h && typeof h.host === "string").slice(0, 100);
  let known = read("ssh.known-hosts", {});
  if (!known || typeof known !== "object" || Array.isArray(known)) known = {};
  const sessions = new Map();
  let active = null,
    editorMode = true,
    reconnectTarget = null,
    keyText = "",
    fontSize = Number(localStorage.getItem("ssh.font-size")) || 13;
  fontSize = Math.max(10, Math.min(24, fontSize));
  let worker = null,
    engine = null,
    resolveEngine,
    rejectEngine,
    engineTimer,
    trustQueue = Promise.resolve();
  const encoder = new TextEncoder();
  function persist(key, value) {
    try {
      localStorage.setItem(key, JSON.stringify(value));
      return true;
    } catch (_) {
      BSDialog.toast(t("storageError"), "error");
      return false;
    }
  }
  function translate() {
    const a = lang === "zh";
    for (const [id, zh, en] of [
      ["sidebarToggle", "切换连接列表", "Toggle connections"],
      ["mobileToggle", "展开连接列表", "Open connections"],
      ["addHost", "新建连接", "New connection"],
      ["railAdd", "新建连接", "New connection"],
      ["newConnection", "新建连接", "New connection"],
      ["showPassword", "显示或隐藏密码", "Show or hide password"],
      ["searchTerminal", "搜索终端", "Search terminal"],
      ["copyTerminal", "复制选中内容", "Copy selected text"],
      ["pasteTerminal", "粘贴", "Paste"],
      ["smallerFont", "减小字号", "Smaller font"],
      ["largerFont", "增大字号", "Larger font"],
      ["closeSearch", "关闭搜索", "Close search"],
      ["sidebarShade", "关闭连接列表", "Close connections"],
    ]) {
      $(id).setAttribute("aria-label", a ? zh : en);
      $(id).title = a ? zh : en;
    }
    document.documentElement.lang = lang === "zh" ? "zh-CN" : "en";
    document
      .querySelectorAll("[data-i18n]")
      .forEach((el) => (el.textContent = t(el.dataset.i18n)));
    $("language").textContent = lang === "zh" ? "EN" : "中";
    $("hostSearch").placeholder = t("searchHosts");
    $("hostName").placeholder =
      lang === "zh" ? "例如：生产服务器" : "e.g. Production";
    $("terminalQuery").placeholder = t("search");
    $("formTitle").textContent = t(
      $("hostID").value ? "editConnection" : "newConnection",
    );
    renderHosts();
    renderTabs();
    updateSession();
  }
  $("language").onclick = () => {
    lang = lang === "zh" ? "en" : "zh";
    localStorage.setItem("ssh.language", lang);
    translate();
  };
  function collapse(value) {
    $("app").classList.toggle("collapsed", value);
    $("sidebarToggle").setAttribute("aria-expanded", String(!value));
    localStorage.setItem("ssh.sidebar-collapsed", String(value));
    setTimeout(fitActive, 180);
  }
  function mobile(open) {
    $("app").classList.toggle("mobile-open", open);
    $("sidebarShade").hidden = !open;
    $("mobileToggle").setAttribute("aria-expanded", String(open));
    if (!open) $("mobileToggle").focus();
  }
  $("sidebarToggle").onclick = () => {
    if (matchMedia("(max-width:640px)").matches) mobile(false);
    else collapse(!$("app").classList.contains("collapsed"));
  };
  $("mobileToggle").onclick = () =>
    mobile(!$("app").classList.contains("mobile-open"));
  $("sidebarShade").onclick = () => mobile(false);
  collapse(localStorage.getItem("ssh.sidebar-collapsed") === "true");
  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && $("app").classList.contains("mobile-open")) {
      mobile(false);
      event.preventDefault();
    }
  });
  function hostConfig() {
    return {
      id: $("hostID").value || crypto.randomUUID?.() || "host-" + Date.now(),
      name: $("hostName").value.trim(),
      host: $("host")
        .value.trim()
        .replace(/^\[|\]$/g, ""),
      port: Number($("port").value),
      user: $("username").value.trim(),
      shell:
        $("shell").value === "custom"
          ? $("customShell").value.trim()
          : $("shell").value,
      auth: document.querySelector("[name=auth]:checked").value,
    };
  }
  function validConfig(cfg) {
    if (!$("connectionForm").reportValidity()) return false;
    if (
      cfg.shell &&
      !["sh", "bash", "zsh", "fish"].includes(cfg.shell) &&
      (!cfg.shell.startsWith("/") || /[\x00\r\n]/.test(cfg.shell))
    ) {
      showError(t("invalidShell"));
      return false;
    }
    if (!cfg.host || /[\s/?#@\\]/.test(cfg.host) || cfg.host.includes("://")) {
      showError(t("invalidHost"));
      return false;
    }
    return true;
  }
  function showError(message) {
    $("formError").textContent = message;
    $("formError").hidden = false;
  }
  function shellFields() {
    const custom = $("shell").value === "custom";
    $("customShellField").hidden = !custom;
    $("customShell").required = custom;
  }
  $("shell").onchange = shellFields;
  function authFields() {
    const key = document.querySelector("[name=auth]:checked").value === "key";
    $("keyFields").hidden = !key;
    $("passwordFields").hidden = key;
  }
  document
    .querySelectorAll("[name=auth]")
    .forEach((el) => (el.onchange = authFields));
  $("showPassword").onclick = () => {
    const show = $("password").type === "password";
    $("password").type = show ? "text" : "password";
    $("showPassword").setAttribute("aria-pressed", String(show));
  };
  $("privateKey").onchange = async () => {
    keyText = "";
    const file = $("privateKey").files[0];
    $("keyName").textContent = "";
    if (!file) return;
    if (file.size > 1024 * 1024) {
      showError(t("keyTooLarge"));
      $("privateKey").value = "";
      return;
    }
    keyText = await file.text();
    $("keyName").textContent = file.name;
  };
  function openEditor(cfg = null, target = null) {
    editorMode = true;
    reconnectTarget = target;
    $("connectionForm").reset();
    keyText = "";
    $("keyName").textContent = "";
    $("password").type = "password";
    $("showPassword").setAttribute("aria-pressed", "false");
    $("hostID").value = cfg?.id || "";
    $("hostName").value = cfg?.name || "";
    $("host").value = cfg?.host || "";
    $("port").value = cfg?.port || 22;
    $("username").value = cfg?.user || "";
    document.querySelector(
      '[name=auth][value="' + (cfg?.auth === "key" ? "key" : "password") + '"]',
    ).checked = true;
    $("shell").value = cfg?.shell
      ? ["sh", "bash", "zsh", "fish"].includes(cfg.shell)
        ? cfg.shell
        : "custom"
      : "";
    $("customShell").value = $("shell").value === "custom" ? cfg.shell : "";
    shellFields();
    authFields();
    $("deleteHost").hidden = !hosts.some((h) => h.id === cfg?.id);
    $("formTitle").textContent = t(cfg ? "editConnection" : "newConnection");
    $("formError").hidden = true;
    $("editor").hidden = false;
    $("terminalWorkspace").hidden = true;
    mobile(false);
    renderTabs();
    renderHosts();
    $("host").focus();
  }
  for (const id of ["addHost", "railAdd", "newConnection"])
    $(id).onclick = () => openEditor();
  function saveHost(cfg) {
    cfg = {
      id: cfg.id,
      name: cfg.name || cfg.host,
      host: cfg.host,
      port: cfg.port,
      user: cfg.user,
      auth: cfg.auth,
      shell: cfg.shell,
    };
    const list = hosts.filter((h) => h.id !== cfg.id);
    if (list.length >= 100) {
      showError(
        lang === "zh" ? "最多保存 100 个连接" : "Up to 100 saved connections",
      );
      return false;
    }
    list.push(cfg);
    if (!persist("ssh.hosts", list)) return false;
    hosts = list;
    $("hostID").value = cfg.id;
    $("deleteHost").hidden = false;
    $("formTitle").textContent = t("editConnection");
    renderHosts();
    return true;
  }
  $("saveHost").onclick = () => {
    const cfg = hostConfig();
    if (validConfig(cfg) && saveHost(cfg))
      BSDialog.toast(t("saved"), "success");
  };
  $("deleteHost").onclick = async () => {
    if (!(await BSDialog.confirm2(t("confirmDelete")))) return;
    const list = hosts.filter((h) => h.id !== $("hostID").value);
    if (persist("ssh.hosts", list)) {
      hosts = list;
      openEditor();
    }
  };
  function renderHosts() {
    const q = $("hostSearch").value.trim().toLowerCase();
    $("hostList").replaceChildren();
    const items = hosts.filter((h) =>
      [h.name, h.host, h.user].join(" ").toLowerCase().includes(q),
    );
    for (const cfg of items) {
      const b = document.createElement("button");
      b.type = "button";
      b.className =
        "host-row" +
        (editorMode && $("hostID").value === cfg.id ? " selected" : "");
      b.innerHTML =
        '<span class="host-glyph" aria-hidden="true">›_</span><span class="host-text"><strong>' +
        e(cfg.name || cfg.host) +
        "</strong><small>" +
        e(cfg.user) +
        "@" +
        e(cfg.host) +
        ":" +
        e(cfg.port) +
        "</small></span>";
      b.onclick = () => openEditor(cfg);
      $("hostList").appendChild(b);
    }
    if (!items.length) {
      const p = document.createElement("p");
      p.className = "hint";
      p.textContent = t(hosts.length ? "noMatches" : "noHosts");
      $("hostList").appendChild(p);
    }
  }
  $("hostSearch").oninput = renderHosts;
  function renderTabs() {
    const container = $("sessions");
    container.replaceChildren();
    for (const s of sessions.values()) {
      const el = document.createElement("div");
      el.className = "tab" + (!editorMode && active === s.id ? " active" : "");
      el.innerHTML =
        '<span class="dot ' +
        (s.state === "connected" ? "online" : "") +
        '" aria-hidden="true"></span><button type="button" role="tab" aria-selected="' +
        (!editorMode && active === s.id) +
        '">' +
        e(s.cfg.name || s.cfg.host) +
        '</button><button type="button" class="close-tab" aria-label="' +
        e(t("close")) +
        '">×</button>';
      el.querySelector("[role=tab]").onclick = () => activate(s.id);
      el.querySelector(".close-tab").onclick = () => closeSession(s);
      container.appendChild(el);
    }
  }
  function activate(id) {
    if (!sessions.has(id)) return;
    active = id;
    editorMode = false;
    reconnectTarget = null;
    $("editor").hidden = true;
    $("terminalWorkspace").hidden = false;
    for (const s of sessions.values()) s.el.hidden = s.id !== id;
    mobile(false);
    renderTabs();
    updateSession();
    requestAnimationFrame(() => {
      fitActive();
      sessions.get(id)?.term.focus();
    });
  }
  const reasonLabels = {
    "Shell 程序无效，请使用程序名或绝对路径":
      "Invalid shell program. Choose a program or absolute path.",
    "连接超时，请重试": "Connection timed out. Try again.",
    "无法解析私钥，请检查格式和口令":
      "Cannot parse the private key. Check its format and passphrase.",
    "SSH 连接失败：": "SSH connection failed: ",
    "无法创建 SSH 会话：": "Cannot create an SSH session: ",
    "服务器拒绝 PTY：": "Server rejected PTY: ",
    无法打开标准输入: "Cannot open standard input.",
    "Shell 已退出：": "Shell exited: ",
    "无法启动 Shell：": "Cannot start a shell: ",
    连接已断开: "Disconnected.",
    会话已结束: "Session ended.",
    输入失败: "Input failed.",
    输入队列已满: "Input queue is full.",
    接收队列已满: "Receive queue is full.",
    "TCP 写入失败": "TCP write failed.",
    主机密钥未确认: "Host key was not accepted.",
  };
  function reasonText(reason) {
    if (lang === "zh") return reason;
    for (const [zh, en] of Object.entries(reasonLabels))
      reason = reason.replaceAll(zh, en);
    return reason;
  }
  function updateSession() {
    const s = sessions.get(active);
    if (!s) return;
    $("sessionHost").textContent =
      s.cfg.user +
      "@" +
      s.cfg.host +
      ":" +
      s.cfg.port +
      " · " +
      (s.cfg.shell || t("defaultShell"));
    $("sessionStatus").textContent = t(s.state);
    $("statusDot").classList.toggle("online", s.state === "connected");
    $("dimensions").textContent = s.term.cols + " × " + s.term.rows;
    $("disconnect").disabled = s.state === "closed";
    $("connectionBanner").hidden = s.state === "connected";
    $("connectionMessage").textContent =
      s.state === "connecting"
        ? t("connecting")
        : reasonText(s.reason) || t("reconnectHint");
    $("reconnect").hidden = s.state !== "closed";
  }
  async function closeSession(s) {
    if (s.state !== "closed" && !(await BSDialog.confirm2(t("confirmClose"))))
      return;
    stop(s);
    s.term.dispose();
    s.el.remove();
    sessions.delete(s.id);
    if (active === s.id) {
      const last = [...sessions.keys()].pop();
      if (last) activate(last);
      else {
        active = null;
        openEditor();
      }
    }
    renderTabs();
  }
  function stop(s) {
    s.state = "closed";
    s.trustDialog?.close();
    s.socket?.close();
    s.readAck?.();
    s.readAck = null;
    s.inputAck?.();
    s.inputAck = null;
    if (worker) worker.postMessage({ type: "close", id: s.run });
    updateSession();
    renderTabs();
  }
  function ensureEngine() {
    if (engine) return engine;
    engine = new Promise((resolve, reject) => {
      resolveEngine = resolve;
      rejectEngine = reject;
      engineTimer = setTimeout(() => reject(Error(t("moduleFailed"))), 30000);
      worker = new Worker("ssh-worker.js");
      worker.onmessage = onWorker;
      worker.onerror = () => {
        clearTimeout(engineTimer);
        reject(Error(t("moduleFailed")));
        for (const s of sessions.values()) finish(s, t("moduleFailed"));
      };
    });
    return engine;
  }
  function finish(s, reason) {
    s.trustDialog?.close();
    s.state = "closed";
    s.reason = reason || t("reconnectHint");
    s.socket?.close();
    s.readAck?.();
    s.readAck = null;
    s.inputAck?.();
    s.inputAck = null;
    renderTabs();
    updateSession();
  }
  function onWorker(event) {
    const m = event.data;
    if (m.type === "ready") {
      clearTimeout(engineTimer);
      resolveEngine();
      return;
    }
    if (m.type === "fatal") {
      clearTimeout(engineTimer);
      rejectEngine(Error(t("moduleFailed")));
      for (const s of sessions.values()) finish(s, t("moduleFailed"));
      return;
    }
    const s = [...sessions.values()].find((item) => item.run === m.id);
    if (!s) return;
    switch (m.type) {
      case "transport-write": {
        const socket = s.socket;
        Promise.resolve()
          .then(() => socket.send(m.data))
          .then(() =>
            worker.postMessage({ type: "write-ack", id: s.run, ok: true }),
          )
          .catch(() =>
            worker.postMessage({ type: "write-ack", id: s.run, ok: false }),
          );
        break;
      }
      case "read-ack":
        s.readAck?.();
        s.readAck = null;
        break;
      case "host-key":
        trustQueue = trustQueue.then(() => confirmKey(s, m)).catch(() => {});
        break;
      case "connected":
        s.state = "connected";
        s.reason = "";
        renderTabs();
        updateSession();
        fitActive();
        worker.postMessage({
          type: "resize",
          id: s.run,
          cols: s.term.cols,
          rows: s.term.rows,
        });
        s.term.focus();
        break;
      case "output":
        s.term.write(m.data, () =>
          worker?.postMessage({ type: "output-ack", id: s.run }),
        );
        break;
      case "input-ack":
        s.inputAck?.();
        s.inputAck = null;
        break;
      case "closed":
        finish(s, m.reason);
        break;
    }
  }
  async function confirmKey(s, key) {
    if (s.state === "closed") return;
    const name = JSON.stringify([s.cfg.host.toLowerCase(), s.cfg.port]),
      old = known[name];
    if (old?.key === key.key) {
      worker.postMessage({ type: "trust", id: s.run, accept: true });
      return;
    }
    const changed = Boolean(old);
    const body =
      '<p class="' +
      (changed ? "changed-key" : "hint") +
      '">' +
      e(t(changed ? "changedWarning" : "hostWarning")) +
      '</p><dl class="key-info"><dt>' +
      e(t("host")) +
      "</dt><dd>" +
      e(key.host) +
      ":" +
      e(key.port) +
      "</dd><dt>" +
      e(t("algorithm")) +
      "</dt><dd>" +
      e(key.algorithm) +
      "</dd><dt>" +
      e(t("fingerprint")) +
      '</dt><dd id="hostFingerprint">' +
      e(key.fingerprint) +
      "</dd>" +
      (changed
        ? "<dt>" +
          e(t("oldFingerprint")) +
          "</dt><dd>" +
          e(old.fingerprint) +
          "</dd>"
        : "") +
      '</dl><div class="dialog-actions"><button data-trust="cancel">' +
      e(t("cancel")) +
      '</button><button data-trust="once">' +
      e(t("once")) +
      '</button><button data-trust="save" class="primary">' +
      e(t("trust")) +
      "</button></div>";
    const dialog = createBSDialog(
      t(changed ? "changedHost" : "confirmHost"),
      body,
      t("close"),
    );
    const result = await new Promise((resolve) => {
      dialog.addEventListener("close", () => resolve("cancel"), { once: true });
      for (const b of dialog.querySelectorAll("[data-trust]"))
        b.onclick = () => {
          resolve(b.dataset.trust);
          dialog.close();
        };
      s.trustDialog = dialog;
    });
    s.trustDialog = null;
    if (s.state === "closed") return;
    if (result === "save") {
      const next = {
        ...known,
        [name]: {
          key: key.key,
          fingerprint: key.fingerprint,
          algorithm: key.algorithm,
        },
      };
      if (!persist("ssh.known-hosts", next)) {
        worker.postMessage({ type: "trust", id: s.run, accept: false });
        return;
      }
      known = next;
    }
    worker.postMessage({
      type: "trust",
      id: s.run,
      accept: result !== "cancel",
    });
  }
  function createSession(cfg) {
    const id = "ssh-" + Date.now() + "-" + Math.random().toString(36).slice(2);
    const el = document.createElement("div");
    el.className = "terminal-panel";
    const mount = document.createElement("div");
    mount.className = "terminal-mount";
    el.appendChild(mount);
    $("terminalStack").appendChild(el);
    const term = new Terminal({
      fontSize,
      fontFamily: "ui-monospace, SFMono-Regular, Menlo, Consolas, monospace",
      cursorBlink: true,
      convertEol: true,
      scrollback: 5000,
      theme: {
        background: "#080b10",
        foreground: "#d8e4f0",
        cursor: "#f8fafc",
      },
      allowProposedApi: false,
    });
    const fit = new FitAddon.FitAddon();
    term.loadAddon(fit);
    term.open(mount);
    const s = {
      id,
      run: id + "-run-1",
      cfg,
      term,
      fit,
      el,
      state: "connecting",
      reason: "",
      socket: null,
      readAck: null,
      inputAck: null,
      inputChain: Promise.resolve(),
    };
    sessions.set(id, s);
    term.onData((text) => sendInput(sessions.get(id), text));
    term.onResize(({ cols, rows }) => {
      const current = sessions.get(id);
      if (current?.state === "connected")
        worker.postMessage({ type: "resize", id: current.run, cols, rows });
      if (active === id) $("dimensions").textContent = cols + " × " + rows;
    });
    return s;
  }
  let ctrl = false,
    alt = false;
  function sendInput(s, text) {
    if (s?.state !== "connected") return;
    if (ctrl && text.length === 1) {
      const code = text.toUpperCase().charCodeAt(0);
      if (code >= 64 && code <= 95) text = String.fromCharCode(code - 64);
    }
    if (alt) text = "\x1b" + text;
    ctrl = alt = false;
    document
      .querySelectorAll("[data-key=ctrl],[data-key=alt]")
      .forEach((el) => el.setAttribute("aria-pressed", "false"));
    const bytes = encoder.encode(text);
    if (bytes.length > 1024 * 1024) {
      BSDialog.toast(
        lang === "zh" ? "单次输入不能超过 1 MB" : "Input must be under 1 MB",
        "error",
      );
      return;
    }
    s.inputChain = s.inputChain
      .then(async () => {
        for (
          let offset = 0;
          offset < bytes.length && s.state === "connected";
          offset += 32768
        ) {
          await new Promise((resolve) => {
            s.inputAck = resolve;
            worker.postMessage({
              type: "input",
              id: s.run,
              data: bytes.slice(offset, offset + 32768),
            });
          });
        }
      })
      .catch(() => {});
  }
  function friendlyError(error) {
    const code = error?.code || error?.message || "";
    return /socket_proxy_disabled/.test(code)
      ? t("proxyDisabled")
      : /permission_denied/.test(code)
        ? t("permissionDenied")
        : t("connectFailed");
  }
  $("connectionForm").onsubmit = async (event) => {
    event.preventDefault();
    const cfg = hostConfig();
    if (!validConfig(cfg)) return;
    if (cfg.auth === "key" && !keyText) {
      showError(t("keyRequired"));
      return;
    }
    if (!window.BookStark?.sockets?.connect) {
      showError(t("bridgeMissing"));
      return;
    }
    if (
      [...sessions.values()].filter((s) => s.state !== "closed").length >= 8
    ) {
      showError(
        lang === "zh" ? "最多同时连接 8 个会话" : "Up to 8 live sessions",
      );
      return;
    }
    const credentials = {
      password: $("password").value,
      key: keyText,
      passphrase: $("passphrase").value,
    };
    $("password").value = "";
    $("passphrase").value = "";
    $("privateKey").value = "";
    keyText = "";
    $("keyName").textContent = "";
    $("connect").disabled = true;
    let s = reconnectTarget && sessions.get(reconnectTarget);
    if (!s || s.state !== "closed") s = createSession(cfg);
    else {
      const previous = s;
      s = {
        ...previous,
        cfg,
        run: previous.id + "-run-" + Date.now(),
        state: "connecting",
        reason: "",
        socket: null,
        readAck: null,
        inputAck: null,
        inputChain: Promise.resolve(),
        trustDialog: null,
      };
      sessions.set(s.id, s);
      s.term.writeln("\r\n\x1b[90m— " + t("reconnect") + " —\x1b[0m");
    }
    activate(s.id);
    $("connect").disabled = false;
    const current = () => sessions.get(s.id) === s && s.state !== "closed";
    try {
      await ensureEngine();
      if (!current()) return;
      const transport = await BookStark.sockets.connect({
        host: cfg.host,
        port: cfg.port,
      });
      if (!current()) {
        transport.close();
        return;
      }
      s.socket = transport;
      worker.postMessage({
        ...cfg,
        ...credentials,
        type: "connect",
        id: s.run,
        cols: s.term.cols,
        rows: s.term.rows,
      });
      credentials.password = credentials.key = credentials.passphrase = "";
      const socket = s.socket;
      socket.closed.then(() => {
        if (current() && s.socket === socket) {
          worker.postMessage({ type: "close", id: s.run });
          finish(s, t("reconnectHint"));
        }
      });
      const reader = socket.readable.getReader();
      (async () => {
        try {
          while (current()) {
            const { value, done } = await reader.read();
            if (done || !current()) break;
            await new Promise((resolve) => {
              s.readAck = resolve;
              worker.postMessage({ type: "data", id: s.run, data: value });
            });
          }
        } catch (_) {
          if (s.state !== "closed") stop(s);
        } finally {
          reader.releaseLock();
        }
      })();
    } catch (error) {
      if (current())
        finish(
          s,
          error.message === t("moduleFailed")
            ? t("moduleFailed")
            : friendlyError(error),
        );
    } finally {
      credentials.password = credentials.key = credentials.passphrase = "";
      $("connect").disabled = false;
    }
  };
  function fitActive() {
    const s = sessions.get(active);
    if (s && !editorMode) {
      try {
        s.fit.fit();
      } catch (_) {}
      updateSession();
    }
  }
  new ResizeObserver(fitActive).observe($("terminalStack"));
  $("disconnect").onclick = async () => {
    const s = sessions.get(active);
    if (s && (await BSDialog.confirm2(t("confirmDisconnect")))) stop(s);
  };
  $("reconnect").onclick = () => {
    const s = sessions.get(active);
    if (s) openEditor(s.cfg, s.id);
  };
  function setFont(delta) {
    fontSize = Math.max(10, Math.min(24, fontSize + delta));
    localStorage.setItem("ssh.font-size", String(fontSize));
    for (const s of sessions.values()) s.term.options.fontSize = fontSize;
    fitActive();
  }
  $("smallerFont").onclick = () => setFont(-1);
  $("largerFont").onclick = () => setFont(1);
  $("searchTerminal").onclick = () => {
    $("searchBar").hidden = !$("searchBar").hidden;
    if (!$("searchBar").hidden) $("terminalQuery").focus();
    fitActive();
  };
  $("closeSearch").onclick = () => {
    $("searchBar").hidden = true;
    fitActive();
    sessions.get(active)?.term.focus();
  };
  function findNext() {
    const s = sessions.get(active),
      q = $("terminalQuery").value.toLowerCase();
    if (!s || !q) return;
    const buffer = s.term.buffer.active,
      matches = [];
    for (let y = 0; y < buffer.length; y++) {
      const line = buffer.getLine(y),
        columns = [];
      let text = "";
      for (let x = 0; x < line.length; x++) {
        const cell = line.getCell(x),
          width = cell.getWidth();
        if (!width) continue;
        const chars = cell.getChars() || " ";
        text += chars;
        for (let n = 0; n < chars.length; n++)
          columns.push({ start: x, end: x + width });
      }
      const lower = text.toLowerCase();
      for (
        let at = lower.indexOf(q);
        at >= 0;
        at = lower.indexOf(q, at + Math.max(q.length, 1))
      ) {
        const start = columns[at],
          end = columns[at + q.length - 1];
        if (start && end)
          matches.push({ x: start.start, y, length: end.end - start.start });
      }
    }
    if (!matches.length) {
      $("searchResult").textContent = t("noResult");
      return;
    }
    if (s.searchKey !== q) {
      s.searchKey = q;
      s.searchAfter = null;
    }
    let index = s.searchAfter
      ? matches.findIndex(
          (m) =>
            m.y > s.searchAfter.y ||
            (m.y === s.searchAfter.y && m.x > s.searchAfter.x),
        )
      : 0;
    if (index < 0) index = 0;
    const match = matches[index];
    s.term.select(match.x, match.y, match.length);
    s.term.scrollToLine(Math.max(0, match.y - 2));
    s.searchAfter = match;
    $("searchResult").textContent = index + 1 + " / " + matches.length;
  }
  $("findNext").onclick = findNext;
  $("terminalQuery").onkeydown = (event) => {
    if (event.key === "Enter") {
      event.preventDefault();
      findNext();
    }
  };
  $("copyTerminal").onclick = async () => {
    const s = sessions.get(active),
      text = s?.term.getSelection();
    if (!text) {
      BSDialog.toast(t("copyHint"));
      return;
    }
    try {
      await navigator.clipboard.writeText(text);
      BSDialog.toast(t("copied"), "success");
    } catch (_) {
      BSDialog.toast(t("copyFallback"));
    }
  };
  async function pasteText(text) {
    const s = sessions.get(active);
    if (s?.state !== "connected" || !text) return;
    if (/[\r\n]/.test(text) && !(await BSDialog.confirm2(t("pasteWarning"))))
      return;
    s.term.paste(text);
    s.term.focus();
  }
  $("pasteTerminal").onclick = async () => {
    try {
      const text = await navigator.clipboard.readText();
      await pasteText(text);
      return;
    } catch (_) {}
    const dialog = createBSDialog(
      t("paste"),
      '<p class="hint">' +
        e(t("pasteHint")) +
        '</p><label class="sr-only" for="pasteText">' +
        e(t("paste")) +
        '</label><textarea id="pasteText" spellcheck="false"></textarea><div class="dialog-actions"><button id="cancelPaste">' +
        e(t("cancel")) +
        '</button><button id="sendPaste" class="primary">' +
        e(t("send")) +
        "</button></div>",
      t("close"),
    );
    $("cancelPaste").onclick = () => dialog.close();
    $("sendPaste").onclick = () => {
      const text = $("pasteText").value;
      dialog.close();
      pasteText(text);
    };
    $("pasteText").focus();
  };
  const keys = {
    esc: "\x1b",
    tab: "\t",
    left: "\x1b[D",
    down: "\x1b[B",
    up: "\x1b[A",
    right: "\x1b[C",
  };
  for (const b of $("extraKeys").querySelectorAll("button")) {
    b.onpointerdown = (event) => event.preventDefault();
    b.onclick = () => {
      const key = b.dataset.key;
      if (key === "ctrl" || key === "alt") {
        if (key === "ctrl") ctrl = !ctrl;
        else alt = !alt;
        b.setAttribute("aria-pressed", String(key === "ctrl" ? ctrl : alt));
        sessions.get(active)?.term.focus();
      } else {
        sendInput(sessions.get(active), keys[key]);
        sessions.get(active)?.term.focus();
      }
    };
  }
  window.addEventListener("beforeunload", (event) => {
    if ([...sessions.values()].some((s) => s.state !== "closed")) {
      event.preventDefault();
      event.returnValue = "";
    }
  });
  window.addEventListener("pagehide", () => {
    for (const s of sessions.values()) s.socket?.close();
    worker?.terminate();
  });
  translate();
  authFields();
})();
