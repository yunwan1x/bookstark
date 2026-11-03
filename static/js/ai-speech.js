/* Shared, opt-in speech for completed AI answers. No audio persistence. */
(function (global) {
  'use strict';
  if (global.AISpeech) return;
  var owners = new WeakMap(), active = null;
  var MAX_AUDIO = 1024 * 1024, MAX_TEXT = 20000;
  var VOICES = [ ['zh-CN-YunxiNeural', '云希', 'Yunxi'], ['zh-CN-XiaoxiaoNeural', '晓晓', 'Xiaoxiao'], ['en-US-AriaNeural', 'Aria', 'Aria'], ['en-US-GuyNeural', 'Guy', 'Guy'] ];
  function tr(zh, en) { return String(global.__currentLang || document.documentElement.lang || 'zh').indexOf('en') === 0 ? en : zh; }
  function label(el, text) { el.setAttribute('aria-label', text); el.title = text; }
  function clean(raw) {
    var text = String(raw || '').replace(/```[^\n]*\n[\s\S]*?(?:```|$)/g, '').replace(/~~~[^\n]*\n[\s\S]*?(?:~~~|$)/g, '');
    text = text.replace(/!\[[^\]]*\]\([^)]*\)/g, '').replace(/\[([^\]]+)\]\([^)]*\)/g, '$1').replace(/^\s*\[[^\]]+\]:\s*\S+.*$/gm, '');
    var template = document.createElement('template');
    template.innerHTML = text.replace(/<br\s*\/?\s*>/gi, '\n').replace(/<\/(?:p|div|li|h[1-6]|tr)>/gi, '$&\n');
    template.content.querySelectorAll('script,style,pre,code,svg,math,iframe,noscript').forEach(function (el) { el.remove(); });
    text = template.content.textContent.replace(/https?:\/\/[A-Za-z0-9\-._~:/?#[\]@!$&'()*+,;=%]+/g, '');
    text = text.replace(/^\s{0,3}(?:#{1,6}\s+|>\s*|[-*+]\s+|\d+[.)、]\s+)/gm, '').replace(/^[\s|:\-]+$/gm, '').replace(/[*_`~]/g, '').replace(/\|/g, '，').replace(/[ \t]+/g, ' ').replace(/\n{3,}/g, '\n\n').trim();
    if (/^[\[{]/.test(text)) { try { JSON.parse(text); return ''; } catch (_) {} }
    return text;
  }
  function split(text) {
    var chars = Array.from(text); if (chars.length > MAX_TEXT) throw Error(tr('回复过长，请分段选择朗读（最多两万字）', 'Answer too long; read a shorter selection (20,000 characters maximum)'));
    var chunks = [], rest = chars;
    while (rest.length) {
      var size = Math.min(200, rest.length);
      if (rest.length > 200) { for (var i = size; i >= 80; i--) { if (/[。！？.!?；;\n\s]/.test(rest[i - 1])) { size = i; break; } } }
      var part = rest.slice(0, size).join('').trim(); if (part) chunks.push(part); rest = rest.slice(size);
    }
    return chunks;
  }
  function preference(key, fallback) { try { return localStorage.getItem('bookstark-tts-' + key) || fallback; } catch (_) { return fallback; } }
  function savePreference(key, value) { try { localStorage.setItem('bookstark-tts-' + key, value); } catch (_) {} }
  function paint(owner) {
    var current = active && active.owner === owner ? active : null;
    owner.container.classList.toggle('ai-speech-active', !!current);
    label(owner.play, current ? (current.paused ? tr('继续朗读', 'Resume reading') : tr('暂停朗读', 'Pause reading')) : tr('朗读回复', 'Read answer'));
    owner.play.innerHTML = '<i aria-hidden="true" class="fa-solid ' + (current ? (current.paused ? 'fa-play' : 'fa-pause') : 'fa-volume-high') + '"></i>';
    owner.stop.hidden = !current;
    owner.voice.disabled = !!current;
    owner.progress.textContent = current ? (current.paused ? tr('已暂停', 'Paused') : current.loading ? tr('正在合成…', 'Preparing…') : tr('朗读中', 'Reading')) + ' ' + (current.index + 1) + '/' + current.chunks.length : '';
  }
  function clearHighlight(owner) { owner.container.querySelectorAll('.ai-speech-reading').forEach(function (el) { el.classList.remove('ai-speech-reading'); }); }
  function highlight(owner, text) {
    clearHighlight(owner); var needle = text.replace(/\s/g, '').slice(0, 18);
    owner.container.querySelectorAll('p,li,blockquote,h1,h2,h3,h4,td').forEach(function (el) {
      if (owner.bar.contains(el)) return;
      var value = el.textContent.replace(/\s/g, '');
      if (needle && (value.indexOf(needle) >= 0 || value.length > 8 && text.replace(/\s/g, '').indexOf(value) >= 0)) el.classList.add('ai-speech-reading');
    });
  }
  function stopWithin(root) { if (active && (!root || root === active.owner.container || root.contains(active.owner.container))) stop(); }
  function stop() {
    var state = active; if (!state) return; active = null;
    state.controller.abort(); if (state.observer) state.observer.disconnect(); if (state.resume) state.resume();
    state.audio.pause(); state.audio.removeAttribute('src'); state.audio.load();
    if (state.url) { URL.revokeObjectURL(state.url); state.url = null; }
    clearHighlight(state.owner); paint(state.owner);
  }
  async function fetchSegment(state, text, onPart) {
    var response = await (global.csrfFetch || global.fetch)('/api/ai/tts/stream', {method: 'POST', credentials: 'same-origin', cache: 'no-store', signal: state.controller.signal, headers: {'Content-Type': 'application/json', 'X-BookStark-Offline-Policy': 'reject'}, body: JSON.stringify({text: text, voice: state.owner.voice.value})});
    if (!response.ok || !response.headers.get('Content-Type') || response.headers.get('Content-Type').indexOf('application/x-ndjson') !== 0) {
      throw Error(response.status === 401 ? tr('登录已失效，请重新登录', 'Session expired. Please sign in again') : response.status === 429 ? tr('朗读请求较多，请稍后再试', 'Too many speech requests. Please retry shortly') : tr('语音合成失败，请稍后重试', 'Speech synthesis failed. Please retry'));
    }
    var reader = response.body.getReader(), decoder = new TextDecoder(), pending = '', bytes = 0, parts = [], complete = false;
    function frame(line) {
      if (!line.trim()) return; if (complete) throw Error('Invalid speech stream');
      var msg = JSON.parse(line);
      if (msg.event === 'error') throw Error(tr('语音连接中断，请重新朗读', 'Speech connection interrupted. Please retry'));
      if (msg.event === 'done') { if (!bytes || msg.bytes !== bytes) throw Error('Incomplete speech stream'); complete = true; return; }
      if (msg.event !== 'audio' || typeof msg.data !== 'string' || msg.data.length > 24000) throw Error('Invalid speech stream');
      var raw = atob(msg.data); bytes += raw.length; if (bytes > MAX_AUDIO) throw Error('Audio too large');
      var part = new Uint8Array(raw.length); for (var i = 0; i < raw.length; i++) part[i] = raw.charCodeAt(i); if (onPart) onPart(part); else parts.push(part);
    }
    try {
      while (true) {
        var chunk = await reader.read(); pending += decoder.decode(chunk.value || new Uint8Array(), {stream: !chunk.done});
        if (pending.length > 100000) throw Error('Invalid speech stream');
        var end; while ((end = pending.indexOf('\n')) >= 0) { frame(pending.slice(0, end)); pending = pending.slice(end + 1); }
        if (chunk.done) break;
      }
      if (pending.trim()) frame(pending); if (!complete) throw Error(tr('音频不完整，请重新朗读', 'Incomplete audio. Please retry'));
      return new Blob(parts, {type: 'audio/mpeg'});
    } finally { await reader.cancel().catch(function () {}); reader.releaseLock(); }
  }
  function prepared(state, text) { return fetchSegment(state, text).then(function (blob) { return {blob: blob}; }, function (error) { return {error: error}; }); }
  async function waitIfPaused(state) { if (state.paused) await new Promise(function (resolve) { state.resume = resolve; }); state.resume = null; }
  async function playBlob(state, blob) {
    await waitIfPaused(state); if (active !== state) return;
    state.url = typeof blob === 'string' ? blob : URL.createObjectURL(blob); state.audio.src = state.url; state.loading = false; highlight(state.owner, state.chunks[state.index]); paint(state.owner);
    try {
      await new Promise(function (resolve, reject) {
        function cleanup() { state.audio.onended = state.audio.onerror = null; state.controller.signal.removeEventListener('abort', aborted); }
        function aborted() { cleanup(); reject(new DOMException('Stopped', 'AbortError')); }
        state.audio.onended = function () { cleanup(); resolve(); };
        state.audio.onerror = function () { cleanup(); reject(Error(tr('音频播放失败，请重试', 'Audio playback failed. Please retry'))); };
        state.controller.signal.addEventListener('abort', aborted, {once: true});
        state.audio.play().catch(function (err) {
          if (err.name === 'NotAllowedError') { state.paused = true; paint(state.owner); }
          else { cleanup(); reject(err); }
        });
      });
    } finally { if (state.url) URL.revokeObjectURL(state.url); state.url = null; }
  }
  function canStream() {
    return global.MediaSource && MediaSource.isTypeSupported('audio/mpeg');
  }
  async function playStream(state, text) {
    await waitIfPaused(state); if (active !== state) return;
    var media = new MediaSource(), url = URL.createObjectURL(media);
    var rejectStream, buffer, queue = [], finished = false;
    var sourceError = new Promise(function (_, reject) { rejectStream = reject; });
    // Attach rejection handling before starting either network or playback.
    sourceError.catch(function () {});
    function pump() {
      if (!buffer || buffer.updating || media.readyState !== 'open') return;
      try {
        if (queue.length) buffer.appendBuffer(queue.shift());
        else if (finished) media.endOfStream();
      } catch (err) { rejectStream(err); }
    }
    var opened = new Promise(function (resolve, reject) {
      function aborted() { reject(new DOMException('Stopped', 'AbortError')); }
      state.controller.signal.addEventListener('abort', aborted, {once: true});
      media.addEventListener('sourceopen', function () {
        state.controller.signal.removeEventListener('abort', aborted);
        try {
          buffer = media.addSourceBuffer('audio/mpeg');
          buffer.addEventListener('updateend', pump);
          buffer.addEventListener('error', function () { rejectStream(Error(tr('音频播放失败，请重试', 'Audio playback failed. Please retry'))); });
          resolve();
        } catch (err) { reject(err); }
      }, {once: true});
    });
    // playBlob attaches this URL to the audio element so sourceopen can fire.
    var playback = playBlob(state, url);
    try {
      await Promise.race([Promise.all([playback, (async function () {
        await opened;
        await fetchSegment(state, text, function (part) { queue.push(part); pump(); });
        finished = true; pump();
      })()]), sourceError]);
    } finally {
      if (buffer) buffer.removeEventListener('updateend', pump);
      URL.revokeObjectURL(url);
    }
  }
  function toggle(owner) {
    if (active && active.owner === owner) {
      var current = active; current.paused = !current.paused;
      if (current.paused) current.audio.pause();
      else { if (current.resume) current.resume(); if (!current.loading) current.audio.play().catch(function () { current.paused = true; paint(owner); }); }
      paint(owner); return;
    }
    stop(); var chunks;
    try { chunks = split(clean(typeof owner.text === 'function' ? owner.text() : owner.text)); } catch (err) { owner.progress.textContent = err.message; return; }
    if (!chunks.length) { owner.progress.textContent = tr('没有可朗读的正文', 'No readable text'); return; }
    var state = active = {owner: owner, controller: new AbortController(), audio: new Audio(), chunks: chunks, index: 0, paused: false, loading: true, url: null};
    state.audio.preload = 'auto'; state.audio.playbackRate = Number(owner.rate.value);
    // Prime this same audio element within the explicit click gesture (mobile browsers).
    state.audio.src = 'data:audio/wav;base64,UklGRiYAAABXQVZFZm10IBAAAAABAAEARKwAAESsAAABAAgAZGF0YQIAAACAgA==';
    var prime = state.audio.play().then(function () { if (active === state) state.audio.pause(); }).catch(function () {});
    state.observer = new MutationObserver(function () { if (active === state && (!owner.container.isConnected || !owner.container.getClientRects().length)) stop(); });
    state.observer.observe(document.body, {childList: true, subtree: true, attributes: true, attributeFilter: ['hidden', 'open', 'style', 'class']});
    paint(owner);
    (async function () {
      try {
        var streaming = canStream();
        var next = streaming ? null : prepared(state, chunks[0]); await prime;
        for (var i = 0; i < chunks.length && active === state; i++) {
          state.index = i; state.loading = true; paint(owner);
          if (streaming) { await playStream(state, chunks[i]); continue; }
          var result = await next;
          if (active !== state) break; if (result.error) throw result.error;
          if (i + 1 < chunks.length) next = prepared(state, chunks[i + 1]);
          await playBlob(state, result.blob);
        }
      } catch (err) { if (active === state && err.name !== 'AbortError') { stop(); owner.progress.textContent = tr('朗读失败：', 'Reading failed: ') + err.message; } }
      finally { if (active === state) stop(); }
    })();
  }
  function mount(container, text) {
    if (!container) return null;
    var existing = owners.get(container); if (existing) { stopWithin(container); existing.text = text; existing.bar.hidden = !clean(typeof text === 'function' ? text() : text); return existing; }
    var owner = {container: container, text: text}, bar = owner.bar = document.createElement('div'); bar.className = 'ai-speech-controls';
    owner.play = document.createElement('button'); owner.play.type = 'button'; owner.play.className = 'row-action'; owner.play.onclick = function () { toggle(owner); };
    owner.stop = document.createElement('button'); owner.stop.type = 'button'; owner.stop.className = 'row-action'; owner.stop.hidden = true; owner.stop.innerHTML = '<i aria-hidden="true" class="fa-solid fa-stop"></i>'; label(owner.stop, tr('停止朗读', 'Stop reading')); owner.stop.onclick = stop;
    owner.voice = document.createElement('select'); owner.voice.className = 'dialog-input'; label(owner.voice, tr('朗读音色', 'Reading voice'));
    VOICES.forEach(function (voice) { var opt = document.createElement('option'); opt.value = voice[0]; opt.textContent = tr(voice[1], voice[2]); owner.voice.appendChild(opt); });
    var voice = preference('voice', VOICES[0][0]); owner.voice.value = VOICES.some(function (v) { return v[0] === voice; }) ? voice : VOICES[0][0]; owner.voice.onchange = function () { savePreference('voice', owner.voice.value); };
    owner.rate = document.createElement('select'); owner.rate.className = 'dialog-input'; label(owner.rate, tr('朗读速度', 'Reading speed'));
    ['0.75', '1', '1.25', '1.5', '2'].forEach(function (rate) { var opt = document.createElement('option'); opt.value = rate; opt.textContent = rate + '×'; owner.rate.appendChild(opt); }); owner.rate.value = preference('rate', '1'); if (!owner.rate.value) owner.rate.value = '1';
    owner.rate.onchange = function () { savePreference('rate', owner.rate.value); if (active && active.owner === owner) active.audio.playbackRate = Number(owner.rate.value); };
    owner.progress = document.createElement('span'); owner.progress.className = 'ai-speech-progress'; owner.progress.setAttribute('role', 'status');
    bar.append(owner.play, owner.stop, owner.voice, owner.rate, owner.progress); container.appendChild(bar); owners.set(container, owner); paint(owner); bar.hidden = !clean(typeof text === 'function' ? text() : text);
    return owner;
  }
  // Inline editors keep their result controls beside the generation status.
  var results = new WeakMap();
  function result(anchor, text) {
    if (!anchor) return;
    var host = results.get(anchor);
    if (host) { stopWithin(host); host.replaceChildren(); }
    else { host = document.createElement('div'); anchor.after(host); results.set(anchor, host); }
    if (text) mount(host, text);
  }
  global.addEventListener('pagehide', stop);
  global.AISpeech = {mount: mount, result: result, stopWithin: stopWithin, stop: stop, clean: clean, split: split};
})(window);
