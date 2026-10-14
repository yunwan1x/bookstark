(function() {
  'use strict';

  function t(key, fallback) {
    if (typeof window.__ !== 'function') return fallback;
    var value = window.__(key);
    return value && value !== key ? value : fallback;
  }

  function byId(id) { return document.getElementById(id); }
  function setOptionalText(id, value) {
    var el = byId(id);
    if (el) el.textContent = value;
  }
  function html(value) { return typeof escHtml === 'function' ? escHtml(value || '') : String(value || ''); }
  function attr(value) { return typeof escAttr === 'function' ? escAttr(value || '') : String(value || ''); }
  function countText(value) {
    if (value === null || value === undefined || value === '') return '0';
    return String(value);
  }
  function tf(key, fallback, values) {
    var message = t(key, fallback);
    Object.keys(values || {}).forEach(function(name) {
      message = message.replace(new RegExp('\\{' + name + '\\}', 'g'), values[name]);
    });
    return message;
  }

  function toast(message, type) {
    if (window.BSDialog && BSDialog.toast) BSDialog.toast(message, type || 'info');
  }

  async function apiJSON(url, options) {
    var res = await csrfFetch(url, options || {});
    var data = await res.json().catch(function() { return {}; });
    if (!res.ok || data.code) {
      throw new Error(data.message || t('topic.error.generic', 'Operation failed'));
    }
    return data;
  }

  function typeText(type) {
    var map = {
      document: t('topic.type.document', 'Document'),
      note: t('topic.type.note', 'Note'),
      article: t('topic.type.article', 'Article'),
      bookmark: t('topic.type.bookmark', 'Bookmark'),
      task: t('topic.type.task', 'Todo')
    };
    return map[type] || type || t('topic.stat.materials', 'Materials');
  }

  function typeIcon(type) {
    var map = {
      document: 'fa-file-lines',
      note: 'fa-note-sticky',
      article: 'fa-pen-nib',
      bookmark: 'fa-bookmark',
      task: 'fa-list-check'
    };
    return map[type] || 'fa-layer-group';
  }

  function formatDate(value) {
    if (!value) return '';
    var date = new Date(value);
    if (isNaN(date.getTime())) return String(value).slice(0, 16);
    return date.getFullYear() + '-' + String(date.getMonth() + 1).padStart(2, '0') + '-' + String(date.getDate()).padStart(2, '0') + ' ' + String(date.getHours()).padStart(2, '0') + ':' + String(date.getMinutes()).padStart(2, '0');
  }

  function formatDateOnly(value) {
    if (!value) return '';
    var date = new Date(value);
    if (isNaN(date.getTime())) return String(value).slice(0, 10);
    return date.getFullYear() + '-' + String(date.getMonth() + 1).padStart(2, '0') + '-' + String(date.getDate()).padStart(2, '0');
  }

  function defaultDueDate() {
    var d = new Date();
    d.setDate(d.getDate() + 7);
    return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0');
  }

  function multiline(value, fallback) {
    var text = (value || '').trim();
    if (!text) return '<span class="topic-muted">' + html(fallback || '') + '</span>';
    return html(text).replace(/\n/g, '<br>');
  }

  function summaryType(value) {
    return value === 'ai' ? 'ai' : 'manual';
  }

  var app = {
    page: 1,
    pageSize: 20,
    totalPages: 1,
    keyword: '',
    topics: [],
    selectedId: 0,
    detail: null,
    totalItems: 0,
    activeDetailTab: 'details',
    topicDetailFilters: {
      details: '',
      resources: '',
      summaries: '',
      tasks: ''
    },
    topicSummaryComposer: null,
    topicCommentComposer: null,
    topicQuestionComposer: null,
    editingSummaryId: 0,
    summaryDraftType: 'manual',
    savingInlineSummary: false,
    topicSummaryPreviewing: false,
    topicQuestionPreviewing: false,
    topicSummaryEditorExpanded: false,
    topicSummaryEditorMode: 'new',
    topicEmojiPicker: null,
    topicDetailSearchTimer: null,
    topicEmojiOutsideHandler: null,
    topicQuestionEmojiPicker: null,
    topicQuestionEmojiOutsideHandler: null,
    topicAIAssistant: null,
    topicSummaryAI: null,
    topicSummaryAIContextText: '',
    topicSummaryAIStreamCtrl: null,
    topicCommentPreviewing: false,
    topicCommentScope: 'current',
    topicCommentTarget: null,
    topicComments: [],
    topicCommentDrafts: {},
    topicCommentPage: 1,
    topicCommentTotal: 0,
    topicCommentPageSize: 50,
    topicCommentLoading: false,
    topicCommentLoadToken: 0,
    topicCommentLayout: 'standard',
    topicDetailLoadToken: 0,
    editingTopicCommentId: 0,
    topicCommentEmojiPicker: null,
    topicCommentEmojiOutsideHandler: null,
    topicSummaryAIActiveComposer: null,
    topicSummaryAIActiveStatusID: 'topicSummaryAIStreamStatus',
    topicSummaryAIActiveScene: 'topic-summary',
    topicSummaryAIActiveKind: 'summary',
    initialTopicId: 0,
    mobileTopicSheetReturnFocus: null,
    editingTopicTaskId: 0,
    editingTopicTask: null,
    topicResourceFilter: 'all',
    topicResourceResults: [],
    topicResourceAddedKeys: {},
    topicResourceAddingKeys: {},
    topicResourceAddedSessionCount: 0,
    topicResourceSearchSeq: 0,
    topicResourcePickerMode: 'search',
    topicModalPreviousFocus: null,
    topicModalFocusHandler: null,
    topicFabPositionFrame: 0,

    init: function() {
      var params = new URLSearchParams(window.location.search);
      this.initialTopicId = parseInt(params.get('id'), 10) || 0;
      if (this.initialTopicId) this.selectedId = this.initialTopicId;
      this.activeDetailTab = 'details';
      this.bind();
      this.initSummaryComposer();
      this.initTopicCommentComposer();
      this.initTopicQuestionComposer();
      this.initTopicCommentLayout();
      this.renderTopicListSkeleton();
      this.renderTopicDetailSkeleton();
      this.switchDetailTab(this.activeDetailTab);
      this.updateTopicStickyControls();
      this.loadTopics({ skipSkeleton: true });
      if (params.get('command') === 'new-topic') {
        this.openCreateModal();
      }
    },

    bindIfPresent: function(id, eventName, handler) {
      var el = byId(id);
      if (el) el.addEventListener(eventName, handler);
      return el;
    },

    bindOverviewStatTabs: function() {
      var self = this;
      document.querySelectorAll('[data-topic-stat-tab]').forEach(function(card) {
        card.addEventListener('click', function() {
          self.switchDetailTab(card.getAttribute('data-topic-stat-tab'));
        });
      });
    },

    bind: function() {
      var self = this;
      byId('topicCreateBtn').addEventListener('click', function() { self.openCreateModal(); });
      byId('topicEmptyCreateBtn').addEventListener('click', function() { self.openCreateModal(); });
      this.bindIfPresent('topicFabBtn', 'click', function() { self.handleTopicFabAction(); });
      this.bindIfPresent('topicMobileSidebarBtn', 'click', function() { self.openMobileTopicSheet(); });
      this.bindIfPresent('topicMobileCommentsBtn', 'click', function() { self.openMobileCommentsModal(); });
      this.bindIfPresent('topicMobileRailCloseBtn', 'click', function() { self.closeMobileTopicSheet(); });
      this.bindIfPresent('topicMobileTopicBackdrop', 'click', function() { self.closeMobileTopicSheet(); });
      byId('topicKeyword').addEventListener('keydown', function(e) { if (e.key === 'Enter') self.search(); });
      byId('topicCreateForm').addEventListener('submit', function(e) {
        e.preventDefault();
        self.createTopic();
      });
      this.bindIfPresent('topicEditForm', 'submit', function(e) {
        e.preventDefault();
        self.saveTopic();
      });
      this.bindIfPresent('topicEditDeleteBtn', 'click', function() { self.deleteTopic(); });
      this.bindIfPresent('topicEditQuestionImageBtn', 'click', function() {
        var input = byId('topicEditQuestionFileInput');
        if (input) input.click();
      });
      this.bindIfPresent('topicEditQuestionFileInput', 'change', function(e) {
        if (e.target.files && e.target.files.length > 0) {
          self.uploadTopicQuestionImageFile(e.target.files[0]);
          e.target.value = '';
        }
      });
      this.bindIfPresent('topicEditQuestionEmojiBtn', 'click', function(e) {
        e.preventDefault();
        self.toggleTopicQuestionEmojiPicker();
      });
      this.bindIfPresent('topicEditQuestionPreviewBtn', 'click', function() { self.toggleTopicQuestionPreview(); });
      this.bindIfPresent('topicEditQuestionClearBtn', 'click', function() { self.clearTopicQuestionEditor(); });
      this.bindIfPresent('topicOverviewEditBtn', 'click', function() { self.openEditModal(); });
      this.bindIfPresent('topicOverviewPinBtn', 'click', function() { self.togglePin(); });
      this.bindIfPresent('topicOverviewAIAssistantBtn', 'click', function() { self.openTopicAIAssistant(); });
      this.bindIfPresent('topicDetailCreateBtn', 'click', function() { self.handleTopicFabAction(); });
      var summaryAIButton = byId('topicSummaryAIButton');
      if (summaryAIButton) summaryAIButton.addEventListener('click', function() { self.openTopicSummaryAI(); });
      this.bindIfPresent('topicSummaryImageButton', 'click', function() {
        var input = byId('topicSummaryFileInput');
        if (input) input.click();
      });
      this.bindIfPresent('topicSummaryFileInput', 'change', function(e) {
        if (e.target.files && e.target.files.length > 0) {
          self.uploadTopicSummaryImageFile(e.target.files[0]);
          e.target.value = '';
        }
      });
      byId('topicSummaryEmojiButton').addEventListener('click', function(e) {
        e.preventDefault();
        self.toggleTopicSummaryEmojiPicker();
      });
      byId('topicSummaryPreviewButton').addEventListener('click', function() { self.toggleTopicSummaryPreview(); });
      byId('topicSummaryClearButton').addEventListener('click', function() { self.clearInlineSummary(); });
      byId('topicSummarySaveButton').addEventListener('click', function() { self.saveInlineSummary(); });
      this.bindIfPresent('topicCommentSaveButton', 'click', function() { self.saveTopicComment(); });
      this.bindIfPresent('topicCommentImageButton', 'click', function() {
        var input = byId('topicCommentFileInput');
        if (input) input.click();
      });
      this.bindIfPresent('topicCommentFileInput', 'change', function(e) {
        if (e.target.files && e.target.files.length > 0) {
          self.uploadTopicCommentImageFile(e.target.files[0]);
          e.target.value = '';
        }
      });
      this.bindIfPresent('topicCommentEmojiButton', 'click', function(e) {
        e.preventDefault();
        self.toggleTopicCommentEmojiPicker();
      });
      this.bindIfPresent('topicCommentPreviewButton', 'click', function() { self.toggleTopicCommentPreview(); });
      this.bindIfPresent('topicCommentAIButton', 'click', function() { self.openTopicCommentAI(); });
      this.bindIfPresent('topicCommentClearButton', 'click', function() { self.clearTopicCommentEditor(); });
      this.bindIfPresent('topicCommentEditCancel', 'click', function() { self.resetTopicCommentDraft(); });
      this.bindIfPresent('topicCommentLocateBtn', 'click', function() { self.locateTopicCommentTarget(); });
      this.bindIfPresent('topicCommentCollapseBtn', 'click', function() { self.setTopicCommentLayout('collapsed'); });
      this.bindIfPresent('topicCommentCollapsedBtn', 'click', function() { self.setTopicCommentLayout('standard'); });
      this.bindIfPresent('topicCommentExpandBtn', 'click', function() {
        self.setTopicCommentLayout(self.topicCommentLayout === 'expanded' ? 'standard' : 'expanded');
      });
      this.bindIfPresent('topicDesktopRailRestoreBtn', 'click', function() { self.setTopicCommentLayout('standard'); });
      document.querySelectorAll('[data-topic-comment-scope]').forEach(function(btn) {
        btn.addEventListener('click', function() {
          self.setTopicCommentScope(btn.getAttribute('data-topic-comment-scope'));
        });
      });
      this.bindIfPresent('topicSummaryRestoreButton', 'click', function() { self.restoreTopicSummaryEditor(); });
      byId('topicResourceSearchBtn').addEventListener('click', function() { self.searchResources(); });
      this.bindIfPresent('topicResourceCreateBtn', 'click', function() {
        self.openTopicResourceCreate(self.topicResourceFilter === 'all' ? 'note' : self.topicResourceFilter);
      });
      byId('topicResourceKeyword').addEventListener('keydown', function(e) {
        if (e.key === 'Enter') {
          e.preventDefault();
          self.searchResources();
        }
      });
      document.querySelectorAll('[data-topic-resource-filter]').forEach(function(btn) {
        btn.addEventListener('click', function() {
          self.topicResourceFilter = btn.getAttribute('data-topic-resource-filter') || 'all';
          self.renderResourceFilterBar();
          self.renderSearchResults(self.topicResourceResults);
        });
        btn.addEventListener('keydown', function(e) { self.handleResourceFilterKeydown(e, btn); });
      });
      byId('topicTaskForm').addEventListener('submit', function(e) {
        e.preventDefault();
        self.saveTask();
      });
      this.bindIfPresent('topicTaskDeleteBtn', 'click', function() {
        if (self.editingTopicTask) self.deleteTask(self.editingTopicTask);
      });
      document.querySelectorAll('[data-close-modal]').forEach(function(el) {
        el.addEventListener('click', function(e) {
          if (el.classList.contains('asset-modal-backdrop') && e.target !== el) return;
          self.closeModal(el.getAttribute('data-close-modal'));
        });
      });
      document.querySelectorAll('[data-summary-restore]').forEach(function(el) {
        el.addEventListener('click', function(e) {
          if (el.classList.contains('asset-modal-backdrop') && e.target !== el) return;
          self.restoreTopicSummaryEditor();
        });
      });
      document.querySelectorAll('[data-topic-detail-tab]').forEach(function(tab) {
        tab.addEventListener('click', function() { self.switchDetailTab(tab.getAttribute('data-topic-detail-tab')); });
        tab.addEventListener('keydown', function(e) { self.handleDetailTabKeydown(e, tab); });
      });
      this.bindOverviewStatTabs();
      this.bindIfPresent('topicDetailSearchBtn', 'click', function() { self.searchActiveDetailTab(); });
      this.bindIfPresent('topicDetailSearchInput', 'keydown', function(e) {
        if (e.key === 'Enter') {
          e.preventDefault();
          self.searchActiveDetailTab();
        }
      });
      this.bindIfPresent('topicDetailSearchInput', 'input', function() {
        clearTimeout(self.topicDetailSearchTimer);
        self.topicDetailSearchTimer = setTimeout(function() {
          self.searchActiveDetailTab();
        }, 180);
      });
      document.addEventListener('keydown', function(e) {
        if (e.key !== 'Escape') return;
        var openModal = document.querySelector('.asset-modal-backdrop.open');
        if (openModal && openModal.id) {
          self.closeModal(openModal.id);
          return;
        }
        self.closeMobileTopicSheet();
      });
      window.addEventListener('resize', function() {
        if (!self.isMobileTopicLayout()) self.closeMobileTopicSheet(false);
        self.updateTopicStickyControls();
      });
      window.addEventListener('scroll', this.updateTopicStickyControls);
      window.addEventListener('resize', this.updateTopicStickyControls);
      window.addEventListener('scroll', function() { self.scheduleTopicFabPositionUpdate(); }, { passive: true });
      window.addEventListener('resize', function() { self.scheduleTopicFabPositionUpdate(); });
      if (window.visualViewport) {
        window.visualViewport.addEventListener('resize', function() { self.scheduleTopicFabPositionUpdate(); });
        window.visualViewport.addEventListener('scroll', function() { self.scheduleTopicFabPositionUpdate(); });
      }
      this.closeMobileTopicSheet(false);
      this.updateTopicFabFooterOffset();
    },

    updateTopicStickyControls: function() {
      var controls = document.querySelector('.topic-detail-sticky-controls');
      if (!controls || !window.getComputedStyle) return;
      var style = window.getComputedStyle(controls);
      if (!style || style.position !== 'sticky') {
        controls.classList.remove('is-stuck');
        return;
      }
      var stickyTop = parseFloat(style.top) || 0;
      var rect = controls.getBoundingClientRect();
      controls.classList.toggle('is-stuck', rect.top <= stickyTop + 1);
    },

    isMobileTopicLayout: function() {
      return window.matchMedia('(max-width: 980px)').matches;
    },

    scheduleTopicFabPositionUpdate: function() {
      if (this.topicFabPositionFrame) return;
      var self = this;
      this.topicFabPositionFrame = window.requestAnimationFrame(function() {
        self.topicFabPositionFrame = 0;
        self.updateTopicFabFooterOffset();
      });
    },

    updateTopicFabFooterOffset: function() {
      var fab = byId('topicFabBtn');
      if (!fab) return;
      var offset = 0;
      var footer = document.querySelector('body > footer');
      if (footer && this.isMobileTopicLayout()) {
        var rect = footer.getBoundingClientRect();
        var viewport = window.visualViewport;
        var viewportTop = viewport ? viewport.offsetTop : 0;
        var viewportBottom = viewportTop + (viewport ? viewport.height : window.innerHeight);
        offset = Math.max(0, Math.min(rect.bottom, viewportBottom) - Math.max(rect.top, viewportTop));
      }
      fab.style.setProperty('--topic-fab-footer-offset', Math.ceil(offset) + 'px');
    },

    openMobileTopicSheet: function() {
      if (!this.isMobileTopicLayout()) return;
      this.mobileTopicSheetReturnFocus = document.activeElement;
      document.body.classList.add('topic-mobile-topic-open');
      var backdrop = byId('topicMobileTopicBackdrop');
      var rail = document.querySelector('.topic-rail');
      var trigger = byId('topicMobileSidebarBtn');
      if (backdrop) backdrop.classList.remove('hidden');
      if (trigger) trigger.setAttribute('aria-expanded', 'true');
      if (window.BookStarkScrollLock) BookStarkScrollLock.lock('topic-mobile-rail');
      if (rail) {
        rail.setAttribute('aria-hidden', 'false');
        rail.setAttribute('role', 'dialog');
        rail.setAttribute('aria-modal', 'true');
      }
      this.updateTopicFab();
      setTimeout(function() {
        var close = byId('topicMobileRailCloseBtn');
        if (close) close.focus();
      }, 30);
    },

    closeMobileTopicSheet: function(restoreFocus) {
      document.body.classList.remove('topic-mobile-topic-open');
      var backdrop = byId('topicMobileTopicBackdrop');
      var rail = document.querySelector('.topic-rail');
      var trigger = byId('topicMobileSidebarBtn');
      if (backdrop) backdrop.classList.add('hidden');
      if (trigger) trigger.setAttribute('aria-expanded', 'false');
      if (window.BookStarkScrollLock) BookStarkScrollLock.unlock('topic-mobile-rail');
      if (rail) {
        rail.setAttribute('aria-hidden', this.isMobileTopicLayout() ? 'true' : 'false');
        if (this.isMobileTopicLayout()) {
          rail.setAttribute('role', 'dialog');
          rail.setAttribute('aria-modal', 'true');
        } else {
          rail.removeAttribute('role');
          rail.removeAttribute('aria-modal');
        }
      }
      var returnFocus = this.mobileTopicSheetReturnFocus;
      var button = returnFocus && returnFocus !== document.body && returnFocus !== document.documentElement && document.contains(returnFocus) ? returnFocus : trigger;
      if (restoreFocus !== false && button && this.isMobileTopicLayout()) button.focus();
      this.updateTopicFab();
      this.updateTopicDetailCreateButton();
    },

    updateTopicDetailCreateButton: function() {
      var btn = byId('topicDetailCreateBtn');
      if (!btn) return;
      var label = t('topic.new', 'New topic');
      if (this.selectedId && this.activeDetailTab === 'resources') {
        label = t('topic.item.add', 'Add material');
      } else if (this.selectedId && this.activeDetailTab === 'summaries') {
        label = t('topic.summary.write', 'Write summary');
      } else if (this.selectedId && this.activeDetailTab === 'tasks') {
        label = t('topic.task.add', 'Add todo');
      }
      btn.setAttribute('aria-label', label);
      btn.setAttribute('title', label);
    },

    updateTopicFab: function() {
      var fab = byId('topicFabBtn');
      if (!fab) return;
      var icon = fab.querySelector('i');
      var label = t('topic.new', 'New topic');
      var iconClass = 'fa-solid fa-plus';
      if (this.selectedId && this.activeDetailTab === 'details') {
        fab.classList.add('hidden');
        return;
      }
      fab.classList.remove('hidden');

      if (this.selectedId && this.activeDetailTab === 'resources') {
        label = t('topic.item.add', 'Add material');
      } else if (this.selectedId && this.activeDetailTab === 'summaries') {
        label = t('topic.summary.write', 'Write summary');
      } else if (this.selectedId && this.activeDetailTab === 'tasks') {
        label = t('topic.task.add', 'Add todo');
      }

      fab.setAttribute('aria-label', label);
      fab.setAttribute('title', label);
      if (icon) icon.className = iconClass;
    },

    handleTopicFabAction: function() {
      if (!this.selectedId) {
        this.openCreateModal();
        return;
      }
      switch (this.activeDetailTab) {
        case 'resources':
          this.openItemModal();
          break;
        case 'summaries':
          this.openNewSummaryEditor();
          break;
        case 'tasks':
          this.openTaskModal();
          break;
        default:
          this.openCreateModal();
      }
    },

    initSummaryComposer: function() {
      var self = this;
      var host = byId('topicSummaryComposer');
      if (!host) return;
      var placeholder = host.getAttribute('data-placeholder') || t('topic.summary.editor.placeholder', 'Record a stage summary');
      if (window.MarkdownComposer) {
        this.topicSummaryComposer = window.MarkdownComposer.create(host, {
          placeholder: placeholder,
          ariaLabel: placeholder,
          minHeight: 162,
          maxHeight: 320,
          submitOnCtrlEnter: true,
          onChange: function(value) {
            if (!String(value || '').trim()) self.setSummaryDraftType('manual');
            self.updateTopicSummaryPreview();
          },
          onSubmit: function() { self.saveInlineSummary(); },
          onPasteFile: function(file) { self.uploadTopicSummaryImageFile(file); }
        });
      } else {
        host.innerHTML = '<textarea class="md-composer-fallback" aria-label="' + attr(placeholder) + '" placeholder="' + attr(placeholder) + '"></textarea>';
        var textarea = host.querySelector('textarea');
        textarea.addEventListener('input', function() {
          if (!textarea.value.trim()) self.setSummaryDraftType('manual');
        });
        textarea.addEventListener('keydown', function(e) {
          if ((e.ctrlKey || e.metaKey) && e.key === 'Enter') {
            e.preventDefault();
            self.saveInlineSummary();
          }
        });
        this.topicSummaryComposer = {
          getValue: function() { return textarea.value; },
          setValue: function(value) { textarea.value = value == null ? '' : String(value); },
          insertAtCursor: function(text) {
            var start = textarea.selectionStart || 0;
            var end = textarea.selectionEnd || 0;
            textarea.value = textarea.value.slice(0, start) + text + textarea.value.slice(end);
            textarea.selectionStart = textarea.selectionEnd = start + String(text || '').length;
            textarea.focus();
          },
          clear: function() { textarea.value = ''; },
          focus: function() { textarea.focus(); }
        };
      }
      this.setSummaryDraftType('manual');
      this.updateSummarySubmitLabel();
    },

    initTopicCommentComposer: function() {
      var self = this;
      var host = byId('topicCommentComposer');
      if (!host) return;
      var mobileModal = byId('topicMobileCommentsModal');
      if (mobileModal && mobileModal.parentElement !== document.body) {
        document.body.appendChild(mobileModal);
      }
      var placeholder = host.getAttribute('data-placeholder') || t('topic.comment.placeholder', 'Write a comment with Markdown');
      function fallbackComposer(textarea) {
        return {
          getValue: function() { return textarea.value; },
          setValue: function(value) {
            textarea.value = value == null ? '' : String(value);
            textarea.dispatchEvent(new Event('input', { bubbles: true }));
          },
          insertAtCursor: function(text) {
            var start = textarea.selectionStart || 0;
            var end = textarea.selectionEnd || 0;
            textarea.value = textarea.value.slice(0, start) + text + textarea.value.slice(end);
            textarea.selectionStart = textarea.selectionEnd = start + String(text || '').length;
            textarea.focus();
            textarea.dispatchEvent(new Event('input', { bubbles: true }));
          },
          clear: function() {
            textarea.value = '';
            textarea.dispatchEvent(new Event('input', { bubbles: true }));
          },
          focus: function() { textarea.focus(); },
          getSelectionRange: function() {
            return { from: textarea.selectionStart || 0, to: textarea.selectionEnd || 0 };
          },
          replaceRange: function(from, to, text) {
            textarea.value = textarea.value.slice(0, from) + text + textarea.value.slice(to);
            var next = from + String(text || '').length;
            textarea.selectionStart = textarea.selectionEnd = next;
            textarea.dispatchEvent(new Event('input', { bubbles: true }));
            return next;
          }
        };
      }
      if (window.MarkdownComposer) {
        this.topicCommentComposer = window.MarkdownComposer.create(host, {
          placeholder: placeholder,
          ariaLabel: placeholder,
          minHeight: 76,
          maxHeight: 220,
          submitOnCtrlEnter: true,
          onChange: function() { self.updateTopicCommentPreview(); },
          onSubmit: function() { self.saveTopicComment(); },
          onPasteFile: function(file) { self.uploadTopicCommentImageFile(file); }
        });
      } else {
        host.innerHTML = '<textarea class="md-composer-fallback" aria-label="' + attr(placeholder) + '" placeholder="' + attr(placeholder) + '"></textarea>';
        var textarea = host.querySelector('textarea');
        textarea.addEventListener('input', function() { self.updateTopicCommentPreview(); });
        textarea.addEventListener('keydown', function(e) {
          if ((e.ctrlKey || e.metaKey) && e.key === 'Enter') {
            e.preventDefault();
            self.saveTopicComment();
          }
        });
        this.topicCommentComposer = fallbackComposer(textarea);
      }
      this.moveTopicCommentPanel(false);
    },

    initTopicQuestionComposer: function() {
      var self = this;
      var host = byId('editTopicQuestion');
      if (!host) return;
      var placeholder = host.getAttribute('data-placeholder') || t('topic.question.placeholder', 'Core question');
      if (window.MarkdownComposer) {
        this.topicQuestionComposer = window.MarkdownComposer.create(host, {
          placeholder: placeholder,
          ariaLabel: placeholder,
          minHeight: 260,
          maxHeight: 520,
          onChange: function() { self.updateTopicQuestionPreview(); },
          onPasteFile: function(file) { self.uploadTopicQuestionImageFile(file); }
        });
        return;
      }
      host.innerHTML = '<textarea class="md-composer-fallback" aria-label="' + attr(placeholder) + '" placeholder="' + attr(placeholder) + '"></textarea>';
      var textarea = host.querySelector('textarea');
      textarea.addEventListener('input', function() { self.updateTopicQuestionPreview(); });
      this.topicQuestionComposer = {
        getValue: function() { return textarea.value; },
        setValue: function(value) { textarea.value = value == null ? '' : String(value); },
        insertAtCursor: function(text) {
          var start = textarea.selectionStart || 0;
          var end = textarea.selectionEnd || 0;
          textarea.value = textarea.value.slice(0, start) + text + textarea.value.slice(end);
          textarea.selectionStart = textarea.selectionEnd = start + String(text || '').length;
          textarea.focus();
          textarea.dispatchEvent(new Event('input', { bubbles: true }));
        },
        clear: function() { textarea.value = ''; textarea.dispatchEvent(new Event('input', { bubbles: true })); },
        focus: function() { textarea.focus(); }
      };
    },

    getTopicQuestionValue: function() {
      if (this.topicQuestionComposer && this.topicQuestionComposer.getValue) {
        return this.topicQuestionComposer.getValue();
      }
      var host = byId('editTopicQuestion');
      var fallback = host ? host.querySelector('textarea') : null;
      return fallback ? fallback.value : '';
    },

    setTopicQuestionValue: function(value) {
      var nextValue = value == null ? '' : String(value);
      if (this.topicQuestionComposer && this.topicQuestionComposer.setValue) {
        this.topicQuestionComposer.setValue(nextValue);
      } else {
        var host = byId('editTopicQuestion');
        var fallback = host ? host.querySelector('textarea') : null;
        if (fallback) fallback.value = nextValue;
      }
      this.updateTopicQuestionPreview(true);
    },

    hideTopicQuestionPreview: function() {
      var preview = byId('topicEditQuestionPreview');
      var host = byId('editTopicQuestion');
      var button = byId('topicEditQuestionPreviewBtn');
      this.topicQuestionPreviewing = false;
      if (preview) preview.classList.add('hidden');
      if (host) host.style.display = '';
      if (button) {
        button.classList.remove('active');
        button.innerHTML = '<i class="fa-solid fa-file-lines"></i>';
      }
    },

    toggleTopicQuestionPreview: function() {
      var preview = byId('topicEditQuestionPreview');
      var host = byId('editTopicQuestion');
      var button = byId('topicEditQuestionPreviewBtn');
      if (!preview || !host || !button) return;
      this.topicQuestionPreviewing = !this.topicQuestionPreviewing;
      if (this.topicQuestionPreviewing) {
        this.updateTopicQuestionPreview(true);
        preview.classList.remove('hidden');
        host.style.display = 'none';
        button.classList.add('active');
        button.innerHTML = '<i class="fa-solid fa-pen"></i>';
      } else {
        this.hideTopicQuestionPreview();
      }
    },

    updateTopicQuestionPreview: function(force) {
      var preview = byId('topicEditQuestionPreview');
      if (!preview || (!force && !this.topicQuestionPreviewing)) return;
      var text = this.getTopicQuestionValue().trim();
      preview.innerHTML = text ? this.renderMarkdown(text) : '';
    },

    clearTopicQuestionEditor: function() {
      if (this.topicQuestionComposer && this.topicQuestionComposer.clear) {
        this.topicQuestionComposer.clear();
      } else {
        this.setTopicQuestionValue('');
      }
      this.updateTopicQuestionPreview(true);
    },

    insertTopicQuestionMarkdownImage: function(filename, url) {
      if (!this.topicQuestionComposer || !this.topicQuestionComposer.insertAtCursor || !url) return;
      if (this.topicQuestionPreviewing) this.toggleTopicQuestionPreview();
      var name = String(filename || 'image').replace(/\.[^.]+$/, '') || 'image';
      this.topicQuestionComposer.insertAtCursor('![' + name + '](' + url + ')');
    },

    insertTopicSummaryMarkdownImage: function(filename, url) {
      if (!this.topicSummaryComposer || !this.topicSummaryComposer.insertAtCursor || !url) return;
      if (this.topicSummaryPreviewing) this.toggleTopicSummaryPreview();
      var name = String(filename || 'image').replace(/\.[^.]+$/, '') || 'image';
      this.topicSummaryComposer.insertAtCursor('![' + name + '](' + url + ')');
      this.updateTopicSummaryPreview();
    },

    uploadTopicQuestionImageFile: function(file) {
      var self = this;
      if (!file || !file.type || file.type.indexOf('image/') !== 0) {
        toast(t('topic.toast.select_image', 'Choose an image file'), 'warning');
        return;
      }
      var formData = new FormData();
      formData.append('file', file);
      formData.append('category', 'topic');
      csrfFetch('/api/uploads', {
        method: 'POST',
        body: formData
      }).then(function(res) {
        if (!res.ok) throw new Error('HTTP ' + res.status);
        return res.json();
      }).then(function(res) {
        if (res && res.code === 0 && res.data && res.data.url) {
          self.insertTopicQuestionMarkdownImage(file.name, res.data.url);
          toast(t('topic.toast.image_inserted', 'Image inserted'), 'success');
          return;
        }
        toast((res && res.message) || t('topic.toast.image_upload_failed', 'Image upload failed'), 'error');
      }).catch(function() {
        toast(t('topic.toast.image_upload_failed', 'Image upload failed'), 'error');
      });
    },

    uploadTopicSummaryImageFile: function(file) {
      var self = this;
      if (!file || !file.type || file.type.indexOf('image/') !== 0) {
        toast(t('topic.toast.select_image', 'Choose an image file'), 'warning');
        return;
      }
      var formData = new FormData();
      formData.append('file', file);
      formData.append('category', 'topic');
      csrfFetch('/api/uploads', {
        method: 'POST',
        body: formData
      }).then(function(res) {
        if (!res.ok) throw new Error('HTTP ' + res.status);
        return res.json();
      }).then(function(res) {
        if (res && res.code === 0 && res.data && res.data.url) {
          self.insertTopicSummaryMarkdownImage(file.name, res.data.url);
          toast(t('topic.toast.image_inserted', 'Image inserted'), 'success');
          return;
        }
        toast((res && res.message) || t('topic.toast.image_upload_failed', 'Image upload failed'), 'error');
      }).catch(function() {
        toast(t('topic.toast.image_upload_failed', 'Image upload failed'), 'error');
      });
    },

    uploadTopicCommentImageFile: function(file) {
      var self = this;
      if (!file || !file.type || file.type.indexOf('image/') !== 0) {
        toast(t('topic.toast.select_image', 'Choose an image file'), 'warning');
        return;
      }
      var formData = new FormData();
      formData.append('file', file);
      formData.append('category', 'topic');
      csrfFetch('/api/uploads', { method: 'POST', body: formData })
        .then(function(res) {
          if (!res.ok) throw new Error('HTTP ' + res.status);
          return res.json();
        })
        .then(function(res) {
          if (!res || res.code !== 0 || !res.data || !res.data.url) {
            throw new Error((res && res.message) || t('topic.toast.image_upload_failed', 'Image upload failed'));
          }
          if (self.topicCommentPreviewing) self.toggleTopicCommentPreview();
          var name = String(file.name || 'image').replace(/\.[^.]+$/, '') || 'image';
          self.topicCommentComposer.insertAtCursor('![' + name + '](' + res.data.url + ')');
          toast(t('topic.toast.image_inserted', 'Image inserted'), 'success');
        })
        .catch(function(err) {
          toast(err.message || t('topic.toast.image_upload_failed', 'Image upload failed'), 'error');
        });
    },

    topicEmojiCategories: function() {
      return [
        { label: t('topic.emoji.common', 'Common'), icons: ['⭐','📌','🔥','💡','✅','❌','⚠️','🎯','📎','🔗','💎','🏷️','📦','🔧','📊','🎨','🚀','💬','📝','🔔','❤️','👍','🎉','⏰','📚','🔍','💰','🌟','🎵','🌈','☁️','⚡'] },
        { label: t('topic.emoji.face', 'Faces'), icons: ['😀','😃','😄','😁','😆','😅','🤣','😂','🙂','😉','😊','😇','🥰','😍','🤩','😘','😋','😛','😜','🤪','🤗','🤭','🤫','🤔','😐','😑','😶','😏','🙄','😬','😌','😔','😪','🤤','😴','🥳','😎','🤓','🧐','😟','😕','😮','😳','🥺','😢','😭','😱','😤','😡','🤬','🤯','🤖','👻','💀'] },
        { label: t('topic.emoji.gesture', 'Gestures'), icons: ['👋','🤚','🖐️','✋','🖖','👌','🤌','🤏','✌️','🤞','🤟','🤘','🤙','👈','👉','👆','👇','☝️','👍','👎','✊','👊','🤛','🤜','👏','🙌','👐','🤲','🤝','🙏','💪'] },
        { label: t('topic.emoji.symbol', 'Symbols'), icons: ['❤️','🧡','💛','💚','💙','💜','🖤','🤍','🤎','💔','💕','💞','💓','💗','💖','💘','☮️','☯️','❗','❓','‼️','⁉️','⚠️','♻️','✅','❎','🌐','💤','🆗','🆕','🆓','▶️','⏸️','⏹️','➡️','⬅️','⬆️','⬇️','➕','➖','➗','✖️','✔️','☑️','🔴','🟠','🟡','🟢','🔵','🟣','⚫','⚪','🔔','📣'] }
      ];
    },

    hideTopicSummaryEmojiPicker: function() {
      if (this.topicEmojiPicker) {
        this.topicEmojiPicker.remove();
        this.topicEmojiPicker = null;
      }
      if (this.topicEmojiOutsideHandler) {
        document.removeEventListener('click', this.topicEmojiOutsideHandler, true);
        this.topicEmojiOutsideHandler = null;
      }
      var button = byId('topicSummaryEmojiButton');
      if (button) {
        button.classList.remove('active');
        button.setAttribute('aria-expanded', 'false');
      }
    },

    hideTopicCommentEmojiPicker: function() {
      if (this.topicCommentEmojiPicker) {
        this.topicCommentEmojiPicker.remove();
        this.topicCommentEmojiPicker = null;
      }
      if (this.topicCommentEmojiOutsideHandler) {
        document.removeEventListener('click', this.topicCommentEmojiOutsideHandler, true);
        this.topicCommentEmojiOutsideHandler = null;
      }
      var button = byId('topicCommentEmojiButton');
      if (button) {
        button.classList.remove('active');
        button.setAttribute('aria-expanded', 'false');
      }
    },

    toggleTopicCommentEmojiPicker: function() {
      var button = byId('topicCommentEmojiButton');
      var composer = this.topicCommentComposer;
      if (!button || !composer || !composer.insertAtCursor) return;
      if (this.topicCommentEmojiPicker) {
        this.hideTopicCommentEmojiPicker();
        return;
      }
      var self = this;
      var picker = document.createElement('div');
      picker.className = 'topic-emoji-picker';
      picker.setAttribute('role', 'menu');
      picker.setAttribute('aria-label', t('topic.summary.emoji', 'Emoji'));
      var tabBar = document.createElement('div');
      tabBar.className = 'topic-emoji-tab-bar';
      var grid = document.createElement('div');
      grid.className = 'topic-emoji-grid';
      var categories = this.topicEmojiCategories();
      function renderCategory(index) {
        tabBar.querySelectorAll('.topic-emoji-tab').forEach(function(tab, i) {
          tab.classList.toggle('active', i === index);
        });
        grid.innerHTML = '';
        categories[index].icons.forEach(function(emoji) {
          var item = document.createElement('button');
          item.type = 'button';
          item.className = 'topic-emoji-item';
          item.textContent = emoji;
          item.setAttribute('role', 'menuitem');
          item.addEventListener('click', function(e) {
            e.preventDefault();
            e.stopPropagation();
            if (self.topicCommentPreviewing) self.toggleTopicCommentPreview();
            composer.insertAtCursor(emoji);
            self.hideTopicCommentEmojiPicker();
          });
          grid.appendChild(item);
        });
      }
      categories.forEach(function(category, index) {
        var tab = document.createElement('button');
        tab.type = 'button';
        tab.className = 'topic-emoji-tab';
        tab.textContent = category.label;
        tab.addEventListener('click', function(e) {
          e.preventDefault();
          e.stopPropagation();
          renderCategory(index);
        });
        tabBar.appendChild(tab);
      });
      picker.appendChild(tabBar);
      picker.appendChild(grid);
      document.body.appendChild(picker);
      var rect = button.getBoundingClientRect();
      var pickerRect = picker.getBoundingClientRect();
      picker.style.left = Math.max(8, Math.min(window.innerWidth - pickerRect.width - 8, rect.left)) + 'px';
      var top = rect.bottom + 8;
      if (top + pickerRect.height > window.innerHeight - 8) top = Math.max(8, rect.top - pickerRect.height - 8);
      picker.style.top = top + 'px';
      button.classList.add('active');
      button.setAttribute('aria-expanded', 'true');
      renderCategory(0);
      this.topicCommentEmojiPicker = picker;
      this.topicCommentEmojiOutsideHandler = function(e) {
        if (picker.contains(e.target) || button.contains(e.target)) return;
        self.hideTopicCommentEmojiPicker();
      };
      setTimeout(function() {
        document.addEventListener('click', self.topicCommentEmojiOutsideHandler, true);
      }, 0);
    },

    hideTopicQuestionEmojiPicker: function() {
      if (this.topicQuestionEmojiPicker) {
        this.topicQuestionEmojiPicker.remove();
        this.topicQuestionEmojiPicker = null;
      }
      if (this.topicQuestionEmojiOutsideHandler) {
        document.removeEventListener('click', this.topicQuestionEmojiOutsideHandler, true);
        this.topicQuestionEmojiOutsideHandler = null;
      }
      var button = byId('topicEditQuestionEmojiBtn');
      if (button) {
        button.classList.remove('active');
        button.setAttribute('aria-expanded', 'false');
      }
    },

    toggleTopicQuestionEmojiPicker: function() {
      var button = byId('topicEditQuestionEmojiBtn');
      var composer = this.topicQuestionComposer;
      if (!button || !composer || !composer.insertAtCursor) return;
      if (this.topicQuestionEmojiPicker) {
        this.hideTopicQuestionEmojiPicker();
        return;
      }
      var self = this;
      var picker = document.createElement('div');
      picker.className = 'topic-emoji-picker';
      picker.setAttribute('role', 'menu');
      picker.setAttribute('aria-label', t('topic.summary.emoji', 'Emoji'));
      var tabBar = document.createElement('div');
      tabBar.className = 'topic-emoji-tab-bar';
      var grid = document.createElement('div');
      grid.className = 'topic-emoji-grid';
      var categories = this.topicEmojiCategories();

      function renderCategory(index) {
        tabBar.querySelectorAll('.topic-emoji-tab').forEach(function(tab, i) {
          tab.classList.toggle('active', i === index);
        });
        grid.innerHTML = '';
        categories[index].icons.forEach(function(emoji) {
          var item = document.createElement('button');
          item.type = 'button';
          item.className = 'topic-emoji-item';
          item.textContent = emoji;
          item.title = emoji;
          item.setAttribute('role', 'menuitem');
          item.setAttribute('aria-label', emoji);
          item.addEventListener('click', function(e) {
            e.preventDefault();
            e.stopPropagation();
            if (self.topicQuestionPreviewing) self.toggleTopicQuestionPreview();
            composer.insertAtCursor(emoji);
            self.hideTopicQuestionEmojiPicker();
          });
          grid.appendChild(item);
        });
      }

      categories.forEach(function(category, index) {
        var tab = document.createElement('button');
        tab.type = 'button';
        tab.className = 'topic-emoji-tab';
        tab.textContent = category.label;
        tab.addEventListener('click', function(e) {
          e.preventDefault();
          e.stopPropagation();
          renderCategory(index);
        });
        tabBar.appendChild(tab);
      });

      picker.appendChild(tabBar);
      picker.appendChild(grid);
      document.body.appendChild(picker);
      var rect = button.getBoundingClientRect();
      var pickerRect = picker.getBoundingClientRect();
      var left = Math.max(8, Math.min(window.innerWidth - pickerRect.width - 8, rect.left));
      var top = rect.bottom + 8;
      if (top + pickerRect.height > window.innerHeight - 8) {
        top = Math.max(8, rect.top - pickerRect.height - 8);
      }
      picker.style.left = left + 'px';
      picker.style.top = top + 'px';
      button.classList.add('active');
      button.setAttribute('aria-expanded', 'true');
      renderCategory(0);
      this.topicQuestionEmojiPicker = picker;
      this.topicQuestionEmojiOutsideHandler = function(e) {
        if (picker.contains(e.target) || button.contains(e.target)) return;
        self.hideTopicQuestionEmojiPicker();
      };
      setTimeout(function() {
        document.addEventListener('click', self.topicQuestionEmojiOutsideHandler, true);
      }, 0);
    },

    toggleTopicSummaryEmojiPicker: function() {
      var button = byId('topicSummaryEmojiButton');
      var composer = this.topicSummaryComposer;
      if (!button || !composer || !composer.insertAtCursor) return;
      if (this.topicEmojiPicker) {
        this.hideTopicSummaryEmojiPicker();
        return;
      }
      var self = this;
      var picker = document.createElement('div');
      picker.className = 'topic-emoji-picker';
      picker.setAttribute('role', 'menu');
      picker.setAttribute('aria-label', t('topic.summary.emoji', 'Emoji'));
      var tabBar = document.createElement('div');
      tabBar.className = 'topic-emoji-tab-bar';
      var grid = document.createElement('div');
      grid.className = 'topic-emoji-grid';
      var categories = this.topicEmojiCategories();

      function renderCategory(index) {
        tabBar.querySelectorAll('.topic-emoji-tab').forEach(function(tab, i) {
          tab.classList.toggle('active', i === index);
        });
        grid.innerHTML = '';
        categories[index].icons.forEach(function(emoji) {
          var item = document.createElement('button');
          item.type = 'button';
          item.className = 'topic-emoji-item';
          item.textContent = emoji;
          item.title = emoji;
          item.setAttribute('role', 'menuitem');
          item.setAttribute('aria-label', emoji);
          item.addEventListener('click', function(e) {
            e.preventDefault();
            e.stopPropagation();
            if (self.topicSummaryPreviewing) self.toggleTopicSummaryPreview();
            composer.insertAtCursor(emoji);
            self.hideTopicSummaryEmojiPicker();
          });
          grid.appendChild(item);
        });
      }

      categories.forEach(function(category, index) {
        var tab = document.createElement('button');
        tab.type = 'button';
        tab.className = 'topic-emoji-tab';
        tab.textContent = category.label;
        tab.addEventListener('click', function(e) {
          e.preventDefault();
          e.stopPropagation();
          renderCategory(index);
        });
        tabBar.appendChild(tab);
      });

      picker.appendChild(tabBar);
      picker.appendChild(grid);
      document.body.appendChild(picker);
      var rect = button.getBoundingClientRect();
      var pickerRect = picker.getBoundingClientRect();
      var left = Math.max(8, Math.min(window.innerWidth - pickerRect.width - 8, rect.left));
      var top = rect.bottom + 8;
      if (top + pickerRect.height > window.innerHeight - 8) {
        top = Math.max(8, rect.top - pickerRect.height - 8);
      }
      picker.style.left = left + 'px';
      picker.style.top = top + 'px';
      button.classList.add('active');
      button.setAttribute('aria-expanded', 'true');
      renderCategory(0);
      this.topicEmojiPicker = picker;
      this.topicEmojiOutsideHandler = function(e) {
        if (picker.contains(e.target) || button.contains(e.target)) return;
        self.hideTopicSummaryEmojiPicker();
      };
      setTimeout(function() {
        document.addEventListener('click', self.topicEmojiOutsideHandler, true);
      }, 0);
    },

    toggleTopicSummaryPreview: function() {
      var preview = byId('topicSummaryPreview');
      var host = byId('topicSummaryComposer');
      var button = byId('topicSummaryPreviewButton');
      if (!preview || !host || !button) return;
      this.topicSummaryPreviewing = !this.topicSummaryPreviewing;
      if (this.topicSummaryPreviewing) {
        this.updateTopicSummaryPreview(true);
        preview.classList.remove('hidden');
        host.style.display = 'none';
        button.classList.add('active');
      } else {
        preview.classList.add('hidden');
        host.style.display = '';
        button.classList.remove('active');
      }
    },

    updateTopicSummaryPreview: function(force) {
      var preview = byId('topicSummaryPreview');
      if (!preview || (!force && !this.topicSummaryPreviewing)) return;
      var text = this.getInlineSummaryValue();
      preview.innerHTML = text ? this.renderMarkdown(text) : '';
    },

    hideTopicCommentPreview: function() {
      var preview = byId('topicCommentPreview');
      var host = byId('topicCommentComposer');
      var button = byId('topicCommentPreviewButton');
      this.topicCommentPreviewing = false;
      if (preview) preview.classList.add('hidden');
      if (host) host.style.display = '';
      if (button) {
        button.classList.remove('active');
        button.innerHTML = '<i class="fa-solid fa-file-lines"></i>';
      }
    },

    toggleTopicCommentPreview: function() {
      var preview = byId('topicCommentPreview');
      var host = byId('topicCommentComposer');
      var button = byId('topicCommentPreviewButton');
      if (!preview || !host || !button) return;
      this.topicCommentPreviewing = !this.topicCommentPreviewing;
      if (this.topicCommentPreviewing) {
        this.updateTopicCommentPreview(true);
        preview.classList.remove('hidden');
        host.style.display = 'none';
        button.classList.add('active');
        button.innerHTML = '<i class="fa-solid fa-pen"></i>';
      } else {
        this.hideTopicCommentPreview();
      }
    },

    updateTopicCommentPreview: function(force) {
      var preview = byId('topicCommentPreview');
      if (!preview || (!force && !this.topicCommentPreviewing)) return;
      var text = this.topicCommentValue();
      preview.innerHTML = text ? this.renderMarkdown(text) : '';
    },

    clearTopicCommentEditor: function() {
      this.resetTopicCommentDraft();
      if (this.topicCommentComposer && this.topicCommentComposer.focus) this.topicCommentComposer.focus();
    },

    openNewSummaryEditor: function() {
      this.clearInlineSummary();
      this.openTopicSummaryEditorModal();
    },

    openTopicSummaryEditorModal: function() {
      var modal = byId('topicSummaryEditorModal');
      var modalDock = byId('topicSummaryModalDock');
      var dock = byId('topicSummaryComposeDock');
      if (!modal || !modalDock || !dock) return;
      this.hideTopicSummaryEmojiPicker();
      if (this.topicSummaryEditorExpanded) return;
      modalDock.appendChild(dock);
      this.openModal('topicSummaryEditorModal');
      this.topicSummaryEditorExpanded = true;
      if (this.topicSummaryComposer && this.topicSummaryComposer.focus) {
        var self = this;
        setTimeout(function() { self.topicSummaryComposer.focus(); }, 30);
      }
    },

    restoreTopicSummaryEditor: function() {
      var modal = byId('topicSummaryEditorModal');
      var host = byId('topicSummaryDockHost');
      var dock = byId('topicSummaryComposeDock');
      if (!modal || !host || !dock) return;
      var clearEditDraft = this.topicSummaryEditorMode === 'edit';
      this.hideTopicSummaryEmojiPicker();
      host.appendChild(dock);
      this.topicSummaryEditorExpanded = false;
      this.topicSummaryEditorMode = 'new';
      if (clearEditDraft) this.clearInlineSummary();
      this.closeModal('topicSummaryEditorModal');
    },

    search: function() {
      this.keyword = byId('topicKeyword').value.trim();
      this.page = 1;
      this.loadTopics();
    },

    loadTopics: async function(options) {
      options = options || {};
      var self = this;
      if (!options.skipSkeleton) this.renderTopicListSkeleton();
      var params = new URLSearchParams();
      params.set('page', this.page);
      params.set('page_size_topics', this.pageSize);
      if (this.keyword) params.set('keyword', this.keyword);
      try {
        var data = await apiJSON('/api/topics?' + params.toString());
        this.topics = data.data || [];
        this.totalItems = data.total || 0;
        this.totalPages = data.total_pages || 1;
        this.renderList(this.totalItems);
        if (this.topics.length) {
          var found = this.topics.some(function(item) { return item.topic_id === self.selectedId; });
          if (this.selectedId && (this.initialTopicId || found)) {
            this.selectTopic(this.selectedId, { scrollDetail: !!this.initialTopicId });
            this.initialTopicId = 0;
          } else {
            this.selectTopic(found ? this.selectedId : this.topics[0].topic_id);
          }
        } else {
          this.selectedId = 0;
          this.detail = null;
          this.renderEmpty();
        }
      } catch (err) {
        byId('topicList').innerHTML = '<div class="topic-empty-list">' + html(err.message) + '</div>';
        toast(err.message, 'error');
      }
    },

    renderList: function(total) {
      var self = this;
      var list = byId('topicList');
      list.classList.toggle('topic-list-empty', !this.topics.length);
      if (!this.topics.length) {
        list.innerHTML = '<div class="topic-empty-list">' + html(t('topic.list.empty', 'No topics yet')) + '</div>';
      } else {
        list.innerHTML = this.topics.map(function(item) {
          var resourceCount = countText(item.resource_count);
          var summaryCount = countText(item.summary_count);
          var taskCount = countText(item.task_count);
          var resourceLabel = t('topic.detail.tab.resources', 'Materials');
          var summaryLabel = t('topic.detail.tab.summaries', 'Summaries');
          var taskLabel = t('topic.detail.tab.tasks', 'Todos');
          var pinnedLabel = item.is_pinned ? '<span class="topic-card-pin-badge"><i class="fa-solid fa-thumbtack" aria-hidden="true"></i>' + html(t('topic.pin', 'Pin')) + '</span>' : '';
          var pinLabel = item.is_pinned ? t('topic.pin.cancel', 'Unpin') : t('topic.pin', 'Pin');
          var stats = '<span class="topic-card-stat" title="' + attr(resourceLabel) + '" aria-label="' + attr(resourceLabel + ' ' + resourceCount) + '"><i class="fa-solid fa-layer-group"></i>' + html(resourceCount) + '</span>' +
            '<span class="topic-card-stat" title="' + attr(summaryLabel) + '" aria-label="' + attr(summaryLabel + ' ' + summaryCount) + '"><i class="fa-solid fa-file-lines"></i>' + html(summaryCount) + '</span>' +
            '<span class="topic-card-stat" title="' + attr(taskLabel) + '" aria-label="' + attr(taskLabel + ' ' + taskCount) + '"><i class="fa-solid fa-list-check"></i>' + html(taskCount) + '</span>';
          return '<div class="topic-list-entry" data-topic-entry-id="' + attr(item.topic_id) + '">' +
            '<div class="topic-card' + (item.topic_id === self.selectedId ? ' selected' : '') + '" role="button" tabindex="0" data-topic-id="' + attr(item.topic_id) + '">' +
            '<div class="topic-card-head"><div class="topic-card-title">' + pinnedLabel + html(item.title) + '</div></div>' +
            '<div class="topic-card-desc">' + html(item.question || t('topic.no_question', 'No question yet')) + '</div>' +
            '<div class="topic-card-meta"><span class="topic-card-actions">' +
            '<button type="button" class="topic-card-tool-btn" data-topic-edit="' + attr(item.topic_id) + '" title="' + attr(t('topic.edit', 'Edit')) + '" aria-label="' + attr(t('topic.overview.edit_aria', 'Edit topic')) + '"><i class="fa-solid fa-pen"></i></button>' +
            '<button type="button" class="topic-card-tool-btn' + (item.is_pinned ? ' is-pinned' : '') + '" data-topic-pin="' + attr(item.topic_id) + '" data-topic-pinned="' + (item.is_pinned ? '1' : '0') + '" title="' + attr(pinLabel) + '" aria-label="' + attr(pinLabel) + '"><i class="fa-solid fa-thumbtack"></i></button>' +
            '</span><span class="topic-card-action-separator" aria-hidden="true"></span><span class="topic-card-stats">' + stats + '</span><span>' + html(formatDateOnly(item.modify_time)) + '</span></div>' +
            '</div><div class="topic-expand" data-topic-expand-id="' + attr(item.topic_id) + '"></div></div>';
        }).join('');
      }
      list.querySelectorAll('[data-topic-id]').forEach(function(card) {
        card.addEventListener('click', function() {
          self.selectTopic(parseInt(card.getAttribute('data-topic-id'), 10));
        });
        card.addEventListener('keydown', function(e) {
          if (e.key !== 'Enter' && e.key !== ' ') return;
          e.preventDefault();
          self.selectTopic(parseInt(card.getAttribute('data-topic-id'), 10));
        });
      });
      list.querySelectorAll('[data-topic-edit]').forEach(function(btn) {
        btn.addEventListener('click', async function(e) {
          e.stopPropagation();
          var id = parseInt(btn.getAttribute('data-topic-edit'), 10);
          await self.openEditModalForTopic(id);
        });
      });
      list.querySelectorAll('[data-topic-pin]').forEach(function(btn) {
        btn.addEventListener('click', function(e) {
          e.stopPropagation();
          var id = parseInt(btn.getAttribute('data-topic-pin'), 10);
          var isPinned = btn.getAttribute('data-topic-pinned') === '1';
          self.toggleTopicPin(id, !isPinned);
        });
      });
      if (typeof renderPagination === 'function') {
        renderPagination('topicPagination', this.page, this.totalPages, function(page) {
          self.page = page;
          self.loadTopics();
        }, { totalItems: total });
      }
    },

    selectTopic: function(id, options) {
      if (!id) return;
      var topicChanged = Number(this.selectedId) !== Number(id);
      if (this.selectedId && topicChanged) {
        this.captureTopicCommentDraft();
        this.clearInlineSummary();
        this.resetTopicDetailFilters();
        this.topicCommentTarget = null;
        this.topicComments = [];
        this.topicCommentLoadToken += 1;
        this.resetTopicCommentDraft({ forget: false });
      }
      this.selectedId = id;
      if (topicChanged) this.setTopicCommentScope('current', { force: true });
      document.querySelectorAll('.topic-card').forEach(function(card) {
        card.classList.toggle('selected', parseInt(card.getAttribute('data-topic-id'), 10) === id);
      });
      this.loadDetail(id, options || {});
    },

    loadDetail: async function(id, options) {
      options = options || {};
      var loadToken = ++this.topicDetailLoadToken;
      if (!options.silent) this.renderTopicDetailSkeleton();
      try {
        var data = await apiJSON('/api/topics/' + encodeURIComponent(id));
        if (loadToken !== this.topicDetailLoadToken || Number(id) !== Number(this.selectedId)) return;
        this.detail = data.data;
        if (options.syncList !== false) this.syncSelectedTopicListItemFromDetail();
        this.renderDetail();
        if (options && options.scrollDetail && window.matchMedia('(max-width: 980px)').matches) {
          var detail = document.querySelector('.topic-detail');
          if (detail && detail.scrollIntoView) {
            requestAnimationFrame(function() {
              detail.scrollIntoView({ behavior: 'smooth', block: 'start' });
            });
          }
        }
      } catch (err) {
        if (loadToken !== this.topicDetailLoadToken || Number(id) !== Number(this.selectedId)) return;
        toast(err.message, 'error');
      }
    },

    refreshSelectedTopic: async function(options) {
      if (!this.selectedId) return;
      options = options || {};
      if (options.silent === undefined) options.silent = true;
      await this.loadDetail(this.selectedId, options);
    },

    sortTopicsInPlace: function() {
      this.topics.sort(function(a, b) {
        var ap = a && a.is_pinned ? 1 : 0;
        var bp = b && b.is_pinned ? 1 : 0;
        if (ap !== bp) return bp - ap;
        var am = String((a && a.modify_time) || '');
        var bm = String((b && b.modify_time) || '');
        if (am !== bm) return bm.localeCompare(am);
        return Number((b && b.topic_id) || 0) - Number((a && a.topic_id) || 0);
      });
    },

    upsertTopicListItem: function(topic, options) {
      if (!topic || !topic.topic_id) return;
      options = options || {};
      var existing = -1;
      for (var i = 0; i < this.topics.length; i++) {
        if (this.topics[i].topic_id === topic.topic_id) {
          existing = i;
          break;
        }
      }
      var current = existing >= 0 ? this.topics[existing] : {};
      var next = Object.assign({}, current, topic);
      if (next.resource_count === undefined) next.resource_count = current.resource_count || 0;
      if (next.summary_count === undefined) next.summary_count = current.summary_count || 0;
      if (next.task_count === undefined) next.task_count = current.task_count || 0;
      if (existing >= 0) {
        this.topics[existing] = next;
      } else {
        this.topics.unshift(next);
        this.totalItems += 1;
      }
      if (options.sort !== false) this.sortTopicsInPlace();
      this.renderList(this.totalItems);
    },

    removeTopicListItem: function(topicId) {
      var before = this.topics.length;
      this.topics = this.topics.filter(function(item) { return item.topic_id !== topicId; });
      if (this.topics.length !== before && this.totalItems > 0) this.totalItems -= 1;
      this.renderList(this.totalItems);
    },

    syncSelectedTopicListItemFromDetail: function() {
      var detail = this.detail || {};
      var topic = Object.assign({}, detail.topic || {});
      if (!topic.topic_id) return;
      var stats = detail.stats || {};
      topic.resource_count = stats.resource_count !== undefined ? stats.resource_count : (detail.resources || []).length;
      topic.summary_count = stats.summary_count !== undefined ? stats.summary_count : (detail.summaries || []).length;
      topic.task_count = stats.task_count !== undefined ? stats.task_count : (detail.tasks || []).length;
      this.upsertTopicListItem(topic);
    },

    renderEmpty: function() {
      byId('topicEmptyState').classList.remove('hidden');
      byId('topicDetailContent').classList.add('hidden');
      this.resetTopicDetailFilters();
      this.clearMobileExpansion();
      this.updateTopicFab();
    },

    renderDetail: function() {
      var detail = this.detail || {};
      var topic = detail.topic || {};
      byId('topicEmptyState').classList.add('hidden');
      byId('topicDetailContent').classList.remove('hidden');
      byId('topicReadTitle').textContent = topic.title || '';
      byId('topicReadQuestion').innerHTML = multiline(topic.question, t('topic.no_question', 'No core question yet'));
      this.updateTopicResourceAddedKeys();
      this.renderTopicStats();
      this.renderTopicOverview();
      this.renderContextPanel();
      this.switchDetailTab(this.activeDetailTab || 'details');
      this.renderResources(detail.resources || []);
      this.renderSummaries(detail.summaries || []);
      this.renderTasks(detail.tasks || []);
      this.renderMobileExpansion();
    },

    renderTopicStats: function() {
      var detail = this.detail || {};
      var resources = detail.resources || [];
      var summaries = detail.summaries || [];
      var tasks = detail.tasks || [];
      setOptionalText('topicResourcesTabCount', resources.length);
      setOptionalText('topicSummariesTabCount', summaries.length);
      setOptionalText('topicTasksTabCount', tasks.length);
    },

    renderTopicOverview: function() {
      var detail = this.detail || {};
      var topic = detail.topic || {};
      var resources = detail.resources || [];
      var summaries = detail.summaries || [];
      var tasks = detail.tasks || [];
      var title = byId('topicOverviewTitle');
      var question = byId('topicOverviewQuestion');
      var overviewPinButton = byId('topicOverviewPinBtn');
      if (title) title.textContent = topic.title || '';
      if (question) question.innerHTML = this.renderMarkdown(topic.question || t('topic.no_question', 'No core question yet'));
      this.renderTopicOverviewStatCards(resources.length, summaries.length, tasks.length);
      if (overviewPinButton) {
        var pinLabel = topic.is_pinned ? t('topic.pin.cancel', 'Unpin') : t('topic.pin', 'Pin');
        overviewPinButton.classList.toggle('is-pinned', !!topic.is_pinned);
        overviewPinButton.title = pinLabel;
        overviewPinButton.setAttribute('aria-label', pinLabel);
      }
      byId('topicOverviewUpdatedAt').textContent = formatDateOnly(topic.modify_time) || '-';
    },

    topicOverviewStatConfig: function(resourceCount, summaryCount, taskCount) {
      return [
        {
          kind: 'resources',
          icon: 'fa-layer-group',
          label: t('topic.detail.tab.resources', 'Materials'),
          caption: t('topic.overview.stat.resources.caption', 'Material base'),
          count: resourceCount
        },
        {
          kind: 'summaries',
          icon: 'fa-file-lines',
          label: t('topic.detail.tab.summaries', 'Summaries'),
          caption: t('topic.overview.stat.summaries.caption', 'Stage notes'),
          count: summaryCount
        },
        {
          kind: 'tasks',
          icon: 'fa-list-check',
          label: t('topic.detail.tab.tasks', 'Todos'),
          caption: t('topic.overview.stat.tasks.caption', 'Action items'),
          count: taskCount
        }
      ];
    },

    renderTopicOverviewStatCards: function(resourceCount, summaryCount, taskCount) {
      var wrap = document.querySelector('.topic-overview-stats');
      if (!wrap) return;
      wrap.innerHTML = this.topicOverviewStatConfig(resourceCount, summaryCount, taskCount).map(function(item) {
        var id = item.kind === 'resources' ? 'topicOverviewResourcesCount' : item.kind === 'summaries' ? 'topicOverviewSummariesCount' : 'topicOverviewTasksCount';
        return '<button type="button" class="topic-overview-stat topic-overview-stat-' + attr(item.kind) + '" data-topic-stat-tab="' + attr(item.kind) + '">' +
          '<span class="topic-overview-stat-icon"><i class="fa-solid ' + attr(item.icon) + '"></i></span>' +
          '<span class="topic-overview-stat-copy">' +
          '<span class="topic-overview-stat-title"><span class="topic-overview-stat-label">' + html(item.label) + '</span><strong id="' + attr(id) + '">' + html(countText(item.count)) + '</strong></span>' +
          '<span class="topic-overview-stat-caption">' + html(item.caption) + '</span>' +
          '</span>' +
          '<i class="topic-overview-stat-chevron fa-solid fa-chevron-right" aria-hidden="true"></i>' +
          '</button>';
      }).join('');
      this.bindOverviewStatTabs();
    },

    renderContextPanel: function() {
      var mobileModal = byId('topicMobileCommentsModal');
      if (!mobileModal || !mobileModal.classList.contains('open')) this.moveTopicCommentPanel(false);
      this.updateTopicCommentTargetLabel();
      this.renderTopicComments();
    },

    initTopicCommentLayout: function() {
      var saved = '';
      try {
        saved = window.localStorage.getItem('bookstark.topic.commentLayout') || '';
      } catch (ignore) {}
      this.setTopicCommentLayout(saved === 'collapsed' ? 'collapsed' : 'standard', { persist: false });
    },

    setTopicCommentLayout: function(mode, options) {
      options = options || {};
      var next = mode === 'collapsed' || mode === 'expanded' ? mode : 'standard';
      this.topicCommentLayout = next;
      var workbench = byId('topicWorkbench');
      if (workbench) {
        workbench.classList.toggle('topic-comments-collapsed', next === 'collapsed');
        workbench.classList.toggle('topic-comments-expanded', next === 'expanded');
      }
      var panel = byId('topicCommentPanel');
      var collapsedButton = byId('topicCommentCollapsedBtn');
      var expandButton = byId('topicCommentExpandBtn');
      var restoreButton = byId('topicDesktopRailRestoreBtn');
      if (panel) panel.setAttribute('aria-hidden', next === 'collapsed' ? 'true' : 'false');
      if (collapsedButton) collapsedButton.setAttribute('aria-expanded', next === 'collapsed' ? 'false' : 'true');
      if (expandButton) {
        var expanded = next === 'expanded';
        expandButton.setAttribute('aria-pressed', expanded ? 'true' : 'false');
        expandButton.title = t(expanded ? 'topic.comment.restore' : 'topic.comment.expand', expanded ? 'Restore comments' : 'Expand comments');
        expandButton.setAttribute('aria-label', expandButton.title);
        var icon = expandButton.querySelector('i');
        if (icon) icon.className = 'fa-solid ' + (expanded ? 'fa-compress' : 'fa-expand');
      }
      if (restoreButton) restoreButton.setAttribute('aria-hidden', next === 'expanded' ? 'false' : 'true');
      this.updateTopicCommentLayoutControls();
      if (options.persist !== false) {
        try {
          if (next === 'collapsed') window.localStorage.setItem('bookstark.topic.commentLayout', next);
          else window.localStorage.removeItem('bookstark.topic.commentLayout');
        } catch (ignore) {}
      }
    },

    updateTopicCommentLayoutControls: function() {
      var count = byId('topicCommentCollapsedCount');
      if (count) count.textContent = countText(this.topicCommentTotal);
    },

    moveTopicCommentPanel: function(mobile) {
      var panel = byId('topicCommentPanel');
      var host = byId(mobile ? 'topicCommentMobileHost' : 'topicCommentDesktopHost');
      if (panel) panel.setAttribute('aria-hidden', mobile || this.topicCommentLayout !== 'collapsed' ? 'false' : 'true');
      if (panel && host && panel.parentNode !== host) host.appendChild(panel);
    },

    openMobileCommentsModal: function(skipLoad) {
      this.moveTopicCommentPanel(true);
      var btn = byId('topicMobileCommentsBtn');
      if (btn) btn.setAttribute('aria-expanded', 'true');
      if (this.topicCommentScope === 'current' && !this.topicCommentTarget) this.setTopicCommentScope('all');
      else if (!skipLoad) this.loadTopicComments();
      this.openModal('topicMobileCommentsModal');
    },

    topicCommentTargetTitle: function(targetType, targetID) {
      var detail = this.detail || {};
      var item = null;
      if (targetType === 'resource') {
        item = (detail.resources || []).find(function(row) { return Number(row.topic_resource_id) === Number(targetID); });
        return item ? (item.title_snapshot || typeText(item.resource_type)) : t('topic.detail.tab.resources', 'Materials');
      }
      if (targetType === 'summary') {
        item = (detail.summaries || []).find(function(row) { return Number(row.summary_id) === Number(targetID); });
        if (!item) return t('topic.detail.tab.summaries', 'Summary');
        return String(item.content || '').replace(/[#*_>`\n\r]+/g, ' ').trim().slice(0, 48) || t('topic.detail.tab.summaries', 'Summary');
      }
      item = (detail.tasks || []).find(function(row) { return Number(row.task_id) === Number(targetID); });
      return item ? String(item.content || '').replace(/[#*_>`\n\r]+/g, ' ').trim().slice(0, 48) : t('topic.detail.tab.tasks', 'Todo');
    },

    updateTopicCommentTargetLabel: function() {
      var label = byId('topicCommentTargetLabel');
      var composer = byId('topicCommentComposer');
      var controls = document.querySelector('.topic-comment-compose');
      var locateButton = byId('topicCommentLocateBtn');
      if (!label) return;
      if (this.topicCommentScope === 'all') {
        label.textContent = '';
        label.classList.add('hidden');
      } else if (this.topicCommentTarget) {
        label.classList.remove('hidden');
        label.textContent = this.topicCommentTarget.title;
      } else {
        label.classList.remove('hidden');
        label.textContent = t('topic.comment.select_target', 'Select a material, summary, or todo to comment on');
      }
      var editable = this.topicCommentScope === 'current' && !!this.topicCommentTarget;
      if (locateButton) {
        locateButton.classList.toggle('hidden', !editable);
        locateButton.disabled = !editable;
      }
      if (controls) {
        controls.classList.toggle('is-disabled', !editable);
        controls.classList.toggle('is-scope-all', this.topicCommentScope === 'all');
      }
      if (composer) composer.setAttribute('aria-disabled', editable ? 'false' : 'true');
    },

    setTopicCommentScope: function(scope, options) {
      options = options || {};
      var nextScope = scope === 'all' ? 'all' : 'current';
      if (this.topicCommentScope === nextScope && !options.force) return;
      if (this.topicCommentScope === 'current' && nextScope === 'all') this.captureTopicCommentDraft();
      this.topicCommentScope = nextScope;
      document.querySelectorAll('[data-topic-comment-scope]').forEach(function(btn) {
        var active = btn.getAttribute('data-topic-comment-scope') === nextScope;
        btn.classList.toggle('active', active);
        btn.setAttribute('aria-pressed', active ? 'true' : 'false');
      });
      this.updateTopicCommentTargetLabel();
      if (nextScope === 'current') this.restoreTopicCommentDraft();
      this.loadTopicComments();
    },

    openTopicComments: function(targetType, targetID, title) {
      this.captureTopicCommentDraft();
      this.topicCommentTarget = {
        type: targetType,
        id: Number(targetID),
        title: title || this.topicCommentTargetTitle(targetType, targetID)
      };
      this.setTopicCommentScope('current', { force: true });
      if (window.matchMedia && window.matchMedia('(max-width: 1180px)').matches) {
        this.openMobileCommentsModal(true);
      } else {
        if (this.topicCommentLayout === 'collapsed') this.setTopicCommentLayout('standard');
        if (this.topicCommentComposer && this.topicCommentComposer.focus) this.topicCommentComposer.focus();
      }
    },

    locateTopicCommentTarget: function() {
      if (this.topicCommentScope !== 'current' || !this.topicCommentTarget) return;
      var config = {
        resource: { tab: 'resources', selector: '[data-resource-id="{id}"]' },
        summary: { tab: 'summaries', selector: '[data-summary-id="{id}"]' },
        task: { tab: 'tasks', selector: '[data-task-id="{id}"]' }
      }[this.topicCommentTarget.type];
      if (!config) return;
      var targetID = Number(this.topicCommentTarget.id);
      if (!targetID) return;
      if (byId('topicMobileCommentsModal') && byId('topicMobileCommentsModal').classList.contains('open')) {
        this.closeModal('topicMobileCommentsModal');
      }
      if (!this.topicDetailFilters) this.resetTopicDetailFilters();
      this.topicDetailFilters[config.tab] = '';
      this.switchDetailTab(config.tab);
      this.renderActiveDetailTab();
      var selector = config.selector.replace('{id}', String(targetID));
      requestAnimationFrame(function() {
        requestAnimationFrame(function() {
          var target = document.querySelector(selector);
          if (!target) return;
          target.classList.remove('topic-comment-located');
          target.scrollIntoView({ behavior: 'smooth', block: 'center', inline: 'nearest' });
          requestAnimationFrame(function() { target.classList.add('topic-comment-located'); });
          window.setTimeout(function() { target.classList.remove('topic-comment-located'); }, 1500);
        });
      });
    },

    loadTopicComments: async function(options) {
      options = options || {};
      var list = byId('topicCommentList');
      if (!list || !this.selectedId) return;
      if (this.topicCommentLoading && options.append) return;
      var append = !!options.append;
      var requestedPage = append ? this.topicCommentPage + 1 : 1;
      var loadToken = ++this.topicCommentLoadToken;
      var topicID = this.selectedId;
      if (this.topicCommentScope === 'current' && !this.topicCommentTarget) {
        this.topicComments = [];
        this.topicCommentPage = 1;
        this.topicCommentTotal = 0;
        this.renderTopicComments();
        return;
      }
      this.topicCommentLoading = true;
      if (!append) {
        list.innerHTML = '<div class="topic-comment-loading"><span class="topic-skeleton-block"></span><span class="topic-skeleton-block"></span></div>';
      } else {
        var moreButton = list.querySelector('[data-load-more-comments]');
        if (moreButton) {
          moreButton.disabled = true;
          moreButton.textContent = t('topic.comment.loading_more', 'Loading...');
        }
      }
      var query = '&page_size=' + this.topicCommentPageSize;
      if (this.topicCommentScope === 'current') {
        query += '&target_type=' + encodeURIComponent(this.topicCommentTarget.type) +
          '&target_id=' + encodeURIComponent(this.topicCommentTarget.id);
      }
      try {
        var data = await apiJSON('/api/topics/' + topicID + '/comments?page=' + requestedPage + query);
        if (loadToken !== this.topicCommentLoadToken || topicID !== this.selectedId) return;
        var rows = (data && data.data) || [];
        var total = Number(data && data.total) || rows.length;
        var items = append ? (this.topicComments || []).concat(rows) : rows;
        var seen = {};
        this.topicComments = items.filter(function(item) {
          var id = Number(item.comment_id);
          if (seen[id]) return false;
          seen[id] = true;
          return true;
        });
        this.topicCommentPage = requestedPage;
        this.topicCommentTotal = total;
        this.renderTopicComments();
      } catch (err) {
        if (loadToken !== this.topicCommentLoadToken || topicID !== this.selectedId) return;
        this.renderTopicCommentLoadError(append);
      } finally {
        if (loadToken === this.topicCommentLoadToken) this.topicCommentLoading = false;
      }
    },

    renderTopicCommentLoadError: function(append) {
      var list = byId('topicCommentList');
      if (!list) return;
      if (append && this.topicComments.length) {
        this.renderTopicComments();
        var loadMore = list.querySelector('.topic-comment-load-more');
        if (loadMore) loadMore.remove();
      }
      var error = document.createElement('div');
      error.className = 'topic-comment-load-error';
      error.setAttribute('role', 'status');
      error.innerHTML = '<span>' + html(t('topic.comment.load_failed', 'Failed to load comments')) + '</span>' +
        '<button type="button" class="topic-secondary-btn" data-retry-comments>' + html(t('topic.comment.retry', 'Retry')) + '</button>';
      list.appendChild(error);
      var self = this;
      error.querySelector('[data-retry-comments]').addEventListener('click', function() {
        self.loadTopicComments({ append: append });
      });
    },

    renderTopicComments: function() {
      var list = byId('topicCommentList');
      if (!list) return;
      this.updateTopicCommentLayoutControls();
      if (this.topicCommentScope === 'current' && !this.topicCommentTarget) {
        list.innerHTML = '<div class="topic-comment-empty">' + html(t('topic.comment.select_target', 'Select a material, summary, or todo to comment on')) + '</div>';
        return;
      }
      var items = this.topicComments || [];
      if (!items.length) {
        list.innerHTML = '<div class="topic-comment-empty">' + html(t('topic.comment.empty', 'No comments yet')) + '</div>';
        return;
      }
      var self = this;
      function renderItem(item) {
        var edited = String(item.modify_time || '') !== String(item.create_time || '');
        var canCompose = self.topicCommentScope === 'current';
        var targetLabel = self.topicCommentScope === 'all'
          ? '<button type="button" class="topic-comment-target-chip" data-comment-target="' + attr(item.target_type) + '" data-comment-target-id="' + attr(item.target_id) + '">' +
              '<i class="fa-solid fa-location-dot" aria-hidden="true"></i><span>' +
              html(self.topicCommentTargetTitle(item.target_type, item.target_id)) + '</span></button>'
          : '';
        return '<article class="topic-comment-item" data-comment-id="' + attr(item.comment_id) + '">' +
          '<div class="topic-comment-meta"><div class="topic-comment-identity"><strong>' + html(item.author_name || '') + '</strong>' +
          '<time>' + html(formatDate(item.create_time)) + (edited ? ' · ' + html(t('topic.comment.edited', 'Edited')) : '') + '</time></div>' +
          '<div class="topic-comment-actions">' +
          (canCompose ? '<button type="button" data-edit-comment="' + attr(item.comment_id) + '" title="' + attr(t('topic.comment.edit_aria', 'Edit comment')) + '" aria-label="' + attr(t('topic.comment.edit_aria', 'Edit comment')) + '"><i class="fa-solid fa-pen" aria-hidden="true"></i></button>' : '') +
          '<button type="button" data-delete-comment="' + attr(item.comment_id) + '" title="' + attr(t('topic.comment.delete_aria', 'Delete comment')) + '" aria-label="' + attr(t('topic.comment.delete_aria', 'Delete comment')) + '"><i class="fa-solid fa-trash-can" aria-hidden="true"></i></button>' +
          '</div></div>' +
          targetLabel +
          '<div class="topic-comment-content note-content">' + self.renderMarkdown(item.content) + '</div>' +
          '</article>';
      }
      list.innerHTML = items.map(renderItem).join('');
      if (this.topicComments.length < this.topicCommentTotal) {
        list.insertAdjacentHTML('beforeend', '<div class="topic-comment-load-more"><button type="button" class="topic-secondary-btn" data-load-more-comments>' +
          html(t('topic.comment.load_more', 'Load more')) + '</button></div>');
      }
      list.querySelectorAll('[data-edit-comment]').forEach(function(btn) {
        btn.addEventListener('click', function() { self.editTopicComment(Number(btn.getAttribute('data-edit-comment'))); });
      });
      list.querySelectorAll('[data-delete-comment]').forEach(function(btn) {
        btn.addEventListener('click', function() { self.deleteTopicComment(Number(btn.getAttribute('data-delete-comment'))); });
      });
      list.querySelectorAll('[data-comment-target]').forEach(function(btn) {
        btn.addEventListener('click', function() {
          self.openTopicComments(btn.getAttribute('data-comment-target'), Number(btn.getAttribute('data-comment-target-id')));
        });
      });
      var loadMore = list.querySelector('[data-load-more-comments]');
      if (loadMore) loadMore.addEventListener('click', function() { self.loadTopicComments({ append: true }); });
    },

    topicCommentValue: function() {
      return this.topicCommentComposer && this.topicCommentComposer.getValue
        ? this.topicCommentComposer.getValue().trim()
        : '';
    },

    setTopicCommentValue: function(value) {
      if (this.topicCommentComposer && this.topicCommentComposer.setValue) this.topicCommentComposer.setValue(value || '');
      this.updateTopicCommentPreview(true);
    },

    topicCommentDraftKey: function() {
      if (!this.selectedId || !this.topicCommentTarget) return '';
      return [this.selectedId, this.topicCommentTarget.type, Number(this.topicCommentTarget.id)].join(':');
    },

    captureTopicCommentDraft: function() {
      var key = this.topicCommentDraftKey();
      if (!key) return;
      var content = this.topicCommentValue();
      if (!content && !this.editingTopicCommentId) {
        delete this.topicCommentDrafts[key];
        return;
      }
      var label = byId('topicCommentEditLabel');
      this.topicCommentDrafts[key] = {
        content: content,
        editingID: Number(this.editingTopicCommentId) || 0,
        stateLabel: label ? label.textContent : ''
      };
    },

    restoreTopicCommentDraft: function() {
      var key = this.topicCommentDraftKey();
      var draft = key ? this.topicCommentDrafts[key] : null;
      this.editingTopicCommentId = draft ? Number(draft.editingID) || 0 : 0;
      this.setTopicCommentValue(draft ? draft.content : '');
      var state = byId('topicCommentEditState');
      if (draft && (draft.stateLabel || draft.editingID)) {
        this.showTopicCommentDraftState(draft.stateLabel || t('topic.comment.editing', 'Editing comment'));
      } else if (state) {
        state.classList.add('hidden');
      }
      this.hideTopicCommentPreview();
    },

    resetTopicCommentDraft: function(options) {
      options = options || {};
      var key = this.topicCommentDraftKey();
      if (key && options.forget !== false) delete this.topicCommentDrafts[key];
      this.editingTopicCommentId = 0;
      if (this.topicCommentComposer && this.topicCommentComposer.clear) this.topicCommentComposer.clear();
      var state = byId('topicCommentEditState');
      if (state) state.classList.add('hidden');
      this.hideTopicCommentPreview();
    },

    showTopicCommentDraftState: function(text) {
      var state = byId('topicCommentEditState');
      var label = byId('topicCommentEditLabel');
      if (state) state.classList.remove('hidden');
      if (label) label.textContent = text;
    },

    editTopicComment: function(commentID) {
      var item = (this.topicComments || []).find(function(row) { return Number(row.comment_id) === Number(commentID); });
      if (!item) return;
      this.editingTopicCommentId = Number(commentID);
      this.setTopicCommentValue(item.content || '');
      this.showTopicCommentDraftState(t('topic.comment.editing', 'Editing comment'));
      if (this.topicCommentComposer && this.topicCommentComposer.focus) this.topicCommentComposer.focus();
    },

    upsertSavedTopicComment: function(comment, editing) {
      if (!comment || !comment.comment_id) return;
      var commentID = Number(comment.comment_id);
      var existingIndex = (this.topicComments || []).findIndex(function(item) {
        return Number(item.comment_id) === commentID;
      });
      if (existingIndex >= 0) {
        this.topicComments[existingIndex] = Object.assign({}, this.topicComments[existingIndex], comment);
      } else {
        this.topicComments.push(comment);
        if (!editing) this.topicCommentTotal += 1;
      }
      this.renderTopicComments();
    },

    saveTopicComment: async function() {
      if (!this.selectedId || this.topicCommentScope !== 'current' || !this.topicCommentTarget) {
        toast(t('topic.comment.select_target', 'Select a material, summary, or todo to comment on'), 'warning');
        return;
      }
      var content = this.topicCommentValue();
      if (!content) {
        if (this.topicCommentComposer && this.topicCommentComposer.focus) this.topicCommentComposer.focus();
        return;
      }
      var editing = this.editingTopicCommentId;
      var topicID = this.selectedId;
      var targetType = this.topicCommentTarget.type;
      var targetID = Number(this.topicCommentTarget.id);
      var url = '/api/topics/' + topicID + '/comments' + (editing ? '/' + editing : '');
      var payload = editing
        ? { content: content }
        : {
            target_type: targetType,
            target_id: targetID,
            content: content
          };
      var button = byId('topicCommentSaveButton');
      if (button) button.disabled = true;
      try {
        var response = await apiJSON(url, {
          method: editing ? 'PUT' : 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(payload)
        });
        if (Number(this.selectedId) === Number(topicID)) {
          var sameTarget = this.topicCommentScope === 'current' && this.topicCommentTarget &&
            this.topicCommentTarget.type === targetType &&
            Number(this.topicCommentTarget.id) === targetID;
          var draftUnchanged = this.topicCommentValue() === content &&
            Number(this.editingTopicCommentId || 0) === Number(editing || 0);
          if (sameTarget) {
            this.upsertSavedTopicComment(response && response.data, editing);
            if (draftUnchanged) this.resetTopicCommentDraft();
          }
          await this.loadDetail(topicID, { silent: true });
        }
        toast(t('topic.comment.saved', 'Comment saved'), 'success');
      } catch (err) {
        toast(err.message || t('topic.comment.save_failed', 'Failed to save comment'), 'error');
      } finally {
        if (button) button.disabled = false;
      }
    },

    deleteTopicComment: async function(commentID) {
      var topicID = this.selectedId;
      if (!topicID) return;
      var comment = (this.topicComments || []).find(function(row) { return Number(row.comment_id) === Number(commentID); });
      var message = formatDeleteConfirmation(t('topic.comment.delete_confirm', 'Delete comment "{name}"?'), comment && comment.content, commentID, true);
      var ok = !window.BSDialog || await BSDialog.confirm2(message);
      if (!ok) return;
      try {
        await apiJSON('/api/topics/' + topicID + '/comments/' + commentID, { method: 'DELETE' });
        if (Number(this.selectedId) === Number(topicID)) {
          if (Number(this.editingTopicCommentId) === Number(commentID)) {
            this.resetTopicCommentDraft();
          }
          await this.loadDetail(topicID, { silent: true });
          if (Number(this.selectedId) === Number(topicID)) await this.loadTopicComments();
        }
        toast(t('topic.comment.deleted', 'Comment deleted'), 'success');
      } catch (err) {
        toast(err.message, 'error');
      }
    },

    renderTopicListSkeleton: function() {
      var list = byId('topicList');
      if (!list) return;
      list.classList.remove('topic-list-empty');
      var rows = [];
      for (var i = 0; i < 6; i++) {
        rows.push('<div class="topic-list-entry topic-list-skeleton" aria-hidden="true">' +
          '<div class="topic-card topic-skeleton-card">' +
          '<span class="topic-skeleton-block topic-skeleton-title" style="width:' + (64 + (i % 3) * 8) + '%"></span>' +
          '<span class="topic-skeleton-block topic-skeleton-line" style="width:' + (88 - (i % 4) * 10) + '%"></span>' +
          '<div class="topic-skeleton-meta">' +
          '<span class="topic-skeleton-block topic-skeleton-chip"></span>' +
          '<span class="topic-skeleton-block topic-skeleton-chip"></span>' +
          '<span class="topic-skeleton-block topic-skeleton-date"></span>' +
          '</div>' +
          '</div>' +
          '</div>');
      }
      list.innerHTML = rows.join('');
    },

    renderTopicDetailSkeleton: function() {
      byId('topicEmptyState').classList.add('hidden');
      byId('topicDetailContent').classList.remove('hidden');
      byId('topicReadTitle').innerHTML = '<span class="topic-skeleton-block topic-detail-title-skeleton"></span>';
      byId('topicReadQuestion').innerHTML = '<span class="topic-skeleton-block topic-detail-line-skeleton"></span><span class="topic-skeleton-block topic-detail-line-skeleton short"></span>';
      this.renderTopicOverviewSkeleton();
      setOptionalText('topicResourcesTabCount', '');
      setOptionalText('topicSummariesTabCount', '');
      setOptionalText('topicTasksTabCount', '');
      byId('topicItemsList').innerHTML = this.topicSkeletonRows('resource', 4);
      byId('topicSummariesList').innerHTML = this.topicSkeletonRows('summary', 3);
      byId('topicActionsList').innerHTML = this.topicSkeletonRows('task', 3);
    },

    renderTopicOverviewSkeleton: function() {
      var title = byId('topicOverviewTitle');
      var question = byId('topicOverviewQuestion');
      if (title) title.innerHTML = '<span class="topic-skeleton-block topic-overview-title-skeleton"></span>';
      if (question) question.innerHTML = '<span class="topic-skeleton-block topic-detail-line-skeleton"></span><span class="topic-skeleton-block topic-detail-line-skeleton short"></span>';
      this.renderTopicOverviewStatSkeletonCards();
      var updatedAt = byId('topicOverviewUpdatedAt');
      if (updatedAt) updatedAt.innerHTML = '<span class="topic-skeleton-block topic-overview-updated-skeleton"></span>';
    },

    renderTopicOverviewStatSkeletonCards: function() {
      var wrap = document.querySelector('.topic-overview-stats');
      if (!wrap) return;
      wrap.innerHTML = ['resources', 'summaries', 'tasks'].map(function(kind, index) {
        return '<button type="button" class="topic-overview-stat topic-overview-stat-' + attr(kind) + ' topic-overview-stat-skeleton" disabled aria-hidden="true">' +
          '<span class="topic-skeleton-block topic-overview-stat-icon-skeleton"></span>' +
          '<span class="topic-overview-stat-copy">' +
          '<span class="topic-skeleton-block topic-overview-stat-title-skeleton" style="width:' + (72 - index * 8) + '%"></span>' +
          '<span class="topic-skeleton-block topic-overview-stat-caption-skeleton" style="width:' + (84 - index * 10) + '%"></span>' +
          '</span>' +
          '<span class="topic-skeleton-block topic-overview-stat-chevron-skeleton"></span>' +
          '</button>';
      }).join('');
    },

    renderTopicSearchSkeleton: function() {
      byId('topicSearchResults').innerHTML = this.renderTopicResourceSkeletonRows();
    },

    topicSkeletonRows: function(kind, count) {
      var rows = [];
      for (var i = 0; i < count; i++) {
        rows.push('<div class="topic-compact-row topic-detail-skeleton topic-' + attr(kind) + '-skeleton" aria-hidden="true">' +
          '<span class="topic-skeleton-block topic-skeleton-icon"></span>' +
          '<div class="topic-skeleton-main">' +
          '<span class="topic-skeleton-block topic-skeleton-title" style="width:' + (58 + (i % 3) * 10) + '%"></span>' +
          '<span class="topic-skeleton-block topic-skeleton-line" style="width:' + (86 - (i % 4) * 9) + '%"></span>' +
          '</div>' +
          '</div>');
      }
      return rows.join('');
    },

    renderMarkdown: function(value) {
      var text = String(value || '');
      if (!text.trim()) return '<span class="topic-muted"></span>';
      if (typeof marked !== 'undefined' && marked.parse) {
        var rendered = marked.parse(text, { breaks: true, gfm: true });
        return typeof sanitizeRenderedHTML === 'function' ? sanitizeRenderedHTML(rendered) : rendered;
      }
      return html(text).replace(/\n/g, '<br>');
    },

    shortDate: function(value) {
      if (!value) return '-';
      var formatted = formatDate(value);
      if (!formatted) return '-';
      return formatted.slice(5, 10);
    },

    switchDetailTab: function(tabName) {
      var nextTab = tabName || 'details';
      this.activeDetailTab = nextTab;
      document.querySelectorAll('[data-topic-detail-tab]').forEach(function(tab) {
        var active = tab.getAttribute('data-topic-detail-tab') === nextTab;
        tab.classList.toggle('active', active);
        tab.setAttribute('aria-selected', active ? 'true' : 'false');
        tab.setAttribute('tabindex', active ? '0' : '-1');
        if (active && tab.scrollIntoView) tab.scrollIntoView({ block: 'nearest', inline: 'nearest' });
      });
      document.querySelectorAll('[data-topic-detail-panel]').forEach(function(panel) {
        var active = panel.getAttribute('data-topic-detail-panel') === nextTab;
        panel.classList.toggle('active', active);
        panel.hidden = !active;
      });
      var stickyControls = document.querySelector('.topic-detail-sticky-controls');
      if (stickyControls) stickyControls.classList.toggle('topic-detail-sticky-controls-flat', nextTab === 'details');
      this.syncTopicDetailSearch();
      this.updateTopicFab();
      this.updateTopicDetailCreateButton();
    },

    handleDetailTabKeydown: function(e, tab) {
      var key = e.key;
      if (key !== 'ArrowLeft' && key !== 'ArrowRight' && key !== 'Home' && key !== 'End') return;
      var tabs = Array.prototype.slice.call(document.querySelectorAll('[data-topic-detail-tab]'));
      if (!tabs.length) return;
      var index = tabs.indexOf(tab);
      if (index < 0) return;
      e.preventDefault();
      var nextIndex = index;
      if (key === 'ArrowLeft') nextIndex = Math.max(0, index - 1);
      if (key === 'ArrowRight') nextIndex = Math.min(tabs.length - 1, index + 1);
      if (key === 'Home') nextIndex = 0;
      if (key === 'End') nextIndex = tabs.length - 1;
      var next = tabs[nextIndex];
      if (!next) return;
      this.switchDetailTab(next.getAttribute('data-topic-detail-tab'));
      next.focus();
    },

    resetTopicDetailFilters: function() {
      this.topicDetailFilters = {
        details: '',
        resources: '',
        summaries: '',
        tasks: ''
      };
      this.syncTopicDetailSearch();
    },

    syncTopicDetailSearch: function() {
      var input = byId('topicDetailSearchInput');
      if (!input) return;
      var tab = this.activeDetailTab || 'resources';
      var search = document.querySelector('.topic-detail-search');
      if (search) search.classList.toggle('topic-detail-search-hidden', tab === 'details');
      var config = {
        details: { placeholder: '', label: '' },
        resources: {
          placeholder: t('topic.detail.search.resources.placeholder', 'Search materials...'),
          label: t('topic.detail.search.resources.aria', 'Search materials')
        },
        summaries: {
          placeholder: t('topic.detail.search.summaries.placeholder', 'Search summaries...'),
          label: t('topic.detail.search.summaries.aria', 'Search summaries')
        },
        tasks: {
          placeholder: t('topic.detail.search.tasks.placeholder', 'Search todos...'),
          label: t('topic.detail.search.tasks.aria', 'Search todos')
        }
      };
      var current = config[tab] || config.resources;
      input.placeholder = current.placeholder;
      input.setAttribute('aria-label', current.label);
      input.value = (this.topicDetailFilters && this.topicDetailFilters[tab]) || '';
    },

    searchActiveDetailTab: function() {
      var tab = this.activeDetailTab || 'resources';
      if (tab === 'details') return;
      var input = byId('topicDetailSearchInput');
      if (!this.topicDetailFilters) this.resetTopicDetailFilters();
      this.topicDetailFilters[tab] = input ? input.value.trim() : '';
      this.renderActiveDetailTab();
    },

    renderActiveDetailTab: function() {
      var detail = this.detail || {};
      if (this.activeDetailTab === 'summaries') {
        this.renderSummaries(detail.summaries || []);
      } else if (this.activeDetailTab === 'tasks') {
        this.renderTasks(detail.tasks || []);
      } else if (this.activeDetailTab === 'details') {
        this.renderTopicOverview();
      } else {
        this.renderResources(detail.resources || []);
      }
    },

    matchesTopicDetailSearch: function(values, keyword) {
      var normalized = String(keyword || '').trim().toLowerCase();
      if (!normalized) return true;
      return (values || []).some(function(value) {
        return String(value || '').toLowerCase().indexOf(normalized) !== -1;
      });
    },

    clearMobileExpansion: function() {
      document.querySelectorAll('.topic-expand').forEach(function(panel) {
        panel.classList.remove('show');
        panel.innerHTML = '';
      });
    },

    renderMobileExpansion: function() {
      var detail = this.detail || {};
      var topic = detail.topic || {};
      var panel = document.querySelector('[data-topic-expand-id="' + this.selectedId + '"]');
      this.clearMobileExpansion();
      if (!panel || !topic.topic_id) return;
      panel.classList.add('show');
      panel.innerHTML =
        '<div class="topic-expand-block"><div class="topic-expand-title">' + html(t('topic.mobile.question', 'Question')) + '</div><div class="topic-expand-text">' + multiline(topic.question, t('topic.mobile.no_question', 'No question yet')) + '</div></div>' +
        '<div class="topic-expand-tabs">' +
          '<button type="button" class="active" data-mobile-topic-tab="resources">' + html(t('topic.detail.tab.resources', 'Materials')) + '</button>' +
          '<button type="button" data-mobile-topic-tab="summaries">' + html(t('topic.detail.tab.summaries', 'Summaries')) + '</button>' +
          '<button type="button" data-mobile-topic-tab="tasks">' + html(t('topic.detail.tab.tasks', 'Todos')) + '</button>' +
        '</div>' +
        '<div class="topic-expand-panel active" data-mobile-topic-panel="resources">' + this.mobileResourceList(detail.resources || [], t('topic.resource.empty.title', 'No materials yet')) + '</div>' +
        '<div class="topic-expand-panel" data-mobile-topic-panel="summaries">' + this.mobileSummaryList(detail.summaries || [], t('topic.summary.empty.title', 'No summaries yet')) + '</div>' +
        '<div class="topic-expand-panel" data-mobile-topic-panel="tasks">' + this.mobileTaskList(detail.tasks || [], t('topic.task.empty.title', 'No todos yet')) + '</div>' +
        '<div class="topic-expand-actions"><button type="button" class="topic-secondary-btn" data-mobile-topic-edit><i class="fa-solid fa-pen"></i><span>' + html(t('topic.edit', 'Edit')) + '</span></button></div>';
      var self = this;
      panel.querySelectorAll('[data-mobile-topic-tab]').forEach(function(tab) {
        tab.addEventListener('click', function(e) {
          e.stopPropagation();
          var name = tab.getAttribute('data-mobile-topic-tab');
          panel.querySelectorAll('[data-mobile-topic-tab]').forEach(function(item) { item.classList.toggle('active', item === tab); });
          panel.querySelectorAll('[data-mobile-topic-panel]').forEach(function(item) { item.classList.toggle('active', item.getAttribute('data-mobile-topic-panel') === name); });
        });
      });
      var editBtn = panel.querySelector('[data-mobile-topic-edit]');
      if (editBtn) editBtn.addEventListener('click', function(e) {
        e.stopPropagation();
        self.openEditModal();
      });
    },

    mobileResourceList: function(items, emptyText) {
      if (!items.length) return '<div class="topic-empty-list">' + html(emptyText) + '</div>';
      return items.slice(0, 8).map(function(item) {
        var open = item.open_url || '';
        var title = open ? '<a href="' + attr(open) + '" target="_blank" rel="noopener noreferrer">' + html(item.title_snapshot) + '</a>' : html(item.title_snapshot);
        return '<div class="topic-expand-item"><i class="fa-solid ' + attr(typeIcon(item.resource_type)) + '"></i><span>' + title + '</span><em>' + html(typeText(item.resource_type)) + '</em></div>';
      }).join('');
    },

    mobileSummaryList: function(items, emptyText) {
      if (!items.length) return '<div class="topic-empty-list">' + html(emptyText) + '</div>';
      var self = this;
      return items.slice(0, 5).map(function(item) {
        return '<div class="topic-expand-item topic-expand-summary-item"><span class="note-content">' + self.renderMarkdown(item.content) + '</span></div>';
      }).join('');
    },

    mobileTaskList: function(items, emptyText) {
      if (!items.length) return '<div class="topic-empty-list">' + html(emptyText) + '</div>';
      return items.slice(0, 8).map(function(item) {
        return '<div class="topic-expand-item"><i class="fa-solid fa-list-check"></i><span>' + html(item.content) + '</span><em>' + html(item.done ? t('topic.task.status.done', 'Done') : item.due_date || '') + '</em></div>';
      }).join('');
    },

    renderTopicEmptyPanel: function(kind, title, body, actionText, actionName) {
      var icon = kind === 'tasks' ? 'fa-list-check' : (kind === 'summaries' ? 'fa-file-lines' : 'fa-layer-group');
      return '<div class="topic-empty-list topic-empty-panel">' +
        '<i class="fa-solid ' + icon + '"></i>' +
        '<strong>' + html(title) + '</strong>' +
        '<p>' + html(body) + '</p>' +
        (actionText ? '<button type="button" class="topic-secondary-btn topic-empty-panel-action" data-topic-empty-action="' + attr(actionName || kind) + '">' + html(actionText) + '</button>' : '') +
        '</div>';
    },

    bindTopicEmptyActions: function() {
      var self = this;
      document.querySelectorAll('[data-topic-empty-action]').forEach(function(btn) {
        btn.addEventListener('click', function() {
          var action = btn.getAttribute('data-topic-empty-action');
          if (action === 'resources') self.openItemModal();
          else if (action === 'summaries') {
            self.openNewSummaryEditor();
          } else if (action === 'tasks') self.openTaskModal();
          else if (action === 'clear-search') {
            var tab = self.activeDetailTab || 'resources';
            if (!self.topicDetailFilters) self.resetTopicDetailFilters();
            self.topicDetailFilters[tab] = '';
            self.syncTopicDetailSearch();
            self.renderActiveDetailTab();
          }
        });
      });
    },

    bindTopicCommentEntries: function(root) {
      var self = this;
      if (!root) return;
      root.querySelectorAll('[data-open-comments]').forEach(function(btn) {
        btn.addEventListener('click', function(e) {
          e.preventDefault();
          e.stopPropagation();
          self.openTopicComments(
            btn.getAttribute('data-open-comments'),
            Number(btn.getAttribute('data-comment-target-id')),
            btn.getAttribute('data-comment-target-title') || ''
          );
        });
      });
    },

    renderResources: function(resources) {
      var self = this;
      var sorted = (resources || []).slice().sort(function(a, b) {
        var ao = Number(a.order_sort || 0);
        var bo = Number(b.order_sort || 0);
        if (ao !== bo) return ao - bo;
        return String(a.create_time || '').localeCompare(String(b.create_time || ''));
      });
      var keyword = (this.topicDetailFilters && this.topicDetailFilters.resources) || '';
      var filtered = sorted.filter(function(item) {
        return self.matchesTopicDetailSearch([
          item.title_snapshot,
          typeText(item.resource_type),
          item.open_url,
          item.resource_missing ? t('topic.resource.missing', 'Source deleted') : ''
        ], keyword);
      });
      if (!sorted.length) {
        byId('topicItemsList').innerHTML = this.renderTopicEmptyPanel('resources', t('topic.resource.empty.title', 'No materials yet'), t('topic.resource.empty.body', 'Attach notes, docs, articles, or bookmarks.'), t('topic.item.add', 'Add material'));
        this.bindTopicEmptyActions();
        return;
      }
      if (!filtered.length) {
        byId('topicItemsList').innerHTML = this.renderTopicEmptyPanel('resources', t('topic.resource.no_match.title', 'No matching materials'), t('topic.resource.no_match.body', 'Try another keyword.'), t('topic.search.clear', 'Clear search'), 'clear-search');
        this.bindTopicEmptyActions();
        return;
      }
      byId('topicItemsList').innerHTML = filtered.map(function(item) {
        var open = item.open_url || '';
        var title = open ? '<a href="' + attr(open) + '" target="_blank" rel="noopener noreferrer">' + html(item.title_snapshot) + '</a>' : html(item.title_snapshot);
        var typeLabel = typeText(item.resource_type) + (item.resource_missing ? ' · ' + t('topic.resource.missing', 'Source deleted') : '');
        return '<div class="topic-compact-row topic-resource-content-item" data-resource-id="' + attr(item.topic_resource_id) + '">' +
          '<i class="fa-solid ' + attr(typeIcon(item.resource_type)) + '"></i>' +
          '<span class="topic-resource-item-title">' + title + '</span>' +
          '<span class="topic-resource-item-type">' + html(typeLabel) + '</span>' +
          '<button type="button" class="topic-icon-btn topic-comment-entry" data-open-comments="resource" data-comment-target-id="' + attr(item.topic_resource_id) + '" data-comment-target-title="' + attr(item.title_snapshot || typeLabel) + '" title="' + attr(t('topic.comment.open', 'View comments')) + '" aria-label="' + attr(t('topic.comment.open', 'View comments')) + '"><i class="fa-regular fa-comment"></i><span>' + html(countText(item.comment_count)) + '</span></button>' +
          '<button type="button" class="topic-icon-btn topic-danger" data-delete-resource="' + attr(item.topic_resource_id) + '" title="' + attr(t('topic.resource.remove', 'Remove')) + '" aria-label="' + attr(t('topic.resource.remove', 'Remove')) + '"><i class="fa-solid fa-xmark"></i></button>' +
          '</div>';
      }).join('');
      this.bindTopicCommentEntries(byId('topicItemsList'));
      byId('topicItemsList').querySelectorAll('[data-delete-resource]').forEach(function(btn) {
        btn.addEventListener('click', function() { self.deleteResource(parseInt(btn.getAttribute('data-delete-resource'), 10)); });
      });
    },

    renderSummaries: function(summaries) {
      var self = this;
      var keyword = (this.topicDetailFilters && this.topicDetailFilters.summaries) || '';
      var filtered = (summaries || []).filter(function(item) {
        return self.matchesTopicDetailSearch([
          item.content,
          item.summary_type,
          summaryType(item.summary_type) === 'ai' ? 'AI' : t('topic.summary.type.manual', 'Manual'),
          formatDate(item.modify_time || item.create_time)
        ], keyword);
      });
      if (!summaries.length) {
        byId('topicSummariesList').innerHTML = this.renderTopicEmptyPanel('summaries', t('topic.summary.empty.title', 'No summaries yet'), t('topic.summary.empty.body', 'Record stage judgments on the right.'), t('topic.summary.write', 'Write summary'));
        this.bindTopicEmptyActions();
        return;
      }
      if (!filtered.length) {
        byId('topicSummariesList').innerHTML = this.renderTopicEmptyPanel('summaries', t('topic.summary.no_match.title', 'No matching summaries'), t('topic.summary.no_match.body', 'Try another keyword.'), t('topic.search.clear', 'Clear search'), 'clear-search');
        this.bindTopicEmptyActions();
        return;
      }
      byId('topicSummariesList').innerHTML = filtered.map(function(item) {
        var updated = formatDate(item.modify_time || item.create_time);
        return '<div class="note-card topic-summary-card" data-summary-id="' + attr(item.summary_id) + '">' +
          '<div class="note-content">' + self.renderMarkdown(item.content) + '</div>' +
          '<div class="note-footer">' +
          '<div class="note-actions">' +
          '<button type="button" class="row-action topic-comment-entry" data-open-comments="summary" data-comment-target-id="' + attr(item.summary_id) + '" data-comment-target-title="' + attr(String(item.content || '').replace(/[#*_>`\n\r]+/g, ' ').trim().slice(0, 48)) + '" title="' + attr(t('topic.comment.open', 'View comments')) + '" aria-label="' + attr(t('topic.comment.open', 'View comments')) + '"><i class="fa-regular fa-comment"></i><span>' + html(countText(item.comment_count)) + '</span></button>' +
          '<button type="button" class="row-action" data-edit-summary="' + attr(item.summary_id) + '" title="' + attr(t('common.edit', 'Edit')) + '" aria-label="' + attr(t('common.edit', 'Edit')) + '"><i class="fa-solid fa-pen"></i></button>' +
          '<button type="button" class="row-action del" data-delete-summary="' + attr(item.summary_id) + '" title="' + attr(t('common.delete', 'Delete')) + '" aria-label="' + attr(t('common.delete', 'Delete')) + '"><i class="fa-solid fa-trash-can"></i></button>' +
          '</div>' +
          '<span class="note-time"><i class="fa-regular fa-clock" style="font-size:11px;margin-right:3px;"></i>' + html(updated) + '</span>' +
          '</div>' +
          '</div>';
      }).join('');
      this.bindTopicCommentEntries(byId('topicSummariesList'));
      byId('topicSummariesList').querySelectorAll('[data-edit-summary]').forEach(function(btn) {
        btn.addEventListener('click', function() {
          var id = parseInt(btn.getAttribute('data-edit-summary'), 10);
          var item = filtered.find(function(summary) { return summary.summary_id === id; });
          self.openSummaryEditor(item);
        });
      });
      byId('topicSummariesList').querySelectorAll('[data-delete-summary]').forEach(function(btn) {
        btn.addEventListener('click', function() {
          self.deleteSummary(parseInt(btn.getAttribute('data-delete-summary'), 10));
        });
      });
    },

    renderTasks: function(tasks) {
      var self = this;
      var keyword = (this.topicDetailFilters && this.topicDetailFilters.tasks) || '';
      var filtered = (tasks || []).filter(function(item) {
        return self.matchesTopicDetailSearch([
          item.content,
          item.due_date,
          item.done ? t('topic.task.status.done', 'Done') : t('topic.task.status.open', 'Open')
        ], keyword);
      });
      if (!tasks.length) {
        byId('topicActionsList').innerHTML = this.renderTopicEmptyPanel('tasks', t('topic.task.empty.title', 'No todos yet'), t('topic.task.empty.body', 'Break next actions into todos.'), t('topic.task.add', 'Add todo'));
        this.bindTopicEmptyActions();
        return;
      }
      if (!filtered.length) {
        byId('topicActionsList').innerHTML = this.renderTopicEmptyPanel('tasks', t('topic.task.no_match.title', 'No matching todos'), t('topic.task.no_match.body', 'Try another keyword.'), t('topic.search.clear', 'Clear search'), 'clear-search');
        this.bindTopicEmptyActions();
        return;
      }
      byId('topicActionsList').innerHTML = filtered.map(function(item) {
        var due = item.due_date || '';
        var doneLabel = item.done ? t('topic.task.status.done', 'Done') : t('topic.task.status.open', 'Open');
        return '<article class="task-row topic-task-row' + (item.done ? ' done' : '') + '" data-task-id="' + attr(item.task_id) + '">' +
          '<div class="task-tools">' +
          '<button type="button" class="task-icon-btn task-check-btn" data-toggle-task="' + attr(item.task_id) + '" aria-label="' + attr(item.done ? t('topic.task.mark_open', 'Mark open') : t('topic.task.mark_done', 'Mark done')) + '"><i class="fa-solid fa-check"></i></button>' +
          '<button type="button" class="task-icon-btn topic-comment-entry" data-open-comments="task" data-comment-target-id="' + attr(item.task_id) + '" data-comment-target-title="' + attr(String(item.content || '').replace(/[#*_>`\n\r]+/g, ' ').trim().slice(0, 48)) + '" title="' + attr(t('topic.comment.open', 'View comments')) + '" aria-label="' + attr(t('topic.comment.open', 'View comments')) + '"><i class="fa-regular fa-comment"></i><span>' + html(countText(item.comment_count)) + '</span></button>' +
          '<button type="button" class="task-icon-btn" data-edit-task="' + attr(item.task_id) + '" title="' + attr(t('common.edit', 'Edit')) + '" aria-label="' + attr(t('topic.task.edit_aria', 'Edit todo')) + '"><i class="fa-solid fa-pen"></i></button>' +
          '<button type="button" class="task-icon-btn" data-delete-task="' + attr(item.task_id) + '" title="' + attr(t('common.delete', 'Delete')) + '" aria-label="' + attr(t('topic.task.delete_aria', 'Delete todo')) + '"><i class="fa-solid fa-trash-can"></i></button>' +
          '</div>' +
          '<div class="topic-task-main">' +
          '<div class="task-body">' +
          '<div class="task-content note-content">' + self.renderMarkdown(item.content) + '</div>' +
          '</div>' +
          '<div class="task-meta">' +
          (due ? '<button type="button" class="task-pill task-due-pill" data-edit-task-due="' + attr(item.task_id) + '" title="' + attr(t('topic.task.due_aria', 'Set due date')) + '" aria-label="' + attr(t('topic.task.due_aria', 'Set due date')) + '"><i class="fa-regular fa-calendar"></i>' + html(due) + '</button>' : '') +
          '<span class="task-pill' + (item.done ? ' done' : '') + '">' + html(doneLabel) + '</span>' +
          '</div>' +
          '</div>' +
          '</article>';
      }).join('');
      this.bindTopicCommentEntries(byId('topicActionsList'));
      byId('topicActionsList').querySelectorAll('[data-toggle-task]').forEach(function(btn) {
        btn.addEventListener('click', function() {
          var id = parseInt(btn.getAttribute('data-toggle-task'), 10);
          var task = filtered.find(function(item) { return item.task_id === id; });
          if (task) self.toggleTaskDone(task);
        });
      });
      byId('topicActionsList').querySelectorAll('[data-edit-task]').forEach(function(btn) {
        btn.addEventListener('click', function() {
          var id = parseInt(btn.getAttribute('data-edit-task'), 10);
          var task = filtered.find(function(item) { return item.task_id === id; });
          if (task) self.openTaskModal(task);
        });
      });
      byId('topicActionsList').querySelectorAll('[data-delete-task]').forEach(function(btn) {
        btn.addEventListener('click', function() {
          var id = parseInt(btn.getAttribute('data-delete-task'), 10);
          var task = filtered.find(function(item) { return item.task_id === id; });
          if (task) self.deleteTask(task);
        });
      });
      byId('topicActionsList').querySelectorAll('[data-edit-task-due]').forEach(function(btn) {
        btn.addEventListener('click', function() {
          var id = parseInt(btn.getAttribute('data-edit-task-due'), 10);
          var task = filtered.find(function(item) { return item.task_id === id; });
          if (task) self.openTaskDueDatePicker(task, btn);
        });
      });
    },

    topicPayload: function() {
      return {
        title: byId('editTopicTitle').value.trim(),
        question: this.getTopicQuestionValue().trim(),
        is_pinned: !!((this.detail || {}).topic || {}).is_pinned
      };
    },

    saveTopic: async function() {
      if (!this.selectedId) return;
      try {
        var payload = this.topicPayload();
        if (payload.question.length > 2000) {
          toast(t('topic.toast.question_too_long', 'Core question cannot exceed 2000 characters'), 'error');
          return;
        }
        var data = await apiJSON('/api/topics/' + this.selectedId, {
          method: 'PUT',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(payload)
        });
        if (data && data.data && this.detail && this.detail.topic) {
          this.detail.topic = data.data;
        }
        toast(t('topic.save.success', 'Saved'), 'success');
        this.closeModal('topicEditModal');
        await this.refreshSelectedTopic({ silent: true });
      } catch (err) {
        toast(err.message, 'error');
      }
    },

    togglePin: async function() {
      if (!this.selectedId || !this.detail) return;
      return this.toggleTopicPin(this.selectedId, !this.detail.topic.is_pinned);
    },

    toggleTopicPin: async function(topicId, nextPinned) {
      if (!topicId) return;
      try {
        await apiJSON('/api/topics/' + topicId + '/pin', {
          method: 'PATCH',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ is_pinned: !!nextPinned })
        });
        if (this.detail && this.detail.topic && this.detail.topic.topic_id === topicId) {
          this.detail.topic.is_pinned = !!nextPinned;
          await this.refreshSelectedTopic({ silent: true });
        } else {
          var item = this.topics.find(function(topic) { return topic.topic_id === topicId; });
          if (item) {
            item.is_pinned = !!nextPinned;
            item.modify_time = new Date().toISOString();
            this.upsertTopicListItem(item);
          }
        }
      } catch (err) {
        toast(err.message, 'error');
      }
    },

    deleteTopic: async function() {
      if (!this.selectedId) return;
      var topic = this.detail && this.detail.topic;
      var ok = !window.BSDialog || await BSDialog.confirm2(formatDeleteConfirmation(t('topic.delete.confirm', 'Delete topic "{name}"?'), topic && topic.title, this.selectedId));
      if (!ok) return;
      try {
        var deletedId = this.selectedId;
        await apiJSON('/api/topics/' + deletedId, { method: 'DELETE' });
        toast(t('topic.delete.success', 'Deleted'), 'success');
        this.closeModal('topicEditModal');
        this.removeTopicListItem(deletedId);
        var next = this.topics[0];
        if (next && next.topic_id) {
          this.selectTopic(next.topic_id);
        } else {
          this.selectedId = 0;
          this.detail = null;
          this.renderEmpty();
        }
      } catch (err) {
        toast(err.message, 'error');
      }
    },

    openCreateModal: function() {
      byId('newTopicTitle').value = '';
      byId('newTopicQuestion').value = '';
      this.openModal('topicCreateModal');
    },

    openEditModal: function() {
      if (!this.selectedId || !this.detail || !this.detail.topic) return;
      var titleInput = byId('editTopicTitle');
      var questionInput = byId('editTopicQuestion');
      if (!titleInput || !questionInput) {
        toast(t('topic.toast.editor_reload', 'The edit panel was updated. Refresh and try again.'), 'error');
        return;
      }
      titleInput.value = this.detail.topic.title || '';
      this.hideTopicQuestionPreview();
      this.hideTopicQuestionEmojiPicker();
      this.setTopicQuestionValue(this.detail.topic.question || '');
      this.openModal('topicEditModal');
    },

    openEditModalForTopic: async function(topicId) {
      if (!topicId) return;
      if (this.selectedId !== topicId || !this.detail || !this.detail.topic || this.detail.topic.topic_id !== topicId) {
        this.selectedId = topicId;
        document.querySelectorAll('.topic-card').forEach(function(card) {
          card.classList.toggle('selected', parseInt(card.getAttribute('data-topic-id'), 10) === topicId);
        });
        await this.loadDetail(topicId);
      }
      this.openEditModal();
    },

    createTopic: async function() {
      var payload = {
        title: byId('newTopicTitle').value.trim(),
        question: byId('newTopicQuestion').value.trim()
      };
      try {
        var data = await apiJSON('/api/topics', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(payload)
        });
        this.closeModal('topicCreateModal');
        var topic = data.data || {};
        this.selectedId = topic.topic_id || 0;
        if (this.selectedId) this.upsertTopicListItem(topic);
        toast(t('topic.create.success', 'Created'), 'success');
        if (this.selectedId) await this.loadDetail(this.selectedId);
      } catch (err) {
        toast(err.message, 'error');
      }
    },

    switchTopicResourcePickerMode: function(mode) {
      this.topicResourcePickerMode = 'search';
      document.querySelectorAll('[data-topic-item-panel]').forEach(function(panel) {
        panel.classList.add('active');
        panel.hidden = false;
      });
      var title = byId('topicItemTitle');
      if (title) title.textContent = t('topic.item.add', 'Add material');
      setTimeout(function() {
        var input = byId('topicResourceKeyword');
        if (input) input.focus();
      }, 30);
    },

    openTopicResourceCreate: function(type) {
      if (!window.BookStarkResourceCreate) {
        toast(t('topic.resource.create.failed', 'Creation failed'), 'error');
        return;
      }
      var allowedTypes = ['note', 'document', 'article', 'bookmark'];
      if (allowedTypes.indexOf(type) < 0) type = 'note';
      var self = this;
      var restorePicker = function() {
        self.openModal('topicItemModal');
        document.body.classList.add('topic-resource-modal-open');
        self.renderResourceFilterBar();
        self.renderSearchResults(self.topicResourceResults);
        self.updateTopicResourceAddedCount();
      };
      this.closeModal('topicItemModal');
      window.BookStarkResourceCreate.open(type || 'note', {
        source: 'topic',
        onCreated: async function(row) {
          var exists = (self.topicResourceResults || []).some(function(item) {
            return self.resourceKey(item) === self.resourceKey(row);
          });
          if (!exists) self.topicResourceResults.unshift(row);
          var added = await self.addSearchResource(row, byId('resourceCreateSubmitBtn'));
          if (!added) {
            throw new Error(t('topic.resource.create.attach_failed', 'Created successfully, but adding to the topic failed. Find it through search and add it again.'));
          }
          self.topicResourceFilter = row.type;
          toast(t('topic.resource.create.success', 'Created and added to topic'), 'success');
        },
        onCancel: restorePicker,
        onClose: restorePicker
      });
    },

    openItemModal: function() {
      if (!this.selectedId) return;
      var modal = byId('topicItemModal');
      if (modal && modal.parentElement !== document.body) {
        document.body.appendChild(modal);
      }
      this.topicResourceFilter = 'all';
      this.topicResourceResults = [];
      this.topicResourceAddingKeys = {};
      this.topicResourceAddedSessionCount = 0;
      this.switchTopicResourcePickerMode('search');
      this.updateTopicResourceAddedKeys();
      this.renderResourceFilterBar();
      this.updateTopicResourceAddedCount();
      byId('topicResourceKeyword').value = '';
      this.renderTopicResourcePickerMeta(t('topic.resource.picker.meta.default', 'Enter keywords to search materials that can be attached to this topic'));
      var results = byId('topicSearchResults');
      if (results) {
        results.removeAttribute('aria-busy');
        results.innerHTML = this.renderTopicResourceState('idle', t('topic.resource.picker.idle.title', 'Search materials'), t('topic.resource.picker.idle.body', 'Search existing notes, docs, articles, or bookmarks.'));
      }
      this.openModal('topicItemModal');
      document.body.classList.add('topic-resource-modal-open');
    },

    searchResources: async function() {
      var q = byId('topicResourceKeyword').value.trim();
      if (!q) {
        this.topicResourceResults = [];
        this.renderTopicResourcePickerMeta(t('topic.resource.picker.meta.default', 'Enter keywords to search materials that can be attached to this topic'));
        byId('topicSearchResults').removeAttribute('aria-busy');
        byId('topicSearchResults').innerHTML = this.renderTopicResourceState('idle', t('topic.resource.picker.idle.title', 'Search materials'), t('topic.resource.picker.idle.body', 'Search existing notes, docs, articles, or bookmarks.'));
        return;
      }
      var seq = ++this.topicResourceSearchSeq;
      var results = byId('topicSearchResults');
      if (results) byId('topicSearchResults').setAttribute('aria-busy', 'true');
      this.renderTopicSearchSkeleton();
      this.renderTopicResourcePickerMeta(t('topic.resource.picker.searching', 'Searching...'));
      try {
        var data = await apiJSON('/api/search?q=' + encodeURIComponent(q));
        if (seq !== this.topicResourceSearchSeq) return;
        this.topicResourceResults = this.normalizeTopicResourceRows(data.data || {});
        this.updateTopicResourceAddedKeys();
        this.renderSearchResults(this.topicResourceResults);
      } catch (err) {
        if (seq !== this.topicResourceSearchSeq) return;
        byId('topicSearchResults').innerHTML = this.renderTopicResourceState('error', t('topic.resource.picker.search_failed', 'Search failed'), err.message);
        this.renderTopicResourcePickerMeta(t('topic.resource.picker.search_failed', 'Search failed'));
      } finally {
        if (seq === this.topicResourceSearchSeq && results) results.removeAttribute('aria-busy');
      }
    },

    normalizeTopicResourceRows: function(result) {
      var rows = [];
      (result.documents || []).forEach(function(item) {
        rows.push({ type: 'document', id: item.id, title: item.name, desc: item.book_name || item.snippet || '', book_identify: item.book_identify || '', identify: item.identify || '' });
      });
      (result.blogs || []).forEach(function(item) {
        rows.push({ type: item.blog_type === 'note' ? 'note' : 'article', id: item.id, title: item.title, desc: item.snippet || '', identify: item.identify || '' });
      });
      (result.bookmarks || []).forEach(function(item) {
        rows.push({ type: 'bookmark', id: item.id, title: item.title || item.url, desc: item.description || item.url || '' });
      });
      return rows;
    },

    renderResourceFilterBar: function() {
      var current = this.topicResourceFilter || 'all';
      document.querySelectorAll('[data-topic-resource-filter]').forEach(function(btn) {
        var active = btn.getAttribute('data-topic-resource-filter') === current;
        btn.classList.toggle('active', active);
        btn.setAttribute('aria-pressed', active ? 'true' : 'false');
      });
    },

    handleResourceFilterKeydown: function(e, currentButton) {
      var key = e.key;
      if (key !== 'ArrowLeft' && key !== 'ArrowRight' && key !== 'Home' && key !== 'End') return;
      var buttons = Array.prototype.slice.call(document.querySelectorAll('[data-topic-resource-filter]'));
      if (!buttons.length) return;
      var index = buttons.indexOf(currentButton);
      if (index < 0) return;
      e.preventDefault();
      var nextIndex = index;
      if (key === 'ArrowLeft') nextIndex = Math.max(0, index - 1);
      if (key === 'ArrowRight') nextIndex = Math.min(buttons.length - 1, index + 1);
      if (key === 'Home') nextIndex = 0;
      if (key === 'End') nextIndex = buttons.length - 1;
      var next = buttons[nextIndex];
      if (!next) return;
      next.focus();
      next.click();
    },

    filterTopicResourceRows: function(rows) {
      var filter = this.topicResourceFilter || 'all';
      if (filter === 'all') return rows || [];
      return (rows || []).filter(function(row) { return row.type === filter; });
    },

    resourceKey: function(row) {
      return String((row || {}).type || '') + ':' + String((row || {}).id || '');
    },

    resourcePreviewHref: function(row) {
      row = row || {};
      var id = encodeURIComponent(row.id || '');
      if (row.type === 'document') {
        var bookIdentify = row.book_identify || row.bookIdentify || '';
        if (bookIdentify) {
          return '/books/' + encodeURIComponent(bookIdentify) + '/edit?doc=' + id + '&from=' + encodeURIComponent(location.pathname + location.search);
        }
        return '/search?q=' + encodeURIComponent(row.title || '');
      }
      if (row.type === 'note' || row.type === 'article') return '/notes?id=' + id;
      if (row.type === 'bookmark') return '/bookmarks?id=' + id;
      if (row.type === 'task') return '/notes?tab=tasks&task_id=' + id;
      return '/search?q=' + encodeURIComponent(row.title || '');
    },

    updateTopicResourceAddedKeys: function() {
      var keys = {};
      (((this.detail || {}).resources) || []).forEach(function(item) {
        keys[String(item.resource_type || '') + ':' + String(item.target_id || '')] = true;
      });
      this.topicResourceAddedKeys = keys;
    },

    isResourceAlreadyAdded: function(row) {
      return !!(this.topicResourceAddedKeys || {})[this.resourceKey(row)];
    },

    renderTopicResourcePickerMeta: function(text) {
      var meta = byId('topicResourceSearchMeta');
      if (meta) meta.textContent = text || '';
    },

    updateTopicResourceAddedCount: function() {
      var count = byId('topicResourceAddedCount');
      if (count) count.textContent = tf('topic.resource.picker.added_count', 'Added {count}', { count: this.topicResourceAddedSessionCount || 0 });
    },

    isTopicResourceModalOpen: function() {
      var modal = byId('topicItemModal');
      return !!(modal && modal.classList.contains('open'));
    },

    focusTopicResourceRow: function(key, preferButton) {
      if (!this.isTopicResourceModalOpen()) return;
      var resultsEl = byId('topicSearchResults');
      if (!resultsEl) return;
      var row = Array.prototype.slice.call(resultsEl.querySelectorAll('[data-resource-key]')).filter(function(item) {
        return item.getAttribute('data-resource-key') === key;
      })[0];
      if (!row) return;
      var target = preferButton ? row.querySelector('button:not([disabled])') : null;
      (target || row).focus();
    },

    renderTopicResourceState: function(type, title, message) {
      var icon = type === 'error' ? 'fa-triangle-exclamation' : (type === 'empty' ? 'fa-magnifying-glass' : 'fa-layer-group');
      return '<div class="topic-resource-state topic-resource-state-' + attr(type || 'idle') + '">' +
        '<i class="fa-solid ' + attr(icon) + '" aria-hidden="true"></i>' +
        '<strong>' + html(title || '') + '</strong>' +
        '<span>' + html(message || '') + '</span>' +
        '</div>';
    },

    renderTopicResourceSkeletonRows: function() {
      var rows = [];
      for (var i = 0; i < 5; i++) {
        rows.push('<div class="topic-resource-skeleton-row" aria-hidden="true">' +
          '<span class="topic-skeleton-block topic-skeleton-icon"></span>' +
          '<div class="topic-skeleton-main">' +
          '<span class="topic-skeleton-block topic-skeleton-title" style="width:' + (58 + (i % 3) * 10) + '%"></span>' +
          '<span class="topic-skeleton-block topic-skeleton-line" style="width:' + (82 - (i % 4) * 8) + '%"></span>' +
          '</div>' +
          '<span class="topic-skeleton-block topic-skeleton-chip"></span>' +
          '</div>');
      }
      return rows.join('');
    },

    renderSearchResults: function(result) {
      var self = this;
      var resultsEl = byId('topicSearchResults');
      var scrollTop = resultsEl ? resultsEl.scrollTop : 0;
      var sourceRows = Array.isArray(result) ? result : this.normalizeTopicResourceRows(result || {});
      var filteredRows = this.filterTopicResourceRows(sourceRows);
      var rows = filteredRows.slice(0, 30);
      this.renderTopicResourcePickerMeta(sourceRows.length ? tf('topic.resource.picker.filtered_count', 'Showing {filtered} / {total}', { filtered: filteredRows.length, total: sourceRows.length }) : t('topic.resource.picker.no_match_meta', 'No matching materials'));
      if (!rows.length) {
        if (resultsEl) resultsEl.innerHTML = this.renderTopicResourceState('empty', t('topic.resource.picker.no_match', 'No matching materials'), t('topic.resource.picker.no_match_body', 'Try another keyword or switch type.'));
        return;
      }
      if (!resultsEl) return;
      resultsEl.innerHTML = rows.map(function(row) {
        var key = self.resourceKey(row);
        var added = self.isResourceAlreadyAdded(row);
        var adding = !!(self.topicResourceAddingKeys || {})[key];
        var button = added
          ? '<button type="button" class="topic-secondary-btn" disabled aria-label="' + attr(t('topic.resource.in_topic', 'Already in topic') + ': ' + row.title) + '"><i class="fa-solid fa-check"></i><span>' + html(t('topic.resource.added', 'Added')) + '</span></button>'
          : '<button type="button" class="topic-primary-btn" data-add-resource-key="' + attr(key) + '" aria-label="' + attr(t('topic.resource.add_to_topic', 'Add to topic') + ': ' + row.title) + '"' + (adding ? ' disabled' : '') + '><i class="fa-solid ' + (adding ? 'fa-spinner fa-spin' : 'fa-plus') + '"></i><span>' + html(adding ? t('topic.resource.adding', 'Adding') : t('topic.item.add_short', 'Add')) + '</span></button>';
        return '<div class="topic-search-result' + (added ? ' is-added' : '') + (adding ? ' is-adding' : '') + '" role="listitem" tabindex="-1" data-resource-key="' + attr(key) + '">' +
          '<a class="topic-search-result-link" href="' + attr(self.resourcePreviewHref(row)) + '">' +
          '<span class="topic-type-icon"><i class="fa-solid ' + attr(typeIcon(row.type)) + '"></i></span>' +
          '<div class="topic-search-result-main"><div class="topic-search-result-title">' + html(row.title) + '</div><div class="topic-search-result-desc">' + html(typeText(row.type) + (row.desc ? ' · ' + row.desc : '')) + '</div></div>' +
          '</a>' +
          button +
          '</div>';
      }).join('');
      resultsEl.scrollTop = scrollTop;
      resultsEl.querySelectorAll('[data-add-resource-key]').forEach(function(btn) {
        btn.addEventListener('click', function() {
          var key = btn.getAttribute('data-add-resource-key');
          var row = (self.topicResourceResults || []).find(function(item) { return self.resourceKey(item) === key; });
          self.addSearchResource(row, btn);
        });
      });
      var modal = byId('topicItemModal');
      var panel = modal ? modal.querySelector('.asset-modal') : null;
      if (this.isTopicResourceModalOpen() && panel && !panel.contains(document.activeElement)) {
        var activeRow = resultsEl.querySelector('.topic-search-result.is-adding, .topic-search-result.is-added') || resultsEl.querySelector('.topic-search-result');
        if (activeRow) activeRow.focus();
      }
    },

    addSearchResource: async function(row, button) {
      if (!row) return false;
      var self = this;
      var key = this.resourceKey(row);
      if (this.isResourceAlreadyAdded(row)) return true;
      if (this.topicResourceAddingKeys[key]) return false;
      var resultsEl = byId('topicSearchResults');
      var scrollTop = resultsEl ? resultsEl.scrollTop : 0;
      this.topicResourceAddingKeys[key] = true;
      this.renderSearchResults(this.topicResourceResults);
      this.focusTopicResourceRow(key, true);
      var addTask = async function() {
        await apiJSON('/api/topics/' + this.selectedId + '/resources', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            resource_type: row.type,
            target_id: row.id,
            title_snapshot: row.title,
            desc_snapshot: row.desc || ''
          })
        });
      }.bind(this);
      try {
        if (window.BookStarkRequestLock && BookStarkRequestLock.run) {
          await BookStarkRequestLock.run('topic-resource-add:' + key, addTask, button);
        } else {
          await addTask();
        }
        this.topicResourceAddedKeys[key] = true;
        this.topicResourceAddedSessionCount = (this.topicResourceAddedSessionCount || 0) + 1;
        this.updateTopicResourceAddedCount();
        toast(t('topic.item.add.success', 'Added'), 'success');
        delete self.topicResourceAddingKeys[key];
        if (this.isTopicResourceModalOpen()) {
          self.renderSearchResults(self.topicResourceResults);
          resultsEl = byId('topicSearchResults');
        }
        if (this.isTopicResourceModalOpen() && resultsEl) {
          resultsEl.scrollTop = scrollTop;
          this.focusTopicResourceRow(key, false);
        }
        await this.refreshSelectedTopic({ silent: true });
        this.updateTopicResourceAddedKeys();
        if (this.isTopicResourceModalOpen()) {
          resultsEl = byId('topicSearchResults');
          if (resultsEl) resultsEl.scrollTop = scrollTop;
          this.focusTopicResourceRow(key, false);
        }
        return true;
      } catch (err) {
        toast(err.message, 'error');
        delete self.topicResourceAddingKeys[key];
        if (this.isTopicResourceModalOpen()) {
          self.renderSearchResults(self.topicResourceResults);
          resultsEl = byId('topicSearchResults');
          if (resultsEl) resultsEl.scrollTop = scrollTop;
          this.focusTopicResourceRow(key, true);
        }
        return false;
      }
    },

    deleteResource: async function(resourceId) {
      if (!this.selectedId || !resourceId) return;
      var resource = ((this.detail || {}).resources || []).find(function(row) { return Number(row.topic_resource_id) === Number(resourceId); });
      var ok = !window.BSDialog || await BSDialog.confirm2(formatDeleteConfirmation(t('topic.item.delete.confirm', 'Remove material reference "{name}"? The original content will not be deleted.'), resource && resource.title_snapshot, resourceId));
      if (!ok) return;
      try {
        await apiJSON('/api/topics/' + this.selectedId + '/resources/' + resourceId, { method: 'DELETE' });
        toast(t('topic.item.delete.success', 'Removed'), 'success');
        await this.refreshSelectedTopic({ silent: true });
      } catch (err) {
        toast(err.message, 'error');
      }
    },

    setSummaryDraftType: function(type) {
      this.summaryDraftType = summaryType(type);
    },

    updateSummarySubmitLabel: function() {
      var btn = byId('topicSummarySaveButton');
      if (!btn) return;
      var label = t('topic.save', 'Save');
      btn.setAttribute('title', label);
      btn.setAttribute('aria-label', label);
    },

    openSummaryEditor: function(summary) {
      if (!summary) return;
      this.topicSummaryEditorMode = 'edit';
      this.editingSummaryId = summary.summary_id || 0;
      this.setInlineSummaryValue(summary.content || '');
      this.setSummaryDraftType(summary.summary_type);
      this.updateSummarySubmitLabel();
      this.renderSummaries(((this.detail || {}).summaries) || []);
      this.openTopicSummaryEditorModal();
      if (this.topicSummaryComposer && this.topicSummaryComposer.focus) this.topicSummaryComposer.focus();
    },

    getInlineSummaryValue: function() {
      if (!this.topicSummaryComposer || !this.topicSummaryComposer.getValue) return '';
      return this.topicSummaryComposer.getValue().trim();
    },

    setInlineSummaryValue: function(value) {
      if (!this.topicSummaryComposer) return;
      if (this.topicSummaryComposer.setValue) {
        this.topicSummaryComposer.setValue(value || '');
      }
      this.updateTopicSummaryPreview();
    },

    clearInlineSummary: function() {
      if (this.topicSummaryComposer && this.topicSummaryComposer.clear) {
        this.topicSummaryComposer.clear();
      } else {
        this.setInlineSummaryValue('');
      }
      this.editingSummaryId = 0;
      this.topicSummaryEditorMode = 'new';
      this.setSummaryDraftType('manual');
      this.updateSummarySubmitLabel();
      this.updateTopicSummaryPreview();
      if (this.topicSummaryComposer && this.topicSummaryComposer.focus) this.topicSummaryComposer.focus();
    },

    setTopicSummaryAIStreamStatus: function(state, count, message) {
      var el = byId(this.topicSummaryAIActiveStatusID || 'topicSummaryAIStreamStatus');
      if (!el) return;
      if (!state || state === 'idle') {
        el.classList.remove('is-visible', 'is-error');
        el.setAttribute('aria-hidden', 'true');
        el.innerHTML = '';
        return;
      }
      el.classList.toggle('is-error', state === 'error');
      el.classList.add('is-visible');
      el.setAttribute('aria-hidden', 'false');
      if (state === 'error') {
        el.textContent = message || t('note.ai.toast.error', 'AI call failed');
        return;
      }
      var template = t('note.ai.streaming_count', 'AI is generating, {count} chars written');
      var text = (message || template).replace('{count}', String(Math.max(0, count || 0)));
      el.innerHTML = '<span class="ai-inline-generation-spinner" aria-hidden="true"></span><span>' + html(text) + '</span>';
    },

    topicSummaryAIContext: function() {
      var detail = this.detail || {};
      var topic = detail.topic || {};
      var lines = [];
      lines.push('【标题】' + (topic.title || t('topic.untitled', 'Untitled topic')));
      if (topic.question) lines.push('【描述】' + topic.question);

      var summaries = detail.summaries || [];
      if (summaries.length) {
        lines.push('');
        lines.push('【已有小结】');
        summaries.forEach(function(item, index) {
          lines.push((index + 1) + '. ' + (item.content || '').trim());
        });
      }
      return lines.join('\n').slice(0, 12000);
    },

    getTopicSummaryAIContextFromEditor: function() {
      var composer = this.topicSummaryComposer;
      if (!composer) return '';
      var value = composer.getValue ? (composer.getValue() || '') : this.getInlineSummaryValue();
      var range = composer.getSelectionRange ? composer.getSelectionRange() : null;
      if (range && range.from !== range.to) return value.substring(range.from, range.to).trim();
      return (value || '').trim();
    },

    topicSummaryAIActions: function() {
      if (this.topicSummaryAIActiveKind === 'comment') {
        return [
          { label: t('topic.ai.summary.action.polish', 'Polish output'), prompt: '美化当前评论：优化 Markdown 格式和表达，保留原意，只返回处理后的 Markdown。' },
          { label: t('topic.comment.publish', 'Draft comment'), prompt: '基于上下文写一条简洁、具体、可推进讨论的评论。只返回 Markdown。' },
          { label: t('topic.ai.summary.action.conclusion', 'Extract conclusions'), prompt: '把当前讨论提炼成明确结论，并指出仍需确认的事项。只返回 Markdown。' },
          { label: t('topic.ai.summary.action.next', 'Next step'), prompt: '基于当前讨论提出清晰的下一步行动。只返回 Markdown。' }
        ];
      }
      return [
        { label: t('topic.ai.summary.action.polish', 'Polish output'), prompt: '美化当前小结输出：优化 Markdown 格式、层级、列表和语句表达，保留原意，只返回处理后的 Markdown。' },
        { label: t('topic.ai.summary.action.stage', 'Stage summary'), prompt: '基于上下文生成一条阶段小结，保留关键事实、当前结论和下一步。只返回 Markdown。' },
        { label: t('topic.ai.summary.action.conclusion', 'Extract conclusions'), prompt: '提炼当前专题最重要的结论和证据，输出简洁的 Markdown 列表。只返回 Markdown。' },
        { label: t('topic.ai.summary.action.next', 'Next step'), prompt: '生成一条偏行动建议的小结，指出下一步要做什么。只返回 Markdown。' }
      ];
    },

    ensureTopicSummaryAI: function() {
      if (this.topicSummaryAI) return this.topicSummaryAI;
      var wrap = document.createElement('div');
      wrap.innerHTML = '' +
        '<div class="note-ai-popover topic-summary-ai-popover" role="dialog" aria-modal="false" aria-label="' + attr(t('topic.ai.summary.title', 'Generate topic summary')) + '">' +
          '<div class="note-ai-popover-head">' +
            '<div class="note-ai-popover-title"><i class="fa-solid fa-wand-magic-sparkles"></i><span>' + html(t('topic.ai.summary.title', 'Generate topic summary')) + '</span></div>' +
            '<div class="note-ai-popover-actions">' +
              '<button class="note-ai-popover-expand" type="button" aria-label="' + attr(t('note.ai.expand', 'Expand AI input')) + '" aria-pressed="false"><i class="fa-solid fa-expand"></i></button>' +
              '<button class="note-ai-popover-close" type="button" aria-label="' + attr(t('dialog.close', 'Close')) + '">&times;</button>' +
            '</div>' +
          '</div>' +
          '<button type="button" class="note-ai-context topic-summary-ai-context-btn"></button>' +
          '<div class="note-ai-input-row">' +
            '<textarea class="note-ai-prompt" rows="1" autocomplete="off" placeholder="' + attr(t('topic.ai.summary.placeholder', 'Tell AI what this summary should focus on')) + '"></textarea>' +
            '<button class="note-ai-go note-ai-go-inline" type="button">' + html(t('dialog.confirm', 'OK')) + '</button>' +
          '</div>' +
          '<div class="note-ai-quick-actions" role="group" aria-label="' + attr(t('topic.ai.quick_actions', 'AI quick actions')) + '"></div>' +
          '<div class="note-ai-footer">' +
            '<button class="note-ai-cancel ai-dlg-btn ai-dlg-btn-cancel" type="button">' + html(t('dialog.cancel', 'Cancel')) + '</button>' +
            '<button class="note-ai-go note-ai-go-footer ai-dlg-btn ai-dlg-btn-go" type="button">' + html(t('note.ai.dialog.generate', 'Generate')) + '</button>' +
          '</div>' +
          '<div class="note-ai-status" aria-live="polite"></div>' +
        '</div>';
      document.body.appendChild(wrap);
      var popover = wrap.querySelector('.topic-summary-ai-popover');
      var prompt = wrap.querySelector('.note-ai-prompt');
      var contextBtn = wrap.querySelector('.topic-summary-ai-context-btn');
      var status = wrap.querySelector('.note-ai-status');
      var expandBtn = wrap.querySelector('.note-ai-popover-expand');
      var quickActions = wrap.querySelector('.note-ai-quick-actions');
      var self = this;
      this.topicSummaryAI = { root: wrap, popover: popover, prompt: prompt, contextButton: contextBtn, status: status, expandBtn: expandBtn, quickActions: quickActions, cleanupDrag: null };

      wrap.querySelector('.note-ai-popover-close').addEventListener('click', function() { self.closeTopicSummaryAI(); });
      wrap.querySelector('.note-ai-cancel').addEventListener('click', function() { self.closeTopicSummaryAI(); });
      contextBtn.addEventListener('click', function() { self.openTopicSummaryAIContextEditor(); });
      expandBtn.addEventListener('click', function() { self.toggleTopicSummaryAIExpanded(); });
      Array.prototype.forEach.call(wrap.querySelectorAll('.note-ai-go'), function(btn) {
        btn.addEventListener('click', function() { self.runTopicSummaryAI(); });
      });
      prompt.addEventListener('keydown', function(e) {
        var expanded = popover.classList.contains('is-expanded');
        if (e.key === 'Enter' && (!expanded || e.ctrlKey || e.metaKey)) {
          e.preventDefault();
          self.runTopicSummaryAI();
        } else if (e.key === 'Escape') {
          e.preventDefault();
          self.closeTopicSummaryAI();
        }
      });
      this.renderTopicSummaryAIQuickActions();
      this.topicSummaryAI.cleanupDrag = this.makeTopicSummaryAIDraggable(popover);
      return this.topicSummaryAI;
    },

    makeTopicSummaryAIDraggable: function(popover) {
      if (!popover) return null;
      var header = popover.querySelector('.note-ai-popover-head');
      if (!header) return null;
      var self = this;
      var startX = 0;
      var startY = 0;
      var startLeft = 0;
      var startTop = 0;
      var dragging = false;

      function clampPosition(left, top) {
        var rect = popover.getBoundingClientRect();
        var maxLeft = Math.max(8, window.innerWidth - rect.width - 8);
        var maxTop = Math.max(8, window.innerHeight - rect.height - 8);
        return {
          left: Math.max(8, Math.min(maxLeft, left)),
          top: Math.max(8, Math.min(maxTop, top))
        };
      }

      function begin(e) {
        if (self.isSmallTopicAIViewport()) return;
        if (e.target && e.target.closest && e.target.closest('button,input,textarea,select,a')) return;
        var rect = popover.getBoundingClientRect();
        dragging = true;
        startX = e.clientX;
        startY = e.clientY;
        startLeft = rect.left;
        startTop = rect.top;
        popover.classList.add('note-ai-popover-dragging');
        try { header.setPointerCapture(e.pointerId); } catch(err) {}
        e.preventDefault();
      }

      function move(e) {
        if (!dragging) return;
        var pos = clampPosition(startLeft + e.clientX - startX, startTop + e.clientY - startY);
        popover.classList.add('is-dragged');
        popover.style.setProperty('left', pos.left + 'px', 'important');
        popover.style.setProperty('top', pos.top + 'px', 'important');
        popover.style.setProperty('right', 'auto', 'important');
        popover.style.setProperty('bottom', 'auto', 'important');
        popover.style.setProperty('transform', 'none', 'important');
      }

      function end(e) {
        if (!dragging) return;
        dragging = false;
        popover.classList.remove('note-ai-popover-dragging');
        try { header.releasePointerCapture(e.pointerId); } catch(err) {}
      }

      function onResize() {
        if (!popover.classList.contains('is-open') || self.isSmallTopicAIViewport()) return;
        if (!popover.classList.contains('is-dragged')) return;
        var rect = popover.getBoundingClientRect();
        var pos = clampPosition(rect.left, rect.top);
        popover.style.setProperty('left', pos.left + 'px', 'important');
        popover.style.setProperty('top', pos.top + 'px', 'important');
        popover.style.setProperty('right', 'auto', 'important');
        popover.style.setProperty('bottom', 'auto', 'important');
      }

      header.addEventListener('pointerdown', begin);
      header.addEventListener('pointermove', move);
      header.addEventListener('pointerup', end);
      header.addEventListener('pointercancel', end);
      window.addEventListener('resize', onResize);
      return function() {
        header.removeEventListener('pointerdown', begin);
        header.removeEventListener('pointermove', move);
        header.removeEventListener('pointerup', end);
        header.removeEventListener('pointercancel', end);
        window.removeEventListener('resize', onResize);
      };
    },

    renderTopicSummaryAIQuickActions: function() {
      var ui = this.topicSummaryAI;
      if (!ui || !ui.quickActions) return;
      var self = this;
      var actions = this.topicSummaryAIActions();
      ui.quickActions.innerHTML = actions.map(function(action, idx) {
        return '<button type="button" data-topic-summary-ai-action="' + idx + '" title="' + attr(action.prompt) + '">' + html(action.label) + '</button>';
      }).join('');
      Array.prototype.forEach.call(ui.quickActions.querySelectorAll('[data-topic-summary-ai-action]'), function(btn) {
        btn.addEventListener('click', function() {
          var action = actions[parseInt(btn.getAttribute('data-topic-summary-ai-action'), 10)];
          ui.prompt.value = action ? action.prompt : '';
          ui.prompt.focus();
          ui.prompt.select();
        });
      });
    },

    updateTopicSummaryAIContextButton: function() {
      var ui = this.topicSummaryAI;
      if (!ui || !ui.contextButton) return;
      var text = this.topicSummaryAIContextText || '';
      ui.contextButton.textContent = tf('topic.ai.context_chars', 'Context {count} chars', { count: text.length });
      ui.contextButton.title = t('topic.ai.context_editor_title', 'Edit topic context');
    },

    isSmallTopicAIViewport: function() {
      return window.matchMedia ? window.matchMedia('(max-width: 640px)').matches : window.innerWidth <= 640;
    },

    positionTopicSummaryAI: function() {
      var ui = this.topicSummaryAI;
      if (!ui || !ui.popover) return;
      var popover = ui.popover;
      if (this.isSmallTopicAIViewport()) {
        document.documentElement.style.setProperty('--note-ai-vv-top', Math.round((window.visualViewport && window.visualViewport.offsetTop) || 0) + 'px');
        popover.style.left = '';
        popover.style.top = '';
        popover.style.transform = '';
        return;
      }
      var anchor = this.topicSummaryAIActiveKind === 'comment'
        ? (byId('topicCommentAIButton') || byId('topicCommentComposer'))
        : (byId('topicSummaryAIButton') || byId('topicSummaryComposer'));
      var rect = anchor ? anchor.getBoundingClientRect() : { left: window.innerWidth / 2, bottom: 120 };
      var width = 360;
      var x = Math.max(12 + width / 2, Math.min(window.innerWidth - 12 - width / 2, rect.left + rect.width / 2));
      var y = Math.min(window.innerHeight - 190, Math.max(48, rect.bottom + 8));
      popover.style.left = x + 'px';
      popover.style.top = y + 'px';
      popover.style.transform = 'translateX(-50%)';
    },

    toggleTopicSummaryAIExpanded: function() {
      var ui = this.topicSummaryAI;
      if (!ui) return;
      var expanded = !ui.popover.classList.contains('is-expanded');
      ui.popover.classList.toggle('is-expanded', expanded);
      ui.popover.setAttribute('aria-modal', expanded ? 'true' : 'false');
      ui.prompt.setAttribute('rows', expanded ? '6' : '1');
      ui.expandBtn.setAttribute('aria-pressed', expanded ? 'true' : 'false');
      ui.expandBtn.innerHTML = '<i class="fa-solid ' + (expanded ? 'fa-compress' : 'fa-expand') + '"></i>';
      ui.prompt.focus();
    },

    closeTopicSummaryAI: function() {
      if (!this.topicSummaryAI) return;
      this.topicSummaryAI.popover.classList.remove('is-open', 'is-expanded', 'note-ai-popover-dragging');
      this.topicSummaryAI.status.classList.remove('is-streaming');
      this.topicSummaryAI.status.textContent = '';
      document.body.classList.remove('note-ai-mobile-open');
      if (window.BookStarkScrollLock) BookStarkScrollLock.unlock('topic-summary-ai');
    },

    openTopicSummaryAIContextEditor: function() {
      var self = this;
      var overlay = document.createElement('div');
      overlay.className = 'asset-modal-backdrop open topic-summary-ai-context-modal';
      overlay.innerHTML = '' +
        '<div class="asset-modal asset-modal-size-md" role="dialog" aria-modal="true">' +
          '<div class="asset-modal-head">' +
            '<div class="asset-modal-title">' + html(t('topic.ai.context_editor_title', 'Edit topic context')) + '</div>' +
            '<button type="button" class="editor-modal-close" data-close-topic-ai-context aria-label="' + attr(t('dialog.close', 'Close')) + '"><i class="fa-solid fa-xmark"></i></button>' +
          '</div>' +
          '<div class="asset-modal-body">' +
            '<textarea class="dialog-input topic-summary-ai-context-textarea" rows="12">' + html(this.topicSummaryAIContextText || '') + '</textarea>' +
          '</div>' +
          '<div class="asset-modal-foot">' +
            '<button type="button" class="bs-btn bs-btn-cancel" data-close-topic-ai-context>' + html(t('dialog.cancel', 'Cancel')) + '</button>' +
            '<button type="button" class="bs-btn bs-btn-primary" data-save-topic-ai-context>' + html(t('topic.save', 'Save')) + '</button>' +
          '</div>' +
        '</div>';
      document.body.appendChild(overlay);
      if (window.BookStarkScrollLock) BookStarkScrollLock.lock('topic-summary-ai-context');
      var textarea = overlay.querySelector('textarea');
      function close() {
        try { document.body.removeChild(overlay); } catch(e) {}
        if (window.BookStarkScrollLock) BookStarkScrollLock.unlock('topic-summary-ai-context');
      }
      Array.prototype.forEach.call(overlay.querySelectorAll('[data-close-topic-ai-context]'), function(btn) {
        btn.addEventListener('click', close);
      });
      overlay.querySelector('[data-save-topic-ai-context]').addEventListener('click', function() {
        self.topicSummaryAIContextText = textarea.value || '';
        self.updateTopicSummaryAIContextButton();
        close();
      });
      overlay.addEventListener('click', function(e) {
        if (e.target === overlay) close();
      });
      textarea.focus();
      textarea.select();
    },

    buildTopicAIAssistantContext: function() {
      var detail = this.detail || {};
      var topic = detail.topic || {};
      var summaries = detail.summaries || [];
      var tasks = detail.tasks || [];
      var lines = [];
      var maxChars = 16000;

      function clean(value) {
        return String(value || '').replace(/\s+\n/g, '\n').trim();
      }

      function pushBlock(title, bodyLines) {
        lines.push('');
        lines.push('【' + title + '】');
        (bodyLines || []).forEach(function(line) {
          var text = clean(line);
          if (text) lines.push(text);
        });
      }

      lines.push('【专题上下文】');
      lines.push('标题：' + (topic.title || '未命名专题'));
      lines.push('核心问题：' + (topic.question || '未填写'));
      lines.push('创建时间：' + (formatDateOnly(topic.create_time) || '-'));
      lines.push('最近更新：' + (formatDateOnly(topic.modify_time) || '-'));
      lines.push('统计：小结 ' + summaries.length + '，待办 ' + tasks.length);

      if (summaries.length) {
        pushBlock('小结', summaries.map(function(item, index) {
          var type = summaryType(item.summary_type) === 'ai' ? 'AI' : '手写';
          var time = formatDate(item.modify_time || item.create_time);
          return (index + 1) + '. [' + type + (time ? ' · ' + time : '') + '] ' + (item.content || '').trim();
        }));
      } else {
        pushBlock('小结', ['暂无小结']);
      }

      if (tasks.length) {
        pushBlock('待办', tasks.map(function(item, index) {
          var status = item.done ? '已完成' : '未完成';
          var due = item.due_date ? ' · 到期 ' + item.due_date : '';
          return (index + 1) + '. [' + status + due + '] ' + (item.content || '');
        }));
      } else {
        pushBlock('待办', ['暂无待办']);
      }

      var text = lines.join('\n').trim();
      if (text.length > maxChars) {
        text = text.slice(0, maxChars) + '\n\n【截断说明】专题内容较长，以上为前 ' + maxChars + ' 字上下文。';
      }
      return text;
    },

    ensureTopicAIAssistant: function() {
      if (this.topicAIAssistant) return this.topicAIAssistant;
      if (typeof AIReadingAssistant === 'undefined' || !AIReadingAssistant.create) return null;
      var self = this;
      this.topicAIAssistant = AIReadingAssistant.create({
        panelId: 'topicAIAssistantPanel',
        title: t('topic.ai.assistant.title', 'AI Topic Assistant'),
        placeholder: t('topic.ai.assistant.placeholder', 'Ask a question about this topic...'),
        fullButtonLabel: t('topic.ai.full', 'Full text'),
        fullContextLabel: t('topic.ai.full', 'Full text'),
        contextLabel: t('topic.ai.context_label', 'Topic context'),
        contextEditorTitle: t('topic.ai.context_editor_title', 'Edit topic context'),
        allowContextEdit: true,
        openContextEditorOnFullClick: true,
        emptyContextText: t('topic.ai.empty_context', 'No context selected'),
        emptyFullContextToast: t('topic.ai.empty_full_context', 'This topic has no content'),
        disabledToast: t('topic.ai.disabled', 'AI is not enabled'),
        scene: 'topic_assistant',
        beforeOpen: function() {
          if (!self.selectedId || !self.detail || !self.detail.topic) {
            toast(t('topic.toast.select_first', 'Select a topic first'), 'warning');
            return false;
          }
          return true;
        },
        getFullContext: function() {
          return self.buildTopicAIAssistantContext();
        },
        getInitialContext: function() {
          return { kind: 'full', text: self.buildTopicAIAssistantContext() };
        },
        getSystemPrompt: function() {
          return (window.AI_SYSTEM_PROMPT_MD || '你是 BookStark 的知识整理助手。') +
            '\n你现在是 AI 专题助手。请只基于当前专题上下文回答问题，必要时指出上下文中缺少的信息。不要输出编辑器操作指令。';
        },
        getActions: function() {
          return [
            { label: t('topic.ai.action.summarize', 'Summarize topic'), prompt: '请总结这个专题，先给一句话结论，再列出 5 个核心要点和证据来源。' },
            { label: t('topic.ai.action.conclusion', 'Extract conclusions'), prompt: '请提炼当前专题已经能支持的结论，并标注哪些结论仍缺证据。' },
            { label: t('topic.ai.action.gaps', 'Find gaps'), prompt: '请检查这个专题的小结和待办，指出关键遗漏、矛盾和需要补充验证的地方。' },
            { label: t('topic.ai.action.next', 'Generate next steps'), prompt: '请基于当前专题生成下一步行动计划，按优先级列出 5 条。' },
            { label: t('topic.ai.action.outline', 'Organize materials'), prompt: '请按主题或时间线梳理当前专题的小结和待办，输出清晰的结构化脉络。' }
          ];
        }
      });
      return this.topicAIAssistant;
    },

    openTopicAIAssistant: function() {
      if (!window.AI_ENABLED || typeof AIHelper === 'undefined') {
        toast(t('topic.ai.disabled', 'AI is not enabled'), 'warning');
        return;
      }
      var assistant = this.ensureTopicAIAssistant();
      if (!assistant) {
        toast(t('topic.ai.load_failed', 'AI topic assistant failed to load. Refresh and try again.'), 'error');
        return;
      }
      assistant.open();
    },

    openTopicSummaryAI: function() {
      if (!this.selectedId) {
        toast(t('topic.toast.select_first', 'Select a topic first'), 'warning');
        return;
      }
      if (!window.AI_ENABLED || typeof AIHelper === 'undefined') {
        toast(t('topic.ai.disabled', 'AI is not enabled'), 'warning');
        return;
      }
      var ui = this.ensureTopicSummaryAI();
      this.topicSummaryAIActiveComposer = this.topicSummaryComposer;
      this.topicSummaryAIActiveStatusID = 'topicSummaryAIStreamStatus';
      this.topicSummaryAIActiveScene = 'topic-summary';
      this.topicSummaryAIActiveKind = 'summary';
      this.topicSummaryAIContextText = this.getTopicSummaryAIContextFromEditor();
      this.updateTopicSummaryAIContextButton();
      this.renderTopicSummaryAIQuickActions();
      ui.prompt.value = '';
      ui.status.classList.remove('is-streaming');
      ui.status.textContent = '';
      ui.popover.classList.remove('is-expanded', 'is-dragged', 'note-ai-popover-dragging');
      ui.popover.style.left = '';
      ui.popover.style.top = '';
      ui.popover.style.right = '';
      ui.popover.style.bottom = '';
      ui.popover.style.transform = '';
      this.positionTopicSummaryAI();
      if (this.isSmallTopicAIViewport()) document.body.classList.add('note-ai-mobile-open');
      ui.popover.classList.add('is-open');
      if (window.BookStarkScrollLock) BookStarkScrollLock.lock('topic-summary-ai');
      window.setTimeout(function() { ui.prompt.focus(); ui.prompt.select(); }, 0);
    },

    openTopicCommentAI: function() {
      if (!this.topicCommentTarget) {
        toast(t('topic.comment.select_target', 'Select a material, summary, or todo to comment on'), 'warning');
        return;
      }
      if (!window.AI_ENABLED || typeof AIHelper === 'undefined') {
        toast(t('topic.ai.disabled', 'AI is not enabled'), 'warning');
        return;
      }
      var ui = this.ensureTopicSummaryAI();
      var composer = this.topicCommentComposer;
      var value = composer && composer.getValue ? (composer.getValue() || '') : '';
      var range = composer && composer.getSelectionRange ? composer.getSelectionRange() : null;
      this.topicSummaryAIActiveComposer = composer;
      this.topicSummaryAIActiveStatusID = 'topicCommentAIStreamStatus';
      this.topicSummaryAIActiveScene = 'topic-comment';
      this.topicSummaryAIActiveKind = 'comment';
      this.topicSummaryAIContextText = range && range.from !== range.to
        ? value.substring(range.from, range.to).trim()
        : value.trim();
      this.updateTopicSummaryAIContextButton();
      this.renderTopicSummaryAIQuickActions();
      ui.prompt.value = '';
      ui.status.classList.remove('is-streaming');
      ui.status.textContent = '';
      ui.popover.classList.remove('is-expanded', 'is-dragged', 'note-ai-popover-dragging');
      ui.popover.style.left = '';
      ui.popover.style.top = '';
      ui.popover.style.right = '';
      ui.popover.style.bottom = '';
      ui.popover.style.transform = '';
      this.positionTopicSummaryAI();
      if (this.isSmallTopicAIViewport()) document.body.classList.add('note-ai-mobile-open');
      ui.popover.classList.add('is-open');
      if (window.BookStarkScrollLock) BookStarkScrollLock.lock('topic-summary-ai');
      window.setTimeout(function() { ui.prompt.focus(); ui.prompt.select(); }, 0);
    },

    runTopicSummaryAI: function() {
      var ui = this.topicSummaryAI;
      var composer = this.topicSummaryAIActiveComposer || this.topicSummaryComposer;
      if (!ui || !composer) return;
      var instruction = (ui.prompt.value || '').trim();
      if (!instruction) {
        ui.prompt.focus();
        return;
      }
      if (this.topicSummaryAIStreamCtrl) {
        try { this.topicSummaryAIStreamCtrl.abort(); } catch(e) {}
        this.topicSummaryAIStreamCtrl = null;
      }
      var value = composer.getValue ? composer.getValue() : '';
      var range = composer.getSelectionRange ? composer.getSelectionRange() : { from: value.length, to: value.length };
      if (!range) range = { from: value.length, to: value.length };
      var insertedEnd = range.from;
      var started = false;
      var writtenChars = 0;
      var self = this;
      var context = (this.topicSummaryAIContextText || '').trim();
      var contextTitle = this.topicSummaryAIActiveKind === 'comment' ? '评论上下文' : '小结上下文';
      var outputName = this.topicSummaryAIActiveKind === 'comment' ? '专题评论编辑器' : '专题小结编辑器';
      var userMsg = context ? '【' + contextTitle + '】\n' + context +
        '\n\n【指令】\n' + instruction +
        '\n\n请只返回要写入' + outputName + '的 Markdown 内容，不要解释。'
        : '【指令】\n' + instruction +
        '\n\n请只返回要写入' + outputName + '的 Markdown 内容，不要解释。';
      ui.status.classList.add('is-streaming');
      ui.status.textContent = t('note.ai.streaming', 'Streaming...');
      ui.popover.classList.remove('is-open');
      document.body.classList.remove('note-ai-mobile-open');
      if (window.BookStarkScrollLock) BookStarkScrollLock.unlock('topic-summary-ai');
      if (this.topicSummaryAIActiveKind !== 'comment') this.setSummaryDraftType('ai');
      this.setTopicSummaryAIStreamStatus('streaming', 0);
      this.topicSummaryAIStreamCtrl = AIHelper.complete({
        messages: AIHelper.buildMessages(window.AI_SYSTEM_PROMPT_MD || '你是 BookStark 的知识整理助手，擅长把专题内容提炼成清晰、可保存的 Markdown 小结。', userMsg),
        scene: this.topicSummaryAIActiveScene || 'topic-summary',
        onChunk: function(chunk) {
          if (!started) {
            if (composer.replaceRange) {
              insertedEnd = composer.replaceRange(range.from, range.to, '');
            } else {
              var before = value.slice(0, range.from);
              var after = value.slice(range.to);
              composer.setValue(before + after);
              insertedEnd = range.from;
            }
            started = true;
          }
          if (composer.replaceRange) {
            insertedEnd = composer.replaceRange(insertedEnd, insertedEnd, chunk);
          } else {
            var current = composer.getValue ? composer.getValue() : '';
            composer.setValue(current.slice(0, insertedEnd) + chunk + current.slice(insertedEnd));
            insertedEnd += chunk.length;
          }
          writtenChars += chunk.length;
          self.setTopicSummaryAIStreamStatus('streaming', writtenChars);
          if (self.topicSummaryAIActiveKind === 'comment') self.updateTopicCommentPreview();
          else self.updateTopicSummaryPreview();
        },
        onDone: function() {
          self.topicSummaryAIStreamCtrl = null;
          ui.status.classList.remove('is-streaming');
          ui.status.textContent = '';
          self.setTopicSummaryAIStreamStatus('idle');
          if (self.topicSummaryAIActiveKind === 'comment') self.updateTopicCommentPreview();
          else self.updateTopicSummaryPreview();
        },
        onError: function(message) {
          self.topicSummaryAIStreamCtrl = null;
          ui.status.classList.remove('is-streaming');
          ui.status.textContent = message || t('note.ai.toast.error', 'AI call failed');
          self.setTopicSummaryAIStreamStatus('error', 0, ui.status.textContent);
          toast(ui.status.textContent, 'error');
        }
      });
    },

    saveInlineSummary: async function() {
      if (!this.selectedId) {
        toast(t('topic.toast.select_first', 'Select a topic first'), 'warning');
        return;
      }
      var content = this.getInlineSummaryValue();
      if (!content) {
        toast(t('topic.ai.summary.empty', 'Enter a summary'), 'warning');
        if (this.topicSummaryComposer && this.topicSummaryComposer.focus) this.topicSummaryComposer.focus();
        return;
      }
      if (this.savingInlineSummary) return;
      this.savingInlineSummary = true;
      var btn = byId('topicSummarySaveButton');
      if (btn) btn.disabled = true;
      var summaryId = this.editingSummaryId || 0;
      var closeSummaryModal = this.topicSummaryEditorExpanded;
      try {
        await apiJSON('/api/topics/' + this.selectedId + '/summaries' + (summaryId ? '/' + summaryId : ''), {
          method: summaryId ? 'PUT' : 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            content: content,
            summary_type: this.summaryDraftType
          })
        });
        this.clearInlineSummary();
        toast(t('topic.save.success', 'Saved'), 'success');
        await this.refreshSelectedTopic({ silent: true });
        if (closeSummaryModal) this.restoreTopicSummaryEditor();
      } catch (err) {
        toast(err.message, 'error');
      } finally {
        this.savingInlineSummary = false;
        if (btn) btn.disabled = false;
      }
    },

    deleteSummary: async function(summaryId) {
      if (!this.selectedId || !summaryId) return;
      var summary = ((this.detail || {}).summaries || []).find(function(row) { return Number(row.summary_id) === Number(summaryId); });
      var ok = !window.BSDialog || await BSDialog.confirm2(formatDeleteConfirmation(t('topic.summary.delete.confirm', 'Delete summary "{name}"?'), summary && summary.content, summaryId, true));
      if (!ok) return;
      try {
        await apiJSON('/api/topics/' + this.selectedId + '/summaries/' + summaryId, { method: 'DELETE' });
        toast(t('topic.delete.success', 'Deleted'), 'success');
        if (this.editingSummaryId === summaryId) this.clearInlineSummary();
        await this.refreshSelectedTopic({ silent: true });
      } catch (err) {
        toast(err.message, 'error');
      }
    },

    openTaskModal: function(task) {
      if (!this.selectedId) return;
      var editing = task || null;
      this.editingTopicTaskId = editing ? Number(editing.task_id || 0) : 0;
      this.editingTopicTask = editing;
      byId('topicTaskContent').value = editing ? (editing.content || '') : '';
      byId('topicTaskDueDate').value = editing ? (editing.due_date || '') : defaultDueDate();
      byId('topicTaskModalTitle').textContent = editing ? t('topic.task.modal.edit', 'Edit todo') : t('topic.task.modal.new', 'New todo');
      byId('topicTaskSubmitBtn').textContent = editing ? t('topic.task.save', 'Save todo') : t('topic.task.add', 'Add todo');
      var deleteBtn = byId('topicTaskDeleteBtn');
      if (deleteBtn) deleteBtn.classList.toggle('hidden', !editing);
      this.openModal('topicTaskModal');
      setTimeout(function() {
        var textarea = byId('topicTaskContent');
        if (textarea) textarea.focus();
      }, 80);
    },

    saveTask: async function() {
      if (!this.selectedId) return;
      var content = byId('topicTaskContent').value.trim();
      var dueDate = byId('topicTaskDueDate').value || '';
      if (!content) {
        toast(t('topic.task.toast.empty', 'Enter todo content'), 'warning');
        return;
      }
      var editing = this.editingTopicTask;
      var submitBtn = byId('topicTaskSubmitBtn');
      if (submitBtn) submitBtn.disabled = true;
      var payload = {
        content: content,
        due_date: dueDate,
        done: editing ? !!editing.done : false,
        parent_id: editing ? Number(editing.parent_id || 0) : 0,
        topic_id: this.selectedId
      };
      try {
        await apiJSON(editing ? '/api/tasks/' + editing.task_id : '/api/tasks', {
          method: editing ? 'PUT' : 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(payload)
        });
        this.closeModal('topicTaskModal');
        this.editingTopicTaskId = 0;
        this.editingTopicTask = null;
        toast(t(editing ? 'topic.task.toast.saved' : 'topic.create.success', editing ? 'Todo saved' : 'Created'), 'success');
        await this.refreshSelectedTopic({ silent: true });
      } catch (err) {
        toast(err.message, 'error');
      } finally {
        if (submitBtn) submitBtn.disabled = false;
      }
    },

    updateTaskDueDate: async function(task, dueDate) {
      if (!task) return;
      try {
        await apiJSON('/api/tasks/' + task.task_id, {
          method: 'PUT',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            content: task.content || '',
            due_date: dueDate || '',
            done: !!task.done,
            parent_id: Number(task.parent_id || 0),
            topic_id: this.selectedId
          })
        });
        toast(t('topic.task.toast.due_saved', 'Due date updated'), 'success');
        await this.refreshSelectedTopic({ silent: true });
      } catch (err) {
        toast(err.message, 'error');
      }
    },

    openTaskDueDatePicker: function(task, source) {
      if (!task || !source || source.__topicTaskDuePickerOpen) return;
      var self = this;
      var input = document.createElement('input');
      var currentDue = task.due_date || '';
      var closed = false;
      input.type = 'date';
      input.value = currentDue;
      input.setAttribute('aria-label', t('topic.task.due_aria', 'Set due date'));
      input.tabIndex = -1;
      input.style.position = 'fixed';
      input.style.left = '-9999px';
      input.style.top = '-9999px';
      input.style.opacity = '0';
      input.style.width = '1px';
      input.style.height = '1px';
      input.style.pointerEvents = 'none';
      source.__topicTaskDuePickerOpen = true;
      document.body.appendChild(input);
      if (typeof source.blur === 'function') source.blur();
      function close() {
        if (closed) return;
        closed = true;
        source.__topicTaskDuePickerOpen = false;
        if (input.parentNode) input.parentNode.removeChild(input);
      }
      function save() {
        var value = input.value || '';
        if (value === currentDue) {
          close();
          return;
        }
        self.updateTaskDueDate(task, value).then(close);
      }
      input.addEventListener('change', save);
      input.addEventListener('keydown', function(e) {
        if (e.key === 'Enter') {
          e.preventDefault();
          save();
        } else if (e.key === 'Escape') {
          e.preventDefault();
          close();
        }
      });
      input.addEventListener('blur', function() {
        setTimeout(close, 240);
      });
      setTimeout(function() {
        input.focus();
        if (typeof input.showPicker === 'function') {
          try {
            input.showPicker();
            return;
          } catch (err) {}
        }
        input.click();
      }, 0);
    },

    deleteTask: async function(task) {
      if (!task || !task.task_id) return;
      var message = task.child_total ? t('task.confirm.delete_children', 'Delete todo "{name}" and its subtodos?') : t('topic.task.delete.confirm', 'Delete todo "{name}"?');
      var ok = !window.BSDialog || await BSDialog.confirm2(formatDeleteConfirmation(message, task.content, task.task_id, true));
      if (!ok) return;
      try {
        await apiJSON('/api/tasks/' + task.task_id, { method: 'DELETE' });
        if (this.editingTopicTaskId === task.task_id) {
          this.editingTopicTaskId = 0;
          this.editingTopicTask = null;
          this.closeModal('topicTaskModal');
        }
        toast(t('topic.task.toast.deleted', 'Todo deleted'), 'success');
        await this.refreshSelectedTopic({ silent: true });
      } catch (err) {
        toast(err.message, 'error');
      }
    },

    toggleTaskDone: async function(task) {
      try {
        await apiJSON('/api/tasks/' + task.task_id + '/done', {
          method: 'PATCH',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ done: !task.done })
        });
        await this.refreshSelectedTopic({ silent: true });
      } catch (err) {
        toast(err.message, 'error');
      }
    },

    openModal: function(id) {
      var modal = byId(id);
      if (!modal) return;
      this.topicModalPreviousFocus = document.activeElement;
      modal.classList.add('open');
      modal.setAttribute('aria-hidden', 'false');
      document.body.classList.add('topic-modal-open');
      if (window.BookStarkScrollLock) BookStarkScrollLock.lock('topic-modal');
      if (!this.topicModalFocusHandler) {
        var self = this;
        this.topicModalFocusHandler = function(e) { self.trapTopicModalFocus(e); };
      }
      document.removeEventListener('keydown', this.topicModalFocusHandler, true);
      document.addEventListener('keydown', this.topicModalFocusHandler, true);
      this.updateTopicFab();
      setTimeout(function() {
        var input = modal.querySelector('input, textarea, select, .asset-combobox-input') || modal.querySelector('button');
        if (input) input.focus();
      }, 30);
    },

    closeModal: function(id) {
      var modal = byId(id);
      if (modal) {
        modal.classList.remove('open');
        modal.setAttribute('aria-hidden', 'true');
      }
      if (id === 'topicTaskModal') {
        this.editingTopicTaskId = 0;
        this.editingTopicTask = null;
        var deleteBtn = byId('topicTaskDeleteBtn');
        if (deleteBtn) deleteBtn.classList.add('hidden');
      }
      if (id === 'topicEditModal') {
        this.hideTopicQuestionPreview();
        this.hideTopicQuestionEmojiPicker();
      }
      if (id === 'topicItemModal') {
        document.body.classList.remove('topic-resource-modal-open');
      }
      if (id === 'topicMobileCommentsModal') {
        var commentsBtn = byId('topicMobileCommentsBtn');
        if (commentsBtn) commentsBtn.setAttribute('aria-expanded', 'false');
        this.hideTopicCommentEmojiPicker();
        this.moveTopicCommentPanel(false);
      }
      this.syncTopicModalState();
      if (!document.querySelector('.asset-modal-backdrop.open') && this.topicModalFocusHandler) {
        document.removeEventListener('keydown', this.topicModalFocusHandler, true);
        if (this.topicModalPreviousFocus && document.contains(this.topicModalPreviousFocus) && typeof this.topicModalPreviousFocus.focus === 'function') {
          this.topicModalPreviousFocus.focus();
        }
        this.topicModalPreviousFocus = null;
      }
    },

    syncTopicModalState: function() {
      if (document.querySelector('.asset-modal-backdrop.open')) {
        document.body.classList.add('topic-modal-open');
        if (window.BookStarkScrollLock) BookStarkScrollLock.lock('topic-modal');
      } else {
        document.body.classList.remove('topic-modal-open');
        if (window.BookStarkScrollLock) BookStarkScrollLock.unlock('topic-modal');
      }
      this.updateTopicFab();
    },

    trapTopicModalFocus: function(e) {
      if (e.key !== 'Tab') return;
      var openModals = document.querySelectorAll('.asset-modal-backdrop.open');
      var modal = openModals.length ? openModals[openModals.length - 1] : null;
      if (!modal) return;
      var panel = modal.querySelector('.asset-modal');
      if (!panel) return;
      var focusable = Array.prototype.slice.call(panel.querySelectorAll('a[href], button:not([disabled]), textarea:not([disabled]), input:not([disabled]), select:not([disabled]), [tabindex]:not([tabindex="-1"])')).filter(function(el) {
        return el.offsetParent !== null || el === document.activeElement;
      });
      if (!focusable.length) return;
      var first = focusable[0];
      var last = focusable[focusable.length - 1];
      if (!panel.contains(document.activeElement)) {
        e.preventDefault();
        (e.shiftKey ? last : first).focus();
      } else if (e.shiftKey && document.activeElement === first) {
        e.preventDefault();
        last.focus();
      } else if (!e.shiftKey && document.activeElement === last) {
        e.preventDefault();
        first.focus();
      }
    }
  };

  window.TopicsApp = app;
  document.addEventListener('DOMContentLoaded', function() { app.init(); });
})();
