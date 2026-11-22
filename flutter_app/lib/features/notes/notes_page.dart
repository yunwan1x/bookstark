import '../../core/local_protected_article_repository.dart';
import '../complex_editors/open_local_protected_article.dart';
import '../../core/native_complex_source_io.dart';
import '../complex_editors/open_local_complex_note.dart';
import '../complex_editors/open_local_article_creation.dart';
import '../../core/complex_editor_document.dart';
import '../../core/html_creation_vault.dart';
import '../html/open_new_local_html_note.dart';
import '../html/open_new_remote_html_note.dart';
import '../../core/html_recovery_vault.dart';
import '../html/open_local_html_note.dart';
import '../html/open_html_note.dart';
import '../html/html_note_page.dart';
import '../html/html_code_source_surface.dart';

import 'dart:convert';
import 'dart:async';

import 'package:file_selector/file_selector.dart';

import '../../core/attachments.dart';
import '../../widgets/bookstark_markdown.dart';
import '../../core/note_list_query.dart';
import '../../core/note_list_source.dart';
import '../../core/note_pin_actions.dart';
import '../../core/note_list_selection_controller.dart';
import 'note_filter_sheet.dart';
import '../../core/draft_vault.dart';
import '../../core/markdown_editing.dart';
import 'note_unlock_dialog.dart';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../../core/notes_repository.dart';
import '../../core/note_list_entry.dart';
import '../../core/note_content_limits.dart';
import '../complex_editors/large_markdown_read_page.dart';
import '../complex_editors/source_chunks.dart';

typedef OpenOwnedComplexNote =
    Future<bool> Function(
      BuildContext context, {
      required int id,
      required NoteCollection collection,
      required ComplexEditorKind kind,
      required bool Function() isCurrentScope,
    });

/// Shared native note/article opening path, including explicit protected-note
/// unlock. Source links and normal lists use the same editor and privacy rules.
Future<bool> openNativeNoteEditor(
  BuildContext context, {
  required NotesRepository repository,
  int? id,
  Note? initial,
  NoteCollection collection = NoteCollection.note,
  DraftVault? drafts,
  HtmlRecoveryVault? htmlRecoveryVault,
  HtmlSourceSurfaceBuilder htmlSourceSurfaceBuilder = defaultHtmlSourceSurface,
  HtmlCodeSourceSurfaceBuilder? htmlReadOnlySourceSurfaceBuilder,
  AttachmentRepository? attachments,
  bool english = false,
  OpenOwnedComplexNote? onOpenOwnedComplex,
  bool forceLegacyArticleDraftReview = false,
  ComplexSourceIoScope? sourceIoScope,
  bool Function()? isCurrentScope,
}) async {
  bool current() {
    if (!context.mounted) return false;
    try {
      return isCurrentScope?.call() ?? true;
    } catch (_) {
      return false;
    }
  }

  if (!context.mounted || !current()) return false;
  if (repository is LocalNotesRepository &&
      repository.collection == NoteCollection.article) {
    if (id == null) {
      return openLocalArticleCreation(
        context,
        store: repository.store,
        legacyDrafts: drafts,
        english: english,
        forceLegacyReview: forceLegacyArticleDraftReview,
        isCurrentScope: current,
        sourceIoScope: sourceIoScope,
      );
    }
    late String type;
    late bool protected;
    try {
      type = await repository.editorTypeOf(id);
      if (!context.mounted || !current()) return false;
      protected = await LocalProtectedArticleRepository.isProtected(
        repository.store,
        id,
      );
    } catch (_) {
      if (!context.mounted || !current()) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            english
                ? 'Unable to read this article. Original content retained.'
                : '无法读取文章，原始内容已保留。',
          ),
        ),
      );
      return false;
    }
    if (!context.mounted || !current()) return false;
    if (protected) {
      if (!context.mounted || !current() || sourceIoScope == null) return false;
      return openLocalProtectedArticle(
        context,
        store: repository.store,
        id: id,
        sourceIoScope: sourceIoScope,
        isCurrentScope: current,
        english: english,
      );
    }
    if (type == 'markdown') {
      return openLocalComplexNote(
        context,
        store: repository.store,
        id: id,
        collection: 'article',
        kind: ComplexEditorKind.markdown,
        english: english,
        legacyMarkdownDrafts: drafts,
        forceLegacyReview: forceLegacyArticleDraftReview,
        isCurrentScope: current,
        sourceIoScope: sourceIoScope,
      );
    }
  }
  Note? content;
  try {
    content = id == null
        ? initial ?? const Note(title: '', content: '')
        : await repository.read(id);
  } on DedicatedEditorRequired catch (requiredEditor) {
    if (!context.mounted || !current()) return false;
    if ({
          'spreadsheet',
          'drawing',
          'mindmap',
          'richdoc',
          'presentation',
        }.contains(requiredEditor.editorType) &&
        repository is LocalNotesRepository) {
      return openLocalComplexNote(
        context,
        kind: ComplexEditorKind.parse(requiredEditor.editorType),
        store: repository.store,
        id: requiredEditor.id,
        collection: repository.collection.name,
        english: english,
        isCurrentScope: current,
        sourceIoScope: sourceIoScope,
      );
    }
    if (repository is RemoteNotesRepository &&
        repository.collection == NoteCollection.note &&
        collection == NoteCollection.note &&
        {
          'spreadsheet',
          'drawing',
          'mindmap',
          'richdoc',
          'presentation',
        }.contains(requiredEditor.editorType)) {
      if (id == null ||
          id <= 0 ||
          requiredEditor.id != id ||
          onOpenOwnedComplex == null ||
          !current()) {
        rethrow;
      }
      return onOpenOwnedComplex(
        context,
        id: requiredEditor.id,
        collection: repository.collection,
        kind: ComplexEditorKind.parse(requiredEditor.editorType),
        isCurrentScope: current,
      );
    }
    if (requiredEditor.editorType != 'html') rethrow;
    if (repository is LocalNotesRepository) {
      return openLocalHtmlNote(
        context,
        store: repository.store,
        id: requiredEditor.id,
        collection: repository.collection.name,
        english: english,
        isCurrentScope: current,
        sourceIoScope: sourceIoScope,
        recoveryVault: htmlRecoveryVault,
        sourceSurfaceBuilder: htmlSourceSurfaceBuilder,
        readOnlySourceSurfaceBuilder: htmlReadOnlySourceSurfaceBuilder,
      );
    }
    if (repository is! RemoteNotesRepository) rethrow;
    return openHtmlNote(
      context,
      client: repository.client,
      isCurrentScope: current,
      id: requiredEditor.id,
      collection: repository.collection.name,
      english: english,
      recoveryVault: htmlRecoveryVault,
      sourceSurfaceBuilder: htmlSourceSurfaceBuilder,
      readOnlySourceSurfaceBuilder: htmlReadOnlySourceSurfaceBuilder,
    );
  } on NoteLocked catch (locked) {
    if (!context.mounted || !current()) return false;
    if (repository is! ProtectedNotesRepository) rethrow;
    content = await showDialog<Note>(
      context: context,
      barrierDismissible: false,
      builder: (_) => NoteUnlockDialog(
        onUnlock: (password) => (repository as ProtectedNotesRepository).unlock(
          locked.id,
          password,
        ),
        english: english,
      ),
    );
  }
  if (!context.mounted || !current() || content == null) return false;
  final opened = content;
  if (id != null &&
      SourceChunks.utf8ByteLength(opened.content) >
          noteEditorMaxContentUtf8Bytes) {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => LargeMarkdownReadPage(
          title: opened.title,
          labels: opened.labels,
          source: opened.content,
          english: english,
        ),
      ),
    );
    return true;
  }
  await Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => NoteEditorPage(
        repository: repository,
        collection: collection,
        note: opened,
        english: english,
        drafts: opened.isProtected ? null : drafts,
        attachments: attachments,
      ),
    ),
  );
  return true;
}

