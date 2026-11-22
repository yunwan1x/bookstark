import '../../core/local_article_creation_source_io.dart';
import '../../core/native_complex_source_io.dart';
import 'complex_source_io_dialogs.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/complex_editor_document.dart';
import '../../core/complex_editor_transport.dart';
import '../../core/local_article_creation_controller.dart';
import '../../core/local_complex_notes_repository.dart';
import '../../core/owned_preview_controller.dart';
import 'article_metadata_dialog.dart';
import 'complex_editor_browser.dart';
import 'local_article_creation_source_coordinator.dart';
import 'local_article_creation_source_surface.dart';

typedef ArticleCreationReviewBuilder =
    Widget Function(
      BuildContext context, {
      required Key key,
      required ComplexEditorDocument document,
      required String title,
      required bool english,
      required OwnedPreviewController retirementController,
      required Future<void> Function(ComplexEditorTransport) onReady,
      required Future<void> Function() onReloadRequested,
    });
Widget defaultArticleCreationReview(
  BuildContext context, {
  required Key key,
  required ComplexEditorDocument document,
  required String title,
  required bool english,
  required OwnedPreviewController retirementController,
  required Future<void> Function(ComplexEditorTransport) onReady,
  required Future<void> Function() onReloadRequested,
}) => ComplexEditorBrowser(
  key: key,
  document: document,
  title: title,
  english: english,
  readOnly: true,
  retirementController: retirementController,
  onReady: onReady,
  onReloadRequested: onReloadRequested,
);

class LocalArticleCreatePage extends StatefulWidget {
  const LocalArticleCreatePage({
    super.key,
    required this.controller,
    this.english = false,
    this.onDisposed,
    this.sourceIoScope,
    this.sourceBuilder = defaultArticleCreationSurface,
    this.reviewBuilder = defaultArticleCreationReview,
  });
  final ComplexSourceIoScope? sourceIoScope;
  final LocalArticleCreationController controller;
  final bool english;
  final VoidCallback? onDisposed;
  final ArticleCreationSurfaceBuilder sourceBuilder;
  final ArticleCreationReviewBuilder reviewBuilder;
  @override
  State<LocalArticleCreatePage> createState() => _LocalArticleCreatePageState();
}

