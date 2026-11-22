import 'dart:convert';
import 'package:flutter/material.dart';
import '../../core/books_repository.dart';
import '../../core/book_draft_vault.dart';
import '../../core/labels_repository.dart';
import '../../widgets/label_picker.dart';

class BookEditorPage extends StatefulWidget {
  const BookEditorPage({
    super.key,
    required this.repository,
    required this.book,
    required this.labelsRepository,
    this.vault,
    this.english = false,
    this.ownerScope,
    this.isCurrentScope,
  });
  final Object? ownerScope;
  final bool Function()? isCurrentScope;
  final BooksRepository repository;
  final LabelsRepository labelsRepository;
  final BookItem book;
  final BookDraftVault? vault;
  final bool english;
  @override
  State<BookEditorPage> createState() => _BookEditorPageState();
}

class _BookEditorPageState extends State<BookEditorPage> {
  late final TextEditingController _name, _description;
  late BookItem _saved;
  late List<String> _labels;
  bool _ready = false, _busy = false, _allowLeave = false, _wrote = false;
  bool _choosing = false;
  String? _error;
  bool _cleanupPending = false;
  late final Set<int?> _draftIds = {widget.book.id};
  int _ownerEpoch = 0;
  bool _retired = false;
  bool _owned(int epoch, BooksRepository repository, BookDraftVault? vault) =>
      mounted &&
      !_retired &&
      epoch == _ownerEpoch &&
      identical(widget.repository, repository) &&
      identical(widget.vault, vault) &&
      (widget.isCurrentScope?.call() ?? true);
  @override
  void didUpdateWidget(covariant BookEditorPage old) {
    super.didUpdateWidget(old);
    if (!identical(old.repository, widget.repository) ||
        !identical(old.vault, widget.vault) ||
        old.ownerScope != widget.ownerScope) {
      _ownerEpoch++;
      _retired = true;
    }
  }

