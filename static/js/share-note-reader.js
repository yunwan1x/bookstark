/* Shared public-note reader, extracted from the former shares page. */
    var shareNoteStore = {};
    var shareNoteOrder = [];
    var shareNoteViewerCurrentKey = null;
    var shareImageLightboxIndex = null;
    var shareImageLightboxTrapHandler = null;
    var shareImageLightboxPrevFocus = null;
    var shareNoteViewerTrapHandler = null;
    var shareNoteViewerPrevFocus = null;

    function trapPublicReaderFocus(event, id) {
        var items = Array.from(document.getElementById(id).querySelectorAll('button:not(:disabled), a[href], [tabindex="0"]')).filter(function(el) { return el.offsetParent !== null; });
        if (!items.length) return;
        var first = items[0], last = items[items.length - 1];
        if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last.focus(); }
        else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus(); }
    }

    /* ─── Markdown renderer (for notes) ─── */
    if (typeof marked !== 'undefined') {
        marked.setOptions({ breaks: true, gfm: true });
        var _renderer = new marked.Renderer();
        _renderer.code = function(obj) {
            var text = (typeof obj === 'object' && obj !== null) ? obj.text : obj;
            var lang = (typeof obj === 'object' && obj !== null) ? obj.lang : arguments[1];
            var escaped = typeof escHtml === 'function' ? escHtml(text) : String(text).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
            if (lang) {
                var escapedLang = typeof escAttr === 'function' ? escAttr(lang) : String(lang).replace(/"/g,'&quot;');
                return '<div class="code-block" data-lang="'+escapedLang+'">' +
                    '<div class="code-block-header">' +
                    '<span class="code-block-dots"><i></i><i></i><i></i></span>' +
                    '<span class="code-block-lang">' + (typeof escHtml === 'function' ? escHtml(lang) : lang) + '</span>' +
                    '<button class="code-copy-btn" title="' + window.__('share.code.copy') + '" aria-label="' + window.__('share.code.copy') + '"><i class="fa-regular fa-copy"></i></button>' +
                    '</div><pre><code>' + escaped + '</code></pre></div>';
            }
            return '<pre><code>' + escaped + '</code></pre>';
        };
        marked.setOptions({ renderer: _renderer });
    }

    /* ─── Code copy ─── */
    document.addEventListener('click', function(e) {
        var btn = e.target.closest('.sh-note-text .code-copy-btn');
        if (!btn) return;
        var code = btn.closest('.code-block') && btn.closest('.code-block').querySelector('code');
        if (!code) return;
        var icon = btn.querySelector('i');
        var done = function() { if (icon) { icon.className = 'fa-solid fa-check'; setTimeout(function() { icon.className = 'fa-regular fa-copy'; }, 1200); } };
        if (navigator.clipboard && navigator.clipboard.writeText) {
            navigator.clipboard.writeText(code.textContent).then(done).catch(function() { if (typeof toast === 'function') toast(window.__('share.code.copy_error'), 'error'); });
        } else {
            var ta = document.createElement('textarea');
            ta.value = code.textContent; ta.style.cssText = 'position:fixed;opacity:0';
            document.body.appendChild(ta); ta.select();
            try { document.execCommand('copy'); done(); } catch(e) {}
            document.body.removeChild(ta);
        }
    });

    function resetShareNoteStore() {
        shareNoteStore = {};
        shareNoteOrder = [];
    }

    function registerShareNote(noteKey, note) {
        if (!noteKey) return;
        shareNoteStore[noteKey] = note;
        if (shareNoteOrder.indexOf(noteKey) < 0) shareNoteOrder.push(noteKey);
    }

    function copyTextToClipboard(text, successMessage) {
        var done = function() {
            if (window.BSDialog) BSDialog.toast(successMessage || window.__('note.toast.copied'), 'success');
        };
        var fail = function() {
            if (window.BSDialog) BSDialog.toast(window.__('note.code_copy_failed'), 'error');
        };
        if (navigator.clipboard && navigator.clipboard.writeText) {
            navigator.clipboard.writeText(text).then(done).catch(function() {
                var ta = document.createElement('textarea');
                ta.value = text; ta.style.position = 'fixed'; ta.style.left = '-9999px';
                document.body.appendChild(ta); ta.select();
                try { document.execCommand('copy'); done(); } catch(ex) { fail(); }
                document.body.removeChild(ta);
            });
            return;
        }
        var ta = document.createElement('textarea');
        ta.value = text; ta.style.position = 'fixed'; ta.style.left = '-9999px';
        document.body.appendChild(ta); ta.select();
        try { document.execCommand('copy'); done(); } catch(ex) { fail(); }
        document.body.removeChild(ta);
    }

    function copyShareNoteContent(noteKey) {
        var note = shareNoteStore[noteKey];
        if (!note) return;
        copyTextToClipboard(note.content || '');
    }

    function copyShareNoteViewerContent() {
        if (!shareNoteViewerCurrentKey) return;
        copyShareNoteContent(shareNoteViewerCurrentKey);
    }

    function updateShareNoteViewerNav() {
        var idx = shareNoteOrder.indexOf(shareNoteViewerCurrentKey);
        var prevBtn = document.getElementById('shareNoteViewerPrevBtn');
        var nextBtn = document.getElementById('shareNoteViewerNextBtn');
        if (prevBtn) prevBtn.disabled = idx <= 0;
        if (nextBtn) nextBtn.disabled = idx < 0 || idx >= shareNoteOrder.length - 1;
    }

    function setShareNoteViewer(noteKey) {
        var note = shareNoteStore[noteKey];
        var titleEl = document.getElementById('shareNoteViewerTitle');
        var metaEl = document.getElementById('shareNoteViewerMeta');
        var contentEl = document.getElementById('shareNoteViewerContent');
        if (!note || !contentEl) return;
        shareNoteViewerCurrentKey = noteKey;
        if (titleEl) titleEl.textContent = note.title || window.__('share.type.note');
        if (metaEl) {
            var meta = [];
            if (note.author) meta.push(note.author);
            if (note.time) meta.push(fmtDate(note.time) + ' ' + fmtHM(note.time));
            if (note.labels && note.labels.length) meta.push(note.labels.join(' / '));
            metaEl.textContent = meta.join(' · ');
        }
        contentEl.innerHTML = typeof marked !== 'undefined'
            ? sanitizeRenderedHTML(marked.parse(note.content || ''))
            : escHtml(note.content || '');
        contentEl.scrollTop = 0;
        prepareShareNoteImages(contentEl);
        updateShareNoteViewerNav();
    }

    function openShareNoteViewer(noteKey) {
        var overlay = document.getElementById('shareNoteViewerOverlay');
        if (!overlay || !shareNoteStore[noteKey]) return;
        shareNoteViewerPrevFocus = document.activeElement;
        overlay.classList.add('active');
        if (window.BookStarkScrollLock) BookStarkScrollLock.lock('share-note-viewer');
        setShareNoteViewer(noteKey);
        trapShareNoteViewer(true);
    }

    function showAdjacentShareNoteViewer(delta) {
        var idx = shareNoteOrder.indexOf(shareNoteViewerCurrentKey);
        var nextKey = idx >= 0 ? shareNoteOrder[idx + delta] : null;
        if (!nextKey) return;
        setShareNoteViewer(nextKey);
    }

    function closeShareNoteViewer() {
        var overlay = document.getElementById('shareNoteViewerOverlay');
        if (overlay) overlay.classList.remove('active');
        var contentEl = document.getElementById('shareNoteViewerContent');
        if (contentEl) contentEl.innerHTML = '';
        shareNoteViewerCurrentKey = null;
        if (window.BookStarkScrollLock) BookStarkScrollLock.unlock('share-note-viewer');
        trapShareNoteViewer(false);
    }

    function prepareShareNoteImages(root) {
        root = root || document.getElementById('share-content');
        if (!root) return;
        var images = root.querySelectorAll('.sh-note-text img');
        Array.prototype.forEach.call(images, function(img) {
            if (img.dataset.shareLightboxReady === '1') return;
            img.dataset.shareLightboxReady = '1';
            img.classList.add('note-image-lightbox-trigger');
            img.setAttribute('tabindex', '0');
            img.setAttribute('role', 'button');
            img.setAttribute('aria-label', window.__('note.compose.image') || '查看图片');
            img.addEventListener('click', function(e) {
                e.preventDefault();
                e.stopPropagation();
                openShareImageLightbox(img);
            });
            img.addEventListener('keydown', function(e) {
                if (e.key !== 'Enter' && e.key !== ' ') return;
                e.preventDefault();
                e.stopPropagation();
                openShareImageLightbox(img);
            });
        });
    }

    function getShareImageLightboxItems() {
        var images = document.querySelectorAll('.public-note-card .sh-note-text img.note-image-lightbox-trigger, #shareNoteViewerContent img.note-image-lightbox-trigger');
        return Array.prototype.slice.call(images).map(function(img, index) {
            return {
                img: img,
                src: img.currentSrc || img.src || img.getAttribute('src') || '',
                alt: img.getAttribute('alt') || '',
                title: img.getAttribute('title') || '',
                index: index
            };
        }).filter(function(item) { return !!item.src; });
    }

    function setShareImageLightboxItem(index) {
        var items = getShareImageLightboxItems();
        var overlayImg = document.getElementById('shareNoteImageLightboxImg');
        var captionEl = document.getElementById('shareNoteImageLightboxCaption');
        var counterEl = document.getElementById('shareNoteImageLightboxCounter');
        var prevBtn = document.getElementById('shareNoteImageLightboxPrevBtn');
        var nextBtn = document.getElementById('shareNoteImageLightboxNextBtn');
        if (!items.length || !overlayImg) {
            closeShareImageLightbox();
            return;
        }
        var nextIndex = Math.max(0, Math.min(index, items.length - 1));
        var item = items[nextIndex];
        shareImageLightboxIndex = nextIndex;
        overlayImg.src = item.src;
        overlayImg.alt = item.alt || item.title || '';
        if (captionEl) captionEl.textContent = item.alt || item.title || '';
        if (counterEl) counterEl.textContent = (nextIndex + 1) + ' / ' + items.length;
        if (prevBtn) prevBtn.disabled = nextIndex <= 0;
        if (nextBtn) nextBtn.disabled = nextIndex >= items.length - 1;
    }

    function openShareImageLightbox(targetImg) {
        var overlay = document.getElementById('shareNoteImageLightboxOverlay');
        if (!overlay || !targetImg) return;
        var items = getShareImageLightboxItems();
        var index = items.findIndex(function(item) { return item.img === targetImg; });
        if (index < 0) return;
        shareImageLightboxPrevFocus = document.activeElement;
        overlay.classList.add('active');
        if (window.BookStarkScrollLock) BookStarkScrollLock.lock('share-note-image-lightbox');
        setShareImageLightboxItem(index);
        trapShareImageLightbox(true);
    }

    function showAdjacentShareImageLightbox(delta) {
        var items = getShareImageLightboxItems();
        if (!items.length) return;
        var current = typeof shareImageLightboxIndex === 'number' ? shareImageLightboxIndex : 0;
        setShareImageLightboxItem(current + delta);
    }

    function closeShareImageLightbox() {
        var overlay = document.getElementById('shareNoteImageLightboxOverlay');
        if (overlay) overlay.classList.remove('active');
        var overlayImg = document.getElementById('shareNoteImageLightboxImg');
        if (overlayImg) {
            overlayImg.removeAttribute('src');
            overlayImg.alt = '';
        }
        shareImageLightboxIndex = null;
        if (window.BookStarkScrollLock) BookStarkScrollLock.unlock('share-note-image-lightbox');
        trapShareImageLightbox(false);
    }

    function trapShareNoteViewer(on) {
        if (on) {
            if (shareNoteViewerTrapHandler) return;
            shareNoteViewerTrapHandler = function(e) {
                if (document.getElementById('shareNoteImageLightboxOverlay').classList.contains('active')) return;
                if (e.key === 'Tab') trapPublicReaderFocus(e, 'shareNoteViewerOverlay');
                if (e.key === 'Escape') { e.preventDefault(); closeShareNoteViewer(); return; }
                if (e.key === 'ArrowLeft') { e.preventDefault(); showAdjacentShareNoteViewer(-1); return; }
                if (e.key === 'ArrowRight') { e.preventDefault(); showAdjacentShareNoteViewer(1); return; }
            };
            document.addEventListener('keydown', shareNoteViewerTrapHandler);
            var closeBtn = document.querySelector('#shareNoteViewerOverlay .note-viewer-close');
            if (closeBtn) closeBtn.focus();
        } else {
            if (shareNoteViewerTrapHandler) {
                document.removeEventListener('keydown', shareNoteViewerTrapHandler);
                shareNoteViewerTrapHandler = null;
            }
            if (shareNoteViewerPrevFocus && typeof shareNoteViewerPrevFocus.focus === 'function') {
                try { shareNoteViewerPrevFocus.focus(); } catch(e) {}
                shareNoteViewerPrevFocus = null;
            }
        }
    }

    function trapShareImageLightbox(on) {
        if (on) {
            if (shareImageLightboxTrapHandler) return;
            shareImageLightboxTrapHandler = function(e) {
                if (e.key === 'Tab') trapPublicReaderFocus(e, 'shareNoteImageLightboxOverlay');
                if (e.key === 'Escape') { e.preventDefault(); closeShareImageLightbox(); return; }
                if (e.key === 'ArrowLeft') { e.preventDefault(); showAdjacentShareImageLightbox(-1); return; }
                if (e.key === 'ArrowRight') { e.preventDefault(); showAdjacentShareImageLightbox(1); return; }
            };
            document.addEventListener('keydown', shareImageLightboxTrapHandler);
            var closeBtn = document.getElementById('shareNoteImageLightboxCloseBtn');
            if (closeBtn) closeBtn.focus();
        } else {
            if (shareImageLightboxTrapHandler) {
                document.removeEventListener('keydown', shareImageLightboxTrapHandler);
                shareImageLightboxTrapHandler = null;
            }
            if (shareImageLightboxPrevFocus && typeof shareImageLightboxPrevFocus.focus === 'function') {
                try { shareImageLightboxPrevFocus.focus(); } catch(e) {}
                shareImageLightboxPrevFocus = null;
            }
        }
    }

    function fmtDate(t) {
        if (!t) return '';
        var d = new Date(t); if (isNaN(d.getTime())) return t.substring(0, 10);
        var now = new Date();
        var diff = Math.floor((new Date(now.getFullYear(),now.getMonth(),now.getDate()) - new Date(d.getFullYear(),d.getMonth(),d.getDate())) / 86400000);
        if (diff === 0) return window.__('share.date.today'); if (diff === 1) return window.__('share.date.yesterday'); if (diff < 7) return diff + window.__('share.date.days_ago');
        return d.getFullYear() === now.getFullYear() ? (d.getMonth()+1) + window.__('share.date.month_day') + d.getDate() + window.__('share.date.day_unit') : d.getFullYear() + window.__('share.date.year_unit') + (d.getMonth()+1) + window.__('share.date.month_day') + d.getDate() + window.__('share.date.day_unit');
    }
    function fmtHM(t) {
        if (!t) return '';
        var d = new Date(t); if (isNaN(d.getTime())) return t.substring(11, 16);
        return d.getHours().toString().padStart(2,'0') + ':' + d.getMinutes().toString().padStart(2,'0');
    }
