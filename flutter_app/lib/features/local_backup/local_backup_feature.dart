import '../../core/owned_writable_generation15.dart';
import '../../core/owned_generation15_restore_coordinator.dart';
import '../../core/local_data_maintenance.dart';
import 'dart:async';
import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import '../../core/file_export.dart';
import '../../core/attachments.dart';
import '../../core/local_applied_backup_review.dart';
import '../../core/local_backup_exporter.dart';
import '../../core/local_backup_importer.dart';
import '../../core/local_data_paths.dart';
import '../../core/local_recovery_inventory.dart';
import '../../core/local_recovery_namespaces.dart';
import '../../core/local_article_draft_receipt.dart';
import '../../core/local_article_creation_legacy_metadata.dart';
import '../../core/local_recovery_resolver.dart';
import '../../core/local_restore_coordinator.dart';
import '../../core/local_retained_backup.dart';
import '../../core/local_storage_session.dart';
import '../../core/local_store.dart';
import '../../core/native_local_backup_picker.dart';
import '../../core/native_local_data_control.dart';
import 'local_backup_page.dart';
import 'local_legacy_migration_page.dart';
import 'local_pending_recovery_page.dart';
import 'local_recovery_page.dart';
import 'local_retention_catalog_page.dart';

/// Owns its nested routes. The app removes/replaces this entire feature only
/// after opening a fresh session, so busy PopScopes never cause popUntil loops.
class LocalBackupFeature extends StatefulWidget {
  const LocalBackupFeature({
    super.key,
    required this.session,
    required this.privateCache,
    required this.isCurrentScope,
    required this.onEntered,
    required this.onConnection,
    required this.openDraft,
    this.store,
    this.owned15,
    this.beforeOwnedSeal,
    this.runOwnedActivation,
    this.openOwnedPending,
    this.openOwnedLegacyMigration,
    this.ownedLegacyActivation,
    this.registerLegacyChildRoute,
    this.unregisterLegacyChildRoute,
    this.recoveryOnly = false,
    this.english = false,
    this.picker,
    this.beforeActivate,
  });
  final Future<void> Function()? beforeActivate;
  final LocalStorageSession session;
  final Directory privateCache;
  final LocalStore? store;
  final OwnedWritableGeneration15? owned15;
  final OpenOwnedLegacyActivation? ownedLegacyActivation;
  final void Function(Route<void>)? registerLegacyChildRoute,
      unregisterLegacyChildRoute;
  final Future<void> Function()? beforeOwnedSeal;
  final Future<LocalControlReceipt> Function(
    Future<LocalControlReceipt> Function(),
  )?
  runOwnedActivation;
  final Future<void> Function()? openOwnedPending, openOwnedLegacyMigration;
  final NativeLocalBackupPicker? picker;
  final bool Function() isCurrentScope;
  final Future<void> Function(LocalControlReceipt) onEntered;
  final Future<void> Function() onConnection;
  final Future<void> Function(BuildContext, LocalRecoveryDestination) openDraft;
  final bool recoveryOnly, english;
  @override
  State<LocalBackupFeature> createState() => _LocalBackupFeatureState();
}

class _LocalBackupFeatureState extends State<LocalBackupFeature> {
  final _navigator = GlobalKey<NavigatorState>();
  late final _picker = widget.picker ?? NativeLocalBackupPicker();
  AttachmentCancellation? _inspectionCancellation;
  Future<void>? _inspectionCancelFuture;
  Future<void> _cancelInspection() {
    final cancellation = _inspectionCancellation;
    if (cancellation == null) return Future<void>.value();
    cancellation.cancel();
    return _inspectionCancelFuture ??= _picker.cancel();
  }

  Future<void> _releaseInbox(PickedLocalBackup selected) async {
    try {
      await _picker.release(selected);
    } catch (_) {
      // Unconfirmed private inbox cleanup leaves the private copy retained.
      // It never removes the external document or any current local data.
    }
  }

  String t(String zh, String en) => widget.english ? en : zh;
  NativeLocalDataControl get control => widget.session.control;
  LocalStore get store =>
      widget.store ?? (throw StateError('No writable local storage session'));
  void _scope() {
    if (!mounted || !widget.isCurrentScope()) {
      throw StateError('Local storage scope has changed');
    }
  }

  Future<void> _writable() async {
    _scope();
    final owned = widget.owned15;
    if (owned != null) {
      if (widget.store != null) {
        throw StateError('Mixed local storage capabilities');
      }
      await owned.confirmCurrent();
      _scope();
      return;
    }
    if (store.maintenance.retired) {
      throw StateError('Storage requires result review');
    }
    final state = await control.readState();
    _scope();
    if (state.observation.needsReview ||
        state.observation.pointer?.generation !=
            store.dataPaths!.generationId) {
      throw LocalDataNeedsReview(state.observation);
    }
  }

