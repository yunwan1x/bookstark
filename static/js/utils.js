/* ===== BookStark Shared Utilities ===== */

// Return plain text; the dialog renderer is responsible for HTML escaping.
// Untitled content uses a short excerpt plus its ID to disambiguate matches.
function formatDeleteConfirmation(message, name, id, excerpt) {
  var label = String(name == null ? '' : name).trim();
  if (excerpt) {
    label = label.replace(/\s+/g, ' ');
    var chars = Array.from(label);
    if (chars.length > 80) label = chars.slice(0, 80).join('') + '…';
  }
  if (!label || excerpt) label += (label ? ' ' : '') + '(#' + id + ')';
  return message.replace(/\{name\}/g, function() { return label; });
}

/**
 * Compute SHA-256 hash of a File/Blob object
 * @param {File|Blob} file - The file to hash
 * @returns {Promise<string>} Hex-encoded SHA-256 hash
 */
function computeFileHash(file) {
  if (!window.crypto || !window.crypto.subtle) {
    return Promise.reject(new Error('crypto.subtle not available'));
  }
  return file.arrayBuffer().then(function(buffer) {
    return crypto.subtle.digest('SHA-256', buffer);
  }).then(function(hashBuffer) {
    var hashArray = Array.from(new Uint8Array(hashBuffer));
    return hashArray.map(function(b) { return b.toString(16).padStart(2, '0'); }).join('');
  });
}

/**
 * Compute SHA-256 hash of a dataURL string (e.g. from Excalidraw)
 * @param {string} dataURL - The data URL to hash
 * @returns {Promise<string>} Hex-encoded SHA-256 hash
 */
function computeDataURLHash(dataURL) {
  if (!window.crypto || !window.crypto.subtle) {
    return Promise.reject(new Error('crypto.subtle not available'));
  }
  var parts = dataURL.split(',');
  var byteString = atob(parts[1]);
  var bytes = new Uint8Array(byteString.length);
  for (var i = 0; i < byteString.length; i++) {
    bytes[i] = byteString.charCodeAt(i);
  }
  return crypto.subtle.digest('SHA-256', bytes).then(function(hashBuffer) {
    var hashArray = Array.from(new Uint8Array(hashBuffer));
    return hashArray.map(function(b) { return b.toString(16).padStart(2, '0'); }).join('');
  });
}

/**
 * Check if a file with the given SHA-256 hash already exists on the server
 * @param {string} hash - Hex-encoded SHA-256 hash
 * @returns {Promise<object|null>} Upload data object with url, thumb_url, etc., or null
 */
function checkUploadByHash(hash) {
  return fetch('/api/uploads/by-hash/' + encodeURIComponent(hash)).then(function(res) {
    if (!res.ok) return null;
    return res.json().then(function(data) {
      if (data.code === 0 && data.data) return data.data;
      return null;
    });
  }).catch(function() {
    return null;
  });
}

/**
 * HTML 转义 - 防止 XSS
 * 转义 &, <, >, ", '
 */
function escHtml(s) {
    if (!s) return '';
    var d = document.createElement('div');
    d.textContent = s;
    return d.innerHTML;
}

/**
 * JS 字符串转义 - 用于内联 onclick 等场景
 * 先 escJs 再 escAttr，防止特殊字符打断 JS 字符串字面量
 */
