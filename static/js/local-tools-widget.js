(function () {
  'use strict';
  const container = document.getElementById('publicLocalDrafts');
  if (!container) return;
  async function refresh() {
    try {
      const rows = await BookStarkLocalDrafts.list(2);
      container.replaceChildren();
      if (!rows.length) { container.textContent = __('tools.empty'); return; }
      rows.forEach(d => {
        const a = document.createElement('a'); a.href = '/tools?draft=' + encodeURIComponent(d.id); a.target = '_blank'; a.rel = 'noopener';
        const title = document.createElement('strong'); title.textContent = d.title;
        const info = document.createElement('small'); info.textContent = __('tools.' + d.type) + ' · ' + new Date(d.updated).toLocaleString(document.documentElement.lang);
        a.append(title, info); container.append(a);
      });
    } catch (_) { container.textContent = __('tools.unavailable'); }
  }
  window.addEventListener('local-drafts-changed', refresh);
  window.addEventListener('focus', refresh);
  document.addEventListener('visibilitychange', () => { if (!document.hidden) refresh(); });
  refresh();
})();