  Future<LocalRecoveryInventory> _inventory() async {
    final owned = widget.owned15;
    final namespaces = await localRecoveryNamespaces(
      owned?.generation ?? store.dataPaths!,
    );
    _scope();
    return LocalRecoveryInventory(
      // Owned15 SQL/content synchronization is its sealed owner's snapshot
      // gate; this inventory reads bounded native keys only, never database rows.
      maintenance: owned == null ? store.maintenance : LocalDataMaintenance(),
      localNamespaces: namespaces,
    );
  }

  Future<LocalBackupExporter> _exporter() async {
    final inventory = await _inventory();
    return LocalBackupExporter(
      store: store,
      attachments: store.dataPaths!.attachments,
      driveBlobs: store.dataPaths!.driveBlobs,
      workspace: Directory(
        '${widget.privateCache.path}/local-backup-export-v1',
      ),
      checkPendingRecovery: () async {
        (await inventory.read()).requireClear();
      },
    );
  }

  Future<OwnedGeneration15BackupExporter> _ownedExporter() async {
    final owned = widget.owned15;
    if (owned == null) throw StateError('Owned15 capability required');
    final inventory = await _inventory();
    return OwnedGeneration15BackupExporter(
      owner: owned,
      factory: widget.session.factory ?? databaseFactory,
      workspace: Directory('${widget.privateCache.path}/owned15-backup-export'),
      checkPendingRecovery: () async {
        (await inventory.read()).requireClear();
      },
    );
  }

  LocalBackupCandidateImporter get _importer => LocalBackupCandidateImporter(
    privateSupport: widget.session.privateSupport,
    privateCache: widget.privateCache,
    factory: widget.session.factory ?? databaseFactory,
    availableBytes: control.availableBytes,
    discardCandidate: (id) async {
      await control.discardCandidate(id);
    },
  );
  Future<void> _push(Widget page) async {
    _scope();
    await _navigator.currentState!.push<void>(
      MaterialPageRoute(builder: (_) => page),
    );
  }

  Widget _backup([LocalBackupCandidate? initial]) => LocalBackupPage(
    english: widget.english,
    exportNotice: widget.owned15 == null
        ? null
        : t(
            '备份保留原有保护与加密状态，可能包含历史明文。当前解锁密码不会写入备份；请保存到可信位置。',
            'The backup retains original protection and encryption and may contain historical plaintext. The current unlock password is not included. Choose a trusted location.',
          ),
    initialCandidate: initial,
    cancelInspection: _cancelInspection,
    onBack: () {
      if (_navigator.currentState!.canPop()) {
        _navigator.currentState!.maybePop();
      } else {
        Navigator.of(context).maybePop();
      }
    },
    createExport: () async {
      await _writable();
      final completed = widget.owned15 == null
          ? await (await _exporter()).create()
          : await (await _ownedExporter()).create();
      if (!mounted || !widget.isCurrentScope()) {
        await completed.dispose();
        throw StateError('Storage scope changed');
      }
      return completed;
    },
    saveExport: (completed) async {
      _scope();
      return const SystemFileExporter().saveFile(
        file: XFile(completed.file.path),
        name: 'bookstark-backup.bsbackup',
        mime: 'application/octet-stream',
        size: completed.size,
        hash: completed.sha256,
      );
    },
    inspectPicked: () async {
      if (_inspectionCancellation != null) {
        throw StateError('Input check is already active');
      }
      final cancellation = AttachmentCancellation();
      _inspectionCancellation = cancellation;
      _inspectionCancelFuture = null;
      PickedLocalBackup? selected;
      LocalBackupCandidate? candidate;
      try {
        await _writable();
        cancellation.check();
        selected = await _picker.pick();
        cancellation.check();
        if (selected == null) return null;
        _scope();
        candidate = await _importer.inspectPicked(
          selected.id,
          cancellation: cancellation,
        );
        cancellation.check();
        if (candidate.sourceSHA256 != selected.sha256 ||
            candidate.sourceBytes != selected.bytes) {
          throw const FormatException(
            'Selected backup changed during inspection',
          );
        }
        final copied = selected;
        selected = null;
        await _releaseInbox(copied);
        cancellation.check();
        _scope();
        return candidate;
      } catch (error, stack) {
        await candidate?.discardUnprepared();
        if (cancellation.cancelled) {
          Error.throwWithStackTrace(const AttachmentCancelled(), stack);
        }
        rethrow;
      } finally {
        if (selected != null) await _releaseInbox(selected);
        if (identical(_inspectionCancellation, cancellation)) {
          _inspectionCancellation = null;
        }
      }
    },

    apply: (candidate) async {
      await _writable();
      if (widget.owned15 != null) {
        final beforeSeal = widget.beforeOwnedSeal;
        final run = widget.runOwnedActivation;
        if (beforeSeal == null || run == null) {
          throw StateError('Owned15 activation lifetime is unavailable');
        }
        final coordinator = OwnedGeneration15RestoreCoordinator(
          owner: widget.owned15!,
          exporter: await _ownedExporter(),
          control: control,
          beforeSeal: beforeSeal,
        );
        await run(() => coordinator.apply(candidate));
        return;
      }
      await widget.beforeActivate?.call();
      _scope();
      await LocalRestoreCoordinator(
        retainedBuilder: LocalRetainedBackupBuilder(
          exporter: await _exporter(),
          control: control,
        ),
      ).apply(candidate);
    },
    openRecovery: () => _push(_recovery()),
    openPending: (_) =>
        widget.owned15 == null ? _push(_pending()) : _openOwnedPending(),
    openDrafts: () =>
        widget.owned15 == null ? _push(_pending()) : _openOwnedPending(),
    openRetained: _catalog,
    openLegacyMigration: () =>
        widget.owned15 == null && widget.openOwnedLegacyMigration == null
        ? _push(
            LocalLegacyMigrationPage(
              ownedActivation: widget.ownedLegacyActivation,
              registerChildRoute: widget.registerLegacyChildRoute,
              unregisterChildRoute: widget.unregisterLegacyChildRoute,
              privateCache: widget.privateCache,
              availableBytes: control.availableBytes,
              isCurrentScope: () => mounted && widget.isCurrentScope(),
              factory: widget.session.factory,
              english: widget.english,
            ),
          )
        : _openOwnedLegacyMigration(),
  );

