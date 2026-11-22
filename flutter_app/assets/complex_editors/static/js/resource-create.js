(function(global) {
  'use strict';

  var state = {
    type: 'note',
    editorType: 'markdown',
    options: null,
    composer: null,
    tagInput: null,
    bookPicker: null,
    folderPicker: null,
    books: [],
    folderAbortController: null,
    folderLoadSeq: 0,
    bookmarkFavicon: '',
    busy: false,
    preview: false,
    previousFocus: null
  };

  var TYPE_META = {
    note: { icon: 'fa-note-sticky', titleKey: 'nav.create_note', title: '新建笔记', hintKey: 'topic.resource.create.note_hint', hint: '使用笔记页相同的 Markdown 编辑、标签、图片与预览能力' },
    article: { icon: 'fa-pen-nib', titleKey: 'nav.create_article', title: '新建文章', hintKey: 'topic.resource.create.article_hint', hint: '设置文章类型、标题、描述和标签' },
    bookmark: { icon: 'fa-bookmark', titleKey: 'nav.create_bookmark', title: '新建书签', hintKey: 'topic.resource.create.bookmark_hint', hint: '支持网页信息解析、标签和公开状态' },
    document: { icon: 'fa-file-lines', titleKey: 'topic.resource.create.document_title', title: '新建文档', hintKey: 'topic.resource.create.document_hint', hint: '选择书籍、目录和对应的文档编辑器' }
  };

  var EMOJIS = ['😀', '😁', '😂', '😊', '😍', '🤔', '👍', '👏', '🔥', '⭐', '✅', '💡', '📌', '📚', '🎯', '🚀'];

  function $(id) { return document.getElementById(id); }
  function tr(key, fallback) {
    if (typeof global.__ !== 'function') return fallback;
    var value = global.__(key);
    return value && value !== key ? value : fallback;
  }
  function esc(value) {
    var node = document.createElement('div');
    node.textContent = value == null ? '' : String(value);
    return node.innerHTML;
  }
  function request(url, options) {
    var fetcher = typeof global.csrfFetch === 'function' ? global.csrfFetch : global.fetch.bind(global);
    return fetcher(url, options || {}).then(function(response) {
      return response.json().catch(function() { return {}; }).then(function(payload) {
        if (!response.ok || payload.code && payload.code !== 0) {
          throw new Error(payload.message || ('HTTP ' + response.status));
        }
        return payload;
      });
    });
  }
  function snippet(value, max) {
    return String(value || '').replace(/[#*`>_[\]()]/g, '').replace(/\s+/g, ' ').trim().slice(0, max || 120);
  }
  function setMessage(message, error) {
    var el = $('resourceCreateMessage');
    if (!el) return;
    el.textContent = message || '';
    el.classList.toggle('is-error', !!error);
  }
  function focusInvalid(id, message) {
    var field = $(id);
    if (id === 'resourceCreateDocumentBook' && state.bookPicker) {
      state.bookPicker.setInvalid(true);
      state.bookPicker.focus();
      state.bookPicker.host.scrollIntoView({ block: 'center', behavior: 'smooth' });
      throw new Error(message);
    }
    if (id === 'resourceCreateDocumentFolder' && state.folderPicker) {
      state.folderPicker.setInvalid(true);
      state.folderPicker.focus();
      state.folderPicker.host.scrollIntoView({ block: 'center', behavior: 'smooth' });
      throw new Error(message);
    }
    if (field) {
      field.setAttribute('aria-invalid', 'true');
      if (id === 'resourceCreateEditor' && state.composer) state.composer.focus();
      else field.focus();
      field.scrollIntoView({ block: 'center', behavior: 'smooth' });
    }
    throw new Error(message);
  }
  function clearInvalid() {
    if (state.bookPicker) state.bookPicker.setInvalid(false);
    if (state.folderPicker) state.folderPicker.setInvalid(false);
    document.querySelectorAll('#resourceCreateContent [aria-invalid="true"]').forEach(function(el) {
      el.removeAttribute('aria-invalid');
    });
  }

  function renderKind() {
    var meta = TYPE_META[state.type];
    var title = tr(meta.titleKey, meta.title);
    var hint = tr(meta.hintKey, meta.hint);
    $('resourceCreateTitle').textContent = title;
    $('resourceCreateKind').innerHTML =
      '<span class="resource-create-kind-icon"><i class="fa-solid ' + meta.icon + '"></i></span>' +
      '<span class="resource-create-kind-copy">' + esc(title) + '<small>' + esc(hint) + '</small></span>';
  }

  function toolButton(action, icon, label) {
    return '<button class="resource-create-tool" type="button" data-resource-tool="' + action + '" title="' + esc(label) + '" aria-label="' + esc(label) + '"><i class="fa-solid ' + icon + '"></i></button>';
  }

  function composerMarkup(options) {
    options = options || {};
    return '<div class="resource-create-toolbar">' +
      toolButton('image', 'fa-image', tr('note.compose.image', '图片')) +
      toolButton('emoji', 'fa-face-smile', tr('note.compose.emoji', '表情')) +
      toolButton('preview', 'fa-file-lines', tr('note.compose.preview', '预览')) +
      toolButton('clear', 'fa-eraser', tr('note.compose.clear', '清空')) +
      '</div>' +
      '<div class="resource-create-emoji" id="resourceCreateEmoji" hidden></div>' +
      '<div class="resource-create-editor" id="resourceCreateEditor"></div>' +
      '<div class="resource-create-preview markdown-body" id="resourceCreatePreview" hidden></div>' +
      '<input type="file" id="resourceCreateImageInput" accept="image/*" hidden>' +
      (options.after || '');
  }

  function renderNote() {
    return '<div class="resource-create-fields">' +
      '<div class="resource-create-field"><span>' + esc(tr('topic.resource.create.note_content', '笔记内容')) + '</span>' +
      composerMarkup({ after:
        '<div class="resource-create-grid" style="margin-top:12px">' +
          '<label class="resource-create-field"><span>' + esc(tr('note.article.tags.label', '标签')) + '</span><div id="resourceCreateTags"></div></label>' +
          '<label class="resource-create-field"><span>' + esc(tr('note.visibility.label', '可见范围')) + '</span><select class="dialog-input" id="resourceCreateVisibility"><option value="0">' + esc(tr('note.visibility.private', '仅自己')) + '</option><option value="1">' + esc(tr('note.visibility.public', '公开')) + '</option></select></label>' +
        '</div>'
      }) + '</div></div>';
  }

  function typeGrid(prefix) {
    var types = [
      ['markdown', 'fa-file-lines', 'Markdown'],
      ['html', 'fa-code', 'HTML'],
      ['richdoc', 'fa-file-word', tr('topic.resource.create.document_richdoc', '富文档')],
      ['spreadsheet', 'fa-table', tr('topic.resource.create.document_spreadsheet', '电子表格')],
      ['presentation', 'fa-display', tr('topic.resource.create.document_presentation', '演示文稿')],
      ['drawing', 'fa-pen-ruler', tr('topic.resource.create.document_drawing', '画板')],
      ['mindmap', 'fa-diagram-project', tr('topic.resource.create.document_mindmap', '脑图')]
    ];
    return '<div class="resource-create-type-grid" id="' + prefix + 'TypeGrid">' + types.map(function(item) {
      return '<button type="button" class="resource-create-type' + (item[0] === 'markdown' ? ' active' : '') + '" data-resource-editor-type="' + item[0] + '" aria-pressed="' + (item[0] === 'markdown' ? 'true' : 'false') + '"><i class="fa-solid ' + item[1] + '"></i><span>' + esc(item[2]) + '</span></button>';
    }).join('') + '</div>';
  }

  function renderArticle() {
    return '<div class="resource-create-fields">' +
      '<fieldset class="resource-create-field"><legend>' + esc(tr('note.article.type.label', '文章类型')) + '</legend>' + typeGrid('resourceCreateArticle') + '</fieldset>' +
      '<label class="resource-create-field"><span>' + esc(tr('note.article.title.label', '文章标题')) + '</span><input class="dialog-input" id="resourceCreateArticleTitle" maxlength="200" autocomplete="off" placeholder="' + esc(tr('note.article.title.placeholder', '输入文章标题')) + '"></label>' +
      '<label class="resource-create-field"><span>' + esc(tr('note.article.desc.label', '文章描述')) + '</span><textarea class="dialog-input" id="resourceCreateArticleDesc" maxlength="500" placeholder="' + esc(tr('note.article.desc.placeholder', '简要说明文章内容')) + '"></textarea></label>' +
      '<label class="resource-create-field"><span>' + esc(tr('note.article.tags.label', '标签')) + '</span><div id="resourceCreateTags"></div></label>' +
      '</div>';
  }

  function renderBookmark() {
    return '<div class="resource-create-fields">' +
      '<label class="resource-create-field"><span>' + esc(tr('bookmark.dialog.url', '网址')) + '</span><input class="dialog-input" id="resourceCreateBookmarkURL" type="url" maxlength="2048" autocomplete="url" placeholder="https://"><small class="resource-create-meta-status" id="resourceCreateBookmarkMeta"></small></label>' +
      '<label class="resource-create-field"><span>' + esc(tr('bookmark.dialog.title', '标题')) + '</span><input class="dialog-input" id="resourceCreateBookmarkTitle" maxlength="500" autocomplete="off"></label>' +
      '<label class="resource-create-field"><span>' + esc(tr('bookmark.dialog.desc', '描述')) + '</span><textarea class="dialog-input" id="resourceCreateBookmarkDesc" maxlength="2000"></textarea></label>' +
      '<label class="resource-create-field"><span>' + esc(tr('bookmark.dialog.tags', '标签')) + '</span><div id="resourceCreateTags"></div></label>' +
      '<label class="resource-create-inline-control"><input type="checkbox" id="resourceCreateBookmarkPublic"><span>' + esc(tr('bookmark.dialog.public', '公开显示')) + '</span></label>' +
      '</div>';
  }

  function renderDocument() {
    return '<div class="resource-create-fields">' +
      '<div class="resource-create-grid">' +
        '<div class="resource-create-field"><span>' + esc(tr('topic.resource.create.document_book', '书籍')) + '</span><div id="resourceCreateDocumentBookPicker"></div><input type="hidden" id="resourceCreateDocumentBook" value=""></div>' +
        '<div class="resource-create-field"><span>' + esc(tr('topic.resource.create.document_folder', '目录')) + '</span><div id="resourceCreateDocumentFolderPicker"></div><input type="hidden" id="resourceCreateDocumentFolder" value="0"></div>' +
      '</div>' +
      '<fieldset class="resource-create-field"><legend>' + esc(tr('topic.resource.create.document_type', '文档类型')) + '</legend>' + typeGrid('resourceCreateDocument') + '</fieldset>' +
      '<label class="resource-create-field"><span>' + esc(tr('topic.resource.create.document_name', '文档名称')) + '</span><input class="dialog-input" id="resourceCreateDocumentName" maxlength="200" autocomplete="off" placeholder="' + esc(tr('topic.resource.create.document_name_placeholder', '输入文档名称')) + '"></label>' +
      '</div>';
  }

  function initComposer() {
    var host = $('resourceCreateEditor');
    if (!host || !global.MarkdownComposer) return;
    state.composer = global.MarkdownComposer.create(host, {
      placeholder: tr('note.compose.placeholder', '记录想法...（支持 Markdown）'),
      minHeight: 190,
      maxHeight: 360,
      submitOnCtrlEnter: true,
      onSubmit: function() {
        var form = $('resourceCreateForm');
        if (form && typeof form.requestSubmit === 'function') form.requestSubmit();
      },
      onPasteFile: uploadImage
    });
    var emoji = $('resourceCreateEmoji');
    if (emoji) {
      emoji.innerHTML = EMOJIS.map(function(item) { return '<button type="button" data-resource-emoji="' + item + '">' + item + '</button>'; }).join('');
    }
  }

  function initTagInput() {
    var container = $('resourceCreateTags');
    if (!container || typeof global.TagInput !== 'function') return;
    state.tagInput = new global.TagInput(container, {
      placeholder: tr('tag_input.placeholder', '搜索或新建标签...'),
      useSheet: true
    });
  }

  function selectEditorType(value) {
    state.editorType = value || 'markdown';
    document.querySelectorAll('#resourceCreateContent [data-resource-editor-type]').forEach(function(button) {
      var active = button.getAttribute('data-resource-editor-type') === state.editorType;
      button.classList.toggle('active', active);
      button.setAttribute('aria-pressed', active ? 'true' : 'false');
    });
  }

  function bindContent() {
    document.querySelectorAll('#resourceCreateContent [data-resource-editor-type]').forEach(function(button) {
      button.addEventListener('click', function() { selectEditorType(button.getAttribute('data-resource-editor-type')); });
    });
    document.querySelectorAll('#resourceCreateContent [data-resource-tool]').forEach(function(button) {
      button.addEventListener('click', function() { runTool(button.getAttribute('data-resource-tool'), button); });
    });
    document.querySelectorAll('#resourceCreateContent [data-resource-emoji]').forEach(function(button) {
      button.addEventListener('click', function() {
        if (state.composer) state.composer.insertAtCursor(button.getAttribute('data-resource-emoji'));
        var picker = $('resourceCreateEmoji');
        if (picker) picker.hidden = true;
      });
    });
    var imageInput = $('resourceCreateImageInput');
    if (imageInput) imageInput.addEventListener('change', function() {
      if (imageInput.files && imageInput.files[0]) uploadImage(imageInput.files[0]);
      imageInput.value = '';
    });
    if (state.type === 'bookmark') {
      var url = $('resourceCreateBookmarkURL');
      if (url) url.addEventListener('blur', fetchBookmarkMeta);
    }
    if (state.type === 'document') {
      initDocumentPickers();
    }
  }

  function render() {
    destroyFields();
    state.editorType = 'markdown';
    state.bookmarkFavicon = '';
    state.preview = false;
    renderKind();
    var content = $('resourceCreateContent');
    if (state.type === 'note') content.innerHTML = renderNote();
    else if (state.type === 'article') content.innerHTML = renderArticle();
    else if (state.type === 'bookmark') content.innerHTML = renderBookmark();
    else content.innerHTML = renderDocument();
    if (state.type === 'note') initComposer();
    if (state.type === 'note' || state.type === 'article' || state.type === 'bookmark') initTagInput();
    bindContent();
    setMessage('');
    setTimeout(function() {
      var field = content.querySelector('input:not([type="hidden"]), textarea, select, [contenteditable="true"]');
      if (state.composer) state.composer.focus();
      else if (field) field.focus();
    }, 40);
  }

  function destroyFields() {
    if (state.composer && typeof state.composer.destroy === 'function') state.composer.destroy();
    if (state.bookPicker && typeof state.bookPicker.destroy === 'function') state.bookPicker.destroy();
    if (state.folderPicker && typeof state.folderPicker.destroy === 'function') state.folderPicker.destroy();
    if (state.folderAbortController) state.folderAbortController.abort();
    state.composer = null;
    state.tagInput = null;
    state.bookPicker = null;
    state.folderPicker = null;
    state.folderAbortController = null;
    state.books = [];
    state.folderLoadSeq += 1;
  }

  function runTool(action, button) {
    if (action === 'image') {
      var input = $('resourceCreateImageInput');
      if (input) input.click();
    } else if (action === 'emoji') {
      var picker = $('resourceCreateEmoji');
      if (picker) picker.hidden = !picker.hidden;
    } else if (action === 'clear') {
      if (state.composer) state.composer.clear();
    } else if (action === 'preview') {
      state.preview = !state.preview;
      var editor = $('resourceCreateEditor');
      var preview = $('resourceCreatePreview');
      if (editor && preview) {
        editor.hidden = state.preview;
        preview.hidden = !state.preview;
        button.classList.toggle('active', state.preview);
        if (state.preview) {
          var value = state.composer ? state.composer.getValue() : '';
          preview.innerHTML = global.marked ? global.marked.parse(value || '') : esc(value);
        } else if (state.composer) {
          state.composer.focus();
        }
      }
    }
  }

  function insertImage(file, url) {
    if (!state.composer) return;
    var name = String(file.name || 'image').replace(/\.[^.]+$/, '');
    state.composer.insertAtCursor('![' + name + '](' + url + ')');
  }

  function uploadImage(file) {
    if (!file || !/^image\//.test(file.type || '')) {
      setMessage(tr('note.upload.not_image', '请选择图片文件'), true);
      return;
    }
    setMessage(tr('note.upload.uploading', '正在上传图片...'));
    function post() {
      var form = new FormData();
      form.append('file', file);
      form.append('category', 'note');
      return request('/api/uploads', { method: 'POST', body: form });
    }
    var upload = Promise.resolve(null);
    if (typeof global.computeFileHash === 'function' && typeof global.checkUploadByHash === 'function') {
      upload = global.computeFileHash(file).then(global.checkUploadByHash).catch(function() { return null; });
    }
    upload.then(function(existing) {
      if (existing && existing.url) return { data: existing };
      return post();
    }).then(function(result) {
      var data = result.data || {};
      if (!data.url) throw new Error(tr('note.toast.image_upload_failed', '图片上传失败'));
      insertImage(file, data.url);
      setMessage(tr('note.toast.image_upload_success', '图片上传成功'));
    }).catch(function(error) {
      setMessage(error.message || tr('note.toast.image_upload_failed', '图片上传失败'), true);
    });
  }

  function fetchBookmarkMeta() {
    var url = $('resourceCreateBookmarkURL');
    var status = $('resourceCreateBookmarkMeta');
    if (!url || !/^https?:\/\//i.test(url.value.trim())) return;
    if (status) status.textContent = tr('bookmark.meta.parsing', '正在解析网页信息...');
    request('/api/fetch-meta', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ url: url.value.trim() })
    }).then(function(result) {
      var data = result.data || {};
      var title = $('resourceCreateBookmarkTitle');
      var desc = $('resourceCreateBookmarkDesc');
      if (title && !title.value.trim() && data.title) title.value = data.title;
      if (desc && !desc.value.trim() && data.description) desc.value = data.description;
      state.bookmarkFavicon = data.favicon || '';
      if (status) status.textContent = tr('bookmark.meta.parse_success', '网页信息已填充');
    }).catch(function(error) {
      if (status) status.textContent = error.message || tr('bookmark.meta.parse_failed', '网页解析失败');
    });
  }

  function rememberBooks(books) {
    (books || []).forEach(function(book) {
      var id = Number(book.book_id || 0);
      if (!id) return;
      var index = state.books.findIndex(function(item) { return Number(item.book_id) === id; });
      if (index >= 0) state.books[index] = book;
      else state.books.push(book);
    });
  }

  function initDocumentPickers() {
    var bookHost = $('resourceCreateDocumentBookPicker');
    var folderHost = $('resourceCreateDocumentFolderPicker');
    if (!bookHost || !folderHost || !global.BookStarkSearchSelect || !global.BookStarkTreePicker) {
      setMessage(tr('topic.resource.create.document_picker_failed', '选择组件加载失败，请刷新后重试'), true);
      return;
    }

    state.folderPicker = global.BookStarkTreePicker.create(folderHost, {
      rootLabel: tr('topic.resource.create.document_root', '书籍根目录'),
      rootMeta: tr('topic.resource.create.document_root_hint', '直接存放在书籍下'),
      searchPlaceholder: tr('topic.resource.create.document_folder_search', '搜索目录...'),
      emptyText: tr('topic.resource.create.document_folder_empty', '没有匹配目录'),
      expandLabel: tr('common.expand', '展开'),
      collapseLabel: tr('common.collapse', '收起'),
      onChange: function(node, value) {
        $('resourceCreateDocumentFolder').value = value || '0';
      }
    });
    state.folderPicker.setDisabled(true);

    state.bookPicker = global.BookStarkSearchSelect.create(bookHost, {
      icon: 'fa-book',
      optionIcon: 'fa-book',
      placeholder: tr('topic.resource.create.document_book_placeholder', '选择书籍'),
      searchPlaceholder: tr('topic.resource.create.document_book_search', '搜索书籍名称或标签...'),
      loadingText: tr('topic.resource.create.document_book_loading', '正在加载书籍...'),
      emptyText: tr('topic.resource.create.document_no_books', '没有匹配书籍'),
      errorText: tr('topic.resource.create.document_book_failed', '书籍加载失败'),
      autoSelectSingle: true,
      load: function(query, signal) {
        return request('/api/books?page=1&page_size=30&keyword=' + encodeURIComponent(query || ''), { signal: signal }).then(function(result) {
          var books = Array.isArray(result.data) ? result.data : [];
          rememberBooks(books);
          return books;
        });
      },
      getValue: function(book) { return book.book_id; },
      getLabel: function(book) { return book.book_name || ''; },
      getMeta: function(book) {
        return tr('topic.resource.create.document_book_doc_count', '{count} 个文档').replace('{count}', Number(book.doc_count || 0));
      },
      onChange: function(book, value) {
        $('resourceCreateDocumentBook').value = value || '';
        $('resourceCreateDocumentFolder').value = '0';
        loadFolders(book);
      }
    });
  }

  function loadFolders(selectedBook) {
    var book = $('resourceCreateDocumentBook');
    if (!book || !state.folderPicker) return;
    var bookID = Number(book.value || 0);
    var seq = ++state.folderLoadSeq;
    if (state.folderAbortController) state.folderAbortController.abort();
    state.folderAbortController = typeof AbortController === 'function' ? new AbortController() : null;
    if (!bookID) {
      state.folderPicker.setTree([]);
      state.folderPicker.setValue('0', true);
      state.folderPicker.setDisabled(true);
      return;
    }
    if (selectedBook) rememberBooks([selectedBook]);
    state.folderPicker.setTree([]);
    state.folderPicker.setValue('0', true);
    state.folderPicker.setDisabled(true);
    setMessage(tr('topic.resource.create.document_folder_loading', '正在加载目录...'));
    request('/api/books/' + bookID + '/docs/tree', {
      signal: state.folderAbortController ? state.folderAbortController.signal : null
    }).then(function(result) {
      if (seq !== state.folderLoadSeq || Number(book.value || 0) !== bookID) return;
      state.folderPicker.setTree(Array.isArray(result.data) ? result.data : []);
      state.folderPicker.setDisabled(false);
      setMessage('');
    }).catch(function(error) {
      if (seq !== state.folderLoadSeq || error && error.name === 'AbortError') return;
      state.folderPicker.setTree([]);
      state.folderPicker.setDisabled(false);
      setMessage(error.message, true);
    });
  }

  function tags() {
    return state.tagInput && typeof state.tagInput.getTags === 'function' ? state.tagInput.getTags() : '';
  }

  async function createNote() {
    var content = String(state.composer ? state.composer.getValue() : '').trim();
    if (!content) focusInvalid('resourceCreateEditor', tr('topic.resource.create.note_required', '请输入笔记内容'));
    var title = snippet(content, 50) || ('note-' + Date.now());
    var result = await request('/api/blogs', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ blog_title: title, blog_type: 'note', editor_type: 'markdown', blog_content: content, visibility: Number($('resourceCreateVisibility').value || 0), labels: tags() })
    });
    return { type: 'note', id: result.data.blog_id, title: result.data.blog_title || title, desc: snippet(content, 120), identify: result.data.blog_identify || '' };
  }

  async function createArticle() {
    var title = $('resourceCreateArticleTitle').value.trim();
    if (!title) focusInvalid('resourceCreateArticleTitle', tr('topic.resource.create.article_title_required', '请输入文章标题'));
    var desc = $('resourceCreateArticleDesc').value.trim();
    var result = await request('/api/blogs', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ blog_title: title, blog_type: 'article', editor_type: state.editorType, blog_content: '', blog_desc: desc, visibility: 0, labels: tags() })
    });
    return { type: 'article', id: result.data.blog_id, title: result.data.blog_title || title, desc: desc, identify: result.data.blog_identify || '', editor_type: state.editorType };
  }

  async function createBookmark() {
    var url = $('resourceCreateBookmarkURL').value.trim();
    var title = $('resourceCreateBookmarkTitle').value.trim();
    if (!url) focusInvalid('resourceCreateBookmarkURL', tr('bookmark.dialog.url_required', '请输入网址'));
    if (!title) focusInvalid('resourceCreateBookmarkTitle', tr('bookmark.dialog.title_required', '请输入标题'));
    var desc = $('resourceCreateBookmarkDesc').value.trim();
    var result = await request('/api/bookmarks', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ title: title, url: url, description: desc, labels: tags(), is_public: !!$('resourceCreateBookmarkPublic').checked, favicon: state.bookmarkFavicon || '' })
    });
    if (!result.data || !result.data.bookmark_id) throw new Error(tr('topic.resource.create.bookmark_attach_failed', '书签已保存，但无法自动挂载'));
    return { type: 'bookmark', id: result.data.bookmark_id, title: result.data.title || title, desc: result.data.description || desc || url };
  }

  async function createDocument() {
    var bookID = Number($('resourceCreateDocumentBook').value || 0);
    var parentID = Number($('resourceCreateDocumentFolder').value || 0);
    var name = $('resourceCreateDocumentName').value.trim();
    if (!bookID) focusInvalid('resourceCreateDocumentBook', tr('topic.resource.create.document_book_required', '请选择书籍'));
    if (!name) focusInvalid('resourceCreateDocumentName', tr('topic.resource.create.document_name_required', '请输入文档名称'));
    var book = state.books.find(function(item) { return Number(item.book_id) === bookID; }) || {};
    var result = await request('/api/books/' + bookID + '/docs', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ document_name: name, parent_id: parentID, doc_type: state.editorType })
    });
    return { type: 'document', id: result.data.document_id, title: result.data.document_name || name, desc: book.book_name || '', book_identify: book.identify || '', identify: result.data.identify || '', editor_type: state.editorType };
  }

  async function submit(event) {
    event.preventDefault();
    if (state.busy) return;
    clearInvalid();
    state.busy = true;
    var button = $('resourceCreateSubmitBtn');
    var label = button.querySelector('span');
    button.disabled = true;
    label.textContent = tr('topic.resource.create.creating', '正在创建...');
    setMessage(tr('topic.resource.create.creating_hint', '正在创建资料...'));
    try {
      var row;
      if (state.type === 'note') row = await createNote();
      else if (state.type === 'article') row = await createArticle();
      else if (state.type === 'bookmark') row = await createBookmark();
      else row = await createDocument();
      if (!row || !row.id) throw new Error(tr('topic.resource.create.failed', '创建失败'));
      var callback = state.options && state.options.onCreated;
      if (callback) await callback(row);
      close('created', row);
    } catch (error) {
      setMessage(error.message || tr('topic.resource.create.failed', '创建失败'), true);
    } finally {
      state.busy = false;
      button.disabled = false;
      label.textContent = tr('topic.resource.create.submit', '创建');
    }
  }

  function open(type, options) {
    if (!TYPE_META[type]) type = 'note';
    state.type = type;
    state.options = options || {};
    state.previousFocus = document.activeElement;
    render();
    var modal = $('resourceCreateModal');
    if (modal.parentElement !== document.body) document.body.appendChild(modal);
    modal.classList.add('active');
    modal.setAttribute('aria-hidden', 'false');
    document.body.classList.add('resource-create-modal-open');
    if (global.BookStarkScrollLock) global.BookStarkScrollLock.lock('resource-create-modal');
  }

  function close(reason, row) {
    if (state.busy && reason !== 'created') return;
    var modal = $('resourceCreateModal');
    if (modal) {
      modal.classList.remove('active');
      modal.setAttribute('aria-hidden', 'true');
    }
    document.body.classList.remove('resource-create-modal-open');
    destroyFields();
    if (global.BookStarkScrollLock) global.BookStarkScrollLock.unlock('resource-create-modal');
    var options = state.options;
    state.options = null;
    if (reason !== 'created' && options && typeof options.onCancel === 'function') options.onCancel();
    if (reason === 'created' && options && typeof options.onClose === 'function') options.onClose(row);
    if (state.previousFocus && typeof state.previousFocus.focus === 'function') {
      try { state.previousFocus.focus(); } catch (ignore) {}
    }
    state.previousFocus = null;
  }

  function init() {
    var form = $('resourceCreateForm');
    if (!form || form.dataset.resourceCreateReady === '1') return;
    form.dataset.resourceCreateReady = '1';
    form.addEventListener('submit', submit);
    $('resourceCreateCloseBtn').addEventListener('click', function() { close('cancel'); });
    $('resourceCreateCancelBtn').addEventListener('click', function() { close('cancel'); });
    $('resourceCreateModal').addEventListener('click', function(event) {
      if (event.target === $('resourceCreateModal')) close('cancel');
    });
    document.addEventListener('keydown', function(event) {
      var modal = $('resourceCreateModal');
      if (!modal || !modal.classList.contains('active')) return;
      if (event.key === 'Escape') {
        event.preventDefault();
        close('cancel');
        return;
      }
      if (event.key === 'Tab') {
        var dialog = modal.querySelector('.asset-modal');
        if (!dialog) return;
        var focusable = Array.prototype.slice.call(dialog.querySelectorAll('button:not([disabled]), input:not([disabled]), textarea:not([disabled]), select:not([disabled]), [tabindex]:not([tabindex="-1"]), [contenteditable="true"]')).filter(function(el) {
          return !el.hidden && el.offsetParent !== null;
        });
        if (!focusable.length) return;
        var first = focusable[0];
        var last = focusable[focusable.length - 1];
        if (event.shiftKey && document.activeElement === first) {
          event.preventDefault();
          last.focus();
        } else if (!event.shiftKey && document.activeElement === last) {
          event.preventDefault();
          first.focus();
        }
      }
    });
  }

  global.BookStarkResourceCreate = {
    init: init,
    open: open,
    close: close
  };

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();
})(window);
