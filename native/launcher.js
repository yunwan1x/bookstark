(function () {
  'use strict';
  var button = document.getElementById('copyPassword');
  if (!button) return;
  button.addEventListener('click', async function () {
    var value = document.getElementById('passwordValue').textContent;
    var status = document.getElementById('copyStatus');
    var copied = false;
    button.disabled = true;
    try {
      if (navigator.clipboard && navigator.clipboard.writeText) {
        try { await navigator.clipboard.writeText(value); copied = true; } catch (_) { /* Older WebViews may require the selection fallback. */ }
      }
      if (!copied) {
        var selection = window.getSelection();
        var range = document.createRange();
        range.selectNodeContents(document.getElementById('passwordValue'));
        selection.removeAllRanges();
        selection.addRange(range);
        copied = document.execCommand('copy');
        if (copied) selection.removeAllRanges();
      }
      status.textContent = copied ? button.dataset.copied : button.dataset.failed;
    } catch (_) {
      status.textContent = button.dataset.failed;
    } finally {
      button.disabled = false;
    }
  });
})();