  String t(String zh, String en) => widget.english ? en : zh;
  BookItem get _snapshot => _saved.copyWith(
    name: _name.text,
    description: _description.text,
    labels: List.of(_labels),
  );
  bool _same(BookItem a, BookItem b) =>
      a.name == b.name &&
      a.description == b.description &&
      a.labels.length == b.labels.length &&
      a.labels.toSet().containsAll(b.labels);
  bool get _dirty => !_same(_saved, _snapshot);
  @override
  void initState() {
    super.initState();
    _saved = widget.book;
    _labels = List.of(_saved.labels);
    _name = TextEditingController(text: _saved.name)..addListener(_changed);
    _description = TextEditingController(text: _saved.description)
      ..addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) => _restore());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _restore() async {
    final epoch = _ownerEpoch,
        repository = widget.repository,
        vault = widget.vault;
    if (!_owned(epoch, repository, vault)) return;
    try {
      if (!_saved.labelsLoaded) {
        throw StateError('请先加载书籍详情 / Load book details first');
      }
      final draft = await vault?.read(_saved.id);
      if (!_owned(epoch, repository, vault)) return;
      if (draft != null && !_same(draft, _saved)) {
        setState(() => _choosing = true);
        if (!mounted) return;
        final restore = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            scrollable: true,
            title: Text(t('发现书籍草稿', 'Book draft found')),
            content: Text(t('恢复上次未保存的修改？', 'Restore your unsaved changes?')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(t('放弃草稿', 'Discard draft')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(t('恢复', 'Restore')),
              ),
            ],
          ),
        );
        if (!_owned(epoch, repository, vault)) return;
        setState(() => _choosing = false);
        if (restore == true) {
          _name.text = draft.name;
          _description.text = draft.description;
          _labels = List.of(draft.labels);
        } else {
          if (!_owned(epoch, repository, vault)) return;
          await vault?.remove(_saved.id);
        }
      }
      if (_owned(epoch, repository, vault)) setState(() => _ready = true);
    } catch (error) {
      if (_owned(epoch, repository, vault)) {
        setState(() => _error = error.toString());
      }
    }
  }

  Future<void> _clearBrokenDraft() async {
    final epoch = _ownerEpoch,
        repository = widget.repository,
        vault = widget.vault;
    if (!_owned(epoch, repository, vault)) return;
    try {
      await vault?.remove(_saved.id);
      if (_owned(epoch, repository, vault)) {
        setState(() {
          _ready = true;
          _error = null;
        });
      }
    } catch (error) {
      if (_owned(epoch, repository, vault)) {
        setState(() => _error = error.toString());
      }
    }
  }

  Future<void> _cleanup() async {
    if (!_cleanupPending) return;
    final epoch = _ownerEpoch,
        repository = widget.repository,
        vault = widget.vault;
    for (final id in List<int?>.of(_draftIds)) {
      if (!_owned(epoch, repository, vault)) {
        throw StateError('Book owner retired');
      }
      await vault?.remove(id);
      if (!_owned(epoch, repository, vault)) {
        throw StateError('Book owner retired');
      }
    }
    _cleanupPending = false;
  }

  Future<void> _save() async {
    if (_busy ||
        !_ready ||
        _retired ||
        widget.isCurrentScope?.call() == false) {
      return;
    }
    final epoch = _ownerEpoch,
        repository = widget.repository,
        vault = widget.vault;
    final snapshot = _snapshot;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_cleanupPending && !_dirty) {
        await _cleanup();
        if (!_owned(epoch, repository, vault)) return;
        _allowLeave = true;
        if (!mounted) return;
        Navigator.pop(context, true);
        return;
      }
      await vault?.write(snapshot);
      if (!_owned(epoch, repository, vault)) return;
      final id = await repository.save(snapshot);
      if (!_owned(epoch, repository, vault)) return;
      _saved = snapshot.copyWith(id: id);
      _wrote = true;
      _draftIds.add(id);
      _cleanupPending = true;
      await _cleanup();
      if (!_owned(epoch, repository, vault)) return;
      if (!_dirty) {
        _allowLeave = true;
        if (!mounted) return;
        Navigator.pop(context, true);
      }
    } on BookSaveFailure catch (error) {
      if (!_owned(epoch, repository, vault)) return;
      // Keep current fields dirty against the previous saved baseline, but retry
      // using PUT on the real created ID instead of posting another book.
      _saved = _saved.copyWith(id: error.savedId);
      _wrote = true;
      _draftIds.add(error.savedId);
      if (_owned(epoch, repository, vault)) {
        setState(() => _error = error.toString());
      }
    } catch (error) {
      if (_owned(epoch, repository, vault)) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (_owned(epoch, repository, vault)) setState(() => _busy = false);
    }
  }

  Future<void> _leave() async {
    final epoch = _ownerEpoch,
        repository = widget.repository,
        vault = widget.vault;
    if (!_owned(epoch, repository, vault)) return;
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _cleanup();
      if (!_owned(epoch, repository, vault)) return;
      if (_dirty) {
        setState(() => _choosing = true);
        if (!mounted) return;
        final action = await showDialog<String>(
          context: context,
          builder: (_) => AlertDialog(
            scrollable: true,
            title: Text(t('保留修改？', 'Keep changes?')),
            content: Text(t('书籍还有未保存的修改。', 'This book has unsaved changes.')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(t('继续编辑', 'Keep editing')),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, 'discard'),
                child: Text(t('放弃', 'Discard')),
              ),
              if (vault != null)
                FilledButton(
                  onPressed: () => Navigator.pop(context, 'keep'),
                  child: Text(t('保留草稿', 'Keep draft')),
                ),
            ],
          ),
        );
        if (!_owned(epoch, repository, vault)) return;
        setState(() => _choosing = false);
        if (action == null) return;
        if (action == 'keep') {
          if (!_owned(epoch, repository, vault)) return;
          await vault!.write(_snapshot);
          for (final id in _draftIds.where((id) => id != _saved.id)) {
            if (!_owned(epoch, repository, vault)) return;
            await vault.remove(id);
          }
        } else {
          for (final id in _draftIds) {
            if (!_owned(epoch, repository, vault)) return;
            await vault?.remove(id);
          }
        }
      }
      if (_owned(epoch, repository, vault)) {
        _allowLeave = true;
        if (!mounted) return;
        Navigator.pop(context, _wrote);
      }
    } catch (error) {
      if (_owned(epoch, repository, vault)) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (_owned(epoch, repository, vault)) setState(() => _busy = false);
    }
  }

  Future<void> _pickLabels() async {
    final epoch = _ownerEpoch,
        repository = widget.repository,
        vault = widget.vault;
    if (!_owned(epoch, repository, vault)) return;
    final labels = await showLabelPicker(
      context,
      repository: widget.labelsRepository,
      selected: _labels,
      english: widget.english,
    );
    if (_owned(epoch, repository, vault) && labels != null) {
      setState(() => _labels = labels);
    }
  }

  @override
  void dispose() {
    _ownerEpoch++;
    _retired = true;
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      (_retired || widget.isCurrentScope?.call() == false)
      ? Scaffold(
          appBar: AppBar(),
          body: Center(
            child: Text(t('空间已切换，请重新打开书籍', 'Space changed. Reopen the book.')),
          ),
        )
      : PopScope(
          canPop: _allowLeave,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _leave();
          },
          child: Scaffold(
            backgroundColor: Theme.of(context).colorScheme.surface,
            appBar: AppBar(
              leading: IconButton(
                tooltip: t('返回', 'Back'),
                onPressed: _busy ? null : _leave,
                icon: const Icon(Icons.arrow_back),
              ),
              title: Text(
                _saved.id == null
                    ? t('新建书籍', 'New book')
                    : t('书籍设置', 'Book settings'),
              ),
              actions: [
                TextButton(
                  onPressed: _ready && !_busy ? _save : null,
                  child: Text(t('保存', 'Save')),
                ),
              ],
            ),
            body: SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (!_choosing && (_busy || (!_ready && _error == null)))
                    const LinearProgressIndicator(),
                  if (_error != null) ...[
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    if (!_ready)
                      TextButton(
                        onPressed: _clearBrokenDraft,
                        child: Text(
                          t('清除损坏草稿并继续', 'Clear unreadable draft and continue'),
                        ),
                      ),
                    const SizedBox(height: 16),
                  ],
                  Text(
                    t('修改书名、说明与标签', 'Edit the name, description and labels'),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _name,
                    enabled: _ready,
                    decoration: InputDecoration(
                      labelText: t('书名', 'Book name'),
                      helperText:
                          '${utf8.encode(_name.text).length}/200 ${t('字节', 'UTF-8 bytes')}',
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _description,
                    enabled: _ready,
                    minLines: 4,
                    maxLines: 8,
                    decoration: InputDecoration(
                      labelText: t('说明', 'Description'),
                      helperText:
                          '${utf8.encode(_description.text).length}/2000 ${t('字节', 'UTF-8 bytes')}',
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    t('标签', 'Labels'),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ..._labels.map(
                        (name) => InputChip(
                          label: Text(name),
                          onDeleted: _ready
                              ? () => setState(() => _labels.remove(name))
                              : null,
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _ready && !_busy ? _pickLabels : null,
                        icon: const Icon(Icons.add),
                        label: Text(t('添加标签', 'Add labels')),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    t(
                      '选择已有标签，或输入新标签',
                      'Choose existing labels or enter a new one',
                    ),
                  ),
                  if (_saved.id != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Row(
                        children: [
                          const Icon(Icons.menu_book_outlined),
                          const SizedBox(width: 12),
                          Flexible(
                            child: Text(
                              t(
                                '${_saved.documentCount}篇文档',
                                '${_saved.documentCount} documents',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 24),
                  Text(
                    t(
                      '未保存时离开会提示保留或放弃修改',
                      'When leaving, choose to keep or discard unsaved changes',
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
}