function escJs(s) {
    if (!s) return '';
    return String(s).replace(/\\/g, '\\\\').replace(/'/g, "\\'").replace(/\n/g, '\\n').replace(/\r/g, '\\r');
}

/**
 * HTML 属性转义 - 防止属性注入
 * 转义 &, <, >, ", '
 */
function escAttr(s) {
    if (!s) return '';
    return String(s).replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/'/g, '&#39;');
}

/**
 * Sanitize rendered Markdown before inserting it with innerHTML.
 * The allowlist keeps the formatting BookStark renders while removing active
 * content, event handlers, inline styles and unsafe URL schemes.
 */
function sanitizeRenderedHTML(html) {
    var template = document.createElement('template');
    template.innerHTML = String(html || '');

    var allowedTags = {
        A: true, B: true, BLOCKQUOTE: true, BR: true, BUTTON: true, CODE: true,
        DEL: true, DETAILS: true, DIV: true, EM: true, FIGCAPTION: true,
        FIGURE: true, H1: true, H2: true, H3: true, H4: true, H5: true, H6: true,
        HR: true, I: true, IMG: true, LI: true, OL: true, P: true, PRE: true,
        S: true, SPAN: true, STRONG: true, SUB: true, SUMMARY: true, SUP: true,
        TABLE: true, TBODY: true, TD: true, TFOOT: true, TH: true, THEAD: true,
        TR: true, U: true, UL: true
    };
    var allowedAttributes = {
        A: { href: true, target: true, title: true },
        BUTTON: { class: true, type: true, title: true, 'aria-label': true },
        CODE: { class: true },
        DETAILS: { open: true },
        DIV: { class: true, 'data-lang': true },
        I: { class: true },
        IMG: { src: true, alt: true, title: true, width: true, height: true, loading: true },
        SPAN: { class: true },
        TD: { colspan: true, rowspan: true, align: true },
        TH: { colspan: true, rowspan: true, align: true }
    };
    var elements = Array.prototype.slice.call(template.content.querySelectorAll('*'));

    elements.forEach(function(element) {
        var tag = element.tagName;
        if (!allowedTags[tag]) {
            element.remove();
            return;
        }
        var tagAttributes = allowedAttributes[tag] || {};
        Array.prototype.slice.call(element.attributes).forEach(function(attribute) {
            var name = attribute.name.toLowerCase();
            if (!tagAttributes[name]) {
                element.removeAttribute(attribute.name);
                return;
            }
            if (name === 'href' || name === 'src') {
                var value = String(attribute.value || '').replace(/[\u0000-\u0020\u007f-\u009f]/g, '');
                var lower = value.toLowerCase();
                var isRelative = value.charAt(0) === '/' || value.charAt(0) === '#' ||
                    value.indexOf('./') === 0 || value.indexOf('../') === 0;
                var isSafeAbsolute = lower.indexOf('http://') === 0 || lower.indexOf('https://') === 0;
                var isSafeLink = name === 'href' &&
                    (lower.indexOf('mailto:') === 0 || lower.indexOf('tel:') === 0);
                if (!isRelative && !isSafeAbsolute && !isSafeLink) {
                    element.removeAttribute(attribute.name);
                }
            }
        });
        if (tag === 'BUTTON') {
            // Preserve only the renderer's copy control, never arbitrary app
            // action classes supplied by Markdown authors.
            if (element.classList.contains('code-copy-btn')) {
                element.setAttribute('class', 'code-copy-btn');
            } else {
                element.removeAttribute('class');
            }
            element.setAttribute('type', 'button');
        }
        if (tag === 'A' && element.hasAttribute('href')) {
            element.setAttribute('rel', 'noopener noreferrer');
        }
        if (tag === 'IMG') {
            element.setAttribute('loading', 'lazy');
        }
    });
    return template.innerHTML;
}

window.sanitizeRenderedHTML = sanitizeRenderedHTML;

// Read the live cookie, not the token embedded in a possibly cached HTML page.
var csrfRefreshPromise = null;
function readCSRFCookie() {
    var match = document.cookie.match(/(?:^|;\s*)csrf_token=([^;]*)/);
    return match ? decodeURIComponent(match[1]) : '';
}

function refreshCSRFCookie() {
    if (!csrfRefreshPromise) {
        csrfRefreshPromise = fetch('/api/csrf-token?_=' + Date.now(), {
            credentials: 'same-origin', cache: 'no-store'
        }).then(function(response) {
            if (!response.ok || !readCSRFCookie()) throw new Error('无法刷新 CSRF token，请重试');
        }).finally(function() { csrfRefreshPromise = null; });
    }
    return csrfRefreshPromise;
}

function fetchWithCurrentCSRF(url, options) {
    options = options || {};
    var method = (options.method || 'GET').toUpperCase();
    var headers = new Headers(options.headers || {});
    if (!/^(POST|PUT|PATCH|DELETE)$/.test(method) ||
        new URL(url, location.href).origin !== location.origin ||
        /^Token /i.test(headers.get('Authorization') || '') || options.credentials === 'omit') {
        return fetch(url, options);
    }
    function send() {
        headers.set('X-CSRF-Token', readCSRFCookie());
        return fetch(url, Object.assign({}, options, { headers: headers }));
    }
    return (readCSRFCookie() ? Promise.resolve() : refreshCSRFCookie()).then(send).then(function(response) {
        if (response.status !== 403) return response;
        // Only replay a request explicitly rejected by CSRF middleware, before
        // its handler ran. Never replay general authorization or network errors.
        return response.clone().json().catch(function() { return {}; }).then(function(body) {
            if (body.csrf_error !== true) return response;
            return refreshCSRFCookie().then(send);
        });
    });
}

/** CSRF-protected fetch with request locking and offline queue support. */
function csrfFetch(url, options) {
    options = options || {};
    var method = (options.method || 'GET').toUpperCase();
    var offlinePolicy = options.offlinePolicy || 'queue';
    if (options.lockKey && window.BookStarkRequestLock) {
        var lockedOptions = {};
        for (var optKey in options) {
            if (Object.prototype.hasOwnProperty.call(options, optKey) && optKey !== 'lockKey' && optKey !== 'lockControl') {
                lockedOptions[optKey] = options[optKey];
            }
        }
        lockedOptions._skipAutoLock = true;
        var lockedRequest = window.BookStarkRequestLock.run(options.lockKey, function() {
            return csrfFetch(url, lockedOptions);
        }, options.lockControl);
        if (!lockedRequest) {
            if (window.BookStarkErrors) BookStarkErrors.toast('请求处理中，请稍候', 'warning');
            return Promise.reject(new Error('请求处理中，请稍候'));
        }
        return lockedRequest;
    }
    if (method !== 'GET' && method !== 'HEAD' && options.autoLock !== false && window.BookStarkRequestLock && !options._skipAutoLock) {
        var bodyKey = '';
        var body = options.body;
        var canAutoLock = true;
        if (typeof body === 'string') {
            bodyKey = ':' + requestLockHash(body);
        } else if (body == null) {
            bodyKey = '';
        } else {
            canAutoLock = false;
        }
        if (canAutoLock) {
            var autoOptions = {};
            for (var autoKey in options) {
                if (Object.prototype.hasOwnProperty.call(options, autoKey) && autoKey !== 'autoLock') {
                    autoOptions[autoKey] = options[autoKey];
                }
            }
            autoOptions._skipAutoLock = true;
            return csrfFetch(url, Object.assign(autoOptions, {
                lockKey: 'request:' + method + ':' + String(url) + bodyKey,
                lockControl: options.lockControl || null
            }));
        }
    }
    if (method === 'POST' || method === 'PUT' || method === 'PATCH' || method === 'DELETE') {
        options.headers = options.headers || {};
        if (offlinePolicy === 'reject') {
            options.headers = new Headers(options.headers);
            options.headers.set('X-BookStark-Offline-Policy', 'reject');
        }
    }
    var fetchOptions = {};
    for (var fetchKey in options) {
        if (Object.prototype.hasOwnProperty.call(options, fetchKey) && fetchKey !== 'offlinePolicy' && fetchKey !== 'lockKey' && fetchKey !== 'lockControl' && fetchKey !== '_skipAutoLock') {
            fetchOptions[fetchKey] = options[fetchKey];
        }
    }
    return fetchWithCurrentCSRF(url, fetchOptions).catch(function(err) {
        // Network error (offline) — queue mutation requests for later
        if (method !== 'GET' && offlinePolicy !== 'reject' && window.BSOfflineQueue) {
          var headers = {};
          new Headers(options.headers || {}).forEach(function(value, key) { headers[key] = value; });
          return window.BSOfflineQueue.addToQueue(url, method, headers, options.body || null).then(function() {
            window.BSOfflineQueue.showOfflineToast('网络不可用，操作已保存，恢复后将自动提交');
            window.BSOfflineQueue.registerSync();
            // Return a fake ok response so callers don't crash
            return new Response(JSON.stringify({code: 0, offlineQueued: true, message: '操作已保存到离线队列'}), {
              status: 202,
              headers: { 'Content-Type': 'application/json', 'X-Offline-Queued': 'true' }
            });
          });
        }
        throw err;
    });
}

function requestLockHash(input) {
    var hash = 5381;
    input = String(input || '');
    for (var i = 0; i < input.length; i++) {
        hash = ((hash << 5) + hash) ^ input.charCodeAt(i);
    }
    return (hash >>> 0).toString(36);
}

window.BookStarkErrors = (function() {
    function text(key, fallback) {
        return (typeof window.__ === 'function' && window.__(key)) || fallback;
    }

    function messageFrom(input, fallback) {
        fallback = fallback || text('common.error.operation_failed', '操作失败');
        if (!input) return fallback;
        if (typeof input === 'string') return input;
        if (input.message) return input.message;
        if (input.error) return input.error;
        if (input.msg) return input.msg;
        return fallback;
    }

    function toast(input, type, fallback) {
        var msg = messageFrom(input, fallback);
        if (window.BSDialog && typeof BSDialog.toast === 'function') {
            BSDialog.toast(msg, type || 'error');
        } else {
            console[type === 'error' ? 'error' : 'log'](msg);
        }
        return msg;
    }

    function field(el, input, fallback) {
        var msg = messageFrom(input, fallback);
        if (typeof el === 'string') el = document.getElementById(el);
        if (!el) {
            toast(msg, 'error');
            return msg;
        }
        el.textContent = msg;
        el.classList.remove('hidden');
        return msg;
    }

    function clearField(el) {
        if (typeof el === 'string') el = document.getElementById(el);
        if (!el) return;
        el.textContent = '';
        el.classList.add('hidden');
    }

    function page(container, input, opts) {
        opts = opts || {};
        var msg = messageFrom(input, opts.message || text('common.error.load_failed', '加载失败'));
        if (typeof container === 'string') container = document.getElementById(container);
        if (container && window.BookStarkState) {
            BookStarkState.render(container, {
                type: 'error',
                title: opts.title || text('common.error.load_failed', '加载失败'),
                message: msg,
                actionText: opts.actionText,
                onAction: opts.onAction
            });
        } else {
            toast(msg, 'error');
        }
        return msg;
    }

    function fromResponse(res, fallback) {
        if (!res) return Promise.resolve(fallback || text('common.error.operation_failed', '操作失败'));
        return res.json().then(function(data) {
            return messageFrom(data, fallback);
        }).catch(function() {
            return fallback || text('common.error.operation_failed', '操作失败');
        });
    }

    // Save endpoints return JSON. Never mark an offline queue acknowledgement,
    // an application error, or an unexpected response as a successful save.
    async function requireSaveSuccess(res) {
        var fallback = '保存失败（HTTP ' + res.status + '）';
        if (res.headers.get('X-Offline-Queued') === 'true') {
            throw new Error('尚未保存到服务器，请联网后重试');
        }
        var data = await res.json().catch(function() { return null; });
        if (!res.ok || !data || data.code !== 0) {
            var error = new Error(messageFrom(data, res.ok ? '保存响应异常，请重试' : fallback));
            error.status = res.status;
            throw error;
        }
        return res;
    }

    return {
        requireSaveSuccess: requireSaveSuccess,
        message: messageFrom,
        toast: toast,
        field: field,
        clearField: clearField,
        page: page,
        fromResponse: fromResponse
    };
})();

(function() {
    if (!('serviceWorker' in navigator)) return;
    var lastStaleToastAt = 0;
    navigator.serviceWorker.addEventListener('message', function(event) {
        if (!event.data || event.data.type !== 'API_CACHE_STALE') return;
        var now = Date.now();
        if (now - lastStaleToastAt < 8000) return;
        lastStaleToastAt = now;
        var message = '网络不可用，正在显示缓存数据，可能不是最新';
        if (typeof window.__ === 'function') {
            message = window.__('offline.cache_stale') || message;
        }
        if (window.BSDialog && BSDialog.toast) {
            BSDialog.toast(message, 'warning', 3500);
        }
    });
})();

window.BookStarkRequestLock = (function() {
    var locks = {};

    function setButtonBusy(button, busy) {
        if (!button) return;
        button.disabled = !!busy;
        button.classList.toggle('is-submitting', !!busy);
        button.setAttribute('aria-busy', busy ? 'true' : 'false');
    }

    function release(key, button) {
        delete locks[key];
        setButtonBusy(button, false);
    }

    function run(key, task, button) {
        key = key || 'default';
        if (locks[key]) return null;
        locks[key] = true;
        setButtonBusy(button, true);
        var promise;
        try {
            promise = Promise.resolve(task());
        } catch (err) {
            release(key, button);
            return Promise.reject(err);
        }
        return promise.then(function(value) {
            release(key, button);
            return value;
        }, function(err) {
            release(key, button);
            throw err;
        });
    }

    function isLocked(key) {
        return !!locks[key];
    }

    return {
        run: run,
        isLocked: isLocked,
        setButtonBusy: setButtonBusy
    };
})();

window.BookStarkState = (function() {
    var timers = {};

    function render(container, opts) {
        if (!container) return;
        opts = opts || {};
        var icon = opts.icon || (opts.type === 'error' ? 'fa-triangle-exclamation' : 'fa-folder-open');
        var title = opts.title || (opts.type === 'error' ? '加载失败' : '暂无数据');
        var message = opts.message || '';
        var action = opts.actionText ? '<button type="button" class="bs-state-action">' + escHtml(opts.actionText) + '</button>' : '';
        container.innerHTML = '<div class="bs-state bs-state-' + escAttr(opts.type || 'empty') + '">' +
            '<i class="fa-solid ' + escAttr(icon) + '"></i>' +
            '<div class="bs-state-title">' + escHtml(title) + '</div>' +
            (message ? '<div class="bs-state-message">' + escHtml(message) + '</div>' : '') +
            action +
        '</div>';
        if (opts.actionText && typeof opts.onAction === 'function') {
            var btn = container.querySelector('.bs-state-action');
            if (btn) btn.addEventListener('click', opts.onAction);
        }
    }

    function loadingTimeout(key, container, opts, delay) {
        clear(key);
        timers[key] = setTimeout(function() {
            render(container, opts);
            delete timers[key];
        }, delay || 12000);
    }

    function clear(key) {
        if (!timers[key]) return;
        clearTimeout(timers[key]);
        delete timers[key];
    }

    return {
        render: render,
        loadingTimeout: loadingTimeout,
        clear: clear
    };
})();

/**
 * 根据字符串首字符生成颜色
 */
var _charColorPalette = [
    '#e63946', // A - 红
    '#f77f00', // B - 橙
    '#fcbf49', // C - 琥珀
    '#e9c46a', // D - 金
    '#a7c957', // E - 黄绿
    '#2d6a4f', // F - 深绿
    '#40916c', // G - 森绿
    '#52b788', // H - 翠绿
    '#14b8a6', // I - 蓝绿
    '#06b6d4', // J - 青
    '#0284c7', // K - 深蓝
    '#2563eb', // L - 蓝
    '#3b82f6', // M - 亮蓝
    '#6366f1', // N - 靛蓝
    '#8b5cf6', // O - 紫
    '#a855f7', // P - 亮紫
    '#c026d3', // Q - 品红
    '#db2777', // R - 玫红
    '#ec4899', // S - 粉
    '#f43f5e', // T - 玫瑰
    '#78716c', // U - 石灰
    '#0d9488', // V - 水鸭
    '#059669', // W - 翡翠
    '#7c3aed', // X - 暗紫
    '#b45309', // Y - 棕
    '#be185d'  // Z - 深粉
];
function charColor(str) {
    if (!str) return _charColorPalette[0];
    var ch = str.charAt(0).toUpperCase();
    var idx = ch.charCodeAt(0) - 65; // A=0, B=1, ..., Z=25
    if (idx < 0 || idx > 25) idx = ch.charCodeAt(0) % 26;
    return _charColorPalette[idx];
}

/**
 * 基于 domain 的 HSL 颜色（360 色相，区分度远高于 26 色调色板）
 */
function domainColor(domain) {
    if (!domain) return '#78716c';
    var hash = 0;
    for (var i = 0; i < domain.length; i++) {
        hash = ((hash << 5) - hash) + domain.charCodeAt(i);
        hash = hash & hash;
    }
    var hue = Math.abs(hash) % 360;
    return 'hsl(' + hue + ', 55%, 45%)';
}

/**
 * 基于 domain 的显示字符（去掉 www. 前缀，取首字母大写）
 */
function domainChar(hostname) {
    if (!hostname) return '?';
    var h = hostname.replace(/^www\./, '');
    var ch = h.charAt(0).toUpperCase();
    return ch || '?';
}

/**
 * 防抖函数 - 限制高频调用
 * @param {Function} fn - 要防抖的函数
 * @param {number} delay - 延迟毫秒数
 * @returns {Function} 防抖后的函数
 */
function debounce(fn, delay) {
    var timer = null;
    return function() {
        var args = arguments;
        var ctx = this;
        clearTimeout(timer);
        timer = setTimeout(function() { fn.apply(ctx, args); }, delay);
    };
}

/**
 * 统一 API 响应处理
 * 所有 API 返回格式：{ code: 0, data: ... } 或 { code: 非零, message: "错误信息" }
 * 成功时 code === 0，失败时 code !== 0
 */
function handleApiResponse(res) {
    if (res.code !== undefined && res.code !== 0) {
        throw new Error(window.BookStarkErrors ? BookStarkErrors.message(res, '操作失败') : (res.message || '操作失败'));
    }
    return res;
}

window.BookStarkFormGuards = (function() {
    var ignoreAttrs = {
        'data-form-type': 'other',
        'data-lpignore': 'true',
        'data-1p-ignore': 'true',
        'data-bwignore': 'true',
        'data-dashlane-disabled': 'true',
        'data-protonpass-ignore': 'true',
        'data-keeper-ignore': 'true'
    };
    var nonCredentialTypes = {
        text: true,
        search: true,
        email: true,
        url: true,
        tel: true,
        number: true,
        date: true,
        month: true,
        week: true,
        time: true,
        datetime: true,
        'datetime-local': true
    };
    var usernameLike = /(^|[-_])(account|user|username|email)([-_]|$)/i;

    function inputType(input) {
        return (input.getAttribute('type') || 'text').toLowerCase();
    }

    function isTextLike(input) {
        if (!input || input.tagName !== 'INPUT') return false;
        return !!nonCredentialTypes[inputType(input)];
    }

    function hasNearbyPassword(input) {
        var scope = input.closest('form, .auth-card, .asset-modal, .book-modal, .article-modal, .modal, [role="dialog"]');
        return !!(scope && scope.querySelector('input[type="password"]'));
    }

    function isCredentialUsername(input) {
        var key = [input.id, input.name, input.getAttribute('autocomplete')].join(' ');
        return usernameLike.test(key) && hasNearbyPassword(input);
    }

    function markNonCredentialInput(input) {
        if (!isTextLike(input) || isCredentialUsername(input)) return;
        var autocomplete = (input.getAttribute('autocomplete') || '').toLowerCase();
        if (!autocomplete) input.setAttribute('autocomplete', 'off');
        input.setAttribute('data-bookstark-noncredential', 'true');
        input.setAttribute('autocapitalize', input.getAttribute('autocapitalize') || 'off');
        if (!input.hasAttribute('spellcheck')) input.setAttribute('spellcheck', 'false');
        Object.keys(ignoreAttrs).forEach(function(name) {
            if (!input.hasAttribute(name)) input.setAttribute(name, ignoreAttrs[name]);
        });
    }

    function apply(root) {
        root = root || document;
        if (root.nodeType === 1 && root.matches && root.matches('input')) markNonCredentialInput(root);
        var inputs = root.querySelectorAll ? root.querySelectorAll('input') : [];
        for (var i = 0; i < inputs.length; i++) markNonCredentialInput(inputs[i]);
    }

    function start() {
        apply(document);
        if (!window.MutationObserver || start._observer) return;
        start._observer = new MutationObserver(function(records) {
            records.forEach(function(record) {
                for (var i = 0; i < record.addedNodes.length; i++) {
                    var node = record.addedNodes[i];
                    if (node.nodeType === 1) apply(node);
                }
            });
        });
        start._observer.observe(document.documentElement, { childList: true, subtree: true });
    }

    start();
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', function() { apply(document); });
    }

    return { apply: apply, start: start, markNonCredentialInput: markNonCredentialInput };
})();

