(function() {
  'use strict';

  var SELECTOR = [
    '.page-sticky-header',
    '.sh-search-wrap',
    '#panel-ssh .asset-panel-head',
    '#panel-webdav .asset-panel-head'
  ].join(',');
  var items = [];
  var ticking = false;

  function toPx(value) {
    var n = parseFloat(value);
    return Number.isFinite(n) ? n : 0;
  }

  function readTopOffset(el) {
    return toPx(window.getComputedStyle(el).top);
  }

  function readAbsoluteTop(el) {
    return el.getBoundingClientRect().top + window.scrollY;
  }

  function shouldTrack(el) {
    var style = window.getComputedStyle(el);
    return style.position === 'sticky' || style.position === '-webkit-sticky';
  }

  function collect() {
    items = Array.prototype.slice.call(document.querySelectorAll(SELECTOR)).map(function(el) {
      return {
        el: el,
        top: readTopOffset(el),
        absoluteTop: readAbsoluteTop(el)
      };
    });
    update();
  }

  function refreshMeasurements() {
    items.forEach(function(item) {
      item.top = readTopOffset(item.el);
      item.absoluteTop = readAbsoluteTop(item.el);
    });
    update();
  }

  function update() {
    ticking = false;
    items.forEach(function(item) {
      var el = item.el;
      if (!el.isConnected || !shouldTrack(el)) {
        el.classList.remove('is-stuck');
        return;
      }
      var stuck = window.scrollY + item.top >= item.absoluteTop - 1;
      el.classList.toggle('is-stuck', stuck);
    });
  }

  function requestUpdate() {
    if (ticking) return;
    ticking = true;
    window.requestAnimationFrame(update);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', collect, { once: true });
  } else {
    collect();
  }
  window.addEventListener('load', refreshMeasurements);
  window.addEventListener('resize', refreshMeasurements);
  window.addEventListener('scroll', requestUpdate, { passive: true });
  window.addEventListener('pageshow', refreshMeasurements);
})();
