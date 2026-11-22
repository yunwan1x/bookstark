(function () {
  'use strict';

  var currentLang = window.__currentLang || 'zh';

  function _getMsgs() {
    return window.__I18N_MESSAGES || {};
  }

  function __(key) {
    var msgs = _getMsgs();
    if (msgs.hasOwnProperty(key)) return msgs[key];
    return key;
  }

  function __setLang(lang) {
    currentLang = lang;

    var textNodes = document.querySelectorAll('[data-i18n]');
    for (var i = 0; i < textNodes.length; i++) {
      var el = textNodes[i];
      var key = el.getAttribute('data-i18n');
      if (key) {
        var translated = __(key);
        if (translated !== key) {
          el.textContent = translated;
        }
      }
    }

    var titleNodes = document.querySelectorAll('[data-i18n-title]');
    for (var j = 0; j < titleNodes.length; j++) {
      var el2 = titleNodes[j];
      var titleKey = el2.getAttribute('data-i18n-title');
      if (titleKey) {
        var t = __(titleKey);
        if (t !== titleKey) {
          el2.setAttribute('title', t);
        }
      }
    }

    var phNodes = document.querySelectorAll('[data-i18n-placeholder]');
    for (var k = 0; k < phNodes.length; k++) {
      var el3 = phNodes[k];
      var phKey = el3.getAttribute('data-i18n-placeholder');
      if (phKey) {
        var p = __(phKey);
        if (p !== phKey) {
          el3.setAttribute('placeholder', p);
        }
      }
    }
  }

  function __reloadLang(lang) {
    currentLang = lang;
    var xhr = new XMLHttpRequest();
    xhr.open('GET', '/api/lang/bundle?lang=' + encodeURIComponent(lang), true);
    xhr.onload = function () {
      if (xhr.status === 200) {
        try {
          var newMsgs = JSON.parse(xhr.responseText);
          window.__I18N_MESSAGES = newMsgs;
          __setLang(lang);
        } catch (e) {}
      }
    };
    xhr.onerror = function () {};
    xhr.send();
  }

  window.__ = __;
  window.__setLang = __setLang;
  window.__reloadLang = __reloadLang;
})();
