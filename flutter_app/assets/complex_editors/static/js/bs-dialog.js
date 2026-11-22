/* ===== BookStark Dialog Component ===== */
/* Requires: utils.js (escHtml, escAttr) */
var BSDialog = (function() {
  var _previousFocus = null;
  var _trapHandler = null;
  var _activeCancel = null;
  var _focusableSelector = 'a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])';
  function _getFocusable(container) {
    return Array.prototype.slice.call(container.querySelectorAll(_focusableSelector)).filter(function(el) { return el.offsetParent !== null; });
  }
  function _trapFocus(e) {
    var o = document.getElementById('bs-dialog-overlay');
    if (!o) return;
    if (e.key === 'Escape') {
      e.preventDefault();
      if (_activeCancel) _activeCancel();
      else hide();
      return;
    }
    if (e.key !== 'Tab') return;
    var b = document.getElementById('bs-dialog-box');
    if (!b) return;
    var focusable = _getFocusable(b);
    if (!focusable.length) return;
    var first = focusable[0], last = focusable[focusable.length - 1];
    if (e.shiftKey) {
      if (document.activeElement === first) { e.preventDefault(); last.focus(); }
    } else {
      if (document.activeElement === last) { e.preventDefault(); first.focus(); }
    }
  }
  function ensureOverlay() {
    var o = document.getElementById('bs-dialog-overlay');
    if (!o) { o = document.createElement('div'); o.id = 'bs-dialog-overlay'; o.className = 'bs-dialog-overlay'; o.setAttribute('role', 'dialog'); o.setAttribute('aria-modal', 'true'); o.innerHTML = '<div id="bs-dialog-box" class="bs-dialog-box" role="document"></div>'; document.body.appendChild(o); }
    return o;
  }
  function showBox(html) {
    _previousFocus = document.activeElement;
    var o = ensureOverlay(), b = document.getElementById('bs-dialog-box');
    b.innerHTML = html; o.classList.add('active');
    if (window.BookStarkFormGuards && typeof window.BookStarkFormGuards.apply === 'function') window.BookStarkFormGuards.apply(b);
    if (window.BookStarkScrollLock) BookStarkScrollLock.lock('bs-dialog');
    var title = b.querySelector('.bs-dialog-title'); if (title) { if (!title.id) title.id = 'bs-dialog-title-' + Date.now(); o.setAttribute('aria-labelledby', title.id); }
    if (_trapHandler) { document.removeEventListener('keydown', _trapHandler); }
    _trapHandler = _trapFocus;
    document.addEventListener('keydown', _trapHandler);
    var i = b.querySelector('input'); if (i) { setTimeout(function() { i.focus(); i.select(); }, 50); } else { var btn = b.querySelector('button'); if (btn) btn.focus(); }
  }
	  function hide() {
    if (_trapHandler) { document.removeEventListener('keydown', _trapHandler); _trapHandler = null; }
    _activeCancel = null;
    var o = document.getElementById('bs-dialog-overlay'); if (o) o.classList.remove('active');
    if (window.BookStarkScrollLock) BookStarkScrollLock.unlock('bs-dialog');
    if (_previousFocus && typeof _previousFocus.focus === 'function') {
      try { _previousFocus.focus(); } catch(e) {}
      _previousFocus = null;
    }
	  }
	  function t(key, fallback) {
	    return (window.__ && window.__(key)) || fallback;
	  }
	  function isSmallScreen() {
	    return window.matchMedia && window.matchMedia('(max-width: 640px)').matches;
	  }
	  function confirm2(msg) {
	    return new Promise(function(resolve) {
	      showBox('<div class="bs-dialog-title">'+escHtml(msg)+'</div><div class="bs-dialog-actions"><button class="bs-btn bs-btn-cancel" id="bs-confirm-cancel">'+escHtml(t('dialog.cancel', 'Cancel'))+'</button><button class="bs-btn bs-btn-primary" id="bs-confirm-ok">'+escHtml(t('dialog.confirm', 'OK'))+'</button></div>');
	      var overlay = document.getElementById('bs-dialog-overlay');
	      var done = false;
	      function finish(value) {
	        if (done) return;
	        done = true;
	        if (overlay) overlay.removeEventListener('click', onOverlayClick);
	        hide();
	        resolve(value);
	      }
	      function onOverlayClick(e) {
	        if (e.target === overlay && isSmallScreen()) finish(false);
	      }
	      _activeCancel = function() { finish(false); };
	      if (overlay) overlay.addEventListener('click', onOverlayClick);
	      document.getElementById('bs-confirm-ok').onclick = function() { finish(true); };
	      document.getElementById('bs-confirm-cancel').onclick = function() { finish(false); };
	    });
	  }
	  function prompt2(msg, def) {
	    return new Promise(function(resolve) {
	      showBox('<div class="bs-dialog-title">'+escHtml(msg)+'</div><div class="bs-dialog-input-wrap"><input id="bs-prompt-input" class="bs-dialog-input dialog-input" value="'+escAttr(def||'')+'"></div><div class="bs-dialog-actions"><button class="bs-btn bs-btn-cancel" id="bs-prompt-cancel">'+escHtml(t('dialog.cancel', 'Cancel'))+'</button><button class="bs-btn bs-btn-primary" id="bs-prompt-ok">'+escHtml(t('dialog.confirm', 'OK'))+'</button></div>');
	      var i = document.getElementById('bs-prompt-input');
	      i.onkeydown = function(e) { if (e.key==='Enter') { hide(); resolve(i.value); } if (e.key==='Escape') { hide(); resolve(null); } };
	      document.getElementById('bs-prompt-ok').onclick = function() { hide(); resolve(i.value); };
      document.getElementById('bs-prompt-cancel').onclick = function() { hide(); resolve(null); };
    });
  }
	  function alert2(msg) {
	    return new Promise(function(resolve) {
	      showBox('<div class="bs-dialog-title">'+escHtml(msg)+'</div><div class="bs-dialog-actions"><button class="bs-btn bs-btn-primary" id="bs-alert-ok">'+escHtml(t('dialog.ok', 'Got it'))+'</button></div>');
	      document.getElementById('bs-alert-ok').onclick = function() { hide(); resolve(); };
	    });
	  }

  /* ===== Toast ===== */
  var _toastContainer = null;
  var _TOAST_ICONS = {
    success: '<i class="fa-solid fa-circle-check" style="font-size:16px"></i>',
    error: '<i class="fa-solid fa-circle-xmark" style="font-size:16px"></i>',
    warning: '<i class="fa-solid fa-triangle-exclamation" style="font-size:16px"></i>',
    info: '<i class="fa-solid fa-circle-info" style="font-size:16px"></i>'
  };
  function _hasSmallScreenModalOpen() {
    return isSmallScreen() && !!document.querySelector('.asset-modal-backdrop.open, .asset-modal-backdrop.active, .editor-overlay.active, .bs-dialog-form-overlay.active');
  }
  function _positionToastContainer() {
    if (!_toastContainer) return;
    var container = _toastContainer;
    if (_hasSmallScreenModalOpen()) {
      container.style.top = 'auto';
      container.style.bottom = '16px';
      container.style.right = '16px';
      container.style.left = '16px';
      container.style.flexDirection = 'column-reverse';
    } else {
      container.style.top = '52px';
      container.style.bottom = 'auto';
      container.style.right = '16px';
      container.style.left = 'auto';
      container.style.flexDirection = 'column';
    }
  }
  function _ensureToastContainer() {
    if (!_toastContainer) {
      _toastContainer = document.createElement('div');
      _toastContainer.id = 'bs-toast-container';
      _toastContainer.style.cssText = 'position:fixed;top:52px;right:16px;z-index:99999;display:flex;flex-direction:column;gap:8px;pointer-events:none;';
      document.body.appendChild(_toastContainer);
    }
    _positionToastContainer();
    return _toastContainer;
  }
  /**
   * Show a lightweight toast notification.
   * @param {string} message - Text to display
   * @param {string} [type='info'] - 'success' | 'error' | 'info'
   * @param {number} [duration=2000] - Auto-dismiss time in ms
   */
  function toast(message, type, duration) {
    type = type || 'info';
    duration = duration || 2000;
    var container = _ensureToastContainer();
    _positionToastContainer();
    var el = document.createElement('div');
    el.className = 'bs-toast bs-toast-' + type + ' toast-enter';
    el.style.cssText = 'pointer-events:auto;display:flex;align-items:center;gap:8px;padding:10px 16px;border-radius:8px;font-size:13px;line-height:1.4;max-width:360px;box-shadow:0 4px 16px rgba(0,0,0,0.12);color:#fff;';
    if (type === 'success') el.style.background = '#16a34a';
    else if (type === 'error') el.style.background = '#dc2626';
    else if (type === 'warning') el.style.background = '#d97706';
    else el.style.background = '#2563eb';
    el.innerHTML = (_TOAST_ICONS[type] || _TOAST_ICONS.info) + '<span>' + escHtml(message) + '</span>';
    container.appendChild(el);
    setTimeout(function() {
      el.classList.remove('toast-enter');
      el.classList.add('toast-exit');
      var removed = false;
      function remove() {
        if (removed) return;
        removed = true;
        el.remove();
      }
      el.addEventListener('animationend', remove);
      // fallback: 确保即使 animationend 未触发也能移除
      setTimeout(remove, 500);
    }, duration);
  }

  return { confirm2: confirm2, prompt2: prompt2, alert2: alert2, toast: toast };
})();
