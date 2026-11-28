/* Unified SFTP & WebDAV File Workbench, Remote Editor, Transfer Queue, and Dial Bridge */
(function () {
  "use strict";
  const $ = (id) => document.getElementById(id);
  const e = window.escHtml || ((s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c])));

  const TEXT_EXTS = new Set([
    "txt", "md", "markdown", "conf", "cfg", "ini", "env", "yml", "yaml", "json", "jsonc", "toml",
    "xml", "html", "htm", "css", "scss", "less", "js", "mjs", "cjs", "ts", "tsx", "jsx",
    "go", "rs", "py", "rb", "php", "java", "kt", "c", "h", "cpp", "hpp", "cs", "swift",
    "sh", "bash", "zsh", "fish", "ps1", "bat", "sql", "csv", "tsv", "log", "gitignore",
    "dockerignore", "editorconfig", "properties", "service", "socket", "timer", "inc", "vue", "svelte"
  ]);
  const TEXT_NAMES = new Set([
    "dockerfile", "caddyfile", "makefile", "procfile", "gemfile", "rakefile",
    "vagrantfile", "jenkinsfile", "hosts", "fstab", "crontab", "passwd", "group",
    "readme", "license", "changelog", ".bashrc", ".zshrc", ".profile", ".env", ".gitignore", "nginx.conf"
  ]);
  const IMG_EXTS = new Set(["png", "jpg", "jpeg", "gif", "webp", "svg", "bmp", "ico"]);

  function extOf(name) {
    const lower = String(name || "").toLowerCase();
    const idx = lower.lastIndexOf(".");
    return idx > 0 ? lower.slice(idx + 1) : "";
  }
  function isTextFile(name, mime) {
    const lower = String(name || "").toLowerCase();
    if (TEXT_NAMES.has(lower) || lower.startsWith(".env")) return true;
    const ext = extOf(lower);
    if (TEXT_EXTS.has(ext)) return true;
    if (mime && /^(text\/|application\/(json|xml|javascript|x-yaml|x-sh|toml))/.test(mime)) return true;
    return false;
  }
  function isImageFile(name, mime) {
    return IMG_EXTS.has(extOf(name)) || Boolean(mime && mime.startsWith("image/"));
  }
  function isPdfFile(name, mime) {
    return extOf(name) === "pdf" || mime === "application/pdf";
  }
  function iconFor(entry) {
    if (entry.isDir) return "fa-folder ic-dir";
    const ext = extOf(entry.name);
    if (["conf", "yml", "yaml", "toml", "ini", "env", "json"].includes(ext) || entry.name.toLowerCase().startsWith(".env"))
      return "fa-file-code ic-conf";
    if (["js", "ts", "go", "py", "sh", "rs", "c", "cpp", "java", "html", "css"].includes(ext))
      return "fa-file-code ic-code";
    if (["zip", "tar", "gz", "tgz", "bz2", "xz", "7z", "rar"].includes(ext))
      return "fa-file-zipper ic-zip";
    if (IMG_EXTS.has(ext)) return "fa-file-image ic-img";
    if (ext === "pdf") return "fa-file-pdf ic-pdf";
    return "fa-file-lines ic-log";
  }
  function fmtSize(bytes) {
    if (bytes == null || bytes < 0) return "—";
    if (bytes < 1024) return bytes + " B";
    if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + " KB";
    if (bytes < 1024 * 1024 * 1024) return (bytes / (1024 * 1024)).toFixed(1) + " MB";
    return (bytes / (1024 * 1024 * 1024)).toFixed(2) + " GB";
  }
  function fmtTime(sec) {
    if (!sec) return "—";
    const d = new Date(sec * 1000);
    const pad = (n) => String(n).padStart(2, "0");
    const now = new Date();
    if (d.getFullYear() === now.getFullYear() && d.getMonth() === now.getMonth() && d.getDate() === now.getDate()) {
      return pad(d.getHours()) + ":" + pad(d.getMinutes());
    }
    return pad(d.getMonth() + 1) + "-" + pad(d.getDate()) + " " + pad(d.getHours()) + ":" + pad(d.getMinutes());
  }
  function parentPath(p) {
    if (!p || p === "/") return "/";
    const clean = p.replace(/\/+$/, "");
    const idx = clean.lastIndexOf("/");
    return idx <= 0 ? "/" : clean.slice(0, idx);
  }
  function joinPath(dir, name) {
    const clean = (dir || "/").replace(/\/+$/, "");
    return (clean === "" ? "" : clean) + "/" + name.replace(/^\/+/, "");
  }
  function shellQuote(s) {
    return "'" + String(s).replace(/'/g, "'\\''") + "'";
  }

  // Create controller bound to app.js callbacks
  window.createFileWorkbench = function createFileWorkbench(host) {
    let seq = 1;
    const pendingRPC = new Map();
    const dialSockets = new Map();
    const transfers = [];
    let currentBlobUrl = null;
    let editorFile = null; // { sessionId, path, name, originalText, dirty, isNew }
    let selectedPaths = new Set();
    let showHidden = false;
    let followCwd = true;
    let splitOrient = localStorage.getItem("ssh.split-orient") || "horizontal";
    let splitRatio = Number(localStorage.getItem("ssh.split-ratio")) || 0.52;
    splitRatio = Math.max(0.25, Math.min(0.75, splitRatio));

    function activeSession() {
      return host.getActiveSession();
    }
    function isZh() {
      return host.getLang() === "zh";
    }
    function L(zh, en) {
      return isZh() ? zh : en;
    }

    // ---------------- Dial Bridge for WebDAV TCP Sockets ----------------
    async function handleDialSocket(m) {
      const { dialId, host: h, port } = m;
      const w = host.getWorker();
      if (!window.BookStark?.sockets?.connect) {
        w?.postMessage({ type: "dial-open", dialId, ok: false, error: L("缺少 TCP 桥接权限", "TCP socket bridge missing") });
        return;
      }
      try {
        const sock = await BookStark.sockets.connect({ host: h, port });
        const entry = { sock, readAck: null, closed: false };
        dialSockets.set(dialId, entry);
        w?.postMessage({ type: "dial-open", dialId, ok: true });
        sock.closed.then(() => {
          entry.closed = true;
          entry.readAck?.();
          dialSockets.delete(dialId);
          host.getWorker()?.postMessage({ type: "dial-close", dialId });
        });
        const reader = sock.readable.getReader();
        (async () => {
          try {
            while (!entry.closed) {
              const { value, done } = await reader.read();
              if (done || entry.closed) break;
              await new Promise((resolve) => {
                entry.readAck = resolve;
                host.getWorker()?.postMessage({ type: "dial-data", dialId, data: value });
              });
            }
          } catch (_) {
            if (!entry.closed) {
              entry.closed = true;
              host.getWorker()?.postMessage({ type: "dial-close", dialId });
            }
          } finally {
            reader.releaseLock();
          }
        })();
      } catch (err) {
        host.getWorker()?.postMessage({
          type: "dial-open",
          dialId,
          ok: false,
          error: err?.message || L("无法建立 TCP 连接", "TCP connection failed"),
        });
      }
    }

    function handleWorkerMessage(m) {
      switch (m.type) {
        case "dial-socket":
          handleDialSocket(m);
          return true;
        case "dial-write": {
          const entry = dialSockets.get(m.dialId);
          if (!entry || entry.closed) {
            host.getWorker()?.postMessage({ type: "dial-write-ack", dialId: m.dialId, ok: false });
            return true;
          }
          Promise.resolve()
            .then(() => entry.sock.send(m.data))
            .then(() => host.getWorker()?.postMessage({ type: "dial-write-ack", dialId: m.dialId, ok: true }))
            .catch(() => host.getWorker()?.postMessage({ type: "dial-write-ack", dialId: m.dialId, ok: false }));
          return true;
        }
        case "dial-read-ack": {
          const entry = dialSockets.get(m.dialId);
          if (entry?.readAck) {
            const fn = entry.readAck;
            entry.readAck = null;
            fn();
          }
          return true;
        }
        case "dial-close": {
          const entry = dialSockets.get(m.dialId);
          if (entry) {
            entry.closed = true;
            entry.readAck?.();
            entry.sock.close();
            dialSockets.delete(m.dialId);
          }
          return true;
        }
        case "fs-progress": {
          const p = pendingRPC.get(m.reqId);
          if (p?.onProgress) p.onProgress(m.done, m.total);
          return true;
        }
        case "fs-res": {
          const p = pendingRPC.get(m.reqId);
          if (p) {
            pendingRPC.delete(m.reqId);
            if (m.ok) p.resolve(m);
            else p.reject(new Error(m.error || "FS error"));
          }
          return true;
        }
        case "dav-test-res": {
          const p = pendingRPC.get(m.reqId);
          if (p) {
            pendingRPC.delete(m.reqId);
            p.resolve(m);
          }
          return true;
        }
      }
      return false;
    }

    function rpc(sessionRunId, op, params = {}, onProgress = null) {
      return new Promise((resolve, reject) => {
        const w = host.getWorker();
        if (!w) return reject(new Error(L("引擎未就绪", "Engine not ready")));
        const reqId = "fs-" + seq++;
        pendingRPC.set(reqId, { resolve, reject, onProgress });
        w.postMessage({ type: "fs-req", id: sessionRunId, reqId, op, ...params });
      });
    }

    async function testWebDAV(cfg) {
      await host.ensureEngine();
      return new Promise((resolve, reject) => {
        const reqId = "davtest-" + seq++;
        pendingRPC.set(reqId, { resolve, reject });
        host.getWorker().postMessage({ type: "dav-test", reqId, ...cfg });
        setTimeout(() => {
          if (pendingRPC.has(reqId)) {
            pendingRPC.delete(reqId);
            reject(new Error(L("测试连接超时", "Connection test timed out")));
          }
        }, 25000);
      });
    }

    // ---------------- Transfer Queue ----------------
    function addTransfer(kind, name, total) {
      const item = {
        id: "tr-" + seq++,
        kind, // "upload" | "download"
        name,
        done: 0,
        total: total || 0,
        status: "active", // "active" | "done" | "error"
        error: "",
        startedAt: Date.now(),
      };
      transfers.unshift(item);
      if (transfers.length > 20) transfers.pop();
      $("transferToggle").hidden = false;
      $("transferCard").hidden = false;
      renderTransfers();
      return item;
    }

    function renderTransfers() {
      const activeCount = transfers.filter((x) => x.status === "active").length;
      $("transferTitle").textContent =
        L("传输队列", "Transfers") + " (" + transfers.length + (activeCount ? " · " + activeCount + L(" 进行中", " active") : "") + ")";
      const list = $("transferList");
      list.replaceChildren();
      if (!transfers.length) {
        $("transferCard").hidden = true;
        return;
      }
      for (const tr of transfers) {
        const pct = tr.status === "done" ? 100 : tr.total > 0 ? Math.min(99, Math.round((tr.done / tr.total) * 100)) : 25;
        const row = document.createElement("div");
        row.className = "transfer-item";
        const ic = tr.status === "done"
          ? '<i class="fa-solid fa-check tr-ok"></i>'
          : tr.status === "error"
            ? '<i class="fa-solid fa-triangle-exclamation tr-err"></i>'
            : tr.kind === "upload"
              ? '<i class="fa-solid fa-arrow-up tr-up"></i>'
              : '<i class="fa-solid fa-arrow-down tr-dn"></i>';
        const meta = tr.status === "done"
          ? L("已完成", "Done") + " · " + fmtSize(tr.total || tr.done)
          : tr.status === "error"
            ? tr.error || L("失败", "Failed")
            : pct + "% · " + fmtSize(tr.done) + (tr.total ? " / " + fmtSize(tr.total) : "");
        row.innerHTML =
          '<div class="transfer-row"><span class="transfer-name">' + ic + " " + e(tr.name) +
          '</span><span class="transfer-meta ' + (tr.status === "done" ? "done" : tr.status === "error" ? "err" : "") + '">' + e(meta) +
          '</span></div><div class="prog-track"><div class="prog-fill ' + (tr.status === "done" ? "done" : tr.status === "error" ? "err" : "") +
          '" style="width:' + pct + '%"></div></div>';
        list.appendChild(row);
      }
    }

    $("transferToggle").onclick = () => {
      $("transferCard").hidden = !$("transferCard").hidden;
    };
    $("transferClose").onclick = () => {
      $("transferCard").hidden = true;
    };
    $("transferClear").onclick = () => {
      for (let i = transfers.length - 1; i >= 0; i--) {
        if (transfers[i].status !== "active") transfers.splice(i, 1);
      }
      renderTransfers();
    };

    // ---------------- View Mode & Split Layout ----------------
    function applyViewMode(s) {
      const split = $("workspaceSplit");
      const modeSwitch = $("viewModeSwitch");
      const mobGroup = $("mobileModeGroup");
      const mobToggle = $("mobileViewToggle");
      const mobDocker = $("mobileDockerToggle");
      if (!s) {
        modeSwitch.hidden = true;
        if (mobGroup) mobGroup.hidden = true;
        return;
      }
      const isDav = s.cfg.protocol === "webdav";
      let mode = isDav ? "files" : (s.viewMode || "terminal");
      if (!isDav && mode === "split" && matchMedia("(max-width:640px)").matches) {
        mode = "terminal";
      }
      split.dataset.view = mode;
      split.dataset.orient = splitOrient;

      // Header controls visibility
      modeSwitch.hidden = isDav;
      if (mobGroup) mobGroup.hidden = isDav;
      $("app").classList.toggle("is-webdav", isDav);
      $("app").classList.toggle("in-files", mode === "files");
      $("app").classList.toggle("in-docker", mode === "docker");

      if (!isDav) {
        for (const btn of modeSwitch.querySelectorAll(".mode-btn")) {
          btn.classList.toggle("active", btn.dataset.mode === mode);
        }
        const mobIcon = mobToggle.querySelector("i");
        if (mode === "files") {
          mobIcon.className = "fa-solid fa-terminal";
          $("mobileViewLabel").textContent = L("终端", "Term");
          mobToggle.classList.add("is-active");
        } else {
          mobIcon.className = "fa-solid fa-folder-open";
          $("mobileViewLabel").textContent = L("文件", "Files");
          mobToggle.classList.remove("is-active");
        }
        if (mobDocker) {
          mobDocker.classList.toggle("is-active", mode === "docker");
        }
      }

      const showTerm = !isDav && (mode === "terminal" || mode === "split");
      const showFiles = isDav || mode === "files" || mode === "split";
      const showDocker = !isDav && mode === "docker";
      const showHandle = !isDav && mode === "split";
      $("terminalStack").hidden = !showTerm;
      $("splitHandle").hidden = !showHandle;
      $("fileWorkbench").hidden = !showFiles;
      if ($("dockerWorkbench")) $("dockerWorkbench").hidden = !showDocker;
      $("fsSplitOrient").hidden = !showHandle;
      $("fsFollowCwd").hidden = isDav;
      $("fsColMode").hidden = isDav;
      $("extraKeys").classList.toggle("files-hidden", !showTerm);

      if (showHandle) {
        applySplitSize();
      } else {
        $("terminalStack").style.flex = "";
        $("fileWorkbench").style.flex = "";
      }

      if (showFiles) {
        renderSessionFiles(s);
        if (s.state === "connected" && !s.fs.loaded && !s.fs.loading) {
          loadDir(s, s.fs.cwd || (isDav ? "/" : ""));
        }
      }
      if (showDocker) {
        host.onDockerShow?.(s);
      } else {
        host.onDockerHide?.(s);
      }
      if (showTerm) {
        requestAnimationFrame(() => host.fitActive());
      }
      host.onViewModeApplied?.(s);
    }

    function applySplitSize() {
      const term = $("terminalStack");
      const fw = $("fileWorkbench");
      term.style.flex = `${splitRatio} 1 0%`;
      fw.style.flex = `${1 - splitRatio} 1 0%`;
    }

    function setViewMode(mode) {
      const s = activeSession();
      if (!s || s.cfg.protocol === "webdav") return;
      s.viewMode = mode;
      applyViewMode(s);
    }

    for (const btn of $("viewModeSwitch").querySelectorAll(".mode-btn")) {
      btn.onclick = () => setViewMode(btn.dataset.mode);
    }
    $("mobileViewToggle").onclick = () => {
      const s = activeSession();
      if (!s || s.cfg.protocol === "webdav") return;
      setViewMode(s.viewMode === "files" ? "terminal" : "files");
    };
    if ($("mobileDockerToggle")) {
      $("mobileDockerToggle").onclick = () => {
        const s = activeSession();
        if (!s || s.cfg.protocol === "webdav") return;
        setViewMode(s.viewMode === "docker" ? "terminal" : "docker");
      };
    }
    matchMedia("(max-width:640px)").addEventListener("change", () => {
      const s = activeSession();
      if (s) applyViewMode(s);
    });
    $("fsSplitOrient").onclick = () => {
      splitOrient = splitOrient === "horizontal" ? "vertical" : "horizontal";
      localStorage.setItem("ssh.split-orient", splitOrient);
      $("workspaceSplit").dataset.orient = splitOrient;
      $("fsSplitOrient").querySelector("i").className =
        splitOrient === "horizontal" ? "fa-solid fa-arrows-up-down" : "fa-solid fa-arrows-left-right";
      requestAnimationFrame(() => host.fitActive());
    };

    // Draggable splitter
    (function setupSplitter() {
      const handle = $("splitHandle");
      let dragging = false;
      handle.onpointerdown = (ev) => {
        dragging = true;
        handle.setPointerCapture(ev.pointerId);
        document.body.style.userSelect = "none";
      };
      handle.onpointermove = (ev) => {
        if (!dragging) return;
        const rect = $("workspaceSplit").getBoundingClientRect();
        const ratio = splitOrient === "horizontal"
          ? (ev.clientX - rect.left) / rect.width
          : (ev.clientY - rect.top) / rect.height;
        splitRatio = Math.max(0.22, Math.min(0.78, ratio));
        applySplitSize();
      };
      const end = () => {
        if (!dragging) return;
        dragging = false;
        document.body.style.userSelect = "";
        localStorage.setItem("ssh.split-ratio", String(splitRatio));
        host.fitActive();
      };
      handle.onpointerup = end;
      handle.onpointercancel = end;
    })();

    // ---------------- Directory Listing & Rendering ----------------
    async function loadDir(s, dirPath) {
      if (!s || s.state !== "connected") return;
      s.fs.loading = true;
      s.fs.error = "";
      selectedPaths.clear();
      if (activeSession() === s) renderSessionFiles(s);
      try {
        const res = await rpc(s.run, "list", { path: dirPath || "" });
        if (s.state === "closed") return;
        s.fs.cwd = res.cwd || "/";
        s.fs.entries = JSON.parse(res.entries || "[]");
        s.fs.loaded = true;
        s.fs.error = "";
      } catch (err) {
        s.fs.error = err.message || L("读取目录失败", "Failed to list directory");
      } finally {
        s.fs.loading = false;
        if (activeSession() === s) renderSessionFiles(s);
      }
    }

    function renderBreadcrumbs(s) {
      const crumb = $("fsBreadcrumb");
      crumb.replaceChildren();
      const isDav = s.cfg.protocol === "webdav";
      const rootIcon = document.createElement("i");
      rootIcon.className = isDav ? "fa-solid fa-cloud crumb-ic dav" : "fa-solid fa-hard-drive crumb-ic";
      crumb.appendChild(rootIcon);

      const cwd = s.fs.cwd || "/";
      const parts = cwd.split("/").filter(Boolean);
      const rootBtn = document.createElement("button");
      rootBtn.type = "button";
      rootBtn.className = "crumb-seg" + (parts.length === 0 ? " cur" : "");
      rootBtn.textContent = "/";
      rootBtn.onclick = (ev) => { ev.stopPropagation(); loadDir(s, "/"); };
      crumb.appendChild(rootBtn);

      let acc = "";
      parts.forEach((seg, idx) => {
        acc += "/" + seg;
        const target = acc;
        if (idx > 0) {
          const sl = document.createElement("span");
          sl.className = "crumb-slash";
          sl.textContent = "/";
          crumb.appendChild(sl);
        }
        const b = document.createElement("button");
        b.type = "button";
        const isLast = idx === parts.length - 1;
        b.className = "crumb-seg" + (isLast ? " cur" : "");
        b.textContent = seg;
        b.onclick = (ev) => {
          ev.stopPropagation();
          if (isLast) openPathInput();
          else loadDir(s, target);
        };
        crumb.appendChild(b);
      });
    }

    function openPathInput() {
      const s = activeSession();
      if (!s) return;
      $("fsBreadcrumb").hidden = true;
      $("fsPathInput").hidden = false;
      $("fsPathInput").value = s.fs.cwd || "/";
      $("fsPathInput").focus();
      $("fsPathInput").select();
    }

    function renderSessionFiles(s) {
      if (!s) return;
      const isDav = s.cfg.protocol === "webdav";
      renderBreadcrumbs(s);
      $("fsLoading").hidden = !s.fs.loading;
      $("fsError").hidden = !s.fs.error;
      $("fsError").textContent = s.fs.error || "";
      $("fsFollowCwd").setAttribute("aria-pressed", String(followCwd));
      $("fsShowHidden").setAttribute("aria-pressed", String(showHidden));

      const q = ($("fsFilter").value || "").trim().toLowerCase();
      const visible = (s.fs.entries || []).filter((item) => {
        if (!showHidden && item.name.startsWith(".")) return false;
        if (q && !item.name.toLowerCase().includes(q)) return false;
        return true;
      });
      $("fsCount").textContent = visible.length + L(" 项", " items");

      const tbody = $("fileTbody");
      tbody.replaceChildren();
      $("fileTable").hidden = s.fs.loading && !s.fs.loaded;
      $("fsEmpty").hidden = s.fs.loading || Boolean(s.fs.error) || visible.length > 0;

      for (const item of visible) {
        const tr = document.createElement("tr");
        if (selectedPaths.has(item.path)) tr.classList.add("selected");
        if (editorFile && editorFile.sessionId === s.id && editorFile.path === item.path) tr.classList.add("editing");

        const tdCheck = document.createElement("td");
        tdCheck.className = "col-check";
        const cb = document.createElement("input");
        cb.type = "checkbox";
        cb.checked = selectedPaths.has(item.path);
        cb.onclick = (ev) => ev.stopPropagation();
        cb.onchange = () => {
          if (cb.checked) selectedPaths.add(item.path);
          else selectedPaths.delete(item.path);
          tr.classList.toggle("selected", cb.checked);
          updateBatchBar();
        };
        tdCheck.appendChild(cb);

        const tdName = document.createElement("td");
        tdName.className = "col-name";
        tdName.innerHTML = '<div class="fname"><i class="fa-solid ' + iconFor(item) + '" aria-hidden="true"></i><span>' + e(item.name + (item.isDir ? "/" : "")) + "</span></div>";
        const mobMore = document.createElement("button");
        mobMore.type = "button";
        mobMore.className = "mobile-row-more";
        mobMore.setAttribute("aria-label", L("更多操作", "Actions"));
        mobMore.innerHTML = '<i class="fa-solid fa-ellipsis-vertical" aria-hidden="true"></i>';
        mobMore.onclick = (ev) => { ev.stopPropagation(); openMobileSheet(s, item); };
        tdName.querySelector(".fname").appendChild(mobMore);

        const tdSize = document.createElement("td");
        tdSize.className = "col-size mono";
        tdSize.textContent = item.isDir ? "—" : fmtSize(item.size);

        const tdMode = document.createElement("td");
        tdMode.className = "col-mode mono";
        tdMode.hidden = isDav;
        if (!isDav) {
          const mBtn = document.createElement("button");
          mBtn.type = "button";
          mBtn.className = "mode-pill";
          mBtn.textContent = item.mode || "—";
          mBtn.title = L("修改权限 (chmod)", "Change permissions");
          mBtn.onclick = (ev) => { ev.stopPropagation(); promptChmod(s, item); };
          tdMode.appendChild(mBtn);
        }

        const tdTime = document.createElement("td");
        tdTime.className = "col-time mono";
        tdTime.textContent = fmtTime(item.modTime);

        const tdAct = document.createElement("td");
        tdAct.className = "col-act";
        const acts = document.createElement("div");
        acts.className = "row-actions";

        if (item.isDir && !isDav) {
          acts.appendChild(makeRowBtn("fa-terminal", L("在终端 cd 到此目录", "cd in terminal"), () => {
            host.sendTerminalCommand("cd " + shellQuote(item.path) + "\r");
            BSDialog.toast(L("已切换到 ", "cd ") + item.path, "success");
          }));
        }
        if (!item.isDir) {
          const canEdit = isTextFile(item.name, item.mime);
          acts.appendChild(makeRowBtn(
            canEdit ? "fa-pen" : "fa-eye",
            canEdit ? L("在线编辑", "Edit") : L("预览", "Preview"),
            () => openFileDrawer(s, item),
            canEdit ? "edit" : ""
          ));
          acts.appendChild(makeRowBtn("fa-download", L("下载", "Download"), () => downloadFile(s, item)));
        }
        acts.appendChild(makeRowBtn("fa-i-cursor", L("重命名", "Rename"), () => promptRename(s, item)));
        acts.appendChild(makeRowBtn("fa-trash", L("删除", "Delete"), () => confirmDelete(s, [item]), "danger"));
        tdAct.appendChild(acts);

        tr.append(tdCheck, tdName, tdSize, tdMode, tdTime, tdAct);
        tr.onclick = () => {
          if (item.isDir) {
            loadDir(s, item.path);
          } else if (matchMedia("(max-width:640px)").matches) {
            openMobileSheet(s, item);
          } else {
            openFileDrawer(s, item);
          }
        };
        tbody.appendChild(tr);
      }
      updateBatchBar();
    }

    function makeRowBtn(fa, title, onclick, extraClass = "") {
      const b = document.createElement("button");
      b.type = "button";
      b.className = "row-act" + (extraClass ? " " + extraClass : "");
      b.title = title;
      b.setAttribute("aria-label", title);
      b.innerHTML = '<i class="fa-solid ' + fa + '" aria-hidden="true"></i>';
      b.onclick = (ev) => { ev.stopPropagation(); onclick(); };
      return b;
    }

    function updateBatchBar() {
      const n = selectedPaths.size;
      $("fsBatchBar").hidden = n === 0;
      $("fsSelectedCount").textContent = L("已选 ", "") + n + L(" 项", " selected");
      $("fsSelectAll").checked = n > 0 && n === $("fileTbody").children.length;
    }

    // ---------------- Path Bar & Toolbar Actions ----------------
    $("fsUp").onclick = () => {
      const s = activeSession();
      if (s) loadDir(s, parentPath(s.fs.cwd));
    };
    $("fsRefresh").onclick = () => {
      const s = activeSession();
      if (s) loadDir(s, s.fs.cwd);
    };
    $("fsPathBox").onclick = openPathInput;
    $("fsPathInput").onblur = () => {
      $("fsPathInput").hidden = true;
      $("fsBreadcrumb").hidden = false;
    };
    $("fsPathInput").onkeydown = (ev) => {
      if (ev.key === "Enter") {
        ev.preventDefault();
        const s = activeSession();
        const val = $("fsPathInput").value.trim() || "/";
        $("fsPathInput").blur();
        if (s) loadDir(s, val);
      } else if (ev.key === "Escape") {
        $("fsPathInput").blur();
      }
    };
    $("fsFilter").oninput = () => {
      const s = activeSession();
      if (s) renderSessionFiles(s);
    };
    $("fsShowHidden").onclick = () => {
      showHidden = !showHidden;
      const s = activeSession();
      if (s) renderSessionFiles(s);
    };
    $("fsFollowCwd").onclick = () => {
      followCwd = !followCwd;
      $("fsFollowCwd").setAttribute("aria-pressed", String(followCwd));
    };
    $("fsSelectAll").onchange = () => {
      const s = activeSession();
      if (!s) return;
      selectedPaths.clear();
      if ($("fsSelectAll").checked) {
        const q = ($("fsFilter").value || "").trim().toLowerCase();
        for (const item of s.fs.entries || []) {
          if (!showHidden && item.name.startsWith(".")) continue;
          if (q && !item.name.toLowerCase().includes(q)) continue;
          selectedPaths.add(item.path);
        }
      }
      renderSessionFiles(s);
    };

    $("fsBatchDownload").onclick = async () => {
      const s = activeSession();
      if (!s) return;
      const targets = (s.fs.entries || []).filter((x) => selectedPaths.has(x.path) && !x.isDir);
      if (!targets.length) {
        BSDialog.toast(L("请选择文件进行下载（暂不支持直接打包目录）", "Select files to download"));
        return;
      }
      for (const item of targets) await downloadFile(s, item);
    };
    $("fsBatchDelete").onclick = () => {
      const s = activeSession();
      if (!s) return;
      const targets = (s.fs.entries || []).filter((x) => selectedPaths.has(x.path));
      if (targets.length) confirmDelete(s, targets);
    };

    // Upload (button + drag-and-drop)
    $("fsUploadBtn").onclick = () => $("fsUploadInput").click();
    $("fsUploadInput").onchange = async () => {
      const files = [...($("fsUploadInput").files || [])];
      $("fsUploadInput").value = "";
      if (files.length) await uploadFiles(files);
    };

    async function uploadFiles(files) {
      const s = activeSession();
      if (!s || s.state !== "connected") return;
      const dir = s.fs.cwd || "/";
      for (const file of files) {
        const tr = addTransfer("upload", file.name, file.size);
        try {
          const buf = new Uint8Array(await file.arrayBuffer());
          const targetPath = joinPath(dir, file.name);
          await rpc(s.run, "write", { path: targetPath, data: buf }, (done, total) => {
            tr.done = done;
            if (total > 0) tr.total = total;
            renderTransfers();
          });
          tr.done = tr.total || buf.byteLength;
          tr.status = "done";
          renderTransfers();
        } catch (err) {
          tr.status = "error";
          tr.error = err.message || L("上传失败", "Upload failed");
          renderTransfers();
        }
      }
      loadDir(s, dir);
    }

    // Drag & drop onto fileWorkbench
    let dragDepth = 0;
    const dropHost = $("filesMain");
    dropHost.addEventListener("dragenter", (ev) => {
      if (!ev.dataTransfer?.types?.includes("Files")) return;
      ev.preventDefault();
      dragDepth++;
      const s = activeSession();
      $("fsDropText").textContent = L("松开鼠标上传至 ", "Drop files to upload to ") + (s?.fs.cwd || "/");
      $("fsDropOverlay").hidden = false;
    });
    dropHost.addEventListener("dragover", (ev) => {
      if (!ev.dataTransfer?.types?.includes("Files")) return;
      ev.preventDefault();
    });
    dropHost.addEventListener("dragleave", () => {
      dragDepth = Math.max(0, dragDepth - 1);
      if (dragDepth === 0) $("fsDropOverlay").hidden = true;
    });
    dropHost.addEventListener("drop", (ev) => {
      ev.preventDefault();
      dragDepth = 0;
      $("fsDropOverlay").hidden = true;
      const files = [...(ev.dataTransfer?.files || [])];
      if (files.length) uploadFiles(files);
    });

    // Mkdir / New File / Rename / Chmod / Delete
    async function promptText(title, label, initial = "", placeholder = "") {
      return new Promise((resolve) => {
        const dlg = createBSDialog(
          title,
          '<div class="field"><label for="fsPromptVal">' + e(label) +
          '</label><input id="fsPromptVal" type="text" value="' + e(initial) + '" placeholder="' + e(placeholder) +
          '" spellcheck="false" /></div><div class="dialog-actions"><button type="button" id="fsPromptCancel">' +
          e(L("取消", "Cancel")) + '</button><button type="button" id="fsPromptOk" class="primary">' +
          e(L("确认", "Confirm")) + "</button></div>",
          L("关闭", "Close")
        );
        const inp = $("fsPromptVal");
        let done = false;
        const finish = (val) => {
          if (done) return;
          done = true;
          dlg.close();
          resolve(val);
        };
        dlg.addEventListener("close", () => finish(null), { once: true });
        $("fsPromptCancel").onclick = () => finish(null);
        $("fsPromptOk").onclick = () => finish(inp.value.trim());
        inp.onkeydown = (ev) => {
          if (ev.key === "Enter") { ev.preventDefault(); finish(inp.value.trim()); }
        };
        inp.focus();
        inp.select();
      });
    }

    $("fsMkdirBtn").onclick = async () => {
      const s = activeSession();
      if (!s || s.state !== "connected") return;
      const name = await promptText(L("新建文件夹", "New Folder"), L("文件夹名称", "Folder name"), "", "configs");
      if (!name || name.includes("/")) return;
      try {
        await rpc(s.run, "mkdir", { path: joinPath(s.fs.cwd, name) });
        BSDialog.toast(L("文件夹已创建", "Folder created"), "success");
        loadDir(s, s.fs.cwd);
      } catch (err) {
        BSDialog.toast(err.message, "error");
      }
    };

    $("fsNewFileBtn").onclick = async () => {
      const s = activeSession();
      if (!s || s.state !== "connected") return;
      const name = await promptText(L("新建文件", "New File"), L("文件名", "File name"), "", "notes.md");
      if (!name || name.includes("/")) return;
      const full = joinPath(s.fs.cwd, name);
      try {
        await rpc(s.run, "write", { path: full, data: new Uint8Array(0) });
        await loadDir(s, s.fs.cwd);
        openFileDrawer(s, { name, path: full, isDir: false, size: 0, mime: "text/plain" });
      } catch (err) {
        BSDialog.toast(err.message, "error");
      }
    };

    async function promptRename(s, item) {
      const nextName = await promptText(L("重命名", "Rename"), L("新名称", "New name"), item.name);
      if (!nextName || nextName === item.name || nextName.includes("/")) return;
      const to = joinPath(parentPath(item.path), nextName);
      try {
        await rpc(s.run, "rename", { path: item.path, to });
        BSDialog.toast(L("已重命名", "Renamed"), "success");
        loadDir(s, s.fs.cwd);
      } catch (err) {
        BSDialog.toast(err.message, "error");
      }
    }

    async function promptChmod(s, item) {
      const mode = await promptText(L("修改权限 (chmod)", "Change Permissions"), item.name, item.mode || "0644", "0755");
      if (!mode) return;
      try {
        await rpc(s.run, "chmod", { path: item.path, mode });
        BSDialog.toast(L("权限已更新", "Permissions updated"), "success");
        loadDir(s, s.fs.cwd);
      } catch (err) {
        BSDialog.toast(err.message, "error");
      }
    }

    async function confirmDelete(s, items) {
      const msg = items.length === 1
        ? L("确定删除 ", "Delete ") + items[0].name + (items[0].isDir ? L("（含目录内所有文件）？", " (and all contents)?") : "？")
        : L("确定删除选中的 ", "Delete ") + items.length + L(" 项？此操作不可撤销。", " selected items? This cannot be undone.");
      if (!(await BSDialog.confirm2(msg))) return;
      for (const it of items) {
        try {
          await rpc(s.run, "delete", { path: it.path, isDir: it.isDir });
          if (editorFile && editorFile.path === it.path) closeDrawer(true);
        } catch (err) {
          BSDialog.toast(it.name + ": " + err.message, "error");
        }
      }
      selectedPaths.clear();
      loadDir(s, s.fs.cwd);
    }

    async function downloadFile(s, item) {
      const tr = addTransfer("download", item.name, item.size);
      try {
        const res = await rpc(s.run, "read", { path: item.path, maxBytes: 0 }, (done, total) => {
          tr.done = done;
          if (total > 0) tr.total = total;
          renderTransfers();
        });
        const blob = new Blob([res.data], { type: item.mime || "application/octet-stream" });
        const a = document.createElement("a");
        const url = URL.createObjectURL(blob);
        a.href = url;
        a.download = item.name;
        document.body.appendChild(a);
        a.click();
        a.remove();
        setTimeout(() => URL.revokeObjectURL(url), 5000);
        tr.done = tr.total || res.data.byteLength;
        tr.status = "done";
        renderTransfers();
      } catch (err) {
        tr.status = "error";
        tr.error = err.message || L("下载失败", "Download failed");
        renderTransfers();
      }
    }

    // ---------------- Slide-Over Remote Code Editor & Preview Drawer ----------------
    function updateGutter() {
      const lines = ($("fsEditorArea").value || "").split("\n").length;
      let out = "";
      for (let i = 1; i <= lines; i++) out += i + "\n";
      $("fsEditorGutter").textContent = out;
    }

    $("fsEditorArea").addEventListener("input", () => {
      updateGutter();
      if (editorFile) {
        editorFile.dirty = $("fsEditorArea").value !== editorFile.originalText;
        $("fsDirtyDot").hidden = !editorFile.dirty;
      }
    });
    $("fsEditorArea").addEventListener("scroll", () => {
      $("fsEditorGutter").scrollTop = $("fsEditorArea").scrollTop;
    });
    $("fsEditorArea").addEventListener("keydown", (ev) => {
      if ((ev.ctrlKey || ev.metaKey) && ev.key.toLowerCase() === "s") {
        ev.preventDefault();
        saveRemoteFile();
      } else if (ev.key === "Tab") {
        ev.preventDefault();
        const ta = $("fsEditorArea");
        const start = ta.selectionStart, end = ta.selectionEnd;
        ta.value = ta.value.slice(0, start) + "  " + ta.value.slice(end);
        ta.selectionStart = ta.selectionEnd = start + 2;
        ta.dispatchEvent(new Event("input"));
      }
    });

    async function openFileDrawer(s, item) {
      if (editorFile?.dirty && !(await BSDialog.confirm2(L("当前文件有未保存修改，确定放弃并切换？", "Discard unsaved changes?")))) {
        return;
      }
      if (currentBlobUrl) {
        URL.revokeObjectURL(currentBlobUrl);
        currentBlobUrl = null;
      }
      $("fsDrawer").hidden = false;
      $("fsDrawerIcon").className = "fa-solid " + iconFor(item) + " ed-icon";
      $("fsDrawerName").textContent = item.name;
      $("fsDrawerPath").textContent = item.path;
      $("fsDirtyDot").hidden = true;
      $("fsEditorBody").hidden = true;
      $("fsPreviewBody").hidden = true;
      $("fsDrawerSave").hidden = true;
      $("fsPreviewImg").hidden = true;
      $("fsPreviewPdf").hidden = true;
      $("fsPreviewBinary").hidden = true;
      $("fsDrawerMeta").textContent = L("读取中…", "Loading…");
      $("fsDrawerDownload").onclick = () => downloadFile(s, item);

      const textMode = isTextFile(item.name, item.mime);
      const imgMode = isImageFile(item.name, item.mime);
      const pdfMode = isPdfFile(item.name, item.mime);

      if (!textMode && !imgMode && !pdfMode) {
        editorFile = { sessionId: s.id, path: item.path, name: item.name, dirty: false };
        $("fsPreviewBody").hidden = false;
        $("fsPreviewBinary").hidden = false;
        $("fsPreviewBinaryText").textContent =
          item.name + " (" + fmtSize(item.size) + ") — " + L("二进制文件不支持直接预览，请点击右上角下载。", "Binary file cannot be previewed. Use download above.");
        $("fsDrawerMeta").textContent = fmtSize(item.size);
        return;
      }

      try {
        const limit = textMode ? 2 * 1024 * 1024 : 12 * 1024 * 1024;
        const res = await rpc(s.run, "read", { path: item.path, maxBytes: limit });
        if (textMode) {
          const text = new TextDecoder("utf-8", { fatal: false }).decode(res.data);
          editorFile = { sessionId: s.id, path: item.path, name: item.name, originalText: text, dirty: false };
          $("fsEditorArea").value = text;
          $("fsEditorArea").readOnly = Boolean(res.truncated);
          updateGutter();
          $("fsEditorBody").hidden = false;
          $("fsDrawerSave").hidden = Boolean(res.truncated);
          $("fsDrawerMeta").textContent =
            (res.truncated ? L("只读（已截断前 2MB）", "Read-only (truncated 2MB)") : "UTF-8 · Ctrl+S") + " · " + fmtSize(res.size);
          renderSessionFiles(s);
        } else if (imgMode) {
          editorFile = { sessionId: s.id, path: item.path, name: item.name, dirty: false };
          const blob = new Blob([res.data], { type: item.mime || "image/" + (extOf(item.name) === "svg" ? "svg+xml" : extOf(item.name)) });
          currentBlobUrl = URL.createObjectURL(blob);
          $("fsPreviewImg").src = currentBlobUrl;
          $("fsPreviewImg").alt = item.name;
          $("fsPreviewImg").hidden = false;
          $("fsPreviewBody").hidden = false;
          $("fsDrawerMeta").textContent = L("图片预览", "Image") + " · " + fmtSize(res.size);
        } else if (pdfMode) {
          editorFile = { sessionId: s.id, path: item.path, name: item.name, dirty: false };
          const blob = new Blob([res.data], { type: "application/pdf" });
          currentBlobUrl = URL.createObjectURL(blob);
          $("fsPreviewPdf").src = currentBlobUrl;
          $("fsPreviewPdf").hidden = false;
          $("fsPreviewBody").hidden = false;
          $("fsDrawerMeta").textContent = "PDF · " + fmtSize(res.size);
        }
      } catch (err) {
        BSDialog.toast(err.message, "error");
        closeDrawer(true);
      }
    }

    async function saveRemoteFile() {
      const s = activeSession();
      if (!s || !editorFile || editorFile.sessionId !== s.id) return;
      const text = $("fsEditorArea").value;
      const bytes = new TextEncoder().encode(text);
      $("fsDrawerSave").disabled = true;
      try {
        await rpc(s.run, "write", { path: editorFile.path, data: bytes });
        editorFile.originalText = text;
        editorFile.dirty = false;
        $("fsDirtyDot").hidden = true;
        BSDialog.toast(L("已保存到远端", "Saved to remote"), "success");
        loadDir(s, s.fs.cwd);
      } catch (err) {
        BSDialog.toast(L("保存失败：", "Save failed: ") + err.message, "error");
      } finally {
        $("fsDrawerSave").disabled = false;
      }
    }

    async function closeDrawer(force = false) {
      if (!force && editorFile?.dirty && !(await BSDialog.confirm2(L("有未保存修改，确定关闭？", "Discard unsaved changes?")))) {
        return;
      }
      if (currentBlobUrl) {
        URL.revokeObjectURL(currentBlobUrl);
        currentBlobUrl = null;
      }
      editorFile = null;
      $("fsDrawer").hidden = true;
      const s = activeSession();
      if (s) renderSessionFiles(s);
    }

    $("fsDrawerSave").onclick = saveRemoteFile;
    $("fsDrawerClose").onclick = () => closeDrawer(false);

    // ---------------- Mobile Action Sheet ----------------
    function closeMobileSheet() {
      $("mobileFileSheet").hidden = true;
      $("mobileSheetBackdrop").hidden = true;
    }
    $("mobileSheetBackdrop").onclick = closeMobileSheet;
    $("mobileSheetClose").onclick = closeMobileSheet;

    function openMobileSheet(s, item) {
      const isDav = s.cfg.protocol === "webdav";
      $("mobileSheetTitle").textContent = item.name + (item.isDir ? "/" : " · " + fmtSize(item.size));
      const box = $("mobileSheetActions");
      box.replaceChildren();
      const defs = [];
      if (item.isDir && !isDav) {
        defs.push(["fa-terminal", L("终端 cd", "cd Here"), "blue", () => {
          host.sendTerminalCommand("cd " + shellQuote(item.path) + "\r");
          setViewMode("terminal");
          BSDialog.toast(L("已切换到 ", "cd ") + item.path, "success");
        }]);
      }
      if (!item.isDir) {
        defs.push([isTextFile(item.name, item.mime) ? "fa-pen" : "fa-eye", isTextFile(item.name, item.mime) ? L("编辑", "Edit") : L("预览", "Preview"), "blue", () => openFileDrawer(s, item)]);
        defs.push(["fa-download", L("下载", "Download"), "green", () => downloadFile(s, item)]);
      }
      defs.push(["fa-copy", L("复制路径", "Copy Path"), "amber", () => {
        navigator.clipboard?.writeText(item.path).then(() => BSDialog.toast(L("路径已复制", "Path copied"), "success")).catch(() => {});
      }]);
      defs.push(["fa-i-cursor", L("重命名", "Rename"), "slate", () => promptRename(s, item)]);
      if (!isDav) {
        defs.push(["fa-shield-halved", "chmod", "slate", () => promptChmod(s, item)]);
      }
      defs.push(["fa-trash", L("删除", "Delete"), "red", () => confirmDelete(s, [item])]);

      for (const [ic, label, tone, fn] of defs) {
        const b = document.createElement("button");
        b.type = "button";
        b.className = "sheet-act tone-" + tone;
        b.innerHTML = '<i class="fa-solid ' + ic + '" aria-hidden="true"></i><span>' + e(label) + "</span>";
        b.onclick = () => { closeMobileSheet(); fn(); };
        box.appendChild(b);
      }
      $("mobileSheetBackdrop").hidden = false;
      $("mobileFileSheet").hidden = false;
    }

    // ---------------- Terminal CWD Sync (OSC 7 + prompt detection) ----------------
    const cwdDecoder = new TextDecoder("utf-8", { fatal: false });
    function onTerminalOutput(s, bytes) {
      if (!followCwd || !s || s.cfg.protocol === "webdav" || s.viewMode === "terminal") return;
      const chunk = cwdDecoder.decode(bytes);
      let nextPath = null;
      // OSC 7: \x1b]7;file://host/path\x07 or \x1b\\
      const osc7 = chunk.match(/\x1b\]7;file:\/\/[^/\x07\x1b]*(\/[^\x07\x1b]+)(?:\x07|\x1b\\)/);
      if (osc7) {
        try { nextPath = decodeURIComponent(osc7[1]); } catch (_) { nextPath = osc7[1]; }
      } else {
        // Common prompt pattern: user@host:/abs/path$ or #
        const clean = chunk.replace(/\x1b\[[0-9;?]*[ -/]*[@-~]/g, "");
        const m = clean.match(/[\w.-]+@[\w.-]+:(\/[^\r\n$#%>]*)[$#%>]\s*$/);
        if (m && m[1]) nextPath = m[1].trim();
      }
      if (nextPath && nextPath !== s.fs.cwd && !s.fs.loading) {
        clearTimeout(s.fs.cwdTimer);
        s.fs.cwdTimer = setTimeout(() => {
          if (s.state === "connected" && s.viewMode !== "terminal" && nextPath !== s.fs.cwd) {
            loadDir(s, nextPath);
          }
        }, 250);
      }
    }

    return {
      handleWorkerMessage,
      testWebDAV,
      applyViewMode,
      setViewMode,
      rpc,
      loadDir,
      renderSessionFiles,
      onTerminalOutput,
      closeDrawer,
      onSessionClosed(s) {
        if (editorFile && editorFile.sessionId === s.id) closeDrawer(true);
      },
      onLanguageChange() {
        const s = activeSession();
        if (s) {
          applyViewMode(s);
          renderSessionFiles(s);
        }
        renderTransfers();
      },
    };
  };
})();
