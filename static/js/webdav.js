(function () {
  'use strict';
  var state = {
    path: '',
    files: [],
    profile: null,
    query: '',
    menu: null,
    editorPath: '',
    editorLoadController: null,
    editorLoadToken: 0
  };
  var $ = function (selector, root) { return (root || document).querySelector(selector); };
  var list = $('#davFileList');
  var modal = $('#davModal');
  var toastTimer = 0;
  var modalReturnFocus = null;
  var modalScrollLockKey = 'webdav-modal';
  window.BookStarkWebDAV = window.BookStarkWebDAV || {};

  function escapeHTML(value) {
    return String(value == null ? '' : value).replace(/[&<>"']/g, function (char) {
      return ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[char];
    });
  }
  function t(key, fallback, values) {
    var translated = typeof window.__ === 'function' ? window.__(key) : key;
    var result = translated && translated !== key ? translated : fallback;
    Object.keys(values || {}).forEach(function (name) {
      result = result.replace(new RegExp('\\{' + name + '\\}', 'g'), function () { return values[name]; });
    });
    return result;
  }
  function request(url, options) {
    options = options || {};
    return (window.csrfFetch ? window.csrfFetch(url, options) : fetch(url, options)).then(function (response) {
      return response.json().catch(function () { return {}; }).then(function (body) {
        if (!response.ok || body.code) throw new Error(body.message || body.error || t('webdav.error.request_failed', '请求失败 ({status})', { status: response.status }));
        return body.data;
      });
    });
  }
  function jsonRequest(url, method, body) {
    return request(url, { method: method, headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
  }
  function toast(message) {
    var element = $('#davToast');
    element.textContent = message;
    element.classList.add('show');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(function () { element.classList.remove('show'); }, 2200);
  }
  function formatBytes(value) {
    var size = Number(value || 0);
    if (size < 1024) return size + ' B';
    var units = ['KB', 'MB', 'GB', 'TB'];
    var index = -1;
    do { size /= 1024; index += 1; } while (size >= 1024 && index < units.length - 1);
    return size.toFixed(size >= 10 ? 1 : 2) + ' ' + units[index];
  }
  function formatDate(value) {
    var date = new Date(value);
    if (isNaN(date.getTime())) return '';
    return date.toLocaleString([], { month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit' });
  }
  function joinPath(base, name) {
    return [base, name].filter(Boolean).join('/').replace(/\/+/g, '/');
  }
  function parentPath(value) {
    var parts = String(value || '').split('/').filter(Boolean);
    parts.pop();
    return parts.join('/');
  }
  function loadProfile() {
    return request('/api/webdav/profile').then(function (profile) {
      state.profile = profile;
      $('#davEndpoint').textContent = profile.endpoint;
      var used = profile.usage.stored_bytes || 0;
      var quota = profile.usage.quota_bytes || 0;
      var percent = quota ? Math.min(100, used / quota * 100) : 0;
      $('#davUsageText').textContent = formatBytes(used) + ' / ' + formatBytes(quota);
      $('#davUsagePercent').textContent = percent.toFixed(percent >= 10 ? 0 : 1) + '%';
      $('#davUsageBar').style.width = percent + '%';
      $('#davUsageFileCount').textContent = profile.usage.file_count || 0;
      $('#davUsageStored').textContent = formatBytes(profile.usage.stored_bytes || 0);
      $('#davUsageDeduplicated').textContent = formatBytes(profile.usage.deduplicated_bytes || 0);
      $('#davUsageCompressed').textContent = formatBytes(profile.usage.compression_saved_bytes || 0);
      $('#passwordBtn span').textContent = profile.has_app_password
        ? t('webdav.password.reset', '重置密码')
        : t('webdav.password.set', '设置密码');
    });
  }
  function loadFiles(nextPath) {
    if (typeof nextPath === 'string') state.path = nextPath.replace(/^\/+|\/+$/g, '');
    $('#davLoading').hidden = false;
    $('#davEmpty').hidden = true;
    $('#davLoadError').hidden = true;
    list.innerHTML = '';
    renderBreadcrumbs();
    return request('/api/webdav/files?path=' + encodeURIComponent(state.path)).then(function (files) {
      state.files = files || [];
      renderFiles();
    }).catch(function (error) {
      toast(error.message);
      $('#davLoadErrorMessage').textContent = error.message;
      $('#davLoadError').hidden = false;
      $('#davEmpty').hidden = true;
    }).finally(function () {
      $('#davLoading').hidden = true;
    });
  }
  function renderBreadcrumbs() {
    var parts = state.path.split('/').filter(Boolean);
    var toolbar = $('#davStickyToolbar');
    toolbar.classList.toggle('is-root', parts.length === 0);
    var rootLabel = t('webdav.root', '根目录');
    var html = '<button type="button" data-path="" title="' + escapeHTML(rootLabel) + '"><i class="fa-solid fa-house"></i><span>' + escapeHTML(rootLabel) + '</span></button>';
    var current = '';
    parts.forEach(function (part) {
      current = joinPath(current, part);
      html += '<i class="fa-solid fa-chevron-right"></i><button type="button" data-path="' + escapeHTML(current) + '">' + escapeHTML(part) + '</button>';
    });
    $('#davBreadcrumbs').innerHTML = html;
  }
  function renderFiles() {
    var query = state.query.toLowerCase();
    var files = state.files.filter(function (file) { return !query || file.name.toLowerCase().indexOf(query) >= 0; });
    $('#davEmpty').hidden = files.length !== 0;
    list.innerHTML = files.map(function (file, index) {
      var icon = file.type === 'dir' ? 'fa-solid fa-folder' : fileIcon(file.name);
      var publicState = file.type === 'dir' ? '' : file.is_public
        ? '<button type="button" class="dav-public-action" data-copy-public title="' + escapeHTML(publicURL(file.public_path)) + '" aria-label="' + escapeHTML(t('webdav.public.copy', '复制公开地址')) + '"><span class="dav-public-badge"><i class="fa-solid fa-link"></i><span>' + escapeHTML(file.public_path) + '</span></span></button>'
        : '<span class="dav-private-badge">' + escapeHTML(t('webdav.private', '未公开')) + '</span>';
      return '<article class="dav-file-row' + (file.type === 'dir' ? ' is-dir' : '') + '" data-index="' + index + '">' +
        '<div class="dav-file-name"><i class="' + icon + '"></i><button type="button" data-open>' + escapeHTML(file.name) + '</button></div>' +
        '<span class="dav-file-meta size">' + (file.type === 'dir' ? escapeHTML(t('webdav.folder', '文件夹')) : formatBytes(file.size)) + '</span>' +
        '<span class="dav-file-meta date">' + formatDate(file.mod_time) + '</span>' +
        '<span class="dav-file-public">' + publicState + '</span>' +
        '<div class="dav-row-menu"><button type="button" data-menu aria-label="' + escapeHTML(t('webdav.file_actions', '文件操作')) + '"><i class="fa-solid fa-ellipsis"></i></button></div>' +
        '</article>';
    }).join('');
  }
  function fileIcon(name) {
    var ext = String(name).split('.').pop().toLowerCase();
    if (['js', 'css', 'html', 'htm', 'json'].indexOf(ext) >= 0) return 'fa-solid fa-file-code';
    if (['png', 'jpg', 'jpeg', 'gif', 'webp', 'svg'].indexOf(ext) >= 0) return 'fa-regular fa-file-image';
    if (['md', 'txt', 'log'].indexOf(ext) >= 0) return 'fa-regular fa-file-lines';
    return 'fa-regular fa-file';
  }
  function currentFile(row) {
    var visibleName = $('[data-open]', row).textContent;
    return state.files.find(function (file) { return file.name === visibleName; });
  }
  function openMenu(row, file) {
    closeMenu();
    var holder = $('.dav-row-menu', row);
    var trigger = $('[data-menu]', holder);
    var editable = /^text\//.test(file.mime_type || '') || /\.(md|txt|css|js|json|html?|xml|svg|csv|log|ya?ml)$/i.test(file.name);
    var previewable = /^image\//.test(file.mime_type || '') || file.mime_type === 'application/pdf' || /^audio\//.test(file.mime_type || '') || /^video\//.test(file.mime_type || '');
    var actions = file.type === 'dir'
      ? '<button data-action="open"><i class="fa-solid fa-folder-open"></i>' + escapeHTML(t('webdav.action.open', '打开')) + '</button>'
      : (previewable ? '<button data-action="preview"><i class="fa-regular fa-eye"></i>' + escapeHTML(t('webdav.action.preview', '预览')) + '</button>' : '') +
        '<button data-action="download"><i class="fa-solid fa-download"></i>' + escapeHTML(t('webdav.action.download', '下载')) + '</button>' +
        (editable ? '<button data-action="edit"><i class="fa-solid fa-pen"></i>' + escapeHTML(t('webdav.action.edit', '文本编辑')) + '</button>' : '') +
        '<button data-action="public"><i class="fa-solid fa-link"></i>' + escapeHTML(file.is_public ? t('webdav.action.manage_public', '管理公开地址') : t('webdav.action.publish', '公开为静态资源')) + '</button>';
    var menu = document.createElement('div');
    var backdrop = document.createElement('button');
    backdrop.type = 'button';
    backdrop.className = 'dav-menu-backdrop';
    backdrop.setAttribute('aria-label', t('webdav.close', '关闭'));
    menu.className = 'dav-menu';
    menu.setAttribute('role', 'menu');
    menu.innerHTML = '<div class="dav-menu-handle" aria-hidden="true"></div>' +
      '<div class="dav-menu-head"><span class="dav-menu-file"><i class="' + (file.type === 'dir' ? 'fa-solid fa-folder' : fileIcon(file.name)) + '"></i><strong>' + escapeHTML(file.name) + '</strong></span>' +
      '<button type="button" data-menu-close aria-label="' + escapeHTML(t('webdav.close', '关闭')) + '"><i class="fa-solid fa-xmark"></i></button></div>' +
      '<div class="dav-menu-actions">' + actions +
      '<hr><button data-action="rename"><i class="fa-solid fa-i-cursor"></i>' + escapeHTML(t('webdav.action.rename', '重命名')) + '</button><button data-action="copy"><i class="fa-regular fa-copy"></i>' + escapeHTML(t('webdav.action.copy', '复制')) + '</button>' +
      '<button class="danger" data-action="delete"><i class="fa-regular fa-trash-can"></i>' + escapeHTML(t('webdav.action.delete', '删除')) + '</button></div>';
    document.body.appendChild(backdrop);
    document.body.appendChild(menu);
    if (window.matchMedia('(min-width: 761px)').matches) {
      var rect = trigger.getBoundingClientRect();
      menu.style.left = Math.max(8, Math.min(window.innerWidth - 166, rect.right - 158)) + 'px';
      menu.style.top = Math.min(window.innerHeight - menu.offsetHeight - 8, rect.bottom + 4) + 'px';
      if (parseFloat(menu.style.top) < 8) menu.style.top = Math.max(8, rect.top - menu.offsetHeight - 4) + 'px';
    }
    backdrop.addEventListener('click', closeMenu);
    menu.addEventListener('click', function (event) {
      if (event.target.closest('[data-menu-close]')) return closeMenu();
      var actionButton = event.target.closest('[data-action]');
      if (!actionButton) return;
      state.modalFile = file;
      closeMenu();
      handleAction(actionButton.dataset.action, file);
    });
    holder.classList.add('open');
    $('#davPage').classList.add('has-open-menu');
    state.menu = { holder: holder, menu: menu, backdrop: backdrop };
  }
  function closeMenu() {
    if (state.menu && state.menu.holder) state.menu.holder.classList.remove('open');
    if (state.menu && state.menu.menu) state.menu.menu.remove();
    if (state.menu && state.menu.backdrop) state.menu.backdrop.remove();
    $('#davPage').classList.remove('has-open-menu');
    state.menu = null;
  }
  function openModal(title, body, buttons) {
    if (modal.hidden) modalReturnFocus = document.activeElement;
    $('#davModalTitle').textContent = title;
    $('#davModalBody').innerHTML = body;
    $('#davModalFooter').innerHTML = (buttons || []).map(function (button) {
      return '<button type="button" class="bs-btn ' + (button.primary ? 'bs-btn-primary' : button.danger ? 'bs-btn-danger' : 'bs-btn-cancel') + '" data-modal-action="' + button.action + '">' + escapeHTML(button.label) + '</button>';
    }).join('');
    modal.hidden = false;
    modal.setAttribute('aria-hidden', 'false');
    modal.classList.add('open');
    if (window.BookStarkScrollLock) window.BookStarkScrollLock.lock(modalScrollLockKey);
    else document.body.style.overflow = 'hidden';
    setTimeout(function () { var input = $('input,textarea', $('#davModalBody')); if (input) input.focus(); }, 20);
  }
  function closeModal() {
    modal.classList.remove('open');
    modal.hidden = true;
    modal.setAttribute('aria-hidden', 'true');
    if (window.BookStarkScrollLock) window.BookStarkScrollLock.unlock(modalScrollLockKey);
    else document.body.style.overflow = '';
    $('#davModalBody').innerHTML = '';
    $('#davModalFooter').innerHTML = '';
    delete modal.dataset.passwordForm;
    delete modal.dataset.secret;
    if (modalReturnFocus && modalReturnFocus.isConnected) modalReturnFocus.focus();
    modalReturnFocus = null;
  }
  window.BookStarkWebDAV.closeModal = closeModal;
  function publicURL(publicPath) {
    var base = state.profile && state.profile.public_base_url ? state.profile.public_base_url.replace(/\/+$/, '') : '';
    return base + '/' + String(publicPath || '').split('/').map(encodeURIComponent).join('/');
  }
  function simplePathModal(title, value, action, label) {
    openModal(title, '<label class="dav-field"><span>' + label + '</span><input id="davModalValue" value="' + escapeHTML(value) + '"></label>',
      [{ action: 'cancel', label: t('webdav.cancel', '取消') }, { action: action, label: t('webdav.confirm', '确定'), primary: true }]);
  }
  function openTextEditor(file, filePath) {
    if (!window.BookStarkCodeEditorModal) {
      toast(t('webdav.error.editor_unavailable', '文本编辑器加载失败'));
      return;
    }
    if (state.editorLoadController) state.editorLoadController.abort();
    state.editorPath = filePath;
    var loadToken = ++state.editorLoadToken;
    var editor = window.BookStarkCodeEditorModal.open({
      title: t('webdav.modal.edit', '编辑 {name}', { name: file.name }),
      subtitle: filePath,
      fileName: file.name,
      loading: true,
      loadingText: t('asset.files.editor.loading', '加载中'),
      savingSubtitle: t('asset.files.editor.saving', '正在保存…'),
      errorSubtitle: t('asset.session.status.error', '保存失败'),
      closeOnSave: true,
      onSave: function(content) {
        return jsonRequest('/api/webdav/files/content', 'PUT', {
          path: filePath,
          content: content,
          content_type: file.mime_type
        }).then(function() {
          return Promise.all([loadFiles(), loadProfile()]);
        });
      },
      onSaved: function() {
        toast(t('asset.files.editor.saved', '文件已保存'));
      },
      onError: function(error) {
        toast(error.message || t('webdav.error.save', '保存失败'));
      },
      onCommandUnavailable: function() {
        toast(t('asset.files.editor.command_unavailable', '当前编辑器不支持此操作'));
      },
      onClose: function() {
        if (state.editorLoadToken !== loadToken) return;
        if (state.editorLoadController) state.editorLoadController.abort();
        state.editorLoadController = null;
        state.editorPath = '';
        state.editorLoadToken += 1;
      }
    });

    function loadContent() {
      if (state.editorLoadToken !== loadToken || state.editorPath !== filePath) return;
      if (state.editorLoadController) state.editorLoadController.abort();
      var controller = typeof AbortController === 'function' ? new AbortController() : null;
      state.editorLoadController = controller;
      editor.setLoading(true, t('asset.files.editor.loading', '加载中'));
      request('/api/webdav/files/content?path=' + encodeURIComponent(filePath), controller ? { signal: controller.signal } : {})
        .then(function(data) {
          if (state.editorLoadToken !== loadToken || state.editorPath !== filePath) return;
          editor.setContent(data && data.content ? data.content : '', file.name);
        })
        .catch(function(error) {
          if (error && error.name === 'AbortError') return;
          if (state.editorLoadToken !== loadToken || state.editorPath !== filePath) return;
          editor.showLoadError(error || new Error(t('webdav.error.request_failed', '请求失败')), loadContent);
        })
        .finally(function() {
          if (state.editorLoadToken === loadToken && state.editorLoadController === controller) {
            state.editorLoadController = null;
          }
        });
    }

    loadContent();
  }
  function handleAction(action, file) {
    var filePath = joinPath(state.path, file.name);
    if (action === 'open') return loadFiles(filePath);
    if (action === 'download') { window.location.href = '/api/webdav/files/download?path=' + encodeURIComponent(filePath); return; }
    if (action === 'preview') {
      var source = '/api/webdav/files/preview?path=' + encodeURIComponent(filePath);
      var preview = /^image\//.test(file.mime_type || '') ? '<img src="' + source + '" alt="' + escapeHTML(file.name) + '" style="display:block;max-width:100%;max-height:70dvh;margin:auto">' :
        /^audio\//.test(file.mime_type || '') ? '<audio src="' + source + '" controls autoplay style="width:100%"></audio>' :
        /^video\//.test(file.mime_type || '') ? '<video src="' + source + '" controls autoplay style="display:block;width:100%;max-height:70dvh"></video>' :
        '<iframe src="' + source + '" title="' + escapeHTML(file.name) + '" style="width:100%;height:70dvh;border:0"></iframe>';
      openModal(t('webdav.modal.preview', '预览 {name}', { name: file.name }), preview, [{ action: 'cancel', label: t('webdav.close', '关闭') }]);
      return;
    }
    if (action === 'rename') return simplePathModal(t('webdav.modal.rename', '重命名'), file.name, 'rename', t('webdav.field.new_name', '新名称'));
    if (action === 'copy') return simplePathModal(t('webdav.modal.copy_to', '复制到'), joinPath(state.path, t('webdav.copy_prefix', '副本-') + file.name), 'copy', t('webdav.field.target_path', '目标路径'));
    if (action === 'delete') {
      openModal(file.type === 'dir' ? t('webdav.modal.delete_folder', '删除目录') : t('webdav.modal.delete_file', '删除文件'),
        '<p>' + escapeHTML(t(file.type === 'dir' ? 'webdav.delete.folder_confirm' : 'webdav.delete.file_confirm',
          file.type === 'dir' ? '确定删除 {name} 及其中全部内容？此操作不可撤销。' : '确定删除 {name}？此操作不可撤销。',
          { name: file.name })) + '</p>',
        [{ action: 'cancel', label: t('webdav.cancel', '取消') }, { action: 'delete', label: t('webdav.action.delete', '删除'), danger: true }]);
      return;
    }
    if (action === 'edit') {
      return openTextEditor(file, filePath);
    }
    if (action === 'public') {
      var currentURL = file.is_public ? publicURL(file.public_path) : '';
      openModal(t('webdav.modal.public', '公开静态资源'),
        '<label class="dav-field"><span>' + escapeHTML(t('webdav.field.public_path', '公开路径')) + '</span><input id="davPublicPath" value="' + escapeHTML(file.public_path || file.name) + '"></label>' +
        '<p class="dav-hint">' + escapeHTML(t('webdav.public.full_url', '完整地址：')) + '<span id="davPublicURLPreview">' + escapeHTML(publicURL(file.public_path || file.name)) + '</span></p>' +
        '<p class="dav-hint">' + escapeHTML(t('webdav.public.hint', '公开后无需登录即可访问。修改文件内容时地址保持不变，ETag 会自动更新。')) + '</p>',
        [{ action: 'cancel', label: t('webdav.cancel', '取消') }].concat(file.is_public ? [{ action: 'copy-public', label: t('webdav.copy_endpoint', '复制地址') }, { action: 'unpublish', label: t('webdav.public.unpublish', '取消公开'), danger: true }] : []).concat([{ action: 'publish', label: t('webdav.save', '保存'), primary: true }]));
      modal.dataset.publicUrl = currentURL;
      $('#davPublicPath').addEventListener('input', function () {
        var nextURL = publicURL(this.value.trim());
        $('#davPublicURLPreview').textContent = nextURL;
        modal.dataset.publicUrl = nextURL;
      });
    }
  }
  function selectedModalFile() {
    return state.modalFile;
  }
  function modalAction(action) {
    if (action === 'cancel') return closeModal();
    var file = selectedModalFile();
    var filePath = file ? joinPath(state.path, file.name) : '';
    var task;
    if (action === 'mkdir') task = jsonRequest('/api/webdav/files/mkdir', 'POST', { path: state.path, name: $('#davModalValue').value.trim() });
    if (action === 'rename') task = jsonRequest('/api/webdav/files/rename', 'POST', { path: filePath, new_path: joinPath(state.path, $('#davModalValue').value.trim()) });
    if (action === 'copy') task = jsonRequest('/api/webdav/files/copy', 'POST', { path: filePath, new_path: $('#davModalValue').value.trim() });
    if (action === 'delete') task = request('/api/webdav/files?path=' + encodeURIComponent(filePath), { method: 'DELETE' });
    if (action === 'publish') task = jsonRequest('/api/webdav/files/public', 'POST', { path: filePath, public_path: $('#davPublicPath').value.trim() }).then(function (data) { navigator.clipboard && navigator.clipboard.writeText(data.url); toast(t('webdav.toast.public_saved', '公开地址已保存并复制')); });
    if (action === 'unpublish') task = request('/api/webdav/files/public?path=' + encodeURIComponent(filePath), { method: 'DELETE' });
    if (action === 'save-password') {
      var passwordInput = $('#davAppPassword');
      var confirmInput = $('#davAppPasswordConfirm');
      var password = passwordInput ? passwordInput.value : '';
      var confirmation = confirmInput ? confirmInput.value : '';
      var error = $('#davPasswordError');
      if (error) {
        error.textContent = '';
        error.hidden = true;
      }
      if (password.length < 8 || password.length > 64) {
        if (error) {
          error.textContent = t('webdav.password.length_error', '请输入 8-64 个字符的应用密码');
          error.hidden = false;
        }
        if (passwordInput) passwordInput.focus();
        return;
      }
      if (password !== confirmation) {
        if (error) {
          error.textContent = t('webdav.password.confirm_error', '两次输入的密码不一致');
          error.hidden = false;
        }
        if (confirmInput) confirmInput.focus();
        return;
      }
      setModalBusy(true);
      jsonRequest('/api/webdav/app-password/reset', 'POST', { password: password }).then(function () {
        closeModal();
        toast(t('webdav.toast.password_saved', '应用密码已保存'));
        return loadProfile();
      }).catch(function (error) {
        setModalBusy(false);
        toast(error.message);
      });
      return;
    }
    if (action === 'revoke-password') task = request('/api/webdav/app-password', { method: 'DELETE' }).then(function () { toast(t('webdav.toast.password_revoked', '应用密码已撤销')); return loadProfile(); });
    if (action === 'copy-public') { navigator.clipboard && navigator.clipboard.writeText(modal.dataset.publicUrl || ''); toast(t('webdav.toast.public_copied', '公开地址已复制')); return; }
    if (!task) return;
    setModalBusy(true);
    Promise.resolve(task).then(function () {
      closeModal();
      return Promise.all([loadFiles(), loadProfile()]);
    }).catch(function (error) {
      setModalBusy(false);
      toast(error.message);
    });
  }
  function setModalBusy(busy) {
    Array.prototype.forEach.call($('#davModalFooter').querySelectorAll('button'), function (button) {
      button.disabled = busy;
    });
  }
  function hashFile(file) {
    if (!window.crypto || !crypto.subtle || typeof Worker === 'undefined') return Promise.resolve('');
    return new Promise(function (resolve, reject) {
      var workerURL = $('#davPage').dataset.hashWorker;
      var worker = new Worker(workerURL);
      worker.onmessage = function (event) {
        if (event.data && event.data.progress != null) return;
        worker.terminate();
        event.data && event.data.error ? reject(new Error(event.data.error)) : resolve(event.data.hash);
      };
      worker.onerror = function (error) { worker.terminate(); reject(error); };
      worker.postMessage({ file: file, chunkSize: 2 * 1024 * 1024 });
    });
  }
  function chunkHashes(file, indices, chunkSize, nonceHex) {
    var nonce = new Uint8Array((nonceHex.match(/.{2}/g) || []).map(function (part) { return parseInt(part, 16); }));
    return Promise.all(indices.map(function (index) {
      return file.slice(index * chunkSize, Math.min(file.size, (index + 1) * chunkSize)).arrayBuffer().then(function (buffer) {
        var chunk = new Uint8Array(buffer);
        var proof = new Uint8Array(nonce.length + chunk.length);
        proof.set(nonce, 0);
        proof.set(chunk, nonce.length);
        return crypto.subtle.digest('SHA-256', proof).then(function (hash) {
          return Array.from(new Uint8Array(hash)).map(function (byte) { return byte.toString(16).padStart(2, '0'); }).join('');
        });
      });
    }));
  }
  function uploadFile(file) {
    var target = joinPath(state.path, file.name);
    toast(t('webdav.upload.hashing', '正在计算指纹：{name}', { name: file.name }));
    function sendFile() {
      toast(t('webdav.upload.uploading', '正在上传：{name}', { name: file.name }));
      var form = new FormData();
      form.append('path', state.path);
      form.append('file', file, file.name);
      return request('/api/webdav/files/upload', { method: 'POST', body: form });
    }
    return hashFile(file).then(function (hash) {
      if (!hash) return { action: 'upload' };
      return jsonRequest('/api/webdav/files/upload/check', 'POST', { path: target, hash: hash, size: file.size, content_type: file.type });
    }).then(function (result) {
      if (result.action === 'linked') return result;
      if (result.action === 'prove') {
        toast(t('webdav.upload.verifying', '正在验证文件：{name}', { name: file.name }));
        return chunkHashes(file, result.chunk_indices, result.chunk_size, result.nonce).then(function (hashes) {
          return jsonRequest('/api/webdav/files/upload/prove', 'POST', { token: result.token, chunk_hashes: hashes });
        }).catch(function () { return sendFile(); });
      }
      return sendFile();
    }).then(function (result) {
      toast(result && (result.action === 'linked' || result.deduplicated)
        ? t('webdav.upload.linked', '{name} 已秒传', { name: file.name })
        : t('webdav.upload.done', '{name} 已上传', { name: file.name }));
    });
  }
  function uploadFiles(files) {
    var queue = Array.prototype.slice.call(files || []);
    var failed = [];
    queue.reduce(function (promise, file) {
      return promise.then(function () {
        return uploadFile(file).catch(function (error) { failed.push(file.name + '：' + error.message); });
      });
    }, Promise.resolve())
      .then(function () { return Promise.all([loadFiles(), loadProfile()]); })
      .then(function () { if (failed.length) toast(t('webdav.upload.failed', '{count} 个文件上传失败', { count: failed.length })); })
      .catch(function (error) { toast(error.message); });
  }

  $('#davBreadcrumbs').addEventListener('click', function (event) { var button = event.target.closest('[data-path]'); if (button) loadFiles(button.dataset.path); });
  list.addEventListener('click', function (event) {
    var row = event.target.closest('.dav-file-row'); if (!row) return;
    var file = currentFile(row); if (!file) return;
    if (event.target.closest('[data-copy-public]')) {
      navigator.clipboard && navigator.clipboard.writeText(publicURL(file.public_path));
      toast(t('webdav.toast.public_copied', '公开地址已复制'));
      return;
    }
    if (event.target.closest('[data-open]')) {
      if (file.type === 'dir') loadFiles(joinPath(state.path, file.name));
      else if (/^(image|audio|video)\//.test(file.mime_type || '') || file.mime_type === 'application/pdf') handleAction('preview', file);
      else handleAction('download', file);
      return;
    }
    if (event.target.closest('[data-menu]')) {
      setTimeout(function () { openMenu(row, file); }, 0);
      return;
    }
    var actionButton = event.target.closest('[data-action]');
    if (actionButton) { state.modalFile = file; closeMenu(); handleAction(actionButton.dataset.action, file); }
  });
  document.addEventListener('click', function (event) {
    if (!event.target.closest('.dav-row-menu') && !event.target.closest('.dav-menu')) closeMenu();
  });
  window.addEventListener('resize', function () {
    if (window.matchMedia('(min-width: 761px)').matches) closeMenu();
  });
  window.addEventListener('scroll', function () {
    if (window.matchMedia('(min-width: 761px)').matches) closeMenu();
  }, true);
  modal.addEventListener('click', function (event) {
    if (event.target.closest('[data-modal-close]')) closeModal();
    var passwordToggle = event.target.closest('[data-password-toggle]');
    if (passwordToggle) {
      var input = $('#' + passwordToggle.dataset.passwordToggle);
      if (input) {
        var visible = input.type === 'text';
        input.type = visible ? 'password' : 'text';
        passwordToggle.setAttribute('aria-pressed', visible ? 'false' : 'true');
        passwordToggle.setAttribute('aria-label', visible ? t('webdav.password.show', '显示密码') : t('webdav.password.hide', '隐藏密码'));
        var icon = $('i', passwordToggle);
        if (icon) icon.className = visible ? 'fa-regular fa-eye' : 'fa-regular fa-eye-slash';
        input.focus();
      }
      return;
    }
    var action = event.target.closest('[data-modal-action]'); if (action) modalAction(action.dataset.modalAction);
  });
  modal.addEventListener('keydown', function (event) {
    if (event.key === 'Enter' && modal.dataset.passwordForm === 'true' && event.target.matches('input')) {
      event.preventDefault();
      modalAction('save-password');
    }
  });
  document.addEventListener('keydown', function (event) {
    if (event.key === 'Escape') {
      if (!modal.hidden) closeModal();
      else closeMenu();
    }
  });
  $('#mkdirBtn').addEventListener('click', function () { state.modalFile = null; simplePathModal(t('webdav.new_folder', '新建目录'), '', 'mkdir', t('webdav.field.folder_name', '目录名称')); });
  $('#uploadBtn').addEventListener('click', function () { $('#uploadInput').click(); });
  $('#uploadInput').addEventListener('change', function () { uploadFiles(this.files); this.value = ''; });
  $('#davSearch').addEventListener('input', function () { state.query = this.value.trim(); renderFiles(); });
  $('#copyEndpointBtn').addEventListener('click', function () { if (state.profile && navigator.clipboard) navigator.clipboard.writeText(state.profile.endpoint); toast(t('webdav.toast.endpoint_copied', 'WebDAV 地址已复制')); });
  $('#passwordBtn').addEventListener('click', function () {
    var hasPassword = state.profile && state.profile.has_app_password;
    openModal(state.profile && state.profile.has_app_password ? t('webdav.password.reset_title', '重置应用密码') : t('webdav.password.set_title', '设置应用密码'),
      '<p class="dav-password-explain">' + escapeHTML(t('webdav.password.explain', 'WebDAV 客户端使用独立应用密码，不会暴露网页登录密码。保存新密码后，旧密码立即失效。')) + '</p>' +
      '<label class="dav-field"><span>' + escapeHTML(t('webdav.password.new', '新应用密码')) + '</span><span class="dav-password-control"><input id="davAppPassword" type="password" autocomplete="new-password" minlength="8" maxlength="64"><button type="button" data-password-toggle="davAppPassword" aria-label="' + escapeHTML(t('webdav.password.show', '显示密码')) + '" aria-pressed="false"><i class="fa-regular fa-eye"></i></button></span></label>' +
      '<label class="dav-field"><span>' + escapeHTML(t('webdav.password.confirm', '确认应用密码')) + '</span><span class="dav-password-control"><input id="davAppPasswordConfirm" type="password" autocomplete="new-password" minlength="8" maxlength="64"><button type="button" data-password-toggle="davAppPasswordConfirm" aria-label="' + escapeHTML(t('webdav.password.show', '显示密码')) + '" aria-pressed="false"><i class="fa-regular fa-eye"></i></button></span></label>' +
      '<p id="davPasswordError" class="dav-field-error" role="alert" hidden></p>' +
      '<p class="dav-hint">' + escapeHTML(t('webdav.password.requirement', '请输入 8-64 个字符。WebDAV 客户端使用当前账号和此应用密码连接。')) + '</p>',
      [{ action: 'cancel', label: t('webdav.cancel', '取消') }].concat(hasPassword ? [{ action: 'revoke-password', label: t('webdav.password.revoke', '撤销密码'), danger: true }] : []).concat([{ action: 'save-password', label: hasPassword ? t('webdav.password.reset', '重置密码') : t('webdav.password.set', '设置密码'), primary: true }]));
    modal.dataset.passwordForm = 'true';
  });
  var dropZone = $('#davDropZone');
  ['dragenter', 'dragover'].forEach(function (name) { dropZone.addEventListener(name, function (event) { event.preventDefault(); dropZone.classList.add('dragging'); }); });
  ['dragleave', 'drop'].forEach(function (name) { dropZone.addEventListener(name, function (event) { event.preventDefault(); dropZone.classList.remove('dragging'); if (name === 'drop') uploadFiles(event.dataTransfer.files); }); });
  $('#davRetryBtn').addEventListener('click', function () { loadFiles(); });
  var stickyToolbar = $('#davStickyToolbar');
  function syncToolbarStuck() {
    var top = parseFloat(getComputedStyle(stickyToolbar).top) || 0;
    var stuck = window.scrollY > 0 && stickyToolbar.getBoundingClientRect().top <= top + 1;
    stickyToolbar.classList.toggle('is-stuck', stuck);
  }
  if (window.BookStarkSticky) window.BookStarkSticky.observe(stickyToolbar);
  window.addEventListener('scroll', syncToolbarStuck, { passive: true });
  window.addEventListener('resize', syncToolbarStuck);
  requestAnimationFrame(syncToolbarStuck);
  Promise.all([loadProfile(), loadFiles('')]).catch(function (error) { toast(error.message); });
}());
