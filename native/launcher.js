(function () {
  'use strict';
  var script = document.currentScript;
  var remoteButton = document.getElementById('show-remote');
  if (remoteButton) remoteButton.addEventListener('click', function () {
    document.getElementById('remote-form').hidden = false;
    remoteButton.setAttribute('aria-expanded', 'true');
    document.getElementById('address').focus();
  });
  document.querySelectorAll('.workspace-choice').forEach(function(form) {
    form.addEventListener('submit', function() {
      form.elements.remember.value = document.getElementById('remember-workspace').checked ? 'on' : 'off';
      form.querySelector('button[type="submit"]').disabled = true;
    });
  });
  var retry = document.getElementById('startup-retry');
  async function resume() {
    retry.disabled = true; retry.hidden = true;
    document.getElementById('startup-title').textContent = script.dataset.loading;
    try {
      var response = await fetch('/__bookstark/resume', {method:'POST'});
      var data = await response.json();
      if (!response.ok || !data.url) throw new Error('resume failed');
      location.replace(data.url);
    } catch (_) {
      document.getElementById('startup-title').textContent = script.dataset.error;
      document.getElementById('startup-message').textContent = script.dataset.detail;
      retry.hidden = false; retry.disabled = false;
    }
  }
  if (retry) { retry.addEventListener('click', resume); resume(); }
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
