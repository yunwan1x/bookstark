(function() {
  var state = {
    assetMode: window.__ASSET_PAGE_MODE__ || 'index',
    tab: window.__ASSET_PAGE_MODE__ === 'docker-host' ? 'docker' : ((window.__ASSET_PAGE_MODE__ === 'files-host' || window.__ASSET_PAGE_MODE__ === 'webdav-files') ? 'files' : 'ssh'),
    settingsTab: 'credentials',
    authMode: 'password',
    sessionTarget: null,
    socket: null,
    terminal: null,
    fitAddon: null,
    terminalMaximized: false,
    terminalStatus: '',
    sshHosts: [],
    containers: [],
    dockerResourceTab: 'containers',
    dockerNetworks: [],
    dockerNetworksLoading: false,
    dockerVolumes: [],
    dockerImages: [],
    dockerImagesLoading: false,
    selectedDockerHostId: window.__DOCKER_HOST_ID__ || '',
    selectedFilesHostId: window.__FILES_HOST_ID__ || '',
    selectedWebDAVServerId: window.__WEBDAV_SERVER_ID__ || '',
    webdavServers: [],
    files: [],
    filePath: '.',
    lastGoodFilePath: '.',
    editingFilePath: false,
    filePathInputValue: '.',
    fileListLimit: 0,
    fileListTruncated: false,
    loadingFiles: window.__ASSET_PAGE_MODE__ === 'files-host' || window.__ASSET_PAGE_MODE__ === 'webdav-files',
    fileEditorPath: '',
    fileEditorSaving: false,
    fileEditorLoadController: null,
    fileEditorLoadToken: 0,
    filePreviewPath: '',
    filePreviewKind: '',
    fileRename: null,
    dockerPendingById: {},
    dockerLogContainerId: '',
    dockerLogSource: null,
    dockerLogFollow: true,
    dockerLogText: '',
    terminalWriteQueue: [],
    terminalWriteQueueBytes: 0,
    terminalWriteScheduled: false,
    terminalWriteTruncated: false,
    credentials: [],
    credentialModalSource: '',
    credentialAuthMode: 'password',
    loadingSshHosts: true,
    loadingWebDAVServers: true,
    loadingCredentials: true,
    loadingDocker: window.__ASSET_PAGE_MODE__ === 'docker-host',
    loadingDockerNetworks: false,
    loadingDockerVolumes: false,
    loadingDockerImages: false,
    settings: {
      terminal_idle_timeout_seconds: 1800,
      terminal_scrollback_lines: 5000,
      credential_secret: ''
    }
  };
  var dockerLogFollowStorageKey = 'bookstark.asset.dockerLogFollow';
  var terminalWriteQueueLimit = 1024 * 1024;
  var terminalWriteFrameLimit = 64 * 1024;
  var floatingDropdown = null;

  function $(selector, root) {
    return (root || document).querySelector(selector);
  }

  function $$(selector, root) {
    return Array.prototype.slice.call((root || document).querySelectorAll(selector));
  }

  function runSubmitLocked(key, button, task) {
    if (window.BookStarkRequestLock) {
      return BookStarkRequestLock.run(key, task, button);
    }
    if (button && button.disabled) return null;
    if (button) button.disabled = true;
    return Promise.resolve().then(task).then(function(value) {
      if (button) button.disabled = false;
      return value;
    }, function(err) {
      if (button) button.disabled = false;
      throw err;
    });
  }

  function ensureDropdownPortal() {
    var portal = $('#assetDropdownPortal');
    if (!portal) {
      portal = document.createElement('div');
      portal.id = 'assetDropdownPortal';
      portal.className = 'asset-dropdown-portal';
      document.body.appendChild(portal);
    }
    return portal;
  }

  function resetFloatingDropdownStyles(dropdown) {
    if (!dropdown) return;
    dropdown.classList.remove('asset-floating-dropdown');
    dropdown.style.left = '';
    dropdown.style.top = '';
    dropdown.style.width = '';
    dropdown.style.maxHeight = '';
  }

  function closeFloatingDropdown(dropdown) {
    if (!floatingDropdown || (dropdown && floatingDropdown.dropdown !== dropdown)) {
      if (dropdown) {
        dropdown.classList.add('asset-hidden');
        resetFloatingDropdownStyles(dropdown);
      }
      return;
    }
    var active = floatingDropdown;
    floatingDropdown = null;
    active.dropdown.classList.add('asset-hidden');
    resetFloatingDropdownStyles(active.dropdown);
    if (active.trigger) active.trigger.setAttribute('aria-expanded', 'false');
    if (active.parent && active.parent.isConnected) {
      if (active.nextSibling && active.nextSibling.parentNode === active.parent) {
        active.parent.insertBefore(active.dropdown, active.nextSibling);
      } else {
        active.parent.appendChild(active.dropdown);
      }
    }
  }

  function positionFloatingDropdown() {
    if (!floatingDropdown) return;
    var dropdown = floatingDropdown.dropdown;
    var trigger = floatingDropdown.trigger;
    if (!dropdown || !trigger || !dropdown.isConnected || !trigger.isConnected) {
      closeFloatingDropdown();
      return;
    }
    var modal = trigger.closest('.asset-modal-backdrop');
    if (modal && !modal.classList.contains('open')) {
      closeFloatingDropdown();
      return;
    }

    var gap = 4;
    var margin = 8;
    var rect = trigger.getBoundingClientRect();
    var preferredMax = floatingDropdown.maxHeight || 220;
    var spaceBelow = window.innerHeight - rect.bottom - margin - gap;
    var spaceAbove = rect.top - margin - gap;
    var openUp = spaceBelow < Math.min(preferredMax, 160) && spaceAbove > spaceBelow;
    var available = openUp ? spaceAbove : spaceBelow;
    var maxHeight = Math.max(120, Math.min(preferredMax, available));
    var left = Math.max(margin, Math.min(rect.left, window.innerWidth - rect.width - margin));

    dropdown.style.width = Math.max(160, rect.width) + 'px';
    dropdown.style.maxHeight = maxHeight + 'px';
    dropdown.style.left = left + 'px';
    dropdown.style.top = '-9999px';

    var dropdownHeight = Math.min(dropdown.scrollHeight, maxHeight);
    var top = openUp ? rect.top - gap - dropdownHeight : rect.bottom + gap;
    top = Math.max(margin, Math.min(top, window.innerHeight - dropdownHeight - margin));
    dropdown.style.top = top + 'px';
  }

  function openFloatingDropdown(dropdown, trigger, options) {
    if (!dropdown || !trigger) return;
    if (floatingDropdown && floatingDropdown.dropdown !== dropdown) closeFloatingDropdown();
    if (!floatingDropdown || floatingDropdown.dropdown !== dropdown) {
      floatingDropdown = {
        dropdown: dropdown,
        trigger: trigger,
        parent: dropdown.parentNode,
        nextSibling: dropdown.nextSibling,
        maxHeight: options && options.maxHeight ? options.maxHeight : 220
      };
    } else {
      floatingDropdown.trigger = trigger;
      floatingDropdown.maxHeight = options && options.maxHeight ? options.maxHeight : floatingDropdown.maxHeight;
    }
    ensureDropdownPortal().appendChild(dropdown);
    dropdown.classList.add('asset-floating-dropdown');
    dropdown.classList.remove('asset-hidden');
    trigger.setAttribute('aria-expanded', 'true');
    positionFloatingDropdown();
  }

  function dropdownIsOpen(dropdown) {
    return !!(dropdown && !dropdown.classList.contains('asset-hidden'));
  }

  function dropdownKeyboardItems(dropdown, selector) {
    if (!dropdown) return [];
    return $$(selector, dropdown).filter(function(item) {
      return !item.disabled && item.getAttribute('aria-disabled') !== 'true' && item.offsetParent !== null;
    });
  }

  function setDropdownActiveItem(items, activeItem) {
    items.forEach(function(item) {
      var active = item === activeItem;
      item.classList.toggle('active', active);
      if (item.getAttribute('role') === 'option') {
        item.setAttribute('aria-selected', active ? 'true' : 'false');
      }
    });
  }

  function focusDropdownItem(dropdown, selector, index) {
    var items = dropdownKeyboardItems(dropdown, selector);
    if (!items.length) return null;
    var next = (index + items.length) % items.length;
    var item = items[next];
    setDropdownActiveItem(items, item);
    item.focus();
    item.scrollIntoView({ block: 'nearest' });
    return item;
  }

  function moveDropdownFocus(dropdown, selector, direction) {
    var items = dropdownKeyboardItems(dropdown, selector);
    if (!items.length) return null;
    var index = items.indexOf(document.activeElement);
    if (index < 0) {
      index = items.findIndex(function(item) { return item.classList.contains('active'); });
    }
    if (index < 0) index = direction > 0 ? -1 : 0;
    return focusDropdownItem(dropdown, selector, index + direction);
  }

  function clickDropdownActiveItem(dropdown, selector) {
    var items = dropdownKeyboardItems(dropdown, selector);
    if (!items.length) return false;
    var item = items.indexOf(document.activeElement) >= 0
      ? document.activeElement
      : items.find(function(node) { return node.classList.contains('active'); }) || items[0];
    item.click();
    return true;
  }

  function t(key) {
    return window.__ ? window.__(key) : key;
  }

  function format(key, values) {
    var text = t(key);
    Object.keys(values || {}).forEach(function(name) {
      text = text.replace(new RegExp('\\{' + name + '\\}', 'g'), values[name]);
    });
    return text;
  }

  var esc = typeof escAttr === 'function' ? escAttr : function(value) {
    return String(value == null ? '' : value)
      .replace(/&/g, '&amp;')
      .replace(/"/g, '&quot;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/'/g, '&#39;');
  };

  function apiJSON(url, options) {
    function responseError(res) {
      var keys = {401: 'asset.error.session', 403: 'asset.error.forbidden', 504: 'asset.error.timeout'};
      return new Error(t(keys[res.status] || 'asset.error.response'));
    }
    function serverMessage(data) {
      var message = data.message || data.error;
      if (typeof message !== 'string') return t('asset.error.request');
      var sshKeys = {
        '认证失败': 'asset.error.ssh_auth',
        '私钥解析失败': 'asset.error.ssh_key',
        '私钥需要密码': 'asset.error.ssh_key_password',
        '连接超时': 'asset.error.timeout',
        'SSH 连接失败': 'asset.error.ssh_connect'
      };
      return sshKeys[message] ? t(sshKeys[message]) : message;
    }
    return csrfFetch(url, options || {}).then(function(res) {
      return res.json().catch(function(err) {
        console.warn('Asset API returned invalid JSON:', res.status, err);
        throw responseError(res);
      }).then(function(data) {
        if (!data || typeof data !== 'object' || Array.isArray(data)) {
          throw responseError(res);
        }
        if (typeof data.code !== 'number' && typeof data.message !== 'string' && typeof data.error !== 'string') {
          throw responseError(res);
        }
        if (!res.ok || (typeof data.code === 'number' && data.code !== 0)) {
          throw new Error(serverMessage(data));
        }
        if (typeof data.code !== 'number') {
          throw responseError(res);
        }
        if (typeof handleApiResponse === 'function') {
          data = handleApiResponse(data);
        } else if (data.code !== 0) {
          throw new Error(data.message || data.error || t('asset.error.request'));
        }
        return data.data;
      });
    }, function(err) {
      if (err && err.name === 'AbortError') throw err;
      console.warn('Asset API request failed:', err);
      throw new Error(t('asset.error.network'));
    });
  }

  function loadData() {
    if (state.assetMode === 'docker-host' || state.assetMode === 'files-host' || state.assetMode === 'webdav-files') {
      state.loadingSshHosts = true;
      state.loadingWebDAVServers = true;
      state.loadingDocker = !!state.selectedDockerHostId;
      state.loadingFiles = !!(state.selectedFilesHostId || state.selectedWebDAVServerId);
      renderAll();
      var listURL = state.assetMode === 'webdav-files' ? '/api/admin/assets/webdav-servers' : '/api/admin/assets/ssh-hosts';
      return apiJSON(listURL).then(function(items) {
        if (state.assetMode === 'webdav-files') {
          state.webdavServers = items || [];
          state.loadingWebDAVServers = false;
          state.loadingSshHosts = false;
          if (state.selectedWebDAVServerId && !state.webdavServers.some(function(server) { return String(server.id) === String(state.selectedWebDAVServerId); })) {
            state.selectedWebDAVServerId = '';
            state.files = [];
            state.loadingFiles = false;
          }
        } else {
          state.sshHosts = items || [];
          state.loadingSshHosts = false;
          state.loadingWebDAVServers = false;
        }
        if (state.selectedDockerHostId && !state.sshHosts.some(function(host) { return String(host.id) === String(state.selectedDockerHostId); })) {
          state.selectedDockerHostId = '';
          state.dockerPendingById = {};
          state.containers = [];
          state.loadingDocker = false;
        }
        if (state.selectedFilesHostId && !state.sshHosts.some(function(host) { return String(host.id) === String(state.selectedFilesHostId); })) {
          state.selectedFilesHostId = '';
          state.files = [];
          state.loadingFiles = false;
        }
        renderAll();
        if (state.selectedDockerHostId) {
          return loadDockerContainers(true);
        }
        if (selectedFileTarget()) {
          return loadFiles(true);
        }
      }).catch(function(err) {
        state.loadingSshHosts = false;
        state.loadingWebDAVServers = false;
        state.loadingDocker = false;
        state.loadingFiles = false;
        renderAll();
        toast(err.message || t('asset.error.load'));
      });
    }

    state.loadingCredentials = true;
    state.loadingSshHosts = true;
    state.loadingWebDAVServers = true;
    state.loadingDocker = !!state.selectedDockerHostId;
    renderAll();
    return Promise.all([
      apiJSON('/api/admin/assets/credentials'),
      apiJSON('/api/admin/assets/ssh-hosts'),
      apiJSON('/api/admin/assets/webdav-servers'),
      apiJSON('/api/admin/assets/settings')
    ]).then(function(results) {
      state.credentials = results[0] || [];
      state.sshHosts = results[1] || [];
      state.webdavServers = results[2] || [];
      state.settings = results[3] || state.settings;
      state.loadingCredentials = false;
      state.loadingSshHosts = false;
      state.loadingWebDAVServers = false;
      if (state.selectedDockerHostId && !state.sshHosts.some(function(host) { return String(host.id) === String(state.selectedDockerHostId); })) {
        state.selectedDockerHostId = '';
        state.dockerPendingById = {};
        state.containers = [];
        state.loadingDocker = false;
      }
      applySettings();
      renderAll();
      if (state.selectedDockerHostId) {
        return loadDockerContainers(true);
      }
    }).catch(function(err) {
      state.loadingCredentials = false;
      state.loadingSshHosts = false;
      state.loadingWebDAVServers = false;
      state.loadingDocker = false;
      renderAll();
      toast(err.message || t('asset.error.load'));
    });
  }

  function applySettings() {
    $('#settingIdle').value = String(state.settings.terminal_idle_timeout_seconds || 1800);
    $('#settingScrollback').value = String(normalizeTerminalScrollback(state.settings.terminal_scrollback_lines));
    $('#settingCredentialSecret').value = state.settings.credential_secret || '';
  }

  function normalizeTerminalScrollback(value) {
    var lines = Number(value || 5000);
    if (!Number.isFinite(lines)) lines = 5000;
    lines = Math.floor(lines);
    if (lines < 500 || lines > 50000) lines = 5000;
    return lines;
  }

  function hostName(id) {
    var host = state.sshHosts.find(function(item) { return String(item.id) === String(id); });
    return host ? host.name : t('asset.host.unbound');
  }

  function selectedDockerHost() {
    return state.sshHosts.find(function(item) { return String(item.id) === String(state.selectedDockerHostId); }) || null;
  }

  function selectedFilesHost() {
    return state.sshHosts.find(function(item) { return String(item.id) === String(state.selectedFilesHostId); }) || null;
  }

  function selectedWebDAVServer() {
    return state.webdavServers.find(function(item) { return String(item.id) === String(state.selectedWebDAVServerId); }) || null;
  }

  function selectedFileTarget() {
    if (state.assetMode === 'webdav-files' || state.selectedWebDAVServerId) return selectedWebDAVServer();
    return selectedFilesHost();
  }

  function fileAPIBase() {
    if (state.assetMode === 'webdav-files' || state.selectedWebDAVServerId) {
      return state.selectedWebDAVServerId ? '/api/admin/assets/webdav-servers/' + encodeURIComponent(state.selectedWebDAVServerId) + '/files' : '';
    }
    return state.selectedFilesHostId ? '/api/admin/assets/ssh-hosts/' + encodeURIComponent(state.selectedFilesHostId) + '/files' : '';
  }

  function statusPill(status) {
    var text = {
      unknown: t('asset.status.unknown'),
      online: t('asset.status.online'),
      offline: t('asset.status.offline'),
      running: t('asset.status.running'),
      stopped: t('asset.status.stopped')
    }[status] || esc(status);
    var tone = status === 'online' || status === 'running' ? 'ok' : status === 'unknown' ? '' : 'bad';
    return '<span class="asset-pill ' + tone + '"><span class="asset-dot"></span>' + text + '</span>';
  }

  function actionButton(label, icon, action, id, tone, attrs) {
    var safeLabel = esc(label);
    var extraAttrs = attrs ? ' ' + attrs : '';
    return '<button class="row-action ' + (tone === 'danger' ? 'del' : '') + '" data-action="' + action + '" data-id="' + esc(id) + '" title="' + safeLabel + '" aria-label="' + safeLabel + '"' + extraAttrs + '><i class="fa-solid ' + icon + '"></i></button>';
  }

  function dockerPortLabel(port) {
    if (!port) return '-';
    var container = port.container_port ? port.container_port : (port.raw || '-');
    if (port.published && port.host_port) {
      var host = port.host_ip ? port.host_ip + ':' + port.host_port : port.host_port;
      return host + ' -> ' + container;
    }
    return container;
  }

  function dockerPortsTitle(item) {
    var details = Array.isArray(item.ports_detail) ? item.ports_detail : [];
    if (details.length) {
      return details.map(dockerPortLabel).join('\n');
    }
    return item.ports || '-';
  }

  function dockerPortsCell(item) {
    var details = Array.isArray(item.ports_detail) ? item.ports_detail : [];
    var title = esc(dockerPortsTitle(item));
    if (!details.length) {
      return item.ports
        ? '<span class="asset-port-chip asset-port-chip-raw" title="' + title + '">' + esc(item.ports) + '</span>'
        : '<span class="asset-sub">-</span>';
    }
    return '<div class="asset-port-chip-list">' + details.map(function(port) {
      return dockerPortChip(port, title);
    }).join('') + '</div>';
  }

  function dockerPortChip(port, title) {
    var label = dockerPortLabel(port);
    var protocol = port && port.protocol ? port.protocol : '';
    return '<span class="asset-port-chip" title="' + title + '">' +
      esc(label) +
      (protocol ? '<small>' + esc(protocol) + '</small>' : '') +
    '</span>';
  }

  function dockerActionButton(id) {
    var safeLabel = esc(t('asset.action.docker'));
    return '<button class="row-action docker-action" data-action="docker-ssh" data-id="' + esc(id) + '" title="' + safeLabel + '" aria-label="' + safeLabel + '">' +
      '<img src="/static/docker.svg" alt="" aria-hidden="true">' +
    '</button>';
  }

  function filesActionButton(id) {
    return actionButton(t('asset.action.files'), 'fa-folder-tree', 'files-ssh', id);
  }

  function assetFilesHref(type, id) {
    if (type === 'webdav' && String(id) === 'local') return '/webdav';
    var base = type === 'webdav' ? '/admin/assets/webdav-servers/' : '/admin/assets/ssh-hosts/';
    return base + encodeURIComponent(id) + '/files';
  }

  function assetFilesTitleLink(type, item) {
    return '<a class="asset-name-link" href="' + esc(assetFilesHref(type, item.id)) + '"><strong>' + esc(item.name) + '</strong></a>';
  }

  function actionMenuItem(label, icon, action, id, tone, attrs) {
    var extraAttrs = attrs || '';
    return '<button class="bs-action-menu-item ' + (tone === 'danger' ? 'bs-action-menu-item-danger' : '') + '" data-action="' + action + '" data-id="' + esc(id) + '" type="button" ' + extraAttrs + '>' +
      '<i class="fa-solid ' + icon + '"></i>' + esc(label) +
    '</button>';
  }

  function dockerActionMenu(item) {
    var safeLabel = esc(t('asset.action.menu'));
    var id = item.id;
    var pendingAction = dockerPendingAction(id);
    var rowPending = !!pendingAction;
    var triggerIcon = rowPending && dockerPendingControl(pendingAction) === 'menu' ? 'fa-spinner fa-spin' : 'fa-ellipsis';
    var triggerAttrs = rowPending ? ' disabled aria-disabled="true"' : '';
    return '<div class="bs-action-dropdown asset-row-menu">' +
      '<button class="bs-action-dd-btn asset-row-menu-btn" type="button" data-bs-action-dropdown-toggle aria-haspopup="true" aria-expanded="false" title="' + safeLabel + '" aria-label="' + safeLabel + '"' + triggerAttrs + '>' +
        '<i class="fa-solid ' + triggerIcon + '"></i>' +
      '</button>' +
      '<div class="bs-action-dd-menu asset-row-menu-panel">' +
        dockerLifecycleMenuItems(item, rowPending) +
        actionMenuItem(t('asset.action.inspect'), 'fa-magnifying-glass-chart', 'inspect-docker', id, '', rowPending ? 'disabled aria-disabled="true"' : '') +
        '<div class="bs-action-menu-sep"></div>' +
        restartPolicySubmenu(id, rowPending) +
        '<div class="bs-action-menu-sep"></div>' +
        actionMenuItem(t('asset.action.delete'), 'fa-trash-can', 'delete-docker', id, 'danger', rowPending ? 'disabled aria-disabled="true"' : '') +
      '</div>' +
    '</div>';
  }

  function restartPolicySubmenu(id, disabled) {
    var disabledAttrs = disabled ? ' disabled aria-disabled="true"' : '';
    return '<div class="bs-action-submenu">' +
      '<button class="bs-action-menu-item bs-action-submenu-trigger" type="button" data-bs-action-submenu-toggle aria-haspopup="true" aria-expanded="false"' + disabledAttrs + '>' +
        '<i class="fa-solid fa-rotate"></i>' + esc(t('asset.restart_policy.placeholder')) + '<i class="fa-solid fa-chevron-right bs-action-submenu-arrow"></i>' +
      '</button>' +
      '<div class="bs-action-submenu-panel">' +
        actionMenuItem(t('asset.restart_policy.no'), 'fa-ban', 'restart-policy-docker', id, '', 'data-policy="no"' + (disabled ? ' disabled aria-disabled="true"' : '')) +
        actionMenuItem(t('asset.restart_policy.always'), 'fa-arrows-rotate', 'restart-policy-docker', id, '', 'data-policy="always"' + (disabled ? ' disabled aria-disabled="true"' : '')) +
        actionMenuItem(t('asset.restart_policy.unless_stopped'), 'fa-circle-pause', 'restart-policy-docker', id, '', 'data-policy="unless-stopped"' + (disabled ? ' disabled aria-disabled="true"' : '')) +
        actionMenuItem(t('asset.restart_policy.on_failure'), 'fa-triangle-exclamation', 'restart-policy-docker', id, '', 'data-policy="on-failure"' + (disabled ? ' disabled aria-disabled="true"' : '')) +
      '</div>' +
    '</div>';
  }

  function dockerMobileActions(item) {
    var id = item.id;
    var pendingAction = dockerPendingAction(id);
    var rowPending = !!pendingAction;
    var logsPending = pendingAction === 'logs-docker';
    var logsIcon = logsPending ? 'fa-spinner fa-spin' : 'fa-clipboard-list';
    var actionAttrs = rowPending ? 'disabled aria-disabled="true"' : '';
    var policyAttrs = rowPending ? ' disabled aria-disabled="true"' : '';
    var lifecycle = item.status === 'running'
      ? actionButton(t('asset.action.stop'), 'fa-stop', 'stop-docker', id, '', actionAttrs) +
        actionButton(t('asset.action.restart'), 'fa-rotate', 'restart-docker', id, '', actionAttrs)
      : actionButton(t('asset.action.start'), 'fa-play', 'start-docker', id, '', actionAttrs);

    return '<div class="asset-actions-mobile">' +
      '<div class="asset-actions-mobile-buttons">' +
        actionButton(t('asset.action.logs'), logsIcon, 'logs-docker', id, '', logsPending ? 'disabled aria-disabled="true" data-loading="true"' : actionAttrs) +
        actionButton(t('asset.action.session'), 'fa-terminal', 'session-docker', id, '', actionAttrs) +
        lifecycle +
        actionButton(t('asset.action.inspect'), 'fa-magnifying-glass-chart', 'inspect-docker', id, '', actionAttrs) +
        actionButton(t('asset.action.delete'), 'fa-trash-can', 'delete-docker', id, 'danger', actionAttrs) +
      '</div>' +
      '<label class="asset-restart-policy-compact">' +
        '<span>' + esc(t('asset.restart_policy.placeholder')) + '</span>' +
        '<select data-id="' + esc(id) + '" aria-label="' + esc(t('asset.restart_policy.aria')) + '"' + policyAttrs + '>' +
          '<option value="">' + esc(t('asset.restart_policy.placeholder')) + '</option>' +
          '<option value="no">' + esc(t('asset.restart_policy.no')) + '</option>' +
          '<option value="always">' + esc(t('asset.restart_policy.always')) + '</option>' +
          '<option value="unless-stopped">' + esc(t('asset.restart_policy.unless_stopped')) + '</option>' +
          '<option value="on-failure">' + esc(t('asset.restart_policy.on_failure')) + '</option>' +
        '</select>' +
      '</label>' +
    '</div>';
  }

  function dockerPendingAction(id) {
    return state.dockerPendingById[String(id)] || '';
  }

  function setDockerPending(id, action) {
    state.dockerPendingById[String(id)] = action;
    if (window.BSActionDropdown) window.BSActionDropdown.closeAll();
    renderDocker();
  }

  function clearDockerPending(id) {
    delete state.dockerPendingById[String(id)];
    renderDocker();
  }

  function dockerPendingControl(action) {
    return action === 'logs-docker' ? 'logs' : 'menu';
  }

  function runDockerRowAction(id, action, request) {
    var containerId = String(id || '');
    if (!containerId || dockerPendingAction(containerId)) return Promise.resolve();
    setDockerPending(containerId, action);
    return Promise.resolve()
      .then(request)
      .finally(function() {
        clearDockerPending(containerId);
      });
  }

  function toast(message, type, duration) {
    if (window.BSDialog && typeof window.BSDialog.toast === 'function') {
      window.BSDialog.toast(message, type || 'info', duration || 2000);
    }
  }

  function promptValue(message, defaultValue) {
    if (window.BSDialog && typeof window.BSDialog.prompt2 === 'function') {
      return window.BSDialog.prompt2(message, defaultValue || '');
    }
    return Promise.resolve(window.prompt(message, defaultValue || ''));
  }

  function loadDockerLogFollowPreference() {
    try {
      var value = localStorage.getItem(dockerLogFollowStorageKey);
      return value == null ? true : value === '1';
    } catch (err) {
      return true;
    }
  }

  function saveDockerLogFollowPreference(enabled) {
    try {
      localStorage.setItem(dockerLogFollowStorageKey, enabled ? '1' : '0');
    } catch (err) {
      // Ignore storage failures; the current modal state is still usable.
    }
  }

  function setTab(tab, opts) {
    opts = opts || {};
    if (opts.updateUrl !== false && window.BookStarkTabURL && state.assetMode !== 'docker-host' && state.assetMode !== 'files-host' && state.assetMode !== 'webdav-files') {
      window.BookStarkTabURL.set('tab', tab);
    }
    state.tab = tab;
    $$('.asset-tab').forEach(function(btn) {
      var active = btn.dataset.tab === tab;
      btn.classList.toggle('active', active);
      btn.setAttribute('aria-selected', active ? 'true' : 'false');
    });
    $$('.asset-tab-panel').forEach(function(panel) {
      panel.classList.toggle('active', panel.id === 'panel-' + tab);
    });
    updateMobileFab();
  }

  function updateMobileFab() {
    var fab = $('#assetMobileFab');
    if (!fab) return;
    if (state.assetMode === 'docker-host') {
      fab.classList.remove('asset-hidden');
      var label = state.dockerResourceTab === 'networks' ? t('asset.docker.network.create') :
        state.dockerResourceTab === 'volumes' ? t('asset.docker.volume.create') :
        state.dockerResourceTab === 'images' ? t('asset.docker.image.pull') :
        t('asset.docker.create');
      fab.setAttribute('aria-label', label);
      return;
    }
    if (state.assetMode === 'files-host' || state.assetMode === 'webdav-files') {
      fab.classList.add('asset-hidden');
      return;
    }
    if (state.tab === 'ssh') {
      fab.classList.remove('asset-hidden');
      fab.setAttribute('aria-label', t('asset.ssh.add'));
      return;
    }
    if (state.tab === 'webdav') {
      fab.classList.remove('asset-hidden');
      fab.setAttribute('aria-label', t('asset.webdav.add'));
      return;
    }
    if (state.tab === 'settings' && state.settingsTab === 'credentials') {
      fab.classList.remove('asset-hidden');
      fab.setAttribute('aria-label', t('asset.credentials.add'));
      return;
    }
    fab.classList.add('asset-hidden');
  }

  function handleMobileFab() {
    if (state.assetMode === 'docker-host') {
      if (state.dockerResourceTab === 'networks') createDockerNetwork();
      else if (state.dockerResourceTab === 'volumes') createDockerVolume();
      else if (state.dockerResourceTab === 'images') pullDockerImage();
      else openDockerCreateForm();
      return;
    }
    if (state.tab === 'ssh') {
      openSshForm();
    } else if (state.tab === 'webdav') {
      openWebDAVForm();
    } else if (state.tab === 'settings' && state.settingsTab === 'credentials') {
      openCredentialForm();
    }
  }

  function selectedStatuses(type) {
    var inputs = $$('[data-status-filter="' + type + '"]');
    if (inputs.length === 0) return null;
    return inputs.filter(function(input) { return input.checked; }).map(function(input) {
      return input.value;
    });
  }

  function tableSkeletonRows(cols, rows) {
    var html = '';
    for (var i = 0; i < rows; i++) {
      html += '<tr class="asset-skeleton-row">';
      for (var c = 0; c < cols; c++) {
        var width = c === 0 ? 72 : c === cols - 1 ? 42 : 56 + ((i + c) % 3) * 12;
        html += '<td><span class="asset-skeleton-line" style="width:' + width + '%"></span></td>';
      }
      html += '</tr>';
    }
    return html;
  }

  function renderSsh() {
    if (!$('#sshRows')) return;
    if (state.loadingSshHosts) {
      $('#sshRows').innerHTML = tableSkeletonRows(6, 5);
      return;
    }
    var q = $('#sshSearch').value.trim().toLowerCase();
    var statuses = selectedStatuses('ssh');
    var rows = state.sshHosts.filter(function(item) {
      var hay = [item.name, item.host, item.username, item.credential_name, item.auth_type, item.status].join(' ').toLowerCase();
      return (!q || hay.indexOf(q) >= 0) && (!statuses || statuses.indexOf(item.status) >= 0);
    });
    $('#sshRows').innerHTML = rows.length ? rows.map(function(item) {
      return '<tr>' +
        '<td data-label="' + esc(t('asset.table.name')) + '"><div class="asset-name-cell">' + assetFilesTitleLink('ssh', item) + '</div></td>' +
        '<td data-label="' + esc(t('asset.table.address')) + '" class="asset-mono">' + esc(item.host) + ':' + esc(item.port) + '</td>' +
        '<td data-label="' + esc(t('asset.table.user')) + '"><div class="asset-name-cell"><strong>' + esc(item.username) + '</strong><span class="asset-sub">' + esc(item.credential_name || '-') + '</span></div></td>' +
        '<td data-label="' + esc(t('asset.table.auth')) + '"><span class="asset-pill">' + authLabel(item.auth_type) + '</span></td>' +
        '<td data-label="' + esc(t('asset.table.status')) + '">' + statusPill(item.status) + '</td>' +
        '<td class="asset-right"><div class="asset-actions">' +
          dockerActionButton(item.id) +
          filesActionButton(item.id) +
          actionButton(t('asset.action.test'), 'fa-plug-circle-check', 'test-ssh', item.id) +
          actionButton(t('asset.action.session'), 'fa-terminal', 'session-ssh', item.id) +
          actionButton(t('asset.action.edit'), 'fa-pen-to-square', 'edit-ssh', item.id) +
          actionButton(t('asset.action.delete'), 'fa-trash-can', 'delete-ssh', item.id, 'danger') +
        '</div></td>' +
      '</tr>';
    }).join('') : '<tr class="asset-empty-row"><td colspan="6"><div class="asset-sub">' + t('asset.empty.ssh') + '</div></td></tr>';
  }

  function renderWebDAV() {
    if (!$('#webdavRows')) return;
    if (state.loadingWebDAVServers) {
      $('#webdavRows').innerHTML = tableSkeletonRows(6, 4);
      return;
    }
    var q = $('#webdavSearch').value.trim().toLowerCase();
    var statuses = selectedStatuses('webdav');
    var rows = state.webdavServers.filter(function(item) {
      var hay = [item.name, item.url, item.root_path, item.credential_name, item.username, item.status].join(' ').toLowerCase();
      return (!q || hay.indexOf(q) >= 0) && (!statuses || statuses.indexOf(item.status) >= 0);
    });
    $('#webdavRows').innerHTML = rows.length ? rows.map(function(item) {
      var actions = item.built_in
        ? actionButton(t('asset.action.files'), 'fa-folder-tree', 'files-webdav', item.id)
        : actionButton(t('asset.action.files'), 'fa-folder-tree', 'files-webdav', item.id) +
          actionButton(t('asset.action.test'), 'fa-plug-circle-check', 'test-webdav', item.id) +
          actionButton(t('asset.action.edit'), 'fa-pen-to-square', 'edit-webdav', item.id) +
          actionButton(t('asset.action.delete'), 'fa-trash-can', 'delete-webdav', item.id, 'danger');
      return '<tr>' +
        '<td data-label="' + esc(t('asset.table.name')) + '"><div class="asset-name-cell">' + assetFilesTitleLink('webdav', item) + '</div></td>' +
        '<td data-label="URL"><div class="asset-cell-clip asset-mono" title="' + esc(item.url || '-') + '">' + esc(item.url || '-') + '</div></td>' +
        '<td data-label="' + esc(t('asset.webdav.root_path')) + '" class="asset-mono">' + esc(item.root_path || '/') + '</td>' +
        '<td data-label="' + esc(t('asset.field.credential')) + '"><div class="asset-name-cell"><strong>' + esc(item.credential_name || '-') + '</strong><span class="asset-sub">' + esc(item.username || '-') + '</span></div></td>' +
        '<td data-label="' + esc(t('asset.table.status')) + '">' + statusPill(item.status) + '</td>' +
        '<td class="asset-right"><div class="asset-actions">' +
          actions +
        '</div></td>' +
      '</tr>';
    }).join('') : '<tr class="asset-empty-row"><td colspan="6"><div class="asset-sub">' + t('asset.empty.webdav') + '</div></td></tr>';
  }

  function credentialLabel(cred) {
    return cred.name + ' · ' + cred.username + ' · ' + authLabel(cred.auth_type);
  }

  function selectedCredential(id) {
    return state.credentials.find(function(cred) {
      return String(cred.id) === String(id);
    });
  }

  function filterCredentials(query) {
    var q = (query || '').trim().toLowerCase();
    if (!q) return state.credentials.slice();
    return state.credentials.filter(function(cred) {
      return [cred.name, cred.username, authLabel(cred.auth_type), credentialLabel(cred)].join(' ').toLowerCase().indexOf(q) >= 0;
    });
  }

  function hideCredentialDropdown() {
    var dropdown = $('#sshCredentialDropdown');
    var input = $('#sshCredentialSearch');
    if (dropdown) closeFloatingDropdown(dropdown);
    if (input) input.setAttribute('aria-expanded', 'false');
  }

  function renderCredentialPicker(selectedID, query, showDropdown) {
    var hidden = $('#sshCredential');
    var input = $('#sshCredentialSearch');
    var dropdown = $('#sshCredentialDropdown');
    if (!hidden || !input || !dropdown) return;

    var nextID = selectedID ? String(selectedID) : hidden.value;
    if (!selectedCredential(nextID)) {
      nextID = state.credentials[0] ? String(state.credentials[0].id) : '';
    }
    hidden.value = nextID;

    var selected = selectedCredential(nextID);
    if (query == null) input.value = selected ? credentialLabel(selected) : '';

    var matches = filterCredentials(query == null ? '' : query);
    var optionsHtml = matches.length ? matches.map(function(cred) {
      var active = String(cred.id) === String(hidden.value) ? ' active' : '';
      return '<button type="button" class="asset-combobox-option' + active + '" role="option" data-id="' + esc(cred.id) + '" aria-selected="' + (active ? 'true' : 'false') + '">' +
        '<span>' + esc(cred.name) + '</span>' +
        '<small>' + esc(cred.username) + ' · ' + esc(authLabel(cred.auth_type)) + '</small>' +
      '</button>';
    }).join('') : '<div class="asset-combobox-empty">' + esc(t(query ? 'asset.credentials.no_match' : 'asset.credentials.empty')) + '</div>';
    dropdown.innerHTML = optionsHtml +
      '<button type="button" class="asset-combobox-create" data-action="create-credential">' +
        '<i class="fa-solid fa-plus"></i><span>' + esc(t('asset.credentials.create_from_picker')) + '</span>' +
      '</button>';

    if (showDropdown) {
      openFloatingDropdown(dropdown, input, { maxHeight: 210 });
    } else {
      closeFloatingDropdown(dropdown);
    }
    input.setAttribute('aria-expanded', showDropdown ? 'true' : 'false');
  }

  function selectCredential(id) {
    var cred = selectedCredential(id);
    if (!cred) return;
    $('#sshCredential').value = String(cred.id);
    $('#sshCredentialSearch').value = credentialLabel(cred);
    hideCredentialDropdown();
  }

  function webDAVCredentials() {
    return state.credentials.filter(function(cred) { return cred.auth_type === 'password'; });
  }

  function selectedWebDAVCredential(id) {
    return webDAVCredentials().find(function(cred) {
      return String(cred.id) === String(id);
    });
  }

  function filterWebDAVCredentials(query) {
    var q = (query || '').trim().toLowerCase();
    var credentials = webDAVCredentials();
    if (!q) return credentials.slice();
    return credentials.filter(function(cred) {
      return [cred.name, cred.username, authLabel(cred.auth_type), credentialLabel(cred)].join(' ').toLowerCase().indexOf(q) >= 0;
    });
  }

  function hideWebDAVCredentialDropdown() {
    var dropdown = $('#webdavCredentialDropdown');
    var input = $('#webdavCredentialSearch');
    if (dropdown) closeFloatingDropdown(dropdown);
    if (input) input.setAttribute('aria-expanded', 'false');
  }

  function renderWebDAVCredentialPicker(selectedID, query, showDropdown) {
    var hidden = $('#webdavCredential');
    var input = $('#webdavCredentialSearch');
    var dropdown = $('#webdavCredentialDropdown');
    if (!hidden || !input || !dropdown) return;

    var nextID = selectedID ? String(selectedID) : hidden.value;
    if (!selectedWebDAVCredential(nextID)) {
      nextID = webDAVCredentials()[0] ? String(webDAVCredentials()[0].id) : '';
    }
    hidden.value = nextID;

    var selected = selectedWebDAVCredential(nextID);
    if (query == null) input.value = selected ? credentialLabel(selected) : '';

    var matches = filterWebDAVCredentials(query == null ? '' : query);
    var optionsHtml = matches.length ? matches.map(function(cred) {
      var active = String(cred.id) === String(hidden.value) ? ' active' : '';
      return '<button type="button" class="asset-combobox-option' + active + '" role="option" data-id="' + esc(cred.id) + '" aria-selected="' + (active ? 'true' : 'false') + '">' +
        '<span>' + esc(cred.name) + '</span>' +
        '<small>' + esc(cred.username) + ' · ' + esc(authLabel(cred.auth_type)) + '</small>' +
      '</button>';
    }).join('') : '<div class="asset-combobox-empty">' + esc(t(query ? 'asset.credentials.no_match' : 'asset.credentials.empty')) + '</div>';
    dropdown.innerHTML = optionsHtml +
      '<button type="button" class="asset-combobox-create" data-action="create-credential">' +
        '<i class="fa-solid fa-plus"></i><span>' + esc(t('asset.credentials.create_from_picker')) + '</span>' +
      '</button>';

    if (showDropdown) {
      openFloatingDropdown(dropdown, input, { maxHeight: 210 });
    } else {
      closeFloatingDropdown(dropdown);
    }
    input.setAttribute('aria-expanded', showDropdown ? 'true' : 'false');
  }

  function selectWebDAVCredential(id) {
    var cred = selectedWebDAVCredential(id);
    if (!cred) return;
    $('#webdavCredential').value = String(cred.id);
    $('#webdavCredentialSearch').value = credentialLabel(cred);
    hideWebDAVCredentialDropdown();
  }

  function authLabel(authType) {
    return authType === 'key' ? 'Private Key' : t('asset.auth.password');
  }

  function renderCredentials() {
    if (!$('#credentialRows')) return;
    if (state.loadingCredentials) {
      $('#credentialRows').innerHTML = tableSkeletonRows(4, 4);
      return;
    }
    $('#credentialRows').innerHTML = state.credentials.length ? state.credentials.map(function(item) {
      return '<tr>' +
        '<td data-label="' + esc(t('asset.table.name')) + '"><div class="asset-name-cell"><strong>' + esc(item.name) + '</strong></div></td>' +
        '<td data-label="' + esc(t('asset.table.user')) + '">' + esc(item.username) + '</td>' +
        '<td data-label="' + esc(t('asset.table.auth')) + '"><span class="asset-pill">' + authLabel(item.auth_type) + '</span></td>' +
        '<td class="asset-right"><div class="asset-actions">' +
          actionButton(t('asset.action.edit'), 'fa-pen-to-square', 'edit-credential', item.id) +
          actionButton(t('asset.action.delete'), 'fa-trash-can', 'delete-credential', item.id, 'danger') +
        '</div></td>' +
      '</tr>';
    }).join('') : '<tr class="asset-empty-row"><td colspan="4"><div class="asset-sub">' + t('asset.credentials.empty') + '</div></td></tr>';
  }

  function renderDocker() {
    var host = selectedDockerHost();
    updateDockerSearchControl();
    var q = $('#dockerSearch').value.trim().toLowerCase();
    var statuses = selectedStatuses('docker');
    var pageTitle = $('#dockerPageTitle');
    if (pageTitle) {
      pageTitle.textContent = host ? format('asset.docker.host.title', { name: host.name }) : t('asset.tab.docker');
    }
    $('#refreshDockerBtn').disabled = !host;
    $('#addDockerContainerBtn').disabled = !host;
    $('#addDockerNetworkBtn').disabled = !host;
    $('#addDockerVolumeBtn').disabled = !host;
    $('#pullDockerImageBtn').disabled = !host;
    $('#pruneDockerBtn').disabled = !host;
    $('#dockerStatusFilter').classList.toggle('asset-hidden', state.dockerResourceTab !== 'containers');
    $('#addDockerContainerBtn').classList.toggle('asset-hidden', state.dockerResourceTab !== 'containers');
    $('#addDockerNetworkBtn').classList.toggle('asset-hidden', state.dockerResourceTab !== 'networks');
    $('#addDockerVolumeBtn').classList.toggle('asset-hidden', state.dockerResourceTab !== 'volumes');
    $('#pullDockerImageBtn').classList.toggle('asset-hidden', state.dockerResourceTab !== 'images');
    $$('.asset-docker-resource-panel').forEach(function(panel) {
      panel.classList.toggle('active', panel.id === 'docker-resource-' + state.dockerResourceTab);
    });
    $$('.asset-docker-subtab').forEach(function(btn) {
      var active = btn.dataset.dockerResourceTab === state.dockerResourceTab;
      btn.classList.toggle('active', active);
      btn.setAttribute('aria-selected', active ? 'true' : 'false');
    });
    var dockerCount = $('#dockerCount');
    if (state.loadingDocker) {
      $('#dockerRows').innerHTML = tableSkeletonRows(5, 5);
      if (dockerCount) dockerCount.textContent = '...';
      return;
    }
    var rows = state.containers.filter(function(item) {
      var hay = [item.name, item.image, item.command, item.status, item.status_text || '', item.ports].join(' ').toLowerCase();
      return (!q || hay.indexOf(q) >= 0) && statuses.indexOf(item.status) >= 0;
    });
    if (dockerCount) dockerCount.textContent = state.containers.length;
    if (!host) {
      $('#dockerRows').innerHTML = '<tr class="asset-empty-row"><td colspan="6"><div class="asset-sub">' + t('asset.empty.docker_host') + '</div></td></tr>';
      return;
    }
    $('#dockerRows').innerHTML = rows.length ? rows.map(function(item) {
      var pendingAction = dockerPendingAction(item.id);
      var rowPending = !!pendingAction;
      var logsPending = pendingAction === 'logs-docker';
      var logsIcon = logsPending ? 'fa-spinner fa-spin' : 'fa-clipboard-list';
      var actionAttrs = rowPending ? 'disabled aria-disabled="true"' : '';
      return '<tr>' +
        '<td data-label="' + esc(t('asset.table.container')) + '"><div class="asset-name-cell"><strong>' + esc(item.name) + '</strong></div></td>' +
        '<td data-label="' + esc(t('asset.table.image')) + '"><div class="asset-cell-clip asset-docker-image" title="' + esc(item.image || '-') + '">' + esc(item.image || '-') + '</div></td>' +
        '<td data-label="' + esc(t('asset.table.status')) + '">' + statusPill(item.status) + '</td>' +
        '<td data-label="' + esc(t('asset.table.ports')) + '">' + dockerPortsCell(item) + '</td>' +
        '<td class="asset-right"><div class="asset-actions">' +
          actionButton(t('asset.action.logs'), logsIcon, 'logs-docker', item.id, '', logsPending ? 'disabled aria-disabled="true" data-loading="true"' : actionAttrs) +
          actionButton(t('asset.action.session'), 'fa-terminal', 'session-docker', item.id, '', actionAttrs) +
          dockerActionMenu(item) +
          dockerMobileActions(item) +
        '</div></td>' +
      '</tr>';
    }).join('') : '<tr class="asset-empty-row"><td colspan="6"><div class="asset-sub">' + t('asset.empty.docker') + '</div></td></tr>';
    applyDockerColumnWidths('#docker-resource-containers .asset-table');
    renderDockerNetworks();
    renderDockerVolumes();
    renderDockerImages();
  }

  function updateDockerSearchControl() {
    var input = $('#dockerSearch');
    if (!input) return;
    var placeholderKey = {
      containers: 'asset.docker.search.containers.placeholder',
      networks: 'asset.docker.search.networks.placeholder',
      volumes: 'asset.docker.search.volumes.placeholder',
      images: 'asset.docker.search.images.placeholder'
    }[state.dockerResourceTab] || 'asset.docker.search.placeholder';
    var ariaKey = {
      containers: 'asset.docker.search.containers.aria',
      networks: 'asset.docker.search.networks.aria',
      volumes: 'asset.docker.search.volumes.aria',
      images: 'asset.docker.search.images.aria'
    }[state.dockerResourceTab] || 'asset.docker.search.aria';
    input.placeholder = t(placeholderKey);
    input.setAttribute('aria-label', t(ariaKey));
  }

  function applyDockerColumnWidths(selector) {
    var table = $(selector);
    if (!table) return;
    var headerCells = $$('thead th', table);
    if (!headerCells.length) return;
    var colCount = headerCells.length;
    var actionIndex = colCount - 1;
    var weights = headerCells.map(function(cell, index) {
      return index === actionIndex ? 0 : Math.max(6, textWeight(cell.textContent));
    });
    $$('tbody tr', table).forEach(function(row) {
      var cells = $$('td', row);
      if (cells.length !== colCount) return;
      cells.forEach(function(cell, index) {
        if (index === actionIndex) return;
        weights[index] = Math.max(weights[index], textWeight(cell.textContent));
      });
    });
    var actionWidth = actionIndex >= 0 ? 132 : 0;
    var total = weights.reduce(function(sum, value) { return sum + value; }, 0) || 1;
    var colgroup = table.querySelector('colgroup');
    if (!colgroup) {
      colgroup = document.createElement('colgroup');
      table.insertBefore(colgroup, table.firstChild);
    }
    colgroup.innerHTML = '';
    for (var i = 0; i < colCount; i++) {
      var col = document.createElement('col');
      if (i === actionIndex) {
        col.style.width = actionWidth + 'px';
      } else {
        col.style.width = (weights[i] / total * 100).toFixed(2) + '%';
      }
      colgroup.appendChild(col);
    }
  }

  function textWeight(value) {
    var text = String(value || '').replace(/\s+/g, ' ').trim();
    if (!text || text === '-') return 4;
    var weight = 0;
    for (var i = 0; i < text.length; i++) {
      weight += text.charCodeAt(i) > 255 ? 2 : 1;
    }
    return Math.max(4, Math.min(weight, 80));
  }

  function renderDockerNetworks() {
    if (!$('#dockerNetworkRows')) return;
    var host = selectedDockerHost();
    var count = $('#dockerNetworkCount');
    if (state.loadingDockerNetworks) {
      $('#dockerNetworkRows').innerHTML = tableSkeletonRows(5, 4);
      if (count) count.textContent = '...';
      return;
    }
    var q = $('#dockerSearch').value.trim().toLowerCase();
    var rows = state.dockerNetworks.filter(function(item) {
      return !q || [item.name, item.id, item.driver, item.scope].join(' ').toLowerCase().indexOf(q) >= 0;
    });
    if (count) count.textContent = state.dockerNetworks.length;
    if (!host) {
      $('#dockerNetworkRows').innerHTML = '<tr class="asset-empty-row"><td colspan="5"><div class="asset-sub">' + t('asset.empty.docker_host') + '</div></td></tr>';
      return;
    }
    $('#dockerNetworkRows').innerHTML = rows.length ? rows.map(function(item) {
      var builtin = ['bridge', 'host', 'none'].indexOf(item.name) >= 0;
      return '<tr>' +
        '<td data-label="' + esc(t('asset.table.name')) + '"><div class="asset-name-cell"><strong>' + esc(item.name) + '</strong></div></td>' +
        '<td data-label="ID" class="asset-mono">' + esc(item.id || '-') + '</td>' +
        '<td data-label="' + esc(t('asset.docker.driver')) + '">' + esc(item.driver || '-') + '</td>' +
        '<td data-label="' + esc(t('asset.docker.scope')) + '">' + esc(item.scope || '-') + '</td>' +
        '<td class="asset-right"><div class="asset-actions">' +
          actionButton(t('asset.action.delete'), 'fa-trash-can', 'delete-docker-network', item.name, 'danger', builtin ? 'disabled aria-disabled="true"' : '') +
        '</div></td>' +
      '</tr>';
    }).join('') : '<tr class="asset-empty-row"><td colspan="5"><div class="asset-sub">' + t('asset.empty.docker_networks') + '</div></td></tr>';
    applyDockerColumnWidths('#docker-resource-networks .asset-table');
  }

  function renderDockerVolumes() {
    if (!$('#dockerVolumeRows')) return;
    var host = selectedDockerHost();
    var count = $('#dockerVolumeCount');
    if (state.loadingDockerVolumes) {
      $('#dockerVolumeRows').innerHTML = tableSkeletonRows(5, 4);
      if (count) count.textContent = '...';
      return;
    }
    var q = $('#dockerSearch').value.trim().toLowerCase();
    var rows = state.dockerVolumes.filter(function(item) {
      return !q || [item.name, item.driver, item.scope, item.mountpoint].join(' ').toLowerCase().indexOf(q) >= 0;
    });
    if (count) count.textContent = state.dockerVolumes.length;
    if (!host) {
      $('#dockerVolumeRows').innerHTML = '<tr class="asset-empty-row"><td colspan="5"><div class="asset-sub">' + t('asset.empty.docker_host') + '</div></td></tr>';
      return;
    }
    $('#dockerVolumeRows').innerHTML = rows.length ? rows.map(function(item) {
      return '<tr>' +
        '<td data-label="' + esc(t('asset.table.name')) + '"><div class="asset-name-cell"><strong>' + esc(item.name) + '</strong></div></td>' +
        '<td data-label="' + esc(t('asset.docker.driver')) + '">' + esc(item.driver || '-') + '</td>' +
        '<td data-label="' + esc(t('asset.docker.scope')) + '">' + esc(item.scope || '-') + '</td>' +
        '<td data-label="' + esc(t('asset.docker.mountpoint')) + '"><div class="asset-cell-clip asset-mono" title="' + esc(item.mountpoint || '-') + '">' + esc(item.mountpoint || '-') + '</div></td>' +
        '<td class="asset-right"><div class="asset-actions">' +
          actionButton(t('asset.action.delete'), 'fa-trash-can', 'delete-docker-volume', item.name, 'danger') +
        '</div></td>' +
      '</tr>';
    }).join('') : '<tr class="asset-empty-row"><td colspan="5"><div class="asset-sub">' + t('asset.empty.docker_volumes') + '</div></td></tr>';
    applyDockerColumnWidths('#docker-resource-volumes .asset-table');
  }

  function dockerImageRef(item) {
    var repo = item.repository || '<none>';
    var tag = item.tag || '<none>';
    if (repo === '<none>' || tag === '<none>') return item.id || repo;
    return repo + ':' + tag;
  }

  function renderDockerImages() {
    if (!$('#dockerImageRows')) return;
    var host = selectedDockerHost();
    var count = $('#dockerImageCount');
    if (state.loadingDockerImages) {
      $('#dockerImageRows').innerHTML = tableSkeletonRows(5, 4);
      if (count) count.textContent = '...';
      return;
    }
    var q = $('#dockerSearch').value.trim().toLowerCase();
    var rows = state.dockerImages.filter(function(item) {
      return !q || [item.repository, item.tag, item.id, item.size, item.created_since, item.created_at].join(' ').toLowerCase().indexOf(q) >= 0;
    });
    if (count) count.textContent = state.dockerImages.length;
    if (!host) {
      $('#dockerImageRows').innerHTML = '<tr class="asset-empty-row"><td colspan="5"><div class="asset-sub">' + t('asset.empty.docker_host') + '</div></td></tr>';
      return;
    }
    $('#dockerImageRows').innerHTML = rows.length ? rows.map(function(item) {
      var ref = dockerImageRef(item);
      return '<tr>' +
        '<td data-label="' + esc(t('asset.table.image')) + '"><div class="asset-name-cell"><strong>' + esc(ref) + '</strong></div></td>' +
        '<td data-label="ID" class="asset-mono">' + esc(item.id || '-') + '</td>' +
        '<td data-label="' + esc(t('asset.files.size')) + '">' + esc(item.size || '-') + '</td>' +
        '<td data-label="' + esc(t('asset.inspect.created')) + '">' + esc(item.created_since || formatDockerTime(item.created_at) || '-') + '</td>' +
        '<td class="asset-right"><div class="asset-actions">' +
          actionButton(t('asset.action.delete'), 'fa-trash-can', 'delete-docker-image', ref, 'danger') +
        '</div></td>' +
      '</tr>';
    }).join('') : '<tr class="asset-empty-row"><td colspan="5"><div class="asset-sub">' + t('asset.empty.docker_images') + '</div></td></tr>';
    applyDockerColumnWidths('#docker-resource-images .asset-table');
  }

  function dockerLifecycleMenuItems(item, disabled) {
    var disabledAttrs = disabled ? 'disabled aria-disabled="true"' : '';
    if (item.status === 'running') {
      return actionMenuItem(t('asset.action.stop'), 'fa-stop', 'stop-docker', item.id, '', disabledAttrs) +
        actionMenuItem(t('asset.action.restart'), 'fa-rotate', 'restart-docker', item.id, '', disabledAttrs);
    }
    return actionMenuItem(t('asset.action.start'), 'fa-play', 'start-docker', item.id, '', disabledAttrs);
  }

  function renderFiles() {
    if (!$('#fileRows')) return;
    var target = selectedFileTarget();
    var pageTitle = $('#dockerPageTitle');
    if (pageTitle && state.assetMode === 'files-host') {
      pageTitle.textContent = target ? format('asset.files.host.title', { name: target.name }) : t('asset.files.title');
    }
    if (pageTitle && state.assetMode === 'webdav-files') {
      pageTitle.textContent = target ? format('asset.webdav.files.server_title', { name: target.name }) : t('asset.webdav.files.title');
    }
    $('#refreshFilesBtn').disabled = !target;
    $('#uploadFileBtn').disabled = !target;
    $('#newDirBtn').disabled = !target;
    $('#fileUpBtn').disabled = !target || state.filePath === '.' || state.filePath === '/';
    renderFileBreadcrumb();
    renderFileQuickPaths(target);
    renderFileLimitNotice();
    if (state.loadingFiles) {
      $('#fileRows').innerHTML = tableSkeletonRows(6, 6);
      return;
    }
    if (!target) {
      $('#fileRows').innerHTML = '<tr class="asset-empty-row"><td colspan="6"><div class="asset-sub">' + t(state.assetMode === 'webdav-files' ? 'asset.webdav.files.empty_target' : 'asset.files.host.empty') + '</div></td></tr>';
      return;
    }
    var dirs = [];
    var files = [];
    state.files.forEach(function(item) {
      (item.type === 'dir' ? dirs : files).push(item);
    });
    var rows = dirs.concat(files);
    $('#fileRows').innerHTML = rows.length ? rows.map(function(item) {
      var isDir = item.type === 'dir';
      var previewKind = isDir ? '' : filePreviewKind(item.path || item.name);
      var icon = isDir ? 'fa-folder' : item.type === 'symlink' ? 'fa-link' : previewKind === 'image' ? 'fa-file-image' : previewKind === 'video' ? 'fa-file-video' : 'fa-file';
      var renaming = state.fileRename && state.fileRename.oldPath === item.path;
      var nameControl = renaming
        ? '<span class="asset-file-name asset-file-name-editing">' +
            '<i class="fa-solid ' + icon + '"></i>' +
            '<input class="asset-file-rename-input" data-file-rename-input="true" data-path="' + esc(item.path) + '" value="' + esc(state.fileRename.value) + '" aria-label="' + esc(t('asset.files.rename')) + '"' + (state.fileRename.saving ? ' disabled' : '') + '>' +
          '</span>'
        : '<button class="asset-file-name" type="button" data-action="' + (isDir ? 'open-file-dir' : previewKind ? 'preview-file' : 'edit-file') + '" data-path="' + esc(item.path) + '">' +
            '<i class="fa-solid ' + icon + '"></i><strong>' + esc(item.name) + '</strong>' +
          '</button>';
      return '<tr>' +
        '<td data-label="' + esc(t('asset.table.name')) + '">' +
          nameControl +
        '</td>' +
        '<td data-label="' + esc(t('asset.files.type')) + '">' + esc(t('asset.files.type.' + item.type)) + '</td>' +
        '<td data-label="' + esc(t('asset.files.size')) + '" class="asset-mono">' + (isDir ? '-' : esc(formatFileSize(item.size))) + '</td>' +
        '<td data-label="' + esc(t('asset.files.mode')) + '" class="asset-mono">' + esc(item.mode || '-') + '</td>' +
        '<td data-label="' + esc(t('asset.files.modified')) + '">' + esc(formatFileTime(item.mod_time)) + '</td>' +
        '<td class="asset-right"><div class="asset-actions">' +
          (previewKind ? actionButton(t('asset.files.preview'), 'fa-eye', 'preview-file', item.path) : '') +
          (isDir ? '' : actionButton(t('asset.files.download'), 'fa-download', 'download-file', item.path)) +
          actionButton(t('asset.files.rename'), 'fa-pen-to-square', 'rename-file', item.path) +
          actionButton(t('asset.action.delete'), 'fa-trash-can', 'delete-file', item.path, 'danger', isDir ? 'data-file-dir="true"' : '') +
        '</div></td>' +
      '</tr>';
    }).join('') : '<tr class="asset-empty-row"><td colspan="6"><div class="asset-sub">' + t('asset.files.empty') + '</div></td></tr>';
    focusFileRenameInput();
  }

  function renderFileLimitNotice() {
    var el = $('#fileLimitNotice');
    if (!el) return;
    if (state.fileListTruncated) {
      el.textContent = format('asset.files.limit_notice', { limit: state.fileListLimit || 1000 });
      el.classList.remove('asset-hidden');
    } else {
      el.textContent = '';
      el.classList.add('asset-hidden');
    }
  }

  function renderFileBreadcrumb() {
    var el = $('#filePathBreadcrumb');
    if (!el) return;
    var current = state.filePath || '.';
    if (state.editingFilePath) {
      el.innerHTML = '<input class="asset-file-path-input" data-file-path-input="true" value="' + esc(state.filePathInputValue) + '" aria-label="' + esc(t('asset.files.path.input')) + '" placeholder="' + esc(t('asset.files.path.input')) + '">';
      focusFilePathInput();
      return;
    }
    if (current === '.' || current === '/') {
      el.innerHTML = '<button type="button" data-file-path="' + esc(current) + '">' + esc(current) + '</button>';
      return;
    }
    var absolute = current.charAt(0) === '/';
    var parts = current.split('/').filter(Boolean);
    var acc = absolute ? '/' : '';
    var html = '<button type="button" data-file-path="' + esc(absolute ? '/' : '.') + '">' + esc(absolute ? '/' : '.') + '</button>';
    parts.forEach(function(part, index) {
      acc = acc === '/' ? '/' + part : (acc ? acc + '/' + part : part);
      html += (absolute && index === 0 ? '' : '<span>/</span>') + '<button type="button" data-file-path="' + esc(acc) + '">' + esc(part) + '</button>';
    });
    el.innerHTML = html;
  }

  function renderFileQuickPaths(host) {
    var el = $('#fileQuickPaths');
    if (!el) return;
    if (!host || state.assetMode === 'webdav-files') {
      el.innerHTML = '';
      return;
    }
    var paths = [
      { label: t('asset.files.quick.systemd'), path: '/etc/systemd/system' }
    ];
    var homePath = fileHomePath(host.username);
    if (homePath) {
      paths.push({ label: t('asset.files.quick.home'), path: homePath });
    }
    paths.push({ label: t('asset.files.quick.etc'), path: '/etc' });
    el.innerHTML = paths.map(function(item) {
      return '<button class="asset-file-path-chip" type="button" data-file-quick-path="' + esc(item.path) + '" title="' + esc(item.path) + '">' + esc(item.label) + '</button>';
    }).join('');
  }

  function fileHomePath(username) {
    var name = String(username || '').trim();
    if (!name) return '';
    return name === 'root' ? '/root' : '/home/' + name;
  }

  function focusFilePathInput() {
    window.requestAnimationFrame(function() {
      var input = $('[data-file-path-input="true"]');
      if (!input) return;
      if (window.BookStarkFormGuards && typeof window.BookStarkFormGuards.markNonCredentialInput === 'function') window.BookStarkFormGuards.markNonCredentialInput(input);
      input.focus();
      input.select();
    });
  }

  function formatFileSize(size) {
    var n = Number(size || 0);
    if (n < 1024) return n + ' B';
    var units = ['KB', 'MB', 'GB', 'TB'];
    for (var i = 0; i < units.length; i++) {
      n = n / 1024;
      if (n < 1024 || i === units.length - 1) return n.toFixed(n >= 10 ? 1 : 2) + ' ' + units[i];
    }
    return String(size);
  }

  function formatFileTime(value) {
    if (!value) return '-';
    var date = new Date(value);
    if (Number.isNaN(date.getTime())) return '-';
    return date.toLocaleString();
  }

  function renderAll() {
    renderCredentialPicker();
    renderWebDAVCredentialPicker();
    renderCredentials();
    renderSsh();
    renderWebDAV();
    renderDocker();
    renderDockerNetworks();
    renderDockerVolumes();
    renderDockerImages();
    renderFiles();
    updateMobileFab();
  }

  function setSettingsTab(tab, opts) {
    opts = opts || {};
    if (opts.updateUrl !== false && window.BookStarkTabURL) window.BookStarkTabURL.set('settingsTab', tab);
    state.settingsTab = tab;
    $$('.asset-settings-tab').forEach(function(btn) {
      btn.classList.toggle('active', btn.dataset.settingsTab === tab);
    });
    $$('.asset-settings-panel').forEach(function(panel) {
      panel.classList.toggle('active', panel.id === 'settings-' + tab);
    });
    updateMobileFab();
  }

  function setDockerCreateTab(tab) {
    $$('.asset-docker-create-tab').forEach(function(btn) {
      var active = btn.dataset.dockerCreateTab === tab;
      btn.classList.toggle('active', active);
      btn.setAttribute('aria-selected', active ? 'true' : 'false');
    });
    $$('.asset-docker-create-panel').forEach(function(panel) {
      panel.classList.toggle('active', panel.id === 'docker-create-' + tab);
    });
  }

  function openModal(id) {
    $(id).classList.add('open');
    $(id).setAttribute('aria-hidden', 'false');
    if (window.BookStarkScrollLock) BookStarkScrollLock.lock('asset-modal');
  }

  function syncModalScrollLock() {
    if (!window.BookStarkScrollLock) return;
    if ($$('.asset-modal-backdrop.open').length) BookStarkScrollLock.lock('asset-modal');
    else BookStarkScrollLock.unlock('asset-modal');
  }

  function closeSession(options) {
    options = options || {};
    var preserveWindowState = !!options.preserveWindowState;
    if (state.socket) {
      if (state.socket.readyState === WebSocket.OPEN) {
        state.socket.send(JSON.stringify({ type: 'close' }));
      }
      state.socket.close();
      state.socket = null;
    }
    if (state.terminal) {
      state.terminal.dispose();
      state.terminal = null;
      state.fitAddon = null;
    }
    clearTerminalWriteQueue();
    $('#terminalPane').innerHTML = '';
    if (!preserveWindowState) {
      $('.asset-session-window').classList.remove('maximized');
      state.terminalMaximized = false;
    }
    setTerminalReconnectVisible(false);
    state.terminalStatus = '';
    state.sessionTarget = null;
  }

  function closeDockerLogStream(status) {
    if (state.dockerLogSource) {
      state.dockerLogSource.close();
      state.dockerLogSource = null;
    }
    if (status) setDockerLogStatus(status);
  }

  function closeDockerLogs() {
    closeDockerLogStream('idle');
    state.dockerLogContainerId = '';
  }

  function closeModals() {
    closeFloatingDropdown();
    closeSession();
    closeDockerLogs();
    closeFileEditor();
    closeFilePreview();
    state.credentialModalSource = '';
    $$('.asset-modal-backdrop').forEach(function(modal) {
      modal.classList.remove('open');
      modal.setAttribute('aria-hidden', 'true');
    });
    syncModalScrollLock();
  }

  function closeCredentialModal() {
    closeFloatingDropdown();
    state.credentialModalSource = '';
    var modal = $('#credentialModal');
    if (modal) {
      modal.classList.remove('open');
      modal.setAttribute('aria-hidden', 'true');
    }
    syncModalScrollLock();
  }

  function cancelCredentialModal() {
    var fromSshPicker = state.credentialModalSource === 'ssh-picker';
    var fromWebDAVPicker = state.credentialModalSource === 'webdav-picker';
    closeCredentialModal();
    if (fromSshPicker || fromWebDAVPicker) {
      window.requestAnimationFrame(function() {
        var input = fromWebDAVPicker ? $('#webdavCredentialSearch') : $('#sshCredentialSearch');
        if (input) input.focus();
      });
    }
  }

  function setCredentialAuthMode(mode) {
    state.credentialAuthMode = mode;
    $$('[data-credential-auth]').forEach(function(btn) {
      btn.classList.toggle('active', btn.dataset.credentialAuth === mode);
    });
    $('#credentialPasswordField').classList.toggle('asset-hidden', mode !== 'password');
    $('#credentialKeyField').classList.toggle('asset-hidden', mode !== 'key');
    setCredentialPasswordVisible(false);
  }

  function setCredentialPasswordVisible(visible) {
    var input = $('#credentialPassword');
    var toggle = $('#credentialPasswordToggle');
    if (!input || !toggle) return;
    input.type = visible ? 'text' : 'password';
    toggle.setAttribute('aria-label', visible ? t('asset.password.hide') : t('asset.password.show'));
    toggle.innerHTML = '<i class="fa-solid ' + (visible ? 'fa-eye-slash' : 'fa-eye') + '"></i>';
  }

  function setCredentialSecretVisible(visible) {
    var input = $('#settingCredentialSecret');
    var toggle = $('#settingCredentialSecretToggle');
    if (!input || !toggle) return;
    input.type = visible ? 'text' : 'password';
    toggle.setAttribute('aria-label', visible ? t('asset.password.hide') : t('asset.password.show'));
    toggle.innerHTML = '<i class="fa-solid ' + (visible ? 'fa-eye-slash' : 'fa-eye') + '"></i>';
  }

  function openSshForm(item) {
    $('#sshModalTitle').textContent = item ? t('asset.ssh.modal.edit') : t('asset.ssh.modal.new');
    $('#sshId').value = item ? item.id : '';
    $('#sshName').value = item ? item.name : '';
    $('#sshHost').value = item ? item.host : '';
    $('#sshPort').value = item ? item.port : 22;
    $('#sshShell').value = item ? item.shell || '/bin/sh' : '/bin/sh';
    $('#sshCwd').value = item ? item.cwd || '' : '';
    $('#sshDockerSocketPath').value = item ? item.docker_socket_path || '/var/run/docker.sock' : '/var/run/docker.sock';
    renderCredentialPicker(item ? item.credential_id : '');
    openModal('#sshModal');
    $('#sshName').focus();
  }

  function saveSsh(event) {
    event.preventDefault();
    var id = $('#sshId').value;
    if (!$('#sshCredential').value) {
      toast(t('asset.credentials.empty'));
      $('#sshCredentialSearch').focus();
      return;
    }
    var body = {
      name: $('#sshName').value.trim(),
      host: $('#sshHost').value.trim(),
      port: Number($('#sshPort').value || 22),
      shell: $('#sshShell').value.trim() || '/bin/sh',
      cwd: $('#sshCwd').value.trim(),
      docker_socket_path: $('#sshDockerSocketPath').value.trim() || '/var/run/docker.sock',
      credential_id: Number($('#sshCredential').value)
    };
    var url = '/api/admin/assets/ssh-hosts' + (id ? '/' + encodeURIComponent(id) : '');
    var method = id ? 'PUT' : 'POST';
    var request = runSubmitLocked('assets:ssh:' + method + ':' + (id || 'new'), event.submitter || $('#sshForm button[type="submit"]'), function() {
      return apiJSON(url, { method: method, headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
    });
    if (!request) return;
    request
      .then(function() {
        closeModals();
        toast(t('asset.toast.ssh_saved'), 'success');
        return loadData();
      })
      .catch(function(err) { toast(err.message || t('asset.error.save')); });
  }

  function openWebDAVForm(item) {
    $('#webdavModalTitle').textContent = item ? t('asset.webdav.modal.edit') : t('asset.webdav.modal.new');
    $('#webdavId').value = item ? item.id : '';
    $('#webdavName').value = item ? item.name : '';
    $('#webdavUrl').value = item ? item.url : '';
    $('#webdavRootPath').value = item ? item.root_path || '/' : '/';
    renderWebDAVCredentialPicker(item ? item.credential_id : '');
    openModal('#webdavModal');
    $('#webdavName').focus();
  }

  function saveWebDAV(event) {
    event.preventDefault();
    var id = $('#webdavId').value;
    if (!$('#webdavCredential').value) {
      toast(t('asset.credentials.empty'));
      $('#webdavCredential').focus();
      return;
    }
    var body = {
      name: $('#webdavName').value.trim(),
      url: $('#webdavUrl').value.trim(),
      root_path: $('#webdavRootPath').value.trim() || '/',
      credential_id: Number($('#webdavCredential').value)
    };
    var url = '/api/admin/assets/webdav-servers' + (id ? '/' + encodeURIComponent(id) : '');
    var method = id ? 'PUT' : 'POST';
    var request = runSubmitLocked('assets:webdav:' + method + ':' + (id || 'new'), event.submitter || $('#webdavForm button[type="submit"]'), function() {
      return apiJSON(url, { method: method, headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
    });
    if (!request) return;
    request
      .then(function() {
        closeModals();
        toast(t('asset.toast.webdav_saved'), 'success');
        return loadData();
      })
      .catch(function(err) { toast(err.message || t('asset.error.save')); });
  }

  function openCredentialForm(item, opts) {
    opts = opts || {};
    state.credentialModalSource = opts.source || '';
    $('#credentialModalTitle').textContent = item ? t('asset.credentials.modal.edit') : t('asset.credentials.modal.new');
    $('#credentialId').value = item ? item.id : '';
    $('#credentialName').value = item ? item.name : '';
    $('#credentialUser').value = item ? item.username : '';
    setCredentialAuthMode(item ? item.auth_type : 'password');
    $('#credentialPassword').value = item && item.auth_type !== 'key' ? item.credential || '' : '';
    $('#credentialKey').value = item && item.auth_type === 'key' ? item.credential || '' : '';
    setCredentialPasswordVisible(false);
    openModal('#credentialModal');
    $('#credentialName').focus();
  }

  function saveCredential(event) {
    event.preventDefault();
    var id = $('#credentialId').value;
    var body = {
      name: $('#credentialName').value.trim(),
      username: $('#credentialUser').value.trim(),
      auth_type: state.credentialAuthMode,
      credential: state.credentialAuthMode === 'password' ? $('#credentialPassword').value : $('#credentialKey').value
    };
    var url = '/api/admin/assets/credentials' + (id ? '/' + encodeURIComponent(id) : '');
    var method = id ? 'PUT' : 'POST';
    var request = runSubmitLocked('assets:credential:' + method + ':' + (id || 'new'), event.submitter || $('#credentialForm button[type="submit"]'), function() {
      return apiJSON(url, { method: method, headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
    });
    if (!request) return;
    request
      .then(function(saved) {
        toast(t('asset.toast.credential_saved'), 'success');
        var modalSource = state.credentialModalSource;
        if ((modalSource === 'ssh-picker' || modalSource === 'webdav-picker') && saved && saved.id) {
          closeCredentialModal();
          var exists = false;
          state.credentials = state.credentials.map(function(item) {
            if (String(item.id) === String(saved.id)) {
              exists = true;
              return saved;
            }
            return item;
          });
          if (!exists) state.credentials.unshift(saved);
          renderCredentials();
          if (modalSource === 'webdav-picker') {
            renderWebDAVCredentialPicker(saved.id);
            selectWebDAVCredential(saved.id);
          } else {
            renderCredentialPicker(saved.id);
            selectCredential(saved.id);
          }
          return;
        }
        closeModals();
        return loadData();
      })
      .catch(function(err) { toast(err.message || t('asset.error.save')); });
  }

  function dockerCreateRow(type, values) {
    values = values || {};
    if (type === 'port') {
      return '<div class="asset-repeat-row" data-docker-create-row="port">' +
        '<input class="dialog-input" data-field="host_ip" placeholder="' + esc(t('asset.docker.create.host_ip')) + '" value="' + esc(values.host_ip || '') + '">' +
        '<input class="dialog-input" data-field="host_port" placeholder="' + esc(t('asset.docker.create.host_port')) + '" value="' + esc(values.host_port || '') + '">' +
        '<input class="dialog-input" data-field="container_port" placeholder="' + esc(t('asset.docker.create.container_port')) + '" value="' + esc(values.container_port || '') + '">' +
        '<select class="dialog-input" data-field="protocol">' +
          '<option value="tcp"' + ((values.protocol || 'tcp') === 'tcp' ? ' selected' : '') + '>tcp</option>' +
          '<option value="udp"' + (values.protocol === 'udp' ? ' selected' : '') + '>udp</option>' +
          '<option value="sctp"' + (values.protocol === 'sctp' ? ' selected' : '') + '>sctp</option>' +
        '</select>' +
        '<button class="asset-repeat-remove" type="button" data-docker-create-remove aria-label="' + esc(t('asset.action.delete')) + '"><i class="fa-solid fa-xmark"></i></button>' +
      '</div>';
    }
    if (type === 'volume') {
      return '<div class="asset-repeat-row asset-repeat-row-volume" data-docker-create-row="volume">' +
        '<input class="dialog-input" data-field="host_path" placeholder="' + esc(t('asset.docker.create.host_path')) + '" value="' + esc(values.host_path || '') + '">' +
        '<input class="dialog-input" data-field="container_path" placeholder="' + esc(t('asset.docker.create.container_path')) + '" value="' + esc(values.container_path || '') + '">' +
        '<select class="dialog-input" data-field="mode">' +
          '<option value="rw"' + ((values.mode || 'rw') === 'rw' ? ' selected' : '') + '>rw</option>' +
          '<option value="ro"' + (values.mode === 'ro' ? ' selected' : '') + '>ro</option>' +
        '</select>' +
        '<button class="asset-repeat-remove" type="button" data-docker-create-remove aria-label="' + esc(t('asset.action.delete')) + '"><i class="fa-solid fa-xmark"></i></button>' +
      '</div>';
    }
    return '<div class="asset-repeat-row asset-repeat-row-env" data-docker-create-row="env">' +
      '<input class="dialog-input" data-field="key" placeholder="' + esc(t('asset.docker.create.env_key')) + '" value="' + esc(values.key || '') + '">' +
      '<input class="dialog-input" data-field="value" placeholder="' + esc(t('asset.docker.create.env_value')) + '" value="' + esc(values.value || '') + '">' +
      '<button class="asset-repeat-remove" type="button" data-docker-create-remove aria-label="' + esc(t('asset.action.delete')) + '"><i class="fa-solid fa-xmark"></i></button>' +
    '</div>';
  }

  function addDockerCreateRow(type, values) {
    var target = type === 'port' ? $('#dockerCreatePorts') : type === 'volume' ? $('#dockerCreateVolumes') : $('#dockerCreateEnv');
    target.insertAdjacentHTML('beforeend', dockerCreateRow(type, values));
  }

  function renderDockerNetworkOptions() {
    var input = $('#dockerCreateNetwork');
    renderAutocomplete('docker-network');
    if (!input) return;
    input.placeholder = state.dockerNetworksLoading ? t('asset.docker.create.network.loading') : 'bridge';
  }

  function renderDockerImageOptions() {
    var input = $('#dockerCreateImage');
    renderAutocomplete('docker-image');
    if (!input) return;
    input.placeholder = state.dockerImagesLoading ? t('asset.docker.create.image.loading') : 'nginx:latest';
  }

  function autocompleteConfig(type) {
    if (type === 'ssh-shell') {
      return {
        input: '#sshShell',
        dropdown: '#sshShellOptions',
        emptyKey: 'asset.autocomplete.empty',
        items: ['/bin/sh', '/bin/bash', '/bin/zsh'].map(function(value) {
          return { value: value, label: value, meta: '' };
        })
      };
    }
    if (type === 'docker-network') {
      return {
        input: '#dockerCreateNetwork',
        dropdown: '#dockerCreateNetworkOptions',
        emptyKey: 'asset.empty.docker_networks',
        items: (state.dockerNetworks || []).map(function(item) {
          return {
            value: item.name || '',
            label: item.name || '',
            meta: [item.driver, item.scope].filter(Boolean).join(' · ')
          };
        })
      };
    }
    if (type === 'docker-image') {
      return {
        input: '#dockerCreateImage',
        dropdown: '#dockerCreateImageOptions',
        emptyKey: 'asset.empty.docker_images',
        items: (state.dockerImages || []).map(function(item) {
          var ref = dockerImageRef(item);
          if (!ref || ref === '<none>' || ref.indexOf('<none>') >= 0) return null;
          return {
            value: ref,
            label: ref,
            meta: [item.id, item.size].filter(Boolean).join(' · ')
          };
        }).filter(Boolean)
      };
    }
    return null;
  }

  function renderAutocomplete(type) {
    var config = autocompleteConfig(type);
    if (!config) return;
    var input = $(config.input);
    var dropdown = $(config.dropdown);
    if (!input || !dropdown) return;
    var query = input.value.trim().toLowerCase();
    var html = (config.items || []).filter(function(item) {
      if (!item || !item.value) return false;
      if (!query) return true;
      return [item.value, item.label, item.meta].join(' ').toLowerCase().indexOf(query) >= 0;
    }).map(function(item) {
      return '<button class="asset-autocomplete-option" type="button" role="option" aria-selected="false" data-autocomplete-type="' + esc(type) + '" data-value="' + esc(item.value) + '">' +
        '<span>' + esc(item.label || item.value) + '</span>' +
        (item.meta ? '<small>' + esc(item.meta) + '</small>' : '') +
      '</button>';
    }).join('');
    dropdown.innerHTML = html || '<div class="asset-combobox-empty">' + esc(t(config.emptyKey || 'asset.autocomplete.empty')) + '</div>';
  }

  function showAutocomplete(type) {
    var config = autocompleteConfig(type);
    if (!config) return;
    renderAutocomplete(type);
    var dropdown = $(config.dropdown);
    var input = $(config.input);
    if (!dropdown || !input) return;
    openFloatingDropdown(dropdown, input, { maxHeight: 220 });
  }

  function hideAutocomplete(type) {
    var config = autocompleteConfig(type);
    if (!config) return;
    var dropdown = $(config.dropdown);
    var input = $(config.input);
    if (!dropdown || !input) return;
    closeFloatingDropdown(dropdown);
    input.setAttribute('aria-expanded', 'false');
  }

  function bindAutocomplete(type) {
    var config = autocompleteConfig(type);
    if (!config) return;
    var input = $(config.input);
    var dropdown = $(config.dropdown);
    if (!input || !dropdown) return;
    var suppressNextFocus = false;
    input.addEventListener('focus', function() {
      if (suppressNextFocus) {
        suppressNextFocus = false;
        return;
      }
      showAutocomplete(type);
    });
    input.addEventListener('input', function() { showAutocomplete(type); });
    input.addEventListener('keydown', function(event) {
      if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
        event.preventDefault();
        showAutocomplete(type);
        setTimeout(function() {
          focusDropdownItem(dropdown, '.asset-autocomplete-option', event.key === 'ArrowDown' ? 0 : -1);
        }, 0);
      } else if (event.key === 'Enter' && dropdownIsOpen(dropdown)) {
        if (clickDropdownActiveItem(dropdown, '.asset-autocomplete-option')) event.preventDefault();
      } else if (event.key === 'Escape' && dropdownIsOpen(dropdown)) {
        event.preventDefault();
        hideAutocomplete(type);
      }
    });
    input.addEventListener('blur', function() {
      setTimeout(function() {
        if (dropdown.contains(document.activeElement)) return;
        hideAutocomplete(type);
      }, 120);
    });
    dropdown.addEventListener('mousedown', function(event) {
      event.preventDefault();
    });
    dropdown.addEventListener('click', function(event) {
      var option = event.target.closest('[data-value]');
      if (!option) return;
      input.value = option.dataset.value || '';
      hideAutocomplete(type);
      suppressNextFocus = true;
      input.focus();
    });
    dropdown.addEventListener('keydown', function(event) {
      if (event.key === 'ArrowDown') {
        event.preventDefault();
        moveDropdownFocus(dropdown, '.asset-autocomplete-option', 1);
      } else if (event.key === 'ArrowUp') {
        event.preventDefault();
        moveDropdownFocus(dropdown, '.asset-autocomplete-option', -1);
      } else if (event.key === 'Home') {
        event.preventDefault();
        focusDropdownItem(dropdown, '.asset-autocomplete-option', 0);
      } else if (event.key === 'End') {
        event.preventDefault();
        focusDropdownItem(dropdown, '.asset-autocomplete-option', -1);
      } else if (event.key === 'Escape') {
        event.preventDefault();
        hideAutocomplete(type);
        input.focus();
      } else if (event.key === 'Tab') {
        hideAutocomplete(type);
      }
    });
  }

  function loadDockerNetworks() {
    if (!state.selectedDockerHostId) return Promise.resolve([]);
    state.dockerNetworksLoading = true;
    renderDockerNetworkOptions();
    return apiJSON('/api/admin/assets/ssh-hosts/' + encodeURIComponent(state.selectedDockerHostId) + '/docker-networks')
      .then(function(items) {
        state.dockerNetworks = items || [];
        return state.dockerNetworks;
      })
      .catch(function(err) {
        state.dockerNetworks = [];
        toast(err.message || t('asset.error.load'));
        return [];
      })
      .finally(function() {
        state.dockerNetworksLoading = false;
        renderDockerNetworkOptions();
      });
  }

  function loadDockerImageOptions() {
    if (!state.selectedDockerHostId) return Promise.resolve([]);
    state.dockerImagesLoading = true;
    renderDockerImageOptions();
    return apiJSON('/api/admin/assets/ssh-hosts/' + encodeURIComponent(state.selectedDockerHostId) + '/docker-images')
      .then(function(items) {
        state.dockerImages = items || [];
        return state.dockerImages;
      })
      .catch(function(err) {
        state.dockerImages = [];
        toast(err.message || t('asset.error.load'));
        return [];
      })
      .finally(function() {
        state.dockerImagesLoading = false;
        renderDockerImageOptions();
      });
  }

  function resetDockerCreateForm() {
    $('#dockerCreateForm').reset();
    $('#dockerCreateStart').checked = true;
    $('#dockerCreatePorts').innerHTML = '';
    $('#dockerCreateVolumes').innerHTML = '';
    $('#dockerCreateEnv').innerHTML = '';
    addDockerCreateRow('port');
    addDockerCreateRow('volume');
    addDockerCreateRow('env');
    renderDockerNetworkOptions();
    renderDockerImageOptions();
    setDockerCreateTab('base');
    setDockerCreateSaving(false);
  }

  function openDockerCreateForm() {
    if (!state.selectedDockerHostId) {
      toast(t('asset.empty.docker_host'));
      return;
    }
    resetDockerCreateForm();
    openModal('#dockerCreateModal');
    loadDockerNetworks();
    loadDockerImageOptions();
    $('#dockerCreateImage').focus();
    showAutocomplete('docker-image');
  }

  function collectDockerCreateRows(type) {
    return $$('[data-docker-create-row="' + type + '"]').map(function(row) {
      var item = {};
      $$('[data-field]', row).forEach(function(input) {
        item[input.dataset.field] = input.value.trim();
      });
      return item;
    }).filter(function(item) {
      return Object.keys(item).some(function(key) { return item[key] !== ''; });
    });
  }

  function setDockerCreateSaving(saving) {
    var submit = $('#dockerCreateSubmit');
    if (!submit) return;
    submit.disabled = saving;
    submit.innerHTML = saving
      ? '<i class="fa-solid fa-spinner fa-spin"></i>' + esc(t('asset.docker.create.creating'))
      : '<i class="fa-solid fa-plus"></i>' + esc(t('asset.docker.create.submit'));
  }

  function saveDockerCreate(event) {
    event.preventDefault();
    if (!state.selectedDockerHostId) return;
    var body = {
      image: $('#dockerCreateImage').value.trim(),
      name: $('#dockerCreateName').value.trim(),
      command: $('#dockerCreateCommand').value.trim(),
      start_after_create: $('#dockerCreateStart').checked,
      restart_policy: $('#dockerCreateRestartPolicy').value,
      ports: collectDockerCreateRows('port'),
      volumes: collectDockerCreateRows('volume'),
      env: collectDockerCreateRows('env'),
      network: $('#dockerCreateNetwork').value.trim(),
      privileged: $('#dockerCreatePrivileged').checked,
      memory: $('#dockerCreateMemory').value.trim(),
      cpus: $('#dockerCreateCpus').value.trim()
    };
    setDockerCreateSaving(true);
    apiJSON('/api/admin/assets/ssh-hosts/' + encodeURIComponent(state.selectedDockerHostId) + '/docker-containers', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body)
    })
      .then(function() {
        closeModals();
        toast(t('asset.toast.docker_created'), 'success');
        return loadDockerContainers(true);
      })
      .catch(function(err) {
        toast(err.message || t('asset.error.save'));
      })
      .finally(function() {
        setDockerCreateSaving(false);
      });
  }

  function deleteAsset(type, id) {
    var url = type === 'ssh'
      ? '/api/admin/assets/ssh-hosts/' + encodeURIComponent(id)
      : type === 'webdav'
        ? '/api/admin/assets/webdav-servers/' + encodeURIComponent(id)
        : '/api/admin/assets/credentials/' + encodeURIComponent(id);
    apiJSON(url, { method: 'DELETE' })
      .then(function() {
        closeModals();
        toast(t('asset.toast.deleted'), 'success');
        return loadData();
      })
      .catch(function(err) { toast(err.message || t('asset.error.delete')); });
  }

  function confirmDelete(type, id) {
    var list = type === 'ssh' ? state.sshHosts : type === 'webdav' ? state.webdavServers : state.credentials;
    var item = list.find(function(row) { return String(row.id) === String(id); });
    if (!item) return;
    var key = type === 'ssh' ? 'asset.confirm.delete_text' : type === 'webdav' ? 'asset.confirm.delete_webdav' : 'asset.confirm.delete_credential';
    BSDialog.confirm2(format(key, { name: item.name })).then(function(ok) {
      if (ok) deleteAsset(type, id);
    });
  }

  function operateDocker(action, id) {
    if (!state.selectedDockerHostId) return Promise.resolve();
    return runDockerRowAction(id, action + '-docker', function() {
      return apiJSON('/api/admin/assets/ssh-hosts/' + encodeURIComponent(state.selectedDockerHostId) + '/docker-containers/' + encodeURIComponent(id) + '/' + encodeURIComponent(action), { method: 'POST' })
        .then(function() {
          toast(t('asset.toast.docker_' + action + '_done'), 'success');
          return loadDockerContainers(true);
        })
        .catch(function(err) {
          toast(err.message || t('asset.error.docker_action'));
          return null;
        });
    });
  }

  function updateDockerRestartPolicy(id, policy) {
    if (!state.selectedDockerHostId || !policy) return Promise.resolve();
    return runDockerRowAction(id, 'restart-policy-docker', function() {
      return apiJSON('/api/admin/assets/ssh-hosts/' + encodeURIComponent(state.selectedDockerHostId) + '/docker-containers/' + encodeURIComponent(id) + '/restart-policy', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ policy: policy })
      })
        .then(function() {
          toast(t('asset.toast.docker_restart_policy_done'), 'success');
          return loadDockerContainers(true);
        })
        .catch(function(err) {
          toast(err.message || t('asset.error.docker_action'));
          return null;
        });
    });
  }

  function confirmDeleteDocker(id) {
    var item = state.containers.find(function(row) { return String(row.id) === String(id); });
    if (!item) return;
    BSDialog.confirm2(format('asset.confirm.delete_docker', { name: item.name })).then(function(ok) {
      if (ok) operateDocker('delete', id);
    });
  }

  function inspectDocker(id) {
    if (!state.selectedDockerHostId) return Promise.resolve();
    return runDockerRowAction(id, 'inspect-docker', function() {
      return apiJSON('/api/admin/assets/ssh-hosts/' + encodeURIComponent(state.selectedDockerHostId) + '/docker-containers/' + encodeURIComponent(id) + '/inspect', { method: 'POST' })
        .then(function(info) {
          openDockerInspect(info || {});
          return loadDockerContainers(true);
        })
        .catch(function(err) {
          toast(err.message || t('asset.error.inspect'));
          return null;
        });
    });
  }

  function openDockerInspect(info) {
    $('#dockerInspectTitle').textContent = info.name || info.id || t('asset.inspect.title');
    var rows = [
      [t('asset.field.container_name'), info.name],
      ['ID', info.id],
      [t('asset.field.image'), info.image],
      [t('asset.field.status'), info.raw_status || info.status],
      [t('asset.inspect.running'), info.running ? t('asset.inspect.yes') : t('asset.inspect.no')],
      [t('asset.inspect.exit_code'), String(info.exit_code || 0)],
      [t('asset.inspect.hostname'), info.hostname],
      [t('asset.inspect.ip_address'), info.ip_address],
      [t('asset.inspect.restart_policy'), info.restart_policy],
      [t('asset.inspect.command'), Array.isArray(info.command) ? info.command.join(' ') : info.command],
      [t('asset.inspect.created'), formatDockerTime(info.created)],
      [t('asset.inspect.started_at'), formatDockerTime(info.started_at)],
      [t('asset.inspect.finished_at'), formatDockerTime(info.finished_at)]
    ];
    $('#dockerInspectBody').innerHTML = rows.map(function(row) {
      return '<div class="asset-inspect-item"><span>' + esc(row[0]) + '</span><strong>' + esc(displayValue(row[1])) + '</strong></div>';
    }).join('');
    openModal('#dockerInspectModal');
  }

  function displayValue(value) {
    if (value === null || value === undefined || value === '') return '-';
    return value;
  }

  function formatDockerTime(value) {
    if (!value || value.indexOf('0001-01-01') === 0) return '';
    var date = new Date(value);
    if (Number.isNaN(date.getTime())) return value;
    return date.toLocaleString();
  }

  function openDockerLogs(id) {
    var container = state.containers.find(function(item) { return String(item.id) === String(id); });
    state.dockerLogContainerId = String(id || '');
    state.dockerLogFollow = loadDockerLogFollowPreference();
    state.dockerLogText = '';
    $('#dockerLogsTitle').textContent = container ? container.name : t('asset.logs.title');
    renderDockerLogFollow();
    setDockerLogStatus('loading');
    setDockerLogOutput(t('asset.logs.loading'));
    openModal('#dockerLogsModal');
    if (dockerPendingAction(id)) return Promise.resolve();
    setDockerPending(id, 'logs-docker');
    return reloadDockerLogs()
      .catch(function(err) {
        toast(err.message || t('asset.error.logs'));
        return null;
      })
      .finally(function() {
        clearDockerPending(id);
      });
  }

  function dockerLogTail() {
    var tail = Number($('#dockerLogTail').value || 200);
    if (!Number.isFinite(tail) || tail < 1) tail = 200;
    tail = Math.min(Math.floor(tail), 10000);
    $('#dockerLogTail').value = String(tail);
    return tail;
  }

  function setDockerLogStatus(status) {
    var el = $('#dockerLogStatus');
    if (el) el.textContent = t('asset.logs.status.' + status);
  }

  function renderDockerLogFollow() {
    var btn = $('#dockerLogFollowBtn');
    if (!btn) return;
    btn.classList.toggle('active', !!state.dockerLogFollow);
    btn.setAttribute('aria-pressed', state.dockerLogFollow ? 'true' : 'false');
  }

  function setDockerLogOutput(text) {
    var output = $('#dockerLogOutput');
    if (!output) return;
    output.textContent = text || '';
    output.scrollTop = output.scrollHeight;
  }

  function appendDockerLogText(text) {
    if (!text) return;
    state.dockerLogText += text;
    if (state.dockerLogText.length > 1000000) {
      state.dockerLogText = state.dockerLogText.slice(-800000);
    }
    setDockerLogOutput(state.dockerLogText);
  }

  function fetchDockerLogs() {
    if (!state.selectedDockerHostId || !state.dockerLogContainerId) return Promise.resolve(null);
    closeDockerLogStream();
    var tail = dockerLogTail();
    setDockerLogStatus('loading');
    setDockerLogOutput(t('asset.logs.loading'));
    return apiJSON('/api/admin/assets/ssh-hosts/' + encodeURIComponent(state.selectedDockerHostId) + '/docker-containers/' + encodeURIComponent(state.dockerLogContainerId) + '/logs?tail=' + encodeURIComponent(tail))
      .then(function(result) {
        state.dockerLogText = result && result.logs ? result.logs : '';
        setDockerLogOutput(state.dockerLogText || t('asset.logs.empty'));
        setDockerLogStatus('paused');
        return result;
      });
  }

  function streamDockerLogs() {
    if (!state.selectedDockerHostId || !state.dockerLogContainerId) return Promise.resolve(null);
    closeDockerLogStream();
    var tail = dockerLogTail();
    state.dockerLogText = '';
    setDockerLogStatus('connecting');
    setDockerLogOutput(t('asset.logs.loading'));
    return new Promise(function(resolve, reject) {
      var settled = false;
      var url = '/api/admin/assets/ssh-hosts/' + encodeURIComponent(state.selectedDockerHostId) + '/docker-containers/' + encodeURIComponent(state.dockerLogContainerId) + '/logs/stream?tail=' + encodeURIComponent(tail);
      var source = new EventSource(url);
      state.dockerLogSource = source;
      source.onopen = function() {
        setDockerLogStatus('streaming');
        if (!state.dockerLogText) setDockerLogOutput('');
        if (!settled) {
          settled = true;
          resolve(source);
        }
      };
      source.addEventListener('log', function(event) {
        var payload;
        try {
          payload = JSON.parse(event.data || '{}');
        } catch (err) {
          payload = { data: event.data || '' };
        }
        appendDockerLogText(payload.data || '');
      });
      source.addEventListener('status', function() {
        setDockerLogStatus('streaming');
      });
      source.addEventListener('log-error', function(event) {
        var message = '';
        if (event && event.data) {
          try {
            message = JSON.parse(event.data).message || '';
          } catch (err) {
            message = event.data;
          }
        }
        setDockerLogStatus('error');
        if (message) appendDockerLogText('\n' + message + '\n');
        source.close();
        if (state.dockerLogSource === source) state.dockerLogSource = null;
        if (!settled) {
          settled = true;
          reject(new Error(message || t('asset.error.logs')));
        }
      });
      source.onerror = function() {
        setDockerLogStatus('error');
        source.close();
        if (state.dockerLogSource === source) state.dockerLogSource = null;
        if (!settled) {
          settled = true;
          reject(new Error(t('asset.error.logs')));
        }
      };
    });
  }

  function reloadDockerLogs() {
    return state.dockerLogFollow ? streamDockerLogs() : fetchDockerLogs();
  }

  function refreshDockerLogs() {
    state.dockerLogText = '';
    return reloadDockerLogs()
      .catch(function(err) {
        setDockerLogOutput('');
        setDockerLogStatus('error');
        toast(err.message || t('asset.error.logs'));
        return null;
      });
  }

  function toggleDockerLogFollow() {
    state.dockerLogFollow = !state.dockerLogFollow;
    saveDockerLogFollowPreference(state.dockerLogFollow);
    renderDockerLogFollow();
    if (!state.dockerLogFollow) {
      closeDockerLogStream('paused');
      return Promise.resolve(null);
    }
    return streamDockerLogs().catch(function(err) {
      toast(err.message || t('asset.error.logs'));
      return null;
    });
  }

  function clearDockerLogView() {
    state.dockerLogText = '';
    setDockerLogOutput('');
  }

  function loadDockerContainers(silent) {
    if (!state.selectedDockerHostId) {
      state.dockerPendingById = {};
      state.containers = [];
      state.loadingDocker = false;
      renderDocker();
      return Promise.resolve([]);
    }
    state.loadingDocker = true;
    renderDocker();
    return apiJSON('/api/admin/assets/ssh-hosts/' + encodeURIComponent(state.selectedDockerHostId) + '/docker-containers')
      .then(function(items) {
        state.containers = items || [];
        state.loadingDocker = false;
        renderDocker();
        return state.containers;
      })
      .catch(function(err) {
        state.containers = [];
        state.loadingDocker = false;
        renderDocker();
        if (!silent) toast(err.message || t('asset.error.load'));
        throw err;
      });
  }

  function loadDockerNetworksForList(silent) {
    if (!state.selectedDockerHostId) {
      state.dockerNetworks = [];
      state.loadingDockerNetworks = false;
      renderDockerNetworks();
      return Promise.resolve([]);
    }
    state.loadingDockerNetworks = true;
    renderDockerNetworks();
    return apiJSON('/api/admin/assets/ssh-hosts/' + encodeURIComponent(state.selectedDockerHostId) + '/docker-networks')
      .then(function(items) {
        state.dockerNetworks = items || [];
        state.loadingDockerNetworks = false;
        renderDockerNetworks();
        renderDockerNetworkOptions();
        return state.dockerNetworks;
      })
      .catch(function(err) {
        state.dockerNetworks = [];
        state.loadingDockerNetworks = false;
        renderDockerNetworks();
        if (!silent) toast(err.message || t('asset.error.load'));
        throw err;
      });
  }

  function loadDockerVolumes(silent) {
    if (!state.selectedDockerHostId) {
      state.dockerVolumes = [];
      state.loadingDockerVolumes = false;
      renderDockerVolumes();
      return Promise.resolve([]);
    }
    state.loadingDockerVolumes = true;
    renderDockerVolumes();
    return apiJSON('/api/admin/assets/ssh-hosts/' + encodeURIComponent(state.selectedDockerHostId) + '/docker-volumes')
      .then(function(items) {
        state.dockerVolumes = items || [];
        state.loadingDockerVolumes = false;
        renderDockerVolumes();
        return state.dockerVolumes;
      })
      .catch(function(err) {
        state.dockerVolumes = [];
        state.loadingDockerVolumes = false;
        renderDockerVolumes();
        if (!silent) toast(err.message || t('asset.error.load'));
        throw err;
      });
  }

  function loadDockerImages(silent) {
    if (!state.selectedDockerHostId) {
      state.dockerImages = [];
      state.loadingDockerImages = false;
      renderDockerImages();
      return Promise.resolve([]);
    }
    state.loadingDockerImages = true;
    renderDockerImages();
    return apiJSON('/api/admin/assets/ssh-hosts/' + encodeURIComponent(state.selectedDockerHostId) + '/docker-images')
      .then(function(items) {
        state.dockerImages = items || [];
        state.loadingDockerImages = false;
        renderDockerImages();
        renderDockerImageOptions();
        return state.dockerImages;
      })
      .catch(function(err) {
        state.dockerImages = [];
        state.loadingDockerImages = false;
        renderDockerImages();
        if (!silent) toast(err.message || t('asset.error.load'));
        throw err;
      });
  }

  function setDockerResourceTab(tab) {
    state.dockerResourceTab = tab || 'containers';
    renderDocker();
    if (state.dockerResourceTab === 'containers') loadDockerContainers(false).catch(function() {});
    if (state.dockerResourceTab === 'networks') loadDockerNetworksForList(false).catch(function() {});
    if (state.dockerResourceTab === 'volumes') loadDockerVolumes(false).catch(function() {});
    if (state.dockerResourceTab === 'images') loadDockerImages(false).catch(function() {});
  }

  function refreshDockerResource() {
    if (state.dockerResourceTab === 'networks') {
      return loadDockerNetworksForList(false).then(function() { toast(t('asset.toast.docker_networks_refreshed'), 'success'); });
    }
    if (state.dockerResourceTab === 'volumes') {
      return loadDockerVolumes(false).then(function() { toast(t('asset.toast.docker_volumes_refreshed'), 'success'); });
    }
    if (state.dockerResourceTab === 'images') {
      return loadDockerImages(false).then(function() { toast(t('asset.toast.docker_images_refreshed'), 'success'); });
    }
    return loadDockerContainers(false).then(function() { toast(t('asset.toast.docker_refreshed'), 'success'); });
  }

  function createDockerNetwork() {
    promptValue(t('asset.docker.network.name'), '').then(function(name) {
      name = (name || '').trim();
      if (!name) return;
      return apiJSON('/api/admin/assets/ssh-hosts/' + encodeURIComponent(state.selectedDockerHostId) + '/docker-networks', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ name: name, driver: 'bridge' })
      }).then(function() {
        toast(t('asset.toast.docker_network_created'), 'success');
        return loadDockerNetworksForList(true);
      });
    }).catch(function(err) { toast(err.message || t('asset.error.docker_action')); });
  }

  function createDockerVolume() {
    promptValue(t('asset.docker.volume.name'), '').then(function(name) {
      name = (name || '').trim();
      if (!name) return;
      return apiJSON('/api/admin/assets/ssh-hosts/' + encodeURIComponent(state.selectedDockerHostId) + '/docker-volumes', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ name: name, driver: 'local' })
      }).then(function() {
        toast(t('asset.toast.docker_volume_created'), 'success');
        return loadDockerVolumes(true);
      });
    }).catch(function(err) { toast(err.message || t('asset.error.docker_action')); });
  }

  function pullDockerImage() {
    promptValue(t('asset.docker.image.name'), '').then(function(image) {
      image = (image || '').trim();
      if (!image) return;
      return apiJSON('/api/admin/assets/ssh-hosts/' + encodeURIComponent(state.selectedDockerHostId) + '/docker-images', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ image: image })
      }).then(function() {
        toast(t('asset.toast.docker_image_pulled'), 'success');
        return loadDockerImages(true);
      });
    }).catch(function(err) { toast(err.message || t('asset.error.docker_action')); });
  }

  function pruneDockerResource() {
    if (!state.selectedDockerHostId) return;
    var resource = state.dockerResourceTab || 'containers';
    var labelKey = {
      containers: 'asset.docker.tab.containers',
      networks: 'asset.docker.tab.networks',
      volumes: 'asset.docker.tab.volumes',
      images: 'asset.docker.tab.images'
    }[resource] || 'asset.tab.docker';
    BSDialog.confirm2(format('asset.confirm.prune_docker', { name: t(labelKey) })).then(function(ok) {
      if (!ok) return;
      $('#pruneDockerBtn').disabled = true;
      return apiJSON('/api/admin/assets/ssh-hosts/' + encodeURIComponent(state.selectedDockerHostId) + '/docker/' + encodeURIComponent(resource) + '/prune', {
        method: 'POST'
      }).then(function() {
        toast(t('asset.toast.docker_prune_done'), 'success');
        return refreshDockerResource();
      }).finally(function() {
        $('#pruneDockerBtn').disabled = false;
      });
    }).catch(function(err) {
      $('#pruneDockerBtn').disabled = false;
      toast(err.message || t('asset.error.docker_action'));
    });
  }

  function deleteDockerObject(kind, id) {
    if (!state.selectedDockerHostId || !id) return;
    var path = kind === 'network' ? 'docker-networks' : kind === 'volume' ? 'docker-volumes' : 'docker-images';
    var messageKey = kind === 'network' ? 'asset.confirm.delete_docker_network' : kind === 'volume' ? 'asset.confirm.delete_docker_volume' : 'asset.confirm.delete_docker_image';
    BSDialog.confirm2(format(messageKey, { name: id })).then(function(ok) {
      if (!ok) return;
      return apiJSON('/api/admin/assets/ssh-hosts/' + encodeURIComponent(state.selectedDockerHostId) + '/' + path + '/' + encodeURIComponent(id), { method: 'DELETE' })
        .then(function() {
          toast(t('asset.toast.deleted'), 'success');
          if (kind === 'network') return loadDockerNetworksForList(true);
          if (kind === 'volume') return loadDockerVolumes(true);
          return loadDockerImages(true);
        });
    }).catch(function(err) { toast(err.message || t('asset.error.delete')); });
  }

  function openDockerHost(id) {
    if (state.assetMode === 'index') {
      window.location.href = '/admin/assets/ssh-hosts/' + encodeURIComponent(id) + '/docker';
      return;
    }
    state.selectedDockerHostId = String(id || '');
    state.dockerPendingById = {};
    state.containers = [];
    state.dockerNetworks = [];
    state.dockerVolumes = [];
    state.dockerImages = [];
    state.dockerResourceTab = 'containers';
    setTab('docker');
    renderDocker();
    loadDockerContainers(false).catch(function() {});
  }

  function loadFiles(silent) {
    var base = fileAPIBase();
    if (!base) {
      state.files = [];
      state.fileListLimit = 0;
      state.fileListTruncated = false;
      state.loadingFiles = false;
      renderFiles();
      return Promise.resolve([]);
    }
    state.loadingFiles = true;
    state.fileListLimit = 0;
    state.fileListTruncated = false;
    renderFiles();
    return apiJSON(base + '?path=' + encodeURIComponent(state.filePath || '.'))
      .then(function(result) {
        if (Array.isArray(result)) {
          state.files = result;
          state.fileListLimit = 0;
          state.fileListTruncated = false;
        } else {
          state.files = result && Array.isArray(result.items) ? result.items : [];
          state.fileListLimit = result && result.limit ? result.limit : 0;
          state.fileListTruncated = !!(result && result.truncated);
        }
        state.loadingFiles = false;
        renderFiles();
        return state.files;
      })
      .catch(function(err) {
        state.files = [];
        state.fileListLimit = 0;
        state.fileListTruncated = false;
        state.loadingFiles = false;
        renderFiles();
        if (!silent) toast(err.message || t('asset.error.load'));
        throw err;
      });
  }

  function startFilePathEdit() {
    if (!selectedFileTarget()) return;
    cancelFileRename();
    state.editingFilePath = true;
    state.filePathInputValue = state.filePath || '.';
    renderFileBreadcrumb();
  }

  function cancelFilePathEdit() {
    if (!state.editingFilePath) return;
    state.editingFilePath = false;
    state.filePathInputValue = state.filePath || '.';
    renderFileBreadcrumb();
  }

  function updateFilePathInput(value) {
    if (!state.editingFilePath) return;
    state.filePathInputValue = value;
  }

  function submitFilePathInput(value) {
    var nextPath = normalizeFilePathInput(value == null ? state.filePathInputValue : value);
    return goToFilePath(nextPath);
  }

  function goToFilePath(nextPath) {
    if (!selectedFileTarget()) return Promise.resolve([]);
    var targetPath = normalizeFilePathInput(nextPath);
    var previousPath = state.filePath || '.';
    var previousFiles = state.files.slice();
    var previousLimit = state.fileListLimit;
    var previousTruncated = state.fileListTruncated;
    cancelFileRename();
    if (targetPath === previousPath) {
      state.editingFilePath = false;
      state.filePathInputValue = previousPath;
      renderFiles();
      return Promise.resolve(state.files);
    }
    state.filePath = targetPath;
    return loadFiles(false).then(function(items) {
      state.lastGoodFilePath = targetPath;
      state.editingFilePath = false;
      state.filePathInputValue = targetPath;
      renderFiles();
      return items;
    }).catch(function(err) {
      state.filePath = previousPath || state.lastGoodFilePath || '.';
      state.filePathInputValue = state.filePath;
      state.editingFilePath = false;
      state.files = previousFiles;
      state.fileListLimit = previousLimit;
      state.fileListTruncated = previousTruncated;
      state.loadingFiles = false;
      renderFiles();
      throw err;
    });
  }

  function normalizeFilePathInput(value) {
    var path = String(value || '').trim();
    if (!path) return '.';
    if (path.charAt(0) === '/') return '/' + path.replace(/^\/+/, '');
    return path;
  }

  function openFilesHost(id) {
    if (state.assetMode === 'index') {
      window.location.href = '/admin/assets/ssh-hosts/' + encodeURIComponent(id) + '/files';
      return;
    }
    state.selectedFilesHostId = String(id || '');
    state.selectedWebDAVServerId = '';
    state.files = [];
    state.filePath = '.';
    state.lastGoodFilePath = '.';
    state.editingFilePath = false;
    state.filePathInputValue = '.';
    state.fileListLimit = 0;
    state.fileListTruncated = false;
    setTab('files');
    renderFiles();
    loadFiles(false).then(function() {
      state.lastGoodFilePath = state.filePath || '.';
    }).catch(function() {});
  }

  function openWebDAVFiles(id) {
    if (String(id) === 'local') {
      window.location.href = '/webdav';
      return;
    }
    if (state.assetMode === 'index') {
      window.location.href = '/admin/assets/webdav-servers/' + encodeURIComponent(id) + '/files';
      return;
    }
    state.selectedWebDAVServerId = String(id || '');
    state.selectedFilesHostId = '';
    state.files = [];
    state.filePath = '.';
    state.lastGoodFilePath = '.';
    state.editingFilePath = false;
    state.filePathInputValue = '.';
    state.fileListLimit = 0;
    state.fileListTruncated = false;
    setTab('files');
    renderFiles();
    loadFiles(false).then(function() {
      state.lastGoodFilePath = state.filePath || '.';
    }).catch(function() {});
  }

  function parentFilePath(value) {
    var current = value || '.';
    if (current === '/' || current === '.') return current;
    var absolute = current.charAt(0) === '/';
    var parts = current.split('/').filter(Boolean);
    parts.pop();
    if (!parts.length) return absolute ? '/' : '.';
    return (absolute ? '/' : '') + parts.join('/');
  }

  function joinFilePath(base, name) {
    if (!base || base === '.') return name;
    if (base === '/') return '/' + name;
    return base.replace(/\/+$/, '') + '/' + name;
  }

  function focusFileRenameInput() {
    if (!state.fileRename || state.fileRename.saving) return;
    window.requestAnimationFrame(function() {
      var input = $('[data-file-rename-input="true"]');
      if (!input) return;
      if (window.BookStarkFormGuards && typeof window.BookStarkFormGuards.markNonCredentialInput === 'function') window.BookStarkFormGuards.markNonCredentialInput(input);
      input.focus();
      input.select();
    });
  }

  function fileNameFromPath(value) {
    var parts = String(value || '').split('/').filter(Boolean);
    return parts.length ? parts[parts.length - 1] : String(value || '');
  }

  function openFileDir(path) {
    goToFilePath(path || '.').catch(function() {});
  }

  function downloadFile(path) {
    var base = fileAPIBase();
    if (!base || !path) return;
    window.location.href = base + '/download?path=' + encodeURIComponent(path);
  }

  function previewFileURL(path) {
    var base = fileAPIBase();
    return base && path ? base + '/preview?path=' + encodeURIComponent(path) : '';
  }

  function filePreviewKind(path) {
    var value = String(path || '').split('?')[0].split('#')[0];
    var lastDot = value.lastIndexOf('.');
    if (lastDot < 0) return '';
    var ext = value.slice(lastDot + 1).toLowerCase();
    if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'svg'].indexOf(ext) >= 0) return 'image';
    if (['mp4', 'webm', 'mov', 'm4v', 'ogv', 'avi', 'mkv'].indexOf(ext) >= 0) return 'video';
    return '';
  }

  function openFilePreview(path) {
    var kind = filePreviewKind(path);
    var url = previewFileURL(path);
    if (!kind || !url) {
      openFileEditor(path);
      return;
    }
    closeFilePreview();
    state.filePreviewPath = path;
    state.filePreviewKind = kind;
    $('#filePreviewTitle').textContent = fileNameFromPath(path);
    $('#filePreviewSubtitle').textContent = path;
    $('#filePreviewOpen').href = url;
    var image = $('#filePreviewImage');
    var video = $('#filePreviewVideo');
    image.classList.toggle('asset-hidden', kind !== 'image');
    video.classList.toggle('asset-hidden', kind !== 'video');
    if (kind === 'image') {
      image.src = url;
      image.alt = fileNameFromPath(path);
    } else {
      video.src = url;
      video.load();
    }
    openModal('#filePreviewModal');
  }

  function closeFilePreview() {
    var image = $('#filePreviewImage');
    var video = $('#filePreviewVideo');
    if (video) {
      video.pause();
      video.removeAttribute('src');
      video.load();
    }
    if (image) {
      image.removeAttribute('src');
      image.alt = '';
    }
    state.filePreviewPath = '';
    state.filePreviewKind = '';
  }

  function openFileEditor(path) {
    var base = fileAPIBase();
    if (!base || !path || !window.BookStarkCodeEditorModal) return;
    closeFileEditor();
    state.fileEditorPath = path;
    var loadToken = ++state.fileEditorLoadToken;
    var editor = window.BookStarkCodeEditorModal.open({
      title: path.split('/').filter(Boolean).pop() || path,
      subtitle: path,
      fileName: path,
      loading: true,
      loadingText: t('asset.files.editor.loading'),
      savingSubtitle: t('asset.files.editor.saving'),
      errorSubtitle: t('asset.session.status.error'),
      closeOnSave: false,
      onSave: function(nextContent) {
        state.fileEditorSaving = true;
        return apiJSON(base + '/content', {
          method: 'PUT',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ path: path, content: nextContent })
        }).then(function() {
          toast(t('asset.files.editor.saved'), 'success');
          return loadFiles(true);
        }).finally(function() {
          state.fileEditorSaving = false;
        });
      },
      onError: function(err) {
        toast(err.message || t('asset.error.save'));
      },
      onCommandUnavailable: function() {
        toast(t('asset.files.editor.command_unavailable'));
      },
      onClose: function() {
        if (state.fileEditorLoadToken !== loadToken) return;
        if (state.fileEditorLoadController) state.fileEditorLoadController.abort();
        state.fileEditorLoadController = null;
        state.fileEditorPath = '';
        state.fileEditorSaving = false;
        state.fileEditorLoadToken += 1;
      }
    });

    function loadContent() {
      if (state.fileEditorLoadToken !== loadToken || state.fileEditorPath !== path) return;
      if (state.fileEditorLoadController) state.fileEditorLoadController.abort();
      var controller = typeof AbortController === 'function' ? new AbortController() : null;
      state.fileEditorLoadController = controller;
      editor.setLoading(true, t('asset.files.editor.loading'));
      apiJSON(base + '/content?path=' + encodeURIComponent(path), controller ? { signal: controller.signal } : {})
      .then(function(data) {
        if (state.fileEditorLoadToken !== loadToken || state.fileEditorPath !== path) return;
        var content = data && typeof data.content === 'string' ? data.content : '';
        editor.setContent(content, path);
      })
      .catch(function(err) {
        if (err && err.name === 'AbortError') return;
        if (state.fileEditorLoadToken !== loadToken || state.fileEditorPath !== path) return;
        editor.showLoadError(err || new Error(t('asset.error.file_action')), loadContent);
      })
      .finally(function() {
        if (state.fileEditorLoadToken === loadToken && state.fileEditorLoadController === controller) {
          state.fileEditorLoadController = null;
        }
      });
    }

    loadContent();
  }

  function closeFileEditor(resetModal) {
    if (state.fileEditorLoadController) state.fileEditorLoadController.abort();
    state.fileEditorLoadController = null;
    state.fileEditorLoadToken += 1;
    state.fileEditorPath = '';
    state.fileEditorSaving = false;
    if (resetModal !== false && window.BookStarkCodeEditorModal) window.BookStarkCodeEditorModal.close();
  }

  function uploadSelectedFile(file) {
    var base = fileAPIBase();
    if (!base || !file) return;
    var form = new FormData();
    form.append('file', file);
    csrfFetch(base + '/upload?path=' + encodeURIComponent(state.filePath || '.'), {
      method: 'POST',
      body: form
    }).then(function(res) {
      return res.json().then(function(data) {
        if (!res.ok || data.code !== 0) throw new Error(data.message || t('asset.error.upload'));
        return data.data;
      });
    }).then(function() {
      toast(t('asset.toast.upload_done'), 'success');
      return loadFiles(true);
    }).catch(function(err) {
      toast(err.message || t('asset.error.upload'));
    });
  }

  function createFileDirectory() {
    promptValue(t('asset.files.new_dir'), '').then(function(name) {
      if (!name) return;
      name = name.trim();
      if (!name) return;
      var remotePath = joinFilePath(state.filePath || '.', name);
      return apiJSON(fileAPIBase() + '/mkdir', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ path: remotePath })
      }).then(function() {
        toast(t('asset.toast.file_done'), 'success');
        return loadFiles(true);
      });
    }).catch(function(err) {
      toast(err.message || t('asset.error.file_action'));
    });
  }

  function renameFile(oldPath) {
    var item = state.files.find(function(file) { return file.path === oldPath; });
    var currentName = item ? item.name : fileNameFromPath(oldPath);
    state.fileRename = {
      oldPath: oldPath,
      originalName: currentName,
      value: currentName,
      saving: false
    };
    renderFiles();
  }

  function updateFileRenameValue(value) {
    if (!state.fileRename) return;
    state.fileRename.value = value;
  }

  function cancelFileRename() {
    if (!state.fileRename || state.fileRename.saving) return;
    state.fileRename = null;
    renderFiles();
  }

  function submitFileRename() {
    if (!state.fileRename || state.fileRename.saving) return;
    var oldPath = state.fileRename.oldPath;
    var name = String(state.fileRename.value || '').trim();
    if (!name) {
      toast(t('asset.files.rename.empty'));
      return;
    }
    if (name.indexOf('/') !== -1) {
      toast(t('asset.files.rename.invalid'));
      return;
    }
    if (name === state.fileRename.originalName) {
      state.fileRename = null;
      renderFiles();
      return;
    }
    state.fileRename.saving = true;
    renderFiles();
    var newPath = joinFilePath(parentFilePath(oldPath), name);
    apiJSON(fileAPIBase() + '/rename', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ old_path: oldPath, new_path: newPath })
    }).then(function() {
      toast(t('asset.toast.file_done'), 'success');
      state.fileRename = null;
      return loadFiles(true);
    }).catch(function(err) {
      if (state.fileRename && state.fileRename.oldPath === oldPath) {
        state.fileRename.saving = false;
        renderFiles();
      }
      toast(err.message || t('asset.error.file_action'));
    });
  }

  function copyFile(srcPath) {
    promptValue(t('asset.files.copy_to'), srcPath).then(function(target) {
      if (!target) return;
      target = target.trim();
      if (!target || target === srcPath) return;
      return apiJSON(fileAPIBase() + '/copy', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ source_path: srcPath, target_path: target })
      }).then(function() {
        toast(t('asset.toast.file_done'), 'success');
        return loadFiles(true);
      });
    }).catch(function(err) {
      toast(err.message || t('asset.error.file_action'));
    });
  }

  function chmodFile(path) {
    promptValue(t('asset.files.chmod'), '0644').then(function(mode) {
      if (!mode) return;
      mode = mode.trim();
      if (!mode) return;
      return apiJSON('/api/admin/assets/ssh-hosts/' + encodeURIComponent(state.selectedFilesHostId) + '/files/chmod', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ path: path, mode: mode })
      }).then(function() {
        toast(t('asset.toast.file_done'), 'success');
        return loadFiles(true);
      });
    }).catch(function(err) {
      toast(err.message || t('asset.error.file_action'));
    });
  }

  function confirmDeleteFile(path, isDir) {
    BSDialog.confirm2(format('asset.confirm.delete_file', { name: path })).then(function(ok) {
      if (!ok) return;
      apiJSON(fileAPIBase() + '?path=' + encodeURIComponent(path) + '&recursive=' + (isDir ? 'true' : 'false'), {
        method: 'DELETE'
      }).then(function() {
        toast(t('asset.toast.deleted'), 'success');
        return loadFiles(true);
      }).catch(function(err) {
        toast(err.message || t('asset.error.delete'));
      });
    });
  }

  function saveSettings() {
    var body = {
      terminal_idle_timeout_seconds: Number($('#settingIdle').value || 1800),
      terminal_scrollback_lines: normalizeTerminalScrollback($('#settingScrollback').value),
      credential_secret: $('#settingCredentialSecret').value.trim()
    };
    apiJSON('/api/admin/assets/settings', { method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) })
      .then(function(settings) {
        state.settings = settings || body;
        applySettings();
        toast(t('asset.toast.settings_saved'), 'success');
      })
      .catch(function(err) { toast(err.message || t('asset.error.save')); });
  }

  function wsURL(path) {
    var proto = window.location.protocol === 'https:' ? 'wss://' : 'ws://';
    return proto + window.location.host + path;
  }

  function writeTerminal(text) {
    queueTerminalWrite(text);
  }

  function queueTerminalWrite(text) {
    if (!state.terminal || !text) return;
    text = String(text);
    var bytes = text.length;
    state.terminalWriteQueue.push(text);
    state.terminalWriteQueueBytes += bytes;
    while (state.terminalWriteQueueBytes > terminalWriteQueueLimit && state.terminalWriteQueue.length) {
      var removed = state.terminalWriteQueue.shift();
      state.terminalWriteQueueBytes -= removed.length;
      state.terminalWriteTruncated = true;
    }
    scheduleTerminalWriteFlush();
  }

  function scheduleTerminalWriteFlush() {
    if (state.terminalWriteScheduled) return;
    state.terminalWriteScheduled = true;
    window.requestAnimationFrame(flushTerminalWriteQueue);
  }

  function flushTerminalWriteQueue() {
    state.terminalWriteScheduled = false;
    if (!state.terminal) {
      clearTerminalWriteQueue();
      return;
    }
    if (state.terminalWriteTruncated) {
      state.terminal.write('\r\n[output truncated: terminal write queue exceeded]\r\n');
      state.terminalWriteTruncated = false;
    }
    var written = 0;
    while (state.terminalWriteQueue.length && written < terminalWriteFrameLimit) {
      var chunk = state.terminalWriteQueue.shift();
      state.terminalWriteQueueBytes -= chunk.length;
      if (written + chunk.length > terminalWriteFrameLimit) {
        var sliceAt = terminalWriteFrameLimit - written;
        var head = chunk.slice(0, sliceAt);
        var rest = chunk.slice(sliceAt);
        state.terminal.write(head);
        state.terminalWriteQueue.unshift(rest);
        state.terminalWriteQueueBytes += rest.length;
        written += head.length;
        break;
      }
      state.terminal.write(chunk);
      written += chunk.length;
    }
    if (state.terminalWriteQueue.length) scheduleTerminalWriteFlush();
  }

  function clearTerminalWriteQueue() {
    state.terminalWriteQueue = [];
    state.terminalWriteQueueBytes = 0;
    state.terminalWriteScheduled = false;
    state.terminalWriteTruncated = false;
  }

  function writeTerminalNow(text) {
    if (state.terminal) {
      state.terminal.write(text);
    }
  }

  function sendTerminalInput(data, notifyWhenClosed) {
    if (!state.socket || state.socket.readyState !== WebSocket.OPEN) {
      if (notifyWhenClosed) toast(t('asset.error.terminal_closed'));
      return;
    }
    state.socket.send(JSON.stringify({ type: 'input', data: data }));
  }

  function copyTextToClipboard(text) {
    if (!text) return;
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).catch(function() {});
      return;
    }
    var textarea = document.createElement('textarea');
    textarea.value = text;
    textarea.setAttribute('readonly', 'readonly');
    textarea.style.position = 'fixed';
    textarea.style.left = '-9999px';
    document.body.appendChild(textarea);
    textarea.select();
    try {
      document.execCommand('copy');
    } catch (err) {
      // Ignore clipboard failures; selection should not interrupt terminal use.
    }
    textarea.remove();
  }

  function pasteClipboardToTerminal(event) {
    event.preventDefault();
    if (!navigator.clipboard || !navigator.clipboard.readText) {
      toast(t('asset.error.clipboard'));
      return;
    }
    navigator.clipboard.readText()
      .then(function(text) {
        if (text) sendTerminalInput(text, true);
        if (state.terminal) state.terminal.focus();
      })
      .catch(function() {
        toast(t('asset.error.clipboard'));
      });
  }

  function sendTerminalResize() {
    if (!state.terminal || !state.socket || state.socket.readyState !== WebSocket.OPEN) return;
    state.socket.send(JSON.stringify({
      type: 'resize',
      cols: state.terminal.cols,
      rows: state.terminal.rows
    }));
  }

  function fitTerminal() {
    if (!state.fitAddon) return;
    window.requestAnimationFrame(function() {
      try {
        state.fitAddon.fit();
        sendTerminalResize();
      } catch (err) {
        // xterm cannot measure hidden or detached containers; retry on next open/resize.
      }
    });
  }

  function createTerminal() {
    if (typeof Terminal !== 'function') {
      toast('xterm.js not loaded');
      return null;
    }
    var terminal = new Terminal({
      cursorBlink: true,
      convertEol: true,
      scrollback: normalizeTerminalScrollback(state.settings.terminal_scrollback_lines),
      fontFamily: '"SFMono-Regular", Consolas, "Liberation Mono", monospace',
      fontSize: 13,
      lineHeight: 1.2,
      theme: {
        background: '#080b10',
        foreground: '#d8e4f0',
        cursor: '#f8fafc',
        selectionBackground: '#334155',
        black: '#0f172a',
        red: '#ef4444',
        green: '#22c55e',
        yellow: '#eab308',
        blue: '#3b82f6',
        magenta: '#a855f7',
        cyan: '#06b6d4',
        white: '#e2e8f0',
        brightBlack: '#64748b',
        brightRed: '#f87171',
        brightGreen: '#4ade80',
        brightYellow: '#fde047',
        brightBlue: '#60a5fa',
        brightMagenta: '#c084fc',
        brightCyan: '#22d3ee',
        brightWhite: '#f8fafc'
      }
    });
    if (window.FitAddon && typeof window.FitAddon.FitAddon === 'function') {
      state.fitAddon = new window.FitAddon.FitAddon();
      terminal.loadAddon(state.fitAddon);
    }
    terminal.open($('#terminalPane'));
    terminal.onData(function(data) {
      sendTerminalInput(data, false);
    });
    terminal.onSelectionChange(function() {
      copyTextToClipboard(terminal.getSelection());
    });
    if (terminal.element) {
      terminal.element.addEventListener('contextmenu', pasteClipboardToTerminal);
    }
    terminal.onResize(sendTerminalResize);
    state.terminal = terminal;
    fitTerminal();
    terminal.focus();
    return terminal;
  }

  function toggleTerminalMaximized() {
    state.terminalMaximized = !state.terminalMaximized;
    $('.asset-session-window').classList.toggle('maximized', state.terminalMaximized);
    fitTerminal();
  }

  function setTerminalStatus(key) {
    state.terminalStatus = key;
    $('#terminalSubtitle').textContent = t('asset.session.status.' + key);
    setTerminalReconnectVisible(key === 'closed' || key === 'error');
  }

  function setTerminalReconnectVisible(visible) {
    var btn = $('#terminalReconnectBtn');
    if (!btn) return;
    btn.hidden = !visible;
  }

  function reconnectTerminal() {
    if (!state.sessionTarget) return;
    var target = {
      type: state.sessionTarget.type,
      id: state.sessionTarget.id
    };
    openSession(target.type, target.id, { preserveWindowState: true });
  }

  function openSession(type, id, options) {
    options = options || {};
    closeSession({ preserveWindowState: !!options.preserveWindowState });
    state.sessionTarget = { type: type, id: id };
    var url;
    if (type === 'ssh') {
      var host = state.sshHosts.find(function(item) { return String(item.id) === String(id); });
      if (!host) return;
      $('#terminalTitle').textContent = host.name;
      url = '/api/admin/assets/ssh-hosts/' + encodeURIComponent(id) + '/terminal';
    } else {
      var dockerHost = selectedDockerHost();
      var container = state.containers.find(function(item) { return String(item.id) === String(id); });
      if (!container || !dockerHost) return;
      $('#terminalTitle').textContent = container.name;
      url = '/api/admin/assets/ssh-hosts/' + encodeURIComponent(dockerHost.id) + '/docker-containers/' + encodeURIComponent(id) + '/terminal';
    }
    setTerminalStatus('connecting');
    openModal('#sessionModal');
    if (!createTerminal()) return;
    state.socket = new WebSocket(wsURL(url));
    state.socket.onopen = function() {
      fitTerminal();
    };
    state.socket.onmessage = function(event) {
      var msg;
      try {
        msg = JSON.parse(event.data);
      } catch (err) {
        return;
      }
      if (msg.type === 'output') writeTerminal(msg.data || '');
      if (msg.type === 'ready') {
        setTerminalStatus('connected');
      }
      if (msg.type === 'error') {
        setTerminalStatus('error');
        writeTerminalNow('\r\n' + (msg.data || t('asset.error.terminal')) + '\r\n');
      }
      if (msg.type === 'closed') {
        setTerminalStatus('closed');
        writeTerminalNow('\r\n' + (msg.data || t('asset.session.closed')) + '\r\n');
      }
    };
    state.socket.onclose = function() {
      state.socket = null;
      if (state.terminalStatus !== 'error') {
        setTerminalStatus('closed');
      } else {
        setTerminalReconnectVisible(true);
      }
    };
    state.socket.onerror = function() {
      setTerminalStatus('error');
      toast(t('asset.error.terminal'));
    };
  }

  function bindEvents() {
    $$('.asset-tab').forEach(function(btn) {
      btn.addEventListener('click', function() { setTab(btn.dataset.tab); });
    });
    $$('.asset-settings-tab').forEach(function(btn) {
      btn.addEventListener('click', function() { setSettingsTab(btn.dataset.settingsTab); });
    });
    $('#addSshBtn').addEventListener('click', function() { openSshForm(); });
    $('#addWebdavBtn').addEventListener('click', function() { openWebDAVForm(); });
    $('#addCredentialBtn').addEventListener('click', function() { openCredentialForm(); });
    $('#addDockerContainerBtn').addEventListener('click', openDockerCreateForm);
    $('#addDockerNetworkBtn').addEventListener('click', createDockerNetwork);
    $('#addDockerVolumeBtn').addEventListener('click', createDockerVolume);
    $('#pullDockerImageBtn').addEventListener('click', pullDockerImage);
    $('#terminalReconnectBtn').addEventListener('click', reconnectTerminal);
    $('#refreshDockerBtn').addEventListener('click', function() {
      refreshDockerResource().catch(function() {});
    });
    $('#refreshFilesBtn').addEventListener('click', function() {
      loadFiles(false).then(function() {
        toast(t('asset.toast.files_refreshed'), 'success');
      }).catch(function() {});
    });
    $('#fileUpBtn').addEventListener('click', function() {
      goToFilePath(parentFilePath(state.filePath)).catch(function() {});
    });
    $('#uploadFileBtn').addEventListener('click', function() {
      $('#fileUploadInput').click();
    });
    $('#fileUploadInput').addEventListener('change', function() {
      uploadSelectedFile(this.files && this.files[0]);
      this.value = '';
    });
    $('#newDirBtn').addEventListener('click', createFileDirectory);
    $('#filePathBreadcrumb').addEventListener('click', function(event) {
      if (event.target.closest('[data-file-path-input]')) return;
      var btn = event.target.closest('[data-file-path]');
      if (btn) {
        goToFilePath(btn.dataset.filePath || '.').catch(function() {});
        return;
      }
      startFilePathEdit();
    });
    $('#filePathBreadcrumb').addEventListener('dblclick', function(event) {
      if (event.target.closest('[data-file-path-input]')) return;
      startFilePathEdit();
    });
    $('#fileQuickPaths').addEventListener('click', function(event) {
      var btn = event.target.closest('[data-file-quick-path]');
      if (!btn) return;
      goToFilePath(btn.dataset.fileQuickPath || '.').catch(function() {});
    });
    $('#assetMobileFab').addEventListener('click', handleMobileFab);
    $('#sshForm').addEventListener('submit', saveSsh);
    $('#webdavForm').addEventListener('submit', saveWebDAV);
    $('#credentialForm').addEventListener('submit', saveCredential);
    $('#dockerCreateForm').addEventListener('submit', saveDockerCreate);
    bindAutocomplete('ssh-shell');
    bindAutocomplete('docker-network');
    bindAutocomplete('docker-image');
    $$('[data-close-modal]').forEach(function(btn) {
      btn.addEventListener('click', function(event) {
        if ((state.credentialModalSource === 'ssh-picker' || state.credentialModalSource === 'webdav-picker') && event.currentTarget.closest('#credentialModal')) {
          cancelCredentialModal();
          return;
        }
        closeModals();
      });
    });
    $$('.asset-modal-backdrop').forEach(function(modal) {
      modal.addEventListener('click', function(event) {
        if (event.target !== modal) return;
        if (modal.id === 'sessionModal') return;
        if ((state.credentialModalSource === 'ssh-picker' || state.credentialModalSource === 'webdav-picker') && modal.id === 'credentialModal') {
          cancelCredentialModal();
          return;
        }
        closeModals();
      });
    });
    $$('[data-credential-auth]').forEach(function(btn) {
      btn.addEventListener('click', function() { setCredentialAuthMode(btn.dataset.credentialAuth); });
    });
    $('#credentialPasswordToggle').addEventListener('click', function() {
      setCredentialPasswordVisible($('#credentialPassword').type === 'password');
    });
    $('#settingCredentialSecretToggle').addEventListener('click', function() {
      setCredentialSecretVisible($('#settingCredentialSecret').type === 'password');
    });
    $('#sshCredentialSearch').addEventListener('focus', function() {
      this.select();
      renderCredentialPicker($('#sshCredential').value, '', true);
    });
    $('#sshCredentialSearch').addEventListener('input', function() {
      renderCredentialPicker($('#sshCredential').value, this.value, true);
    });
    $('#sshCredentialSearch').addEventListener('keydown', function(event) {
      var dropdown = $('#sshCredentialDropdown');
      var selector = '.asset-combobox-option, .asset-combobox-create';
      if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
        event.preventDefault();
        renderCredentialPicker($('#sshCredential').value, this.value, true);
        setTimeout(function() {
          focusDropdownItem(dropdown, selector, event.key === 'ArrowDown' ? 0 : -1);
        }, 0);
      } else if (event.key === 'Enter' && dropdownIsOpen(dropdown)) {
        if (clickDropdownActiveItem(dropdown, selector)) event.preventDefault();
      } else if (event.key === 'Escape' && dropdownIsOpen(dropdown)) {
        event.preventDefault();
        var selected = selectedCredential($('#sshCredential').value);
        $('#sshCredentialSearch').value = selected ? credentialLabel(selected) : '';
        hideCredentialDropdown();
      }
    });
    $('#sshCredentialSearch').addEventListener('blur', function() {
      setTimeout(function() {
        var dropdown = $('#sshCredentialDropdown');
        if (dropdown && dropdown.contains(document.activeElement)) return;
        var selected = selectedCredential($('#sshCredential').value);
        $('#sshCredentialSearch').value = selected ? credentialLabel(selected) : '';
        hideCredentialDropdown();
      }, 120);
    });
    $('#sshCredentialDropdown').addEventListener('mousedown', function(event) {
      event.preventDefault();
    });
    $('#sshCredentialDropdown').addEventListener('click', function(event) {
      var create = event.target.closest('[data-action="create-credential"]');
      if (create) {
        hideCredentialDropdown();
        openCredentialForm(null, { source: 'ssh-picker' });
        return;
      }
      var option = event.target.closest('[data-id]');
      if (option) selectCredential(option.dataset.id);
    });
    $('#sshCredentialDropdown').addEventListener('keydown', function(event) {
      var dropdown = $('#sshCredentialDropdown');
      var input = $('#sshCredentialSearch');
      var selector = '.asset-combobox-option, .asset-combobox-create';
      if (event.key === 'ArrowDown') {
        event.preventDefault();
        moveDropdownFocus(dropdown, selector, 1);
      } else if (event.key === 'ArrowUp') {
        event.preventDefault();
        moveDropdownFocus(dropdown, selector, -1);
      } else if (event.key === 'Home') {
        event.preventDefault();
        focusDropdownItem(dropdown, selector, 0);
      } else if (event.key === 'End') {
        event.preventDefault();
        focusDropdownItem(dropdown, selector, -1);
      } else if (event.key === 'Escape') {
        event.preventDefault();
        var selected = selectedCredential($('#sshCredential').value);
        input.value = selected ? credentialLabel(selected) : '';
        hideCredentialDropdown();
        input.focus();
      } else if (event.key === 'Tab') {
        hideCredentialDropdown();
      }
    });
    $('#webdavCredentialSearch').addEventListener('focus', function() {
      this.select();
      renderWebDAVCredentialPicker($('#webdavCredential').value, '', true);
    });
    $('#webdavCredentialSearch').addEventListener('input', function() {
      renderWebDAVCredentialPicker($('#webdavCredential').value, this.value, true);
    });
    $('#webdavCredentialSearch').addEventListener('keydown', function(event) {
      var dropdown = $('#webdavCredentialDropdown');
      var selector = '.asset-combobox-option, .asset-combobox-create';
      if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
        event.preventDefault();
        renderWebDAVCredentialPicker($('#webdavCredential').value, this.value, true);
        setTimeout(function() {
          focusDropdownItem(dropdown, selector, event.key === 'ArrowDown' ? 0 : -1);
        }, 0);
      } else if (event.key === 'Enter' && dropdownIsOpen(dropdown)) {
        if (clickDropdownActiveItem(dropdown, selector)) event.preventDefault();
      } else if (event.key === 'Escape' && dropdownIsOpen(dropdown)) {
        event.preventDefault();
        var selected = selectedWebDAVCredential($('#webdavCredential').value);
        $('#webdavCredentialSearch').value = selected ? credentialLabel(selected) : '';
        hideWebDAVCredentialDropdown();
      }
    });
    $('#webdavCredentialSearch').addEventListener('blur', function() {
      setTimeout(function() {
        var dropdown = $('#webdavCredentialDropdown');
        if (dropdown && dropdown.contains(document.activeElement)) return;
        var selected = selectedWebDAVCredential($('#webdavCredential').value);
        $('#webdavCredentialSearch').value = selected ? credentialLabel(selected) : '';
        hideWebDAVCredentialDropdown();
      }, 120);
    });
    $('#webdavCredentialDropdown').addEventListener('mousedown', function(event) {
      event.preventDefault();
    });
    $('#webdavCredentialDropdown').addEventListener('click', function(event) {
      var create = event.target.closest('[data-action="create-credential"]');
      if (create) {
        hideWebDAVCredentialDropdown();
        openCredentialForm(null, { source: 'webdav-picker' });
        return;
      }
      var option = event.target.closest('[data-id]');
      if (option) selectWebDAVCredential(option.dataset.id);
    });
    $('#webdavCredentialDropdown').addEventListener('keydown', function(event) {
      var dropdown = $('#webdavCredentialDropdown');
      var input = $('#webdavCredentialSearch');
      var selector = '.asset-combobox-option, .asset-combobox-create';
      if (event.key === 'ArrowDown') {
        event.preventDefault();
        moveDropdownFocus(dropdown, selector, 1);
      } else if (event.key === 'ArrowUp') {
        event.preventDefault();
        moveDropdownFocus(dropdown, selector, -1);
      } else if (event.key === 'Home') {
        event.preventDefault();
        focusDropdownItem(dropdown, selector, 0);
      } else if (event.key === 'End') {
        event.preventDefault();
        focusDropdownItem(dropdown, selector, -1);
      } else if (event.key === 'Escape') {
        event.preventDefault();
        var selected = selectedWebDAVCredential($('#webdavCredential').value);
        input.value = selected ? credentialLabel(selected) : '';
        hideWebDAVCredentialDropdown();
        input.focus();
      } else if (event.key === 'Tab') {
        hideWebDAVCredentialDropdown();
      }
    });
    $('#sshSearch').addEventListener('input', renderSsh);
    $('#webdavSearch').addEventListener('input', renderWebDAV);
    $('#dockerSearch').addEventListener('input', renderDocker);
    $('#pruneDockerBtn').addEventListener('click', pruneDockerResource);
    $$('.asset-docker-subtab').forEach(function(btn) {
      btn.addEventListener('click', function() { setDockerResourceTab(btn.dataset.dockerResourceTab); });
    });
    $('#dockerCreateModal').addEventListener('click', function(event) {
      var tabBtn = event.target.closest('[data-docker-create-tab]');
      if (tabBtn) setDockerCreateTab(tabBtn.dataset.dockerCreateTab);
      var addBtn = event.target.closest('[data-docker-create-add]');
      if (addBtn) addDockerCreateRow(addBtn.dataset.dockerCreateAdd);
      var removeBtn = event.target.closest('[data-docker-create-remove]');
      if (removeBtn) {
        var row = removeBtn.closest('[data-docker-create-row]');
        if (row) row.remove();
      }
    });
    $$('[data-status-filter="ssh"]').forEach(function(input) {
      input.addEventListener('change', renderSsh);
    });
    $$('[data-status-filter="webdav"]').forEach(function(input) {
      input.addEventListener('change', renderWebDAV);
    });
    $$('[data-status-filter="docker"]').forEach(function(input) {
      input.addEventListener('change', renderDocker);
    });
    document.body.addEventListener('input', function(event) {
      var input = event.target.closest('[data-file-rename-input]');
      if (input) {
        updateFileRenameValue(input.value);
        return;
      }
      input = event.target.closest('[data-file-path-input]');
      if (input) updateFilePathInput(input.value);
    });
    document.body.addEventListener('keydown', function(event) {
      var input = event.target.closest('[data-file-rename-input]');
      if (input) {
        if (event.key === 'Enter') {
          event.preventDefault();
          submitFileRename();
        } else if (event.key === 'Escape') {
          event.preventDefault();
          cancelFileRename();
        }
        return;
      }
      input = event.target.closest('[data-file-path-input]');
      if (input) {
        if (event.key === 'Enter') {
          event.preventDefault();
          submitFilePathInput(input.value).catch(function() {});
        } else if (event.key === 'Escape') {
          event.preventDefault();
          cancelFilePathEdit();
        }
      }
    });
    document.body.addEventListener('focusout', function(event) {
      var renameInput = event.target.closest('[data-file-rename-input]');
      var pathInput = event.target.closest('[data-file-path-input]');
      if (!renameInput && !pathInput) return;
      window.setTimeout(function() {
        var active = document.activeElement;
        if (renameInput) {
          if (active && active.closest && active.closest('[data-file-rename-input]')) return;
          cancelFileRename();
          return;
        }
        if (active && active.closest && active.closest('[data-file-path-input]')) return;
        cancelFilePathEdit();
      }, 0);
    });
    document.body.addEventListener('click', function(event) {
      var btn = event.target.closest('[data-action]');
      if (!btn) return;
      var action = btn.dataset.action;
      var id = btn.dataset.id;
      if (action === 'docker-ssh') openDockerHost(id);
      if (action === 'files-ssh') openFilesHost(id);
      if (action === 'files-webdav') openWebDAVFiles(id);
      if (action === 'session-ssh') openSession('ssh', id);
      if (action === 'session-docker') openSession('docker', id);
      if (action === 'edit-ssh') openSshForm(state.sshHosts.find(function(item) { return String(item.id) === String(id); }));
      if (action === 'edit-webdav') openWebDAVForm(state.webdavServers.find(function(item) { return String(item.id) === String(id); }));
      if (action === 'edit-credential') openCredentialForm(state.credentials.find(function(item) { return String(item.id) === String(id); }));
      if (action === 'delete-ssh') confirmDelete('ssh', id);
      if (action === 'delete-webdav') confirmDelete('webdav', id);
      if (action === 'delete-credential') confirmDelete('credential', id);
      if (action === 'start-docker') operateDocker('start', id);
      if (action === 'stop-docker') operateDocker('stop', id);
      if (action === 'restart-docker') operateDocker('restart', id);
      if (action === 'restart-policy-docker') updateDockerRestartPolicy(id, btn.dataset.policy);
      if (action === 'delete-docker') confirmDeleteDocker(id);
      if (action === 'delete-docker-network') deleteDockerObject('network', id);
      if (action === 'delete-docker-volume') deleteDockerObject('volume', id);
      if (action === 'delete-docker-image') deleteDockerObject('image', id);
      if (action === 'logs-docker') openDockerLogs(id);
      if (action === 'test-ssh') {
        apiJSON('/api/admin/assets/ssh-hosts/' + encodeURIComponent(id) + '/test', { method: 'POST' })
          .then(function() { toast(t('asset.toast.test_done'), 'success'); return loadData(); })
          .catch(function(err) { toast(err.message || t('asset.error.test')); });
      }
      if (action === 'test-webdav') {
        apiJSON('/api/admin/assets/webdav-servers/' + encodeURIComponent(id) + '/test', { method: 'POST' })
          .then(function() { toast(t('asset.toast.test_done'), 'success'); return loadData(); })
          .catch(function(err) { toast(err.message || t('asset.error.test')); });
      }
      if (action === 'inspect-docker') {
        inspectDocker(id);
      }
      if (action === 'open-file-dir') openFileDir(btn.dataset.path || id);
      if (action === 'edit-file') openFileEditor(btn.dataset.path || id);
      if (action === 'preview-file') openFilePreview(btn.dataset.path || id);
      if (action === 'download-file') downloadFile(btn.dataset.path || id);
      if (action === 'rename-file') renameFile(id);
      if (action === 'copy-file') copyFile(id);
      if (action === 'chmod-file') chmodFile(id);
      if (action === 'delete-file') confirmDeleteFile(id, btn.dataset.fileDir === 'true');
      if (window.BSActionDropdown) window.BSActionDropdown.closeAll();
    });
    document.body.addEventListener('change', function(event) {
      var select = event.target.closest('.asset-restart-policy-compact select');
      if (!select) return;
      var policy = select.value;
      select.value = '';
      updateDockerRestartPolicy(select.dataset.id, policy);
    });
    $('#maximizeTerminalBtn').addEventListener('click', toggleTerminalMaximized);
    $('#closeTerminalDot').addEventListener('click', closeModals);
    $('#maximizeTerminalDot').addEventListener('click', toggleTerminalMaximized);
    $('#closeFilePreviewDot').addEventListener('click', closeModals);
    window.addEventListener('resize', function() {
      fitTerminal();
      positionFloatingDropdown();
    });
    window.addEventListener('scroll', positionFloatingDropdown, true);
    window.addEventListener('beforeunload', closeDockerLogStream);
    $('#saveSettingsBtn').addEventListener('click', saveSettings);
    $('#refreshDockerLogsBtn').addEventListener('click', refreshDockerLogs);
    $('#dockerLogFollowBtn').addEventListener('click', toggleDockerLogFollow);
    $('#clearDockerLogsBtn').addEventListener('click', clearDockerLogView);
    document.addEventListener('keydown', function(event) {
      if (event.key !== 'Escape') return;
      if ((state.credentialModalSource === 'ssh-picker' || state.credentialModalSource === 'webdav-picker') && $('#credentialModal').classList.contains('open')) {
        cancelCredentialModal();
        return;
      }
      closeModals();
    });
  }

  if (state.assetMode === 'docker-host') {
    state.tab = 'docker';
  }
  if (state.assetMode === 'files-host') {
    state.tab = 'files';
  }
  if (state.assetMode === 'webdav-files') {
    state.tab = 'files';
  }
  if (state.assetMode !== 'docker-host' && state.assetMode !== 'files-host' && state.assetMode !== 'webdav-files' && window.BookStarkTabURL) {
    var initialTab = window.BookStarkTabURL.get('tab', ['ssh', 'webdav', 'settings'], '');
    var initialSettingsTab = window.BookStarkTabURL.get('settingsTab', ['credentials', 'base'], '');
    if (initialTab) setTab(initialTab, { updateUrl: false });
    if (initialSettingsTab) {
      if (!initialTab) setTab('settings', { updateUrl: false });
      setSettingsTab(initialSettingsTab, { updateUrl: false });
    }
  }
  bindEvents();
  loadData();
})();
