/* ===== BookStark Service Worker Registration ===== */
(function() {
  'use strict';

  var toastShown = false;
  var deferredInstallPrompt = null;

  function dispatchPWAChange() {
    window.dispatchEvent(new CustomEvent('bs:pwa-status-change'));
  }

  function isStandalone() {
    return window.matchMedia('(display-mode: standalone)').matches || window.navigator.standalone === true;
  }

  function formatBytes(bytes) {
    bytes = Number(bytes || 0);
    if (bytes < 1024) return bytes + ' B';
    if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + ' KB';
    return (bytes / 1024 / 1024).toFixed(1) + ' MB';
  }

  function getStorageEstimate() {
    if (!navigator.storage || !navigator.storage.estimate) {
      return Promise.resolve({ usageText: '-', quotaText: '-', percent: 0 });
    }
    return navigator.storage.estimate().then(function(info) {
      var usage = info.usage || 0;
      var quota = info.quota || 0;
      return {
        usage: usage,
        quota: quota,
        usageText: formatBytes(usage),
        quotaText: quota ? formatBytes(quota) : '-',
        percent: quota ? Math.round(usage / quota * 100) : 0
      };
    });
  }

  function getStatus() {
    return Promise.all([getStorageEstimate(), getCacheDetails()]).then(function(results) {
      var storage = results[0];
      var caches = results[1];
      return {
        standalone: isStandalone(),
        installable: !!deferredInstallPrompt,
        serviceWorker: 'serviceWorker' in navigator,
        caches: 'caches' in window,
        cacheDetails: caches,
        online: navigator.onLine !== false,
        storage: storage
      };
    });
  }

  function promptInstall() {
    if (!deferredInstallPrompt) return Promise.resolve({ available: false });
    var promptEvent = deferredInstallPrompt;
    deferredInstallPrompt = null;
    promptEvent.prompt();
    return promptEvent.userChoice.then(function(choice) {
      dispatchPWAChange();
      return choice;
    }).catch(function(err) {
      dispatchPWAChange();
      throw err;
    });
  }

  function cacheModuleName(key) {
    if (key.indexOf('bookstark-static') === 0) return 'static';
    if (key.indexOf('bookstark-dynamic') === 0) return 'dynamic';
    return 'other';
  }

  function getCacheDetails() {
    if (!('caches' in window)) return Promise.resolve([]);
    return caches.keys().then(function(keys) {
      return Promise.all(keys.map(function(key) {
        return caches.open(key).then(function(cache) {
          return cache.keys().then(function(reqs) {
            return {
              key: key,
              module: cacheModuleName(key),
              count: reqs.length
            };
          });
        }).catch(function() {
          return { key: key, module: cacheModuleName(key), count: 0 };
        });
      }));
    });
  }

  function clearCaches(scope) {
    if (!('caches' in window)) return Promise.resolve(0);
    scope = scope || 'all';
    return caches.keys().then(function(keys) {
      var filtered = keys.filter(function(key) {
        if (scope === 'all') return true;
        return cacheModuleName(key) === scope;
      });
      return Promise.all(filtered.map(function(key) { return caches.delete(key); })).then(function(results) {
        var count = results.filter(Boolean).length;
        dispatchPWAChange();
        return count;
      });
    });
  }

  function isCachedPageRequest(request) {
    var accept = request.headers && request.headers.get ? (request.headers.get('accept') || '') : '';
    return request.mode === 'navigate' || request.destination === 'document' || accept.indexOf('text/html') !== -1;
  }

  function clearPageCache() {
    if (!('caches' in window)) return Promise.resolve(0);
    return caches.keys().then(function(keys) {
      var dynamicKeys = keys.filter(function(key) {
        return cacheModuleName(key) === 'dynamic';
      });
      return Promise.all(dynamicKeys.map(function(key) {
        return caches.open(key).then(function(cache) {
          return cache.keys().then(function(requests) {
            var pages = requests.filter(isCachedPageRequest);
            return Promise.all(pages.map(function(request) {
              return cache.delete(request);
            })).then(function(results) {
              return results.filter(Boolean).length;
            });
          });
        });
      })).then(function(counts) {
        return counts.reduce(function(total, count) { return total + count; }, 0);
      });
    });
  }

  window.BookStarkPWA = {
    getStatus: getStatus,
    promptInstall: promptInstall,
    clearCaches: clearCaches,
    clearPageCache: clearPageCache,
    getCacheDetails: getCacheDetails,
    isStandalone: isStandalone
  };

  window.addEventListener('beforeinstallprompt', function(event) {
    event.preventDefault();
    deferredInstallPrompt = event;
    dispatchPWAChange();
  });

  window.addEventListener('appinstalled', function() {
    deferredInstallPrompt = null;
    dispatchPWAChange();
    if (typeof BSDialog !== 'undefined' && BSDialog.toast) {
      BSDialog.toast('已安装到设备', 'success', 3000);
    }
  });

  if (!('serviceWorker' in navigator)) return;

  navigator.serviceWorker.register('/sw.js').then(function(reg) {
    // Check for updates on load
    reg.update().catch(function(err) {
      console.warn('SW update check failed:', err);
    });

    reg.addEventListener('updatefound', function() {
      var newWorker = reg.installing;
      newWorker.addEventListener('statechange', function() {
        if (newWorker.state === 'activated' && navigator.serviceWorker.controller) {
          showUpdateToast();
        }
      });
    });
  }).catch(function(err) {
    console.warn('SW registration failed:', err);
  });

  // Also detect controller change (e.g. after skipWaiting)
  var refreshing = false;
  navigator.serviceWorker.addEventListener('controllerchange', function() {
    if (refreshing) return;
    refreshing = true;
    showUpdateToast();
  });

  function showUpdateToast() {
    if (toastShown) return;
    toastShown = true;
    if (typeof BSDialog !== 'undefined' && BSDialog.toast) {
      var ver = window.BS_VERSION || '';
      var msg = ver ? '新版本 ' + ver + ' 已就绪' : '新版本已就绪';
      BSDialog.toast(msg, 'info', 5000);
    }
  }

  // Listen for pre-cache result from service worker
  navigator.serviceWorker.addEventListener('message', function(event) {
    if (event.data && event.data.type === 'PRECACHE_RESULT') {
      var d = event.data.data;
      if (d && typeof BSDialog !== 'undefined' && BSDialog.toast) {
        var pct = d.total > 0 ? Math.round(d.ok / d.total * 100) : 0;
        var msg = '预缓存 ' + d.total + ' 个资源，成功 ' + d.ok +
                  ' 个，复用 ' + (d.reused || 0) + ' 个，失败 ' + d.fail + ' 个（' + pct + '%）';
        BSDialog.toast(msg, d.fail > 0 ? 'warning' : 'success', 6000);
      }
    }
  });
})();
