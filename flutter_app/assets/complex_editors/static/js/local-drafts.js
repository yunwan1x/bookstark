/* Browser-only draft store. Metadata is separate so the sidebar never loads images/content. */
(function () {
  'use strict';
  const types = ['markdown', 'richdoc', 'spreadsheet', 'drawing', 'mindmap', 'presentation'];
  let connection;
  const channel = typeof BroadcastChannel === 'function' ? new BroadcastChannel('bookstark-local-drafts') : null;
  function announce() { window.dispatchEvent(new Event('local-drafts-changed')); if (channel) channel.postMessage('changed'); }
  if (channel) channel.onmessage = () => window.dispatchEvent(new Event('local-drafts-changed'));
  function open() {
    if (connection) return connection;
    connection = new Promise((resolve, reject) => {
      const request = indexedDB.open('bookstark-local-tools', 1);
      request.onupgradeneeded = () => {
        const db = request.result;
        db.createObjectStore('drafts', { keyPath: 'id' }).createIndex('updated', 'updated');
        db.createObjectStore('contents', { keyPath: 'id' });
      };
      request.onerror = () => { connection = null; reject(request.error); };
      request.onblocked = () => { connection = null; reject(new Error('Storage blocked')); };
      request.onsuccess = () => { const db = request.result; db.onversionchange = () => { db.close(); connection = null; }; resolve(db); };
    });
    return connection;
  }
  async function list(limit) {
    const db = await open();
    return new Promise((resolve, reject) => {
      const tx = db.transaction('drafts'); const rows = [];
      const request = tx.objectStore('drafts').index('updated').openCursor(null, 'prev');
      request.onsuccess = () => { const c = request.result; if (c && (!limit || rows.length < limit)) { rows.push(c.value); c.continue(); } };
      tx.oncomplete = () => resolve(rows); tx.onabort = () => reject(tx.error);
    });
  }
  async function get(id) {
    const db = await open();
    return new Promise((resolve, reject) => {
      const tx = db.transaction(['drafts', 'contents']);
      const meta = tx.objectStore('drafts').get(id), content = tx.objectStore('contents').get(id);
      tx.oncomplete = () => resolve(meta.result && content.result ? Object.assign({}, meta.result, { content: content.result.content }) : null);
      tx.onabort = () => reject(tx.error);
    });
  }
  async function save(draft, expectedRevision) {
    if (!types.includes(draft.type) || typeof draft.content !== 'string') throw new Error('Invalid draft');
    const db = await open();
    return new Promise((resolve, reject) => {
      const tx = db.transaction(['drafts', 'contents'], 'readwrite');
      let conflict = false, result;
      const store = tx.objectStore('drafts');
      const request = store.get(draft.id);
      request.onsuccess = () => {
        const old = request.result;
        if ((old ? old.revision : 0) !== expectedRevision) { conflict = true; tx.abort(); return; }
        result = { id: draft.id, title: draft.title.slice(0,120), type: draft.type, updated: Date.now(), revision: expectedRevision + 1, bytes: new Blob([draft.content]).size };
        store.put(result); tx.objectStore('contents').put({ id: draft.id, content: draft.content });
      };
      tx.oncomplete = () => { announce(); resolve(result); };
      tx.onabort = () => reject(conflict ? Object.assign(new Error('Draft conflict'), { code: 'conflict' }) : tx.error || new Error('Save failed'));
    });
  }
  async function remove(id, expectedRevision) {
    const db = await open();
    return new Promise((resolve,reject) => {
      const tx = db.transaction(['drafts','contents'], 'readwrite'); let conflict = false;
      const request = tx.objectStore('drafts').get(id);
      request.onsuccess = () => {
        if (!request.result || request.result.revision !== expectedRevision) { conflict = true; tx.abort(); return; }
        tx.objectStore('drafts').delete(id); tx.objectStore('contents').delete(id);
      };
      tx.oncomplete = () => { announce(); resolve(); };
      tx.onabort = () => reject(conflict ? Object.assign(new Error('Draft conflict'), { code:'conflict' }) : tx.error);
    });
  }
  window.BookStarkLocalDrafts = { types, list, get, save, remove };
})();