class NotesPage extends StatefulWidget {
  const NotesPage({
    super.key,
    required this.repository,
    this.english = false,
    this.collection = NoteCollection.note,
    this.drafts,
    this.attachments,
    this.onShareSettings,
    this.listSource,
    this.pinActions,
    this.onOpenExisting,
    this.onOpenOwnedComplex,
    this.onCreateMarkdown,
    this.onCreateArticleMarkdown,
    this.sourceIoScope,
    this.htmlCreationVault,
    this.isCurrentScope,
    this.htmlRecoveryVault,
    this.htmlSourceSurfaceBuilder = defaultHtmlSourceSurface,
    this.htmlReadOnlySourceSurfaceBuilder,
  });
  final ComplexSourceIoScope? sourceIoScope;
  final NotesRepository repository;
  final NoteListSource? listSource;
  final NotePinActions? pinActions;
  final Future<void> Function(int id)? onOpenExisting;
  final OpenOwnedComplexNote? onOpenOwnedComplex;
  final Future<void> Function(BuildContext context)? onCreateMarkdown;
  final Future<void> Function(BuildContext context)? onCreateArticleMarkdown;
  final bool Function()? isCurrentScope;
  final HtmlCreationVault? htmlCreationVault;
  final HtmlRecoveryVault? htmlRecoveryVault;
  final HtmlSourceSurfaceBuilder htmlSourceSurfaceBuilder;
  final HtmlCodeSourceSurfaceBuilder? htmlReadOnlySourceSurfaceBuilder;
  final Future<void> Function(NoteListEntry)? onShareSettings;
  final DraftVault? drafts;
  final AttachmentRepository? attachments;
  final bool english;
  final NoteCollection collection;
  @override
  State<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends State<NotesPage> {
  final _search = TextEditingController();
  List<NoteListEntry> _notes = [];
  String? _error;
  int _page = 1, _generation = 0;
  bool _busy = false,
      _more = true,
      _opening = false,
      _selecting = false,
      _deleting = false;
  String _label = '', _pinned = '';
  final Set<int> _selected = {};
  String t(String zh, String en) => widget.english ? en : zh;

  late NoteListQuery _query;
  NoteListSelectionController? _selection;
  final Map<int, NoteListEntry> _chosen = {};
  bool _queryChanging = false;
  bool get _typed => widget.listSource != null;
  bool _current() {
    if (!mounted) return false;
    try {
      return widget.isCurrentScope?.call() ?? true;
    } catch (_) {
      return false;
    }
  }

  String _safeFailure() => t(
    '操作未完成，请核对连接和权限后重试。',
    'The operation did not complete. Check connection and permission.',
  );
  void _setupTyped() {
    _query = NoteListQuery(collection: widget.collection.name);
    _selection = _typed
        ? NoteListSelectionController(
            scope:
                widget.pinActions?.scope ??
                'local-list-${identityHashCode(widget.listSource)}',
            isCurrent: _current,
          )
        : null;
  }

  void _syncSelection() {
    final selection = _selection;
    if (selection != null) {
      _selected
        ..clear()
        ..addAll(selection.selectedIds);
      _chosen.removeWhere((id, _) => !_selected.contains(id));
    }
  }

  void _setSelected(int id, bool selected) {
    if (!_current() || _deleting) return;
    _selection?.setSelected(id, selected);
    if (selected) {
      _selected.add(id);
      for (final note in _notes) {
        if (note.id == id) _chosen[id] = note;
      }
    } else {
      _selected.remove(id);
      _chosen.remove(id);
    }
  }

  void _toggleSelected(NoteListEntry note) =>
      _setSelected(note.id, !_selected.contains(note.id));
  void _clearSelection() {
    _selection?.clearForQueryChange(confirmed: true);
    _selected.clear();
    _chosen.clear();
  }

  void _selectLoaded() {
    for (final note in _notes) {
      _setSelected(note.id, true);
    }
  }

  Future<void> _applyQuery(NoteListQuery next) async {
    if (!_current() || _deleting || _queryChanging || next == _query) return;
    final source = widget.listSource, old = _query;
    _queryChanging = true;
    try {
      if (_selected.isNotEmpty) {
        final yes = await showDialog<bool>(
          context: context,
          builder: (dialog) => AlertDialog(
            scrollable: true,
            title: Text(t('更改筛选并清除选择？', 'Change filters and clear selection?')),
            content: Text(
              t(
                '只清除已选记录的选择状态，不修改或删除资料。',
                'Only the selected IDs are cleared. Resources are not changed or deleted.',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog, false),
                child: Text(t('返回并保留', 'Keep selection')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialog, true),
                child: Text(t('应用并清除选择', 'Apply and clear selection')),
              ),
            ],
          ),
        );
        if (!_current() ||
            !identical(widget.listSource, source) ||
            old != _query) {
          return;
        }
        if (yes != true) {
          _search.text = _query.keyword;
          return;
        }
      }
      if (!_current() || !identical(widget.listSource, source)) return;
      next.requireSupported(source!.capabilities);
      setState(() {
        _clearSelection();
        _selecting = false;
        _query = next;
        _search.text = next.keyword;
        _label = next.label;
        _pinned = next.pin == NotePinFilter.all
            ? ''
            : next.pin == NotePinFilter.pinned
            ? '1'
            : '0';
      });
      await _load();
    } catch (_) {
      if (_current()) setState(() => _error = _safeFailure());
    } finally {
      if (mounted) setState(() => _queryChanging = false);
    }
  }

  Future<void> _submitSearch() async {
    if (_typed) {
      await _applyQuery(_query.copyWith(keyword: _search.text));
    } else {
      setState(_clearSelection);
      await _load();
    }
  }

  Future<void> _filterTyped() async {
    if (!_current() || _busy || _deleting || _queryChanging) return;
    final source = widget.listSource;
    final next = await showNoteFilterSheet(
      context,
      initial: _query,
      capabilities: source!.capabilities,
      english: widget.english,
    );
    if (_current() && identical(source, widget.listSource) && next != null) {
      await _applyQuery(next);
    }
  }

