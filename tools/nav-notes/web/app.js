(function () {
  'use strict';

  const DATA_KEY = 'bookstark_nav_notes_v1';
  const DEVICE_ENV_KEY = 'bookstark_nav_notes_device_env';
  const DEVICE_THEME_KEY = 'bookstark_nav_notes_theme';
  const DEVICE_VIEW_PREFS_KEY = 'bookstark_nav_notes_view_prefs_v1';
  const WORKSPACE_SNAPSHOT_PATH = 'backups/nav-notes-snapshot.json';

  const TONES = ['blue', 'green', 'purple', 'amber', 'pink', 'cyan'];
  const SWATCH_HEX = {
    blue: '#2563eb',
    green: '#059669',
    purple: '#7c3aed',
    amber: '#d97706',
    pink: '#db2777',
    cyan: '#0891b2'
  };
  const PRESET_TAGS = ['服务器', '模型', '下载', '定时任务', '临时', '备忘'];

  const FA_ICONS = [
    { id: 'globe', kw: 'globe web 网站 网页 公网' },
    { id: 'server', kw: 'server 主机 服务器 vps' },
    { id: 'cloud', kw: 'cloud 云 网盘 服务' },
    { id: 'database', kw: 'database db 数据库 sql redis' },
    { id: 'terminal', kw: 'terminal ssh 终端 命令行' },
    { id: 'code', kw: 'code 代码 开发 git github' },
    { id: 'microchip', kw: 'microchip gpu 芯片 硬件 显卡' },
    { id: 'brain', kw: 'brain ai 模型 llm 人工智能' },
    { id: 'robot', kw: 'robot bot 机器人 ai 对话' },
    { id: 'rocket', kw: 'rocket 火箭 启动 加速 部署' },
    { id: 'bolt', kw: 'bolt 闪电 效率 快捷' },
    { id: 'compass', kw: 'compass 指南针 导航 星图' },
    { id: 'layer-group', kw: 'layer 架构 平台 容器' },
    { id: 'cube', kw: 'cube docker 容器 工具' },
    { id: 'cubes', kw: 'cubes 集群 微服务' },
    { id: 'boxes-stacked', kw: 'boxes 资源 仓库 归档' },
    { id: 'hard-drive', kw: 'drive nas 硬盘 存储 磁盘' },
    { id: 'network-wired', kw: 'network lan 内网 路由 拓扑' },
    { id: 'wifi', kw: 'wifi 无线 网络 路由' },
    { id: 'satellite-dish', kw: 'satellite 信号 雷达 代理' },
    { id: 'shield-halved', kw: 'shield 安全 密码 防火墙' },
    { id: 'key', kw: 'key 密钥 token 凭据' },
    { id: 'lock', kw: 'lock 加密 隐私 锁' },
    { id: 'download', kw: 'download 下载 bt pt' },
    { id: 'upload', kw: 'upload 上传 同步 备份' },
    { id: 'folder-open', kw: 'folder 目录 文件 归档' },
    { id: 'file-code', kw: 'file 脚本 配置 文档' },
    { id: 'book', kw: 'book 书 文档 笔记 wiki' },
    { id: 'bookmark', kw: 'bookmark 书签 收藏' },
    { id: 'star', kw: 'star 收藏 常用 星标' },
    { id: 'fire', kw: 'fire 热门 常用 主力' },
    { id: 'wand-magic-sparkles', kw: 'magic comfyui 绘画 生成 ai' },
    { id: 'chart-line', kw: 'chart 股票 行情 监控 指标' },
    { id: 'chart-pie', kw: 'pie 报表 资产 财务' },
    { id: 'coins', kw: 'coins 金融 基金 理财' },
    { id: 'wallet', kw: 'wallet 钱包 账单 续费' },
    { id: 'film', kw: 'film 视频 影视 影音' },
    { id: 'music', kw: 'music 音乐 音频 播客' },
    { id: 'image', kw: 'image 图片 相册 图像' },
    { id: 'camera', kw: 'camera 摄影 截图 监控' },
    { id: 'gamepad', kw: 'gamepad 游戏 娱乐 掌机' },
    { id: 'house', kw: 'house 家庭 内网 homelab' },
    { id: 'building', kw: 'building 公司 办公 生产' },
    { id: 'wrench', kw: 'wrench 运维 调试 工具' },
    { id: 'gear', kw: 'gear 设置 后台 管理 控制台' },
    { id: 'sliders', kw: 'sliders 参数 面板 控制' },
    { id: 'paper-plane', kw: 'plane 传输 邮件 消息 推送' },
    { id: 'link', kw: 'link 链接 入口 跳转' }
  ];
  const FA_ICON_SET = new Set(FA_ICONS.map((x) => x.id));

  function hashSeed(str) {
    let h = 2166136261;
    const s = String(str || '');
    for (let i = 0; i < s.length; i++) {
      h ^= s.charCodeAt(i);
      h = Math.imul(h, 16777619) >>> 0;
    }
    return h >>> 0;
  }

  function hashFaIcon(seed) {
    return FA_ICONS[hashSeed(seed) % FA_ICONS.length].id;
  }

  function resolveIconMeta(link, resolvedUrl) {
    let hostSeed = '';
    try { hostSeed = new URL(resolvedUrl || link.defaultUrl || '').hostname; } catch (_) {}
    const seed = hostSeed || link.title || link.id || 'site';
    const faIcon = (link.icon && FA_ICON_SET.has(link.icon)) ? link.icon : hashFaIcon(seed);
    const mode = link.iconMode === 'icon' ? 'icon' : 'auto';
    const favicons = [];
    if (mode === 'auto' && navigator.onLine !== false) {
      const seen = new Set();
      const push = (u) => { if (u && !seen.has(u)) { seen.add(u); favicons.push(u); } };
      push(safeUrl(link.faviconUrl));
      for (const candidate of [resolvedUrl, link.defaultUrl]) {
        const clean = safeUrl(candidate);
        if (!clean) continue;
        try { push(new URL('/favicon.ico', clean).href); } catch (_) {}
      }
    }
    return { mode, faIcon, favicons };
  }

  function hydrateFavicons(root) {
    if (!root) return;
    root.querySelectorAll('.u-ico[data-favicons]').forEach((box) => {
      let list = [];
      try { list = JSON.parse(box.dataset.favicons || '[]'); } catch (_) {}
      if (!list.length) return;
      let idx = 0;
      const tryNext = () => {
        if (idx >= list.length || !box.isConnected) return;
        const src = list[idx++];
        const img = document.createElement('img');
        img.className = 'u-favicon';
        img.alt = '';
        img.decoding = 'async';
        img.referrerPolicy = 'no-referrer';
        img.onload = () => {
          if (!box.isConnected) return;
          if (img.naturalWidth > 0 && img.naturalHeight > 0) {
            box.querySelectorAll('.u-favicon').forEach((n) => n.remove());
            box.appendChild(img);
            box.classList.add('has-favicon');
          } else {
            tryNext();
          }
        };
        img.onerror = tryNext;
        img.src = src;
      };
      tryNext();
    });
  }

  const $ = (id) => document.getElementById(id);

  function genId() {
    if (typeof crypto !== 'undefined' && crypto.randomUUID) return crypto.randomUUID().slice(0, 12);
    return 'id_' + Date.now().toString(36) + '_' + Math.random().toString(36).slice(2, 7);
  }

  function esc(str) {
    return String(str ?? '')
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

  function safeUrl(raw) {
    const val = String(raw || '').trim();
    if (!val) return '';
    try {
      const u = new URL(val);
      if (u.protocol === 'http:' || u.protocol === 'https:') return u.href;
    } catch (_) {}
    return '';
  }

  function displayHost(raw) {
    try {
      const u = new URL(raw);
      return u.host + (u.pathname && u.pathname !== '/' ? u.pathname : '');
    } catch (_) {
      return raw || '';
    }
  }

  function tagTone(tag) {
    const fixed = {
      '服务器': 'blue',
      'VPS': 'blue',
      '内网IP': 'blue',
      '模型': 'purple',
      'AI': 'purple',
      '下载': 'green',
      'NAS': 'green',
      '定时任务': 'amber',
      '临时': 'amber',
      '备忘': 'cyan'
    };
    if (fixed[tag]) return fixed[tag];
    let h = 0;
    for (let i = 0; i < tag.length; i++) h = (h * 31 + tag.charCodeAt(i)) >>> 0;
    return TONES[h % TONES.length];
  }

  function parseTags(content) {
    const re = /(?:^|[\s,，;；(（\[【])#([\u4e00-\u9fa5A-Za-z0-9_./-]{1,24})/g;
    const found = [];
    const seen = new Set();
    let m;
    while ((m = re.exec(String(content || ''))) !== null) {
      const name = m[1].replace(/[.,;:!?。，；：！？]+$/, '');
      if (name && !seen.has(name)) {
        seen.add(name);
        found.push(name);
      }
    }
    return found;
  }

  function formatTime(ts) {
    const d = new Date(ts || Date.now());
    const now = new Date();
    const pad = (n) => String(n).padStart(2, '0');
    const sameDay = d.getFullYear() === now.getFullYear() && d.getMonth() === now.getMonth() && d.getDate() === now.getDate();
    if (sameDay) return '今天 ' + pad(d.getHours()) + ':' + pad(d.getMinutes());
    return pad(d.getMonth() + 1) + '-' + pad(d.getDate()) + ' ' + pad(d.getHours()) + ':' + pad(d.getMinutes());
  }

  function defaultData() {
    const now = Date.now();
    return {
      schema: 1,
      envs: [
        { id: 'public', name: '公网', color: 'blue' },
        { id: 'lan', name: '内网', color: 'green' },
        { id: 'test', name: '测试', color: 'amber' }
      ],
      defaultEnv: 'public',
      links: [
        {
          id: genId(),
          title: 'BookStark 云市场',
          group: '自托管',
          icon: '',
          iconMode: 'auto',
          faviconUrl: '',
          color: 'blue',
          defaultUrl: 'https://cloud.vs2010wy.top',
          envUrls: { public: 'https://cloud.vs2010wy.top', lan: 'http://192.168.10.10:8089' }
        },
        {
          id: genId(),
          title: 'ComfyUI 出图台',
          group: 'AI / 模型',
          icon: 'wand-magic-sparkles',
          iconMode: 'auto',
          faviconUrl: '',
          color: 'purple',
          defaultUrl: 'http://192.168.10.25:8188',
          envUrls: { public: 'https://comfy.example.com', lan: 'http://192.168.10.25:8188', test: 'http://100.64.0.25:8188' }
        },
        {
          id: genId(),
          title: 'OpenWebUI',
          group: 'AI / 模型',
          icon: 'robot',
          iconMode: 'auto',
          faviconUrl: '',
          color: 'green',
          defaultUrl: 'http://192.168.10.25:3000',
          envUrls: { lan: 'http://192.168.10.25:3000', public: 'https://ai.example.com' }
        },
        {
          id: genId(),
          title: 'GitHub',
          group: '常用',
          icon: '',
          iconMode: 'auto',
          faviconUrl: '',
          color: 'cyan',
          defaultUrl: 'https://github.com',
          envUrls: {}
        },
        {
          id: genId(),
          title: 'HF-Mirror 模型站',
          group: 'AI / 模型',
          icon: '',
          iconMode: 'auto',
          faviconUrl: '',
          color: 'pink',
          defaultUrl: 'https://hf-mirror.com',
          envUrls: {}
        }
      ],
      notes: [
        {
          id: genId(),
          content: '#服务器 #VPS 香港主站（示例，可直接编辑或删除）\n4C/8G/120G，跑 BookStark 与代理服务，数据目录在 /root/bookstark\nssh root@cloud.vs2010wy.top',
          pinned: true,
          archived: false,
          createdAt: now - 3600000 * 6,
          updatedAt: now - 3600000 * 6
        },
        {
          id: genId(),
          content: '#模型 #4090主机 本地大模型与 ComfyUI 权重目录（示例）\nQwen2.5-Coder-32B (19.8G)、Flux.1-Dev 均存放在 NVMe 数据盘：\n/data/models/llm/qwen2.5-coder-32b/',
          pinned: true,
          archived: false,
          createdAt: now - 3600000 * 4,
          updatedAt: now - 3600000 * 4
        },
        {
          id: genId(),
          content: '#定时任务 #备份 每日凌晨 3 点自动备份数据库到 NAS\n0 3 * * * /root/scripts/backup_bookstark.sh',
          pinned: false,
          archived: false,
          createdAt: now - 3600000 * 2,
          updatedAt: now - 3600000 * 2
        },
        {
          id: genId(),
          content: '#下载 #临时 常用系统镜像与离线包归档位置\n\\\\192.168.10.10\\downloads\\iso-and-tools',
          pinned: false,
          archived: false,
          createdAt: now - 600000,
          updatedAt: now - 600000
        }
      ]
    };
  }

  function readDevicePref(key, fallback) {
    try {
      const v = sessionStorage.getItem(key);
      if (v) return v;
    } catch (_) {}
    try {
      const v = localStorage.getItem(key);
      if (v) return v;
    } catch (_) {}
    return fallback;
  }

  function writeDevicePref(key, val) {
    try { sessionStorage.setItem(key, val); return; } catch (_) {}
    try { localStorage.setItem(key, val); } catch (_) {}
  }

  function loadData() {
    try {
      const raw = localStorage.getItem(DATA_KEY);
      if (raw) {
        const parsed = JSON.parse(raw);
        if (parsed && Array.isArray(parsed.envs) && Array.isArray(parsed.links) && Array.isArray(parsed.notes)) {
          if (!parsed.envs.length) parsed.envs = defaultData().envs;
          return parsed;
        }
      }
    } catch (_) {}
    return defaultData();
  }

  function loadViewPrefs() {
    const fallback = { showNav: true, showNotes: true, defaultView: 'last', lastView: 'nav' };
    try {
      const raw = localStorage.getItem(DEVICE_VIEW_PREFS_KEY);
      if (raw) {
        const p = JSON.parse(raw);
        if (p && typeof p === 'object') {
          const showNav = p.showNav !== false;
          const showNotes = p.showNotes !== false;
          const defaultView = ['last', 'nav', 'notes', 'all'].includes(p.defaultView) ? p.defaultView : 'last';
          const lastView = ['nav', 'notes', 'all'].includes(p.lastView) ? p.lastView : 'nav';
          return {
            showNav: showNav || !showNotes ? showNav : true,
            showNotes: showNotes || !showNav ? showNotes : true,
            defaultView,
            lastView
          };
        }
      }
    } catch (_) {}
    return fallback;
  }

  function saveViewPrefs() {
    try { localStorage.setItem(DEVICE_VIEW_PREFS_KEY, JSON.stringify(viewPrefs)); } catch (_) {}
  }

  function resolveInitialView(prefs) {
    if (prefs.showNav && !prefs.showNotes) return 'nav';
    if (!prefs.showNav && prefs.showNotes) return 'notes';
    return prefs.defaultView === 'last' ? prefs.lastView : prefs.defaultView;
  }

  // App State
  let data = loadData();
  let viewPrefs = loadViewPrefs();
  let activeView = resolveInitialView(viewPrefs); // 'nav' | 'notes' | 'all'
  let activeEnv = readDevicePref(DEVICE_ENV_KEY, data.defaultEnv || (data.envs[0] && data.envs[0].id) || 'public');
  if (!data.envs.some((e) => e.id === activeEnv)) activeEnv = data.envs[0].id;
  let activeGroup = 'ALL';
  let activeTag = 'ALL'; // 'ALL' | 'PINNED' | 'ARCHIVED' | '<tagName>'
  let searchQuery = '';
  let lastUrlMatchCount = 0;
  let lastMemoMatchCount = 0;
  let boardCollapsed = false;
  let editingNoteId = null;
  let toastTimer = 0;

  function showToast(msg) {
    const el = $('toast');
    el.textContent = msg;
    el.hidden = false;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => { el.hidden = true; }, 2200);
  }

  function saveData(label) {
    try {
      localStorage.setItem(DATA_KEY, JSON.stringify(data));
      const badge = $('syncStatus');
      if (badge) {
        badge.innerHTML = '<i class="fa-solid fa-circle-check"></i> ' + esc(label || '已自动保存');
      }
    } catch (err) {
      showToast('保存失败：存储空间可能已满');
    }
  }

  function applyTheme(theme) {
    const dark = theme === 'dark';
    document.documentElement.setAttribute('data-theme', dark ? 'dark' : 'light');
    $('themeLightBtn')?.classList.toggle('active', !dark);
    $('themeDarkBtn')?.classList.toggle('active', dark);
    writeDevicePref(DEVICE_THEME_KEY, dark ? 'dark' : 'light');
  }

  function resolveLink(link) {
    const envUrls = link.envUrls || {};
    const specific = safeUrl(envUrls[activeEnv]);
    const envObj = data.envs.find((e) => e.id === activeEnv);
    if (specific) {
      return { url: specific, matched: true, envName: envObj ? envObj.name : activeEnv, envColor: envObj ? envObj.color : 'blue' };
    }
    const fallback = safeUrl(link.defaultUrl) || Object.values(envUrls).map(safeUrl).find(Boolean) || '#';
    return { url: fallback, matched: false, envName: '通用', envColor: 'slate' };
  }

  function listLinkEndpoints(link) {
    const items = [];
    const seen = new Set();
    const envUrls = link.envUrls || {};
    for (const env of data.envs) {
      const u = safeUrl(envUrls[env.id]);
      if (u) {
        items.push({ id: env.id, name: env.name, color: env.color, url: u, current: env.id === activeEnv });
        seen.add(u);
      }
    }
    const def = safeUrl(link.defaultUrl);
    if (def && !seen.has(def)) {
      items.push({ id: '__default', name: '默认 / 通用', color: 'slate', url: def, current: !items.some((x) => x.current) });
    }
    return items;
  }

  function copyText(text, btn) {
    const done = () => {
      if (btn) {
        const orig = btn.textContent;
        btn.textContent = '已复制';
        btn.classList.add('copied');
        setTimeout(() => { btn.textContent = orig; btn.classList.remove('copied'); }, 1500);
      }
      showToast('已复制到剪贴板');
    };
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).then(done).catch(() => fallbackCopy(text, done));
    } else {
      fallbackCopy(text, done);
    }
  }

  function fallbackCopy(text, cb) {
    const ta = document.createElement('textarea');
    ta.value = text;
    ta.style.position = 'fixed';
    ta.style.opacity = '0';
    document.body.appendChild(ta);
    ta.select();
    try { document.execCommand('copy'); } catch (_) {}
    ta.remove();
    cb();
  }

  // Render URL Board
  function renderEnvBar() {
    const host = $('envBar');
    host.innerHTML = data.envs.map((env) => {
      const active = env.id === activeEnv;
      return '<button type="button" class="env-pill' + (active ? ' active' : '') + '" role="radio" aria-checked="' + active + '" data-env-id="' + esc(env.id) + '">'
        + '<span class="dot dot-' + esc(env.color || 'blue') + '"></span>'
        + '<span>' + esc(env.name) + '</span>'
        + '</button>';
    }).join('') + '<button type="button" class="env-pill env-manage-btn" id="openEnvManageBtn" title="管理自定义环境" aria-label="管理环境"><i class="fa-solid fa-gear"></i></button>';
  }

  function renderGroupTabs() {
    const groups = [];
    const seen = new Set();
    for (const l of data.links) {
      const g = (l.group || '常用').trim() || '常用';
      if (!seen.has(g)) { seen.add(g); groups.push(g); }
    }
    if (activeGroup !== 'ALL' && !seen.has(activeGroup)) activeGroup = 'ALL';
    const host = $('groupTabs');
    host.innerHTML =
      '<button type="button" class="group-tab' + (activeGroup === 'ALL' ? ' active' : '') + '" data-group="ALL">全部 (' + data.links.length + ')</button>' +
      groups.map((g) => '<button type="button" class="group-tab' + (activeGroup === g ? ' active' : '') + '" data-group="' + esc(g) + '">' + esc(g) + '</button>').join('');

    const dl = $('groupSuggestions');
    if (dl) {
      const defaults = ['常用', '自托管', 'AI / 模型', '开发', '金融', '下载'];
      const merged = Array.from(new Set([...defaults, ...groups]));
      dl.innerHTML = merged.map((g) => '<option value="' + esc(g) + '"></option>').join('');
    }
  }

  function renderUrlGrid() {
    const q = searchQuery.trim().toLowerCase();
    const list = data.links.filter((link) => {
      const g = (link.group || '常用').trim() || '常用';
      if (activeGroup !== 'ALL' && g !== activeGroup) return false;
      if (!q) return true;
      const allUrls = [link.defaultUrl || '', ...Object.values(link.envUrls || {})].join(' ').toLowerCase();
      return (link.title || '').toLowerCase().includes(q) || g.toLowerCase().includes(q) || allUrls.includes(q);
    });
    lastUrlMatchCount = list.length;

    const grid = $('urlGrid');
    if (!list.length) {
      grid.innerHTML = '<div class="empty-state">' + (data.links.length ? '当前筛选下没有匹配的网址' : '还没有常用网址，点右上角「添加网址」录入吧') + '</div>';
      return;
    }

    grid.innerHTML = list.map((link) => {
      const res = resolveLink(link);
      const endpoints = listLinkEndpoints(link);
      const multi = endpoints.length > 1;
      const tone = TONES.includes(link.color) ? link.color : 'blue';
      const iconMeta = resolveIconMeta(link, res.url);
      const envTone = res.matched ? res.envColor : 'slate';
      const chipLabel = multi ? (res.envName + ' ▾') : res.envName;
      const favAttr = iconMeta.favicons.length ? ' data-favicons="' + esc(JSON.stringify(iconMeta.favicons)) + '"' : '';

      return '<article class="url-tile' + (res.matched ? ' env-matched tone-' + esc(envTone) : '') + '" data-link-id="' + esc(link.id) + '">'
        + '<a class="url-tile-link" href="' + esc(res.url) + '" target="_blank" rel="noopener noreferrer" title="' + esc(link.title + ' · ' + res.url) + '">'
        + '<span class="u-ico tone-' + esc(tone) + '"' + favAttr + '><i class="fa-solid fa-' + esc(iconMeta.faIcon) + '" aria-hidden="true"></i></span>'
        + '<span class="u-txt"><strong>' + esc(link.title) + '</strong><span class="u-host">' + esc(displayHost(res.url)) + '</span></span>'
        + '</a>'
        + '<div class="u-right">'
        + (multi
            ? '<button type="button" class="env-chip clickable tone-' + esc(envTone) + '" data-open-env-pop="' + esc(link.id) + '" title="点击直开其他环境">' + esc(chipLabel) + '</button>'
            : '<span class="env-chip tone-' + esc(envTone) + '">' + esc(chipLabel) + '</span>')
        + '<button type="button" class="u-edit-btn" data-edit-link="' + esc(link.id) + '" title="编辑网址" aria-label="编辑网址"><i class="fa-solid fa-pen"></i></button>'
        + '</div>'
        + '</article>';
    }).join('');
    hydrateFavicons(grid);
  }

  // Render Tag Rail + Quick Tags
  function computeTagStats() {
    const counts = new Map();
    let totalActive = 0;
    let pinnedCount = 0;
    let archivedCount = 0;
    for (const n of data.notes) {
      if (n.archived) { archivedCount++; continue; }
      totalActive++;
      if (n.pinned) pinnedCount++;
      for (const tg of parseTags(n.content)) {
        counts.set(tg, (counts.get(tg) || 0) + 1);
      }
    }
    const sortedTags = Array.from(counts.entries()).sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0], 'zh-CN'));
    return { totalActive, pinnedCount, archivedCount, sortedTags };
  }

  function renderTagRail() {
    const { totalActive, pinnedCount, archivedCount, sortedTags } = computeTagStats();
    const host = $('tagRail');
    const item = (key, label, count, dotTone, iconHtml) =>
      '<button type="button" class="tag-btn' + (activeTag === key ? ' active' : '') + '" data-filter-tag="' + esc(key) + '">'
      + '<span class="tag-btn-left">'
      + (iconHtml || '<span class="tag-dot dot-' + esc(dotTone || 'blue') + '"></span>')
      + '<span class="tag-btn-label">' + esc(label) + '</span>'
      + '</span>'
      + '<span class="tag-count">' + count + '</span>'
      + '</button>';

    const tagButtons = sortedTags.map(([tg, c]) => item(tg, '#' + tg, c, tagTone(tg))).join('');
    host.innerHTML =
      '<div class="rail-section-label">按标签筛选</div>'
      + '<div class="tag-rail-list">'
      + item('ALL', '全部记录', totalActive, 'blue')
      + tagButtons
      + item('PINNED', '已置顶', pinnedCount, '', '<i class="fa-solid fa-thumbtack fa-xs"></i>')
      + item('ARCHIVED', '已归档', archivedCount, '', '<i class="fa-solid fa-box-archive fa-xs"></i>')
      + '</div>';

    // Quick tags in composer
    const mergedQuick = Array.from(new Set([...PRESET_TAGS, ...sortedTags.slice(0, 6).map(([tg]) => tg)])).slice(0, 8);
    $('quickTagChips').innerHTML = mergedQuick.map((tg) =>
      '<button type="button" class="qtag" data-insert-tag="' + esc(tg) + '">+ #' + esc(tg) + '</button>'
    ).join('');
  }

  // Smart Note Body Rendering (paths, commands, code blocks, inline tags, links)
  function looksLikeCommandOrPath(line) {
    const t = line.trim();
    if (!t || t.length > 400) return false;
    if (/^(\/[\w.@+-]|~\/|\\\\[A-Za-z0-9_.-]+\\|[A-Za-z]:\\)/.test(t)) return true;
    if (/^(ssh|scp|rsync|docker|docker-compose|curl|wget|git|ollama|kubectl|systemctl|nginx|caddy|python3?|pip3?|npm|pnpm|go|make|tar|chmod|chown|find|grep|tmux|screen|vllm)\s+/i.test(t)) return true;
    if (/^([*\d/, -]+\s+){4}[*\d/,-]+\s+\S+/.test(t)) return true; // cron line
    if (/^[a-zA-Z0-9_.-]+:\/[\w./@-]+/.test(t)) return true; // host:/path
    return false;
  }

  function renderRichTextLine(line) {
    // Handle inline backticks, URLs, and #tags safely
    const parts = line.split(/(`[^`\n]+`)/g);
    let out = '';
    for (const part of parts) {
      if (part.startsWith('`') && part.endsWith('`') && part.length > 2) {
        const inner = part.slice(1, -1);
        out += '<span class="code-chip-row" style="margin:4px 0;"><code>' + esc(inner) + '</code><button type="button" class="copy-btn" data-copy="' + esc(inner) + '">复制</button></span>';
      } else {
        // Escape first, then linkify URLs & highlight #tags
        let safe = esc(part);
        safe = safe.replace(/(https?:\/\/[^\s<>"]+)/g, '<a class="memo-ext-link" href="$1" target="_blank" rel="noopener noreferrer">$1</a>');
        safe = safe.replace(/(^|[\s,，;；(（\[【])#([\u4e00-\u9fa5A-Za-z0-9_./-]{1,24})/g, '$1<span class="memo-inline-tag" data-filter-tag="$2">#$2</span>');
        out += '<div class="memo-line">' + safe + '</div>';
      }
    }
    return out;
  }

  function renderNoteBody(content) {
    const raw = String(content || '');
    // Split fenced code blocks ```...```
    const blocks = raw.split(/(```[\s\S]*?```)/g);
    let html = '';
    for (const blk of blocks) {
      if (blk.startsWith('```') && blk.endsWith('```') && blk.length >= 6) {
        const code = blk.slice(3, -3).replace(/^[a-zA-Z0-9_-]*\n/, '').trim();
        if (code) {
          html += '<div class="code-chip-row"><code>' + esc(code) + '</code><button type="button" class="copy-btn" data-copy="' + esc(code) + '">复制</button></div>';
        }
        continue;
      }
      const lines = blk.split(/\r?\n/);
      for (const line of lines) {
        if (!line.trim()) continue;
        if (looksLikeCommandOrPath(line)) {
          const clean = line.trim();
          html += '<div class="code-chip-row"><code>' + esc(clean) + '</code><button type="button" class="copy-btn" data-copy="' + esc(clean) + '">复制</button></div>';
        } else {
          html += renderRichTextLine(line);
        }
      }
    }
    return html || '<div class="memo-line" style="color:var(--text-3)">（空记录）</div>';
  }

  function renderMemoGrid() {
    const q = searchQuery.trim().toLowerCase();
    const filtered = data.notes
      .filter((note) => {
        if (activeTag === 'ARCHIVED') {
          if (!note.archived) return false;
        } else {
          if (note.archived) return false;
          if (activeTag === 'PINNED' && !note.pinned) return false;
          if (activeTag !== 'ALL' && activeTag !== 'PINNED') {
            if (!parseTags(note.content).includes(activeTag)) return false;
          }
        }
        if (!q) return true;
        return (note.content || '').toLowerCase().includes(q);
      })
      .sort((a, b) => Number(!!b.pinned) - Number(!!a.pinned) || (b.updatedAt || 0) - (a.updatedAt || 0));
    lastMemoMatchCount = filtered.length;

    const filterBar = $('activeFilterBar');
    if (activeTag !== 'ALL' || q) {
      const parts = [];
      if (activeTag === 'PINNED') parts.push('视图：已置顶');
      else if (activeTag === 'ARCHIVED') parts.push('视图：已归档');
      else if (activeTag !== 'ALL') parts.push('标签：#' + activeTag);
      if (q) parts.push('搜索：“' + q + '”');
      filterBar.innerHTML = '<span>' + esc(parts.join(' · ')) + '（共 ' + filtered.length + ' 条）</span><button type="button" id="resetFilterBtn">清除筛选</button>';
      filterBar.hidden = false;
    } else {
      filterBar.hidden = true;
    }

    const host = $('memoGrid');
    if (!filtered.length) {
      host.innerHTML = '<div class="empty-state">' + (q || activeTag !== 'ALL' ? '没有匹配的随手记，换个标签或关键词试试' : '在上方输入框随手写一句，打上 #标签 即可快速归档') + '</div>';
      return;
    }

    host.innerHTML = filtered.map((note) => {
      const tags = parseTags(note.content);
      const isEditing = editingNoteId === note.id;
      const tagsHtml = tags.length
        ? tags.map((tg) => '<button type="button" class="mtag tone-' + esc(tagTone(tg)) + '" data-filter-tag="' + esc(tg) + '">#' + esc(tg) + '</button>').join('')
        : '<span class="mtag tone-slate">#未分类</span>';

      const bodyHtml = isEditing
        ? '<div class="inline-editor" data-edit-box="' + esc(note.id) + '">'
          + '<textarea id="inlineEditArea">' + esc(note.content) + '</textarea>'
          + '<div class="inline-editor-actions">'
          + '<button type="button" class="btn btn-ghost btn-xs" data-cancel-edit>取消</button>'
          + '<button type="button" class="btn btn-dark btn-xs" data-save-edit="' + esc(note.id) + '">保存 ⌘↵</button>'
          + '</div></div>'
        : '<div class="memo-body">' + renderNoteBody(note.content) + '</div>';

      return '<article class="memo-card' + (note.pinned ? ' is-pinned' : '') + '" data-note-id="' + esc(note.id) + '">'
        + '<div class="memo-head">'
        + '<div class="memo-tags">' + tagsHtml + '</div>'
        + '<div class="memo-ops">'
        + '<button type="button" class="memo-op-btn' + (note.pinned ? ' is-active' : '') + '" data-pin-note="' + esc(note.id) + '" title="' + (note.pinned ? '取消置顶' : '置顶') + '"><i class="fa-solid fa-thumbtack"></i></button>'
        + '<button type="button" class="memo-op-btn" data-edit-note="' + esc(note.id) + '" title="编辑"><i class="fa-solid fa-pen"></i></button>'
        + '<button type="button" class="memo-op-btn" data-archive-note="' + esc(note.id) + '" title="' + (note.archived ? '恢复到列表' : '归档') + '"><i class="fa-solid ' + (note.archived ? 'fa-rotate-left' : 'fa-box-archive') + '"></i></button>'
        + '<button type="button" class="memo-op-btn is-danger" data-delete-note="' + esc(note.id) + '" title="删除"><i class="fa-solid fa-trash"></i></button>'
        + '</div>'
        + '</div>'
        + bodyHtml
        + '<div class="memo-foot"><span>' + esc(formatTime(note.updatedAt || note.createdAt)) + '</span><span>' + (note.pinned ? '📌 已置顶' : note.archived ? '已归档' : '') + '</span></div>'
        + '</article>';
    }).join('');

    if (editingNoteId) {
      const ta = $('inlineEditArea');
      if (ta) { ta.focus(); ta.setSelectionRange(ta.value.length, ta.value.length); }
    }
  }

  function applyViewLayout() {
    const bothEnabled = viewPrefs.showNav && viewPrefs.showNotes;
    if (!bothEnabled) {
      activeView = viewPrefs.showNav ? 'nav' : 'notes';
    } else if (!['nav', 'notes', 'all'].includes(activeView)) {
      activeView = 'nav';
    }
    const showNavPanel = viewPrefs.showNav && (activeView === 'nav' || activeView === 'all');
    const showNotesPanel = viewPrefs.showNotes && (activeView === 'notes' || activeView === 'all');

    $('urlBoardSection').hidden = !showNavPanel;
    $('notesSection').hidden = !showNotesPanel;
    $('viewSeg').hidden = !bothEnabled;

    const singleNav = showNavPanel && !showNotesPanel;
    $('appRoot').classList.toggle('single-nav-mode', singleNav);
    if (singleNav) {
      $('urlBoardBody').hidden = false;
      $('toggleBoardBtn').setAttribute('aria-expanded', 'true');
    } else {
      $('urlBoardBody').hidden = boardCollapsed;
      $('toggleBoardBtn').setAttribute('aria-expanded', String(!boardCollapsed));
    }

    $('viewSeg').querySelectorAll('[data-view-tab]').forEach((btn) => {
      const on = btn.dataset.viewTab === activeView;
      btn.classList.toggle('active', on);
      btn.setAttribute('aria-selected', String(on));
    });

    $('modNavCheck').checked = viewPrefs.showNav;
    $('modNotesCheck').checked = viewPrefs.showNotes;
    $('defaultViewPills').querySelectorAll('[data-default-view]').forEach((btn) => {
      btn.classList.toggle('active', btn.dataset.defaultView === viewPrefs.defaultView);
    });

    updateSearchBadges();
  }

  function updateSearchBadges() {
    const q = searchQuery.trim();
    const navBadge = $('navSearchBadge');
    const notesBadge = $('notesSearchBadge');
    if (!navBadge || !notesBadge) return;
    if (q && activeView === 'notes' && viewPrefs.showNav && lastUrlMatchCount > 0) {
      navBadge.textContent = String(lastUrlMatchCount);
      navBadge.hidden = false;
    } else {
      navBadge.hidden = true;
    }
    if (q && activeView === 'nav' && viewPrefs.showNotes && lastMemoMatchCount > 0) {
      notesBadge.textContent = String(lastMemoMatchCount);
      notesBadge.hidden = false;
    } else {
      notesBadge.hidden = true;
    }
  }

  function setActiveView(view) {
    if (!['nav', 'notes', 'all'].includes(view)) return;
    if (view === 'nav' && !viewPrefs.showNav) return;
    if (view === 'notes' && !viewPrefs.showNotes) return;
    if (view === 'all' && !(viewPrefs.showNav && viewPrefs.showNotes)) return;
    activeView = view;
    viewPrefs.lastView = view;
    saveViewPrefs();
    closeEnvPopover();
    applyViewLayout();
  }

  function renderAll() {
    renderEnvBar();
    renderGroupTabs();
    renderUrlGrid();
    renderTagRail();
    renderMemoGrid();
    applyViewLayout();
  }

  // Link Dialog
  let selectedLinkColor = 'blue';
  let selectedIconMode = 'auto';
  let selectedLinkIcon = ''; // '' = deterministic hash by domain/title

  function currentPreviewFaIcon() {
    if (selectedLinkIcon && FA_ICON_SET.has(selectedLinkIcon)) return selectedLinkIcon;
    let hostSeed = '';
    try { hostSeed = new URL($('linkDefaultUrlInput').value.trim()).hostname; } catch (_) {}
    return hashFaIcon(hostSeed || $('linkTitleInput').value.trim() || 'site');
  }

  function renderIconPicker() {
    const modeBtns = $('iconModeTabs').querySelectorAll('[data-icon-mode]');
    modeBtns.forEach((b) => b.classList.toggle('active', b.dataset.iconMode === selectedIconMode));
    $('customFaviconField').hidden = selectedIconMode === 'icon';
    $('linkIconHint').textContent = selectedIconMode === 'auto'
      ? (selectedLinkIcon ? '优先加载网站 Favicon，失败时回退为自选图标' : '优先加载网站 Favicon，失败时按域名 Hash 自动匹配图标')
      : (selectedLinkIcon ? '始终显示自选 FontAwesome 图标' : '始终按域名 Hash 自动匹配 FontAwesome 图标');

    const prev = $('linkIconPreview');
    prev.className = 'u-ico tone-' + selectedLinkColor;
    prev.innerHTML = '<i class="fa-solid fa-' + esc(currentPreviewFaIcon()) + '" aria-hidden="true"></i>';

    const q = ($('iconSearchInput').value || '').trim().toLowerCase();
    const list = q ? FA_ICONS.filter((ic) => ic.id.includes(q) || ic.kw.toLowerCase().includes(q)) : FA_ICONS;
    const autoChip = !q
      ? '<button type="button" class="icon-choice is-auto-chip' + (selectedLinkIcon === '' ? ' active' : '') + '" data-pick-icon="" title="按域名自动 Hash 匹配图标">自动 Hash</button>'
      : '';
    $('linkIconGrid').innerHTML = autoChip + list.map((ic) =>
      '<button type="button" class="icon-choice' + (selectedLinkIcon === ic.id ? ' active' : '') + '" data-pick-icon="' + esc(ic.id) + '" title="fa-' + esc(ic.id) + '" aria-label="' + esc(ic.id) + '"><i class="fa-solid fa-' + esc(ic.id) + '"></i></button>'
    ).join('');
  }

  function renderLinkSwatches() {
    $('linkColorSwatches').innerHTML = TONES.map((c) =>
      '<button type="button" class="swatch' + (selectedLinkColor === c ? ' active' : '') + '" data-swatch="' + c + '" style="background:' + SWATCH_HEX[c] + '" aria-label="' + c + '"></button>'
    ).join('');
  }

  function addEnvUrlRow(envId, urlValue) {
    const container = $('envUrlRows');
    const row = document.createElement('div');
    row.className = 'env-url-row';
    const opts = data.envs.map((e) => '<option value="' + esc(e.id) + '"' + (e.id === envId ? ' selected' : '') + '>' + esc(e.name) + '</option>').join('');
    row.innerHTML = '<select class="env-row-select">' + opts + '</select>'
      + '<input type="url" class="env-row-url" placeholder="https:// 或 http://192.168..." value="' + esc(urlValue || '') + '">'
      + '<button type="button" class="row-del" title="移除此环境地址" aria-label="移除"><i class="fa-solid fa-xmark"></i></button>';
    row.querySelector('.row-del').onclick = () => row.remove();
    container.appendChild(row);
  }

  function openLinkDialog(linkId) {
    const link = linkId ? data.links.find((x) => x.id === linkId) : null;
    $('linkDialogTitle').textContent = link ? '编辑网址' : '添加网址';
    $('linkIdInput').value = link ? link.id : '';
    $('linkTitleInput').value = link ? link.title : '';
    $('linkGroupInput').value = link ? (link.group || '常用') : (activeGroup !== 'ALL' ? activeGroup : '常用');
    $('linkDefaultUrlInput').value = link ? (link.defaultUrl || '') : '';
    $('linkFaviconUrlInput').value = link ? (link.faviconUrl || '') : '';
    $('iconSearchInput').value = '';
    selectedLinkColor = link && TONES.includes(link.color) ? link.color : 'blue';
    selectedIconMode = link && link.iconMode === 'icon' ? 'icon' : 'auto';
    selectedLinkIcon = link && link.icon && FA_ICON_SET.has(link.icon) ? link.icon : '';
    renderLinkSwatches();
    renderIconPicker();

    const rowsHost = $('envUrlRows');
    rowsHost.innerHTML = '';
    if (link && link.envUrls) {
      for (const [eid, u] of Object.entries(link.envUrls)) {
        if (u && data.envs.some((e) => e.id === eid)) addEnvUrlRow(eid, u);
      }
    }
    $('deleteLinkBtn').hidden = !link;
    $('linkDialog').showModal();
    $('linkTitleInput').focus();
  }

  // Manage Environments Dialog
  function renderEnvManageList() {
    const host = $('envManageList');
    host.innerHTML = data.envs.map((env) => {
      const usageCount = data.links.filter((l) => l.envUrls && l.envUrls[env.id]).length;
      return '<div class="env-manage-item">'
        + '<div class="env-manage-left"><span class="tag-dot dot-' + esc(env.color || 'blue') + '"></span><span>' + esc(env.name) + '</span><span class="env-manage-meta">已绑定 ' + usageCount + ' 个网址</span></div>'
        + (data.envs.length > 1
            ? '<button type="button" class="btn btn-danger-ghost btn-xs" data-del-env="' + esc(env.id) + '">删除</button>'
            : '<span class="env-manage-meta">至少保留 1 个</span>')
        + '</div>';
    }).join('');
  }

  function openEnvDialog() {
    renderEnvManageList();
    $('envDialog').showModal();
  }

  // Single-card Multi-Env Popover
  function closeEnvPopover() {
    $('envPopover').hidden = true;
  }

  function openEnvPopover(linkId, anchor) {
    const link = data.links.find((l) => l.id === linkId);
    if (!link) return;
    const pop = $('envPopover');
    const endpoints = listLinkEndpoints(link);
    pop.innerHTML = '<div class="env-pop-head">' + esc(link.title) + ' · 选择环境打开</div>'
      + endpoints.map((ep) =>
        '<a class="env-pop-item' + (ep.current ? ' current' : '') + '" href="' + esc(ep.url) + '" target="_blank" rel="noopener noreferrer">'
        + '<div class="env-pop-meta"><strong>' + esc(ep.name) + (ep.current ? '（当前）' : '') + '</strong><span>' + esc(ep.url) + '</span></div>'
        + '<span class="env-pop-go">打开 ↗</span>'
        + '</a>'
      ).join('');
    pop.hidden = false;
    const rect = anchor.getBoundingClientRect();
    const popRect = pop.getBoundingClientRect();
    const left = Math.min(window.innerWidth - popRect.width - 12, Math.max(12, rect.right - popRect.width));
    const top = Math.min(window.innerHeight - popRect.height - 12, rect.bottom + 6);
    pop.style.left = left + 'px';
    pop.style.top = top + 'px';
  }

  // Workspace File Snapshot (BookStark.files)
  function hasWorkspaceFiles() {
    return !!(window.BookStark && window.BookStark.files && typeof window.BookStark.files.write === 'function');
  }

  async function saveWorkspaceSnapshot() {
    if (!hasWorkspaceFiles()) { showToast('当前预览模式未连接工作区文件系统'); return; }
    try {
      const bytes = new TextEncoder().encode(JSON.stringify(data, null, 2));
      await window.BookStark.files.write(WORKSPACE_SNAPSHOT_PATH, bytes);
      showToast('已保存快照到工作区 ' + WORKSPACE_SNAPSHOT_PATH);
    } catch (_) {
      showToast('保存工作区快照失败');
    }
  }

  async function loadWorkspaceSnapshot() {
    if (!hasWorkspaceFiles()) { showToast('当前预览模式未连接工作区文件系统'); return; }
    try {
      const buf = await window.BookStark.files.read(WORKSPACE_SNAPSHOT_PATH);
      const parsed = JSON.parse(new TextDecoder().decode(buf));
      if (!parsed || !Array.isArray(parsed.links) || !Array.isArray(parsed.notes)) throw new Error('invalid');
      data = parsed;
      if (!data.envs || !data.envs.length) data.envs = defaultData().envs;
      if (!data.envs.some((e) => e.id === activeEnv)) activeEnv = data.envs[0].id;
      saveData('已从工作区快照恢复');
      renderAll();
      showToast('已从工作区快照恢复');
    } catch (_) {
      showToast('未找到工作区快照或读取失败');
    }
  }

  // Event Wiring
  function initEvents() {
    function closeSettingsMenu() {
      $('settingsMenu').hidden = true;
      $('settingsMenuBtn').setAttribute('aria-expanded', 'false');
    }

    // Search
    const searchInput = $('globalSearch');
    searchInput.oninput = () => {
      searchQuery = searchInput.value;
      renderUrlGrid();
      renderMemoGrid();
      updateSearchBadges();
    };

    // View Segmented Tabs
    $('viewSeg').onclick = (e) => {
      const btn = e.target.closest('[data-view-tab]');
      if (!btn) return;
      setActiveView(btn.dataset.viewTab);
    };

    // Unified Settings Dropdown (View + Theme + Data)
    $('settingsMenuBtn').onclick = (e) => {
      e.stopPropagation();
      const menu = $('settingsMenu');
      const open = menu.hidden;
      menu.hidden = !open;
      $('settingsMenuBtn').setAttribute('aria-expanded', String(open));
    };
    $('settingsMenu').onclick = (e) => e.stopPropagation();
    const onModuleToggle = (key, inputEl) => {
      const nextNav = key === 'nav' ? inputEl.checked : viewPrefs.showNav;
      const nextNotes = key === 'notes' ? inputEl.checked : viewPrefs.showNotes;
      if (!nextNav && !nextNotes) {
        inputEl.checked = true;
        showToast('至少保留 1 个显示模块');
        return;
      }
      viewPrefs.showNav = nextNav;
      viewPrefs.showNotes = nextNotes;
      if (nextNav && nextNotes && viewPrefs.lastView) {
        activeView = viewPrefs.lastView;
      }
      saveViewPrefs();
      applyViewLayout();
    };
    $('modNavCheck').onchange = () => onModuleToggle('nav', $('modNavCheck'));
    $('modNotesCheck').onchange = () => onModuleToggle('notes', $('modNotesCheck'));
    $('defaultViewPills').onclick = (e) => {
      const btn = e.target.closest('[data-default-view]');
      if (!btn) return;
      viewPrefs.defaultView = btn.dataset.defaultView;
      saveViewPrefs();
      applyViewLayout();
      showToast('已更新启动默认页');
    };
    $('themePills').onclick = (e) => {
      const btn = e.target.closest('[data-theme-choice]');
      if (!btn) return;
      applyTheme(btn.dataset.themeChoice);
    };

    document.addEventListener('keydown', (e) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'k') {
        e.preventDefault();
        searchInput.focus();
        searchInput.select();
      } else if (e.altKey && !e.ctrlKey && !e.metaKey && ['1', '2', '3'].includes(e.key)) {
        const map = { '1': 'nav', '2': 'notes', '3': 'all' };
        if (viewPrefs.showNav && viewPrefs.showNotes) {
          e.preventDefault();
          setActiveView(map[e.key]);
        }
      } else if (e.key === '/' && !/INPUT|TEXTAREA|SELECT/.test(document.activeElement?.tagName || '')) {
        e.preventDefault();
        searchInput.focus();
      } else if (e.key === 'Escape') {
        closeEnvPopover();
        closeSettingsMenu();
        if (editingNoteId) { editingNoteId = null; renderMemoGrid(); }
        else if (document.activeElement === searchInput && searchInput.value) {
          searchInput.value = '';
          searchQuery = '';
          renderUrlGrid();
          renderMemoGrid();
          updateSearchBadges();
        }
      }
    });

    document.addEventListener('click', (e) => {
      if (!e.target.closest('#settingsDropdown')) {
        closeSettingsMenu();
      }
      if (!e.target.closest('#envPopover') && !e.target.closest('[data-open-env-pop]')) {
        closeEnvPopover();
      }
    });

    $('exportJsonBtn').onclick = () => {
      closeSettingsMenu();
      const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' });
      const a = document.createElement('a');
      a.href = URL.createObjectURL(blob);
      a.download = 'bookstark-stardeck-' + new Date().toISOString().slice(0, 10) + '.json';
      a.click();
      setTimeout(() => URL.revokeObjectURL(a.href), 5000);
      showToast('已导出 JSON 备份');
    };
    $('importJsonBtn').onclick = () => {
      closeSettingsMenu();
      $('importFileInput').click();
    };
    $('importFileInput').onchange = (e) => {
      const file = e.target.files && e.target.files[0];
      e.target.value = '';
      if (!file) return;
      const reader = new FileReader();
      reader.onload = () => {
        try {
          const parsed = JSON.parse(String(reader.result || ''));
          if (!parsed || !Array.isArray(parsed.links) || !Array.isArray(parsed.notes)) throw new Error('invalid');
          data = parsed;
          if (!data.envs || !data.envs.length) data.envs = defaultData().envs;
          if (!data.envs.some((env) => env.id === activeEnv)) activeEnv = data.envs[0].id;
          saveData('已导入恢复');
          renderAll();
          showToast('导入成功：' + data.links.length + ' 个网址，' + data.notes.length + ' 条随手记');
        } catch (_) {
          showToast('导入失败：JSON 格式无效');
        }
      };
      reader.readAsText(file);
    };
    $('saveSnapshotBtn').onclick = () => { closeSettingsMenu(); saveWorkspaceSnapshot(); };
    $('loadSnapshotBtn').onclick = () => { closeSettingsMenu(); loadWorkspaceSnapshot(); };
    $('clearSamplesBtn').onclick = () => {
      closeSettingsMenu();
      if (!confirm('确定清空全部网址和随手记吗？建议先导出 JSON 备份。')) return;
      data.links = [];
      data.notes = [];
      activeGroup = 'ALL';
      activeTag = 'ALL';
      saveData('已清空');
      renderAll();
      showToast('已清空全部数据');
    };

    // Board Collapse (only active when both modules are shown together)
    $('toggleBoardBtn').onclick = () => {
      if (activeView !== 'all') return;
      boardCollapsed = !boardCollapsed;
      $('toggleBoardBtn').setAttribute('aria-expanded', String(!boardCollapsed));
      $('urlBoardBody').hidden = boardCollapsed;
    };

    // Group Tabs
    $('groupTabs').onclick = (e) => {
      const btn = e.target.closest('[data-group]');
      if (!btn) return;
      activeGroup = btn.dataset.group;
      renderGroupTabs();
      renderUrlGrid();
    };

    // Env Bar
    $('envBar').onclick = (e) => {
      if (e.target.closest('#openEnvManageBtn')) { openEnvDialog(); return; }
      const pill = e.target.closest('[data-env-id]');
      if (!pill) return;
      activeEnv = pill.dataset.envId;
      writeDevicePref(DEVICE_ENV_KEY, activeEnv);
      closeEnvPopover();
      renderEnvBar();
      renderUrlGrid();
      const envObj = data.envs.find((x) => x.id === activeEnv);
      if (envObj) showToast('已切换到「' + envObj.name + '」环境');
    };

    // Add Link
    $('addLinkBtn').onclick = () => openLinkDialog(null);

    // URL Grid delegation
    $('urlGrid').onclick = (e) => {
      const popBtn = e.target.closest('[data-open-env-pop]');
      if (popBtn) {
        e.preventDefault();
        e.stopPropagation();
        openEnvPopover(popBtn.dataset.openEnvPop, popBtn);
        return;
      }
      const editBtn = e.target.closest('[data-edit-link]');
      if (editBtn) {
        e.preventDefault();
        e.stopPropagation();
        openLinkDialog(editBtn.dataset.editLink);
      }
    };

    // Link Dialog Events
    $('linkColorSwatches').onclick = (e) => {
      const sw = e.target.closest('[data-swatch]');
      if (!sw) return;
      selectedLinkColor = sw.dataset.swatch;
      renderLinkSwatches();
      renderIconPicker();
    };
    $('iconModeTabs').onclick = (e) => {
      const btn = e.target.closest('[data-icon-mode]');
      if (!btn) return;
      selectedIconMode = btn.dataset.iconMode;
      renderIconPicker();
    };
    $('linkIconGrid').onclick = (e) => {
      const btn = e.target.closest('[data-pick-icon]');
      if (!btn) return;
      selectedLinkIcon = btn.dataset.pickIcon;
      renderIconPicker();
    };
    $('iconSearchInput').oninput = () => renderIconPicker();
    $('randomIconBtn').onclick = () => {
      const pool = FA_ICONS.filter((x) => x.id !== selectedLinkIcon);
      selectedLinkIcon = pool[Math.floor(Math.random() * pool.length)].id;
      renderIconPicker();
    };
    $('linkTitleInput').oninput = () => { if (!selectedLinkIcon) renderIconPicker(); };
    $('linkDefaultUrlInput').oninput = () => { if (!selectedLinkIcon) renderIconPicker(); };
    $('addEnvUrlRowBtn').onclick = () => {
      const used = new Set(Array.from($('envUrlRows').querySelectorAll('.env-row-select')).map((s) => s.value));
      const next = data.envs.find((e) => !used.has(e.id)) || data.envs[0];
      addEnvUrlRow(next ? next.id : 'public', '');
    };
    $('linkForm').onsubmit = (e) => {
      e.preventDefault();
      const id = $('linkIdInput').value;
      const title = $('linkTitleInput').value.trim();
      const group = $('linkGroupInput').value.trim() || '常用';
      const defaultUrl = safeUrl($('linkDefaultUrlInput').value);
      const faviconUrl = safeUrl($('linkFaviconUrlInput').value);
      if (!title || !defaultUrl) {
        showToast('请填写网站名称与有效的 http/https 网址');
        return;
      }
      const envUrls = {};
      for (const row of $('envUrlRows').querySelectorAll('.env-url-row')) {
        const eid = row.querySelector('.env-row-select').value;
        const u = safeUrl(row.querySelector('.env-row-url').value);
        if (eid && u) envUrls[eid] = u;
      }
      const patch = {
        title,
        group,
        icon: selectedLinkIcon,
        iconMode: selectedIconMode,
        faviconUrl,
        color: selectedLinkColor,
        defaultUrl,
        envUrls
      };
      if (id) {
        const idx = data.links.findIndex((x) => x.id === id);
        if (idx >= 0) data.links[idx] = { ...data.links[idx], ...patch };
      } else {
        data.links.push({ id: genId(), ...patch });
      }
      saveData('网址已保存');
      $('linkDialog').close();
      renderGroupTabs();
      renderUrlGrid();
      showToast(id ? '网址已更新' : '已添加到网址大盘');
    };
    $('deleteLinkBtn').onclick = () => {
      const id = $('linkIdInput').value;
      if (!id) return;
      data.links = data.links.filter((x) => x.id !== id);
      saveData('网址已删除');
      $('linkDialog').close();
      renderGroupTabs();
      renderUrlGrid();
      showToast('已删除该网址');
    };

    // Manage Environments Events
    $('envManageList').onclick = (e) => {
      const btn = e.target.closest('[data-del-env]');
      if (!btn || data.envs.length <= 1) return;
      const delId = btn.dataset.delEnv;
      data.envs = data.envs.filter((x) => x.id !== delId);
      for (const link of data.links) {
        if (link.envUrls && delId in link.envUrls) delete link.envUrls[delId];
      }
      if (activeEnv === delId) {
        activeEnv = data.envs[0].id;
        writeDevicePref(DEVICE_ENV_KEY, activeEnv);
      }
      saveData('环境已更新');
      renderEnvManageList();
      renderEnvBar();
      renderUrlGrid();
    };
    $('addEnvForm').onsubmit = (e) => {
      e.preventDefault();
      const name = $('newEnvNameInput').value.trim();
      const color = $('newEnvColorInput').value;
      if (!name) return;
      if (data.envs.some((x) => x.name === name)) {
        showToast('该环境名称已存在');
        return;
      }
      data.envs.push({ id: 'env_' + genId().slice(0, 6), name, color });
      $('newEnvNameInput').value = '';
      saveData('已新增环境');
      renderEnvManageList();
      renderEnvBar();
      showToast('已新增环境「' + name + '」');
    };

    // Close modal buttons
    document.querySelectorAll('[data-close-dialog]').forEach((btn) => {
      btn.onclick = () => btn.closest('dialog')?.close();
    });

    // Tag Rail + Quick Tags
    $('tagRail').onclick = (e) => {
      const btn = e.target.closest('[data-filter-tag]');
      if (!btn) return;
      activeTag = btn.dataset.filterTag;
      renderTagRail();
      renderMemoGrid();
    };
    $('activeFilterBar').onclick = (e) => {
      if (e.target.closest('#resetFilterBtn')) {
        activeTag = 'ALL';
        searchQuery = '';
        $('globalSearch').value = '';
        renderAll();
      }
    };
    $('quickTagChips').onclick = (e) => {
      const btn = e.target.closest('[data-insert-tag]');
      if (!btn) return;
      const ta = $('noteInput');
      const tagText = '#' + btn.dataset.insertTag + ' ';
      const start = ta.selectionStart ?? ta.value.length;
      const end = ta.selectionEnd ?? ta.value.length;
      const prefix = start > 0 && !/\s/.test(ta.value[start - 1]) ? ' ' : '';
      ta.value = ta.value.slice(0, start) + prefix + tagText + ta.value.slice(end);
      const nextPos = start + prefix.length + tagText.length;
      ta.focus();
      ta.setSelectionRange(nextPos, nextPos);
    };

    // Note Composer Submit
    function submitComposer() {
      const ta = $('noteInput');
      const content = ta.value.trim();
      if (!content) { showToast('先写点内容再记下来吧'); ta.focus(); return; }
      const now = Date.now();
      data.notes.unshift({
        id: genId(),
        content,
        pinned: false,
        archived: false,
        createdAt: now,
        updatedAt: now
      });
      ta.value = '';
      if (activeTag === 'ARCHIVED') activeTag = 'ALL';
      saveData('随手记已保存');
      renderTagRail();
      renderMemoGrid();
      showToast('已记下来');
    }
    $('noteComposer').onsubmit = (e) => { e.preventDefault(); submitComposer(); };
    $('noteInput').addEventListener('keydown', (e) => {
      if ((e.metaKey || e.ctrlKey) && e.key === 'Enter') {
        e.preventDefault();
        submitComposer();
      }
    });

    // Memo Grid Delegation
    $('memoGrid').onclick = (e) => {
      const copyBtn = e.target.closest('[data-copy]');
      if (copyBtn) { copyText(copyBtn.dataset.copy, copyBtn); return; }

      const tagBtn = e.target.closest('[data-filter-tag]');
      if (tagBtn) {
        activeTag = tagBtn.dataset.filterTag;
        renderTagRail();
        renderMemoGrid();
        return;
      }

      const pinBtn = e.target.closest('[data-pin-note]');
      if (pinBtn) {
        const n = data.notes.find((x) => x.id === pinBtn.dataset.pinNote);
        if (n) { n.pinned = !n.pinned; saveData(n.pinned ? '已置顶' : '已取消置顶'); renderTagRail(); renderMemoGrid(); }
        return;
      }

      const editBtn = e.target.closest('[data-edit-note]');
      if (editBtn) {
        editingNoteId = editBtn.dataset.editNote;
        renderMemoGrid();
        return;
      }

      if (e.target.closest('[data-cancel-edit]')) {
        editingNoteId = null;
        renderMemoGrid();
        return;
      }

      const saveBtn = e.target.closest('[data-save-edit]');
      if (saveBtn) {
        const ta = $('inlineEditArea');
        const nextContent = (ta ? ta.value : '').trim();
        if (!nextContent) { showToast('内容不能为空'); return; }
        const n = data.notes.find((x) => x.id === saveBtn.dataset.saveEdit);
        if (n) { n.content = nextContent; n.updatedAt = Date.now(); }
        editingNoteId = null;
        saveData('修改已保存');
        renderTagRail();
        renderMemoGrid();
        showToast('已更新');
        return;
      }

      const archBtn = e.target.closest('[data-archive-note]');
      if (archBtn) {
        const n = data.notes.find((x) => x.id === archBtn.dataset.archiveNote);
        if (n) {
          n.archived = !n.archived;
          if (n.archived) n.pinned = false;
          saveData(n.archived ? '已归档' : '已恢复');
          renderTagRail();
          renderMemoGrid();
          showToast(n.archived ? '已移入归档' : '已恢复到列表');
        }
        return;
      }

      const delBtn = e.target.closest('[data-delete-note]');
      if (delBtn) {
        const id = delBtn.dataset.deleteNote;
        data.notes = data.notes.filter((x) => x.id !== id);
        if (editingNoteId === id) editingNoteId = null;
        saveData('已删除');
        renderTagRail();
        renderMemoGrid();
        showToast('已删除该条记录');
      }
    };

    $('memoGrid').addEventListener('keydown', (e) => {
      if (e.target && e.target.id === 'inlineEditArea' && (e.metaKey || e.ctrlKey) && e.key === 'Enter') {
        e.preventDefault();
        const btn = $('memoGrid').querySelector('[data-save-edit]');
        if (btn) btn.click();
      }
    });
  }

  // Boot
  const savedTheme = readDevicePref(DEVICE_THEME_KEY, '');
  applyTheme(savedTheme || (window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light'));
  initEvents();
  renderAll();
})();