  Future<void> _openOwnedPending() async {
    final open = widget.openOwnedPending;
    if (open == null) throw StateError('Owned15 recovery entry unavailable');
    _scope();
    await open();
  }

  Future<void> _openOwnedLegacyMigration() async {
    final open = widget.openOwnedLegacyMigration;
    if (open == null) throw StateError('Owned15 migration entry unavailable');
    _scope();
    await open();
  }

  String _draftKind(LocalRecoveryDestination destination) =>
      switch (destination.kind) {
        'note' =>
          destination.collection == 'article'
              ? t('文章', 'Article')
              : t('笔记', 'Note'),
        'excerpt' => t('笔记 · 阅读摘录', 'Note · Reading excerpt'),
        'html' || 'html-create' => 'HTML',
        'complex' => t('复杂文档', 'Complex document'),
        'article-create' || 'article-create-archive' => t('文章', 'Article'),
        'task' => t('待办', 'Task'),
        'book' => t('书籍', 'Book'),
        'bookmark' => t('书签', 'Bookmark'),
        'topic' => t('专题', 'Topic'),
        'file' => t('网盘文件', 'Drive file'),
        'document' || 'document-create' => t('章节', 'Chapter'),
        _ => t('本机内容', 'Local content'),
      };
  String _draftTitle(LocalRecoveryDestination destination) {
    if (destination.kind == 'article-create-archive') {
      return t('旧版新建文章草稿', 'Old new-article draft');
    }
    if (destination.title.isNotEmpty) return destination.title;
    if (destination.kind == 'excerpt') return _draftKind(destination);
    return '${_draftKind(destination)} · ${t('新建草稿', 'New draft')}';
  }

  String _archiveStatus(LocalArticleDraftDisposition disposition) =>
      switch (disposition) {
        LocalArticleDraftDisposition.restored => t(
          '已转入编辑器',
          'Transferred to the editor',
        ),
        LocalArticleDraftDisposition.skipped => t(
          '已选择暂不恢复',
          'Restore was deferred',
        ),
        LocalArticleDraftDisposition.matched => t(
          '标记时已与文章一致',
          'Matched the article when handled',
        ),
      };

  String _creationArchiveStatus(
    LocalArticleCreationLegacyDisposition disposition,
  ) => switch (disposition) {
    LocalArticleCreationLegacyDisposition.restored => t(
      '已转入新建草稿',
      'Transferred to an article creation draft',
    ),
    LocalArticleCreationLegacyDisposition.skipped => t(
      '已选择暂不恢复',
      'Restore was deferred',
    ),
  };