  Widget _typedFilters() => Padding(
    padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ActionChip(
              label: Text(
                t(
                  '筛选 · ${_query.filterCount}',
                  'Filters · ${_query.filterCount}',
                ),
              ),
              avatar: const Icon(Icons.filter_alt_outlined),
              onPressed: _busy || _deleting || _queryChanging
                  ? null
                  : _filterTyped,
            ),
            if (_query.label.isNotEmpty)
              InputChip(
                label: Text(_query.label),
                onDeleted: _deleting
                    ? null
                    : () => _applyQuery(_query.copyWith(label: '')),
              ),
            if (_query.createdDate.isNotEmpty)
              InputChip(
                label: Text(_query.createdDate),
                onDeleted: _deleting
                    ? null
                    : () => _applyQuery(_query.copyWith(createdDate: '')),
              ),
            if (_query.pin != NotePinFilter.all)
              InputChip(
                label: Text(
                  _query.pin == NotePinFilter.pinned
                      ? t('已置顶', 'Pinned')
                      : t('未置顶', 'Not pinned'),
                ),
                onDeleted: _deleting
                    ? null
                    : () =>
                          _applyQuery(_query.copyWith(pin: NotePinFilter.all)),
              ),
            if (_query.visibility != NoteVisibilityFilter.all)
              InputChip(
                label: Text(
                  _query.visibility == NoteVisibilityFilter.public
                      ? t('公开', 'Public')
                      : t('私有', 'Private'),
                ),
                onDeleted: _deleting
                    ? null
                    : () => _applyQuery(
                        _query.copyWith(visibility: NoteVisibilityFilter.all),
                      ),
              ),
            if (_query.hasCode)
              InputChip(
                label: Text(t('含代码', 'Code')),
                onDeleted: _deleting
                    ? null
                    : () => _applyQuery(_query.copyWith(hasCode: false)),
              ),
            if (_query.filterCount > 0)
              TextButton(
                onPressed: _deleting
                    ? null
                    : () => _applyQuery(
                        NoteListQuery(
                          collection: _query.collection,
                          keyword: _query.keyword,
                        ),
                      ),
                child: Text(t('清除', 'Clear')),
              ),
            TextButton(
              onPressed: _deleting
                  ? null
                  : () => setState(() {
                      _selecting = !_selecting;
                      _clearSelection();
                    }),
              child: Text(
                _selecting ? t('取消选择', 'Cancel selection') : t('选择', 'Select'),
              ),
            ),
          ],
        ),
        if (_selecting) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                t('已选 ${_selected.length} 项', '${_selected.length} selected'),
              ),
              if ((_selection?.offscreenCount(_notes.map((n) => n.id)) ?? 0) >
                  0)
                Text(
                  t(
                    '含其他页 ${_selection!.offscreenCount(_notes.map((n) => n.id))} 项',
                    '${_selection!.offscreenCount(_notes.map((n) => n.id))} on other pages',
                  ),
                ),
              TextButton(
                onPressed: _deleting ? null : () => setState(_selectLoaded),
                child: Text(t('全选已加载', 'Select loaded')),
              ),
              if (widget.pinActions != null &&
                  !_article &&
                  widget.listSource?.capabilities.pinned == true)
                FilledButton(
                  onPressed: _deleting || _selected.isEmpty
                      ? null
                      : _pinSelected,
                  child: Text(t('置顶所选', 'Pin selected')),
                ),
              OutlinedButton(
                onPressed: _deleting || _selected.isEmpty
                    ? null
                    : _removeSelected,
                child: Text(t('移到回收站', 'Move to trash')),
              ),
            ],
          ),
        ],
      ],
    ),
  );
  Future<void> _pinSelected() async {
    final actions = widget.pinActions, selection = _selection;
    if (actions == null ||
        widget.listSource?.capabilities.pinned != true ||
        selection == null ||
        !_current() ||
        _deleting ||
        _selected.isEmpty) {
      return;
    }
    final source = widget.listSource, repository = widget.repository;
    bool owned() =>
        _current() &&
        identical(source, widget.listSource) &&
        identical(repository, widget.repository) &&
        identical(actions, widget.pinActions) &&
        identical(selection, _selection);
    final snapshot = selection.capture();
    if (snapshot.ids.length > actions.maxBatchIds) {
      setState(
        () => _error = t(
          '所选记录超过本次操作上限，请减少选择。',
          'Too many selected records. Reduce the selection.',
        ),
      );
      return;
    }
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        scrollable: true,
        title: Text(t('置顶所选记录？', 'Pin selected records?')),
        content: Text(
          t(
            '仅置顶已选中的 ${snapshot.ids.length} 项，包含其他页的选择。',
            'Pin only the ${snapshot.ids.length} explicitly selected IDs, including other pages.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: Text(t('返回', 'Back')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(t('置顶所选', 'Pin selected')),
          ),
        ],
      ),
    );
    if (yes != true ||
        !owned() ||
        !identical(actions, widget.pinActions) ||
        !identical(selection, _selection) ||
        _deleting) {
      return;
    }
    setState(() {
      _deleting = true;
      _error = null;
    });
    var remaining = snapshot.ids.length;
    try {
      final result = await actions.pinSelected(snapshot.ids);
      if (!owned() ||
          !identical(actions, widget.pinActions) ||
          !identical(selection, _selection)) {
        return;
      }
      if (result.scope != snapshot.scope ||
          !setEquals(result.requestedIds, snapshot.ids)) {
        throw StateError('Note action scope changed');
      }
      selection.reconcile(snapshot, verifiedIds: result.verifiedIds);
      _syncSelection();
      remaining = _selected.length;
    } catch (_) {
      if (!mounted || !owned()) return;
    } finally {
      if (owned()) setState(() => _deleting = false);
    }
    if (!mounted || !owned()) return;
    await _load();
    if (mounted && owned()) {
      setState(() {
        _selecting = _selected.isNotEmpty;
        if (remaining > 0) {
          _error = t(
            '部分结果尚未确认，已保留失败和其他页的选择。',
            'Some results remain unconfirmed. Their selected IDs are retained across pages.',
          );
        }
      });
    }
  }

  Future<void> _changeFlag(NoteListEntry note, String action) async {
    final actions = widget.pinActions;
    if (actions == null ||
        !_current() ||
        _deleting ||
        _article ||
        widget.listSource?.capabilities.pinned != true) {
      return;
    }
    final source = widget.listSource, repository = widget.repository;
    bool owned() =>
        _current() &&
        identical(source, widget.listSource) &&
        identical(repository, widget.repository) &&
        identical(actions, widget.pinActions);
    if (action.startsWith('public-')) {
      final yes = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          scrollable: true,
          title: Text(t('更改可见性？', 'Change visibility?')),
          content: Text(
            t(
              '公开可能创建分享；设为私有会清除已有分享。',
              'Public visibility may create a share. Making it private removes existing shares.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: Text(t('返回', 'Back')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: Text(t('继续', 'Continue')),
            ),
          ],
        ),
      );
      if (yes != true || !owned() || !identical(actions, widget.pinActions)) {
        return;
      }
    }
    setState(() {
      _deleting = true;
      _error = null;
    });
    var confirmed = false;
    NoteActionState? observed;
    try {
      if (action == 'review-flags') {
        observed = await actions.readState(note.id);
        confirmed = true;
      } else {
        final result = action.startsWith('pin-')
            ? await actions.setPinned(note.id, action == 'pin-on')
            : await actions.setPublic(note.id, action == 'public-on');
        confirmed = result.confirmed;
      }
    } catch (_) {
      /* A fresh user action is required; never retry toggle here. */
    } finally {
      if (owned()) setState(() => _deleting = false);
    }
    if (!owned() || !identical(actions, widget.pinActions)) return;
    await _load();
    if (owned() && observed != null) {
      setState(() {
        final actual = observed!;
        _notes = [
          for (final item in _notes)
            if (item.id != actual.id)
              item
            else
              FilteredNoteListEntry(
                id: item.id,
                title: item.title,
                contentPreview: item.contentPreview,
                labels: item.labels,
                updatedAt: item.updatedAt,
                isProtected: item.isProtected,
                pinned: actual.pinned,
                visibility: actual.isPublic
                    ? NoteVisibilityFilter.public
                    : NoteVisibilityFilter.private,
                editorType: actual.editorType,
              ),
        ];
      });
    }
    if (owned() && !confirmed) {
      setState(
        () => _error = t(
          '结果尚未确认，请核对状态后重新操作。',
          'The result is unconfirmed. Review the state before a new action.',
        ),
      );
    }
  }

  Widget _recordMenu(NoteListEntry note) {
    final flags = note is FilteredNoteListEntry ? note : null;
    final canPin =
        widget.pinActions != null &&
        !_article &&
        widget.listSource?.capabilities.pinned == true;
    return PopupMenuButton<String>(
      enabled: !_deleting,
      tooltip: _article
          ? t('文章操作', 'Article actions')
          : t('笔记操作', 'Note actions'),
      onSelected: (action) {
        if (action == 'edit') {
          _edit(note);
        } else if (action == 'sharing') {
          _sharing(note);
        } else if (action == 'trash') {
          _remove(note);
        } else {
          _changeFlag(note, action);
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(value: 'edit', child: Text(t('编辑', 'Edit'))),
        if (canPin && flags?.pinned != null)
          PopupMenuItem(
            value: flags!.pinned! ? 'pin-off' : 'pin-on',
            child: Text(flags.pinned! ? t('取消置顶', 'Unpin') : t('置顶', 'Pin')),
          ),
        if (canPin && flags?.visibility != null)
          PopupMenuItem(
            value: flags!.visibility == NoteVisibilityFilter.public
                ? 'public-off'
                : 'public-on',
            child: Text(
              flags.visibility == NoteVisibilityFilter.public
                  ? t('设为私有', 'Make private')
                  : t('设为公开', 'Make public'),
            ),
          ),
        if (canPin && (flags?.pinned == null || flags?.visibility == null))
          PopupMenuItem(
            value: 'review-flags',
            child: Text(t('核对当前状态', 'Review current state')),
          ),
        if (widget.onShareSettings != null)
          PopupMenuItem(
            value: 'sharing',
            child: Text(t('分享设置', 'Sharing settings')),
          ),
        PopupMenuItem(value: 'trash', child: Text(t('移到回收站', 'Move to trash'))),
      ],
    );
  }

  Widget _flags(NoteListEntry note) {
    final flags = note is FilteredNoteListEntry ? note : null;
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        if (flags?.pinned == true) Text(t('已置顶', 'Pinned')),
        if (flags?.visibility != null)
          Text(
            flags!.visibility == NoteVisibilityFilter.public
                ? t('公开', 'Public')
                : t('私有', 'Private'),
          ),
        if (note.isProtected) Text(t('受保护', 'Protected')),
      ],
    );
  }

  @override
  void didUpdateWidget(covariant NotesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.repository, widget.repository) ||
        !identical(oldWidget.listSource, widget.listSource) ||
        oldWidget.collection != widget.collection ||
        !identical(oldWidget.pinActions, widget.pinActions)) {
      _generation++;
      _selection?.retire();
      if (!identical(oldWidget.pinActions, widget.pinActions)) {
        oldWidget.pinActions?.retire();
      }
      _selected.clear();
      _chosen.clear();
      _search.clear();
      _label = '';
      _pinned = '';
      _notes = [];
      _page = 1;
      _more = true;
      _busy = false;
      _opening = false;
      _deleting = false;
      _selecting = false;
      _setupTyped();
      _load();
    }
  }

  Future<void> _sharing(NoteListEntry note) async {
    final callback = widget.onShareSettings;
    final repository = widget.repository, source = widget.listSource;
    bool owned() =>
        _current() &&
        identical(repository, widget.repository) &&
        identical(source, widget.listSource) &&
        identical(callback, widget.onShareSettings);
    if (!owned() || _opening || _deleting || callback == null) {
      return;
    }
    setState(() => _opening = true);
    try {
      await callback(note);
      if (mounted && owned()) {
        await _load();
      }
    } catch (_) {
      if (mounted && owned()) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              t(
                '无法打开分享设置，请核对权限和连接。',
                'Sharing settings could not open. Check permission and connection.',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted && owned()) {
        setState(() => _opening = false);
      }
    }
  }

  bool get _article => widget.collection == NoteCollection.article;
  @override
  void initState() {
    super.initState();
    _setupTyped();
    _load();
  }

  Future<void> _load({bool next = false}) async {
    if (!_current() || _deleting || (next && (_busy || !_more))) return;
    final generation = ++_generation, page = next ? _page + 1 : 1;
    final repository = widget.repository,
        source = widget.listSource,
        query = _query;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final List<NoteListEntry> items;
      bool more;
      if (source != null) {
        final result = await source.list(query, page: page);
        items = result.items;
        more = result.hasMore;
      } else if (repository is NoteListRepository) {
        items = await (repository as NoteListRepository).listEntries(
          keyword: _search.text,
          page: page,
          label: _label,
          pinned: _pinned,
        );
        more = items.isNotEmpty;
      } else {
        final notes = repository is FilteredNotesRepository
            ? await (repository as FilteredNotesRepository).listFiltered(
                keyword: _search.text,
                page: page,
                label: _label,
                pinned: _pinned,
              )
            : await repository.list(keyword: _search.text, page: page);
        items = notes
            .map(
              (note) => NoteListEntry(
                id:
                    note.id ??
                    (throw const FormatException('List item has no ID')),
                title: note.title,
                contentPreview: String.fromCharCodes(
                  note.content.runes.take(512),
                ),
                labels: note.labels,
                updatedAt: note.updatedAt,
                isProtected: note.isProtected,
              ),
            )
            .toList();
        more = items.isNotEmpty;
      }
      if (!_current() ||
          generation != _generation ||
          !identical(repository, widget.repository) ||
          !identical(source, widget.listSource)) {
        return;
      }
      setState(() {
        final unique = <int, NoteListEntry>{
          for (final note in items) note.id: note,
        };
        _notes = next
            ? [
                ..._notes,
                ...unique.values.where(
                  (note) => !_notes.any((old) => old.id == note.id),
                ),
              ]
            : unique.values.toList();
        if (source == null && !next) {
          _selected.retainAll(_notes.map((note) => note.id));
        }
        _page = page;
        _more = more;
      });
    } catch (error) {
      if (_current() && generation == _generation) {
        setState(
          () => _error = source == null ? error.toString() : _safeFailure(),
        );
      }
    } finally {
      if (_current() && generation == _generation) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _edit([NoteListEntry? note]) async {
    if (!_current() || _opening || _deleting) return;
    final repository = widget.repository,
        collection = widget.collection,
        source = widget.listSource;
    final onArticleCreate = widget.onCreateArticleMarkdown;
    final onCreate = widget.onCreateMarkdown,
        onOwned = widget.onOpenOwnedComplex;
    final io = widget.sourceIoScope;
    bool owned() =>
        _current() &&
        identical(widget.repository, repository) &&
        widget.collection == collection &&
        identical(widget.listSource, source);
    _opening = true;
    try {
      final opener = widget.onOpenExisting;
      if (note != null && opener != null) {
        if (!_current()) return;
        await opener(note.id);
        if (_current()) await _load();
        return;
      }
      final local = repository;
      if (note == null &&
          (local is LocalNotesRepository || local is RemoteNotesRepository)) {
        final format = await showModalBottomSheet<String>(
          context: context,
          useSafeArea: true,
          showDragHandle: true,
          builder: (context) => Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  t(
                    _article ? '新建文章' : '新建笔记',
                    _article ? 'New article' : 'New note',
                  ),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.description_outlined),
                    title: Text(
                      t(
                        _article ? 'Markdown 文章' : 'Markdown 笔记',
                        _article ? 'Markdown article' : 'Markdown note',
                      ),
                    ),
                    subtitle: Text(t('写作与阅读', 'Writing and reading')),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.pop(context, 'markdown'),
                  ),
                ),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.code),
                    title: Text(
                      t(
                        _article ? 'HTML 文章' : 'HTML 笔记',
                        _article ? 'HTML article' : 'HTML note',
                      ),
                    ),
                    subtitle: Text(t('代码与交互页面', 'Code and interactive pages')),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.pop(context, 'html'),
                  ),
                ),
              ],
            ),
          ),
        );
        if (format == null || !mounted || !owned()) return;
        if (format == 'markdown' &&
            _article &&
            local is RemoteNotesRepository) {
          final createArticle = onArticleCreate;
          if (createArticle == null) {
            throw StateError('Article WebView creation entry required');
          }
          await createArticle(context);
          if (owned()) await _load();
          return; // Unknown/cancel/error never falls through to null-ID POST.
        }
        if (format == 'markdown' &&
            !_article &&
            local is RemoteNotesRepository &&
            onCreate != null) {
          await onCreate(context);
          if (_current()) await _load();
          return; // callback failure/unknown never falls back to legacy POST
        }
        if (format == 'html') {
          if (local is LocalNotesRepository) {
            await openNewLocalHtmlNote(
              context,
              store: local.store,
              collection: local.collection.name,
              english: widget.english,
              isCurrentScope: owned,
              creationVault: widget.htmlCreationVault,
              noteRecoveryVault: widget.htmlRecoveryVault,
              sourceSurfaceBuilder: widget.htmlSourceSurfaceBuilder,
              readOnlySourceSurfaceBuilder:
                  widget.htmlReadOnlySourceSurfaceBuilder,
            );
          } else if (local is RemoteNotesRepository) {
            await openNewRemoteHtmlNote(
              context,
              client: local.client,
              isCurrentScope: owned,
              collection: local.collection.name,
              english: widget.english,
              creationVault: widget.htmlCreationVault,
              noteRecoveryVault: widget.htmlRecoveryVault,
              sourceSurfaceBuilder: widget.htmlSourceSurfaceBuilder,
              readOnlySourceSurfaceBuilder:
                  widget.htmlReadOnlySourceSurfaceBuilder,
            );
          }
          if (owned()) await _load();
          return;
        }
      }
      if (!mounted || !owned()) return;
      await openNativeNoteEditor(
        context,
        repository: repository,
        onOpenOwnedComplex: onOwned,
        isCurrentScope: owned,
        sourceIoScope: io,
        id: note?.id,
        collection: collection,
        drafts: widget.drafts,
        htmlRecoveryVault: widget.htmlRecoveryVault,
        htmlSourceSurfaceBuilder: widget.htmlSourceSurfaceBuilder,
        htmlReadOnlySourceSurfaceBuilder:
            widget.htmlReadOnlySourceSurfaceBuilder,
        attachments: widget.attachments,
        english: widget.english,
      );
      if (owned()) await _load();
    } catch (error) {
      if (mounted && owned()) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (owned()) _opening = false;
    }
  }

  Future<void> _remove(NoteListEntry note) async {
    if (!_current() || _deleting) return;
    final repository = widget.repository, source = widget.listSource;
    bool owned() =>
        _current() &&
        identical(repository, widget.repository) &&
        identical(source, widget.listSource);
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('移到回收站？', 'Move to trash?')),
        content: Text(note.title),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t('取消', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t('移到回收站', 'Move to trash')),
          ),
        ],
      ),
    );
    if (!owned() || yes != true || _deleting) return;
    setState(() => _deleting = true);
    try {
      await repository.remove(note.id);
      if (!mounted || !owned()) return;
      setState(() => _deleting = false);
      await _load();
    } catch (e) {
      if (mounted && owned()) {
        setState(() => _deleting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_typed ? _safeFailure() : e.toString())),
        );
      }
    }
  }

  Future<void> _filterLabel() async {
    if (_typed) {
      await _filterTyped();
      return;
    }
    final input = TextEditingController(text: _label);
    final value = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        scrollable: true,
        title: Text(t('按标签筛选', 'Filter by label')),
        content: TextField(
          controller: input,
          autofocus: true,
          decoration: InputDecoration(
            labelText: t('准确标签名', 'Exact label name'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: Text(t('取消', 'Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialog, ''),
            child: Text(t('全部标签', 'All labels')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, input.text.trim()),
            child: Text(t('应用', 'Apply')),
          ),
        ],
      ),
    );
    // Dialog route may retain the TextField during its closing animation.
    Future<void>.delayed(const Duration(milliseconds: 300), input.dispose);
    if (!mounted || value == null) return;
    setState(() {
      _label = value;
      _clearSelection();
    });
    await _load();
  }

  Future<void> _removeSelected() async {
    if (!_current() || _deleting || _selected.isEmpty) return;
    final repository = widget.repository, source = widget.listSource;
    final selection = _selection, snapshot = selection?.capture();
    final ids = Set<int>.from(snapshot?.ids ?? _selected);
    final selectedNotes = {
      ..._chosen,
      for (final note in _notes) note.id: note,
    };
    bool owned() =>
        _current() &&
        identical(repository, widget.repository) &&
        identical(source, widget.listSource) &&
        identical(selection, _selection);
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        scrollable: true,
        title: Text(t('移到回收站？', 'Move to trash?')),
        content: Text(
          t(
            '将选中的${ids.length}条记录移到回收站。',
            'Move ${ids.length} explicitly selected records to trash.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: Text(t('取消', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(t('移到回收站', 'Move to trash')),
          ),
        ],
      ),
    );
    if (!owned() || yes != true || _deleting) return;
    setState(() {
      _deleting = true;
      _error = null;
    });
    final failed = <int, String>{}, verified = <int>{};
    try {
      for (final id in ids) {
        if (!mounted || !owned()) return;
        try {
          await repository.remove(id);
          if (!mounted || !owned()) return;
          verified.add(id);
        } catch (error) {
          if (!mounted || !owned()) return;
          failed[id] = source == null ? error.toString() : _safeFailure();
        }
      }
      if (!mounted || !owned()) return;
      setState(() {
        if (selection != null && snapshot != null) {
          selection.reconcile(snapshot, verifiedIds: verified);
          _syncSelection();
        } else {
          _selected
            ..clear()
            ..addAll(failed.keys);
        }
        _selecting = _selected.isNotEmpty;
      });
    } finally {
      if (owned()) setState(() => _deleting = false);
    }
    if (!mounted || !owned()) return;
    await _load();
    if (!owned() || failed.isEmpty) return;
    setState(() {
      if (source == null) {
        for (final id in failed.keys) {
          if (!_notes.any((note) => note.id == id) &&
              selectedNotes[id] != null) {
            _notes.add(selectedNotes[id]!);
          }
        }
        _selected
          ..clear()
          ..addAll(failed.keys);
      }
      _error = source == null
          ? t('部分记录未移入回收站：', 'Some records could not be moved: ') +
                failed.entries
                    .map((entry) => '#${entry.key}: ${entry.value}')
                    .join('\n')
          : t(
              '部分结果尚未确认，已保留失败和其他页的选择。',
              'Some results remain unconfirmed. Their selected IDs are retained across pages.',
            );
    });
  }

  Widget _filters() => _typed
      ? _typedFilters()
      : Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (widget.repository is FilteredNotesRepository)
                    ActionChip(
                      label: Text(
                        _label.isEmpty ? t('全部标签', 'All labels') : _label,
                      ),
                      avatar: const Icon(Icons.label_outline, size: 18),
                      onPressed: _busy || _deleting ? null : _filterLabel,
                    ),
                  if (widget.repository is RemoteNotesRepository)
                    PopupMenuButton<String>(
                      enabled: !_busy && !_deleting,
                      onSelected: (value) {
                        setState(() {
                          _pinned = value;
                          _clearSelection();
                        });
                        _load();
                      },
                      itemBuilder: (_) => [
                        for (final entry in {
                          '': t('最近更新', 'Recently updated'),
                          '1': t('仅置顶', 'Pinned only'),
                          '0': t('排除置顶', 'Unpinned only'),
                        }.entries)
                          PopupMenuItem(
                            value: entry.key,
                            child: Text(entry.value),
                          ),
                      ],
                      child: Chip(
                        label: Text(
                          _pinned == '1'
                              ? t('仅置顶', 'Pinned only')
                              : _pinned == '0'
                              ? t('排除置顶', 'Unpinned only')
                              : t('最近更新', 'Recently updated'),
                        ),
                        avatar: const Icon(Icons.expand_more, size: 18),
                      ),
                    ),
                  TextButton(
                    onPressed: _deleting
                        ? null
                        : () => setState(() {
                            _selecting = !_selecting;
                            _clearSelection();
                          }),
                    child: Text(
                      _selecting
                          ? t('取消选择', 'Cancel selection')
                          : t('选择', 'Select'),
                    ),
                  ),
                ],
              ),
              if (_article && !_selecting) ...[
                const SizedBox(height: 16),
                Text(
                  t('文章', 'Articles'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  t(
                    '整理长文与深入思考',
                    'Organize long-form writing and deeper thoughts',
                  ),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (_selecting)
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      t(
                        '已选${_selected.length}条（已加载）',
                        '${_selected.length} selected (loaded records)',
                      ),
                    ),
                    TextButton(
                      onPressed: _deleting
                          ? null
                          : () => setState(() => _selectLoaded()),
                      child: Text(t('全选已加载', 'Select loaded')),
                    ),
                    TextButton(
                      onPressed: _deleting || _selected.isEmpty
                          ? null
                          : _removeSelected,
                      child: Text(t('移到回收站', 'Move to trash')),
                    ),
                  ],
                ),
            ],
          ),
        );

  void _tapRecord(NoteListEntry note) {
    if (_deleting) return;
    if (_selecting) {
      setState(() {
        _toggleSelected(note);
      });
    } else {
      _edit(note);
    }
  }

  Widget _articleCard(NoteListEntry note) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: _deleting ? null : () => _tapRecord(note),
        onLongPress: !_typed || _deleting
            ? null
            : () => setState(() {
                _selecting = true;
                _setSelected(note.id, true);
              }),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_selecting)
                    Checkbox(
                      value: _selected.contains(note.id),
                      onChanged: _deleting ? null : (_) => _tapRecord(note),
                    ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        note.title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  if (!_selecting && _typed) _recordMenu(note),
                  if (!_selecting && !_typed)
                    PopupMenuButton<String>(
                      enabled: !_deleting,
                      tooltip: _article
                          ? t('文章操作', 'Article actions')
                          : t('笔记操作', 'Note actions'),
                      onSelected: (action) {
                        if (action == 'edit') {
                          _edit(note);
                        } else {
                          _remove(note);
                        }
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'edit',
                          child: Text(t('编辑', 'Edit')),
                        ),
                        PopupMenuItem(
                          value: 'trash',
                          child: Text(t('移到回收站', 'Move to trash')),
                        ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 4),
              if (_typed) _flags(note),
              Text(
                note.contentPreview,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (note.labels.isNotEmpty || note.updatedAt != null) ...[
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          for (final label in note.labels)
                            InkWell(
                              onTap:
                                  _deleting ||
                                      _selecting ||
                                      (widget.repository
                                              is! FilteredNotesRepository &&
                                          widget
                                                  .listSource
                                                  ?.capabilities
                                                  .labels !=
                                              true)
                                  ? null
                                  : () {
                                      if (_typed) {
                                        _applyQuery(
                                          _query.copyWith(label: label),
                                        );
                                      } else {
                                        setState(() {
                                          _label = label;
                                          _clearSelection();
                                        });
                                        _load();
                                      }
                                    },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary.withValues(
                                    alpha: .09,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  label,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (note.updatedAt != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        _date(note.updatedAt!),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _date(DateTime value) {
    final date = value.toLocal();
    return widget.english
        ? '${date.month}/${date.day}${date.year == DateTime.now().year ? '' : '/${date.year}'}'
        : '${date.year == DateTime.now().year ? '' : '${date.year}年'}${date.month}月${date.day.toString().padLeft(2, '0')}日';
  }

  @override
  void dispose() {
    _generation++;
    _selection?.retire();
    widget.pinActions?.retire();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      actions: [
        if (_selecting)
          IconButton(
            tooltip: t('批量移到回收站', 'Move selected to trash'),
            onPressed: _deleting || _selected.isEmpty ? null : _removeSelected,
            icon: const Icon(Icons.delete_outline),
          ),
      ],
      title: Text(
        _article
            ? t('知识库 · 文章', 'Knowledge · Articles')
            : t('知识库 · 笔记', 'Knowledge · Notes'),
      ),
    ),
    floatingActionButton: _selecting
        ? null
        : FloatingActionButton(
            shape: _article ? const CircleBorder() : null,
            onPressed: _deleting ? null : () => _edit(),
            tooltip: _article
                ? t('新建文章', 'New article')
                : t('新建笔记', 'New note'),
            child: const Icon(Icons.add),
          ),
    body: PopScope(
      canPop: !_deleting,
      child: RefreshIndicator(
        onRefresh: () => _load(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            Padding(
              padding: EdgeInsets.all(_article ? 16 : 24),
              child: TextField(
                controller: _search,
                enabled: !_deleting,
                onSubmitted: (_) => _submitSearch(),
                decoration: InputDecoration(
                  hintText: _typed
                      ? (widget.listSource!.capabilities.searchHint ==
                                'title-or-label'
                            ? t('搜索标题或标签', 'Search title or labels')
                            : t('搜索标题或正文', 'Search title or content'))
                      : _article
                      ? t('搜索文章', 'Search articles')
                      : t('搜索笔记', 'Search notes'),
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _article
                      ? null
                      : IconButton(
                          onPressed: _deleting
                              ? null
                              : () {
                                  _submitSearch();
                                },
                          icon: const Icon(Icons.arrow_forward),
                        ),
                ),
              ),
            ),
            _filters(),
            if (_busy || _deleting) const LinearProgressIndicator(),
            if (_error != null)
              MaterialBanner(
                content: Text(_error!),
                actions: [
                  TextButton(
                    onPressed: () => _load(),
                    child: Text(t('重试', 'Retry')),
                  ),
                ],
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_notes.isEmpty && !_busy && _error == null)
                    Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        _label.isNotEmpty ||
                                _search.text.isNotEmpty ||
                                _pinned.isNotEmpty
                            ? t('没有符合条件的记录', 'No matching records')
                            : _article
                            ? t(
                                '还没有文章，点击 + 开始写作',
                                'No articles yet. Tap + to start writing.',
                              )
                            : t(
                                '还没有笔记，点击 + 开始记录',
                                'No notes yet. Tap + to start.',
                              ),
                      ),
                    ),
                  for (final note in _notes)
                    if (_article)
                      _articleCard(note)
                    else
                      Card(
                        child: ListTile(
                          leading: _selecting
                              ? Checkbox(
                                  value: _selected.contains(note.id),
                                  onChanged: _deleting
                                      ? null
                                      : (value) => setState(() {
                                          _setSelected(note.id, value == true);
                                        }),
                                )
                              : null,
                          onLongPress: !_typed || _deleting
                              ? null
                              : () => setState(() {
                                  _selecting = true;
                                  _setSelected(note.id, true);
                                }),
                          onTap: _deleting
                              ? null
                              : () {
                                  if (_selecting) {
                                    setState(() {
                                      _toggleSelected(note);
                                    });
                                  } else {
                                    _edit(note);
                                  }
                                },
                          title: Text(
                            note.title,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (_typed) _flags(note),
                              Text(
                                note.contentPreview,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (note.labels.isNotEmpty ||
                                  note.updatedAt != null) ...[
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 4,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    for (final label in note.labels)
                                      Text(
                                        label,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.primary,
                                        ),
                                      ),
                                    if (note.updatedAt != null)
                                      Text(
                                        _date(note.updatedAt!),
                                        style: Theme.of(
                                          context,
                                        ).textTheme.labelSmall,
                                      ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                          trailing: _selecting
                              ? null
                              : _typed
                              ? _recordMenu(note)
                              : _article || widget.onShareSettings != null
                              ? PopupMenuButton<String>(
                                  tooltip: _article
                                      ? t('文章操作', 'Article actions')
                                      : t('笔记操作', 'Note actions'),
                                  onSelected: (action) {
                                    if (action == 'edit') {
                                      _edit(note);
                                    } else if (action == 'sharing') {
                                      _sharing(note);
                                    } else {
                                      _remove(note);
                                    }
                                  },
                                  itemBuilder: (_) => [
                                    if (widget.onShareSettings != null)
                                      PopupMenuItem(
                                        value: 'sharing',
                                        child: Text(
                                          t('分享设置', 'Sharing settings'),
                                        ),
                                      ),
                                    PopupMenuItem(
                                      value: 'edit',
                                      child: Text(t('编辑', 'Edit')),
                                    ),
                                    PopupMenuItem(
                                      value: 'trash',
                                      child: Text(t('移到回收站', 'Move to trash')),
                                    ),
                                  ],
                                )
                              : IconButton(
                                  tooltip: t('移到回收站', 'Move to trash'),
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () => _remove(note),
                                ),
                        ),
                      ),
                  if (_more && _notes.isNotEmpty)
                    TextButton(
                      onPressed: _busy ? null : () => _load(next: true),
                      child: Text(t('加载更多', 'Load more')),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class NoteEditorPage extends StatefulWidget {
  const NoteEditorPage({
    super.key,
    required this.repository,
    required this.note,
    this.english = false,
    this.collection = NoteCollection.note,
    this.drafts,
    this.attachments,
    this.onMemoryDraftChanged,
    this.allowAttachmentInsertion = true,
    this.pickFile,
    this.shareFile,
    this.documentPath,
    this.contentEditorTitle,
    this.contentContextTag,
    this.onSaveAcknowledged,
  });
  final NotesRepository repository;
  final void Function(Note saved, bool metadataComplete, bool created)?
  onSaveAcknowledged;

  /// A document uses the same editor state and media pipeline with its own
  /// prototype layout. Null preserves the existing note/article layouts.
  final String? documentPath;

  /// A content-only Markdown resource (topic summary/comment) uses the same
  /// editor, drafts and attachments without a synthetic editable title.
  final String? contentEditorTitle;
  final String? contentContextTag;
  final DraftVault? drafts;
  final AttachmentRepository? attachments;
  final ValueChanged<Note>? onMemoryDraftChanged;
  final bool allowAttachmentInsertion;
  final Future<XFile?> Function(bool imagesOnly)? pickFile;
  final Future<void> Function(Attachment attachment, Uint8List bytes)?
  shareFile;
  final Note note;
  final bool english;
  final NoteCollection collection;
  @override
  State<NoteEditorPage> createState() => _NoteEditorPageState();
}

class _NoteEditorPageState extends State<NoteEditorPage>
    with WidgetsBindingObserver {
  late final TextEditingController _title, _content;
  late Note _saved;
  late List<String> _labels;
  bool _saving = false, _preview = false, _allowLeave = false;
  String? _error, _draftError;
  Timer? _draftTimer;
  bool _saveIncomplete = false, _uploading = false, _sharing = false;
  final Map<Uri, int> _attachmentSizes = {};
  AttachmentCancellation? _uploadCancellation;
  bool _draftReady = false, _draftRetained = false, _leaving = false;
  int _editVersion = 0;
  DraftVault? get _vault => _saved.isProtected ? null : widget.drafts;
  Note get _snapshot => _saved.copyWith(
    title: _title.text,
    content: _content.text,
    labels: List.of(_labels),
  );
  String t(String zh, String en) => widget.english ? en : zh;
  bool get _article => widget.collection == NoteCollection.article;
  bool get _document => widget.documentPath != null || _contentOnly;
  bool get _contentOnly => widget.contentEditorTitle != null;
  bool get _dirty =>
      _saveIncomplete ||
      (_saved.id == null &&
          (_title.text.isNotEmpty ||
              _content.text.isNotEmpty ||
              _labels.isNotEmpty)) ||
      _title.text != _saved.title ||
      _content.text != _saved.content ||
      !listEquals(_labels, _saved.labels);
  @override
  void initState() {
    super.initState();
    _saved = widget.note;
    _labels = List.of(_saved.labels);
    WidgetsBinding.instance.addObserver(this);
    _draftReady = widget.drafts == null || _saved.isProtected;
    WidgetsBinding.instance.addPostFrameCallback((_) => _restoreDraft());
    _title = TextEditingController(text: _saved.title)..addListener(_changed);
    _content = TextEditingController(text: _saved.content)
      ..addListener(_changed);
  }

  void _changed() {
    // Revokes old source-bound image capabilities before any asynchronous
    // preview or draft save can observe the new text.
    widget.onMemoryDraftChanged?.call(_snapshot);
    _editVersion++;
    setState(() => _draftRetained = false);
    _draftTimer?.cancel();
    if (_draftReady && _vault != null) {
      _draftTimer = Timer(const Duration(milliseconds: 600), _persistDraft);
    }
  }

  Future<void> _restoreDraft() async {
    final vault = _vault;
    if (vault == null || _draftReady || !mounted) return;
    setState(() => _draftError = null);
    try {
      final draft = await vault.read(_saved.id);
      if (!mounted) return;
      if (draft != null &&
          (draft.title != _saved.title ||
              draft.content != _saved.content ||
              !listEquals(draft.labels, _saved.labels))) {
        final restore = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => PopScope(
            canPop: false,
            child: AlertDialog(
              scrollable: true,
              title: Text(t('发现未保存草稿', 'Unsaved draft found')),
              content: SizedBox(
                width: 292,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      t(
                        _article
                            ? '此文章有上次保留的修改。请选择恢复草稿，或继续使用已保存内容。'
                            : '此笔记有上次保留的修改。请选择恢复草稿，或继续使用已保存内容。',
                        'This note has retained changes. Restore the draft or use the saved content.',
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(t('恢复草稿', 'Restore draft')),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(t('使用已保存内容', 'Use saved content')),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        if (!mounted) return;
        if (restore == true) {
          _title.text = draft.title;
          _content.text = draft.content;
          _labels = List.of(draft.labels);
          _draftRetained = true;
        } else {
          await vault.remove(_saved.id);
        }
      }
      if (mounted) setState(() => _draftReady = true);
    } catch (error) {
      if (mounted) setState(() => _draftError = error.toString());
    }
  }

  Future<bool> _persistDraft() async {
    _draftTimer?.cancel();
    final vault = _vault;
    if (vault == null || !_draftReady) return false;
    final version = _editVersion;
    final snapshot = _snapshot;
    try {
      if (_dirty) {
        await vault.write(snapshot);
      } else {
        await vault.remove(snapshot.id);
      }
      if (mounted && version == _editVersion) {
        setState(() {
          _draftRetained = _dirty;
          _draftError = null;
        });
      }
      return true;
    } catch (error) {
      if (mounted) {
        setState(() {
          _draftRetained = false;
          _draftError = error.toString();
        });
      }
      return false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _persistDraft();
    }
  }

  Future<bool> _save() async {
    if (_saving || _uploading || !_draftReady) return false;
    if (_contentOnly && _content.text.trim().runes.length > 20000) {
      setState(
        () =>
            _error = t('正文最多20000字', 'Content is limited to 20000 characters'),
      );
      return false;
    }
    if (_contentOnly && _title.text.trim().isEmpty) {
      _title.text = t('正文', 'Content');
    }
    if (utf8.encode(_title.text).length > 200 ||
        utf8.encode(_content.text).length > noteEditorMaxContentUtf8Bytes) {
      setState(
        () => _error = t(
          '标题或正文超出服务器长度限制',
          'Title or content exceeds the server limit',
        ),
      );
      return false;
    }
    if (_title.text.trim().isEmpty) {
      if (_saved.id != null) {
        setState(
          () => _error = (_document
              ? t('请输入文档名称', 'Enter a document name')
              : _article
              ? t('请输入文章标题', 'Enter an article title')
              : t('请输入笔记标题', 'Enter a note title')),
        );
        return false;
      }
      _title.text =
          '${(_article ? t('未命名文章', 'Untitled article') : t('未命名笔记', 'Untitled note'))} ${DateTime.now().toIso8601String().substring(0, 19).replaceFirst('T', ' ')}';
    }
    _draftTimer?.cancel();
    final snapshot = _snapshot;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final id = await widget.repository.save(snapshot);
      if (!mounted) return false;
      _draftTimer?.cancel();
      setState(() {
        _saved = snapshot.copyWith(id: id);
        _saveIncomplete = false;
      });
      widget.onSaveAcknowledged?.call(
        snapshot.copyWith(id: id),
        true,
        snapshot.id == null,
      );
      try {
        await _vault?.remove(snapshot.id);
      } catch (error) {
        if (mounted) setState(() => _draftError = error.toString());
      }
      if (!mounted) return false;
      if (_dirty) {
        await _persistDraft();
      } else {
        setState(() => _draftRetained = false);
      }
      return !_dirty;
    } catch (error) {
      if (mounted) {
        setState(() {
          if (error is NoteSaveFailure) {
            _saved = _saved.copyWith(id: error.savedId);
            _saveIncomplete = true;
          }
          _error = error.toString();
        });
        if (error is NoteSaveFailure) {
          widget.onSaveAcknowledged?.call(
            snapshot.copyWith(id: error.savedId),
            false,
            snapshot.id == null,
          );
          try {
            await _vault?.remove(snapshot.id);
          } catch (_) {
            /* A later draft write still reports storage errors. */
          }
          await _persistDraft();
        }
      }
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addAttachment(bool imagesOnly) async {
    final repository = widget.attachments;
    if (repository == null || _uploading || !_draftReady) return;
    final before = _content.text;
    final selection = _content.selection;
    final cancellation = AttachmentCancellation();
    _uploadCancellation = cancellation;
    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      final picker = widget.pickFile;
      final file = picker != null
          ? await picker(imagesOnly)
          : await openFile(
              acceptedTypeGroups: imagesOnly
                  ? [
                      const XTypeGroup(
                        label: 'Images',
                        extensions: [
                          'png',
                          'jpg',
                          'jpeg',
                          'gif',
                          'webp',
                          'bmp',
                        ],
                        mimeTypes: [
                          'image/png',
                          'image/jpeg',
                          'image/gif',
                          'image/webp',
                          'image/bmp',
                        ],
                      ),
                    ]
                  : [],
            );
      if (file == null || !mounted) return;
      final attachment = await repository.add(
        file,
        protected: _saved.isProtected,
        cancellation: cancellation,
      );
      cancellation.check();
      if (!mounted) return;
      final text = _content.text;
      final current = _content.selection;
      final at = text == before && selection.isValid
          ? selection.end.clamp(0, text.length)
          : current.isValid
          ? current.end.clamp(0, text.length)
          : text.length;
      final snippet =
          '\n${markdownAttachment(attachment.name, attachment.uri, image: attachment.image)}\n';
      _content.value = TextEditingValue(
        text: text.replaceRange(at, at, snippet),
        selection: TextSelection.collapsed(offset: at + snippet.length),
      );
      if (attachment.size != null) {
        _attachmentSizes[attachment.uri] = attachment.size!;
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _shareAttachment(
    Attachment attachment, [
    Uint8List? existing,
  ]) async {
    if (_sharing || widget.attachments == null) return;
    setState(() {
      _sharing = true;
      _error = null;
    });
    try {
      await shareBookstarkAttachment(
        context,
        widget.attachments!,
        attachment,
        bytes: existing,
        override: widget.shareFile,
      );
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _openLink(String text, String? href) => openBookstarkLink(
    context,
    text,
    href,
    repository: widget.attachments,
    english: widget.english,
    onShare: _shareAttachment,
  );

  void _removeAttachment(Attachment attachment) {
    final updated = removeAttachmentReference(_content.text, attachment);
    if (updated != _content.text) {
      _content.text = updated;
      return;
    }
    setState(() => _preview = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          t(
            '此引用需手动核对，请在正文中编辑；原文和文件均已保留',
            'Review this reference in the source. The original text and stored file are retained.',
          ),
        ),
      ),
    );
  }

  Future<void> _editLabels() async {
    if (!_draftReady) return;
    var value = _labels.join(', ');
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('编辑标签', 'Edit labels')),
        content: TextFormField(
          initialValue: value,
          onChanged: (text) => value = text,
          autofocus: true,
          decoration: InputDecoration(
            hintText: t('用逗号分隔多个标签', 'Separate labels with commas'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t('取消', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, value),
            child: Text(t('确定', 'Apply')),
          ),
        ],
      ),
    );
    if (mounted && result != null) {
      setState(
        () => _labels = result
            .split(RegExp('[,，]'))
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toSet()
            .toList(),
      );
      _changed();
    }
  }

  void _insert(String before, String after) {
    if (!_draftReady) return;
    wrapMarkdown(_content, before, after);
  }

  Future<void> _leave() async {
    if (_uploading) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(t('正在处理附件，请稍候', 'Processing attachment. Please wait.')),
        ),
      );
      return;
    }
    if (_saving || _leaving) return;
    _leaving = true;
    try {
      if (_dirty) {
        final action = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            scrollable: true,
            title: Text(t('尚有未保存的修改', 'Unsaved changes')),
            content: Text(
              _saved.isProtected
                  ? t(
                      _article
                          ? '此文章已加密，解锁内容不会保留为磁盘草稿。'
                          : '此笔记已加密，解锁内容不会保留为磁盘草稿。',
                      'This protected note cannot be retained as an on-disk draft.',
                    )
                  : t('请选择如何处理当前修改', 'Choose how to handle your changes.'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(t('取消', 'Cancel')),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, 'discard'),
                child: Text(t('放弃修改', 'Discard')),
              ),
              if (_vault != null && _draftReady)
                TextButton(
                  onPressed: () => Navigator.pop(context, 'keep'),
                  child: Text(t('保留草稿并返回', 'Keep draft and leave')),
                ),
              FilledButton(
                onPressed: () => Navigator.pop(context, 'save'),
                child: Text(t('保存并返回', 'Save and leave')),
              ),
            ],
          ),
        );
        if (action == null || !mounted) return;
        _draftTimer?.cancel();
        if (action == 'save' && !await _save()) return;
        if (action == 'keep' && !await _persistDraft()) return;
        if (action == 'discard') {
          try {
            await _vault?.remove(_saved.id);
          } catch (error) {
            if (mounted) setState(() => _draftError = error.toString());
            return;
          }
        }
      }
      if (mounted) {
        _draftTimer?.cancel();
        setState(() => _allowLeave = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.pop(context);
        });
      }
    } finally {
      _leaving = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _uploadCancellation?.cancel();
    _draftTimer?.cancel();
    if (!_allowLeave && _dirty && _draftReady && _vault != null) {
      _persistDraft();
    }
    _title.dispose();
    _content.dispose();
    super.dispose();
  }

  Future<void> _chooseDocumentAttachment() async {
    final image = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: Text(t('插入图片', 'Insert image')),
              onTap: () => Navigator.pop(context, true),
            ),
            ListTile(
              leading: const Icon(Icons.attach_file),
              title: Text(t('添加文件', 'Attach file')),
              onTap: () => Navigator.pop(context, false),
            ),
          ],
        ),
      ),
    );
    if (image != null && mounted) await _addAttachment(image);
  }

  List<Widget> _attachmentRows() => [
    if (widget.attachments != null)
      for (final attachment in noteAttachments(
        _content.text,
        widget.attachments!.owns,
      ))
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            attachment.image ? Icons.image_outlined : Icons.attach_file,
          ),
          title: Text(
            attachment.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: _attachmentSizes[attachment.uri] == null
              ? null
              : Text('${_attachmentSizes[attachment.uri]} B'),
          onTap: () => _openLink(attachment.name, attachment.uri.toString()),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: t('分享附件', 'Share attachment'),
                onPressed: _sharing ? null : () => _shareAttachment(attachment),
                icon: const Icon(Icons.share_outlined),
              ),
              IconButton(
                tooltip: t('移除引用', 'Remove reference'),
                onPressed: () => _removeAttachment(attachment),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
  ];

  Widget _documentBody() => SafeArea(
    child: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(widget.documentPath ?? ''),
        if (widget.contentContextTag != null) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Chip(
              label: Text(
                widget.contentContextTag!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
        const SizedBox(height: 24),
        if (!_draftReady) Text(t('正在检查草稿…', 'Checking for drafts…')),
        if (_draftError != null) ...[
          Text(
            _draftError!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          if (!_draftReady)
            TextButton(
              onPressed: _restoreDraft,
              child: Text(t('重试读取草稿', 'Retry loading draft')),
            ),
        ],
        if (_draftRetained)
          Text(t('草稿已保留 · 尚未提交', 'Draft retained · Not submitted')),
        if (!_contentOnly) ...[
          TextField(
            controller: _title,
            enabled: _draftReady,
            decoration: InputDecoration(labelText: t('文档名称', 'Document name')),
          ),
          const SizedBox(height: 24),
        ],
        SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(value: false, label: Text(t('编辑', 'Edit'))),
            ButtonSegment(value: true, label: Text(t('预览', 'Preview'))),
          ],
          selected: {_preview},
          onSelectionChanged: (selection) =>
              setState(() => _preview = selection.single),
        ),
        const SizedBox(height: 16),
        if (!_preview)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              IconButton.outlined(
                tooltip: t('加粗', 'Bold'),
                onPressed: () => _insert('**', '**'),
                icon: const Icon(Icons.format_bold),
              ),
              IconButton.outlined(
                tooltip: t('斜体', 'Italic'),
                onPressed: () => _insert('*', '*'),
                icon: const Icon(Icons.format_italic),
              ),
              IconButton.outlined(
                tooltip: t('标题', 'Heading'),
                onPressed: () => _insert('## ', ''),
                icon: const Icon(Icons.title),
              ),
              IconButton.outlined(
                tooltip: t('列表', 'List'),
                onPressed: () => _insert('- ', ''),
                icon: const Icon(Icons.format_list_bulleted),
              ),
              IconButton.outlined(
                tooltip: t('链接', 'Link'),
                onPressed: () => _insert('[', '](https://)'),
                icon: const Icon(Icons.link),
              ),
              if (widget.attachments != null &&
                  widget.allowAttachmentInsertion) ...[
                IconButton.outlined(
                  tooltip: t('添加附件', 'Add attachment'),
                  onPressed: _uploading ? null : _chooseDocumentAttachment,
                  icon: const Icon(Icons.attach_file),
                ),
              ],
            ],
          ),
        const SizedBox(height: 24),
        if (_saving) const LinearProgressIndicator(),
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (_uploading) ...[
          const LinearProgressIndicator(),
          TextButton(
            onPressed: () => _uploadCancellation?.cancel(),
            child: Text(t('取消附件操作', 'Cancel attachment')),
          ),
        ],
        if (_sharing) Text(t('正在准备分享…', 'Preparing share…')),
        ..._attachmentRows(),
        if (_preview)
          BookstarkMarkdown(
            data: _content.text,
            attachments: widget.attachments,
            english: widget.english,
            onLink: _openLink,
            onShare: (attachment, bytes) => _shareAttachment(attachment, bytes),
          )
        else
          TextField(
            controller: _content,
            enabled: _draftReady,
            minLines: 16,
            maxLines: null,
            decoration: InputDecoration(
              labelText: t('Markdown正文', 'Markdown content'),
              helperText: _contentOnly
                  ? t(
                      '最多20000字，支持Markdown',
                      'Up to 20000 characters; Markdown supported',
                    )
                  : null,
              alignLabelWithHint: true,
            ),
          ),
        const SizedBox(height: 24),
        Text(
          t('未保存时离开可保留草稿', 'Keep a draft when leaving with unsaved changes'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _allowLeave || (!_dirty && !_saving && !_uploading),
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) _leave();
    },
    child: Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: t('返回', 'Back'),
          onPressed: _leave,
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(
          (widget.contentEditorTitle ??
              (_document
                  ? t('编辑文档', 'Edit document')
                  : _article
                  ? t('编辑文章', 'Edit article')
                  : t('编辑笔记', 'Edit note'))),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: _document
                ? TextButton(
                    onPressed: _saving || _uploading || !_draftReady
                        ? null
                        : _save,
                    child: Text(
                      _saving ? t('保存中…', 'Saving…') : t('保存', 'Save'),
                    ),
                  )
                : FilledButton(
                    onPressed: _saving || _uploading || !_draftReady
                        ? null
                        : _save,
                    child: Text(
                      _saving ? t('保存中…', 'Saving…') : t('保存', 'Save'),
                    ),
                  ),
          ),
        ],
      ),
      body: _document
          ? _documentBody()
          : Column(
              children: [
                Flexible(
                  flex: 3,
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!_draftReady) ...[
                            Text(t('正在检查草稿…', 'Checking for drafts…')),
                            if (_draftError != null)
                              TextButton(
                                onPressed: _restoreDraft,
                                child: Text(t('重试读取草稿', 'Retry loading draft')),
                              ),
                          ],
                          if (_draftError != null)
                            Text(
                              '${t('草稿未保留', 'Draft not retained')}: $_draftError',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          if (_draftRetained)
                            Text(
                              t(
                                '草稿已保留 · 尚未提交',
                                'Draft retained · Not submitted',
                              ),
                            ),
                          if (_saved.isProtected)
                            Text(
                              t('已解锁 · 不保留磁盘草稿', 'Unlocked · No on-disk draft'),
                            ),
                          Text(
                            _saved.id == null
                                ? (_article
                                      ? t('新文章 · 尚未保存', 'New article · Unsaved')
                                      : t('新笔记 · 尚未保存', 'New note · Unsaved'))
                                : _dirty
                                ? t('未保存', 'Unsaved')
                                : t('已保存', 'Saved'),
                          ),
                          TextField(
                            enabled: _draftReady,
                            controller: _title,
                            decoration: InputDecoration(
                              hintText: (_article
                                  ? t('文章标题', 'Article title')
                                  : t('笔记标题', 'Note title')),
                            ),
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          Wrap(
                            children: [
                              for (final label in _labels)
                                Chip(
                                  label: Text(label),
                                  onDeleted: !_draftReady
                                      ? null
                                      : () {
                                          _labels.remove(label);
                                          _changed();
                                        },
                                ),
                              ActionChip(
                                avatar: const Icon(Icons.label_outline),
                                label: Text(t('添加标签', 'Add labels')),
                                onPressed: _editLabels,
                              ),
                            ],
                          ),
                          if (_error != null)
                            Text(
                              _error!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          if (_uploading)
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        t('正在处理附件…', 'Processing attachment…'),
                                      ),
                                    ),
                                  ],
                                ),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton(
                                    onPressed: () =>
                                        _uploadCancellation?.cancel(),
                                    child: Text(
                                      t('取消附件操作', 'Cancel attachment'),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          if (_sharing) Text(t('正在准备分享…', 'Preparing share…')),
                          ..._attachmentRows(),
                          Row(
                            children: [
                              for (final mode in [false, true])
                                Expanded(
                                  child: mode == _preview
                                      ? FilledButton(
                                          onPressed: () =>
                                              setState(() => _preview = mode),
                                          child: Text(
                                            mode
                                                ? t('预览', 'Preview')
                                                : t('编辑', 'Edit'),
                                            textAlign: TextAlign.center,
                                          ),
                                        )
                                      : TextButton(
                                          onPressed: () =>
                                              setState(() => _preview = mode),
                                          child: Text(
                                            mode
                                                ? t('预览', 'Preview')
                                                : t('编辑', 'Edit'),
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  flex: 5,
                  child: _preview
                      ? BookstarkMarkdown(
                          data: _content.text,
                          attachments: widget.attachments,
                          english: widget.english,
                          scrollable: true,
                          onLink: _openLink,
                          onShare: (attachment, bytes) =>
                              _shareAttachment(attachment, bytes),
                        )
                      : Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: TextField(
                            enabled: _draftReady,
                            controller: _content,
                            expands: true,
                            minLines: null,
                            maxLines: null,
                            textAlignVertical: TextAlignVertical.top,
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              hintText: 'Markdown…',
                            ),
                          ),
                        ),
                ),
                if (!_preview)
                  SafeArea(
                    top: false,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          IconButton(
                            tooltip: t('标题', 'Heading'),
                            onPressed: () => _insert('## ', ''),
                            icon: const Icon(Icons.title),
                          ),
                          IconButton(
                            tooltip: t('加粗', 'Bold'),
                            onPressed: () => _insert('**', '**'),
                            icon: const Icon(Icons.format_bold),
                          ),
                          IconButton(
                            tooltip: t('斜体', 'Italic'),
                            onPressed: () => _insert('*', '*'),
                            icon: const Icon(Icons.format_italic),
                          ),
                          IconButton(
                            tooltip: t('待办', 'Task'),
                            onPressed: () => _insert('- [ ] ', ''),
                            icon: const Icon(Icons.check_box_outlined),
                          ),
                          IconButton(
                            tooltip: t('链接', 'Link'),
                            onPressed: () => _insert('[', '](https://)'),
                            icon: const Icon(Icons.link),
                          ),
                          if (widget.attachments != null &&
                              widget.allowAttachmentInsertion) ...[
                            IconButton(
                              tooltip: t('插入图片', 'Insert image'),
                              onPressed: _uploading
                                  ? null
                                  : () => _addAttachment(true),
                              icon: const Icon(Icons.image_outlined),
                            ),
                            IconButton(
                              tooltip: t('添加附件', 'Add attachment'),
                              onPressed: _uploading
                                  ? null
                                  : () => _addAttachment(false),
                              icon: const Icon(Icons.attach_file),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    ),
  );
}
