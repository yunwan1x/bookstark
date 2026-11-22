import '../speech/local_speech_provider_page.dart';
import '../../core/document_excerpt_request.dart';
import '../../core/document_excerpt_origin.dart';
import '../../core/complex_reading_protocol.dart';
import '../../core/complex_reading_position_vault.dart';
import '../../core/document_route_adapter.dart';
import '../document_reading_surface.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import '../../core/attachments.dart';
import '../../core/books_repository.dart';
import '../../core/documents_repository.dart';
import '../../core/document_editor_repository.dart';
import '../../core/draft_vault.dart';
import '../../core/notes_repository.dart';
import '../../core/document_excerpt.dart';
import '../../core/reading_position_vault.dart';
import '../../widgets/bookstark_markdown.dart';
import '../notes/notes_page.dart';

class DocumentReaderPage extends StatefulWidget {
  const DocumentReaderPage({
    super.key,
    required this.bookId,
    required this.documentId,
    required this.books,
    required this.documents,
    this.attachments,
    this.drafts,
    this.english = false,
    this.onExcerpt,
    this.onExcerptRequest,
    this.server,
    this.positions,
    this.onSpeak,
    this.onSpeakSelection,
    this.onShareSettings,
    this.boundedReader,
    this.readingFingerprint,
    this.isCurrentScope,
    this.onEditComplex,
  });
  final Future<void> Function(BuildContext, DocumentItem)? onEditComplex;
  final Future<void> Function(BuildContext, DocumentExcerptRequest)?
  onExcerptRequest;
  final Future<void> Function(LocalSpeechSelection, String, String)?
  onSpeakSelection;
  final int bookId, documentId;
  final BoundedDocumentsReader? boundedReader;
  final Future<String?> Function(TypedDocumentRead read)? readingFingerprint;
  final bool Function()? isCurrentScope;
  final Future<void> Function(DocumentItem)? onShareSettings;
  final BooksRepository books;
  final DocumentsRepository documents;
  final AttachmentRepository? attachments;
  final DraftVault? drafts;
  final bool english;
  final Uri? server;
  final ReadingPositionVault? positions;
  final Future<void> Function(BuildContext, Note, int documentId)? onExcerpt;
  final Future<void> Function(String markdown, String title, String context)?
  onSpeak;
  @override
  State<DocumentReaderPage> createState() => _DocumentReaderPageState();
}

