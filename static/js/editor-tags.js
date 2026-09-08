/**
 * BookStark Editor Tags
 * Popover-based tag editing in the editor topbar
 * Desktop: dropdown popover below tag button
 * Mobile: bottom sheet
 */
(function() {
  var RESOURCE_TYPE = window.EDITOR_TYPE === 'blog' ? 'blog' : 'document';
  var RESOURCE_ID = window.EDITOR_TYPE === 'blog' ? window.BLOG_ID : (window.DOCUMENT_ID || 0);
  var currentTags = [];
  var tagSearchTimer = null;
  var tagSaveTimer = null;
  var popoverOpen = false;

  // Parse initial labels from server
  function initTags() {
    var raw = window.EDITOR_LABELS || '';
    if (raw) {
      currentTags = raw.split(',').map(function(s) { return s.trim(); }).filter(function(s) { return s.length > 0; });
    }
    renderTags();
    updateBadge();
    bindEvents();
  }

  /**
   * Switch to a different document — reload tags from server.
   * Called by editor.js when the user clicks a document in the tree.
   */
  function switchDocument(docId) {
    if (window.EDITOR_TYPE === 'blog') return; // blogs don't switch
    if (!docId) return;
    RESOURCE_ID = docId;
    // Fetch tags for the new document
    fetch('/api/labels/resource/document/' + docId).then(function(r) { return r.json(); }).then(function(d) {
      if (d.code === 0 && Array.isArray(d.data)) {
        currentTags = d.data;
      } else {
        currentTags = [];
      }
      renderTags();
      updateBadge();
    }).catch(function() {
      currentTags = [];
      renderTags();
      updateBadge();
    });
  }
  window.editorTagsSwitchDoc = switchDocument;

  // Bind popover events
  function bindEvents() {
    var closeBtn = document.getElementById('tagPopoverClose');
    if (closeBtn) {
      closeBtn.addEventListener('click', function(e) {
        e.stopPropagation();
        closePopover();
      });
    }

    var overlay = document.getElementById('tagPopoverOverlay');
    if (overlay) {
      overlay.addEventListener('click', closePopover);
    }

    // Click outside popover to close (desktop)
    // Use mousedown instead of click to avoid race with toggleTagRow:
    // toggleTagRow runs on the button's click, but by the time click bubbles
    // to document, the popover is already open. mousedown fires before click,
    // so we check on mousedown and skip if the target is the toggle button.
    document.addEventListener('mousedown', function(e) {
      if (!popoverOpen) return;
      var popover = document.getElementById('tagPopover');
      var toggleBtn = document.getElementById('tagToggleBtn');
      if (popover && toggleBtn && !popover.contains(e.target) && !toggleBtn.contains(e.target)) {
        closePopover();
      }
    });

    // Escape to close
    document.addEventListener('keydown', function(e) {
      if (e.key === 'Escape' && popoverOpen) {
        closePopover();
      }
    });
  }

  // Render tag chips inside popover
  function renderTags() {
    var container = document.getElementById('tagContainer');
    if (!container) return;
    // Remove existing chips
    var chips = container.querySelectorAll('.tag-chip');
    chips.forEach(function(c) { c.remove(); });
    currentTags.forEach(function(name) {
      var chip = document.createElement('span');
      chip.className = 'tag-chip';
      chip.setAttribute('data-tag', name);
      chip.innerHTML = escHtml(name) + ' <span class="tag-remove" onclick="editorRemoveTag(\'' + name.replace(/'/g, "\\'").replace(/"/g, '&quot;') + '\')" title="移除" aria-label="移除标签 ' + escHtml(name) + '">&times;</span>';
      container.appendChild(chip);
    });
  }

  // Update badge count
  function updateBadge() {
    var badge = document.getElementById('tagCountBadge');
    if (!badge) return;
    badge.textContent = currentTags.length;
    badge.style.display = currentTags.length > 0 ? 'inline-flex' : 'none';
  }

  // Toggle popover
  window.toggleTagRow = function() {
    if (popoverOpen) {
      closePopover();
    } else {
      openPopover();
    }
  };

  function openPopover() {
    var popover = document.getElementById('tagPopover');
    var overlay = document.getElementById('tagPopoverOverlay');
    var btn = document.getElementById('tagToggleBtn');
    if (!popover) return;
    popover.classList.add('active');
    if (overlay) overlay.classList.add('active');
    if (btn) btn.classList.add('active');
    popoverOpen = true;
    setTimeout(function() {
      var input = document.getElementById('tagInput');
      if (input) input.focus();
    }, 100);
  }

  function closePopover() {
    var popover = document.getElementById('tagPopover');
    var overlay = document.getElementById('tagPopoverOverlay');
    var btn = document.getElementById('tagToggleBtn');
    if (!popover) return;
    popover.classList.remove('active');
    if (overlay) overlay.classList.remove('active');
    if (btn) btn.classList.remove('active');
    popoverOpen = false;
    hideTagDropdown();
  }
  window.closeEditorTagPopover = closePopover;

  // Add tag
  window.editorAddTag = function(name) {
    name = name.trim().replace(/,$/, '');
    if (!name || currentTags.indexOf(name) >= 0) return;
    currentTags.push(name);
    renderTags();
    updateBadge();
    var input = document.getElementById('tagInput');
    if (input) input.value = '';
    hideTagDropdown();
    scheduleSave();
  };

  // Remove tag
  window.editorRemoveTag = function(name) {
    currentTags = currentTags.filter(function(t) { return t !== name; });
    renderTags();
    updateBadge();
    scheduleSave();
  };

  // Search tags
  window.editorTagSearch = function() {
    clearTimeout(tagSearchTimer);
    tagSearchTimer = setTimeout(function() {
      var q = document.getElementById('tagInput').value.trim();
      var dd = document.getElementById('tagDropdown');
      if (!dd) return;
      var params = 'page_size=10';
      if (!q) params += '&sort_by=recent';
      if (q) params += '&keyword=' + encodeURIComponent(q);
      fetch('/api/labels?' + params).then(function(r) { return r.json(); }).then(function(d) {
        var items = (d.data || []).filter(function(l) { return currentTags.indexOf(l.label_name) < 0; });
        if (items.length === 0) {
          dd.innerHTML = q ? '<div class="tag-dropdown-empty">按 Enter 创建「' + escHtml(q) + '」</div>' : '';
          if (q) showTagDropdown(); else hideTagDropdown();
        } else {
          dd.innerHTML = items.map(function(l) {
            return '<div class="tag-dropdown-item" onclick="editorAddTag(\'' + l.label_name.replace(/'/g, "\\'") + '\')">' +
              '<span class="tag-item-name">' + escHtml(l.label_name) + '</span>' +
              '<span class="tag-item-count">' + (l.book_count || 0) + '书 ' + (l.blog_count || 0) + '博</span>' +
              '</div>';
          }).join('');
          showTagDropdown();
        }
      }).catch(function() {
        hideTagDropdown();
      });
    }, 300);
  };

  // Key handler
  window.editorTagKey = function(e) {
    if (e.key === 'Enter' || e.key === ',') {
      e.preventDefault();
      var input = document.getElementById('tagInput');
      if (input) editorAddTag(input.value);
    }
    // Backspace on empty input removes last tag
    if (e.key === 'Backspace') {
      var input = document.getElementById('tagInput');
      if (input && input.value === '' && currentTags.length > 0) {
        editorRemoveTag(currentTags[currentTags.length - 1]);
      }
    }
    if (e.key === 'Escape') {
      closePopover();
    }
  };

  function hideTagDropdown() {
    var dd = document.getElementById('tagDropdown');
    if (dd) dd.style.display = 'none';
  }

  function showTagDropdown() {
    var dd = document.getElementById('tagDropdown');
    if (dd) dd.style.display = 'block';
  }

  // Save tags (debounced)
  function scheduleSave() {
    clearTimeout(tagSaveTimer);
    tagSaveTimer = setTimeout(function() {
      saveTags();
    }, 800);
  }

  function saveTags() {
    if (!RESOURCE_ID) return; // no document selected yet
    var labelsStr = currentTags.join(',');
    csrfFetch('/api/labels/resource/' + RESOURCE_TYPE + '/' + RESOURCE_ID, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ labels: labelsStr })
    }).then(function(r) {
      if (!r.ok) throw new Error('save failed');
      return r.json();
    }).then(function(d) {
      // Update local tags from server response
      if (d.data && Array.isArray(d.data)) {
        currentTags = d.data;
        renderTags();
        updateBadge();
      }
      showSaveIndicator();
    }).catch(function() {
      // Show error briefly
      var indicator = document.querySelector('.tag-save-indicator');
      if (indicator) {
        indicator.textContent = '保存失败';
        indicator.style.color = 'var(--color-danger)';
        indicator.classList.add('visible');
        setTimeout(function() {
          indicator.classList.remove('visible');
          indicator.style.color = '';
        }, 2000);
      }
    });
  }

  function showSaveIndicator() {
    var indicator = document.querySelector('.tag-save-indicator');
    if (!indicator) return;
    indicator.textContent = '已保存';
    indicator.style.color = '';
    indicator.classList.add('visible');
    setTimeout(function() {
      indicator.classList.remove('visible');
    }, 1500);
  }

  function escHtml(s) {
    if (typeof window.escHtml === 'function') return window.escHtml(s);
    var d = document.createElement('div');
    d.textContent = s;
    return d.innerHTML;
  }

  // Init on DOM ready
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initTags);
  } else {
    initTags();
  }
})();
