import 'dart:async';
import 'package:bookstark_flutter/core/attachments.dart';
// Synthetic UI fixtures only. No native filesystem, SQLite, backup or restore
// proof. Production pages are reused; all mutation callbacks are inert.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:bookstark_flutter/core/app_theme.dart';
import 'package:bookstark_flutter/core/local_applied_backup_review.dart';
import 'package:bookstark_flutter/core/local_backup_codec.dart';
import 'package:bookstark_flutter/core/local_backup_content.dart';
import 'package:bookstark_flutter/core/local_backup_importer.dart';
import 'package:bookstark_flutter/core/local_generation_state.dart';
import 'package:bookstark_flutter/core/local_recovery_inventory.dart';
import 'package:bookstark_flutter/core/native_local_data_control.dart';
import 'package:bookstark_flutter/features/local_backup/local_backup_page.dart';
import 'package:bookstark_flutter/features/local_backup/local_pending_recovery_page.dart';
import 'package:bookstark_flutter/features/local_backup/local_recovery_page.dart';
import 'package:bookstark_flutter/features/local_backup/local_retention_catalog_page.dart';

final _manifest = LocalBackupManifest(
  id: 'a' * 32,
  createdAt: '2026-11-08T10:20:00.000Z',
  sqliteVersion: '3.42.0',
  tables: {
    for (final table in LocalBackupManifest.requiredTables)
      table: table == 'notes'
          ? 24
          : table == 'books'
          ? 3
          : table == 'trash_entries'
          ? 2
          : 0,
  },
  files: [
    LocalBackupFile(
      path: 'database/content.db',
      bytes: 8 * 1024 * 1024,
      sha256: 'b' * 64,
    ),
    for (var i = 1; i <= 12; i++)
      LocalBackupFile(
        path: 'attachments/${i.toRadixString(16).padLeft(32, '0')}',
        bytes: 32768,
        sha256: 'c' * 64,
      ),
  ],
);
const _report = LocalBackupContentReport(
  disabledHtmlBindings: 0,
  unavailableReferences: 0,
  pendingImageCleanup: 0,
);
final _bytes =
    12 +
    utf8.encode(jsonEncode(_manifest.toJson())).length +
    _manifest.totalBytes;
final _intent = LocalRestoreIntent(
  operationId: 'a' * 32,
  sourcePointerRaw: null,
  retainedId: 'b' * 32,
  retainedManifestSHA256: 'c' * 64,
  targetPointerRaw: LocalGenerationPointer(
    generation: 'd' * 32,
    epoch: 1,
    activationId: 'a' * 32,
    sourceSHA256: 'e' * 64,
  ).encode(),
);
final _retention = LocalRetention(
  id: _intent.retainedId,
  sourcePointerSHA256: _intent.sourcePointerSHA256,
  sourceGeneration: 'legacy',
  manifestSHA256: _intent.retainedManifestSHA256,
);

class _VisualCandidate implements LocalBackupCandidate {
  @override
  String get id => 'd' * 32;
  @override
  LocalBackupManifest get manifest => _manifest;
  @override
  LocalBackupContentReport get contentReport => _report;
  @override
  int get sourceBytes => _bytes;
  @override
  Future<void> discardUnprepared() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Visual fixture has no storage');
}

class _VisualReview implements ReviewedLocalAppliedBackup {
  @override
  LocalRestoreIntent get intent => _intent;
  @override
  LocalBackupManifest get manifest => _manifest;
  @override
  LocalBackupContentReport get contentReport => _report;
  @override
  int get bytes => _bytes;
}

Future<LocalDataControlState> _state(String mode) => NativeLocalDataControl(
  invoke: (_, _) async {
    if (mode == 'inconsistent') throw StateError('Visual unreadable state');
    final switched = mode == 'switched' || mode == 'review';
    final pending = mode == 'prepared' || switched;
    return {
      'format': 1,
      'pointerRaw': switched ? _intent.targetPointerRaw : null,
      'intentRaw': pending ? _intent.encode() : null,
      'currentRetentionRaw': switched || mode == 'ready'
          ? null
          : _retention.encode(),
      'sourceRetentionRaw': pending ? _retention.encode() : null,
      'metadataOnly': true,
    };
  },
).readState();

void main() {
  final query = Uri.base.queryParameters;
  final screen = query['screen'] ?? 'home';
  final english = query['lang'] == 'en';
  final scale = double.tryParse(query['scale'] ?? '') ?? 1;
  final candidate = _VisualCandidate();
  final pendingInspection = Completer<LocalBackupCandidate?>();
  final summary = LocalRecoverySummary(
    references: const [],
    complexKeys: const [],
    unknown: 0,
    activeTransfers: 0,
    overflow: false,
  );
  Future<void> inert() async {}
  late Widget page;
  if (screen == 'pending') {
    page = LocalPendingRecoveryPage(
      english: english,
      load: () async => LocalPendingRecoveryView(
        LocalRecoverySummary(
          references: const [
            LocalRecoveryReference(
              store: 'secure',
              kind: 'note',
              key: 'visual-only',
            ),
          ],
          complexKeys: const [],
          unknown: 0,
          activeTransfers: 0,
          overflow: false,
        ),
        [
          LocalPendingRecoveryItem(
            title: english ? 'Notes · Reading excerpt' : '笔记 · 阅读摘录',
            detail: english ? 'Unsaved content' : '未保存的正文',
            reference: null,
            open: inert,
          ),
          LocalPendingRecoveryItem(
            title: english ? 'HTML · New draft' : 'HTML · 新建草稿',
            detail: english ? 'Not created yet' : '尚未创建',
            actionLabel: english ? 'Continue' : '继续处理',
            reference: null,
            open: inert,
          ),
        ],
      ),
    );
  } else if (screen == 'catalog') {
    final control = NativeLocalDataControl(
      invoke: (_, _) async => {
        'format': 1,
        'retentions': [_retention.encode()],
        'unknown': 0,
        'overflow': false,
        'metadataOnly': true,
      },
    );
    page = LocalRetentionCatalogPage(
      english: english,
      canRestore: true,
      load: control.listRetained,
      inspect: (_) async => candidate,
      restore: (_) => inert(),
    );
  } else if ([
    'prepared',
    'retained',
    'switched',
    'review',
    'inconsistent',
    'ready',
  ].contains(screen)) {
    page = LocalRecoveryPage(
      english: english,
      load: () => _state(screen),
      reviewApplied: (_) async => _VisualReview(),
      finishUnapplied: (_) => _state('retained'),
      acknowledge: (_) => inert(),
      reenter: (_) => inert(),
      openRetained: inert,
      returnToConnection: inert,
    );
  } else {
    page = LocalBackupPage(
      english: english,
      initialCandidate: ['checked', 'scope'].contains(screen)
          ? candidate
          : null,
      createExport: () async => throw PendingLocalRecovery(summary),
      saveExport: (_) async => throw UnsupportedError('Visual only'),
      inspectPicked: () async {
        if (screen == 'checking') return await pendingInspection.future;
        return candidate;
      },
      cancelInspection: () async {
        if (!pendingInspection.isCompleted) {
          pendingInspection.completeError(const AttachmentCancelled());
        }
      },
      apply: (_) => inert(),
      openRecovery: inert,
      openPending: (_) => inert(),
      openRetained: inert,
      openLegacyMigration: inert,
    );
  }
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: bookstarkTheme(),
      locale: Locale(english ? 'en' : 'zh'),
      supportedLocales: const [Locale('zh'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: page,
    ),
  );
}