class _DocumentReaderPageState extends State<DocumentReaderPage>
    with WidgetsBindingObserver {
  final _scroll = ScrollController();
  DocumentItem? _item;
  PreparedDocumentRoute? _prepared;
  ComplexReadingIdentity? _readingIdentity;
  ComplexReadingAnchor? _readingAnchor;
  ComplexReadingIdentity? _failedComplexIdentity;
  bool get _canExcerpt =>
      widget.onExcerpt != null || widget.onExcerptRequest != null;
  bool get _current => mounted && (widget.isCurrentScope?.call() ?? true);
  String _path = '';
  String _bookIdentify = '';
  ReadingPosition? _resume;
  final _pendingPositions = <int, ReadingPosition>{};
  Timer? _positionTimer;
  bool _positionDirty = false, _jumping = false;
  String? _positionError;
  String? _positionReadError;
  int? _failedPositionId;
  String? _error;
  bool _loading = true, _editing = false, _sharing = false;
  int _generation = 0;
  late int _requestedId = widget.documentId;
  String t(String zh, String en) => widget.english ? en : zh;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scroll.addListener(_scrolled);
    _load(widget.documentId);
  }

  @override
  void didUpdateWidget(covariant DocumentReaderPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.documents, widget.documents) ||
        !identical(oldWidget.books, widget.books) ||
        oldWidget.bookId != widget.bookId ||
        oldWidget.documentId != widget.documentId) {
      _generation++;
      _positionTimer?.cancel();
      _pendingPositions.clear();
      _positionDirty = false;
      _item = null;
      _prepared = null;
      _resume = null;
      unawaited(_load(widget.documentId));
    }
  }

  void _scrolled() {
    if (!_current ||
        _loading ||
        _jumping ||
        _item == null ||
        _prepared?.mode != DocumentReadingMode.markdown) {
      return;
    }
    _positionDirty = true;
    if (_resume != null) setState(() => _resume = null);
    _positionTimer?.cancel();
    _positionTimer = Timer(
      const Duration(milliseconds: 600),
      () => _savePosition(),
    );
  }

  Future<bool> _savePosition({bool report = true}) async {
    _positionTimer?.cancel();
    final vault = widget.positions;
    if (vault == null) return true;
    final item = _item;
    if (_positionDirty &&
        item != null &&
        _scroll.hasClients &&
        _scroll.position.hasContentDimensions) {
      final extent = _scroll.position.maxScrollExtent;
      final fraction = extent <= 0
          ? 0.0
          : (_scroll.offset / extent).clamp(0.0, 1.0);
      _pendingPositions[item.id] = ReadingPosition(fraction, item.modifiedAt);
      _positionDirty = false;
    }
    try {
      for (final entry in Map.of(_pendingPositions).entries) {
        await vault.write(entry.key, entry.value);
        if (identical(_pendingPositions[entry.key], entry.value)) {
          _pendingPositions.remove(entry.key);
        }
      }
      if (mounted && report) setState(() => _positionError = null);
      return true;
    } catch (error) {
      if (mounted && report) setState(() => _positionError = error.toString());
      return false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      unawaited(_savePosition());
    }
  }

  void _resumeReading() {
    final position = _resume;
    if (position == null ||
        !_scroll.hasClients ||
        !_scroll.position.hasContentDimensions) {
      return;
    }
    _jumping = true;
    _scroll.jumpTo(_scroll.position.maxScrollExtent * position.fraction);
    _jumping = false;
    setState(() => _resume = null);
  }

  Future<void> _clearUnreadablePosition() async {
    final failedComplex = _failedComplexIdentity, positions = widget.positions;
    if (failedComplex != null && positions != null) {
      try {
        await ComplexReadingPositionVault(
          positions,
          isCurrent: () => _current,
        ).remove(failedComplex);
        if (_current) {
          setState(() {
            _failedComplexIdentity = null;
            _positionReadError = null;
          });
        }
      } catch (_) {
        if (_current) {
          setState(
            () => _positionReadError = t(
              '无法清除阅读位置，请重试。',
              'Unable to clear reading position. Retry.',
            ),
          );
        }
      }
      return;
    }
    final id = _failedPositionId;
    if (id == null) return;
    try {
      await widget.positions?.removeRecord(id);
      if (mounted) {
        setState(() {
          _positionReadError = null;
          _failedPositionId = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _positionReadError = error.toString());
    }
  }

  Future<void> _speakSelection(LocalSpeechSelection captured) async {
    final item = _item, prepared = _prepared, identity = _readingIdentity;
    final repository = widget.documents,
        fingerprint = widget.readingFingerprint;
    final BoundedDocumentsReader? bounded =
        widget.boundedReader ??
        (repository is BoundedDocumentsReader
            ? repository as BoundedDocumentsReader
            : null);
    final callback = widget.onSpeakSelection, generation = _generation;
    bool current() =>
        _current &&
        generation == _generation &&
        identical(_item, item) &&
        identical(_prepared, prepared) &&
        identical(widget.documents, repository) &&
        _readingIdentity?.same(identity!) == true &&
        captured.current;
    if (item == null ||
        prepared == null ||
        identity == null ||
        bounded == null ||
        fingerprint == null ||
        callback == null ||
        !current()) {
      return;
    }
    Future<bool> verify() async {
      try {
        if (!current() || !await captured.verifyFreshBinding() || !current()) {
          return false;
        }
        final fresh = await bounded.readBounded(
          item.id,
          bookId: item.bookId,
          maxMarkdownReadBytes: documentReadMaxBytes,
        );
        if (!current() ||
            fresh.item.id != identity.documentId ||
            fresh.item.bookId != identity.bookId ||
            fresh.item.type != item.type ||
            DocumentExcerptOrigin.digest(fresh.source) !=
                identity.sourceDigest) {
          return false;
        }
        final full = await fingerprint(fresh);
        return current() && full == identity.fullFingerprint;
      } catch (_) {
        return false;
      }
    }

    final selected = LocalSpeechSelection.captured(
      text: captured.text,
      bindingId: captured.bindingId,
      selectionKind: captured.selectionKind,
      isCurrentBinding: current,
      verifyFreshBinding: verify,
    );
    if (!await verify() || !current()) return;
    // Root receives no pretend full text for a complex source.
    await callback(selected, item.name, _path);
  }

  Future<void> _excerpt(String selected, {String? selectionKind}) async {
    final item = _item,
        action = widget.onExcerpt,
        typedAction = widget.onExcerptRequest;
    final prepared = _prepared, repository = widget.documents;
    final generation = _generation,
        fullFingerprint = _readingIdentity?.fullFingerprint;
    final fingerprintReader = widget.readingFingerprint;
    bool sourceCurrent() =>
        _current &&
        generation == _generation &&
        identical(_item, item) &&
        identical(widget.documents, repository);
    if (item == null || !_canExcerpt || _editing || !sourceCurrent()) return;
    setState(() => _editing = true);
    try {
      if (typedAction != null) {
        if (prepared == null) {
          throw StateError('Typed excerpt source unavailable');
        }
        final BoundedDocumentsReader? bounded =
            widget.boundedReader ??
            (repository is BoundedDocumentsReader
                ? repository as BoundedDocumentsReader
                : null);
        if (bounded == null) {
          throw StateError('Bounded excerpt source required');
        }
        final mode =
            selectionKind ??
            switch (item.type) {
              'spreadsheet' => 'cells',
              'drawing' => 'elements',
              'mindmap' => 'nodes',
              'presentation' => 'slide',
              _ => 'text',
            };
        final sourceDigest = DocumentExcerptOrigin.digest(prepared.source);
        final request = DocumentExcerptRequest.snapshot(
          bookId: widget.bookId,
          item: item,
          source: prepared.source,
          selected: selected,
          path: _path,
          bookIdentify: _bookIdentify,
          fullFingerprint: fullFingerprint,
          selectionKind: mode,
          server: widget.server,
          english: widget.english,
          isCurrentSource: sourceCurrent,
          verifyCurrentSource: () async {
            if (!sourceCurrent()) return false;
            final fresh = await bounded.readBounded(
              item.id,
              bookId: item.bookId,
              maxMarkdownReadBytes: documentReadMaxBytes,
            );
            if (!sourceCurrent() ||
                fresh.item.type != item.type ||
                DocumentExcerptOrigin.digest(fresh.source) != sourceDigest) {
              return false;
            }
            if (item.type != 'markdown') {
              if (fingerprintReader == null || fullFingerprint == null) {
                return false;
              }
              final freshFull = await fingerprintReader(fresh);
              if (!sourceCurrent() || freshFull != fullFingerprint) {
                return false;
              }
            }
            return true;
          },
        );
        if (!sourceCurrent()) return;
        await typedAction(context, request);
      } else {
        final note = documentExcerpt(
          quote: selected,
          name: item.name,
          path: _path,
          bookIdentify: _bookIdentify,
          documentId: item.id,
          server: widget.server,
          english: widget.english,
        );
        await action!(context, note, item.id);
      }
    } catch (_) {
      if (sourceCurrent()) {
        setState(
          () => _error = t(
            '摘录尚未打开，原文和草稿已保留。',
            'Excerpt did not open. Original and draft retained.',
          ),
        );
      }
    } finally {
      if (sourceCurrent()) setState(() => _editing = false);
    }
  }

  Future<void> _load(int id) async {
    final generation = ++_generation;
    final repository = widget.documents, books = widget.books;
    final vault = widget.positions;
    bool current() =>
        _current &&
        generation == _generation &&
        identical(widget.documents, repository) &&
        identical(widget.books, books);
    _requestedId = id;
    setState(() {
      _loading = true;
      _error = null;
      _positionReadError = null;
      _failedPositionId = null;
      _failedComplexIdentity = null;
    });
    try {
      await _savePosition();
      if (!current()) return;
      // Keep the last verified document until the new route is fully validated.
      final BoundedDocumentsReader? bounded =
          widget.boundedReader ??
          (repository is BoundedDocumentsReader
              ? repository as BoundedDocumentsReader
              : null);
      final read = bounded == null
          ? null
          : await bounded.readBounded(
              id,
              bookId: widget.bookId,
              maxMarkdownReadBytes: documentReadMaxBytes,
            );
      final item = read?.item ?? await repository.read(id);
      if (!current()) return;
      if (item.bookId != widget.bookId) {
        throw StateError(
          '导航文档不属于本书 / Navigation document belongs to another book',
        );
      }
      if (item.id != id) {
        throw StateError('Navigation document identity changed');
      }
      var prepared = read == null
          ? await const DocumentRouteAdapter().prepare(
              DocumentBodyMetadata.local(item),
              bookId: widget.bookId,
              documentId: id,
              canEdit: true,
              reviewedWriterAvailable:
                  item.type == 'markdown' || widget.onEditComplex != null,
            )
          : await const DocumentRouteAdapter().prepareRead(
              read,
              bookId: widget.bookId,
              documentId: id,
              canEdit: true,
              reviewedWriterAvailable:
                  item.type == 'markdown' || widget.onEditComplex != null,
            );
      if (!current()) return;
      ComplexReadingIdentity? readingIdentity;
      ComplexReadingAnchor? readingAnchor;
      if (read != null &&
          prepared.mode == DocumentReadingMode.complexWebView &&
          widget.readingFingerprint != null) {
        try {
          final full = await widget.readingFingerprint!(read);
          if (!current()) return;
          if (full != null) {
            readingIdentity = ComplexReadingIdentity(
              bookId: item.bookId,
              documentId: item.id,
              kind: prepared.document!.kind,
              fullFingerprint: full,
              sourceDigest: prepared.document!.digest,
            );
            readingIdentity.validate();
            final positions = widget.positions;
            if (positions != null) {
              try {
                readingAnchor = await ComplexReadingPositionVault(
                  positions,
                  isCurrent: current,
                ).read(readingIdentity);
              } catch (_) {
                if (!current()) return;
                _failedComplexIdentity = readingIdentity;
                _positionReadError = t(
                  '复杂文档位置无法读取，正文仍可阅读。',
                  'Complex reading position unavailable. Document remains readable.',
                );
              }
            }
            if (!current()) return;
          }
        } catch (_) {
          if (!current()) return;
          // Owned full-snapshot permission/API unavailable: preserve bounded
          // reading, but don't grant editor/anchor capability from its old body.
          readingIdentity = null;
          readingAnchor = null;
          prepared = PreparedDocumentRoute(
            item: prepared.item,
            mode: prepared.mode,
            source: prepared.source,
            document: prepared.document,
            editGate: DocumentEditGate.writerUnavailable,
          );
        }
      }
      if (item.bookId != widget.bookId) {
        throw StateError(
          '导航文档不属于本书 / Navigation document belongs to another book',
        );
      }
      final book = await books.read(widget.bookId);
      ReadingPosition? position;
      try {
        position = prepared.mode == DocumentReadingMode.complexWebView
            ? null
            : _pendingPositions[id] ?? await vault?.read(id);
      } catch (error) {
        if (current()) {
          setState(() {
            _positionReadError = error.toString();
            _failedPositionId = id;
          });
        }
      }
      final nodes = flattenDocuments(await repository.tree(widget.bookId));
      final byId = {for (final node in nodes) node.id: node};
      final parents = <String>[];
      var parent = item.parentId;
      final seen = <int>{item.id};
      while (parent != 0) {
        if (!seen.add(parent) || !byId.containsKey(parent)) {
          throw StateError('Invalid chapter path');
        }
        parents.insert(0, byId[parent]!.name);
        parent = byId[parent]!.parentId;
      }
      if (!current()) return;
      setState(() {
        _item = item;
        _prepared = prepared;
        _readingIdentity = readingIdentity;
        _readingAnchor = readingAnchor;
        _path = [book.name, ...parents].join(' / ');
        _bookIdentify = book.identify;
        _resume =
            prepared.mode != DocumentReadingMode.complexWebView &&
                position != null &&
                position.fraction > 0
            ? position
            : null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (current() && _scroll.hasClients && _scroll.position.hasPixels) {
          _jumping = true;
          _scroll.jumpTo(0);
          _jumping = false;
        }
      });
    } catch (error) {
      if (current()) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _edit() async {
    final item = _item;
    if (!_current ||
        item == null ||
        _editing ||
        _loading ||
        _prepared?.canEnterEditor == false ||
        (item.type != 'markdown' && widget.onEditComplex == null)) {
      return;
    }
    setState(() => _editing = true);
    try {
      if (item.type != 'markdown') {
        final callback = widget.onEditComplex!;
        await callback(context, item);
        if (mounted && identical(widget.onEditComplex, callback)) {
          await _load(item.id);
        }
        return;
      }
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => NoteEditorPage(
            repository: DocumentEditorRepository(
              widget.documents,
              widget.bookId,
              boundedReader:
                  widget.boundedReader ??
                  (widget.documents is BoundedDocumentsReader
                      ? widget.documents as BoundedDocumentsReader
                      : null),
              isCurrentScope: widget.isCurrentScope,
            ),
            note: Note(id: item.id, title: item.name, content: item.markdown),
            documentPath: _path,
            drafts: widget.drafts,
            attachments: widget.attachments,
            english: widget.english,
          ),
        ),
      );
      if (mounted) await _load(item.id);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _editing = false);
    }
  }

  Future<void> _share(Attachment attachment, [Uint8List? bytes]) async {
    if (_sharing || widget.attachments == null) return;
    setState(() => _sharing = true);
    try {
      await shareBookstarkAttachment(
        context,
        widget.attachments!,
        attachment,
        bytes: bytes,
      );
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _link(String text, String? href) => openBookstarkLink(
    context,
    text,
    href,
    repository: widget.attachments,
    english: widget.english,
    onShare: _share,
  );
  Future<void> _copy() async {
    final item = _item;
    if (item == null || item.type != 'markdown') return;
    await Clipboard.setData(ClipboardData(text: item.markdown));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(t('正文已复制', 'Content copied'))));
    }
  }

  Future<void> _speak() async {
    final item = _item, action = widget.onSpeak;
    if (item == null || action == null || _editing || _loading) return;
    setState(() => _editing = true);
    try {
      await action(item.markdown, item.name, _path);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _editing = false);
    }
  }

  @override
  void dispose() {
    _positionTimer?.cancel();
    unawaited(_savePosition(report: false));
    WidgetsBinding.instance.removeObserver(this);
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _openSharingSettings() async {
    final item = _item, callback = widget.onShareSettings;
    if (item == null || callback == null || _loading || _editing) {
      return;
    }
    setState(() => _editing = true);
    try {
      await callback(item);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              t('无法打开分享设置。', 'Sharing settings could not be opened.'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _editing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = _current ? _item : null;
    final blocked = _loading || _editing;
    return Scaffold(
      appBar: AppBar(
        title: Text(item?.name ?? t('文档阅读', 'Read document')),
        actions: [
          PopupMenuButton<String>(
            tooltip: t('阅读菜单', 'Reading menu'),
            enabled: !blocked,
            onSelected: (action) {
              if (action == 'speak') {
                _speak();
              } else if (action == 'sharing') {
                _openSharingSettings();
              } else if (action == 'copy') {
                _copy();
              } else {
                _load(_requestedId);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'refresh', child: Text(t('刷新', 'Refresh'))),
              if (item != null && widget.onShareSettings != null)
                PopupMenuItem(
                  value: 'sharing',
                  child: Text(t('分享设置', 'Sharing settings')),
                ),
              if (item?.type == 'markdown')
                PopupMenuItem(
                  value: 'copy',
                  child: Text(t('复制全文', 'Copy content')),
                ),
              if (item?.type == 'markdown' && widget.onSpeak != null)
                PopupMenuItem(
                  value: 'speak',
                  child: Text(t('朗读全文', 'Read aloud')),
                ),
            ],
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Material(
          color: Theme.of(context).colorScheme.surface,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  onPressed: blocked || item == null || item.previousId == 0
                      ? null
                      : () => _load(item.previousId),
                  icon: const Icon(Icons.chevron_left),
                  label: Text(t('上一篇', 'Previous')),
                ),
                TextButton.icon(
                  onPressed:
                      blocked ||
                          !_current ||
                          item == null ||
                          _prepared?.canEnterEditor == false ||
                          (item.type != 'markdown' &&
                              widget.onEditComplex == null)
                      ? null
                      : _edit,
                  icon: const Icon(Icons.edit_outlined),
                  label: Text(t('编辑', 'Edit')),
                ),
                TextButton.icon(
                  onPressed: blocked || item == null || item.nextId == 0
                      ? null
                      : () => _load(item.nextId),
                  icon: const Icon(Icons.chevron_right),
                  label: Text(t('下一篇', 'Next')),
                ),
              ],
            ),
          ),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, viewport) => RefreshIndicator(
          onRefresh: () => _load(_requestedId),
          child: ListView(
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              if (_resume != null)
                TextButton.icon(
                  onPressed: _loading ? null : _resumeReading,
                  icon: const Icon(Icons.bookmark_outline),
                  label: Text(t('继续上次阅读', 'Resume reading')),
                ),
              if (_positionError != null) ...[
                Text(
                  '${t('阅读位置未保存', 'Reading position unavailable')}: $_positionError',
                ),
                TextButton(
                  onPressed: () => _savePosition(),
                  child: Text(t('重试保存位置', 'Retry saving position')),
                ),
              ],
              if (_positionReadError != null) ...[
                Text(
                  '${t('无法读取上次阅读位置', 'Cannot read the previous reading position')}: $_positionReadError',
                ),
                TextButton(
                  onPressed: _clearUnreadablePosition,
                  child: Text(t('清除损坏位置', 'Clear unreadable position')),
                ),
              ],
              if (_loading || _editing || _sharing)
                const LinearProgressIndicator(),
              if (_error != null) ...[
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                TextButton(
                  onPressed: () => _load(_requestedId),
                  child: Text(t('重试', 'Retry')),
                ),
              ],
              if (item != null) ...[
                Text(_path, style: Theme.of(context).textTheme.titleSmall),
                if (item.modifiedAt.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      t('更新于 ${item.modifiedAt}', 'Updated ${item.modifiedAt}'),
                    ),
                  ),
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child:
                        _prepared != null &&
                            _prepared!.mode != DocumentReadingMode.markdown
                        ? SizedBox(
                            height: viewport.maxHeight * .72,
                            child: DocumentReadingSurface(
                              key: ValueKey((
                                item.bookId,
                                item.id,
                                item.modifiedAt,
                              )),
                              route: _prepared!,
                              english: widget.english,
                              readingIdentity: _readingIdentity,
                              initialReadingAnchor: _readingAnchor,
                              onSpeakSelection: widget.onSpeakSelection == null
                                  ? null
                                  : _speakSelection,
                              onExcerptSelectedText: !_canExcerpt
                                  ? null
                                  : (actual, text) async {
                                      if (!_current || actual.id != _item?.id) {
                                        throw StateError('Reader retired');
                                      }
                                      await _excerpt(text);
                                    },
                              onReadingAnchor: widget.positions == null
                                  ? null
                                  : (identity, anchor) async {
                                      if (!_current ||
                                          _readingIdentity?.same(identity) !=
                                              true) {
                                        throw StateError('Reader retired');
                                      }
                                      await ComplexReadingPositionVault(
                                        widget.positions!,
                                        isCurrent: () =>
                                            _current &&
                                            _readingIdentity?.same(identity) ==
                                                true,
                                      ).write(identity, anchor);
                                      if (_current) {
                                        setState(() => _readingAnchor = anchor);
                                      }
                                    },
                              initialFraction:
                                  _resume?.modifiedAt == item.modifiedAt
                                  ? _resume!.fraction
                                  : 0,
                              markdownBody: (source) => BookstarkMarkdown(
                                data: source,
                                attachments: widget.attachments,
                                english: widget.english,
                                onExcerpt: !_canExcerpt ? null : _excerpt,
                                onLink: _link,
                                onShare: (attachment, bytes) =>
                                    _share(attachment, bytes),
                              ),
                              onPartPosition: (actual, fraction) async {
                                if (!_current || _item?.id != actual.id) {
                                  throw StateError('Reader scope retired');
                                }
                                _pendingPositions[actual.id] = ReadingPosition(
                                  fraction,
                                  actual.modifiedAt,
                                );
                                if (!await _savePosition()) {
                                  throw StateError(
                                    'Reading position not saved',
                                  );
                                }
                              },
                              onExcerptCurrentPart: !_canExcerpt
                                  ? null
                                  : (actual, text) async {
                                      if (!_current || _item?.id != actual.id) {
                                        throw StateError(
                                          'Reader scope retired',
                                        );
                                      }
                                      await _excerpt(
                                        text,
                                        selectionKind: 'part',
                                      );
                                    },
                            ),
                          )
                        : item.markdown.isEmpty
                        ? Text(t('空文档', 'Empty document'))
                        : BookstarkMarkdown(
                            onExcerpt: !_canExcerpt ? null : _excerpt,
                            data: item.markdown,
                            attachments: widget.attachments,
                            english: widget.english,
                            onLink: _link,
                            onShare: (attachment, bytes) =>
                                _share(attachment, bytes),
                          ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