class _LocalArticleCreatePageState extends State<LocalArticleCreatePage>
    with WidgetsBindingObserver {
  static const purple = Color(0xff6530ad), lavender = Color(0xfff1e8fc);
  LocalArticleCreationController get c => widget.controller;
  late final LocalArticleCreationSourceCoordinator _source;
  late ComplexEditorDocument _document;
  OwnedPreviewController _lease = OwnedPreviewController();
  late bool _renderEditing;
  late String _token;
  int _mount = 0;
  bool _waitingUser = false;
  bool _ioChoosing = false, _ioBusy = false, _ioPicker = false;
  LocalArticleCreationSourceIo? _io;
  bool _work = false,
      _metadata = false,
      _leaving = false,
      _allowPop = false,
      _reviewReady = false;
  Future<void>? _surfaceJob;
  Timer? _timer;
  String? _notice;
  String t(String zh, String en) => widget.english ? en : zh;
  bool get _editing => c.phase == LocalArticleCreationPhase.editing;
  ComplexEditorDocument get _visibleDocument =>
      c.phase == LocalArticleCreationPhase.review && c.observed != null
      ? c.observed!.document
      : c.phase == LocalArticleCreationPhase.cleanup && c.created != null
      ? c.created!.document
      : c.draft.document;
  String get _visibleTitle =>
      c.phase == LocalArticleCreationPhase.review && c.observed != null
      ? c.observed!.title
      : c.created?.title ?? c.draft.title;
  List<String> get _visibleLabels =>
      c.phase == LocalArticleCreationPhase.review && c.observed != null
      ? c.observed!.labels
      : c.created?.labels ?? c.draft.labels;
  String get _wantedToken =>
      _editing ? 'edit' : 'view:${_visibleDocument.digest}';
  bool get _blocked =>
      _work ||
      _ioBusy ||
      _ioChoosing ||
      c.busy ||
      _metadata ||
      _leaving ||
      _surfaceJob != null;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _renderEditing = _editing;
    _document = _visibleDocument;
    _token = _wantedToken;
    _source = LocalArticleCreationSourceCoordinator(
      freezeEdit: (body) => ComplexNoteEdit(
        title: c.draft.title,
        document: ComplexEditorDocument.parse(ComplexEditorKind.markdown, body),
        labels: c.draft.labels,
      ),
      applyCapturedEdit: (edit) {
        final old = c.draft;
        if (old.title != edit.title ||
            !old.document.same(edit.document) ||
            old.labels.length != edit.labels.length ||
            !old.labels.asMap().entries.every(
              (e) => e.value == edit.labels[e.key],
            )) {
          c.edit(edit);
        }
      },
      flushCreationJournal: c.flush,
      create: c.save,
      creationStillEditable: () => c.canEdit,
      pendingOrUnknown: () => !{
        LocalArticleCreationPhase.editing,
        LocalArticleCreationPhase.finished,
      }.contains(c.phase),
    );
    c.addListener(_updated);
  }

  Future<void> _sourceFiles() async {
    final scope = widget.sourceIoScope, controller = c;
    if (scope == null || _blocked || !controller.canEdit || !_source.ready) {
      return;
    }
    _ioChoosing = true;
    setState(() {});
    ComplexSourceIoAction? action;
    try {
      action = await showComplexSourceIoSheet(
        context,
        format: 'Markdown (.md)',
        english: widget.english,
      );
    } finally {
      _ioChoosing = false;
      if (mounted) setState(() {});
    }
    if (!mounted ||
        action == null ||
        !identical(c, controller) ||
        !controller.canEdit ||
        !_source.ready) {
      return;
    }
    try {
      scope.guard();
    } catch (_) {
      return;
    }
    _timer?.cancel();
    _ioBusy = true;
    setState(() {});
    LocalArticleCreationSourceIo? job;
    var failed = false;
    try {
      job = LocalArticleCreationSourceIo(
        controller: controller,
        owner: scope,
        isCurrent: () =>
            mounted &&
            !_leaving &&
            identical(c, controller) &&
            identical(widget.sourceIoScope, scope),
        checkpoint: _source.prepareLeave,
        prepareNative: () async {
          final transport = _source.transport;
          if (transport == null) throw StateError('Article source unavailable');
          final grant = await transport.sourceIoIdentity();
          return NativeComplexSourceIo(
            owner: scope,
            lease: grant['lease'] as String,
            generation: grant['generation'] as int,
            allowMarkdown: true,
            onPickerVisibility: (v) {
              _ioPicker = v;
            },
          );
        },
        retireSurface: () async {
          await _lease.retire();
          await _source.drain();
          _source.invalidate();
        },
        remount: _remount,
      );
      _io = job;
      await job.run(
        importing: action == ComplexSourceIoAction.importSource,
        confirm: (file) =>
            confirmComplexSourceImport(context, file, english: widget.english),
      );
    } catch (_) {
      failed = true;
    } finally {
      _io = null;
      job?.retire();
      _ioPicker = false;
      _ioBusy = false;
      if (mounted) {
        setState(
          () => _notice = failed
              ? t(
                  '源文件操作未完成；草稿保留，没有创建文章。',
                  'Source operation incomplete. Draft retained; article was not created.',
                )
              : job?.completed == true
              ? action == ComplexSourceIoAction.importSource
                    ? t(
                        '源文件已持久保存为草稿，仍需明确创建。',
                        'Source durably imported as draft. Explicit Create is still required.',
                      )
                    : t(
                        '源文件已写全并关闭，未读回目标；文章未创建。',
                        'Source fully transferred and closed; destination not read back. Article was not created.',
                      )
              : t('已取消，原草稿保留。', 'Cancelled. Original draft retained.'),
        );
        if (_source.ready && controller.canEdit) await _source.unlock();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && !_ioPicker) _io?.retire();
  }

  void _updated() {
    if (!mounted) return;
    if (c.phase == LocalArticleCreationPhase.finished) {
      if (!_work) unawaited(_closeAndPop());
    } else if (_token != _wantedToken) {
      unawaited(_remount());
    }
    setState(() {});
  }

  Future<void> _remount() {
    final pending = _surfaceJob;
    if (pending != null) return pending;
    final work = _remountNow();
    _surfaceJob = work;
    return work.whenComplete(() {
      if (identical(_surfaceJob, work)) _surfaceJob = null;
      if (mounted) setState(() {});
    });
  }

  Future<void> _remountNow() async {
    _timer?.cancel();
    try {
      await _lease.retire();
      await _source.drain();
      _source.invalidate();
      if (!mounted || _leaving) return;
      _lease.dispose();
      _lease = OwnedPreviewController();
      setState(() {
        _mount++;
        _renderEditing = _editing;
        _document = _visibleDocument;
        _token = _wantedToken;
        _reviewReady = false;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _notice = t(
            '旧页面尚未关闭，请重试。',
            'The previous page has not closed. Retry.',
          ),
        );
      }
    }
  }

  void _state(ComplexEditorState state) {
    if (!mounted ||
        !state.dirty ||
        state.inputLocked ||
        _blocked ||
        !c.canEdit ||
        state.revision == _source.lastCheckpointRevision) {
      return;
    }
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 650), () async {
      final ok = await _source.checkpoint();
      if (mounted && !ok) {
        setState(
          () => _notice = t(
            '草稿尚未确认写入，请保留当前页面。',
            'Draft durability is unconfirmed. Keep this page open.',
          ),
        );
      }
    });
  }

  Future<void> _metadataDialog() async {
    if (_blocked || !c.canEdit || !_source.ready) return;
    _metadata = true;
    _timer?.cancel();
    setState(() {});
    try {
      if (!await _source.prepareLeave() || !mounted || !c.canEdit) {
        throw StateError('Article checkpoint unavailable');
      }
      final result = await showDialog<ArticleMetadata>(
        context: context,
        builder: (_) => ArticleMetadataDialog(
          title: c.draft.title,
          labels: c.draft.labels,
          document: c.draft.document,
          english: widget.english,
        ),
      );
      if (!mounted || !c.canEdit || result == null) return;
      c.edit(
        ComplexNoteEdit(
          title: result.title,
          document: c.draft.document,
          labels: result.labels,
        ),
      );
      if (!await c.flush()) throw StateError('Metadata durability unavailable');
      if (mounted) setState(() => _notice = null);
    } catch (_) {
      if (mounted) {
        setState(
          () => _notice = t(
            '文章信息或草稿未确认写入，请重试。',
            'Article information or draft durability is unconfirmed. Retry.',
          ),
        );
      }
    } finally {
      if (mounted && c.canEdit) await _source.unlock();
      _metadata = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _create() async {
    if (_blocked || !c.canEdit || !_source.ready) return;
    _work = true;
    _timer?.cancel();
    setState(() {});
    try {
      final ok = await _source.submit();
      if (mounted && (!ok || c.failure != null) && _editing) {
        setState(
          () => _notice = t(
            '请检查标题是否为空、重复或过长，然后重试。',
            'Check that the title is nonempty, unique and within the size limit.',
          ),
        );
      }
    } finally {
      _waitingUser = false;
      _work = false;
      if (mounted) setState(() {});
    }
    if (!mounted) return;
    if (c.phase == LocalArticleCreationPhase.finished) {
      await _closeAndPop();
    } else if (_lease.retired || _token != _wantedToken) {
      await _remount();
    }
  }

  Future<void> _action(Future<void> Function() action) async {
    if (_blocked) return;
    _work = true;
    _timer?.cancel();
    setState(() {});
    try {
      await _lease.retire();
      if (!mounted) return;
      await action();
    } catch (_) {
      if (mounted) {
        setState(
          () => _notice = t(
            '状态已变化，请重新核对。草稿仍保留。',
            'The state changed. Review again. The draft is retained.',
          ),
        );
      }
    } finally {
      _waitingUser = false;
      _work = false;
      if (mounted) setState(() {});
    }
    if (!mounted) return;
    if (c.phase == LocalArticleCreationPhase.finished) {
      await _closeAndPop();
    } else if (_lease.retired || _token != _wantedToken) {
      await _remount();
    }
  }

  Future<void> _reload() async {
    if (_blocked) return;
    _work = true;
    setState(() {});
    try {
      await _lease.retire();
      await _source.drain();
      if (!await c.flush()) throw StateError('Article durability unavailable');
      if (mounted) await _remount();
    } catch (_) {
      if (mounted) {
        setState(
          () => _notice = t(
            '草稿未确认写入，请保留页面并重试。',
            'Draft durability is unconfirmed. Keep this page open and retry.',
          ),
        );
      }
    } finally {
      _waitingUser = false;
      _work = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _readyReview(
    int epoch,
    OwnedPreviewController lease,
    ComplexEditorDocument expected,
    ComplexEditorTransport transport,
  ) async {
    ComplexEditorSnapshot? snapshot;
    try {
      snapshot = await transport.capture();
      if (!snapshot.document.same(expected)) {
        throw StateError('Readonly article source mismatch');
      }
      if (mounted &&
          epoch == _mount &&
          identical(lease, _lease) &&
          !lease.retired) {
        setState(() => _reviewReady = true);
      }
    } catch (_) {
      if (mounted && epoch == _mount) {
        setState(
          () => _notice = t(
            '无法核对只读正文，请重新打开。草稿仍保留。',
            'Cannot verify the read-only content. Reopen it. The draft is retained.',
          ),
        );
      }
    } finally {
      if (snapshot != null) {
        try {
          await transport.release(snapshot);
        } catch (_) {}
      }
    }
  }

  Future<void> _closeAndPop({bool? result}) async {
    if (_leaving || !mounted) return;
    _leaving = true;
    _timer?.cancel();
    setState(() {});
    try {
      final pending = _surfaceJob;
      if (pending != null) await pending;
      await _lease.retire();
      await _source.drain();
      if (!await c.flush()) throw StateError('Creation draft was not durable');
      if (!mounted) return;
      setState(() => _allowPop = true);
      await WidgetsBinding.instance.endOfFrame;
      if (mounted && ModalRoute.of(context)?.isCurrent == true) {
        Navigator.pop(
          context,
          result ??
              (!c.discarded &&
                  (c.created != null || c.record.createdId != null)),
        );
      }
    } catch (_) {
      _leaving = false;
      if (mounted) {
        setState(
          () => _notice = t(
            '草稿未确认写入，当前页面已保留。请重试。',
            'Draft durability is unconfirmed. This page is retained. Retry.',
          ),
        );
        await _remount();
      }
    }
  }

  Future<void> _leave() async {
    if (_blocked) return;
    _work = true;
    _timer?.cancel();
    setState(() {});
    try {
      if (_editing) {
        if (_source.ready && !await _source.prepareLeave()) {
          throw StateError('Latest article body was not checkpointed');
        }
        if (!mounted) return;
        if (c.dirty) {
          setState(() => _waitingUser = true);
          final choice = await showDialog<String>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(t('保留新建草稿？', 'Keep this new draft?')),
              content: Text(
                t(
                  '草稿仅保留在此设备，不会创建文章。',
                  'The draft stays on this device. No article will be created.',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(t('继续编辑', 'Continue editing')),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, 'discard'),
                  child: Text(t('放弃草稿', 'Discard draft')),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, 'keep'),
                  child: Text(t('保留并返回', 'Keep and return')),
                ),
              ],
            ),
          );
          if (mounted) setState(() => _waitingUser = false);
          if (!mounted || choice == null) return;
          if (choice == 'discard') {
            await c.discardDraft();
            if (c.phase != LocalArticleCreationPhase.finished) {
              throw StateError('Draft cleanup unavailable');
            }
          }
        }
      }
      if (mounted) await _closeAndPop(result: false);
    } catch (_) {
      if (mounted) {
        setState(
          () => _notice = t(
            '草稿未确认写入或清理，请保留页面后重试。',
            'Draft storage or cleanup is unconfirmed. Keep this page open and retry.',
          ),
        );
      }
    } finally {
      _waitingUser = false;
      _work = false;
      if (mounted && !_leaving && c.canEdit) await _source.unlock();
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _io?.retire();
    _timer?.cancel();
    c.removeListener(_updated);
    _lease.dispose();
    unawaited(_source.dispose());
    c.dispose();
    widget.onDisposed?.call();
    super.dispose();
  }

  String get _pageTitle {
    if (_editing) return t('新建文章', 'New article');
    if (c.phase == LocalArticleCreationPhase.cleanup) {
      return t('文章已创建', 'Article created');
    }
    if (c.unavailable) return t('已创建文章不可用', 'Created article unavailable');
    if (c.phase == LocalArticleCreationPhase.review) {
      return c.confirmedAbsent
          ? t('核对未创建草稿', 'Review uncreated draft')
          : t('核对已创建文章', 'Review created article');
    }
    return t('核对创建结果', 'Review creation result');
  }

  Widget _badge(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: lavender,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      text,
      style: const TextStyle(color: purple, fontWeight: FontWeight.w600),
    ),
  );
  Widget _button(
    String label,
    VoidCallback? action, {
    bool tonal = false,
    bool outline = false,
  }) {
    final style = FilledButton.styleFrom(
      backgroundColor: tonal ? lavender : purple,
      foregroundColor: tonal ? purple : Colors.white,
      minimumSize: const Size.fromHeight(48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: outline
          ? OutlinedButton(
              onPressed: action,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                foregroundColor: purple,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(label),
            )
          : FilledButton(onPressed: action, style: style, child: Text(label)),
    );
  }

  Widget _summary() {
    final cleanup = c.phase == LocalArticleCreationPhase.cleanup;
    final found =
        c.phase == LocalArticleCreationPhase.review && c.observed != null;
    if (found) {
      return Align(
        alignment: Alignment.centerLeft,
        child: _badge(t('只读核对', 'Read-only review')),
      );
    }
    final label = cleanup
        ? t('已创建，草稿清理待重试', 'Created; draft cleanup needs retry')
        : c.unavailable
        ? t('原文章已删除或格式已变化', 'Original article deleted or format changed')
        : c.confirmedAbsent
        ? t('未找到已创建文章', 'No created article found')
        : t('创建结果待核对', 'Creation result needs review');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cleanup
            ? const Color(0xffe4f4e7)
            : c.unavailable
            ? const Color(0xffffe5e5)
            : const Color(0xfffff0ca),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(cleanup ? Icons.check_circle_outline : Icons.error_outline),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _reviewActions() {
    final canReview = !_blocked && _reviewReady;
    final canApply = canReview && c.reviewed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (c.phase == LocalArticleCreationPhase.review && !c.unavailable)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: c.reviewed,
            onChanged: canReview ? (v) => c.setReviewed(v ?? false) : null,
            title: Text(
              c.confirmedAbsent
                  ? t('我已核对草稿内容', 'I reviewed the draft')
                  : t('我已核对文章内容', 'I reviewed the article'),
            ),
          ),
        if (c.phase == LocalArticleCreationPhase.cleanup)
          _button(
            t('重试清理', 'Retry cleanup'),
            _blocked ? null : () => _action(c.retryCleanup),
          )
        else if (c.unavailable)
          _button(
            t('清理失效草稿', 'Clear unavailable draft'),
            _blocked ? null : () => _action(c.finishUnavailable),
          )
        else if (c.phase == LocalArticleCreationPhase.review &&
            c.confirmedAbsent) ...[
          _button(
            t('重试创建', 'Retry creation'),
            canApply ? () => _action(c.retryCreate) : null,
          ),
          _button(
            t('返回编辑', 'Return to editing'),
            canApply ? () => _action(c.resumeEditing) : null,
            outline: true,
          ),
        ] else if (c.phase == LocalArticleCreationPhase.review)
          _button(
            t('采用此结果', 'Adopt this result'),
            canApply ? () => _action(c.adopt) : null,
          )
        else
          _button(
            t('核对结果', 'Check result'),
            _blocked ? null : () => _action(c.inspect),
          ),
        _button(
          t('保留并返回', 'Keep and return'),
          _blocked ? null : _leave,
          tonal: true,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final epoch = _mount, lease = _lease, document = _document;
    final title = _visibleTitle.isEmpty
        ? t('点击填写标题', 'Tap to enter a title')
        : _visibleTitle;
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_leave());
      },
      child: Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(primary: purple),
        ),
        child: Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            backgroundColor: purple,
            foregroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            title: Text(
              _pageTitle,
              style: const TextStyle(color: Colors.white),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            leading: IconButton(
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              onPressed: _blocked ? null : _leave,
              icon: const Icon(Icons.arrow_back),
            ),
            actions: [
              if (_ioBusy)
                IconButton(
                  tooltip: t('取消源文件操作', 'Cancel source operation'),
                  onPressed: () => _io?.cancel(),
                  icon: const Icon(Icons.close),
                ),
              if (_editing && widget.sourceIoScope != null)
                IconButton(
                  tooltip: t('源文件导入与导出', 'Source file import and export'),
                  onPressed: _blocked || !_source.ready ? null : _sourceFiles,
                  icon: const Icon(Icons.import_export),
                ),

              if (_editing)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: FilledButton(
                    onPressed: _blocked || !_source.ready ? null : _create,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: purple,
                    ),
                    child: Text(t('创建', 'Create')),
                  ),
                ),
            ],
          ),
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final height = math.max(
                  240.0,
                  constraints.maxHeight * (_renderEditing ? 0.74 : 0.40),
                );
                return SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_editing)
                          Row(
                            children: [
                              _badge(t('本地文章', 'Local article')),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(t('尚未创建', 'Not created yet')),
                              ),
                            ],
                          )
                        else
                          _summary(),
                        if (!_editing) ...[
                          const SizedBox(height: 12),
                          Text(
                            c.phase == LocalArticleCreationPhase.cleanup
                                ? t(
                                    '文章不会再次创建。',
                                    'The article will not be created again.',
                                  )
                                : c.unavailable
                                ? t(
                                    '创建记录仍保留，不会重新创建文章。',
                                    'The creation receipt remains; the article will not be recreated.',
                                  )
                                : c.confirmedAbsent
                                ? t(
                                    '核对草稿后，可重试创建或返回编辑。',
                                    'Review the draft before retrying or returning to editing.',
                                  )
                                : c.observed != null
                                ? t(
                                    '找到已创建的文章，请核对后继续。',
                                    'A created article was found. Review it to continue.',
                                  )
                                : t(
                                    '不会自动重复创建。请先核对本机记录。',
                                    'Creation will not repeat automatically. Check local records first.',
                                  ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        InkWell(
                          onTap: _editing && !_blocked && _source.ready
                              ? _metadataDialog
                              : null,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    title,
                                    style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                if (_editing)
                                  const Icon(
                                    Icons.edit_outlined,
                                    color: purple,
                                  ),
                              ],
                            ),
                          ),
                        ),
                        if (_visibleLabels.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                for (final label in _visibleLabels)
                                  Chip(
                                    backgroundColor: lavender,
                                    side: BorderSide.none,
                                    shape: const StadiumBorder(),
                                    label: Text(
                                      label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(color: purple),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        if (_notice != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Text(
                              _notice!,
                              style: const TextStyle(color: Color(0xff9c2c2c)),
                            ),
                          ),
                        if ((_work || c.busy) && !_waitingUser)
                          const LinearProgressIndicator(),
                        const SizedBox(height: 12),
                        SizedBox(
                          key: const ValueKey(
                            'article-creation-browser-boundary',
                          ),
                          height: height,
                          child: _renderEditing
                              ? LocalArticleCreationSourceSurface(
                                  key: ValueKey('article-new-$epoch'),
                                  coordinator: _source,
                                  source: document.source,
                                  title: title,
                                  english: widget.english,
                                  retirementController: lease,
                                  onChanged: () {
                                    if (mounted) setState(() {});
                                  },
                                  onStateChanged: _state,
                                  onSaveRequested: _create,
                                  onReloadRequested: _reload,
                                  builder: widget.sourceBuilder,
                                )
                              : widget.reviewBuilder(
                                  context,
                                  key: ValueKey('article-new-review-$epoch'),
                                  document: document,
                                  title: title,
                                  english: widget.english,
                                  retirementController: lease,
                                  onReady: (transport) => _readyReview(
                                    epoch,
                                    lease,
                                    document,
                                    transport,
                                  ),
                                  onReloadRequested: _reload,
                                ),
                        ),
                        const SizedBox(height: 12),
                        if (_editing)
                          Center(
                            child: Text(
                              t(
                                '草稿仅保留在此设备',
                                'Drafts are retained only on this device',
                              ),
                            ),
                          )
                        else ...[
                          if (c.phase == LocalArticleCreationPhase.cleanup ||
                              c.unavailable)
                            Text(t('创建时的草稿', 'Draft at creation time')),
                          _reviewActions(),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
