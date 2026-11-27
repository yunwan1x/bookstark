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
      "连接你的服务器，开始终端与 SFTP 会话。",
      "Connect to your server for terminal and SFTP.",
    ],
    davConnectHint: [
      "通过 BookStark TCP 直连 WebDAV（无跨域限制），支持在线浏览、编辑与上传下载。",
      "Connect directly to WebDAV via BookStark TCP sockets (no CORS) to browse, edit, and transfer files.",
    ],
    filterAll: ["全部", "All"],
    modeTerminal: ["终端", "Terminal"],
    modeSplit: ["分屏", "Split"],
    modeFiles: ["文件", "Files"],
    davUrl: ["WebDAV 地址 (URL)", "WebDAV URL"],
    davUrlHint: [
      "支持 Alist / Nextcloud / OwnCloud / 群晖 / 坚果云；通过 BookStark TCP 直连无跨域限制。",
      "Works with Alist, Nextcloud, OwnCloud, Synology & more via direct TCP without CORS.",
    ],
    davBasePath: ["初始路径（可选）", "Initial path (optional)"],
    davInsecure: [
      "允许自签名 HTTPS 证书（适合内网 NAS / PVE）",
      "Allow self-signed HTTPS certificates (for LAN NAS / homelab)",
    ],
    testConnection: ["测试连接", "Test connection"],
    invalidDavUrl: [
      "请输入有效的 http:// 或 https:// WebDAV 地址。",
      "Enter a valid http:// or https:// WebDAV URL.",
    ],
    upload: ["上传", "Upload"],
    mkdir: ["新建", "New folder"],
    newFile: ["新文件", "New file"],
    followCwd: ["跟随终端目录", "Follow terminal CWD"],
    showHidden: ["隐藏文件", "Hidden"],
    loadingDir: ["正在读取目录…", "Loading directory…"],
    emptyDir: [
      "当前目录为空，可拖拽本地文件到此上传",
      "Directory is empty. Drag & drop files here to upload.",
    ],
    colName: ["名称", "Name"],
    colSize: ["大小", "Size"],
    colMode: ["权限", "Mode"],
    colTime: ["修改时间", "Modified"],
    colAct: ["操作", "Actions"],
    saveRemote: ["保存", "Save"],
    download: ["下载", "Download"],
    deleteItem: ["删除", "Delete"],
    keyClear: ["清屏", "Clear"],
    keyCopy: ["复制", "Copy"],
    keyPaste: ["粘贴", "Paste"],
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
      "勾选后加密保存，下次打开自动填充；导出工具包不含登录凭据。",
      "When checked, credentials are encrypted and filled next time. Exported tool packages contain no credentials.",
    ],
    remember: ["记住登录凭据", "Remember credentials"],
    secretFailed: ["凭据保存或读取失败，请检查工具文件权限后重试。", "Could not save or load credentials. Check tool file permissions and retry."],
    savedKey: ["已保存：", "Saved: "],
    delete: ["删除连接", "Delete connection"],
    save: ["保存连接", "Save connection"],
    connect: ["连接", "Connect"],
    disconnect: ["断开", "Disconnect"],
    zenMode: ["专注模式（最大化终端）", "Focus mode (maximize terminal)"],
    exitZen: ["退出专注", "Exit focus"],
    moreActions: ["更多操作", "More actions"],
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
      "连接已断开，输出已保留。可以重新连接。",
      "Disconnected. Output is retained. You can reconnect.",
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
  hosts = hosts
    .filter((h) => h && (typeof h.host === "string" || typeof h.url === "string"))
    .slice(0, 100);
  let known = read("ssh.known-hosts", {});
  if (!known || typeof known !== "object" || Array.isArray(known)) known = {};
  const sessions = new Map();
  let active = null,
    editorMode = true,
    hostFilter = "all",
    reconnectTarget = null,
    keyText = "",
    keyName = "",
    editorVersion = 0,
    secretLoading = false,
    secretSaving = false,
    restoredCredentials = false,
    fontSize = Number(localStorage.getItem("ssh.font-size")) || 13;
  fontSize = Math.max(10, Math.min(24, fontSize));
  let worker = null,
    engine = null,
    resolveEngine,
    rejectEngine,
    engineTimer,
    trustQueue = Promise.resolve();
  const encoder = new TextEncoder();
  const filesWB = window.createFileWorkbench({
    getActiveSession: () => sessions.get(active) || null,
    getWorker: () => worker,
    ensureEngine: () => ensureEngine(),
    getLang: () => lang,
    fitActive: () => fitActive(),
    sendTerminalCommand: (text) => sendInput(sessions.get(active), text),
  });
  function setFormProtocol(proto) {
    const isDav = proto === "webdav";
    $("protocol").value = isDav ? "webdav" : "ssh";
    $("protoSSH").classList.toggle("active", !isDav);
    $("protoDAV").classList.toggle("active", isDav);
    $("sshFields").hidden = isDav;
    $("davFields").hidden = !isDav;
    $("authSegments").hidden = isDav;
    $("testDav").hidden = !isDav;
    $("host").required = !isDav;
    $("port").required = !isDav;
    $("username").required = !isDav;
    $("davUrl").required = isDav;
    $("formMark").className = isDav ? "app-mark dav" : "app-mark";
    $("formMark").innerHTML = isDav ? '<i class="fa-solid fa-cloud" aria-hidden="true"></i>' : "›_";
    $("formHint").textContent = t(isDav ? "davConnectHint" : "connectHint");
    if (isDav) {
      document.querySelector('[name=auth][value="password"]').checked = true;
      authFields();
    }
    $("formError").hidden = true;
  }
  $("protoSSH").onclick = () => {
    clearRestoredCredentials();
    setFormProtocol("ssh");
  };
  $("protoDAV").onclick = () => {
    clearRestoredCredentials();
    setFormProtocol("webdav");
  };
  for (const pill of $("protoFilter").querySelectorAll(".proto-pill")) {
    pill.onclick = () => {
      hostFilter = pill.dataset.filter;
      for (const p of $("protoFilter").querySelectorAll(".proto-pill"))
        p.classList.toggle("active", p === pill);
      renderHosts();
    };
  }
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
      ["zenToggle", "专注模式（最大化终端）", "Focus mode (maximize terminal)"],
      ["zenExit", "退出专注模式", "Exit focus mode"],
      ["mobileMore", "更多操作", "More actions"],
      ["disconnect", "断开连接", "Disconnect"],
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
    filesWB.onLanguageChange();
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
    const proto = $("protocol").value === "webdav" ? "webdav" : "ssh";
    if (proto === "webdav") {
      const url = $("davUrl").value.trim();
      let hostname = url;
      try { hostname = new URL(url).hostname; } catch (_) {}
      return {
        id: $("hostID").value || crypto.randomUUID?.() || "dav-" + Date.now(),
        protocol: "webdav",
        name: $("hostName").value.trim(),
        host: hostname,
        url,
        user: $("davUser").value.trim(),
        basePath: $("davBasePath").value.trim(),
        insecureSkipVerify: $("davInsecure").checked,
        auth: "password",
      };
    }
    return {
      id: $("hostID").value || crypto.randomUUID?.() || "host-" + Date.now(),
      protocol: "ssh",
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
    if (cfg.protocol === "webdav") {
      try {
        const u = new URL(cfg.url);
        if (u.protocol !== "http:" && u.protocol !== "https:") throw Error("bad");
      } catch (_) {
        showError(t("invalidDavUrl"));
        return false;
      }
      return true;
    }
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
    const version = editorVersion;
    keyText = "";
    keyName = "";
    const file = $("privateKey").files[0];
    $("keyName").textContent = "";
    if (!file) return;
    if (file.size > 1024 * 1024) {
      showError(t("keyTooLarge"));
      $("privateKey").value = "";
      return;
    }
    const text = await file.text();
    if (version !== editorVersion || $("privateKey").files[0] !== file) return;
    keyText = text;
    keyName = file.name;
    $("keyName").textContent = keyName;
  };
  function openEditor(cfg = null, target = null) {
    if (secretSaving) return;
    const version = ++editorVersion;
    secretLoading = false;
    restoredCredentials = false;
    editorMode = true;
    reconnectTarget = target;
    $("connectionForm").reset();
    keyText = "";
    keyName = "";
    $("rememberCredentials").checked = cfg?.remember === true;
    setSecretBusy(false);
    $("keyName").textContent = "";
    $("password").type = "password";
    $("showPassword").setAttribute("aria-pressed", "false");
    $("hostID").value = cfg?.id || "";
    $("hostName").value = cfg?.name || "";
    const isDav = cfg?.protocol === "webdav";
    setFormProtocol(isDav ? "webdav" : "ssh");
    if (isDav) {
      $("davUrl").value = cfg?.url || "";
      $("davUser").value = cfg?.user || "";
      $("davBasePath").value = cfg?.basePath || "";
      $("davInsecure").checked = cfg?.insecureSkipVerify === true;
    } else {
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
    }
    $("deleteHost").hidden = !hosts.some((h) => h.id === cfg?.id);
    $("formTitle").textContent = t(cfg ? "editConnection" : "newConnection");
    $("formError").hidden = true;
    $("editor").hidden = false;
    $("terminalWorkspace").hidden = true;
    $("terminalActions").hidden = true;
    $("viewModeSwitch").hidden = true;
    $("mobileViewToggle").hidden = true;
    $("app").classList.remove("in-terminal", "zen-mode", "is-webdav", "in-files");
    $("zenExit").hidden = true;
    $("zenToggle").setAttribute("aria-pressed", "false");
    $("moreWrap").classList.remove("open");
    $("mobileMore").setAttribute("aria-expanded", "false");
    mobile(false);
    renderTabs();
    renderHosts();
    $(isDav ? "davUrl" : "host").focus();
    if (cfg?.remember) {
      secretLoading = true;
      setSecretBusy(true);
      Promise.resolve().then(() => secretAPI().get(secretName(cfg.id))).then(raw => {
        if (version !== editorVersion || !raw) return;
        const value = JSON.parse(raw);
        if (value.target !== credentialTarget(cfg)) throw Error("credential_target_changed");
        $("password").value = value.password || "";
        $("passphrase").value = value.passphrase || "";
        keyText = value.key || "";
        keyName = value.keyName || "private-key";
        $("keyName").textContent = keyText ? t("savedKey") + keyName : "";
        restoredCredentials = true;
      }).catch(() => {if (version === editorVersion) showError(t("secretFailed"));})
        .finally(() => {if (version === editorVersion) {secretLoading = false;setSecretBusy(false);}});
    }
  }
  function secretAPI() {
    if (!window.BookStark?.secrets) throw Error("secret_bridge_missing");
    return window.BookStark.secrets;
  }
  function secretName(id) { return "ssh-" + id; }
  function credentialTarget(cfg) {
    if (cfg.protocol === "webdav")
      return JSON.stringify(["webdav", cfg.url, cfg.user || ""]);
    return JSON.stringify([cfg.host, cfg.port, cfg.user, cfg.auth]);
  }
  function setSecretBusy(busy) {
    for (const id of ["saveHost", "connect", "deleteHost", "testDav", "rememberCredentials", "password", "privateKey", "passphrase", ...(secretSaving ? ["host", "port", "username", "hostName", "shell", "customShell", "davUrl", "davUser", "davBasePath", "davInsecure"] : [])])
      $(id).disabled = busy;
    document.querySelectorAll("[name=auth]").forEach(input => input.disabled = busy && secretSaving);
    if (!busy) for (const id of ["host", "port", "username", "hostName", "shell", "customShell", "davUrl", "davUser", "davBasePath", "davInsecure"]) $(id).disabled = false;
  }
  function clearRestoredCredentials() {
    ++editorVersion;
    secretLoading = false;
    if (!secretSaving) setSecretBusy(false);
    if (!restoredCredentials) return;
    restoredCredentials = false;
    $("password").value = $("passphrase").value = $("privateKey").value = "";
    keyText = keyName = "";
    $("keyName").textContent = "";
  }
  for (const id of ["host", "port", "username", "davUrl", "davUser"])
    $(id).addEventListener("input", clearRestoredCredentials);
  document.querySelectorAll("[name=auth]").forEach(input => input.addEventListener("change", clearRestoredCredentials));
  async function saveCredentials(cfg) {
    const remember = $("rememberCredentials").checked;
    if (remember && cfg.auth === "key" && !keyText) throw Error("missing_key");
    const previous = hosts.find(h => h.id === cfg.id);
    if (remember) {
      await secretAPI().set(secretName(cfg.id), JSON.stringify({
        target: credentialTarget(cfg), password: cfg.auth === "password" ? $("password").value : "",
        key: cfg.auth === "key" ? keyText : "", passphrase: cfg.auth === "key" ? $("passphrase").value : "", keyName
      }));
    } else if (previous?.remember) await secretAPI().remove(secretName(cfg.id));
    cfg.remember = remember;
  }
  for (const id of ["addHost", "railAdd", "newConnection"])
    $(id).onclick = () => openEditor();
  function saveHost(cfg) {
    cfg = cfg.protocol === "webdav"
      ? {
          id: cfg.id,
          protocol: "webdav",
          name: cfg.name || cfg.host || cfg.url,
          host: cfg.host || cfg.url,
          url: cfg.url,
          user: cfg.user || "",
          basePath: cfg.basePath || "",
          insecureSkipVerify: cfg.insecureSkipVerify === true,
          auth: "password",
          remember: cfg.remember === true,
        }
      : {
          id: cfg.id,
          protocol: "ssh",
          name: cfg.name || cfg.host,
          host: cfg.host,
          port: cfg.port,
          user: cfg.user,
          auth: cfg.auth,
          shell: cfg.shell,
          remember: cfg.remember === true,
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
  $("saveHost").onclick = async () => {
    if (secretLoading || secretSaving) return;
    const cfg = hostConfig();
    if (!validConfig(cfg)) return;
    secretSaving = true;
    setSecretBusy(true);
    try {
      await saveCredentials(cfg);
      if (saveHost(cfg)) BSDialog.toast(t("saved"), "success");
    } catch (_) { showError(t("secretFailed")); }
    finally {secretSaving = false;setSecretBusy(false);}
  };
  $("deleteHost").onclick = async () => {
    if (secretLoading || secretSaving) return;
    const id = $("hostID").value, version = editorVersion;
    if (!(await BSDialog.confirm2(t("confirmDelete"))) || version !== editorVersion) return;
    secretSaving = true;
    setSecretBusy(true);
    try {
      if (hosts.find(h => h.id === id)?.remember) await secretAPI().remove(secretName(id));
      const list = hosts.filter(h => h.id !== id);
      if (persist("ssh.hosts", list)) {hosts = list;secretSaving = false;openEditor();}
    } catch (_) {showError(t("secretFailed"));}
    finally {secretSaving = false;setSecretBusy(false);}
  };
  $("rememberCredentials").onchange = async () => {
    const cfg = hosts.find(h => h.id === $("hostID").value);
    if ($("rememberCredentials").checked || !cfg?.remember) return;
    secretSaving = true;
    setSecretBusy(true);
    try {
      await secretAPI().remove(secretName(cfg.id));
      saveHost({...cfg, remember:false});
    } catch (_) {$("rememberCredentials").checked = true;showError(t("secretFailed"));}
    finally {secretSaving = false;setSecretBusy(false);}
  };
  $("testDav").onclick = async () => {
    const cfg = hostConfig();
    if (!validConfig(cfg)) return;
    if (!window.BookStark?.sockets?.connect) {
      showError(t("bridgeMissing"));
      return;
    }
    $("formError").hidden = true;
    $("testDav").disabled = true;
    try {
      const res = await filesWB.testWebDAV({
        url: cfg.url,
        user: cfg.user,
        password: $("password").value,
        basePath: cfg.basePath,
        insecureSkipVerify: cfg.insecureSkipVerify,
      });
      if (res.ok) {
        BSDialog.toast(
          (lang === "zh" ? "WebDAV 连接正常 (" : "WebDAV OK (") + res.ms + "ms · " + res.count + (lang === "zh" ? " 项)" : " items)"),
          "success",
        );
      } else {
        showError(res.error || t("connectFailed"));
      }
    } catch (err) {
      showError(err.message || t("connectFailed"));
    } finally {
      $("testDav").disabled = false;
    }
  };
  function renderHosts() {
    const q = $("hostSearch").value.trim().toLowerCase();
    $("hostList").replaceChildren();
    const items = hosts.filter((h) => {
      const proto = h.protocol === "webdav" ? "webdav" : "ssh";
      if (hostFilter !== "all" && proto !== hostFilter) return false;
      return [h.name, h.host, h.url, h.user].join(" ").toLowerCase().includes(q);
    });
    for (const cfg of items) {
      const isDav = cfg.protocol === "webdav";
      const b = document.createElement("button");
      b.type = "button";
      b.className =
        "host-row" +
        (editorMode && $("hostID").value === cfg.id ? " selected" : "");
      const sub = isDav
        ? e(cfg.url || cfg.host)
        : e(cfg.user) + "@" + e(cfg.host) + ":" + e(cfg.port);
      b.innerHTML =
        '<span class="host-glyph' + (isDav ? " dav" : "") + '" aria-hidden="true">' +
        (isDav ? '<i class="fa-solid fa-cloud"></i>' : "›_") +
        '</span><span class="host-text"><strong>' +
        e(cfg.name || cfg.host) +
        '<span class="proto-badge' + (isDav ? " dav" : "") + '">' + (isDav ? "DAV" : "SSH") + "</span>" +
        "</strong><small>" + sub + "</small></span>";
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
      const isDav = s.cfg.protocol === "webdav";
      const el = document.createElement("div");
      el.className = "tab" + (!editorMode && active === s.id ? " active" : "");
      el.title = isDav
        ? s.cfg.url
        : s.cfg.user + "@" + s.cfg.host + ":" + s.cfg.port;
      const dotClass =
        s.state === "connected" ? (isDav ? "dav-online" : "online") : "";
      el.innerHTML =
        '<span class="dot ' +
        dotClass +
        '" aria-hidden="true"></span><button type="button" role="tab" aria-selected="' +
        (!editorMode && active === s.id) +
        '">' +
        e(s.cfg.name || s.cfg.host) +
        '</button><span class="tab-proto' +
        (isDav ? " dav" : "") +
        '">' +
        (isDav ? "DAV" : "SSH") +
        '</span><button type="button" class="close-tab" aria-label="' +
        e(t("close")) +
        '">×</button>';
      el.querySelector("[role=tab]").onclick = () => activate(s.id);
      el.querySelector(".close-tab").onclick = () => closeSession(s);
      container.appendChild(el);
      if (!editorMode && active === s.id) {
        el.scrollIntoView({ block: "nearest", inline: "nearest" });
      }
    }
  }
  function activate(id) {
    if (!sessions.has(id)) return;
    active = id;
    editorMode = false;
    reconnectTarget = null;
    $("editor").hidden = true;
    $("terminalWorkspace").hidden = false;
    $("terminalActions").hidden = false;
    $("app").classList.add("in-terminal");
    for (const s of sessions.values()) {
      if (s.el) s.el.hidden = s.id !== id;
    }
    mobile(false);
    renderTabs();
    const cur = sessions.get(id);
    filesWB.applyViewMode(cur);
    updateSession();
    requestAnimationFrame(() => {
      fitActive();
      if (cur?.cfg.protocol !== "webdav" && cur?.viewMode !== "files") {
        cur?.term?.focus();
      }
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
    const isDav = s.cfg.protocol === "webdav";
    $("sessionHost").textContent = isDav
      ? s.cfg.url + (s.cfg.user ? " · " + s.cfg.user : "")
      : s.cfg.user +
        "@" +
        s.cfg.host +
        ":" +
        s.cfg.port +
        " · " +
        (s.cfg.shell || t("defaultShell"));
    $("sessionStatus").textContent = t(s.state);
    $("statusDot").classList.toggle("online", !isDav && s.state === "connected");
    $("statusDot").classList.toggle("dav-online", isDav && s.state === "connected");
    const badge = $("statusProtoBadge");
    if (isDav) {
      badge.hidden = false;
      badge.className = "status-badge dav";
      badge.textContent = lang === "zh" ? "WASM Socket · 无 CORS" : "WASM Socket · No CORS";
      $("dimensions").textContent = (s.fs?.entries?.length || 0) + (lang === "zh" ? " 项" : " items");
      $("statusMeta").textContent = "WebDAV · UTF-8";
    } else {
      badge.hidden = s.viewMode === "terminal";
      badge.className = "status-badge";
      badge.textContent = lang === "zh" ? "SFTP 通道已复用" : "SFTP Multiplexed";
      $("dimensions").textContent = s.term ? s.term.cols + " × " + s.term.rows : "";
      $("statusMeta").textContent = s.viewMode === "terminal" ? "SSH · UTF-8" : "SSH + SFTP · UTF-8";
    }
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
    filesWB.onSessionClosed(s);
    s.term?.dispose();
    s.el?.remove();
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
    if (worker) {
      worker.postMessage({
        type: s.cfg.protocol === "webdav" ? "dav-close" : "close",
        id: s.run,
      });
    }
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
    if (filesWB.handleWorkerMessage(m)) return;
    const s = [...sessions.values()].find((item) => item.run === m.id);
    if (!s) return;
    switch (m.type) {
      case "dav-connected":
        s.state = "connected";
        s.reason = "";
        s.fs.cwd = m.cwd || "/";
        s.fs.entries = JSON.parse(m.entries || "[]");
        s.fs.loaded = true;
        s.fs.loading = false;
        s.fs.error = "";
        renderTabs();
        if (active === s.id) {
          filesWB.applyViewMode(s);
          filesWB.renderSessionFiles(s);
          updateSession();
        }
        break;
      case "dav-error":
        s.fs.loading = false;
        s.fs.error = m.reason || t("connectFailed");
        finish(s, m.reason);
        if (active === s.id) filesWB.renderSessionFiles(s);
        break;
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
        filesWB.onTerminalOutput(s, m.data);
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
    const isDav = cfg.protocol === "webdav";
    const id = (isDav ? "dav-" : "ssh-") + Date.now() + "-" + Math.random().toString(36).slice(2);
    if (isDav) {
      const s = {
        id,
        run: id + "-run-1",
        cfg,
        term: null,
        fit: null,
        el: null,
        viewMode: "files",
        fs: { cwd: "/", entries: [], loaded: false, loading: true, error: "" },
        state: "connecting",
        reason: "",
        socket: null,
        readAck: null,
        inputAck: null,
        inputChain: Promise.resolve(),
      };
      sessions.set(id, s);
      return s;
    }
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
      viewMode: "terminal",
      fs: { cwd: "", entries: [], loaded: false, loading: false, error: "", cwdTimer: null },
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
      if (active === id && current?.cfg.protocol !== "webdav")
        $("dimensions").textContent = cols + " × " + rows;
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
    if (secretLoading || secretSaving) return;
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
    if ($("rememberCredentials").checked || hosts.find(h => h.id === cfg.id)?.remember) {
      secretSaving = true;
      setSecretBusy(true);
      try {await saveCredentials(cfg);if (!saveHost(cfg)) return;}
      catch (_) {showError(t("secretFailed"));return;}
      finally {secretSaving = false;setSecretBusy(false);}
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
        fs: { cwd: cfg.protocol === "webdav" ? "/" : "", entries: [], loaded: false, loading: cfg.protocol === "webdav", error: "", cwdTimer: null },
        state: "connecting",
        reason: "",
        socket: null,
        readAck: null,
        inputAck: null,
        inputChain: Promise.resolve(),
        trustDialog: null,
      };
      sessions.set(s.id, s);
      s.term?.writeln("\r\n\x1b[90m— " + t("reconnect") + " —\x1b[0m");
    }
    activate(s.id);
    $("connect").disabled = false;
    const current = () => sessions.get(s.id) === s && s.state !== "closed";
    try {
      await ensureEngine();
      if (!current()) return;
      if (cfg.protocol === "webdav") {
        worker.postMessage({
          type: "dav-connect",
          id: s.run,
          url: cfg.url,
          user: cfg.user,
          password: credentials.password,
          basePath: cfg.basePath,
          insecureSkipVerify: cfg.insecureSkipVerify,
        });
        credentials.password = "";
        return;
      }
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
    if (s && !editorMode && s.term && s.viewMode !== "files") {
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
    for (const s of sessions.values()) {
      if (s.term) s.term.options.fontSize = fontSize;
    }
    fitActive();
  }
  $("smallerFont").onclick = () => setFont(-1);
  $("largerFont").onclick = () => setFont(1);
  function setZen(on) {
    const enabled = Boolean(on) && !editorMode;
    $("app").classList.toggle("zen-mode", enabled);
    $("zenExit").hidden = !enabled;
    $("zenToggle").setAttribute("aria-pressed", String(enabled));
    $("moreWrap").classList.remove("open");
    $("mobileMore").setAttribute("aria-expanded", "false");
    requestAnimationFrame(() => {
      fitActive();
      const s = sessions.get(active);
      if (s?.term && s.viewMode !== "files") s.term.focus();
    });
  }
  $("zenToggle").onclick = () =>
    setZen(!$("app").classList.contains("zen-mode"));
  $("zenExit").onclick = () => setZen(false);
  $("mobileMore").onclick = (event) => {
    event.stopPropagation();
    const open = !$("moreWrap").classList.contains("open");
    $("moreWrap").classList.toggle("open", open);
    $("mobileMore").setAttribute("aria-expanded", String(open));
  };
  document.addEventListener("click", (event) => {
    if (!event.target.closest("#moreWrap")) {
      $("moreWrap").classList.remove("open");
      $("mobileMore").setAttribute("aria-expanded", "false");
    }
  });
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
    "ctrl-c": "\x03",
    "ctrl-l": "\x0c",
    slash: "/",
    dash: "-",
    pipe: "|",
    tilde: "~",
  };
  for (const b of $("extraKeys").querySelectorAll("button")) {
    b.onpointerdown = (event) => event.preventDefault();
    b.onclick = () => {
      const action = b.dataset.action;
      if (action === "copy") {
        $("copyTerminal").click();
        return;
      }
      if (action === "paste") {
        $("pasteTerminal").click();
        return;
      }
      const key = b.dataset.key;
      if (key === "ctrl" || key === "alt") {
        if (key === "ctrl") ctrl = !ctrl;
        else alt = !alt;
        b.setAttribute("aria-pressed", String(key === "ctrl" ? ctrl : alt));
        sessions.get(active)?.term?.focus();
      } else if (keys[key]) {
        sendInput(sessions.get(active), keys[key]);
        sessions.get(active)?.term?.focus();
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
