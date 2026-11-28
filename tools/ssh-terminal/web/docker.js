/* Multiplexed SSH Docker & Compose Workbench */
(function () {
  "use strict";
  const $ = (id) => document.getElementById(id);
  const e = window.escHtml || ((s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c])));

  function sq(s) {
    return "'" + String(s ?? "").replace(/'/g, "'\\''") + "'";
  }
  function dirOf(p) {
    if (!p) return "/";
    const clean = String(p).replace(/\/+$/, "");
    const i = clean.lastIndexOf("/");
    return i <= 0 ? "/" : clean.slice(0, i);
  }
  function joinPosix(dir, name) {
    const d = (dir || "/").replace(/\/+$/, "");
    return (d || "") + "/" + String(name || "").replace(/^\/+/, "");
  }
  function parseNDJSON(text) {
    const out = [];
    for (const raw of String(text || "").split(/\r?\n/)) {
      const line = raw.trim();
      if (!line) continue;
      try { out.push(JSON.parse(line)); } catch (_) {}
    }
    return out;
  }
  function parseLabels(raw) {
    const map = {};
    if (!raw) return map;
    for (const part of String(raw).split(",")) {
      const idx = part.indexOf("=");
      if (idx > 0) map[part.slice(0, idx).trim()] = part.slice(idx + 1).trim();
    }
    return map;
  }
  function formatPorts(raw) {
    if (!raw) return "—";
    const parts = String(raw).split(",").map((s) => s.trim()).filter(Boolean);
    const seen = new Set();
    const out = [];
    for (const p of parts) {
      const m = p.match(/(?:[\d.:[\]*]+:)?(\d+)->(\d+\/\w+)/);
      const label = m ? m[1] + " → " + m[2] : p;
      if (!seen.has(label)) {
        seen.add(label);
        out.push(label);
      }
    }
    return out.slice(0, 2).join(", ") + (out.length > 2 ? " +" + (out.length - 2) : "");
  }
  function parsePercent(s) {
    const n = parseFloat(String(s || "0").replace("%", ""));
    return Number.isFinite(n) ? n : 0;
  }
  function parseMemBytes(str) {
    const m = String(str || "").trim().match(/^([\d.]+)\s*([KMGTP]?i?B)/i);
    if (!m) return 0;
    const val = parseFloat(m[1]);
    const u = m[2].toUpperCase();
    const mult = u.startsWith("T") ? 1024 ** 4 : u.startsWith("G") ? 1024 ** 3 : u.startsWith("M") ? 1024 ** 2 : u.startsWith("K") ? 1024 : 1;
    return val * mult;
  }
  function fmtBytes(n) {
    if (!n || n <= 0) return "0 B";
    if (n < 1024) return Math.round(n) + " B";
    if (n < 1024 ** 2) return (n / 1024).toFixed(1) + " KB";
    if (n < 1024 ** 3) return (n / 1024 ** 2).toFixed(1) + " MB";
    return (n / 1024 ** 3).toFixed(2) + " GB";
  }

  const COMPOSE_TEMPLATES = {
    blank: `services:\n  app:\n    image: nginx:alpine\n    container_name: my-app\n    restart: unless-stopped\n    ports:\n      - "8080:80"\n`,
    uptime: `services:\n  uptime-kuma:\n    image: louislam/uptime-kuma:1\n    container_name: uptime-kuma\n    restart: unless-stopped\n    ports:\n      - "3001:3001"\n    volumes:\n      - ./data:/app/data\n`,
    watchtower: `services:\n  watchtower:\n    image: containrrr/watchtower:latest\n    container_name: watchtower\n    restart: unless-stopped\n    volumes:\n      - /var/run/docker.sock:/var/run/docker.sock\n    environment:\n      - WATCHTOWER_CLEANUP=true\n      - WATCHTOWER_SCHEDULE=0 0 4 * * *\n`,
  };

  window.createDockerWorkbench = function createDockerWorkbench(host) {
    let seq = 1;
    const pendingExec = new Map();
    const activeStreams = new Map();
    const sessionState = new Map();
    let autoRefresh = false;
    let refreshTimer = null;

    function isZh() { return host.getLang() === "zh"; }
    function L(zh, en) { return isZh() ? zh : en; }
    function curSession() { return host.getActiveSession(); }

    function stateOf(s) {
      if (!s) return null;
      let st = sessionState.get(s.id);
      if (!st) {
        st = {
          loaded: false,
          loading: false,
          error: "",
          dockerVer: "",
          composeVer: "",
          subtab: "containers", // containers | compose | images | storage
          filter: "",
          statusFilter: "all", // all | running | stopped
          groupByStack: false,
          containers: [],
          statsMap: new Map(),
          stacks: [],
          images: [],
          volumes: [],
          networks: [],
          dfText: "—",
          reclaimText: "—",
          selectedContainerId: null,
          inspectData: null,
          drawerTab: "logs", // logs | config | mounts | network
          logFollow: true,
          logTail: 200,
          logFilter: "",
          logLines: [],
          logStreamId: null,
          // Compose view state
          selectedStackName: null,
          composeFileTab: "compose", // compose | env
          composeContent: "",
          composeOrig: "",
          composeDirty: false,
          composePath: "",
          composeDir: "",
          composeExecCmd: "",
          composeExecStatus: "",
          composeExecLines: [],
          composeStreamId: null,
          stackEditingMobile: false,
          imageFilter: "",
        };
        sessionState.set(s.id, st);
      }
      return st;
    }

    // ---------------- Worker Message Router ----------------
    function handleWorkerMessage(m) {
      if (m.type === "exec-res") {
        const p = pendingExec.get(m.reqId);
        if (p) {
          pendingExec.delete(m.reqId);
          clearTimeout(p.timer);
          p.resolve(m);
        }
        return true;
      }
      if (m.type === "exec-stream") {
        const st = activeStreams.get(m.streamId);
        if (st?.onChunk) st.onChunk(m.chunk || "", Boolean(m.isErr));
        return true;
      }
      if (m.type === "exec-stream-end") {
        const st = activeStreams.get(m.streamId);
        if (st) {
          activeStreams.delete(m.streamId);
          st.onEnd?.(m);
        }
        return true;
      }
      return false;
    }

    function execCmd(s, command, timeoutMs = 25000) {
      return new Promise((resolve, reject) => {
        const w = host.getWorker();
        if (!w || !s || s.state !== "connected") {
          return reject(new Error(L("SSH 会话未连接", "SSH session not connected")));
        }
        const reqId = "ex-" + seq++;
        const timer = setTimeout(() => {
          pendingExec.delete(reqId);
          reject(new Error(L("命令执行超时", "Command timed out")));
        }, timeoutMs);
        pendingExec.set(reqId, { resolve, reject, timer });
        w.postMessage({ type: "exec-req", id: s.run, reqId, command });
      });
    }

    function startStream(s, command, handlers) {
      const w = host.getWorker();
      if (!w || !s || s.state !== "connected") return null;
      const streamId = "st-" + seq++;
      activeStreams.set(streamId, handlers || {});
      w.postMessage({ type: "exec-stream-start", id: s.run, streamId, command });
      return streamId;
    }

    function stopStream(s, streamId) {
      if (!streamId) return;
      activeStreams.delete(streamId);
      const w = host.getWorker();
      if (w && s) w.postMessage({ type: "exec-stream-stop", id: s.run, streamId });
    }

    // ---------------- Data Loading ----------------
    async function refreshAll(s, silent = false) {
      if (!s || s.state !== "connected" || s.cfg.protocol === "webdav") return;
      const st = stateOf(s);
      if (st.loading) return;
      st.loading = true;
      if (!silent) {
        st.error = "";
        render(s);
      }
      try {
        const [verRes, psRes, lsRes, dfRes] = await Promise.all([
          execCmd(s, "docker version --format '{{.Server.Version}}' 2>&1; echo '---SEP---'; docker compose version --short 2>/dev/null || true"),
          execCmd(s, "docker ps -a --no-trunc --format '{{json .}}'"),
          execCmd(s, "docker compose ls --all --format json 2>/dev/null || echo '[]'"),
          execCmd(s, "docker system df --format '{{json .}}' 2>/dev/null || true"),
        ]);

        if (!psRes.ok) {
          const msg = (psRes.stderr || psRes.stdout || psRes.error || "").trim();
          st.error = msg.includes("command not found")
            ? L("该主机未安装 Docker，或当前用户 PATH 中找不到 docker 命令。", "Docker is not installed or not in PATH on this host.")
            : msg.includes("permission denied")
              ? L("当前 SSH 用户无权限访问 Docker Socket（请加入 docker 用户组或使用 root 连接）。", "Permission denied accessing Docker socket.")
              : (L("读取 Docker 信息失败：", "Failed to query Docker: ") + msg);
          st.loaded = true;
          st.loading = false;
          render(s);
          return;
        }

        st.error = "";
        const verParts = (verRes.stdout || "").split("---SEP---");
        st.dockerVer = (verParts[0] || "").trim().split("\n")[0] || "";
        st.composeVer = (verParts[1] || "").trim().split("\n")[0] || "";

        st.containers = parseNDJSON(psRes.stdout).map((c) => {
          const labels = parseLabels(c.Labels);
          const state = String(c.State || "").toLowerCase();
          return {
            id: c.ID || "",
            shortId: String(c.ID || "").slice(0, 12),
            name: String(c.Names || "").replace(/^\//, ""),
            image: c.Image || "",
            state,
            status: c.Status || "",
            ports: c.Ports || "",
            portsShort: formatPorts(c.Ports),
            running: state === "running",
            stack: labels["com.docker.compose.project"] || "",
            configFile: labels["com.docker.compose.project.config_files"] || "",
            workDir: labels["com.docker.compose.project.working_dir"] || "",
            networks: c.Networks || "",
            created: c.CreatedAt || "",
          };
        });

        try {
          const parsedStacks = JSON.parse((lsRes.stdout || "[]").trim() || "[]");
          st.stacks = Array.isArray(parsedStacks) ? parsedStacks : [];
        } catch (_) {
          st.stacks = [];
        }

        // Parse system df
        const dfItems = parseNDJSON(dfRes.stdout);
        let totalBytes = 0;
        let reclaimBytes = 0;
        for (const item of dfItems) {
          totalBytes += parseMemBytes(item.Size);
          const rec = String(item.Reclaimable || "").split("(")[0].trim();
          reclaimBytes += parseMemBytes(rec);
        }
        if (dfItems.length) {
          st.dfText = fmtBytes(totalBytes);
          st.reclaimText = fmtBytes(reclaimBytes);
        }

        // Keep selected container valid
        if (st.selectedContainerId && !st.containers.some((c) => c.id === st.selectedContainerId)) {
          closeContainerDrawer(s);
        }

        // Auto-select first compose stack on desktop if none selected
        if (st.subtab === "compose" && !st.selectedStackName && st.stacks.length && !matchMedia("(max-width:640px)").matches) {
          selectStack(s, st.stacks[0], false);
        }

        st.loaded = true;
        st.loading = false;
        render(s);
        host.onDockerSummary?.(s, st.containers.length);

        // Fetch live CPU/Mem stats in background without delaying table render
        if (st.containers.some((c) => c.running)) {
          execCmd(s, "docker stats --no-stream --no-trunc --format '{{json .}}' 2>/dev/null || true", 15000)
            .then((statsRes) => {
              const map = new Map();
              for (const row of parseNDJSON(statsRes.stdout)) {
                const key = row.ID || row.Name;
                if (key) {
                  map.set(row.ID || "", row);
                  if (row.Name) map.set(row.Name.replace(/^\//, ""), row);
                }
              }
              st.statsMap = map;
              if (curSession()?.id === s.id && s.viewMode === "docker") render(s);
            })
            .catch(() => {});
        }
      } catch (err) {
        st.error = err.message || String(err);
        st.loaded = true;
        st.loading = false;
        render(s);
      }
    }

    async function refreshImages(s) {
      const st = stateOf(s);
      try {
        const res = await execCmd(s, "docker images --format '{{json .}}'");
        if (res.ok) {
          st.images = parseNDJSON(res.stdout);
          render(s);
        }
      } catch (err) {
        BSDialog.toast(err.message, "error");
      }
    }

    async function refreshStorage(s) {
      const st = stateOf(s);
      try {
        const [vRes, nRes] = await Promise.all([
          execCmd(s, "docker volume ls --format '{{json .}}'"),
          execCmd(s, "docker network ls --format '{{json .}}'"),
        ]);
        if (vRes.ok) st.volumes = parseNDJSON(vRes.stdout);
        if (nRes.ok) st.networks = parseNDJSON(nRes.stdout);
        render(s);
      } catch (err) {
        BSDialog.toast(err.message, "error");
      }
    }

    // ---------------- Container Actions & Live Logs ----------------
    async function containerAction(s, c, action) {
      if (action === "rm") {
        const ok = await BSDialog.confirm2(
          L("确认删除容器 ", "Delete container ") + c.name + L("？（运行中将强制停止并删除）", "? (Running container will be force-removed)")
        );
        if (!ok) return;
      }
      const cmdMap = {
        start: "docker start " + sq(c.id),
        stop: "docker stop " + sq(c.id),
        restart: "docker restart " + sq(c.id),
        rm: "docker rm -f " + sq(c.id),
      };
      const cmd = cmdMap[action];
      if (!cmd) return;
      try {
        BSDialog.toast(L("正在执行 ", "Running ") + action + " " + c.name + "…", "info");
        const res = await execCmd(s, cmd, 60000);
        if (!res.ok) {
          BSDialog.toast((res.stderr || res.error || L("操作失败", "Action failed")).trim(), "error");
        } else {
          BSDialog.toast(c.name + " " + action + L(" 成功", " succeeded"), "success");
          if (action === "rm" && stateOf(s).selectedContainerId === c.id) closeContainerDrawer(s);
          refreshAll(s, true);
        }
      } catch (err) {
        BSDialog.toast(err.message, "error");
      }
    }

    function openContainerExec(s, c) {
      if (!c.running) {
        BSDialog.toast(L("容器未运行，请先启动", "Container is not running"), "error");
        return;
      }
      host.setViewMode("terminal");
      const cmd = "docker exec -it " + sq(c.name || c.id) + " sh -c 'command -v bash >/dev/null 2>&1 && exec bash || exec sh'\r";
      host.sendTerminalCommand(cmd);
      BSDialog.toast(L("已进入容器终端：", "Attached to container: ") + c.name, "success");
    }

    async function openContainerDrawer(s, c, tab = "logs") {
      const st = stateOf(s);
      const changed = st.selectedContainerId !== c.id;
      st.selectedContainerId = c.id;
      st.drawerTab = tab;
      if (changed) {
        st.inspectData = null;
        stopLogStream(s);
        st.logLines = [];
      }
      render(s);
      if (tab === "logs" && (changed || !st.logStreamId)) {
        startLogStream(s, c);
      }
      if (!st.inspectData) {
        try {
          const res = await execCmd(s, "docker inspect " + sq(c.id));
          if (res.ok) {
            const arr = JSON.parse(res.stdout || "[]");
            if (Array.isArray(arr) && arr[0] && stateOf(s).selectedContainerId === c.id) {
              st.inspectData = arr[0];
              renderDrawerBody(s);
            }
          }
        } catch (_) {}
      }
    }

    function closeContainerDrawer(s) {
      const st = stateOf(s);
      stopLogStream(s);
      st.selectedContainerId = null;
      st.inspectData = null;
      st.logLines = [];
      render(s);
    }

    function stopLogStream(s) {
      const st = stateOf(s);
      if (st.logStreamId) {
        stopStream(s, st.logStreamId);
        st.logStreamId = null;
      }
    }

    function startLogStream(s, c) {
      const st = stateOf(s);
      stopLogStream(s);
      st.logLines = [];
      renderLogBody(s);
      const tail = Number(st.logTail) || 200;
      const followFlag = st.logFollow ? "-f " : "";
      const cmd = "docker logs " + followFlag + "--timestamps --tail " + tail + " " + sq(c.id);
      let buf = "";
      st.logStreamId = startStream(s, cmd, {
        onChunk(chunk, isErr) {
          buf += chunk;
          const parts = buf.split(/\r?\n/);
          buf = parts.pop() || "";
          for (const line of parts) {
            st.logLines.push({ text: line, isErr });
          }
          if (st.logLines.length > 1500) {
            st.logLines.splice(0, st.logLines.length - 1500);
          }
          if (curSession()?.id === s.id && st.selectedContainerId === c.id && st.drawerTab === "logs") {
            renderLogBody(s);
          }
        },
        onEnd() {
          if (buf) {
            st.logLines.push({ text: buf, isErr: false });
            buf = "";
          }
          st.logStreamId = null;
          if (curSession()?.id === s.id && st.selectedContainerId === c.id && st.drawerTab === "logs") {
            renderLogBody(s);
          }
        },
      });
    }

    function jumpToHostDir(s, dirPath) {
      if (!dirPath) return;
      host.openFilesAt(s, dirPath);
    }

    // ---------------- Compose Stack Management ----------------
    async function selectStack(s, stack, mobileOpen = true) {
      const st = stateOf(s);
      if (st.composeDirty && !(await BSDialog.confirm2(L("当前 Compose 文件有未保存修改，确定切换？", "Discard unsaved Compose changes?")))) {
        return;
      }
      st.selectedStackName = stack.Name;
      st.composeFileTab = "compose";
      const cfgRaw = String(stack.ConfigFiles || "").split(",")[0].trim();
      st.composePath = cfgRaw;
      st.composeDir = dirOf(cfgRaw);
      st.stackEditingMobile = mobileOpen;
      st.composeDirty = false;
      st.composeContent = "";
      st.composeOrig = "";
      render(s);
      if (cfgRaw) {
        await loadComposeFile(s, "compose");
      }
    }

    async function loadComposeFile(s, tab) {
      const st = stateOf(s);
      st.composeFileTab = tab;
      const targetPath = tab === "env" ? joinPosix(st.composeDir, ".env") : st.composePath;
      if (!targetPath) return;
      st.composeDirty = false;
      st.composeContent = L("# 正在通过 SFTP 读取 ", "# Loading via SFTP: ") + targetPath + "…";
      renderComposeEditor(s);
      try {
        const res = await host.fsRpc(s.run, "read", { path: targetPath, maxBytes: 1024 * 1024 });
        const text = new TextDecoder("utf-8", { fatal: false }).decode(res.data || new Uint8Array());
        st.composeContent = text;
        st.composeOrig = text;
      } catch (err) {
        if (tab === "env") {
          st.composeContent = "# " + targetPath + "\n";
          st.composeOrig = "";
        } else {
          st.composeContent = "# " + L("无法读取文件：", "Cannot read file: ") + err.message;
          st.composeOrig = "";
        }
      }
      renderComposeEditor(s);
    }

    async function saveComposeFile(s, silentToast = false) {
      const st = stateOf(s);
      const targetPath = st.composeFileTab === "env" ? joinPosix(st.composeDir, ".env") : st.composePath;
      if (!targetPath) return false;
      const text = $("dkComposeEditor").value;
      const enc = new TextEncoder();
      try {
        // Auto-backup original file to .bak before overwriting
        if (st.composeOrig && st.composeOrig !== text) {
          await host.fsRpc(s.run, "write", { path: targetPath + ".bak", data: enc.encode(st.composeOrig) }).catch(() => {});
        }
        await host.fsRpc(s.run, "write", { path: targetPath, data: enc.encode(text) });
        st.composeContent = text;
        st.composeOrig = text;
        st.composeDirty = false;
        if (!silentToast) BSDialog.toast(L("已保存（原文件已备份 .bak）", "Saved (backup saved as .bak)"), "success");
        renderComposeBar(s);
        return true;
      } catch (err) {
        BSDialog.toast(L("保存失败：", "Save failed: ") + err.message, "error");
        return false;
      }
    }

    async function runComposeOp(s, op) {
      const st = stateOf(s);
      if (!st.composePath) return;
      if (op === "down") {
        const ok = await BSDialog.confirm2(L("确认停止并移除栈 ", "Stop and remove stack ") + st.selectedStackName + " (docker compose down)?");
        if (!ok) return;
      }
      if (op === "up" && st.composeDirty) {
        const saved = await saveComposeFile(s, true);
        if (!saved) return;
      }
      if (st.composeStreamId) {
        stopStream(s, st.composeStreamId);
        st.composeStreamId = null;
      }
      const base = "cd " + sq(st.composeDir) + " && docker compose -f " + sq(st.composePath);
      const cmds = {
        up: base + " up -d",
        pull: base + " pull && " + base + " up -d",
        restart: base + " restart",
        down: base + " down",
      };
      const cmd = cmds[op];
      if (!cmd) return;
      const started = Date.now();
      st.composeExecCmd = cmd;
      st.composeExecStatus = L("执行中…", "Running…");
      st.composeExecLines = ["$ " + cmd];
      renderComposeConsole(s);

      let buf = "";
      st.composeStreamId = startStream(s, cmd, {
        onChunk(chunk) {
          buf += chunk;
          const parts = buf.split(/\r?\n/);
          buf = parts.pop() || "";
          for (const line of parts) st.composeExecLines.push(line);
          if (curSession()?.id === s.id) renderComposeConsole(s);
        },
        onEnd(res) {
          if (buf) { st.composeExecLines.push(buf); buf = ""; }
          st.composeStreamId = null;
          const sec = ((Date.now() - started) / 1000).toFixed(1) + "s";
          st.composeExecStatus = res.code === 0
            ? L("已完成 (" + sec + ")", "Done (" + sec + ")")
            : L("失败 (exit " + res.code + ")", "Failed (exit " + res.code + ")");
          if (curSession()?.id === s.id) renderComposeConsole(s);
          refreshAll(s, true);
        },
      });
    }

    async function promptNewComposeStack(s) {
      const html =
        '<div class="bs-form">' +
        '<label>' + e(L("栈名称", "Stack name")) + '<input id="dkNewName" class="dialog-input" placeholder="my-app" /></label>' +
        '<label>' + e(L("部署目录（远程绝对路径）", "Remote directory")) + '<input id="dkNewDir" class="dialog-input" value="/opt/stacks/my-app" /></label>' +
        '<label>' + e(L("模板", "Template")) + '<select id="dkNewTpl" class="dialog-input">' +
        '<option value="blank">' + e(L("基础 Nginx 示例", "Basic Nginx")) + '</option>' +
        '<option value="uptime">Uptime Kuma</option>' +
        '<option value="watchtower">Watchtower</option>' +
        '</select></label>' +
        '<label>docker-compose.yml<textarea id="dkNewYaml" class="dialog-input" rows="8" style="font-family:monospace;font-size:12px">' + e(COMPOSE_TEMPLATES.blank) + '</textarea></label>' +
        '<div style="display:flex;justify-content:flex-end;gap:8px;margin-top:8px">' +
        '<button type="button" class="bs-btn bs-btn-cancel" id="dkNewCancel">' + e(L("取消", "Cancel")) + '</button>' +
        '<button type="button" class="bs-btn bs-btn-primary" id="dkNewSubmit">' + e(L("创建并部署 (Up -d)", "Create & Up -d")) + '</button>' +
        '</div></div>';
      const dlg = createBSDialog(L("新建 Compose 栈", "New Compose Stack"), html, L("关闭", "Close"));
      const nameIn = dlg.querySelector("#dkNewName");
      const dirIn = dlg.querySelector("#dkNewDir");
      const tplSel = dlg.querySelector("#dkNewTpl");
      const yamlIn = dlg.querySelector("#dkNewYaml");
      nameIn.oninput = () => {
        const clean = nameIn.value.trim().replace(/[^a-zA-Z0-9._-]/g, "");
        if (clean) dirIn.value = "/opt/stacks/" + clean;
      };
      tplSel.onchange = () => { yamlIn.value = COMPOSE_TEMPLATES[tplSel.value] || COMPOSE_TEMPLATES.blank; };
      dlg.querySelector("#dkNewCancel").onclick = () => dlg.close();
      dlg.querySelector("#dkNewSubmit").onclick = async () => {
        const name = nameIn.value.trim().replace(/[^a-zA-Z0-9._-]/g, "");
        const dir = dirIn.value.trim().replace(/\/+$/, "");
        const yaml = yamlIn.value;
        if (!name || !dir.startsWith("/") || !yaml.trim()) {
          BSDialog.toast(L("请填写有效的名称、绝对路径和 YAML 内容", "Enter valid name, absolute path and YAML"), "error");
          return;
        }
        const btn = dlg.querySelector("#dkNewSubmit");
        btn.disabled = true;
        try {
          await host.fsRpc(s.run, "mkdir", { path: dir });
          const cfgPath = joinPosix(dir, "docker-compose.yml");
          await host.fsRpc(s.run, "write", { path: cfgPath, data: new TextEncoder().encode(yaml) });
          dlg.close();
          const st = stateOf(s);
          st.subtab = "compose";
          st.selectedStackName = name;
          st.composePath = cfgPath;
          st.composeDir = dir;
          st.composeContent = yaml;
          st.composeOrig = yaml;
          st.composeDirty = false;
          st.stackEditingMobile = true;
          render(s);
          runComposeOp(s, "up");
        } catch (err) {
          BSDialog.toast(err.message, "error");
          btn.disabled = false;
        }
      };
    }

    async function promptPullImage(s) {
      const ref = await BSDialog.prompt(L("输入要拉取的镜像名（如 nginx:alpine）", "Image name to pull (e.g. nginx:alpine)"), "", L("拉取镜像", "Pull Image"));
      if (!ref || !ref.trim()) return;
      const img = ref.trim();
      BSDialog.toast(L("正在拉取 ", "Pulling ") + img + "…", "info");
      try {
        const res = await execCmd(s, "docker pull " + sq(img), 180000);
        if (!res.ok) {
          BSDialog.toast((res.stderr || res.error || L("拉取失败", "Pull failed")).trim(), "error");
        } else {
          BSDialog.toast(L("镜像拉取完成：", "Pulled: ") + img, "success");
          refreshImages(s);
          refreshAll(s, true);
        }
      } catch (err) {
        BSDialog.toast(err.message, "error");
      }
    }

    async function pruneCache(s) {
      if (!(await BSDialog.confirm2(L("清理未使用的悬空镜像与构建缓存？不会影响正在运行的容器。", "Prune dangling images and build cache? Running containers are unaffected.")))) {
        return;
      }
      try {
        const res = await execCmd(s, "docker image prune -f && docker builder prune -f", 60000);
        if (res.ok) {
          BSDialog.toast(L("清理完成", "Prune completed"), "success");
          refreshAll(s, true);
          if (stateOf(s).subtab === "images") refreshImages(s);
        } else {
          BSDialog.toast((res.stderr || res.error || L("清理失败", "Prune failed")).trim(), "error");
        }
      } catch (err) {
        BSDialog.toast(err.message, "error");
      }
    }

    // ---------------- Rendering ----------------
    function render(s) {
      if (!s || curSession()?.id !== s.id) return;
      const st = stateOf(s);
      const runningCount = st.containers.filter((c) => c.running).length;

      $("dkCntCompose").textContent = String(st.stacks.length);
      $("dkCntContainers").textContent = String(st.containers.length);
      $("dkCntImages").textContent = st.images.length ? String(st.images.length) : "—";
      $("dkStatRun").textContent = runningCount + " / " + st.containers.length;
      $("dkStatDisk").textContent = st.dfText;

      for (const b of document.querySelectorAll("#dockerWorkbench .dk-subtab")) {
        b.classList.toggle("active", b.dataset.subtab === st.subtab);
      }

      const banner = $("dkBanner");
      if (st.error) {
        banner.hidden = false;
        banner.className = "dk-banner error";
        $("dkBannerText").textContent = st.error;
      } else {
        banner.hidden = true;
      }

      $("dkViewContainers").hidden = st.subtab !== "containers";
      $("dkViewCompose").hidden = st.subtab !== "compose";
      $("dkViewImages").hidden = st.subtab !== "images";
      $("dkViewStorage").hidden = st.subtab !== "storage";

      $("dkAutoRefreshBtn").classList.toggle("active", autoRefresh);
      $("dkAutoRefreshText").textContent = autoRefresh ? L("5s 自动刷新", "Auto 5s") : L("自动刷新", "Auto");

      if (st.subtab === "containers") renderContainersView(s);
      else if (st.subtab === "compose") renderComposeView(s);
      else if (st.subtab === "images") renderImagesView(s);
      else if (st.subtab === "storage") renderStorageView(s);
    }

    function renderContainersView(s) {
      const st = stateOf(s);
      const q = st.filter.trim().toLowerCase();
      const filtered = st.containers.filter((c) => {
        if (st.statusFilter === "running" && !c.running) return false;
        if (st.statusFilter === "stopped" && c.running) return false;
        if (!q) return true;
        return (
          c.name.toLowerCase().includes(q) ||
          c.image.toLowerCase().includes(q) ||
          c.portsShort.toLowerCase().includes(q) ||
          c.stack.toLowerCase().includes(q)
        );
      });

      const runCnt = st.containers.filter((c) => c.running).length;
      const stopCnt = st.containers.length - runCnt;
      $("dkFltAll").textContent = L("全部", "All") + " (" + st.containers.length + ")";
      $("dkFltRun").textContent = L("运行中", "Up") + " (" + runCnt + ")";
      $("dkFltStop").textContent = L("已停止", "Stopped") + " (" + stopCnt + ")";
      for (const b of document.querySelectorAll("#dkStatusSeg button")) {
        b.classList.toggle("active", b.dataset.sf === st.statusFilter);
      }
      $("dkGroupToggle").classList.toggle("active", st.groupByStack);

      const listEl = $("dkContainerList");
      listEl.replaceChildren();

      if (st.loading && !st.loaded) {
        listEl.innerHTML = '<div class="dk-empty"><i class="fa-solid fa-spinner fa-spin"></i> ' + e(L("正在通过 SSH 读取容器…", "Loading containers via SSH…")) + "</div>";
      } else if (!filtered.length) {
        listEl.innerHTML = '<div class="dk-empty">' + e(st.containers.length ? L("没有匹配的容器", "No matching containers") : L("当前主机暂无容器", "No containers on this host")) + "</div>";
      } else {
        const ordered = st.groupByStack
          ? [...filtered].sort((a, b) => (a.stack || "zzz").localeCompare(b.stack || "zzz") || a.name.localeCompare(b.name))
          : filtered;
        let lastGroup = null;
        for (const c of ordered) {
          if (st.groupByStack) {
            const grp = c.stack || L("独立容器", "Standalone");
            if (grp !== lastGroup) {
              lastGroup = grp;
              const sep = document.createElement("div");
              sep.className = "dk-group-sep";
              sep.innerHTML = '<i class="fa-solid fa-layer-group"></i><span>' + e(grp) + "</span>";
              listEl.appendChild(sep);
            }
          }
          const stat = st.statsMap.get(c.id) || st.statsMap.get(c.name);
          const cpuPct = stat ? parsePercent(stat.CPUPerc) : 0;
          const memTxt = stat ? String(stat.MemUsage || "").split("/")[0].trim() : "";
          const metricLine = stat ? stat.CPUPerc + " · " + memTxt : c.running ? "…" : "—";

          const row = document.createElement("div");
          row.className = "dk-tbl-row" + (st.selectedContainerId === c.id ? " selected" : "");
          row.innerHTML =
            '<div>' +
              '<div class="dk-cname"><span class="dk-cname-text">' + e(c.name) + "</span>" +
              (c.stack ? '<span class="dk-stack-tag">' + e(c.stack) + "</span>" : "") +
              "</div>" +
              '<div class="dk-cimg" title="' + e(c.image) + '">' + e(c.image) + "</div>" +
            "</div>" +
            '<div><span class="dk-status ' + (c.running ? "up" : "stop") + '"><i class="fa-solid fa-circle" style="font-size:6px"></i>' + e(c.status || c.state) + "</span></div>" +
            '<div>' + (c.portsShort !== "—" ? '<span class="dk-port" title="' + e(c.ports) + '">' + e(c.portsShort) + "</span>" : '<span class="dk-mono">—</span>') + "</div>" +
            '<div class="dk-metric"><span>' + e(metricLine) + '</span><span class="dk-bar"><i style="width:' + Math.min(100, Math.max(cpuPct > 0 ? 4 : 0, Math.round(cpuPct))) + '%"></i></span></div>' +
            '<div class="dk-acts">' +
              '<button type="button" class="dk-sq hi" data-act="exec" title="' + e(L("进容器终端", "Exec shell")) + '"><i class="fa-solid fa-terminal"></i></button>' +
              '<button type="button" class="dk-sq hi" data-act="logs" title="' + e(L("实时日志", "Live logs")) + '"><i class="fa-solid fa-file-lines"></i></button>' +
              '<button type="button" class="dk-sq" data-act="restart" title="' + e(L("重启", "Restart")) + '"><i class="fa-solid fa-rotate"></i></button>' +
              (c.running
                ? '<button type="button" class="dk-sq warn" data-act="stop" title="' + e(L("停止", "Stop")) + '"><i class="fa-solid fa-stop"></i></button>'
                : '<button type="button" class="dk-sq ok" data-act="start" title="' + e(L("启动", "Start")) + '"><i class="fa-solid fa-play"></i></button>') +
            "</div>";

          row.onclick = (ev) => {
            const btn = ev.target.closest("[data-act]");
            if (btn) {
              ev.stopPropagation();
              const act = btn.dataset.act;
              if (act === "exec") openContainerExec(s, c);
              else if (act === "logs") openContainerDrawer(s, c, "logs");
              else containerAction(s, c, act);
              return;
            }
            openContainerDrawer(s, c, st.drawerTab || "logs");
          };
          listEl.appendChild(row);
        }
      }

      // Compute summary metrics
      let totalCpu = 0;
      let totalMem = 0;
      for (const c of st.containers) {
        if (!c.running) continue;
        const stat = st.statsMap.get(c.id) || st.statsMap.get(c.name);
        if (stat) {
          totalCpu += parsePercent(stat.CPUPerc);
          totalMem += parseMemBytes(String(stat.MemUsage || "").split("/")[0]);
        }
      }
      $("dkSumCpu").textContent = totalCpu.toFixed(1) + "%";
      $("dkSumMem").textContent = fmtBytes(totalMem);
      $("dkSumReclaim").textContent = st.reclaimText;

      // Drawer
      const selected = st.containers.find((c) => c.id === st.selectedContainerId);
      $("dkDrawer").hidden = !selected;
      if (selected) {
        $("dkDrawerName").textContent = selected.name;
        const stBadge = $("dkDrawerStatus");
        stBadge.className = "dk-status " + (selected.running ? "up" : "stop");
        stBadge.textContent = selected.state || selected.status;
        $("dkDrStartStop").innerHTML = selected.running
          ? '<i class="fa-solid fa-stop"></i><span>' + e(L("停止", "Stop")) + "</span>"
          : '<i class="fa-solid fa-play"></i><span>' + e(L("启动", "Start")) + "</span>";
        $("dkDrStartStop").className = "dk-btn " + (selected.running ? "danger" : "up");

        const cfgFile = String(selected.configFile || "").split(",")[0].trim();
        $("dkDrFoot").hidden = !cfgFile;
        if (cfgFile) $("dkDrStackPath").textContent = cfgFile;

        for (const b of document.querySelectorAll("#dkDrawerTabs .dk-dr-tab")) {
          b.classList.toggle("active", b.dataset.dtab === st.drawerTab);
        }
        renderDrawerBody(s);
      }
    }

    function renderDrawerBody(s) {
      const st = stateOf(s);
      const isLogs = st.drawerTab === "logs";
      $("dkLogPane").hidden = !isLogs;
      $("dkInspectPane").hidden = isLogs;
      if (isLogs) {
        renderLogBody(s);
        return;
      }
      const pane = $("dkInspectPane");
      const info = st.inspectData;
      if (!info) {
        pane.innerHTML = '<div class="dk-empty"><i class="fa-solid fa-spinner fa-spin"></i> ' + e(L("正在读取详情…", "Inspecting…")) + "</div>";
        return;
      }
      if (st.drawerTab === "config") {
        const envs = (info.Config?.Env || []).map((line) => {
          const i = line.indexOf("=");
          return [i > 0 ? line.slice(0, i) : line, i > 0 ? line.slice(i + 1) : ""];
        });
        pane.innerHTML =
          '<div class="dk-kv-card">' +
            kvRow("ID", (info.Id || "").slice(0, 16)) +
            kvRow(L("镜像", "Image"), info.Config?.Image || "") +
            kvRow(L("重启策略", "Restart"), info.HostConfig?.RestartPolicy?.Name || "no") +
            kvRow(L("启动命令", "Cmd"), (info.Config?.Cmd || []).join(" ") || "—") +
          "</div>" +
          '<div style="font-size:11.5px;color:var(--dk-muted);font-weight:600">' + e(L("环境变量", "Environment")) + " (" + envs.length + ")</div>" +
          '<div class="dk-kv-card">' +
            (envs.length ? envs.map(([k, v]) => kvRow(k, v)).join("") : '<div class="dk-empty">' + e(L("无环境变量", "None")) + "</div>") +
          "</div>";
      } else if (st.drawerTab === "mounts") {
        const mounts = info.Mounts || [];
        if (!mounts.length) {
          pane.innerHTML = '<div class="dk-empty">' + e(L("无挂载卷", "No mounts")) + "</div>";
          return;
        }
        pane.replaceChildren();
        for (const m of mounts) {
          const card = document.createElement("div");
          card.className = "dk-kv-card";
          card.innerHTML =
            kvRow(L("类型", "Type"), (m.Type || "bind") + (m.RW ? " (rw)" : " (ro)")) +
            kvRow(L("宿主机路径", "Source"), m.Source || "—") +
            kvRow(L("容器路径", "Destination"), m.Destination || "—");
          if (m.Source && m.Source.startsWith("/")) {
            const bar = document.createElement("div");
            bar.className = "dk-kv-row";
            const btn = document.createElement("button");
            btn.type = "button";
            btn.className = "dk-btn sftp";
            btn.innerHTML = '<i class="fa-solid fa-folder-open"></i><span>' + e(L("在文件面板打开此目录", "Open in Files")) + "</span>";
            btn.onclick = () => jumpToHostDir(s, m.Source);
            bar.appendChild(btn);
            card.appendChild(bar);
          }
          pane.appendChild(card);
        }
      } else if (st.drawerTab === "network") {
        const nets = info.NetworkSettings?.Networks || {};
        const ports = info.NetworkSettings?.Ports || {};
        let html = '<div class="dk-kv-card">';
        const netKeys = Object.keys(nets);
        if (netKeys.length) {
          for (const nk of netKeys) {
            html += kvRow(nk, nets[nk].IPAddress || L("宿主机/无独立 IP", "host / none"));
          }
        } else {
          html += kvRow(L("网络", "Network"), "—");
        }
        html += '</div><div style="font-size:11.5px;color:var(--dk-muted);font-weight:600">' + e(L("端口映射", "Ports")) + '</div><div class="dk-kv-card">';
        const pKeys = Object.keys(ports);
        if (pKeys.length) {
          for (const pk of pKeys) {
            const binds = ports[pk];
            const val = Array.isArray(binds) && binds.length
              ? binds.map((b) => (b.HostIp || "0.0.0.0") + ":" + b.HostPort).join(", ")
              : L("仅内部暴露", "Internal only");
            html += kvRow(pk, val);
          }
        } else {
          html += kvRow(L("端口", "Ports"), "—");
        }
        html += "</div>";
        pane.innerHTML = html;
      }
    }

    function kvRow(k, v) {
      return '<div class="dk-kv-row"><span class="dk-kv-k">' + e(k) + '</span><span class="dk-kv-v">' + e(v) + "</span></div>";
    }

    function renderLogBody(s) {
      const st = stateOf(s);
      $("dkLogFollow").classList.toggle("active", st.logFollow);
      const box = $("dkLogBody");
      const kw = st.logFilter.trim().toLowerCase();
      const atBottom = box.scrollHeight - box.scrollTop - box.clientHeight < 40;
      const lines = kw ? st.logLines.filter((x) => x.text.toLowerCase().includes(kw)) : st.logLines;
      if (!lines.length) {
        box.innerHTML = '<span style="color:var(--dk-dim)">' + e(st.logStreamId ? L("等待日志输出…", "Waiting for logs…") : L("暂无日志", "No logs")) + "</span>";
        return;
      }
      box.innerHTML = lines
        .map((x) => '<div class="dk-log-line' + (x.isErr ? " err" : "") + (kw ? " hi" : "") + '">' + e(x.text) + "</div>")
        .join("");
      if (st.logFollow && atBottom) box.scrollTop = box.scrollHeight;
    }

    // ---------------- Compose Render ----------------
    function renderComposeView(s) {
      const st = stateOf(s);
      $("dkViewCompose").classList.toggle("stack-editing", Boolean(st.stackEditingMobile && st.selectedStackName));

      const q = ($("dkStackSearch").value || "").trim().toLowerCase();
      const list = $("dkStackList");
      list.replaceChildren();

      const stacks = st.stacks.filter((x) => !q || String(x.Name || "").toLowerCase().includes(q) || String(x.ConfigFiles || "").toLowerCase().includes(q));
      if (!stacks.length) {
        list.innerHTML = '<div class="dk-empty">' + e(L("未发现 Compose 栈，点击右上角「新建 Compose 栈」开始部署", "No Compose stacks found. Click New Compose Stack to deploy.")) + "</div>";
      } else {
        for (const item of stacks) {
          const isUp = /running/i.test(item.Status || "");
          const btn = document.createElement("button");
          btn.type = "button";
          btn.className = "dk-stack-card" + (st.selectedStackName === item.Name ? " active" : "");
          btn.innerHTML =
            '<div class="dk-stack-top">' +
              '<span class="dk-stack-name"><i class="fa-solid fa-layer-group" style="color:var(--dk-cyan)"></i>' + e(item.Name) + "</span>" +
              '<span class="dk-status ' + (isUp ? "up" : "stop") + '">' + e(item.Status || "stopped") + "</span>" +
            "</div>" +
            '<div class="dk-stack-path" title="' + e(item.ConfigFiles || "") + '">' + e(item.ConfigFiles || "—") + "</div>";
          btn.onclick = () => selectStack(s, item, true);
          list.appendChild(btn);
        }
      }
      renderComposeBar(s);
      renderComposeEditor(s);
      renderComposeConsole(s);
    }

    function renderComposeBar(s) {
      const st = stateOf(s);
      const hasStack = Boolean(st.composePath);
      $("dkComposeEmpty").hidden = hasStack;
      $("dkComposeEditorWrap").hidden = !hasStack;
      $("dkComposeExecBox").hidden = !hasStack;
      $("dkComposeBar").hidden = !hasStack;
      if (!hasStack) return;

      $("dkTabYaml").classList.toggle("active", st.composeFileTab === "compose");
      $("dkTabEnv").classList.toggle("active", st.composeFileTab === "env");
      $("dkComposeSave").textContent = st.composeDirty ? L("保存 *", "Save *") : L("保存", "Save");
    }

    function renderComposeEditor(s) {
      const st = stateOf(s);
      const ta = $("dkComposeEditor");
      if (ta.value !== st.composeContent) ta.value = st.composeContent;
      updateComposeGutter();
    }

    function updateComposeGutter() {
      const ta = $("dkComposeEditor");
      const count = Math.max(1, (ta.value || "").split("\n").length);
      let html = "";
      for (let i = 1; i <= count; i++) html += i + "\n";
      $("dkComposeGutter").textContent = html;
    }

    function renderComposeConsole(s) {
      const st = stateOf(s);
      $("dkComposeExecCmd").textContent = st.composeExecCmd || L("就绪（点击上方按钮执行 Compose 操作）", "Ready");
      $("dkComposeExecStatus").textContent = st.composeExecStatus || "";
      const out = $("dkComposeExecOut");
      out.textContent = st.composeExecLines.join("\n") || L("点击「保存并 Up -d」或「Pull & 更新」将在此实时回显执行日志。", "Output will stream here when running compose commands.");
      out.scrollTop = out.scrollHeight;
    }

    // ---------------- Images & Storage Render ----------------
    function renderImagesView(s) {
      const st = stateOf(s);
      const q = st.imageFilter.trim().toLowerCase();
      const tbody = $("dkImagesTbody");
      tbody.replaceChildren();
      const items = st.images.filter((im) => !q || (im.Repository + ":" + im.Tag).toLowerCase().includes(q));
      if (!items.length) {
        tbody.innerHTML = '<tr><td colspan="4" class="dk-empty">' + e(L("暂无镜像", "No images")) + "</td></tr>";
        return;
      }
      for (const im of items) {
        const tr = document.createElement("tr");
        const ref = (im.Repository || "<none>") + ":" + (im.Tag || "<none>");
        tr.innerHTML =
          '<td><strong style="color:#fff">' + e(ref) + '</strong><div class="dk-mono">' + e(String(im.ID || "").slice(0, 12)) + "</div></td>" +
          '<td class="dk-mono">' + e(im.Size || "—") + "</td>" +
          '<td class="dk-mono">' + e(im.CreatedSince || im.CreatedAt || "—") + "</td>" +
          '<td style="text-align:right"><button type="button" class="dk-sq del" title="' + e(L("删除镜像", "Remove image")) + '"><i class="fa-solid fa-trash"></i></button></td>';
        tr.querySelector("button").onclick = async () => {
          if (!(await BSDialog.confirm2(L("删除镜像 ", "Remove image ") + ref + "?"))) return;
          const res = await execCmd(s, "docker rmi " + sq(im.ID || ref));
          if (res.ok) {
            BSDialog.toast(L("已删除镜像", "Image removed"), "success");
            refreshImages(s);
            refreshAll(s, true);
          } else {
            BSDialog.toast((res.stderr || res.error || L("删除失败", "Failed")).trim(), "error");
          }
        };
        tbody.appendChild(tr);
      }
    }

    function renderStorageView(s) {
      const st = stateOf(s);
      const vBody = $("dkVolumesTbody");
      vBody.replaceChildren();
      if (!st.volumes.length) {
        vBody.innerHTML = '<tr><td colspan="3" class="dk-empty">' + e(L("暂无卷", "No volumes")) + "</td></tr>";
      } else {
        for (const v of st.volumes) {
          const tr = document.createElement("tr");
          tr.innerHTML =
            '<td><strong style="color:#fff">' + e(v.Name || "") + "</strong></td>" +
            '<td class="dk-mono">' + e(v.Driver || "local") + "</td>" +
            '<td style="text-align:right"><button type="button" class="dk-sq del" title="' + e(L("删除卷", "Remove volume")) + '"><i class="fa-solid fa-trash"></i></button></td>';
          tr.querySelector("button").onclick = async () => {
            if (!(await BSDialog.confirm2(L("删除卷 ", "Remove volume ") + v.Name + "?"))) return;
            const res = await execCmd(s, "docker volume rm " + sq(v.Name));
            if (res.ok) { BSDialog.toast(L("已删除卷", "Volume removed"), "success"); refreshStorage(s); }
            else BSDialog.toast((res.stderr || res.error || L("删除失败", "Failed")).trim(), "error");
          };
          vBody.appendChild(tr);
        }
      }

      const nBody = $("dkNetworksTbody");
      nBody.replaceChildren();
      if (!st.networks.length) {
        nBody.innerHTML = '<tr><td colspan="3" class="dk-empty">' + e(L("暂无网络", "No networks")) + "</td></tr>";
      } else {
        for (const n of st.networks) {
          const builtin = ["bridge", "host", "none"].includes(n.Name);
          const tr = document.createElement("tr");
          tr.innerHTML =
            '<td><strong style="color:#fff">' + e(n.Name || "") + '</strong><div class="dk-mono">' + e(String(n.ID || "").slice(0, 12)) + "</div></td>" +
            '<td class="dk-mono">' + e((n.Driver || "") + " · " + (n.Scope || "")) + "</td>" +
            '<td style="text-align:right">' + (builtin ? '<span class="dk-mono">' + e(L("内置", "Built-in")) + "</span>" : '<button type="button" class="dk-sq del"><i class="fa-solid fa-trash"></i></button>') + "</td>";
          const b = tr.querySelector("button");
          if (b) {
            b.onclick = async () => {
              if (!(await BSDialog.confirm2(L("删除网络 ", "Remove network ") + n.Name + "?"))) return;
              const res = await execCmd(s, "docker network rm " + sq(n.ID || n.Name));
              if (res.ok) { BSDialog.toast(L("已删除网络", "Network removed"), "success"); refreshStorage(s); }
              else BSDialog.toast((res.stderr || res.error || L("删除失败", "Failed")).trim(), "error");
            };
          }
          nBody.appendChild(tr);
        }
      }
    }

    // ---------------- Auto-Refresh Timer ----------------
    function syncAutoTimer() {
      clearInterval(refreshTimer);
      refreshTimer = null;
      if (!autoRefresh) return;
      refreshTimer = setInterval(() => {
        const s = curSession();
        if (s && s.state === "connected" && s.viewMode === "docker" && !document.hidden) {
          refreshAll(s, true);
        }
      }, 5000);
    }

    // ---------------- DOM Event Wiring ----------------
    for (const b of document.querySelectorAll("#dockerWorkbench .dk-subtab")) {
      b.onclick = () => {
        const s = curSession();
        if (!s) return;
        const st = stateOf(s);
        st.subtab = b.dataset.subtab;
        if (st.subtab === "images" && !st.images.length) refreshImages(s);
        if (st.subtab === "storage" && !st.volumes.length) refreshStorage(s);
        if (st.subtab === "compose" && !st.selectedStackName && st.stacks.length && !matchMedia("(max-width:640px)").matches) {
          selectStack(s, st.stacks[0], false);
          return;
        }
        render(s);
      };
    }

    $("dkRefreshBtn").onclick = () => {
      const s = curSession();
      if (!s) return;
      refreshAll(s, false);
      const st = stateOf(s);
      if (st.subtab === "images") refreshImages(s);
      if (st.subtab === "storage") refreshStorage(s);
    };
    $("dkAutoRefreshBtn").onclick = () => {
      autoRefresh = !autoRefresh;
      syncAutoTimer();
      const s = curSession();
      if (s) render(s);
    };
    $("dkPruneBtn").onclick = () => { const s = curSession(); if (s) pruneCache(s); };
    $("dkNewComposeBtn").onclick = () => { const s = curSession(); if (s) promptNewComposeStack(s); };
    $("dkBannerRetry").onclick = () => { const s = curSession(); if (s) refreshAll(s, false); };

    $("dkContainerSearch").oninput = (ev) => {
      const s = curSession();
      if (!s) return;
      stateOf(s).filter = ev.target.value;
      renderContainersView(s);
    };
    for (const b of document.querySelectorAll("#dkStatusSeg button")) {
      b.onclick = () => {
        const s = curSession();
        if (!s) return;
        stateOf(s).statusFilter = b.dataset.sf;
        renderContainersView(s);
      };
    }
    $("dkGroupToggle").onclick = () => {
      const s = curSession();
      if (!s) return;
      const st = stateOf(s);
      st.groupByStack = !st.groupByStack;
      renderContainersView(s);
    };

    // Drawer controls
    $("dkDrawerClose").onclick = () => { const s = curSession(); if (s) closeContainerDrawer(s); };
    $("dkDrExec").onclick = () => {
      const s = curSession();
      if (!s) return;
      const c = stateOf(s).containers.find((x) => x.id === stateOf(s).selectedContainerId);
      if (c) openContainerExec(s, c);
    };
    $("dkDrMount").onclick = () => {
      const s = curSession();
      if (!s) return;
      const st = stateOf(s);
      const bind = (st.inspectData?.Mounts || []).find((m) => m.Source && m.Source.startsWith("/"));
      const c = st.containers.find((x) => x.id === st.selectedContainerId);
      const target = bind?.Source || c?.workDir;
      if (target) jumpToHostDir(s, target);
      else BSDialog.toast(L("该容器未绑定宿主机目录", "No host bind mount found"), "info");
    };
    $("dkDrRestart").onclick = () => {
      const s = curSession();
      if (!s) return;
      const c = stateOf(s).containers.find((x) => x.id === stateOf(s).selectedContainerId);
      if (c) containerAction(s, c, "restart");
    };
    $("dkDrStartStop").onclick = () => {
      const s = curSession();
      if (!s) return;
      const c = stateOf(s).containers.find((x) => x.id === stateOf(s).selectedContainerId);
      if (c) containerAction(s, c, c.running ? "stop" : "start");
    };
    $("dkDrRemove").onclick = () => {
      const s = curSession();
      if (!s) return;
      const c = stateOf(s).containers.find((x) => x.id === stateOf(s).selectedContainerId);
      if (c) containerAction(s, c, "rm");
    };
    $("dkDrEditCompose").onclick = () => {
      const s = curSession();
      if (!s) return;
      const st = stateOf(s);
      const c = st.containers.find((x) => x.id === st.selectedContainerId);
      if (!c) return;
      const cfg = String(c.configFile || "").split(",")[0].trim();
      const stack = st.stacks.find((x) => x.Name === c.stack) || { Name: c.stack || "stack", ConfigFiles: cfg, Status: "running" };
      st.subtab = "compose";
      selectStack(s, stack, true);
    };
    for (const b of document.querySelectorAll("#dkDrawerTabs .dk-dr-tab")) {
      b.onclick = () => {
        const s = curSession();
        if (!s) return;
        const st = stateOf(s);
        st.drawerTab = b.dataset.dtab;
        const c = st.containers.find((x) => x.id === st.selectedContainerId);
        if (st.drawerTab === "logs" && c && !st.logStreamId) startLogStream(s, c);
        render(s);
      };
    }
    $("dkLogSearch").oninput = (ev) => {
      const s = curSession();
      if (!s) return;
      stateOf(s).logFilter = ev.target.value;
      renderLogBody(s);
    };
    $("dkLogFollow").onclick = () => {
      const s = curSession();
      if (!s) return;
      const st = stateOf(s);
      st.logFollow = !st.logFollow;
      const c = st.containers.find((x) => x.id === st.selectedContainerId);
      if (c) startLogStream(s, c);
      renderLogBody(s);
    };
    $("dkLogTail").onchange = (ev) => {
      const s = curSession();
      if (!s) return;
      const st = stateOf(s);
      st.logTail = Number(ev.target.value) || 200;
      const c = st.containers.find((x) => x.id === st.selectedContainerId);
      if (c) startLogStream(s, c);
    };
    $("dkLogCopy").onclick = () => {
      const s = curSession();
      if (!s) return;
      const text = stateOf(s).logLines.map((x) => x.text).join("\n");
      navigator.clipboard?.writeText(text).then(() => BSDialog.toast(L("日志已复制", "Logs copied"), "success")).catch(() => {});
    };

    // Compose controls
    $("dkStackSearch").oninput = () => { const s = curSession(); if (s) renderComposeView(s); };
    $("dkComposeBack").onclick = () => {
      const s = curSession();
      if (!s) return;
      stateOf(s).stackEditingMobile = false;
      renderComposeView(s);
    };
    $("dkTabYaml").onclick = () => { const s = curSession(); if (s) loadComposeFile(s, "compose"); };
    $("dkTabEnv").onclick = () => { const s = curSession(); if (s) loadComposeFile(s, "env"); };
    $("dkOpenStackDir").onclick = () => {
      const s = curSession();
      if (s && stateOf(s).composeDir) jumpToHostDir(s, stateOf(s).composeDir);
    };
    $("dkComposeEditor").oninput = () => {
      const s = curSession();
      if (!s) return;
      const st = stateOf(s);
      st.composeContent = $("dkComposeEditor").value;
      st.composeDirty = st.composeContent !== st.composeOrig;
      updateComposeGutter();
      renderComposeBar(s);
    };
    $("dkComposeEditor").onscroll = () => {
      $("dkComposeGutter").scrollTop = $("dkComposeEditor").scrollTop;
    };
    $("dkComposeSave").onclick = () => { const s = curSession(); if (s) saveComposeFile(s, false); };
    $("dkComposeUp").onclick = () => { const s = curSession(); if (s) runComposeOp(s, "up"); };
    $("dkComposePull").onclick = () => { const s = curSession(); if (s) runComposeOp(s, "pull"); };
    $("dkComposeRestart").onclick = () => { const s = curSession(); if (s) runComposeOp(s, "restart"); };
    $("dkComposeDown").onclick = () => { const s = curSession(); if (s) runComposeOp(s, "down"); };

    // Images controls
    $("dkImageSearch").oninput = (ev) => {
      const s = curSession();
      if (!s) return;
      stateOf(s).imageFilter = ev.target.value;
      renderImagesView(s);
    };
    $("dkPullImageBtn").onclick = () => { const s = curSession(); if (s) promptPullImage(s); };

    return {
      handleWorkerMessage,
      onShow(s) {
        if (!s || s.cfg.protocol === "webdav") return;
        const st = stateOf(s);
        render(s);
        if (!st.loaded && s.state === "connected") {
          refreshAll(s, false);
        }
        syncAutoTimer();
      },
      onHide(s) {
        if (s) stopLogStream(s);
      },
      onSessionClosed(s) {
        if (!s) return;
        const st = sessionState.get(s.id);
        if (st) {
          stopStream(s, st.logStreamId);
          stopStream(s, st.composeStreamId);
          sessionState.delete(s.id);
        }
      },
      onConnected(s) {
        if (s && curSession()?.id === s.id && s.viewMode === "docker") {
          refreshAll(s, false);
        }
      },
      onLanguageChange() {
        const s = curSession();
        if (s && s.viewMode === "docker") render(s);
      },
    };
  };
})();
