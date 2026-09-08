/* ===== BookStark Mobile UI primitives ===== */
(function() {
  'use strict';

  function enhanceSheet(root, opts) {
    if (!root || root.__bsSheetEnhanced) return;
    opts = opts || {};
    var selector = opts.panelSelector || root.getAttribute('data-mobile-sheet-panel') || '.mobile-sheet';
    var panel = selector === 'self' ? root : root.querySelector(selector);
    if (!panel) return;
    root.__bsSheetEnhanced = true;
    root.classList.add('bs-mobile-sheet-root');
    panel.classList.add('bs-mobile-sheet-panel');
    var close = typeof opts.close === 'function' ? opts.close : resolveClose(root.getAttribute('data-mobile-sheet-close'));

    function isCloseTarget(target) {
      return selector !== 'self' && target === root && root.getAttribute('data-mobile-sheet-backdrop') !== 'false';
    }

    root.addEventListener('click', function(e) {
      if (window.innerWidth > 640 || !isCloseTarget(e.target)) return;
      close();
    });

    root.addEventListener('keydown', function(e) {
      if (e.key !== 'Escape') return;
      close();
    });
  }

  function syncVisualViewportHeight() {
    var vv = window.visualViewport;
    var height = vv && vv.height ? vv.height : window.innerHeight;
    if (!height) return;
    document.documentElement.style.setProperty('--bs-vvh', height + 'px');
  }

  function initVisualViewportHeight() {
    syncVisualViewportHeight();
    window.addEventListener('resize', syncVisualViewportHeight);
    if (window.visualViewport) {
      window.visualViewport.addEventListener('resize', syncVisualViewportHeight);
      window.visualViewport.addEventListener('scroll', syncVisualViewportHeight);
    }
  }

  function resolveClose(path) {
    if (!path) return function() {};
    var parts = path.split('.');
    var ctx = window;
    for (var i = 0; i < parts.length - 1; i++) {
      ctx = ctx && ctx[parts[i]];
    }
    var fn = ctx && ctx[parts[parts.length - 1]];
    return typeof fn === 'function' ? function() { fn.call(ctx); } : function() {};
  }

  function enhanceIndexedSwipeNav(root, opts) {
    if (!root || root.__bsSwipeNavEnhanced) return;
    opts = opts || {};
    root.__bsSwipeNavEnhanced = true;
    var itemSelector = opts.itemSelector || root.getAttribute('data-swipe-item') || '[data-swipe-idx],[data-tab],[role="tab"]';
    var indexAttr = opts.indexAttr || root.getAttribute('data-swipe-index') || 'data-swipe-idx';
    var mode = opts.mode || root.getAttribute('data-swipe-mode') || 'click';
    var ignoreSelector = opts.ignoreSelector || root.getAttribute('data-swipe-ignore') || 'input,textarea,select,[data-swipe-ignore]';
    var maxWidth = opts.maxWidth || parseInt(root.getAttribute('data-swipe-max-width') || '640', 10);
    var threshold = opts.threshold || parseInt(root.getAttribute('data-swipe-threshold') || '54', 10);
    var startX = 0;
    var startY = 0;
    var lastX = 0;
    var tracking = false;
    var horizontalSwipe = false;
    var suppressClick = false;
    var navigating = false;
    var activePointerId = null;

    root.style.touchAction = root.style.touchAction || 'pan-y';

    function visible(el) {
      return !!(el && (el.offsetWidth || el.offsetHeight || el.getClientRects().length));
    }

    function itemIndex(el, fallback) {
      var raw = el.getAttribute(indexAttr);
      if (raw === null || raw === '') raw = el.getAttribute('data-nav-idx');
      if (raw === null || raw === '') raw = el.getAttribute('data-swipe-idx');
      var idx = parseInt(raw, 10);
      return isNaN(idx) ? fallback : idx;
    }

    function getItems() {
      var byIdx = {};
      Array.prototype.slice.call(root.querySelectorAll(itemSelector)).forEach(function(el, order) {
        if (el.disabled || el.getAttribute('aria-disabled') === 'true') return;
        var idx = itemIndex(el, order);
        if (!byIdx[idx] || el.classList.contains('active') || el.getAttribute('aria-selected') === 'true' || visible(el)) {
          byIdx[idx] = el;
        }
      });
      return Object.keys(byIdx).map(function(idx) {
        return { idx: parseInt(idx, 10), el: byIdx[idx] };
      }).sort(function(a, b) { return a.idx - b.idx; });
    }

    function isActive(el) {
      if (!el) return false;
      if (el.classList.contains('active') || el.getAttribute('aria-selected') === 'true') return true;
      if (el.href) {
        try {
          var url = new URL(el.href, window.location.href);
          return url.pathname === window.location.pathname;
        } catch(e) {}
      }
      return false;
    }

    function getActivePos(items) {
      for (var i = 0; i < items.length; i++) {
        if (isActive(items[i].el)) return i;
      }
      return -1;
    }

    function activate(el) {
      if (!el || navigating) return;
      if (typeof opts.activate === 'function') {
        opts.activate(el);
        return;
      }
      if (mode === 'href' && el.href) {
        navigating = true;
        window.location.assign(el.href);
      } else {
        el.click();
      }
    }

    function navigateBySwipe(dir) {
      var items = getItems();
      var cur = getActivePos(items);
      if (cur < 0) return;
      var next = cur + dir;
      if (next < 0 || next >= items.length) return;
      activate(items[next].el);
    }

    function shouldIgnoreTarget(target) {
      if (!target) return false;
      if (typeof opts.shouldIgnoreTarget === 'function' && opts.shouldIgnoreTarget(target)) return true;
      if (ignoreSelector && target.closest(ignoreSelector)) return true;
      if (root.classList.contains('search-expanded')) return true;
      return false;
    }

    function reset() {
      tracking = false;
      horizontalSwipe = false;
      activePointerId = null;
    }

    function beginSwipe(clientX, clientY, target, pointerId) {
      if (window.innerWidth > maxWidth || navigating || shouldIgnoreTarget(target)) return false;
      if (getItems().length < 2) return false;
      startX = clientX;
      startY = clientY;
      lastX = startX;
      tracking = true;
      horizontalSwipe = false;
      activePointerId = pointerId == null ? null : pointerId;
      return true;
    }

    function moveSwipe(clientX, clientY, event) {
      if (!tracking) return;
      var dx = clientX - startX;
      var dy = clientY - startY;
      lastX = clientX;
      if (Math.abs(dx) > 12 && Math.abs(dx) > Math.abs(dy) * 1.15) {
        horizontalSwipe = true;
        if (event && event.cancelable) event.preventDefault();
      }
      if (Math.abs(dy) > Math.abs(dx) * 1.3 && !horizontalSwipe) reset();
    }

    function endSwipe(clientX) {
      if (!tracking) return;
      tracking = false;
      activePointerId = null;
      var dx = clientX - startX;
      var shouldNavigate = horizontalSwipe && Math.abs(dx) >= threshold;
      horizontalSwipe = false;
      if (!shouldNavigate) return;
      navigateBySwipe(dx < 0 ? 1 : -1);
      suppressClick = true;
      window.setTimeout(function() { suppressClick = false; }, 350);
    }

    root.addEventListener('touchstart', function(e) {
      var t = e.touches && e.touches[0];
      if (!t) return;
      beginSwipe(t.clientX, t.clientY, e.target, null);
    }, { passive: true });

    document.addEventListener('touchmove', function(e) {
      if (!tracking) return;
      var t = e.touches && e.touches[0];
      if (!t) return;
      moveSwipe(t.clientX, t.clientY, e);
    }, { passive: false });

    document.addEventListener('touchend', function(e) {
      if (!tracking) return;
      var t = e.changedTouches && e.changedTouches[0];
      endSwipe(t ? t.clientX : lastX);
    }, { passive: true });

    document.addEventListener('touchcancel', reset, { passive: true });
    root.addEventListener('pointerdown', function(e) {
      if (beginSwipe(e.clientX, e.clientY, e.target, e.pointerId) && root.setPointerCapture) {
        try { root.setPointerCapture(e.pointerId); } catch(err) {}
      }
    });
    document.addEventListener('pointermove', function(e) {
      if (!tracking || activePointerId !== e.pointerId) return;
      moveSwipe(e.clientX, e.clientY, e);
    });
    document.addEventListener('pointerup', function(e) {
      if (!tracking || activePointerId !== e.pointerId) return;
      endSwipe(e.clientX);
    });
    document.addEventListener('pointercancel', function(e) {
      if (activePointerId === e.pointerId) reset();
    });
    root.addEventListener('click', function(e) {
      if (!suppressClick) return;
      e.preventDefault();
      e.stopPropagation();
    }, true);
  }

  function autoEnhanceSwipeNavs(scope) {
    scope = scope || document;
    Array.prototype.slice.call(scope.querySelectorAll('[data-swipe-nav]')).forEach(function(root) {
      enhanceIndexedSwipeNav(root);
    });
  }

  function autoEnhanceSheets(scope) {
    scope = scope || document;
    Array.prototype.slice.call(scope.querySelectorAll('[data-mobile-sheet]')).forEach(function(root) {
      enhanceSheet(root);
    });
  }

  function init() {
    initVisualViewportHeight();
    autoEnhanceSheets(document);
    autoEnhanceSwipeNavs(document);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

  window.BookStarkMobileUI = {
    enhanceSheet: enhanceSheet,
    enhanceIndexedSwipeNav: enhanceIndexedSwipeNav,
    syncVisualViewportHeight: syncVisualViewportHeight,
    autoEnhanceSheets: autoEnhanceSheets,
    autoEnhanceSwipeNavs: autoEnhanceSwipeNavs
  };
})();
