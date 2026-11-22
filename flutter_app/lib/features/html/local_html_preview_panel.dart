import 'dart:convert';
import '../../core/local_attachments.dart';
import '../../core/local_html_preview_owner.dart';
import '../../core/native_complex_source_io.dart';
import 'local_html_attachment_preview.dart';
import 'dart:async';
import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as paths;
import 'package:path_provider/path_provider.dart';
import '../../core/attachments.dart' show attachmentName;
import '../../core/drive_models.dart';
import '../../core/local_store.dart';
import '../../core/local_drive_repository.dart';
import '../../core/local_html_preview_document.dart';
import '../../core/local_html_resources_repository.dart';
import 'local_html_browser_preview.dart';

class LocalHtmlPreviewHost extends StatefulWidget {
  const LocalHtmlPreviewHost({
    super.key,
    required this.store,
    required this.noteId,
    required this.collection,
    required this.source,
    this.english = false,
    this.isCurrentScope,
    this.baselineFingerprint,
    this.sourceIoScope,
  });
  final LocalStore store;
  final int noteId;
  final String collection, source;
  final bool english;
  final bool Function()? isCurrentScope;
  final String? baselineFingerprint;
  final ComplexSourceIoScope? sourceIoScope;
  @override
  State<LocalHtmlPreviewHost> createState() => _LocalHtmlPreviewHostState();
}

class _LocalHtmlPreviewHostState extends State<LocalHtmlPreviewHost> {
  LocalDriveRepository? _drive;
  LocalHtmlResourcesRepository? _resources;
  LocalAttachments? _attachments;
  LocalHtmlPreviewOwner? _previewOwner;
  bool _failed = false;
  int _epoch = 0;
  @override
  void initState() { super.initState(); unawaited(_open()); }

  Future<void> _open() async {
    final epoch = ++_epoch;
    final store = widget.store;
    final collection = widget.collection;
    final noteId = widget.noteId;
    final current = widget.isCurrentScope;
    final sourceOwner = widget.sourceIoScope;
    bool owned() => mounted && epoch == _epoch &&
        identical(widget.store, store) && widget.collection == collection &&
        widget.noteId == noteId && identical(widget.sourceIoScope, sourceOwner) &&
        !store.maintenance.retired &&
        (current?.call() ?? true);
    try {
      await _previewOwner?.retireAndDrain();
      if (!owned()) return;
      _drive?.dispose();
      var root = store.dataPaths?.driveBlobs;
      var attachmentsRoot = store.dataPaths?.attachments;
      if (root == null || attachmentsRoot == null) {
        final support = await getApplicationSupportDirectory();
        if (!owned()) return;
        final resolved = await support.resolveSymbolicLinks();
        if (!owned()) return;
        root ??= Directory(paths.join(resolved, 'drive-blobs'));
        attachmentsRoot ??= Directory(paths.join(resolved, 'attachments'));
      }
      final attachmentDirectory = attachmentsRoot;
      final drive = LocalDriveRepository(store, root);
      final resources = LocalHtmlResourcesRepository(
        store, drive, collection: collection,
      );
      if (!owned()) { drive.dispose(); return; }
      setState(() {
        _previewOwner = LocalHtmlPreviewOwner(
          isCurrentScope: owned, sourceOwner: sourceOwner);
        _drive = drive;
        _resources = resources;
        _attachments = LocalAttachments(
          attachmentDirectory, maintenance: store.maintenance,
        );
        _failed = false;
      });
    } catch (_) {
      if (owned()) setState(() => _failed = true);
    }
  }

