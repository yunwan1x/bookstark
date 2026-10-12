(function () {
    'use strict';
    var dialog = document.getElementById('homeAssistant');
    if (!dialog) return;
    var english = (window.__currentLang || document.documentElement.lang || '').indexOf('en') === 0;
    function lt(zh, en) { return english ? en : zh; }
    function el(id) { return document.getElementById('homeAssistant' + id); }
    var session = null, active = null, poll = null;
    var launcher = el('Open'), indicator = launcher.querySelector('.assistant-indicator'), unread = false;
    var status = el('Status'), input = el('Input'), messages = el('Messages'), drafts = el('Drafts');
    function node(tag, text, cls) { var n = document.createElement(tag); n.textContent = text; if (cls) n.className = cls; return n; }
    function setBusy() {
        launcher.dataset.busy = active ? 'true' : 'false';
        indicator.hidden = !active && !unread;
        var busy = !!active || !session || session.busy;
        el('Send').disabled = busy; el('Reset').disabled = busy; el('Refresh').disabled = !!active;
        el('Stop').hidden = !active;
        drafts.querySelectorAll('button').forEach(function (b) { b.disabled = busy; });
        el('ResetConfirm').disabled = busy;
    }
    function safeLink(url, title) {
        // Only server-generated local record links are interactive; model prose
        // remains plain text (no markdown HTML, remote images, or unsafe links).
        if (typeof url !== 'string' || !/^\/(notes\?|books\/|bookmarks\?|topics\?)/.test(url) || /[\\\r\n]/.test(url)) return null;
        var a = node('a', title); a.href = url; a.target = '_blank'; a.rel = 'noopener noreferrer'; return a;
    }
    function messageHeader(role, timestamp, label) {
        var head = node('div', '', 'home-assistant-message-head');
        var avatar = node('span', '', 'home-assistant-avatar');
        var icon = node('i', '', role === 'user' ? 'fa-solid fa-user' : 'fa-solid fa-robot');
        avatar.setAttribute('aria-hidden', 'true'); avatar.appendChild(icon);
        head.append(avatar, label || node('strong', role === 'user' ? lt('你', 'You') : lt('AI 助手', 'AI assistant')));
        // Older messages have no stored timestamp. Do not invent historical times.
        var date = typeof timestamp === 'number' && timestamp > 0 ? new Date(timestamp * 1000) : null;
        if (date && Number.isFinite(date.getTime())) {
            var locale = english ? 'en-GB' : 'zh-CN';
            var options = {hour:'2-digit', minute:'2-digit', hour12:false};
            if (date.toDateString() !== new Date().toDateString()) { options.month = '2-digit'; options.day = '2-digit'; }
            if (date.getFullYear() !== new Date().getFullYear()) options.year = 'numeric';
            var time = node('time', date.toLocaleString(locale, options));
            time.dateTime = date.toISOString(); time.title = date.toLocaleString(locale, {hour12:false});
            head.appendChild(time);
        }
        var copy = node('button', '', 'row-action home-assistant-copy');
        copy.type = 'button'; copy.title = lt('复制消息', 'Copy message'); copy.setAttribute('aria-label', copy.title);
        var glyph = node('i', '', 'fa-regular fa-copy'); glyph.setAttribute('aria-hidden', 'true'); copy.appendChild(glyph);
        copy.onclick = async function () {
            var body = copy.closest('.home-assistant-message').querySelector('.home-assistant-text');
            try {
                await navigator.clipboard.writeText(body.textContent);
                glyph.className = 'fa-solid fa-check'; copy.setAttribute('aria-label', lt('已复制', 'Copied'));
                setTimeout(function () { glyph.className = 'fa-regular fa-copy'; copy.setAttribute('aria-label', copy.title); }, 1500);
            } catch (_) { BSDialog.toast(lt('复制失败，请手动选择文字复制', 'Copy failed. Select the text and copy manually.'), 'error'); }
        };
        head.appendChild(copy);
        return head;
    }
    function render() {
        messages.replaceChildren(); drafts.replaceChildren();
        if (!session) { setBusy(); return; }
        if (!session.messages.length) messages.appendChild(node('p', lt('可以问：最近有哪些待办？帮我总结学习相关的笔记。', 'Try: What are my recent tasks? Summarize my notes about learning.')));
        session.messages.forEach(function (m) {
            var box = node('article', '', 'home-assistant-message'); box.dataset.role = m.role;
            box.appendChild(messageHeader(m.role, m.created_at));
            box.appendChild(node('div', m.content, 'home-assistant-text'));
            if (m.sources && m.sources.length) {
                var links = node('div', '', 'home-assistant-sources');
                links.appendChild(node('span', lt('参考记录：', 'Referenced records:')));
                m.sources.forEach(function (s) { var a = safeLink(s.url, s.title); if (a) links.appendChild(a); });
                box.appendChild(links);
            }
            messages.appendChild(box);
        });
        if (session.drafts.length) drafts.appendChild(node('h3', lt('草稿与执行结果', 'Drafts and results')));
        session.drafts.forEach(function (d) {
            var box = node('article', '', 'home-assistant-draft'); box.dataset.draftId = d.id;
            box.appendChild(node('h3', d.payload.kind === 'note' ? lt('私有笔记 · ', 'Private note · ') + d.payload.title : lt('待办 · ', 'Task · ') + d.payload.due_date));
            box.appendChild(node('div', d.payload.content, 'home-assistant-text'));
            if (d.status === 'pending') {
                box.appendChild(node('p', lt('尚未创建 · 草稿 24 小时内有效', 'Not created · draft expires after 24 hours')));
                var actions = node('div', '', 'home-assistant-controls');
                [['confirm', lt('确认创建', 'Confirm create')], ['cancel', lt('取消草稿', 'Cancel draft')]].forEach(function (action) {
                    var b = node('button', action[1], 'ai-dlg-btn ' + (action[0] === 'confirm' ? 'ai-dlg-btn-go' : 'ai-dlg-btn-cancel'));
                    b.type = 'button'; b.onclick = function () { resolve(d.id, action[0]); }; actions.appendChild(b);
                });
                box.appendChild(actions);
            } else {
                var label = d.status === 'done' ? lt('已创建', 'Created') : d.status === 'expired' ? lt('已过期', 'Expired') : lt('已取消', 'Cancelled');
                box.appendChild(node('p', label));
                if (d.status === 'done') { var link = safeLink(d.url, lt('打开记录 ↗', 'Open record ↗')); if (link) box.appendChild(link); }
            }
            drafts.appendChild(box);
        });
        setBusy();
    }
    async function request(path, body, onEvent) {
        var options = { method: body ? 'POST' : 'GET', cache: 'no-store', credentials: 'same-origin', offlinePolicy: 'reject', signal: active.signal };
        if (body) { options.headers = { 'Content-Type': 'application/json' }; options.body = JSON.stringify(body); }
        if (onEvent) options.headers.Accept = 'text/event-stream';
        var r = await csrfFetch('/api/ai/assistant' + path, options);
        if (r.status === 401) { session = null; render(); throw new Error(lt('登录已失效，请重新登录', 'Session expired. Please sign in again.')); }
        if (onEvent && r.ok && (r.headers.get('Content-Type') || '').indexOf('text/event-stream') === 0) {
            var receipt = await readStream(r, onEvent);
            var committed = await request('');
            if (!committed.session || committed.session.id !== receipt.session_id) throw new Error(lt('会话已更新，请刷新查看结果', 'Conversation changed. Refresh to view the result.'));
            return committed;
        }
        var data; try { data = await r.json(); } catch (_) { throw new Error(lt('服务器未返回有效响应，请稍后刷新助手', 'Invalid server response. Refresh the assistant shortly.')); }
        if (!r.ok || data.code !== 0 || data.offlineQueued) throw new Error(data.message || lt('请求失败，请刷新后重试', 'Request failed. Refresh and retry.'));
        return data;
    }
    async function readStream(response, onEvent) {
        if (!response.body) throw new Error(lt('浏览器不支持流式读取', 'Streaming is not supported by this browser.'));
        var reader = response.body.getReader(), decoder = new TextDecoder('utf-8', {fatal:true});
        var buffer = '', event = '', lines = [], eventSize = 0, total = 0, result = null;
        function invalidStream() { return new Error(lt('流式响应异常或超出限制，请刷新后重试。', 'Invalid or oversized streamed response. Refresh and retry.')); }
        function line(value) {
            if (value.endsWith('\r')) value = value.slice(0, -1);
            if (!value) {
                if (lines.length) {
                    var data = JSON.parse(lines.join('\n'));
                    if (event === 'error') throw new Error(data.message || lt('生成失败，请刷新查看结果', 'Generation failed. Refresh to check the result.'));
                    if (event === 'done') {
                        if (data.code !== 0 || typeof data.session_id !== 'string' || !session || data.session_id !== session.id) throw invalidStream();
                        result = data;
                    } else onEvent(event, data);
                }
                event = ''; lines = []; eventSize = 0;
            } else if (value.indexOf('event:') === 0) event = value.slice(6).trim();
            else if (value.indexOf('data:') === 0) {
                var part = value.slice(5); if (part[0] === ' ') part = part.slice(1);
                eventSize += part.length; if (eventSize > 512 * 1024) throw invalidStream();
                lines.push(part);
            }
        }
        try {
            while (!result) {
                var chunk = await reader.read(); total += chunk.value ? chunk.value.length : 0;
                if (total > 2 * 1024 * 1024) throw invalidStream();
                buffer += chunk.done ? decoder.decode() : decoder.decode(chunk.value, {stream:true});
                var pos;
                while (!result && (pos = buffer.indexOf('\n')) >= 0) { line(buffer.slice(0, pos)); buffer = buffer.slice(pos + 1); }
                if (buffer.length > 512 * 1024) throw invalidStream();
                if (chunk.done) break;
            }
            if (!result) throw new Error(lt('连接中断，回答尚未完成。请刷新查看最终结果，避免重复操作。', 'Connection interrupted; the answer is incomplete. Refresh to check the final result before retrying.'));
            return result;
        } catch (err) {
            if (err.name === 'SyntaxError' || err.name === 'TypeError') throw invalidStream();
            throw err;
        } finally { await reader.cancel().catch(function () {}); reader.releaseLock(); }
    }
    async function run(work, progress) {
        if (active) return;
        clearTimeout(poll); active = new AbortController(); setBusy(); status.textContent = progress; el('Refresh').hidden = true;
        // Also bound the browser wait if a proxy never returns a response.
        var timeout = setTimeout(function () { if (active) active.abort(); }, 160000);
        try { await work(); }
        catch (err) { el('Refresh').hidden = false; status.textContent = err.name === 'AbortError' ? lt('已停止等待。请重新加载查看最终结果，避免重复操作。', 'Stopped waiting. Reload to check the final result before retrying.') : err.message; }
        finally { clearTimeout(timeout); active = null; if (!dialog.open) unread = true; setBusy(); if (session && session.busy && dialog.open) poll = setTimeout(sync, 3000); }
    }
    async function sync() {
        return run(async function () {
            var data = await request(''); session = data.session; render();
            status.textContent = session.busy ? lt('会话正在处理中，稍后自动刷新…', 'Conversation is busy. Refreshing shortly…') : '';
        }, lt('正在加载会话…', 'Loading conversation…'));
    }
    async function resolve(id, action) {
        if (!session || session.busy) return;
        return run(async function () {
            var data = await request('/drafts/' + encodeURIComponent(id), { session_id: session.id, action: action });
            session.drafts = session.drafts.map(function (d) { return d.id === id ? data.draft : d; }); render();
            status.textContent = data.draft.status === 'done' ? lt('创建成功', 'Created successfully') : lt('草稿已取消', 'Draft cancelled');
            if (data.draft.status === 'done') window.dispatchEvent(new Event('bookstark:assistant-created'));
        }, lt('正在处理…', 'Processing…'));
    }
    el('Open').onclick = function () {
        if (dragged) { dragged = false; return; }
        if (dialog.open) { dialog.close(); return; }
        unread = false; if (innerWidth <= 640) dialog.showModal(); else dialog.show(); launcher.setAttribute('aria-expanded', 'true'); setBusy();
        if (!active) sync();
        input.focus();
    };
    el('Close').onclick = function () { dialog.close(); };
    dialog.addEventListener('close', function () { clearTimeout(poll); launcher.setAttribute('aria-expanded', 'false'); el('ResetCheck').hidden = true; el('Open').focus(); });
    dialog.addEventListener('keydown', function (e) { if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); dialog.close(); } });
    // Drag the launcher to either edge; persist geometry only, never conversation data.
    var dragged = false, pointer = null, position = null;
    try { position = JSON.parse(localStorage.getItem('bookstark-assistant-position')); } catch (_) {}
    function place() {
        if (!position || !Number.isFinite(position.y)) return;
        var y = Math.max(12, Math.min(innerHeight - 72, position.y * innerHeight));
        launcher.style.top = y + 'px'; launcher.style.bottom = 'auto';
        launcher.style.left = position.side === 'left' ? '12px' : 'auto';
        launcher.style.right = position.side === 'left' ? 'auto' : '12px';
    }
    place(); window.addEventListener('resize', place);
    launcher.addEventListener('pointerdown', function (e) {
        if (e.button !== 0) return;
        dragged = false; pointer = {id:e.pointerId,x:e.clientX,y:e.clientY}; launcher.setPointerCapture(e.pointerId);
    });
    launcher.addEventListener('pointermove', function (e) {
        if (!pointer || e.pointerId !== pointer.id) return;
        if (Math.hypot(e.clientX-pointer.x,e.clientY-pointer.y)>8) dragged = true;
        if (dragged) { position = {side:e.clientX<innerWidth/2?'left':'right',y:(e.clientY-26)/innerHeight}; place(); }
    });
    function endDrag() { if (pointer && dragged) { try { localStorage.setItem('bookstark-assistant-position',JSON.stringify(position)); } catch (_) {} } pointer = null; }
    launcher.addEventListener('pointerup', endDrag); launcher.addEventListener('pointercancel', endDrag);
    el('Refresh').onclick = sync;
    el('Info').onclick = function () { var info = el('Disclosure'); info.hidden = !info.hidden; el('Info').setAttribute('aria-expanded', String(!info.hidden)); };
    el('Stop').onclick = function () { if (active) active.abort(); };
    el('Reset').onclick = function () { el('ResetCheck').hidden = false; };
    el('ResetCancel').onclick = function () { el('ResetCheck').hidden = true; };
    el('ResetConfirm').onclick = function () {
        if (!session) return;
        run(async function () { var data = await request('/reset', { session_id: session.id }); session = data.session; render(); el('ResetCheck').hidden = true; status.textContent = ''; }, lt('正在新建会话…', 'Starting a new conversation…'));
    };
    el('Form').onsubmit = function (e) {
        e.preventDefault(); var text = input.value.trim();
        if (!text || !session || session.busy || active) return;
        run(async function () {
            render();
            var question = node('article', '', 'home-assistant-message'); question.dataset.role = 'user';
            question.appendChild(messageHeader('user', Date.now() / 1000)); question.appendChild(node('div', text, 'home-assistant-text')); messages.appendChild(question);
            var partial = node('article', '', 'home-assistant-message'), label = node('strong', lt('AI 助手 · 生成中，尚未完成', 'AI assistant · Generating, not complete'));
            partial.dataset.role = 'assistant'; partial.dataset.streaming = 'true'; var output = node('div', '', 'home-assistant-text'); partial.append(messageHeader('assistant', Date.now() / 1000, label), output); messages.appendChild(partial);
            try {
                var data = await request('/chat', { session_id: session.id, message: text }, function (event, data) {
                    var scroll = el('Scroll'), follow = scroll.scrollHeight - scroll.scrollTop - scroll.clientHeight < 100;
                    if (event === 'round') { output.textContent = ''; status.textContent = lt('正在生成回答…', 'Generating a response…'); }
                    if (event === 'delta' && typeof data.text === 'string') {
                        if (output.textContent.length + data.text.length > 24000) throw new Error(lt('回答超出长度限制，请缩小问题范围', 'Answer too long. Narrow the request.'));
                        output.appendChild(document.createTextNode(data.text));
                    }
                    if (event === 'progress') {
                        var steps = {search:lt('正在检索资料…', 'Searching records…'), read:lt('正在读取资料…', 'Reading records…'), draft_note:lt('正在准备笔记草稿…', 'Preparing a note draft…'), draft_task:lt('正在准备待办草稿…', 'Preparing a task draft…')};
                        status.textContent = steps[data.tool] || lt('正在校验工具请求…', 'Validating tool request…');
                    }
                    if (follow) scroll.scrollTop = scroll.scrollHeight;
                });
                session = data.session; render();
            } catch (err) {
                label.textContent = lt('AI 助手 · 未完成（不作为执行结果）', 'AI assistant · Incomplete (not an execution result)');
                partial.dataset.streaming = 'incomplete'; throw err;
            }
            if (input.value.trim() === text) input.value = '';
            status.textContent = ''; el('Scroll').scrollTop = el('Scroll').scrollHeight; if (dialog.open) input.focus();
        }, lt('正在检索和思考，复杂问题可能需要一两分钟…', 'Searching and thinking. Complex requests may take a minute or two…'));
    };
    input.addEventListener('keydown', function (e) { if (e.key === 'Enter' && (e.ctrlKey || e.metaKey) && !e.isComposing) { e.preventDefault(); el('Form').requestSubmit(); } });
    window.addEventListener('pagehide', function () { if (active) active.abort(); clearTimeout(poll); if (dialog.open) dialog.close(); session = null; input.value = ''; render(); });
    setBusy();
})();
