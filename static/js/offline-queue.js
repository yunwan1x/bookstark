/* ===== BookStark Offline Queue ===== */
(function() {
  'use strict';

  var DB_NAME = 'bookstark-offline-queue';
  var DB_VERSION = 1;
  var STORE_NAME = 'requests';
  var db = null;

  function emit(name, detail) {
    try {
      window.dispatchEvent(new CustomEvent(name, { detail: detail || {} }));
    } catch(e) {}
  }

  function openDB() {
    if (db) return Promise.resolve(db);
    return new Promise(function(resolve, reject) {
      var req = indexedDB.open(DB_NAME, DB_VERSION);
      req.onupgradeneeded = function(e) {
        var database = e.target.result;
        if (!database.objectStoreNames.contains(STORE_NAME)) {
          database.createObjectStore(STORE_NAME, { keyPath: 'id', autoIncrement: true });
        }
      };
      req.onsuccess = function(e) {
        db = e.target.result;
        resolve(db);
      };
      req.onerror = function(e) {
        reject(e.target.error);
      };
    });
  }

  function addToQueue(url, method, headers, body) {
    return openDB().then(function(database) {
      return new Promise(function(resolve, reject) {
        var tx = database.transaction(STORE_NAME, 'readwrite');
        var store = tx.objectStore(STORE_NAME);
        var record = {
          url: url,
          method: method,
          headers: headers,
          body: body,
          timestamp: Date.now()
        };
        var req = store.add(record);
        req.onsuccess = function() {
          emit('bs:offline-queue-change', { action: 'add' });
          resolve(req.result);
        };
        req.onerror = function(e) { reject(e.target.error); };
      });
    });
  }

  function getAllFromQueue() {
    return openDB().then(function(database) {
      return new Promise(function(resolve, reject) {
        var tx = database.transaction(STORE_NAME, 'readonly');
        var store = tx.objectStore(STORE_NAME);
        var req = store.getAll();
        req.onsuccess = function() { resolve(req.result); };
        req.onerror = function(e) { reject(e.target.error); };
      });
    });
  }

  function removeFromQueue(id) {
    return openDB().then(function(database) {
      return new Promise(function(resolve, reject) {
        var tx = database.transaction(STORE_NAME, 'readwrite');
        var store = tx.objectStore(STORE_NAME);
        var req = store.delete(id);
        req.onsuccess = function() {
          emit('bs:offline-queue-change', { action: 'remove' });
          resolve();
        };
        req.onerror = function(e) { reject(e.target.error); };
      });
    });
  }

  function clearQueue() {
    return openDB().then(function(database) {
      return new Promise(function(resolve, reject) {
        var tx = database.transaction(STORE_NAME, 'readwrite');
        var store = tx.objectStore(STORE_NAME);
        var req = store.clear();
        req.onsuccess = function() {
          emit('bs:offline-queue-change', { action: 'clear' });
          resolve();
        };
        req.onerror = function(e) { reject(e.target.error); };
      });
    });
  }

  function replayQueue() {
    // Share this lock with the service worker so a queued write is not sent twice.
    if (navigator.locks) return navigator.locks.request('bookstark-offline-replay', replayQueueUnlocked);
    if (!replayQueue.pending) {
      replayQueue.pending = replayQueueUnlocked().finally(function() { replayQueue.pending = null; });
    }
    return replayQueue.pending;
  }

  function replayQueueUnlocked() {
    emit('bs:offline-queue-sync-start');
    return getAllFromQueue().then(function(records) {
      if (!records || records.length === 0) return { success: 0, failed: 0 };
      var success = 0;
      var failed = 0;
      return records.reduce(function(chain, record) {
        return chain.then(function() {
          var opts = {
            method: record.method,
            headers: new Headers(record.headers || {}),
            credentials: 'same-origin'
          };
          if (record.body) {
            opts.body = record.body;
          }
          // The original record already exists. Do not enqueue another copy if
          // the service worker encounters a network failure during this replay.
          opts.headers.set('X-BookStark-Offline-Policy', 'reject');
          return fetchWithCurrentCSRF(record.url, opts).then(function(res) {
            if (res.ok) {
              return removeFromQueue(record.id).then(function() {
                success++;
                notifySWMutationSuccess(record.url, record.method);
              });
            } else if (res.status === 408 || res.status === 429 || res.status >= 500) {
              // Retry transient server/rate-limit failures later.
              return;
            } else {
              if (res.status === 401) return;
              if (res.status === 403) {
                return res.clone().json().catch(function() { return {}; }).then(function(body) {
                  if (body.csrf_error === true) return;
                  return removeFromQueue(record.id).then(function() { failed++; });
                });
              }
              // Permanent client error — remove from queue to avoid infinite retry.
              return removeFromQueue(record.id).then(function() { failed++; });
            }
          }).catch(function() {
            // Network error — keep in queue for next attempt
          });
        });
      }, Promise.resolve()).then(function() {
        return { success: success, failed: failed };
      });
    }).then(function(result) {
      emit('bs:offline-queue-sync-end', result);
      return result;
    }, function(err) {
      emit('bs:offline-queue-sync-end', { error: true });
      throw err;
    });
  }

  function getQueueCount() {
    return getAllFromQueue().then(function(records) {
      return records ? records.length : 0;
    });
  }

  function registerSync() {
    if ('serviceWorker' in navigator && 'SyncManager' in window) {
      return navigator.serviceWorker.ready.then(function(reg) {
        return reg.sync.register('offline-queue');
      }).catch(function() {
        // Sync registration failed, will retry on next SW activation
      });
    }
    return Promise.resolve();
  }

  function notifySWCacheInvalidation() {
    if (navigator.serviceWorker && navigator.serviceWorker.controller) {
      navigator.serviceWorker.controller.postMessage({ type: 'CLEAR_API_CACHE' });
    }
  }

  function notifySWMutationSuccess(url, method) {
    if (navigator.serviceWorker && navigator.serviceWorker.controller) {
      navigator.serviceWorker.controller.postMessage({ type: 'API_MUTATION_SUCCESS', url: url, method: method });
    }
  }

  // Show offline toast
  function showOfflineToast(message) {
    if (typeof BSDialog !== 'undefined' && BSDialog.toast) {
      BSDialog.toast(message, 'warning', 4000);
    }
  }

  // Expose for SW and csrfFetch
  window.BSOfflineQueue = {
    addToQueue: addToQueue,
    getAllFromQueue: getAllFromQueue,
    replayQueue: replayQueue,
    getQueueCount: getQueueCount,
    registerSync: registerSync,
    showOfflineToast: showOfflineToast,
    notifySWCacheInvalidation: notifySWCacheInvalidation,
    notifySWMutationSuccess: notifySWMutationSuccess
  };

  // Auto-replay on online event (with delay for network stabilization)
  window.addEventListener('online', function() {
    setTimeout(function() {
      replayQueue().then(function(result) {
        var msgs = [];
        if (result.success > 0) msgs.push(result.success + ' 条操作已同步');
        if (result.failed > 0) msgs.push(result.failed + ' 条操作失败');
        if (msgs.length > 0) showOfflineToast(msgs.join('，'));
      }).catch(function() {});
    }, 1500);
  });

  // Replay any queued requests on page load (in case we came back online)
  if (navigator.onLine) {
    replayQueue().then(function(result) {
      if (result.success > 0) {
        showOfflineToast(result.success + ' 条离线操作已同步');
      }
    }).catch(function() {});
  }
})();
