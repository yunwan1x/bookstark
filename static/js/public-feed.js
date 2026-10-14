/* One public reading surface for guests and signed-in readers. */
(function () {
  'use strict';
  const searchToggle = document.querySelector('.public-search-toggle');
  const searchForm = document.getElementById('publicSearch');
  function toggleSearch(open) {
    searchToggle.setAttribute('aria-expanded', String(open));
    searchForm.classList.toggle('is-open', open);
    if (open) searchForm.querySelector('[name="keyword"]').focus();
  }
  searchToggle.addEventListener('click', () => toggleSearch(searchToggle.getAttribute('aria-expanded') !== 'true'));
  searchForm.addEventListener('keydown', e => {
    if (e.key === 'Escape') { toggleSearch(false); searchToggle.focus(); }
  });
  if (searchForm.querySelector('[name="keyword"]').value) searchForm.classList.add('is-open');
  // Save only this tab's reading position, not content or credentials.
  const positionKey = 'bookstark:public-login-return';
  document.querySelector('.public-login')?.addEventListener('click', () => {
    try { sessionStorage.setItem(positionKey, JSON.stringify({url: '/shares' + location.search, y: scrollY})); } catch (_) {}
  });
  try {
    const saved = JSON.parse(sessionStorage.getItem(positionKey) || 'null');
    if (document.querySelector('.public-account') && saved && saved.url === location.pathname + location.search) {
      sessionStorage.removeItem(positionKey);
      requestAnimationFrame(() => scrollTo(0, saved.y));
    }
  } catch (_) {}

  async function api(url, method) {
    const res = await csrfFetch(url, {method, offlinePolicy: 'reject', lockKey: 'public:' + url});
    const result = await res.json().catch(() => ({}));
    if (!res.ok || result.code !== 0) throw new Error(result.message || window.__('share.pin.error'));
    return result;
  }
  document.addEventListener('click', async e => {
    document.querySelectorAll('.public-manage[open]').forEach(menu => {
      if (!menu.contains(e.target)) menu.open = false;
    });
    const btn = e.target.closest('[data-public-action]');
    if (!btn || btn.disabled) return;
    const action = btn.dataset.publicAction;
    btn.disabled = true;
    try {
      if (action === 'unpublish' && !await BSDialog.confirm2(formatDeleteConfirmation(window.__('public.unpublish_confirm'), btn.dataset.title, btn.dataset.id))) { btn.disabled = false; return; }
      const base = '/api/shares/' + encodeURIComponent(btn.dataset.type) + '/' + encodeURIComponent(btn.dataset.id);
      await api(base + (action === 'pin' ? '/pin' : ''), action === 'pin' ? 'PATCH' : 'DELETE');
      location.reload();
    } catch (err) { BSDialog.toast(err.message, 'error'); btn.disabled = false; }
  });
  document.addEventListener('keydown', e => {
    if (e.key === 'Escape' && document.querySelector('#user-menu-trigger[aria-expanded="true"]')) {
      BookStarkHeaderMenus.closeAll(); document.getElementById('user-menu-trigger').focus();
    }
    if (e.key === 'Escape') document.querySelectorAll('.public-manage[open]').forEach(menu => {
      menu.open = false; menu.querySelector('summary').focus();
    });
  });

  if (!window.__PUBLIC_NOTES__) return;
  Object.entries(window.__PUBLIC_NOTES__).forEach(([key, note]) => {
    registerShareNote(key, {title: note.title, content: note.content || '', author: note.author, time: note.share_time, labels: note.labels});
  });
  document.querySelectorAll('.public-note-card').forEach(row => {
    const note = shareNoteStore[row.dataset.noteKey], body = row.querySelector('[data-note-content]');
    if (!note || !body) return;
    body.innerHTML = sanitizeRenderedHTML(marked.parse(note.content));
    body.querySelectorAll('img').forEach(img => { img.loading = 'lazy'; });
    prepareShareNoteImages(body);
  });
  document.addEventListener('click', e => {
    const btn = e.target.closest('[data-note-action]');
    if (!btn) return;
    const row = btn.closest('.public-note-card');
    if (btn.dataset.noteAction === 'copy') copyShareNoteContent(row.dataset.noteKey);
    if (btn.dataset.noteAction === 'expand') openShareNoteViewer(row.dataset.noteKey);
    if (btn.dataset.noteAction === 'comments') BookStarkShareComments.toggle(row.querySelector('.share-comments'), btn);
  });
})();
