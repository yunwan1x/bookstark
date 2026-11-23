/* Shared browser/native capability boundary. Browser pages retain native Web APIs. */
(function () {
  'use strict';
  const android = window.BookStarkNative;
  const raw = window.chrome?.webview || window.webkit?.messageHandlers?.external;
  const native = window === window.top && (!!android?.request || typeof raw?.postMessage === 'function');
  const pending = new Map(), guards = new Set(), activeExports = new Set();
  let serial = 0, leaving = null, leaveApproved = false, enabled = !!android?.request;
  const label = (zh, en) => document.documentElement.lang.startsWith('zh') ? zh : en;
  const fail = error => { if (window.BSDialog) BSDialog.toast(error.message || String(error), 'error'); else console.error(error); };
  function request(action, args, timeout = 10 * 60 * 1000) {
    if (!native) return Promise.reject(new Error('Native capability unavailable'));
    const id = Date.now().toString(36) + '_' + Math.random().toString(36).slice(2) + '_' + (++serial);
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => { pending.delete(id); reject(new Error(label('客户端操作超时，请重试', 'Native operation timed out. Please retry.'))); }, timeout);
      pending.set(id, {resolve, reject, timer});
      const payload = JSON.stringify({id, action, args: args || {}});
      try { if (android?.request) android.request(payload); else raw.postMessage('bookstark:request:' + payload); }
      catch (error) { clearTimeout(timer); pending.delete(id); reject(error); }
    });
  }
  window.BookStarkHostReply = (id, result, error) => {
    const job = pending.get(id); if (!job) return;
    pending.delete(id); clearTimeout(job.timer);
    if (error) job.reject(new Error(error)); else job.resolve(result);
  };
  const ready = android?.request ? Promise.resolve(true) : native ? request('capabilities', {}, 1500).then(value => value?.version === 1, () => false) : Promise.resolve(false);
  ready.then(value => { enabled = value; });
  async function confirmLeave() {
    const message = window.__ ? __('tools.discard') : label('内容尚未保存。确定丢弃并离开吗？', 'Changes are not saved. Discard them and leave?');
    return window.BSDialog ? BSDialog.confirm2(message) : window.confirm(message);
  }
  async function beforeLeave() {
    if (leaving) return leaving;
    leaveApproved = false;
    leaving = (async () => {
      await Promise.allSettled(Array.from(activeExports));
      for (const guard of guards) {
        try { if (await guard() === false) return await confirmLeave(); }
        catch (_) { return await confirmLeave(); }
      }
      return true;
    })().then(ok => { leaveApproved = !!ok; if (ok) setTimeout(() => { leaveApproved = false; }, 1500); return ok; }).finally(() => { leaving = null; });
    return leaving;
  }
  async function navigate(action) { if (await beforeLeave()) action(); }
  window.BookStarkBeforeLeave = beforeLeave;
  window.BookStarkNativeGuards = {add: guard => { guards.add(guard); return () => guards.delete(guard); }};
  async function copyText(text) {
    const value = String(text ?? '');
    if (native && await ready) return request('clipboard-write', {text: value});
    if (browserCopy) {
      try { await browserCopy(value); return true; } catch (_) { /* Fall back for denied Web API permissions. */ }
    }
    const active = document.activeElement, selection = document.getSelection();
    const ranges = selection ? Array.from({length: selection.rangeCount}, (_, i) => selection.getRangeAt(i).cloneRange()) : [];
    const node = document.createElement('textarea'); node.value = value; node.style.cssText = 'position:fixed;left:-9999px;top:0';
    document.body.append(node); node.select();
    let copied = false;
    try { copied = document.execCommand('copy'); }
    finally { node.remove(); if (active?.focus) active.focus(); if (selection) { selection.removeAllRanges(); ranges.forEach(range => selection.addRange(range)); } }
    if (!copied) throw new Error(label('复制失败，请手动复制', 'Copy failed. Please copy manually.'));
    return true;
  }
  const browserCopy = navigator.clipboard?.writeText?.bind(navigator.clipboard);
  window.BookStarkCopyText = copyText;
  // Existing page handlers all receive the same acknowledged/fallback copy path.
  function installClipboard(target) {
    try {
      const clipboard = target.clipboard || {};
      Object.defineProperty(clipboard, 'writeText', {configurable: true, value: copyText});
      if (!target.clipboard) Object.defineProperty(target, 'clipboard', {configurable: true, value: clipboard});
    } catch (_) { /* Explicit BookStarkCopyText callers still work on sealed engines. */ }
  }
  installClipboard(navigator);
  function saveBlob(blob, name, kind) {
    const task = streamBlob(blob, name, kind); activeExports.add(task);
    task.then(() => activeExports.delete(task), () => activeExports.delete(task));
    return task;
  }
  async function streamBlob(blob, name, kind) {
    if (blob.size > 100 * 1024 * 1024) throw new Error(label('导出文件超过 100 MB', 'Export exceeds 100 MB'));
    const token = await request('save-begin', {name: name || 'BookStark', mime: blob.type || 'application/octet-stream', kind: kind || 'save'});
    try {
      for (let offset = 0; offset < blob.size; offset += 96 * 1024) {
        const bytes = new Uint8Array(await blob.slice(offset, offset + 96 * 1024).arrayBuffer());
        let binary = ''; for (let start = 0; start < bytes.length; start += 8192) binary += String.fromCharCode.apply(null, bytes.subarray(start, start + 8192));
        await request('save-chunk', {token, data: btoa(binary)});
      }
      return await request('save-finish', {token});
    } catch (error) { request('save-cancel', {token}).catch(() => {}); throw error; }
  }
  async function downloadURL(url, name) {
    const response = await fetch(url, {credentials: 'same-origin'});
    if (!response.ok) throw new Error(label('下载失败', 'Download failed') + ': HTTP ' + response.status);
    if (!name) {
      const disposition = response.headers.get('Content-Disposition') || '';
      const encoded = disposition.match(/filename\*=UTF-8''([^;]+)/i), plain = disposition.match(/filename="?([^";]+)"?/i);
      try { name = encoded ? decodeURIComponent(encoded[1]) : plain ? plain[1] : new URL(url, location.href).pathname.split('/').pop(); } catch (_) {}
    }
    return saveBlob(await response.blob(), name);
  }
  function printable(doc) {
    const clone = doc.documentElement.cloneNode(true);
    const canvases = doc.querySelectorAll('canvas');
    clone.querySelectorAll('canvas').forEach((node, index) => {
      try { const image = doc.createElement('img'); image.src = canvases[index].toDataURL(); image.style.cssText = node.style.cssText; image.width = canvases[index].width; image.height = canvases[index].height; node.replaceWith(image); } catch (_) { node.remove(); }
    });
    clone.querySelectorAll('script, iframe, object, embed, video, audio, meta[http-equiv="refresh"]').forEach(node => node.remove());
    const base = doc.createElement('base'); base.href = doc.baseURI; clone.querySelector('head')?.prepend(base);
    return '<!doctype html>' + clone.outerHTML;
  }
  async function printDocument(doc) { return saveBlob(new Blob([printable(doc)], {type: 'text/html'}), doc.title || 'BookStark', 'print'); }
  window.BookStarkHost = {get available() { return enabled; }, get isLeaving() { return leaveApproved; }, request, navigate, saveBlob, downloadURL: (url, name) => downloadURL(url,name).catch(fail), printDocument};
  function activate() {
  const docs = new WeakSet();
  function connect(doc) {
    if (!doc || docs.has(doc)) return;
    docs.add(doc);
    try {
      doc.defaultView.print = () => printDocument(doc).catch(fail);
      installClipboard(doc.defaultView.navigator);
      if (doc !== document) {
        const originalOpen = doc.defaultView.open;
        doc.defaultView.open = function(url, target) {
          if ((!url || url === 'about:blank') && !['_self','_top','_parent'].includes(String(target || '').toLowerCase())) return window.BookStarkNativeBlankWindow();
          if (url && !['_self','_top','_parent'].includes(String(target || '').toLowerCase()) && window.BookStarkOpenNativeURL?.(new URL(url, doc.baseURI).href)) return null;
          return originalOpen.apply(doc.defaultView, arguments);
        };
        const handled = new WeakSet();
        doc.addEventListener('click', event => {
          const link = event.target.closest?.('a[href]'); if (!link || handled.has(link)) return;
          handled.add(link); link.addEventListener('click', click => {
            if (click.defaultPrevented || link.hasAttribute('download')) return;
            const url = new URL(link.href, doc.baseURI);
            if (url.origin === location.origin && !link.target) return;
            if (window.BookStarkOpenNativeURL?.(url.href)) click.preventDefault();
          });
        }, true);
      }
    } catch (_) {}
    doc.addEventListener('click', event => {
      const link = event.target.closest?.('a[download]');
      if (!link || event.defaultPrevented) return;
      // Blob/data downloads need a real native file destination, including in editor iframes.
      if (!/^(blob:|data:)/.test(link.href)) return;
      event.preventDefault(); downloadURL(link.href, link.download).catch(fail);
    }, true);
    const connected = new WeakSet();
    function frames() { doc.querySelectorAll('iframe').forEach(frame => {
      const attach = () => { try { connect(frame.contentDocument); } catch (_) {} };
      if (!connected.has(frame)) { connected.add(frame); frame.addEventListener('load', attach); }
      attach();
    }); }
    new MutationObserver(frames).observe(doc, {childList: true, subtree: true}); frames();
  }
  connect(document);
  const links = new WeakSet();
  document.addEventListener('click', event => {
    const link = event.target.closest?.('a[href]'); if (!link || links.has(link)) return;
    links.add(link); link.addEventListener('click', click => {
      if (click.defaultPrevented || click.button !== 0 || link.hasAttribute('download')) return;
      const url = new URL(link.href, location.href);
      if (url.origin !== location.origin || url.pathname === location.pathname && url.search === location.search && url.hash) return;
      click.preventDefault(); navigate(() => location.assign(url.href)).catch(fail);
    });
  }, true);
  }
  ready.then(value => { if (value) activate(); });
})();