  @override
  void didUpdateWidget(covariant LocalHtmlPreviewHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.store, widget.store) ||
        oldWidget.collection != widget.collection ||
        oldWidget.noteId != widget.noteId ||
        !identical(oldWidget.sourceIoScope, widget.sourceIoScope)) {
      _resources = null;
      _attachments = null;
      unawaited(_open());
    }
  }
  @override
  void dispose() {
    _epoch++;
    final preview = _previewOwner;
    final drive = _drive;
    unawaited(() async {
      try { await preview?.retireAndDrain(); }
      finally { drive?.dispose(); }
    }().catchError((Object _) {}));
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final collection = widget.collection;
    final noteId = widget.noteId;
    final source = widget.source;
    final current = widget.isCurrentScope;
    final epoch = _epoch;
    bool owned() => mounted && epoch == _epoch &&
        !store.maintenance.retired && (current?.call() ?? true);
    if (_failed || !owned()) {
      return Center(child: Text(widget.english
          ? 'Local resources unavailable.' : '本地资源暂不可用。'));
    }
    final repository = _resources;
    if (repository == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final attachments = _attachments;
    final baseline = widget.baselineFingerprint;
    final previewOwner = _previewOwner;
    final canBind = previewOwner != null && attachments != null && baseline != null &&
        RegExp(r'^[a-f0-9]{64}$').hasMatch(baseline);
    return LocalHtmlPreviewPanel(
      repository: repository, noteId: noteId, source: source,
      english: widget.english, isCurrentScope: owned,
      previewOwner: previewOwner,
      previewBuilder: !canBind ? null : (document) =>
          LocalHtmlAttachmentPreview(
            attachments: attachments,
            rawSource: source, document: document,
            scopeIdentity: jsonEncode([
              store.path, collection, noteId, 'html', baseline,
              document.fingerprint,
            ]),
            isCurrentScope: owned, previewOwner: previewOwner,
            english: widget.english,
          ),
    );
  }
}

class LocalHtmlPreviewPanel extends StatefulWidget {
  const LocalHtmlPreviewPanel({
    super.key,
    required this.repository,
    required this.noteId,
    required this.source,
    this.english = false,
    this.previewBuilder,
    this.pickFile,
    this.isCurrentScope,
    this.previewOwner,
  });
  final LocalHtmlResourcesRepository repository;
  final int noteId;
  final String source;
  final bool english;
  final Widget Function(LocalHtmlPreviewDocument)? previewBuilder;
  final Future<XFile?> Function()? pickFile;
  final bool Function()? isCurrentScope;
  final LocalHtmlPreviewOwner? previewOwner;
  @override
  State<LocalHtmlPreviewPanel> createState() => _LocalHtmlPreviewPanelState();
}

class _LocalHtmlPreviewPanelState extends State<LocalHtmlPreviewPanel> {
  LocalHtmlPreviewDocument? _document;
  Object? _failure;
  bool _loading = true;
  int _count = 0, _generation = 0, _revision = 0;
  String t(String zh, String en) => widget.english ? en : zh;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final repository = widget.repository;
    final noteId = widget.noteId;
    final source = widget.source;
    final current = widget.isCurrentScope;
    bool owned() => mounted && generation == _generation &&
        identical(widget.repository, repository) && widget.noteId == noteId &&
        widget.source == source && (current?.call() ?? true);
    setState(() {
      _loading = true;
      _failure = null;
    });
    try {
      if (!owned()) return;
      final previewOwner = widget.previewOwner;
      final bindings = previewOwner == null
          ? await repository.list(noteId)
          : await previewOwner.use(() => repository.list(noteId));
      if (!owned()) return;
      setState(() => _count = bindings.length);
      final document = previewOwner == null
          ? await repository.load(noteId, source)
          : await previewOwner.use(() => repository.load(noteId, source));
      if (owned()) {
        setState(() {
          _document = document;
          _revision++;
        });
      }
    } catch (error) {
      if (owned()) {
        setState(() => _failure = error);
      }
    } finally {
      if (owned()) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _resources() async {
    final repository = widget.repository;
    final noteId = widget.noteId;
    final current = widget.isCurrentScope;
    final owner = widget.previewOwner;
    bool owned() => mounted && identical(widget.repository, repository) &&
        widget.noteId == noteId && (current?.call() ?? true) &&
        (owner?.current ?? true);
    if (!owned()) return;
    final applied = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => LocalHtmlResourceSheet(
        repository: repository,
        noteId: noteId,
        english: widget.english,
        pickFile: widget.pickFile,
        isCurrentScope: owned,
        previewOwner: owner,
      ),
    );
    if (applied == true && owned()) await _load();
  }

