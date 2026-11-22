import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../../core/attachments.dart';
import '../../core/local_legacy_candidate_review.dart';
import '../../core/local_legacy_format_selection.dart';
import '../../core/local_legacy_go_export.dart';
import '../../core/local_legacy_zip_stage.dart';
import '../../core/native_local_backup_picker.dart';
import 'local_legacy_candidate_review_page.dart';
import 'local_legacy_format_page.dart';

/// One source-inspection owner. Root joins real readers/files, never the
/// Navigator future. Failed retirement stays sealed and can be retried.
class LocalLegacyInspectionLifetime {
  Future<void> Function()? _close;
  Future<void>? _retirement;
  bool _closed = false;
  bool get current => !_closed;
  void bind(Future<void> Function() close) {
    if (_close != null) throw StateError('Legacy inspection owner reused');
    _close = close;
  }

  Future<void> retire() {
    _closed = true;
    final existing = _retirement;
    if (existing != null) return existing;
    final done = Completer<void>();
    final work = done.future;
    _retirement = work;
    unawaited(
      Future<void>.sync(() async {
        await _close?.call();
      }).then<void>(
        (_) => done.complete(),
        onError: (Object error, StackTrace stack) {
          if (identical(_retirement, work)) _retirement = null;
          done.completeError(error, stack);
        },
      ),
    );
    return work;
  }
}

/// A fresh source preparation owner, not a writable review session.
class OwnedLegacyActivationRoute {
  const OwnedLegacyActivationRoute({required this.page, required this.retire});
  final Widget page;
  final Future<void> Function() retire;
}

typedef OpenOwnedLegacyActivation =
    Future<OwnedLegacyActivationRoute> Function(
      LegacyZipStage zip,
      LegacyFormatSelection selection,
    );

/// Owns source inspection; optional activation builds a separate owned candidate.
class LocalLegacyMigrationPage extends StatefulWidget {
  const LocalLegacyMigrationPage({
    super.key,
    required this.privateCache,
    required this.availableBytes,
    required this.isCurrentScope,
    this.factory,
    this.ownedActivation,
    this.inspectionLifetime,
    this.registerChildRoute,
    this.unregisterChildRoute,
    this.picker,
    this.english = false,
  });
  final Directory privateCache;
  final Future<int> Function() availableBytes;
  final bool Function() isCurrentScope;
  final DatabaseFactory? factory;
  final OpenOwnedLegacyActivation? ownedActivation;
  final LocalLegacyInspectionLifetime? inspectionLifetime;
  final void Function(Route<void>)? registerChildRoute, unregisterChildRoute;
  final NativeLocalBackupPicker? picker;
  final bool english;
  @override
  State<LocalLegacyMigrationPage> createState() =>
      _LocalLegacyMigrationPageState();
}