window.BookStarkScrollLock = (function() {
    var locks = {};
    var locked = false;
    var scrollY = 0;
    var saved = null;

    function hasLocks() {
        for (var key in locks) {
            if (Object.prototype.hasOwnProperty.call(locks, key)) return true;
        }
        return false;
    }

    function applyLock() {
        if (locked) return;
        var body = document.body;
        var html = document.documentElement;
        if (!body || !html) return;
        scrollY = window.pageYOffset || html.scrollTop || body.scrollTop || 0;
        saved = {
            htmlOverflow: html.style.overflow,
            bodyOverflow: body.style.overflow,
            bodyPosition: body.style.position,
            bodyTop: body.style.top,
            bodyLeft: body.style.left,
            bodyRight: body.style.right,
            bodyWidth: body.style.width,
            bodyPaddingRight: body.style.paddingRight
        };
        var scrollbarWidth = window.innerWidth - html.clientWidth;
        html.style.overflow = 'hidden';
        body.style.overflow = 'hidden';
        body.style.position = 'fixed';
        body.style.top = '-' + scrollY + 'px';
        body.style.left = '0';
        body.style.right = '0';
        body.style.width = '100%';
        if (scrollbarWidth > 0) {
            body.style.paddingRight = scrollbarWidth + 'px';
        }
        locked = true;
    }

    function releaseLock() {
        if (!locked) return;
        var body = document.body;
        var html = document.documentElement;
        if (saved && body && html) {
            html.style.overflow = saved.htmlOverflow;
            body.style.overflow = saved.bodyOverflow;
            body.style.position = saved.bodyPosition;
            body.style.top = saved.bodyTop;
            body.style.left = saved.bodyLeft;
            body.style.right = saved.bodyRight;
            body.style.width = saved.bodyWidth;
            body.style.paddingRight = saved.bodyPaddingRight;
        }
        locked = false;
        saved = null;
        window.scrollTo(0, scrollY);
    }

    function lock(key) {
        locks[key || 'default'] = true;
        applyLock();
    }

    function unlock(key) {
        delete locks[key || 'default'];
        if (!hasLocks()) releaseLock();
    }

    function clear() {
        locks = {};
        releaseLock();
    }

    return { lock: lock, unlock: unlock, clear: clear };
})();