  LocalPendingRecoveryPage _pending() => LocalPendingRecoveryPage(
    english: widget.english,
    load: () async {
      _scope();
      final resolver = LocalRecoveryResolver(
        store: store,
        inventory: await _inventory(),
      );
      final resolution = await resolver.read();
      _scope();
      return LocalPendingRecoveryView(resolution.summary, [
        for (final record in resolution.records)
          LocalPendingRecoveryItem(
            reference: record.reference,
            archived: record.archived,
            title: record.destination?.kind == 'article-create-archive'
                ? t('旧版新建文章草稿', 'Old new-article draft')
                : record.archived
                ? (record.destination?.title.isNotEmpty == true
                      ? record.destination!.title + t(' · 旧稿', ' · Old draft')
                      : t('旧文章草稿', 'Old article draft'))
                : record.destination == null
                ? t('暂时无法定位的恢复记录', 'Recovery record cannot be located')
                : _draftTitle(record.destination!),
            detail: record.archived
                ? record.archivedCreationDisposition != null
                      ? _creationArchiveStatus(
                          record.archivedCreationDisposition!,
                        )
                      : _archiveStatus(record.archivedDisposition!)
                : record.destination == null
                ? t(
                    '记录已保留，暂不能切换本地数据。',
                    'Record retained; local data cannot switch yet.',
                  )
                : t(
                    '打开对应页面继续处理，未确认的提交先只读核对。',
                    'Continue in the original editor; review uncertain submissions first.',
                  ),
            actionLabel: record.archived
                ? t('查看旧草稿', 'View old draft')
                : {
                    'html-create',
                    'article-create',
                    'document-create',
                  }.contains(record.destination?.kind)
                ? t('继续处理', 'Continue')
                : null,
            open: record.destination == null
                ? null
                : () async {
                    await _writable();
                    final fresh = await resolver.read();
                    final matches = fresh.records.where(
                      (item) =>
                          item.reference.key == record.reference.key &&
                          item.reference.store == record.reference.store,
                    );
                    if (matches.length != 1 ||
                        matches.single.destination == null ||
                        matches.single.archived != record.archived ||
                        matches.single.destination!.kind !=
                            record.destination!.kind) {
                      throw StateError('Recovery resource scope changed');
                    }
                    _scope();
                    if (!mounted) return;
                    await widget.openDraft(
                      _navigator.currentState!.overlay!.context,
                      matches.single.destination!,
                    );
                  },
          ),
      ]);
    },
  );
  LocalRecoveryPage _recovery() => LocalRecoveryPage(
    english: widget.english,
    onBack: () async {
      if (_navigator.currentState!.canPop()) {
        await _navigator.currentState!.maybePop();
      } else {
        _scope();
        await widget.onConnection();
      }
    },
    load: () {
      _scope();
      return control.readState();
    },
    reviewApplied: (selected) {
      _scope();
      return LocalAppliedBackupReviewer(
        control: control,
        privateSupport: widget.session.privateSupport,
        privateCache: widget.privateCache,
        factory: widget.session.factory ?? databaseFactory,
      ).read(selected);
    },
    finishUnapplied: (selected) async {
      _scope();
      final intent = selected.observation.intent;
      if (!selected.observation.canFinishUnapplied || intent == null) {
        throw StateError('Unapplied intent must be reviewed first');
      }
      return (await control.finishUnapplied(intent)).state;
    },
    acknowledge: (review) async {
      _scope();
      final receipt = await control.acknowledgeApplied(review.intent);
      _scope();
      await widget.onEntered(receipt);
    },
    reenter: (selected) async {
      _scope();
      final receipt = selected.observation.canReenterUnchangedSource
          ? await control.reenterUnchangedSource(selected)
          : await control.reenterReadySource(selected);
      _scope();
      await widget.onEntered(receipt);
    },
    openRetained: _catalog,
    returnToConnection: () {
      _scope();
      return widget.onConnection();
    },
  );
  Future<void> _catalog() async {
    _scope();
    final state = await control.readState();
    final canRestore =
        !state.observation.needsReview &&
        (widget.owned15 != null
            ? widget.owned15!.current &&
                  state.observation.pointer?.generation ==
                      widget.owned15!.pointer.generation
            : widget.store != null &&
                  !store.maintenance.retired &&
                  state.observation.pointer?.generation ==
                      store.dataPaths!.generationId);
    await _push(
      LocalRetentionCatalogPage(
        english: widget.english,
        canRestore: canRestore,
        load: () {
          _scope();
          return control.listRetained();
        },
        inspect: (retained) {
          _scope();
          return _importer.inspectRetained(retained);
        },
        restore: (candidate) async {
          await _writable();
          await _push(_backup(candidate));
        },
      ),
    );
  }

  @override
  void dispose() {
    _inspectionCancellation?.cancel();
    unawaited(_picker.dispose().catchError((Object _) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => NavigatorPopHandler<Object?>(
    onPopWithResult: (_) => _navigator.currentState!.maybePop(),
    child: Navigator(
      key: _navigator,
      onGenerateRoute: (_) => MaterialPageRoute(
        builder: (_) => widget.recoveryOnly ? _recovery() : _backup(),
      ),
    ),
  );
}
