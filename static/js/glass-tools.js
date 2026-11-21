/* Theme paint for the explicitly approved HTML pages included in the glass designs.
   The stored article and arbitrary user HTML remain untouched. */
(function () {
    'use strict';
    var tool = /\/shares\/share-1795182178449561508(?:\/|$)/.test(location.pathname) ? 'short' :
        /\/shares\/share-1783071864572357387(?:\/|$)/.test(location.pathname) ? 'meeting' :
        /\/shares\/share-1782810570348556351(?:\/|$)/.test(location.pathname) ? 'article' : '';
    if (!tool) return;
    function sync(frame) {
        try {
            var doc = frame.contentDocument;
            if (!doc || !doc.head || !doc.body) return;
            var enabled = document.documentElement.dataset.themeStyle === 'glass';
            var sheet = doc.getElementById('bookstark-glass-tool');
            if (enabled && !sheet) {
                sheet = doc.createElement('link');
                sheet.id = 'bookstark-glass-tool'; sheet.rel = 'stylesheet';
                sheet.href = '/static/css/glass-tools.css?v=pearl-v2';
                doc.head.appendChild(sheet);
            }
            if (sheet) sheet.disabled = !enabled;
            if (enabled) doc.documentElement.dataset.bookstarkGlass = tool;
            else delete doc.documentElement.dataset.bookstarkGlass;
        } catch (_) { /* Cross-origin frames keep their own appearance. */ }
    }
    function scan() {
        document.querySelectorAll('iframe.html-preview-iframe').forEach(function (frame) {
            if (!frame.dataset.glassBound) {
                frame.dataset.glassBound = '1';
                frame.addEventListener('load', function () { sync(frame); });
            }
            sync(frame);
        });
    }
    function start() {
        new MutationObserver(scan).observe(document.body, {childList:true, subtree:true});
        new MutationObserver(scan).observe(document.documentElement, {attributes:true, attributeFilter:['data-theme-style']});
        scan();
    }
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start);
    else start();
})();
