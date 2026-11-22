import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../../core/document_creation.dart';
import '../../core/documents_repository.dart';
import '../../core/resource_creation_result.dart';
import 'document_location_page.dart';

class DocumentCreatePage extends StatefulWidget {
  const DocumentCreatePage({
    super.key,
    required this.controller,
    required this.onOpenEditor,
    required this.onReviewBook,
    this.initialLocation,
    this.english = false,
  });
  final DocumentCreationController controller;
  final DocumentLocation? initialLocation;
  final Future<void> Function(BuildContext, DocumentItem) onOpenEditor;
  final Future<void> Function(BuildContext, int bookId) onReviewBook;
  final bool english;
  @override
  State<DocumentCreatePage> createState() => _DocumentCreatePageState();
}

class _DocumentCreatePageState extends State<DocumentCreatePage> {
  final _name = TextEditingController();
  Future<void> _tail = Future.value();
  Timer? _timer;
  DocumentLocation? _location;
  String? _error;
  bool _ready = false, _busy = false, _allowLeave = false;
  DocumentCreationController get controller => widget.controller;
  DocumentCreationPhase get _phase =>
      controller.draft?.phase ?? DocumentCreationPhase.editing;
  bool get _editable =>
      _ready && !_busy && _phase == DocumentCreationPhase.editing;
  String t(String zh, String en) => widget.english ? en : zh;
  @override
  void initState() {
    super.initState();
    _restore();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _name.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    try {
      final initial = widget.initialLocation;
      await controller.initialize(
        initial: initial == null
            ? null
            : DocumentCreationDraft(
                bookId: initial.book.id!,
                parentId: initial.parentId,
                name: '',
              ),
      );
      final draft = controller.draft;
      if (draft != null) {
        _name.text = draft.name;
        try {
          final book = await controller.books.read(draft.bookId);
          final nodes = flattenDocuments(
            await controller.documents.tree(draft.bookId),
          );
          final parents = nodes.where((node) => node.id == draft.parentId);
          _location = DocumentLocation(
            book: book,
            parentId: draft.parentId,
            parentName: draft.parentId == 0
                ? t('书籍根目录', 'Book root')
                : parents.isEmpty
                ? t('父目录待核对', 'Parent needs verification')
                : parents.single.name,
          );
        } catch (error) {
          _error = error.toString();
        }
      }
      if (mounted) setState(() => _ready = true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _persist() {
    final location = _location;
    final old = controller.draft;
    if (location == null && old == null ||
        _phase != DocumentCreationPhase.editing) {
      return Future.value();
    }
    final value = DocumentCreationDraft(
      bookId: location?.book.id ?? old!.bookId,
      parentId: location?.parentId ?? old!.parentId,
      name: _name.text,
    );
    final operation = _tail.then((_) => controller.edit(value));
    _tail = operation.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return operation;
  }

  void _changed(String value) {
    setState(() {});
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 500), () async {
      try {
        await _persist();
        if (mounted) setState(() => _error = null);
      } catch (error) {
        if (mounted) setState(() => _error = error.toString());
      }
    });
  }

  Future<void> _chooseLocation() async {
    if (!_editable) return;
    _timer?.cancel();
    final location = await Navigator.of(context).push<DocumentLocation>(
      MaterialPageRoute(
        builder: (_) => DocumentLocationPage(
          books: controller.books,
          documents: controller.documents,
          initialBook: _location?.book,
          english: widget.english,
        ),
      ),
    );
    if (!mounted || location == null) return;
    setState(() => _location = location);
    try {
      await _persist();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _create() async {
    if (!_editable) return;
    _timer?.cancel();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _persist();
      await controller.create();
      if (!mounted) return;
      if (controller.storageError != null) {
        setState(
          () => _error = t(
            '文档已创建，但本机回执尚未保存。请保存回执后打开，勿重复创建。',
            'Document created, but its local receipt could not be stored. Save the receipt and open it; do not create again.',
          ),
        );
        return;
      }
      await _open();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open() async {
    final item = controller.acknowledged;
    if (controller.storageError != null) await controller.persistAcknowledged();
    if (!mounted) return;
    await widget.onOpenEditor(context, item);
    await controller.clear();
    if (!mounted) return;
    final result = ResourceCreationResult(
      kind: CreatedResourceKind.document,
      id: item.id,
      title: item.name,
      created: true,
      metadataComplete: true,
      bookId: item.bookId,
    );
    setState(() => _allowLeave = true);
    Navigator.of(context).pop(result);
  }

  Future<void> _reopen() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _open();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leave() async {
    if (_busy) return;
    _timer?.cancel();
    setState(() => _busy = true);
    try {
      try {
        if (_phase == DocumentCreationPhase.editing && _ready) await _persist();
      } catch (error) {
        if (!mounted) return;
        setState(() => _error = error.toString());
        final leave = await showDialog<bool>(
          context: context,
          builder: (dialog) => AlertDialog(
            title: Text(t('草稿未确认保存', 'Draft could not be saved')),
            content: Text(
              t(
                '当前输入未能安全保留，退出可能丢失尚未保存的修改。可以继续编辑，或仍然退出。',
                'Your current input could not be stored safely. Leaving may lose unsaved changes. You can continue editing or leave anyway.',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialog).pop(false),
                child: Text(t('继续编辑', 'Continue editing')),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialog).pop(true),
                child: Text(t('仍然退出', 'Leave anyway')),
              ),
            ],
          ),
        );
        if (leave != true || !mounted) return;
      }
      if (!mounted) return;
      setState(() => _allowLeave = true);
      Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _abandonUnknown() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('结束本机核对？', 'End local verification?')),
        content: Text(
          t(
            '远端可能已经创建文档。这只清除本机待核对记录，不删除远端文档，也不证明创建失败。请先查看书籍目录。',
            'A document may already exist on the server. This clears only the local pending record. It does not delete a remote document or establish that creation failed. Review the book first.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t('继续核对', 'Keep verifying')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(t('清除本机记录', 'Clear local record')),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await controller.clear(explicitlyAbandonUnknown: true);
      if (mounted) {
        setState(() => _allowLeave = true);
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final unknown =
        _phase == DocumentCreationPhase.unknown ||
        _phase == DocumentCreationPhase.submitting;
    final acknowledged = _phase == DocumentCreationPhase.acknowledged;
    final draft = controller.draft;
    return PopScope(
      canPop: _allowLeave,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: t('返回', 'Back'),
            onPressed: _busy ? null : _leave,
            icon: const Icon(Icons.arrow_back),
          ),
          title: Text(t('新建文档', 'New document')),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              16 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton(
                  onPressed: !_ready || _busy || unknown
                      ? null
                      : acknowledged
                      ? _reopen
                      : _location == null && draft == null
                      ? null
                      : _create,
                  child: Text(
                    _busy
                        ? t('处理中…', 'Working…')
                        : acknowledged
                        ? t('打开已创建文档', 'Open created document')
                        : t('创建并编辑', 'Create and edit'),
                  ),
                ),
                TextButton(
                  onPressed: _busy ? null : _leave,
                  child: Text(t('取消', 'Cancel')),
                ),
              ],
            ),
          ),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (!_ready || _busy) const LinearProgressIndicator(),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (unknown)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t('创建结果待核对', 'Creation result is unknown'),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          t(
                            '请求可能已在服务器执行。当前禁止再次创建，重启后仍保留此记录。',
                            'The request may have completed on the server. Creation is blocked and this record survives restart.',
                          ),
                        ),
                        TextButton(
                          onPressed: _busy || draft == null
                              ? null
                              : () async {
                                  setState(() => _busy = true);
                                  try {
                                    await widget.onReviewBook(
                                      context,
                                      draft.bookId,
                                    );
                                  } catch (error) {
                                    if (mounted) {
                                      setState(() => _error = error.toString());
                                    }
                                  } finally {
                                    if (mounted) setState(() => _busy = false);
                                  }
                                },
                          child: Text(t('查看书籍目录', 'Review book')),
                        ),
                        TextButton(
                          onPressed: _busy ? null : _abandonUnknown,
                          child: Text(t('结束本机核对', 'End local verification')),
                        ),
                      ],
                    ),
                  ),
                ),
              if (acknowledged)
                Text(
                  t(
                    '已创建文档 ID：${draft!.createdId}',
                    'Created document ID: ${draft.createdId}',
                  ),
                ),
              Text(
                t('文档位置', 'Document location'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.menu_book_outlined),
                  title: Text(
                    _location?.book.name ??
                        (draft == null
                            ? t('请选择位置', 'Choose a location')
                            : t(
                                '书籍 ID：${draft.bookId}',
                                'Book ID: ${draft.bookId}',
                              )),
                  ),
                  subtitle: _location == null
                      ? null
                      : Text(_location!.parentName),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _editable ? _chooseLocation : null,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                t(
                  '文档继承所属书籍的访问范围。',
                  'Documents inherit access from their book.',
                ),
              ),
              const SizedBox(height: 32),
              Text(
                t('文档名称', 'Document name'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _name,
                readOnly: !_editable,
                maxLength: 1000,
                onChanged: _changed,
                decoration: InputDecoration(
                  hintText: t('输入文档名称', 'Enter a document name'),
                  counterText:
                      '${utf8.encode(_name.text).length} / 200 UTF-8 bytes',
                  errorText: utf8.encode(_name.text).length > 200
                      ? t('名称超过200字节', 'Name exceeds 200 bytes')
                      : null,
                ),
              ),
              const SizedBox(height: 32),
              Text(
                t('文档类型', 'Document type'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.check_circle,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: const Text('Markdown'),
                  subtitle: Text(
                    t(
                      '原生编辑，支持图片与附件。',
                      'Native editor with images and attachments.',
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.info_outline),
                  title: Text(t('创建后进入编辑器', 'Open the editor after creation')),
                  subtitle: Text(
                    t(
                      '确认创建前不会发送创建请求。',
                      'No creation request is sent before confirmation.',
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
