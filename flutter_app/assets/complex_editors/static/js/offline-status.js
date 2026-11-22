/* ===== BookStark Offline Status Center ===== */
(function() {
  'use strict';

  var state = { count: 0, syncing: false, records: [], online: navigator.onLine !== false, probing: false };
  var offlineToastShown = false;
  var views = [];

  function statusPanelHTML(withClose) {
    return '' +
      '<div class="offline-status-head">' +
      '  <div class="offline-status-title"><i class="fa-solid fa-cloud"></i><span>同步状态</span></div>' +
      (withClose ? '  <button type="button" class="offline-status-close" data-offline-action="close" aria-label="关闭"><i class="fa-solid fa-xmark"></i></button>' : '') +
      '</div>' +
      '<div class="offline-status-body">' +
      '  <div class="offline-status-row"><span>网络</span><span class="offline-status-value" data-offline-field="network">-</span></div>' +
      '  <div class="offline-status-row"><span>离线队列</span><span class="offline-status-value" data-offline-field="queueCount">0</span></div>' +
      '  <div class="offline-status-row"><span>状态</span><span class="offline-status-value" data-offline-field="syncState">-</span></div>' +
      '  <div class="offline-status-section">' +
      '    <div class="offline-status-row"><span>安装状态</span><span class="offline-status-value" data-offline-field="installState">-</span></div>' +
      '    <div class="offline-status-row"><span>缓存占用</span><span class="offline-status-value" data-offline-field="cacheUsage">-</span></div>' +
      '    <div class="offline-cache-list" data-offline-field="cacheList"></div>' +
      '  </div>' +
      '  <div class="offline-queue-list" data-offline-field="queueList"></div>' +
      '  <div class="offline-status-actions">' +
      '    <button type="button" class="offline-status-btn" data-offline-action="install" style="display:none">安装应用</button>' +
      '    <button type="button" class="offline-status-btn" data-offline-action="clearDynamic">清理动态缓存</button>' +
      '    <button type="button" class="offline-status-btn" data-offline-action="clearAll">清理全部缓存</button>' +
      '    <button type="button" class="offline-status-btn" data-offline-action="refresh">刷新</button>' +
      '    <button type="button" class="offline-status-btn primary" data-offline-action="replay">立即同步</button>' +
      '  </div>' +
      '</div>';
  }

  function bindView(root) {
    if (!root || root.__offlineStatusBound) return;
    root.__offlineStatusBound = true;
    views.push(root);
    var closeBtn = root.querySelector('[data-offline-action="close"]');
    if (closeBtn) closeBtn.addEventListener('click', close);
    var refreshBtn = root.querySelector('[data-offline-action="refresh"]');
    if (refreshBtn) refreshBtn.addEventListener('click', refreshWithProbe);
    var replayBtn = root.querySelector('[data-offline-action="replay"]');
    if (replayBtn) replayBtn.addEventListener('click', replay);
    var installBtn = root.querySelector('[data-offline-action="install"]');
    if (installBtn) installBtn.addEventListener('click', promptInstall);
    var clearDynamicBtn = root.querySelector('[data-offline-action="clearDynamic"]');
    if (clearDynamicBtn) clearDynamicBtn.addEventListener('click', function() { clearCache('dynamic'); });
    var clearAllBtn = root.querySelector('[data-offline-action="clearAll"]');
    if (clearAllBtn) clearAllBtn.addEventListener('click', function() { clearCache('all'); });
  }

  function findField(root, name) {
    return root ? root.querySelector('[data-offline-field="' + name + '"]') : null;
  }

  function forEachView(fn) {
    views = views.filter(function(root) { return root && document.documentElement.contains(root); });
    views.forEach(fn);
  }

  function setActionDisabled(action, disabled) {
    forEachView(function(root) {
      var btn = root.querySelector('[data-offline-action="' + action + '"]');
      if (btn) btn.disabled = !!disabled;
    });
  }

  function close() {
    var panel = document.getElementById('offlineStatusPanel');
    if (panel) panel.classList.remove('active');
  }

  function refresh(options) {
    options = options || {};
    var shouldProbe = options.probe === true;
    if (!window.BSOfflineQueue) {
      render();
      return shouldProbe ? probeConnectivity() : Promise.resolve(state.online !== false);
    }
    var listPromise = BSOfflineQueue.getAllFromQueue ? BSOfflineQueue.getAllFromQueue() : Promise.resolve([]);
    return listPromise.then(function(records) {
      state.records = records || [];
      state.count = state.records.length;
      render();
      return shouldProbe ? probeConnectivity() : state.online !== false;
    }).catch(function() {
      state.records = [];
      render();
      return shouldProbe ? probeConnectivity() : state.online !== false;
    });
  }

  function refreshWithProbe() {
    return refresh({ probe: true });
  }

  function replay() {
    if (!window.BSOfflineQueue || state.syncing) return;
    state.syncing = true;
    render();
    BSOfflineQueue.replayQueue().then(function(result) {
      if (window.BSDialog && BSDialog.toast) {
        var msg = '同步完成';
        if (result && (result.success || result.failed)) {
          msg = '已同步 ' + (result.success || 0) + ' 条，失败 ' + (result.failed || 0) + ' 条';
        }
        BSDialog.toast(msg, result && result.failed ? 'warning' : 'success');
      }
    }).finally(function() {
      state.syncing = false;
      refresh({ probe: false });
    });
  }

  function render() {
    var online = state.online !== false;

    forEachView(function(root) {
      var network = findField(root, 'network');
      var count = findField(root, 'queueCount');
      var syncState = findField(root, 'syncState');
      var replayBtn = root.querySelector('[data-offline-action="replay"]');
      var list = findField(root, 'queueList');
      if (network) network.textContent = state.probing ? '检测中' : (online ? '在线' : '离线');
      if (count) count.textContent = state.count + ' 条';
      if (syncState) syncState.textContent = state.syncing ? '同步中' : (state.count > 0 ? '待同步' : '已同步');
      if (replayBtn) replayBtn.disabled = state.syncing || !online || state.count === 0;
      if (list) renderList(list);
    });
    renderPWA();
  }

  function setOnline(online) {
    online = !!online;
    if (state.online === online && !state.probing) return;
    state.online = online;
    state.probing = false;
    render();
  }

  function probeConnectivity() {
    if (state.probing) return Promise.resolve(state.online !== false);
    if (navigator.onLine === false) {
      setOnline(false);
      return Promise.resolve(false);
    }
    state.probing = true;
    render();
    var controller = typeof AbortController !== 'undefined' ? new AbortController() : null;
    var timeout = setTimeout(function() {
      if (controller) controller.abort();
    }, 3500);
    return fetch('/api/lang/bundle?__online_probe=' + Date.now(), {
      method: 'GET',
      cache: 'no-store',
      credentials: 'same-origin',
      signal: controller ? controller.signal : undefined,
      headers: { 'X-BookStark-Online-Probe': '1' }
    }).then(function(response) {
      clearTimeout(timeout);
      if (!response || !response.ok || response.headers.get('X-From-Cache') === 'true' || response.headers.get('X-Cache-Stale') === 'true' || response.headers.get('X-Offline-Queued') === 'true') {
        setOnline(false);
        return false;
      }
      setOnline(true);
      return true;
    }).catch(function() {
      clearTimeout(timeout);
      setOnline(false);
      return false;
    });
  }

  function renderPWA() {
    if (!window.BookStarkPWA) {
      forEachView(function(root) {
        var installState = findField(root, 'installState');
        var cacheUsage = findField(root, 'cacheUsage');
        var installBtn = root.querySelector('[data-offline-action="install"]');
        var clearBtn = root.querySelector('[data-offline-action="clearAll"]');
        var clearDynamicBtn = root.querySelector('[data-offline-action="clearDynamic"]');
        var cacheList = findField(root, 'cacheList');
        if (installState) installState.textContent = '浏览器不支持';
        if (cacheUsage) cacheUsage.textContent = '-';
        if (installBtn) installBtn.style.display = 'none';
        if (clearBtn) clearBtn.disabled = true;
        if (clearDynamicBtn) clearDynamicBtn.disabled = true;
        if (cacheList) cacheList.innerHTML = '';
      });
      return;
    }
    BookStarkPWA.getStatus().then(function(status) {
      forEachView(function(root) {
        var installState = findField(root, 'installState');
        var cacheUsage = findField(root, 'cacheUsage');
        var installBtn = root.querySelector('[data-offline-action="install"]');
        var clearBtn = root.querySelector('[data-offline-action="clearAll"]');
        var clearDynamicBtn = root.querySelector('[data-offline-action="clearDynamic"]');
        var cacheList = findField(root, 'cacheList');
        if (installState) {
          installState.textContent = status.standalone ? '已安装' : (status.installable ? '可安装' : '浏览器中');
        }
        if (cacheUsage) {
          var storage = status.storage || {};
          cacheUsage.textContent = storage.quota ? storage.usageText + ' / ' + storage.quotaText + ' (' + storage.percent + '%)' : storage.usageText;
        }
        if (installBtn) installBtn.style.display = status.installable && !status.standalone ? '' : 'none';
        if (clearBtn) clearBtn.disabled = !status.caches;
        if (clearDynamicBtn) clearDynamicBtn.disabled = !status.caches;
        if (cacheList) cacheList.innerHTML = renderCacheDetails(status.cacheDetails || []);
      });
    });
  }

  function renderCacheDetails(details) {
    if (!details.length) return '<div class="offline-cache-empty">暂无浏览器缓存</div>';
    var modules = { static: { label: '静态资源', count: 0 }, dynamic: { label: '页面/API', count: 0 }, other: { label: '其他', count: 0 } };
    details.forEach(function(item) {
      var key = modules[item.module] ? item.module : 'other';
      modules[key].count += item.count || 0;
    });
    return Object.keys(modules).map(function(key) {
      return '<div class="offline-cache-row"><span>' + modules[key].label + '</span><span>' + modules[key].count + ' 项</span></div>';
    }).join('');
  }

  function promptInstall() {
    if (!window.BookStarkPWA) return;
    BookStarkPWA.promptInstall().then(function(result) {
      if (!result || result.available === false) {
        if (window.BSDialog && BSDialog.toast) BSDialog.toast('当前浏览器暂未提供安装入口', 'info');
      }
      renderPWA();
    });
  }

  function clearCache(scope) {
    if (!window.BookStarkPWA) return;
    var action = scope === 'dynamic' ? 'clearDynamic' : 'clearAll';
    setActionDisabled(action, true);
    BookStarkPWA.clearCaches(scope).then(function(count) {
      if (window.BSDialog && BSDialog.toast) BSDialog.toast('已清理 ' + count + ' 个缓存', 'success');
      return renderPWA();
    }).catch(function() {
      if (window.BSDialog && BSDialog.toast) BSDialog.toast('缓存清理失败', 'error');
    }).finally(function() {
      setActionDisabled(action, false);
    });
  }

  function renderList(list) {
    if (!state.records.length) {
      list.innerHTML = '<div class="offline-queue-item"><span class="offline-queue-url">没有待同步操作</span></div>';
      return;
    }
    list.innerHTML = state.records.slice(0, 20).map(function(record) {
      var path = record.url || '';
      try { path = new URL(path, window.location.origin).pathname; } catch(e) {}
      return '<div class="offline-queue-item">' +
        '<div><span class="offline-queue-method">' + escHtml(record.method || 'POST') + '</span><span class="offline-queue-url">' + escHtml(path) + '</span></div>' +
        '<div class="offline-queue-time">' + new Date(record.timestamp || Date.now()).toLocaleString() + '</div>' +
      '</div>';
    }).join('');
  }

  window.addEventListener('online', function() {
    setTimeout(function() { refreshWithProbe(); }, 500);
  });
  window.addEventListener('offline', function() {
    state.online = false;
    state.probing = false;
    if (!offlineToastShown && window.BSDialog && BSDialog.toast) {
      offlineToastShown = true;
      BSDialog.toast('已离线，可继续访问已缓存内容，操作会进入待同步队列', 'warning', 5000);
    }
    refresh({ probe: false });
  });
  window.addEventListener('bs:pwa-status-change', renderPWA);
  window.addEventListener('bs:offline-queue-change', function() { refresh({ probe: false }); });
  window.addEventListener('bs:offline-queue-sync-start', function() { state.syncing = true; render(); });
  window.addEventListener('bs:offline-queue-sync-end', function() { state.syncing = false; refresh({ probe: false }); });

  document.addEventListener('DOMContentLoaded', function() {
    if (navigator.onLine === false && window.BSDialog && BSDialog.toast) {
      offlineToastShown = true;
      BSDialog.toast('当前处于离线状态', 'warning', 5000);
    }
    refresh({ probe: false });
  });

  window.BookStarkOfflineStatus = {
    refresh: refresh,
    probe: refreshWithProbe,
    open: function() {
      refreshWithProbe();
    },
    mount: function(target) {
      var container = typeof target === 'string' ? document.getElementById(target) : target;
      if (!container) return null;
      var panel = container.querySelector('.offline-status-popover');
      if (!panel) {
        panel = document.createElement('div');
        panel.className = 'offline-status-popover active';
        panel.innerHTML = statusPanelHTML(false);
        container.appendChild(panel);
      }
      bindView(panel);
      refresh({ probe: false });
      return panel;
    }
  };
})();