  @override
  void didUpdateWidget(covariant LocalHtmlPreviewPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source ||
        oldWidget.noteId != widget.noteId ||
        !identical(oldWidget.repository, widget.repository)) {
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Card(
        child: ListTile(
          dense: true,
          leading: const Icon(Icons.folder_outlined),
          title: Text(t('本地交互预览', 'Local interactive preview')),
          subtitle: Text(t('使用此笔记的本地资源', 'Uses this note’s local resources')),
          onTap: _resources,
          trailing: const Icon(Icons.chevron_right),
        ),
      ),
      const SizedBox(height: 8),
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _failure != null || _document == null
            ? Center(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      t(
                        _failure is HtmlResourceUnavailable
                            ? '本地附件已丢失或更新，请检查资源并重新应用。'
                            : '交互预览读取失败，请检查资源或重试。',
                        _failure is HtmlResourceUnavailable
                            ? 'A local attachment is missing or changed. Review and apply the resources.'
                            : 'Unable to read the interactive preview. Review resources or retry.',
                      ),
                    ),
                  ),
                ),
              )
            : ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: KeyedSubtree(
                  key: ValueKey(_revision),
                  child:
                      widget.previewBuilder?.call(_document!) ??
                      LocalHtmlBrowserPreview(
                        document: _document!,
                        english: widget.english,
                      ),
                ),
              ),
      ),
      const SizedBox(height: 8),
      Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            children: [
              TextButton.icon(
                key: const ValueKey('local-html-resources'),
                onPressed: _resources,
                icon: const Icon(Icons.attach_file),
                label: Text('${t('本地资源', 'Local resources')} $_count'),
              ),
              TextButton.icon(
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh),
                label: Text(t('重新加载', 'Reload')),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

class LocalHtmlResourceSheet extends StatefulWidget {
  const LocalHtmlResourceSheet({
    super.key,
    required this.repository,
    required this.noteId,
    this.english = false,
    this.pickFile,
    this.isCurrentScope,
    this.previewOwner,
  });
  final LocalHtmlResourcesRepository repository;
  final int noteId;
  final bool english;
  final Future<XFile?> Function()? pickFile;
  final bool Function()? isCurrentScope;
  final LocalHtmlPreviewOwner? previewOwner;
  @override
  State<LocalHtmlResourceSheet> createState() => _LocalHtmlResourceSheetState();
}

class _LocalHtmlResourceSheetState extends State<LocalHtmlResourceSheet> {
  late final LocalHtmlResourcesRepository _repository = widget.repository;
  late final int _noteId = widget.noteId;
  late final LocalHtmlPreviewOwner? _owner = widget.previewOwner;
  bool get _current => mounted && identical(widget.repository, _repository) &&
      widget.noteId == _noteId && (widget.isCurrentScope?.call() ?? true) &&
      (_owner?.current ?? true);
  Future<T> _work<T>(Future<T> Function() operation) {
    if (!_current) throw StateError('Local HTML resource scope retired');
    final owner = _owner;
    return owner == null ? Future<T>.sync(operation) : owner.use(operation);
  }
  List<HtmlResourceBinding> _baseline = [];
  final _known = <String, DriveNode?>{};
  final _selected = <String>{};
  final _changed = <String>{};
  bool _loading = true, _busy = false;
  String? _error;
  String t(String zh, String en) => widget.english ? en : zh;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final values = await _work(() => _repository.list(_noteId));
      if (!_current) return;
      _baseline = values.map((r) => r.binding).toList();
      _known.clear();
      _selected.clear();
      _changed.clear();
      for (final value in values) {
        _known[value.binding.path] = value.node;
        _selected.add(value.binding.path);
        if (value.changed) _changed.add(value.binding.path);
      }
    } catch (_) {
      if (_current) {
        _error = t('无法读取资源设置，请重试。', 'Unable to read resource settings. Retry.');
      }
    } finally {
      if (_current) setState(() => _loading = false);
    }
  }

  Future<String?> _path(String initial) => showDialog<String>(
    context: context,
    builder: (_) => _ResourcePathDialog(
      initial: initial,
      existing: _selected.toSet(),
      english: widget.english,
    ),
  );

  Future<void> _add() async {
    if (!_current || _busy) return;
    final type = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.upload_file),
            title: Text(t('从本机文件添加', 'Add from device files')),
            onTap: () => Navigator.pop(context, 'import'),
          ),
          ListTile(
            leading: const Icon(Icons.folder_open),
            title: Text(t('从本地文件库选择', 'Choose from local files')),
            onTap: () => Navigator.pop(context, 'existing'),
          ),
        ],
      ),
    );
    if (!mounted || !_current || type == null) return;
    DriveNode? node;
    String? initial;
    if (type == 'existing') {
      node = await Navigator.of(context).push<DriveNode>(
        MaterialPageRoute(
          builder: (_) => _ResourceFilePicker(
            repository: _repository,
            english: widget.english,
            isCurrentScope: () => _current,
            previewOwner: _owner,
          ),
        ),
      );
      initial = node?.name;
    } else {
      setState(() {
        _busy = true;
        _error = null;
      });
      try {
        final file = await (widget.pickFile?.call() ?? openFile());
        if (file != null && _current) {
          node = await _work(() => _repository.importFile(_noteId, file));
          initial = attachmentName(file.name);
        }
      } catch (_) {
        if (_current) {
          _error = t(
            '无法添加附件，请检查文件类型及 5 MB 限制。',
            'Unable to add attachment. Check its type and the 5 MB limit.',
          );
        }
      } finally {
        if (_current) setState(() => _busy = false);
      }
    }
    if (!_current || node == null || initial == null) return;
    final path = await _path(initial == 'index.html' ? 'page.html' : initial);
    if (path != null && _current) {
      setState(() {
        _known[path] = node;
        _selected.add(path);
      });
    }
  }

  Future<void> _apply() async {
    if (!_current || _busy || _loading) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_selected.any((path) => _known[path] == null)) {
        throw const HtmlResourceUnavailable('');
      }
      await _work(() => _repository.replace(_noteId, [
        for (final path in _selected)
          HtmlResourceChoice(path: path, node: _known[path]!),
      ], baseline: _baseline));
      if (mounted && _current) Navigator.pop(context, true);
    } catch (error) {
      if (_current) {
        _error = error is HtmlResourceConflict
            ? t(
                '资源设置已变化，请重新读取后选择。',
                'Resource settings changed. Reload before selecting again.',
              )
            : t(
                '无法应用，请移除丢失的附件并检查路径、格式及大小。',
                'Unable to apply. Remove missing attachments and check paths, types and sizes.',
              );
      }
    } finally {
      if (_current) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .82,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              t('本地资源', 'Local resources'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(
              t(
                '选择这篇页面可以使用的附件。新添加的文件会保留在本地文件库中。',
                'Choose attachments this page can use. Newly added files stay in your local file library.',
              ),
            ),
            if (_error != null) ...[
              Text(_error!),
              TextButton(
                onPressed: _busy ? null : _load,
                child: Text(t('重新读取', 'Reload settings')),
              ),
            ],
            if (_loading || _busy) const LinearProgressIndicator(),
            Expanded(
              child: ListView(
                children: [
                  for (final path in _known.keys)
                    CheckboxListTile(
                      key: ValueKey('html-resource-check-$path'),
                      value: _selected.contains(path),
                      title: Text(path),
                      subtitle: Text(
                        _known[path] == null
                            ? t(
                                '文件已删除，可取消选择',
                                'File deleted; deselect to remove',
                              )
                            : _changed.contains(path)
                            ? t(
                                '文件已更新，应用后使用新版',
                                'File changed; apply to use its new version',
                              )
                            : '${_known[path]!.size} B',
                      ),
                      onChanged: _busy || _loading
                          ? null
                          : (yes) => setState(() {
                              if (yes == true) {
                                _selected.add(path);
                              } else {
                                _selected.remove(path);
                              }
                            }),
                    ),
                  ListTile(
                    key: const ValueKey('html-resource-add'),
                    leading: const Icon(Icons.add),
                    title: Text(t('添加附件', 'Add attachment')),
                    trailing: const Icon(Icons.chevron_right),
                    enabled: !_busy && !_loading,
                    onTap: _add,
                  ),
                ],
              ),
            ),
            FilledButton(
              key: const ValueKey('html-resource-apply'),
              onPressed: _busy || _loading ? null : _apply,
              child: Text(t('应用并重新加载', 'Apply and reload')),
            ),
            OutlinedButton(
              onPressed: _busy ? null : () => Navigator.pop(context, false),
              child: Text(t('取消', 'Cancel')),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ResourceFilePicker extends StatefulWidget {
  const _ResourceFilePicker({
    required this.repository, required this.english,
    required this.isCurrentScope, required this.previewOwner,
  });
  final LocalHtmlResourcesRepository repository;
  final bool english;
  final bool Function() isCurrentScope;
  final LocalHtmlPreviewOwner? previewOwner;
  @override
  State<_ResourceFilePicker> createState() => _ResourceFilePickerState();
}

class _ResourceFilePickerState extends State<_ResourceFilePicker> {
  late final LocalHtmlResourcesRepository _repository = widget.repository;
  late final LocalHtmlPreviewOwner? _owner = widget.previewOwner;
  int _request = 0;
  bool get _current => mounted && identical(widget.repository, _repository) &&
      identical(widget.previewOwner, _owner) &&
      widget.isCurrentScope() && (_owner?.current ?? true);
  final _search = TextEditingController();
  List<DriveNode> _files = [];
  bool _busy = true, _failed = false, _next = false;
  int _page = 1;
  String _query = '';
  String t(String zh, String en) => widget.english ? en : zh;
  @override
  void initState() {
    super.initState();
    unawaited(_load(1));
  }

  Future<void> _load(int page) async {
    if (!_current) return;
    final request = ++_request;
    final query = _query;
    bool owned() => _current && request == _request;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      final owner = _owner;
      Future<List<DriveNode>> read() => _repository.available(
        keyword: query, page: page);
      final files = owner == null ? await read() : await owner.use(read);
      if (owned()) {
        setState(() {
          _files = files;
          _page = page;
          _next = files.length == 50;
        });
      }
    } catch (_) {
      if (owned()) setState(() => _failed = true);
    } finally {
      if (owned()) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _request++;
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(t('选择本地附件', 'Choose local attachment'))),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _search,
          enabled: !_busy,
          decoration: InputDecoration(labelText: t('搜索文件', 'Search files')),
          onSubmitted: (_) {
            _query = _search.text;
            _load(1);
          },
        ),
        TextButton(
          onPressed: _busy
              ? null
              : () {
                  _query = _search.text;
                  _load(1);
                },
          child: Text(t('搜索', 'Search')),
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_failed) Text(t('读取失败，请重试。', 'Unable to read files. Retry.')),
        if (_failed)
          TextButton(
            onPressed: _busy ? null : () => _load(_page),
            child: Text(t('重试', 'Retry')),
          ),
        if (!_busy && !_failed && _files.isEmpty)
          Text(t('未找到附件。', 'No attachments found.')),
        for (final file in _files)
          ListTile(
            leading: const Icon(Icons.insert_drive_file_outlined),
            title: Text(file.name),
            subtitle: Text(
              widget.repository.supports(file)
                  ? '${file.path}\n${file.size} B'
                  : t('格式不支持或超过 5 MB', 'Unsupported format or exceeds 5 MB'),
            ),
            isThreeLine: widget.repository.supports(file),
            enabled: _current && !_busy && !_failed && _repository.supports(file),
            onTap: () { if (_current) Navigator.pop(context, file); },
          ),
        Wrap(
          spacing: 12,
          children: [
            if (_page > 1)
              OutlinedButton(
                onPressed: _busy ? null : () => _load(_page - 1),
                child: Text(t('上一页', 'Previous')),
              ),
            if (_next && _page < 1000)
              OutlinedButton(
                onPressed: _busy ? null : () => _load(_page + 1),
                child: Text(t('下一页', 'Next')),
              ),
          ],
        ),
      ],
    ),
  );
}

