import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/complex_editor_document.dart';
import '../../core/local_article_draft_archive.dart';
import '../../core/local_recovery_namespaces.dart';
import '../../core/local_store.dart';
import '../../core/native_recovery_storage.dart';
import '../../core/secure_record_store.dart';
import 'local_article_draft_archive_page.dart';
import 'open_local_complex_note.dart';

Future<void> openLocalArticleDraftArchive(
  BuildContext context, {
  required LocalStore store,
  required String namespace,
  required int id,
  bool english = false,
  bool Function()? isCurrentScope,
}) async {
  bool current() {
    if (!context.mounted || store.maintenance.retired) return false;
    try {
      return isCurrentScope?.call() ?? true;
    } catch (_) {
      return false;
    }
  }

  if (!current() || id <= 0) throw StateError('Article archive unavailable');
  const storage = FlutterSecureStorage(
    aOptions: AndroidOptions(sharedPreferencesName: 'FlutterSecureStorage'),
  );
  final namespaces = await localRecoveryNamespaces(store.dataPaths!);
  if (!current()) throw StateError('Archive space changed');
  final records = SecureRecordStore(
    prefix: 'bookstark.draft.v1',
    namespace: namespace,
    readValue: (key) => storage.read(key: key),
    writeValue: (_, _) async => throw StateError('Archive access is read-only'),
    deleteValue: (_) async => throw StateError('Archive access is read-only'),
  );
  final reader = LocalArticleDraftArchiveReader(
    maintenance: store.maintenance,
    ownedNamespaces: namespaces,
    readValue: (key) => storage.read(key: key),
    fingerprintDraft: NativeRecoveryStorage.localArticleDraftFingerprint,
    isCurrentScope: current,
  );
  final key = records.metadataKey(id);
  final snapshot = await reader.read(key);
  if (!context.mounted || !current()) return;

  Future<bool> targetAvailable() => store.maintenance.use(() async {
    if (!current() ||
        kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android ||
        namespace != jsonEncode([store.dataPaths!.draftNamespace, 'article'])) {
      return false;
    }
    final rows = await (await store.database).query(
      'notes',
      columns: ['editor_type'],
      where: "id = ? AND collection = 'article' AND deleted = 0",
      whereArgs: [id],
    );
    return current() &&
        rows.length == 1 &&
        rows.single['editor_type'] == 'markdown';
  });

  final canRestore = await targetAvailable();
  if (!context.mounted || !current()) return;
  final approval = await Navigator.push<LocalArticleDraftRestoreApproval>(
    context,
    MaterialPageRoute(
      builder: (_) => LocalArticleDraftArchivePage(
        archive: snapshot,
        english: english,
        isCurrentScope: current,
        prepareRestore: canRestore
            ? () async {
                if (!await targetAvailable()) {
                  throw StateError('Original article unavailable');
                }
                final fresh = await reader.read(key);
                if (!current() ||
                    fresh.receipt.digest != snapshot.receipt.digest ||
                    fresh.receipt.ciphertextSHA256 !=
                        snapshot.receipt.ciphertextSHA256) {
                  throw StateError('Archived draft changed after review');
                }
                return LocalArticleDraftRestoreApproval.fromArchive(fresh);
              }
            : null,
      ),
    ),
  );
  if (!context.mounted || !current() || approval == null) return;
  if (!await targetAvailable()) {
    throw StateError('Original article unavailable');
  }
  if (!context.mounted || !current()) return;
  await openLocalComplexNote(
    context,
    store: store,
    id: id,
    collection: 'article',
    kind: ComplexEditorKind.markdown,
    english: english,
    forceLegacyReview: true,
    approvedLegacyDraft: approval,
    isCurrentScope: current,
  );
}
