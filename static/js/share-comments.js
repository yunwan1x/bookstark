(function() {
  'use strict';

  function t(key) {
    if (typeof window.__ === 'function') return window.__(key);
    return key;
  }

  function readCSRFToken() {
    var meta = document.querySelector('meta[name="csrf-token"]');
    if (meta && meta.content) return meta.content;
    var match = document.cookie.match(/(?:^|; )csrf_token=([^;]+)/);
    return match ? decodeURIComponent(match[1]) : '';
  }

  function esc(value) {
    return String(value || '').replace(/[&<>"']/g, function(ch) {
      return {
        '&': '&amp;',
        '<': '&lt;',
        '>': '&gt;',
        '"': '&quot;',
        "'": '&#39;'
      }[ch];
    });
  }

  function formatTime(value) {
    if (!value) return '';
    var date = new Date(value);
    if (Number.isNaN(date.getTime())) return '';
    return date.toLocaleString();
  }

  function apiJSON(url, options) {
    options = options || {};
    options.headers = options.headers || {};
    if (options.body && !options.headers['Content-Type']) options.headers['Content-Type'] = 'application/json';
    if (options.method && options.method !== 'GET') options.headers['X-CSRF-Token'] = readCSRFToken();
    return fetch(url, options).then(function(res) {
      return res.json().catch(function() { return {}; }).then(function(data) {
        if (!res.ok || (data && data.code && data.code !== 0)) {
          var err = new Error((data && data.message) || t('share_comments.error'));
          err.status = res.status;
          throw err;
        }
        return data;
      });
    });
  }

  function rootIdentify(root) {
    return (root && root.getAttribute('data-share-identify')) || window.shareIdentify || '';
  }

  function findInRoot(root, selector, fallbackID) {
    if (root) {
      var scoped = root.querySelector(selector);
      if (scoped) return scoped;
    }
    return fallbackID ? document.getElementById(fallbackID) : null;
  }

  function fieldValue(el) {
    return el && typeof el.value === 'string' ? el.value.trim() : '';
  }

  function commentMaxLength() {
    var n = parseInt(window.__SHARE_COMMENT_MAX_LENGTH__, 10);
    return n >= 100 && n <= 5000 ? n : 2000;
  }

  function commentsMarkup() {
    var account = window.__SHARE_COMMENT_ACCOUNT__ || '';
    var identity = account
      ? '<div class="share-comments-identity">' + esc(t('share_comments.identity_prefix')) + ' ' + esc(account) + '</div>'
      : '<div class="share-comments-fields">' +
          '<input class="share-comment-input share-comment-author" type="text" maxlength="40" autocomplete="name" placeholder="' + esc(t('share_comments.name_placeholder')) + '" aria-label="' + esc(t('share_comments.name_placeholder')) + '">' +
          '<input class="share-comment-input share-comment-email" type="email" maxlength="200" autocomplete="email" placeholder="' + esc(t('share_comments.email_placeholder')) + '" aria-label="' + esc(t('share_comments.email_placeholder')) + '">' +
        '</div>';
    return '' +
      '<div class="share-comments-head">' +
        '<h3 class="share-comments-title"><i class="fa-regular fa-comments"></i>' + esc(t('share_comments.title')) + '</h3>' +
        '<span class="share-comments-count"></span>' +
      '</div>' +
      '<div class="share-comments-list" aria-live="polite"><div class="share-comments-state">' + esc(t('share_comments.loading')) + '</div></div>' +
      '<form class="share-comments-form">' +
        identity +
        '<textarea class="share-comment-textarea share-comment-content-input" maxlength="' + esc(commentMaxLength()) + '" placeholder="' + esc(t('share_comments.content_placeholder')) + '" aria-label="' + esc(t('share_comments.content_placeholder')) + '"></textarea>' +
        '<div class="share-comments-actions">' +
          '<div class="share-comments-state"></div>' +
          '<button class="share-comments-submit" type="submit"><i class="fa-solid fa-paper-plane"></i>' + esc(t('share_comments.submit')) + '</button>' +
        '</div>' +
      '</form>';
  }

  function hydrate(root) {
    if (!root || root.getAttribute('data-comments-hydrated') === '1') return root;
    if (!root.querySelector('.share-comments-list')) root.innerHTML = commentsMarkup();
    root.setAttribute('data-comments-hydrated', '1');
    return root;
  }

  function stateText(root, text) {
    var el = findInRoot(root, '.share-comments-state', 'share-comments-state');
    if (el) el.textContent = text || '';
  }

  function setSubmitting(root, active, form) {
    var btn = form ? form.querySelector('.share-comments-submit') : null;
    if (!btn) btn = findInRoot(root, '.share-comments-submit', 'share-comments-submit');
    if (!btn) return;
    btn.disabled = !!active;
    btn.innerHTML = active
      ? '<i class="fa-solid fa-spinner fa-spin"></i>' + esc(t('share_comments.submitting'))
      : '<i class="fa-solid fa-paper-plane"></i>' + esc(t('share_comments.submit'));
  }

  function renderComments(root, items, total) {
    var list = findInRoot(root, '.share-comments-list', 'share-comments-list');
    var count = findInRoot(root, '.share-comments-count', 'share-comments-count');
    if (!list) return;
    if (count) count.textContent = total > 0 ? t('share_comments.count').replace('{count}', String(total)) : '';
    if (!items || !items.length) {
      list.innerHTML = '<div class="share-comments-state">' + esc(t('share_comments.empty')) + '</div>';
      return;
    }
    list.innerHTML = items.map(function(item) { return renderCommentItem(item); }).join('');
  }

  function renderCommentItem(item) {
    var deleteBtn = item.can_delete
      ? '<button type="button" class="share-comment-delete" data-comment-id="' + esc(item.comment_id) + '" title="' + esc(t('share_comments.delete')) + '" aria-label="' + esc(t('share_comments.delete')) + '"><i class="fa-regular fa-trash-can"></i></button>'
      : '';
    var replyBtn = !item.is_deleted
      ? '<button type="button" class="share-comment-reply" data-parent-comment-id="' + esc(item.comment_id) + '" data-reply-to-comment-id="' + esc(item.comment_id) + '" data-reply-to-author="' + esc(item.author_name || t('share_comments.anonymous')) + '" title="' + esc(t('share_comments.reply')) + '" aria-label="' + esc(t('share_comments.reply')) + '"><i class="fa-regular fa-comments"></i></button>'
      : '';
    return '' +
      '<article class="share-comment-item" data-comment-id="' + esc(item.comment_id) + '">' +
        '<div class="share-comment-meta">' +
          '<div><span class="share-comment-author">' + esc(item.author_name || t('share_comments.anonymous')) + '</span> <span class="share-comment-time">' + esc(formatTime(item.create_time)) + '</span></div>' +
          '<div class="share-comment-tools">' + replyBtn + deleteBtn + '</div>' +
        '</div>' +
        '<div class="share-comment-content' + (item.is_deleted ? ' is-deleted' : '') + '">' + esc(item.content) + '</div>' +
        '<div class="share-comment-reply-slot"></div>' +
        renderReplies(item) +
      '</article>';
  }

  function renderReplies(item) {
    var replies = item.replies || [];
    if (!replies.length) return '';
    var collapsed = replies.length > 3;
    var visible = collapsed ? replies.slice(0, 3) : replies;
    var hidden = collapsed ? replies.slice(3) : [];
    return '<div class="share-comment-replies">' +
      visible.map(function(reply) { return renderReplyItem(item, reply, false); }).join('') +
      (hidden.length ? '<div class="share-comment-replies-extra" hidden>' + hidden.map(function(reply) { return renderReplyItem(item, reply, true); }).join('') + '</div>' : '') +
      (hidden.length ? '<button type="button" class="share-comment-replies-toggle" data-expanded="false">' + esc(t('share_comments.expand_replies').replace('{count}', String(hidden.length))) + '</button>' : '') +
      '</div>';
  }

  function renderReplyItem(rootItem, item) {
    var deleteBtn = item.can_delete
      ? '<button type="button" class="share-comment-delete" data-comment-id="' + esc(item.comment_id) + '" title="' + esc(t('share_comments.delete')) + '" aria-label="' + esc(t('share_comments.delete')) + '"><i class="fa-regular fa-trash-can"></i></button>'
      : '';
    var replyToAuthor = item.reply_to_author_name || item.author_name || t('share_comments.anonymous');
    return '' +
      '<article class="share-comment-item share-comment-reply-item" data-comment-id="' + esc(item.comment_id) + '">' +
        '<div class="share-comment-meta">' +
          '<div><span class="share-comment-author">' + esc(item.author_name || t('share_comments.anonymous')) + '</span> <span class="share-comment-time">' + esc(formatTime(item.create_time)) + '</span></div>' +
          '<div class="share-comment-tools">' +
            '<button type="button" class="share-comment-reply" data-parent-comment-id="' + esc(rootItem.comment_id) + '" data-reply-to-comment-id="' + esc(item.comment_id) + '" data-reply-to-author="' + esc(item.author_name || t('share_comments.anonymous')) + '" title="' + esc(t('share_comments.reply')) + '" aria-label="' + esc(t('share_comments.reply')) + '"><i class="fa-regular fa-comments"></i></button>' +
            deleteBtn +
          '</div>' +
        '</div>' +
        '<div class="share-comment-reply-context">' + esc(t('share_comments.reply_to_user').replace('{name}', replyToAuthor)) + '</div>' +
        '<div class="share-comment-content">' + esc(item.content) + '</div>' +
      '</article>';
  }

  function renderReplyForm(root, parentID, replyToID, replyToAuthor) {
    var account = window.__SHARE_COMMENT_ACCOUNT__ || '';
    var identity = account
      ? '<div class="share-comments-identity">' + esc(t('share_comments.identity_prefix')) + ' ' + esc(account) + '</div>'
      : '<div class="share-comments-fields">' +
          '<input class="share-comment-input share-comment-author" type="text" maxlength="40" autocomplete="name" placeholder="' + esc(t('share_comments.name_placeholder')) + '" aria-label="' + esc(t('share_comments.name_placeholder')) + '">' +
          '<input class="share-comment-input share-comment-email" type="email" maxlength="200" autocomplete="email" placeholder="' + esc(t('share_comments.email_placeholder')) + '" aria-label="' + esc(t('share_comments.email_placeholder')) + '">' +
        '</div>';
    var context = replyToAuthor ? t('share_comments.reply_to_user').replace('{name}', replyToAuthor) : t('share_comments.reply_to_comment');
    return '' +
      '<form class="share-comments-form share-comment-reply-form">' +
        '<div class="share-comment-reply-context">' + esc(context) + '</div>' +
        '<input type="hidden" class="share-comment-parent-id" value="' + esc(parentID) + '">' +
        '<input type="hidden" class="share-comment-reply-to-id" value="' + esc(replyToID) + '">' +
        identity +
        '<textarea class="share-comment-textarea share-comment-content-input" maxlength="' + esc(commentMaxLength()) + '" placeholder="' + esc(context) + '" aria-label="' + esc(context) + '"></textarea>' +
        '<div class="share-comments-actions">' +
          '<div class="share-comments-state"></div>' +
          '<button class="share-comments-submit" type="submit"><i class="fa-solid fa-paper-plane"></i>' + esc(t('share_comments.submit')) + '</button>' +
        '</div>' +
      '</form>';
  }

  function toggleReplyForm(root, btn) {
    var item = btn.closest('.share-comment-item');
    if (!item) return;
    var slot = item.querySelector('.share-comment-reply-slot') || (item.parentElement && item.parentElement.closest('.share-comment-item') ? item.parentElement.closest('.share-comment-item').querySelector('.share-comment-reply-slot') : null);
    if (!slot) return;
    var parentID = btn.getAttribute('data-parent-comment-id') || '';
    var replyToID = btn.getAttribute('data-reply-to-comment-id') || parentID;
    var replyToAuthor = btn.getAttribute('data-reply-to-author') || '';
    var open = slot.getAttribute('data-reply-to-comment-id') === replyToID && slot.innerHTML.trim() !== '';
    document.querySelectorAll('.share-comment-reply-slot').forEach(function(el) {
      el.innerHTML = '';
      el.removeAttribute('data-reply-to-comment-id');
    });
    if (open) return;
    slot.setAttribute('data-reply-to-comment-id', replyToID);
    slot.innerHTML = renderReplyForm(root, parentID, replyToID, replyToAuthor);
    var textarea = slot.querySelector('.share-comment-content-input');
    if (textarea) textarea.focus();
  }

  function toggleReplies(root, btn) {
    var box = btn.closest('.share-comment-replies');
    if (!box) return;
    var extra = box.querySelector('.share-comment-replies-extra');
    if (!extra) return;
    var opening = extra.hidden;
    extra.hidden = !opening;
    btn.setAttribute('data-expanded', opening ? 'true' : 'false');
    btn.textContent = opening ? t('share_comments.collapse_replies') : t('share_comments.expand_replies').replace('{count}', String(extra.children.length));
  }

  function loadComments(root) {
    var identify = rootIdentify(root);
    if (!window.__SHARE_COMMENTS_ENABLED__ || !identify) return;
    var list = findInRoot(root, '.share-comments-list', 'share-comments-list');
    if (list) list.innerHTML = '<div class="share-comments-state">' + esc(t('share_comments.loading')) + '</div>';
    apiJSON('/api/shares/' + encodeURIComponent(identify) + '/comments?page=1&page_size=50')
      .then(function(data) {
        renderComments(root, data.data || [], data.total || 0);
      })
      .catch(function(err) {
        if (list) list.innerHTML = '<div class="share-comments-state">' + esc(err.message || t('share_comments.error')) + '</div>';
      });
  }

  function submitComment(event) {
    event.preventDefault();
    var root = event.target.closest('.share-comments');
    var form = event.target;
    var identify = rootIdentify(root);
    var contentEl = form.querySelector('textarea.share-comment-content-input, #share-comment-content') || findInRoot(root, 'textarea.share-comment-content-input, #share-comment-content', 'share-comment-content');
    var authorEl = form.querySelector('input.share-comment-author, #share-comment-author') || findInRoot(root, 'input.share-comment-author, #share-comment-author', 'share-comment-author');
    var emailEl = form.querySelector('input.share-comment-email, #share-comment-email') || findInRoot(root, 'input.share-comment-email, #share-comment-email', 'share-comment-email');
    var parentID = parseInt(fieldValue(form.querySelector('.share-comment-parent-id')), 10) || 0;
    var replyToID = parseInt(fieldValue(form.querySelector('.share-comment-reply-to-id')), 10) || 0;
    var content = fieldValue(contentEl);
    var authorName = fieldValue(authorEl);
    var email = fieldValue(emailEl);
    if (!content) {
      stateText(root, t('share_comments.content_required'));
      return;
    }
    if (content.length > commentMaxLength()) {
      stateText(root, t('share_comments.max_length').replace('{count}', String(commentMaxLength())));
      return;
    }
    setSubmitting(root, true, form);
    stateText(root, '');
    apiJSON('/api/shares/' + encodeURIComponent(identify) + '/comments', {
      method: 'POST',
      body: JSON.stringify({
        author_name: authorName,
        author_email: email,
        content: content,
        parent_comment_id: parentID,
        reply_to_comment_id: replyToID
      })
    }).then(function() {
      if (contentEl) contentEl.value = '';
      loadComments(root);
    }).catch(function(err) {
      stateText(root, err.message || t('share_comments.error'));
    }).finally(function() {
      setSubmitting(root, false, form);
    });
  }

  function deleteComment(root, commentID) {
    if (!commentID || !window.confirm(t('share_comments.delete_confirm'))) return;
    apiJSON('/api/share-comments/' + encodeURIComponent(commentID) + '?identify=' + encodeURIComponent(rootIdentify(root)), {
      method: 'DELETE'
    }).then(function() {
      loadComments(root);
    }).catch(function(err) {
      stateText(root, err.message || t('share_comments.error'));
    });
  }

  function init(scope) {
    var roots;
    if (scope && scope.classList && scope.classList.contains('share-comments')) {
      roots = [scope];
    } else {
      var base = scope && scope.querySelectorAll ? scope : document;
      roots = Array.prototype.slice.call(base.querySelectorAll('.share-comments'));
    }
    if (!roots.length || !window.__SHARE_COMMENTS_ENABLED__) return;
    roots.forEach(function(root) {
      if (root.getAttribute('data-comments-bound') === '1') return;
      if (root.getAttribute('data-comments-lazy') === '1' && root.hidden) return;
      hydrate(root);
      root.setAttribute('data-comments-bound', '1');
      root.addEventListener('submit', function(event) {
        if (event.target.closest('.share-comments-form')) submitComment(event);
      });
      root.addEventListener('click', function(event) {
        var btn = event.target.closest('.share-comment-delete');
        if (btn) {
          deleteComment(root, btn.getAttribute('data-comment-id'));
          return;
        }
        btn = event.target.closest('.share-comment-reply');
        if (btn) {
          toggleReplyForm(root, btn);
          return;
        }
        btn = event.target.closest('.share-comment-replies-toggle');
        if (btn) toggleReplies(root, btn);
      });
      loadComments(root);
    });
  }

  function toggle(root, trigger) {
    if (!root) return false;
    var opening = root.hidden;
    root.hidden = !opening;
    if (trigger) trigger.setAttribute('aria-expanded', opening ? 'true' : 'false');
    if (opening) {
      hydrate(root);
      init(root);
    }
    return opening;
  }

  function handleLazyToggle(event) {
    var trigger = event.target.closest('[data-share-comments-toggle]');
    if (!trigger) return;
    var targetID = trigger.getAttribute('aria-controls');
    var root = targetID ? document.getElementById(targetID) : null;
    if (!root) {
      var shell = trigger.closest('.note-comments-disclosure, .sh-note-row');
      root = shell ? shell.querySelector('.share-comments') : null;
    }
    if (root) toggle(root, trigger);
  }

  window.BookStarkShareComments = {
    init: init,
    load: loadComments,
    hydrate: hydrate,
    toggle: toggle
  };

  document.addEventListener('click', handleLazyToggle);
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();
})();