class _ResourcePathDialog extends StatefulWidget {
  const _ResourcePathDialog({
    required this.initial,
    required this.existing,
    required this.english,
  });
  final String initial;
  final Set<String> existing;
  final bool english;
  @override
  State<_ResourcePathDialog> createState() => _ResourcePathDialogState();
}

class _ResourcePathDialogState extends State<_ResourcePathDialog> {
  late final TextEditingController _field;
  String t(String zh, String en) => widget.english ? en : zh;
  @override
  void initState() {
    super.initState();
    _field = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  bool get valid =>
      validLocalHtmlResourcePath(_field.text) &&
      _field.text != 'index.html' &&
      !widget.existing.contains(_field.text);
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(t('网页内的附件路径', 'Attachment path in the page')),
    content: TextField(
      controller: _field,
      autofocus: true,
      onChanged: (_) => setState(() {}),
      onSubmitted: (_) {
        if (valid) Navigator.pop(context, _field.text);
      },
      decoration: InputDecoration(
        labelText: t('相对路径', 'Relative path'),
        helperText: t(
          '例如 cover.png 或 styles/theme.css',
          'For example cover.png or styles/theme.css',
        ),
        errorText: valid
            ? null
            : t('路径无效、重复或已保留。', 'Invalid, duplicate or reserved path.'),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(t('取消', 'Cancel')),
      ),
      FilledButton(
        onPressed: valid ? () => Navigator.pop(context, _field.text) : null,
        child: Text(t('添加', 'Add')),
      ),
    ],
  );
}