/* Shared action dropdown helper. */
(function() {
    function menuOf(dropdown) {
        return dropdown ? dropdown.querySelector('.bs-action-dd-menu, .bm-batch-dd-menu') : null;
    }

    function buttonOf(dropdown) {
        return dropdown ? dropdown.querySelector('.bs-action-dd-btn, .bm-batch-dd-btn') : null;
    }

    function isDisabled(el) {
        return !el || el.disabled || el.getAttribute('aria-disabled') === 'true';
    }

    function visible(el) {
        return !!(el && el.offsetParent !== null);
    }

    function itemsOf(container) {
        if (!container) return [];
        var nodes = container.querySelectorAll(
            '.bs-action-menu-item, .bm-batch-menu-item, [role="menuitem"], a[href], button:not(.bs-action-dd-btn):not(.bm-batch-dd-btn)'
        );
        var items = [];
        for (var i = 0; i < nodes.length; i++) {
            if (!isDisabled(nodes[i]) && visible(nodes[i])) items.push(nodes[i]);
        }
        return items;
    }

    function focusMenuItem(dropdown, index) {
        var menu = menuOf(dropdown);
        var items = itemsOf(menu);
        if (!items.length) return;
        var next = (index + items.length) % items.length;
        items[next].focus();
    }

    function openDropdown(dropdown, focusIndex) {
        if (!dropdown) return;
        closeAll(dropdown);
        dropdown.classList.add('open');
        var row = dropdown.closest('tr');
        if (row) row.classList.add('bs-action-dropdown-row-open');
        var menu = menuOf(dropdown);
        if (menu) menu.style.display = '';
        var btn = buttonOf(dropdown);
        if (btn) btn.setAttribute('aria-expanded', 'true');
        if (typeof focusIndex === 'number') {
            setTimeout(function() { focusMenuItem(dropdown, focusIndex); }, 0);
        }
    }

    function closeDropdown(dropdown) {
        if (!dropdown) return;
        dropdown.classList.remove('open');
        var row = dropdown.closest('tr');
        if (row) row.classList.remove('bs-action-dropdown-row-open');
        var menu = menuOf(dropdown);
        if (menu) menu.style.display = 'none';
        var btn = buttonOf(dropdown);
        if (btn) btn.setAttribute('aria-expanded', 'false');
    }

    function closeAll(except) {
        var dropdowns = document.querySelectorAll('.bs-action-dropdown.open, .bm-batch-dropdown.open');
        for (var i = 0; i < dropdowns.length; i++) {
            if (except && dropdowns[i] === except) continue;
            closeDropdown(dropdowns[i]);
        }
    }

    function toggle(dropdown) {
        if (!dropdown) return;
        var wasOpen = dropdown.classList.contains('open');
        closeAll(dropdown);
        if (wasOpen) {
            closeDropdown(dropdown);
            return;
        }
        openDropdown(dropdown);
    }

    function moveFocus(container, direction) {
        var items = itemsOf(container);
        if (!items.length) return;
        var idx = items.indexOf(document.activeElement);
        if (idx < 0) idx = direction > 0 ? -1 : 0;
        items[(idx + direction + items.length) % items.length].focus();
    }

    function openSubmenu(submenu) {
        if (!submenu) return;
        var trigger = submenu.querySelector('[data-bs-action-submenu-toggle]');
        submenu.classList.add('open');
        if (trigger) trigger.setAttribute('aria-expanded', 'true');
    }

    function closeSubmenu(submenu) {
        if (!submenu) return;
        var trigger = submenu.querySelector('[data-bs-action-submenu-toggle]');
        submenu.classList.remove('open');
        if (trigger) {
            trigger.setAttribute('aria-expanded', 'false');
            trigger.focus();
        }
    }

    document.addEventListener('click', function(event) {
        var submenuTrigger = event.target.closest('[data-bs-action-submenu-toggle]');
        if (submenuTrigger) {
            if (isDisabled(submenuTrigger)) return;
            event.preventDefault();
            event.stopPropagation();
            var submenu = submenuTrigger.closest('.bs-action-submenu');
            if (submenu) {
                submenu.classList.toggle('open');
                submenuTrigger.setAttribute('aria-expanded', submenu.classList.contains('open') ? 'true' : 'false');
            }
            return;
        }

        var trigger = event.target.closest('[data-bs-action-dropdown-toggle]');
        if (trigger) {
            if (isDisabled(trigger)) return;
            event.preventDefault();
            event.stopPropagation();
            toggle(trigger.closest('.bs-action-dropdown, .bm-batch-dropdown'));
            return;
        }
        if (!event.target.closest('.bs-action-dropdown, .bm-batch-dropdown')) {
            closeAll();
        }
    });

    document.addEventListener('keydown', function(event) {
        var trigger = event.target.closest('.bs-action-dd-btn, .bm-batch-dd-btn');
        if (trigger) {
            if (isDisabled(trigger)) return;
            var triggerDropdown = trigger.closest('.bs-action-dropdown, .bm-batch-dropdown');
            if (event.key === 'ArrowDown') {
                event.preventDefault();
                openDropdown(triggerDropdown, 0);
            } else if (event.key === 'ArrowUp') {
                event.preventDefault();
                openDropdown(triggerDropdown, -1);
            } else if (event.key === 'Escape') {
                closeDropdown(triggerDropdown);
            }
            return;
        }

        var dropdown = event.target.closest('.bs-action-dropdown.open, .bm-batch-dropdown.open');
        if (!dropdown) return;
        var menu = menuOf(dropdown);
        var submenu = event.target.closest('.bs-action-submenu');

        if (event.key === 'ArrowDown') {
            event.preventDefault();
            moveFocus(menu, 1);
        } else if (event.key === 'ArrowUp') {
            event.preventDefault();
            moveFocus(menu, -1);
        } else if (event.key === 'Home') {
            event.preventDefault();
            focusMenuItem(dropdown, 0);
        } else if (event.key === 'End') {
            event.preventDefault();
            focusMenuItem(dropdown, -1);
        } else if (event.key === 'ArrowRight' && submenu && event.target.matches('[data-bs-action-submenu-toggle]')) {
            event.preventDefault();
            openSubmenu(submenu);
            var panel = submenu.querySelector('.bs-action-submenu-panel');
            var subItems = itemsOf(panel);
            if (subItems.length) subItems[0].focus();
        } else if (event.key === 'ArrowLeft' && submenu) {
            event.preventDefault();
            closeSubmenu(submenu);
        } else if (event.key === 'Escape') {
            event.preventDefault();
            closeDropdown(dropdown);
            var btn = buttonOf(dropdown);
            if (btn) btn.focus();
        } else if (event.key === 'Tab') {
            closeDropdown(dropdown);
        }
    });

    window.BSActionDropdown = {
        open: openDropdown,
        toggle: toggle,
        closeAll: closeAll,
        close: closeDropdown
    };
})();