class _LocalLegacyMigrationPageState extends State<LocalLegacyMigrationPage>
    with WidgetsBindingObserver {
  late final _picker = widget.picker ?? NativeLocalBackupPicker();
  Directory? _work;
  LegacyZipStage? _stage;
  LegacyGoExport? _source;
  LegacyFormatSelection? _selection;
  LegacyCandidateReviewSession? _review;
  AttachmentCancellation? _request;
  Route<void>? _child;
  Future<void>? _operation;
  OwnedLegacyActivationRoute? _ownedActivation;
  Future<OwnedLegacyActivationRoute>? _ownedOpening;
  bool _ownedOpenCancelled = false;
  bool _choosing = false,
      _disposed = false,
      _leaving = false,
      _failed = false,
      _building = false;
  String t(String zh, String en) => widget.english ? en : zh;
  bool get _current =>
      mounted &&
      !_disposed &&
      !_leaving &&
      (widget.inspectionLifetime?.current ?? true) &&
      widget.isCurrentScope();
  bool get _busy => _operation != null || _ownedOpening != null;
  void _refresh() {
    if (mounted && !_disposed) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.inspectionLifetime?.bind(_drainInspection);
  }

  void _check(AttachmentCancellation request) {
    request.check();
    if (!_current) throw StateError('Retired inspection owner');
  }

  Future<void> _directory(Directory folder) async {
    if (!p.isAbsolute(folder.path) ||
        await FileSystemEntity.type(folder.path, followLinks: false) !=
            FileSystemEntityType.directory ||
        await folder.resolveSymbolicLinks() != p.normalize(folder.path)) {
      throw const FormatException('Untrusted private inspection directory');
    }
  }

  Future<void> _cleanStage() async {
    final opening = _ownedOpening;
    if (opening != null) {
      try {
        _ownedActivation = await opening;
      } catch (_) {}
      if (identical(_ownedOpening, opening)) _ownedOpening = null;
    }
    final owned = _ownedActivation;
    if (owned != null) {
      await owned
          .retire(); // Actual construction/SQL/file work, never Navigator.
      if (identical(_ownedActivation, owned)) _ownedActivation = null;
    }
    final stage = _stage;
    if (stage != null) {
      await _directory(stage.directory);
      final allowed = stage.files.values
          .map((f) => p.normalize(f.file.path))
          .toSet();
      await for (final entry in stage.directory.list(followLinks: false)) {
        if (!allowed.contains(p.normalize(entry.path)) ||
            await FileSystemEntity.type(entry.path, followLinks: false) !=
                FileSystemEntityType.file) {
          throw const LegacyReviewCleanupRequired();
        }
      }
      for (final file in stage.files.values) {
        if (await file.file.exists()) await file.file.delete();
      }
      await stage.directory.delete();
      _stage = null;
    }
    final work = _work;
    if (work != null) {
      await _directory(work);
      // Non-recursive: an unknown file or unfinished child prevents deletion.
      await work.delete();
      _work = null;
    }
    _source = null;
    _selection = null;
  }

  Future<void> _closeReview() async {
    await _review
        ?.close(); // Its registered readers close before database/files.
    _review = null;
  }

  Future<void> _push(Widget page) async {
    if (!_current) return;
    final route = MaterialPageRoute<void>(builder: (_) => page);
    _child = route;
    widget.registerChildRoute?.call(route);
    try {
      await Navigator.of(context).push(route);
    } finally {
      widget.unregisterChildRoute?.call(route);
      if (identical(_child, route)) _child = null;
    }
  }

  Future<void> _choose() async {
    if (_busy || !_current) return;
    final request = AttachmentCancellation();
    _request = request;
    _failed = false;
    _building = false;
    final work = _inspect(request);
    _operation = work;
    _refresh();
    try {
      await work;
    } catch (_) {
      if (!request.cancelled) _failed = true;
    } finally {
      if (identical(_operation, work)) _operation = null;
      if (identical(_request, request)) _request = null;
      _refresh();
    }
  }

  Future<void> _inspect(AttachmentCancellation request) async {
    PickedLocalBackup? picked;
    try {
      await _closeReview();
      await _cleanStage();
      _check(request);
      try {
        _choosing = true;
        picked = await _picker.pick();
      } finally {
        _choosing = false;
      }
      _check(request);
      if (picked == null) return;
      await _directory(widget.privateCache);
      final inbox = Directory(
        p.join(widget.privateCache.path, 'local-backup-inbox-v1'),
      );
      await _directory(inbox);
      final file = File(p.join(inbox.path, '${picked.id}.bsbackup'));
      if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(picked.id) ||
          await FileSystemEntity.type(file.path, followLinks: false) !=
              FileSystemEntityType.file ||
          await file.length() != picked.bytes) {
        throw const FormatException('Unbound selected ZIP');
      }
      _work = await widget.privateCache.createTemp('legacy-review-flow-');
      _stage = await LegacyZipStage.inspect(
        file,
        privateParent: _work!,
        expectedSha256: picked.sha256,
        availableBytes: widget.availableBytes,
        isCancelled: () => request.cancelled || !_current,
      );
      _check(request);
      _source = await LegacyGoExport.inspect(
        _stage!,
        isCancelled: () => request.cancelled || !_current,
      );
      if (_source!.issues.any(
        (issue) => !{
          LegacyGoIssueCode.editorTypeMissing,
          LegacyGoIssueCode.protectedContent,
          LegacyGoIssueCode.unknownField,
        }.contains(issue.code),
      )) {
        throw const FormatException(
          'Export requires unsupported conflict resolution',
        );
      }
      _check(request);
      _selection = LegacyFormatSelection(
        LegacyFormatSource.fromInspection(_source!, scopeKey: attachmentId()),
      );
    } catch (_) {
      await _cleanStage();
      rethrow;
    } finally {
      if (picked != null) await _picker.release(picked);
    }
  }

  Future<void> _formats() async {
    final selection = _selection;
    if (_busy || !_current || selection == null) return;
    await _push(
      LocalLegacyFormatPage(
        source: selection.source,
        initial: selection,
        english: widget.english,
        isCurrentScope: () =>
            _current && identical(_selection?.source, selection.source),
        onResolved: (value) async {
          if (!_current || !identical(value.source, selection.source)) {
            throw StateError('Retired format inspection');
          }
          _selection = value;
          final route = _child;
          if (route != null && route.navigator != null && route.isActive) {
            route.navigator!.removeRoute(route);
          }
          _refresh();
        },
      ),
    );
    _refresh();
  }

  Future<void> _openOwnedActivation() async {
    final open = widget.ownedActivation, selection = _selection, stage = _stage;
    if (open == null ||
        selection == null ||
        stage == null ||
        !selection.complete ||
        !_current ||
        _busy ||
        _ownedOpening != null ||
        _ownedActivation != null) {
      return;
    }
    _ownedOpenCancelled = false;
    final opening = open(stage, selection);
    _ownedOpening = opening;
    _refresh();
    try {
      final owned = await opening;
      _ownedActivation = owned;
      if (identical(_ownedOpening, opening)) _ownedOpening = null;
      if (_ownedOpenCancelled || !_current || !identical(_stage, stage)) {
        await owned.retire();
        if (identical(_ownedActivation, owned)) _ownedActivation = null;
        return;
      }
      await _push(owned.page);
      await owned.retire();
      if (identical(_ownedActivation, owned)) _ownedActivation = null;
    } catch (_) {
      _failed = true; // Retain source/preparation on unconfirmed cleanup.
    } finally {
      if (identical(_ownedOpening, opening)) _ownedOpening = null;
      _refresh();
    }
  }

  Future<void> _openReview() async {
    final selection = _selection, stage = _stage, workRoot = _work;
    if (_busy ||
        !_current ||
        selection == null ||
        !selection.complete ||
        stage == null ||
        workRoot == null) {
      return;
    }
    final request = AttachmentCancellation();
    _request = request;
    _building = true;
    _failed = false;
    final build = LegacyCandidateReviewSession.build(
      stage: stage,
      selection: selection,
      privateParent: workRoot,
      availableBytes: widget.availableBytes,
      factory: widget.factory,
      cancellation: request,
      isCurrentScope: () => _current && identical(_stage, stage),
    );
    _operation = build;
    _refresh();
    try {
      final review = await build;
      _review = review;
      _check(request);
      // Construction ends before navigation, so cancel never waits for the page.
      _operation = null;
      _request = null;
      _refresh();
      await _push(
        LocalLegacyCandidateReviewPage(
          session: review,
          english: widget.english,
        ),
      );
      await _closeReview();
    } catch (_) {
      await _closeReview();
      if (!request.cancelled) _failed = true;
    } finally {
      if (identical(_operation, build)) _operation = null;
      if (identical(_request, request)) _request = null;
      _building = false;
      _refresh();
    }
  }

  Future<void> _cancel() async {
    _ownedOpenCancelled = true;
    _request?.cancel();
    await _picker.cancel();
    try {
      await _operation;
    } catch (_) {}
  }

  Future<void> _drainInspection() async {
    _leaving = true;
    await _cancel();
    await _closeReview();
    final owned = _ownedActivation;
    if (owned != null) await owned.retire();
    final route = _child;
    if (route != null && route.isActive) route.navigator?.removeRoute(route);
    await _cleanStage();
    if (widget.picker == null) await _picker.dispose();
  }

  Future<void> _exit() async {
    if (_leaving || _disposed) return;
    final lifetime = widget.inspectionLifetime;
    if (lifetime != null) {
      _leaving = true;
      _refresh();
      try {
        await lifetime.retire();
        if (mounted && !_disposed) Navigator.of(context).pop();
      } catch (_) {
        _leaving = false;
        _failed = true;
        _refresh();
      }
      return;
    }
    _leaving = true;
    _refresh();
    try {
      await _cancel();
      await _closeReview();
      final route = _child;
      if (route?.navigator != null && route!.isActive) {
        route.navigator!.removeRoute(route);
      }
      await _cleanStage();
      if (mounted && !_disposed) Navigator.of(context).pop();
    } catch (_) {
      _leaving = false;
      _failed = true;
      _refresh();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if ((state == AppLifecycleState.paused ||
            state == AppLifecycleState.detached) &&
        _busy &&
        !_choosing) {
      unawaited(_cancel().catchError((Object _) {}));
    } else if (state == AppLifecycleState.resumed && !_current) {
      unawaited(_exit());
    }
  }

  @override
  void didUpdateWidget(covariant LocalLegacyMigrationPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.privateCache, widget.privateCache) || !_current) {
      unawaited(_exit());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _request?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    final lifetime = widget.inspectionLifetime;
    if (lifetime != null) {
      unawaited(lifetime.retire().catchError((Object _) {}));
      super.dispose();
      return;
    }
    unawaited(() async {
      try {
        if (widget.picker == null) await _picker.dispose();
        await _cancel();
        await _closeReview();
        await _cleanStage();
      } catch (_) {
        // Failed cleanup retains this private temporary copy for recovery.
      } finally {
        if (widget.picker == null) await _picker.dispose();
      }
    }());
    super.dispose();
  }

  Widget _button(String label, VoidCallback? action, {bool outline = false}) =>
      SizedBox(
        width: double.infinity,
        child: outline
            ? OutlinedButton(
                onPressed: action,
                child: Text(label, textAlign: TextAlign.center),
              )
            : FilledButton(
                onPressed: action,
                child: Text(label, textAlign: TextAlign.center),
              ),
      );
  @override
  Widget build(BuildContext context) {
    final source = _source, selection = _selection;
    Widget body;
    if (_busy) {
      body = CandidateReviewCard(
        child: Column(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            Text(
              _building
                  ? t('正在准备审阅副本', 'Preparing review copy')
                  : t('正在检查数据包', 'Checking export'),
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            Text(t('校验文件与附件', 'Verifying files and attachments')),
            const SizedBox(height: 32),
            _button(
              t('取消检查', 'Cancel check'),
              () => unawaited(_cancel()),
              outline: true,
            ),
          ],
        ),
      );
    } else if (_failed) {
      body = CandidateReviewFailure(
        english: widget.english,
        busy: _leaving,
        onReturn: () => unawaited(_choose()),
      );
    } else if (source == null || selection == null) {
      body = Column(
        children: [
          const SizedBox(height: 64),
          const Icon(Icons.folder_rounded, color: reviewBlue, size: 104),
          const SizedBox(height: 32),
          Text(
            t('检查旧版导出包', 'Check legacy export'),
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Text(
            t(
              '选择 BookStark 旧版导出的 ZIP 文件。',
              'Choose a ZIP exported by legacy BookStark.',
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 40),
          _button(
            t('选择 ZIP 文件', 'Choose ZIP file'),
            _leaving ? null : () => unawaited(_choose()),
          ),
          const SizedBox(height: 24),
          Text(
            t(
              '保留原始文件，审阅不会替换当前数据。',
              'Keep the original. Review does not replace current data.',
            ),
            textAlign: TextAlign.center,
          ),
        ],
      );
    } else {
      final notes = selection.source.items
          .where((b) => b.collection == 'note')
          .length;
      final articles = selection.source.items
          .where((b) => b.collection == 'article')
          .length;
      final protected = selection.source.items
          .where((b) => b.isProtected)
          .length;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 32),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  t('已完成检查', 'Check complete'),
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          CandidateReviewCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t('数据概览', 'Data overview'),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 24,
                  runSpacing: 16,
                  children: [
                    for (final stat in [
                      (t('笔记', 'Notes'), notes),
                      (t('文章', 'Articles'), articles),
                      (t('受保护', 'Protected'), protected),
                      (
                        t('附件', 'Attachments'),
                        _stage!.files.keys
                            .where((k) => k.startsWith('uploads/'))
                            .length,
                      ),
                    ])
                      Column(
                        children: [
                          Text(stat.$1),
                          Text(
                            '${stat.$2}',
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          CandidateReviewCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  t('内容格式', 'Content formats'),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  selection.complete
                      ? t('已确认', 'Confirmed')
                      : t('等待确认', 'Needs confirmation'),
                ),
                const SizedBox(height: 16),
                _button(
                  selection.complete
                      ? t('重新确认', 'Confirm again')
                      : t('确认内容格式', 'Confirm formats'),
                  _leaving ? null : () => unawaited(_formats()),
                  outline: selection.complete,
                ),
                const SizedBox(height: 12),
                _button(
                  t('只读审阅副本', 'Review read-only copy'),
                  selection.complete && !_leaving
                      ? () => unawaited(_openReview())
                      : null,
                ),
                const SizedBox(height: 12),
                if (widget.ownedActivation != null) ...[
                  _button(
                    t('准备独立可编辑空间', 'Prepare an independent editable space'),
                    selection.complete &&
                            !_leaving &&
                            _ownedOpening == null &&
                            _ownedActivation == null
                        ? () => unawaited(_openOwnedActivation())
                        : null,
                  ),
                  const SizedBox(height: 12),
                ],
                _button(
                  t('重新选择文件', 'Choose another file'),
                  _leaving ? null : () => unawaited(_choose()),
                  outline: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Text(
            t('当前数据保持不变。', 'Current data remains unchanged.'),
            textAlign: TextAlign.center,
          ),
        ],
      );
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_exit());
      },
      child: CandidateReviewFrame(
        title: t('旧版数据检查', 'Legacy export check'),
        onBack: _leaving ? null : () => unawaited(_exit()),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: body,
        ),
      ),
    );
  }
}
