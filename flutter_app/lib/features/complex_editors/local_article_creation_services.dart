import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/complex_editor_document.dart';
import '../../core/complex_recovery_store.dart';
import '../../core/draft_vault.dart';
import '../../core/local_article_creation_legacy_handoff.dart';
import '../../core/local_article_creation_record.dart';
import '../../core/local_complex_notes_repository.dart';
import '../../core/local_store.dart';
import '../../core/native_recovery_storage.dart';

/// Same production scope and ownership checks with injectable storage boundaries.
class LocalArticleCreationServices {
  LocalArticleCreationServices._({
    required this.store,
    required this.repository,
    required this.vault,
    required this.legacy,
    required this.fingerprint,
    required this.flush,
  });
  factory LocalArticleCreationServices.forStore(
    LocalStore store, {
    DraftVault? legacy,
    ComplexRecoveryBytesStore? byteStore,
    Future<String?> Function(String key)? fingerprint,
    Future<void> Function()? flush,
  }) {
    final paths = store.dataPaths;
    if (paths == null) {
      throw ArgumentError('Owned local article storage required');
    }
    final namespace = jsonEncode([paths.draftNamespace, 'article']);
    const storage = FlutterSecureStorage(
      aOptions: AndroidOptions(sharedPreferencesName: 'FlutterSecureStorage'),
    );
    final old =
        legacy ??
        DraftVault(
          namespace: namespace,
          maintenance: store.maintenance,
          readValue: (key) => storage.read(key: key),
          writeValue: (key, value) => storage.write(key: key, value: value),
          deleteValue: (key) => storage.delete(key: key),
        );
    if (old.namespace != namespace ||
        !identical(old.maintenance, store.maintenance)) {
      throw ArgumentError('Current owned article draft storage required');
    }
    final repository = LocalComplexNotesRepository(
      store,
      kind: ComplexEditorKind.markdown,
      collection: 'article',
    );
    return LocalArticleCreationServices._(
      store: store,
      repository: repository,
      vault: LocalArticleCreationVault(
        scope: repository.scope,
        store: byteStore ?? NativeComplexRecoveryStore(),
        maintenance: store.maintenance,
      ),
      legacy: old,
      fingerprint:
          fingerprint ??
          NativeRecoveryStorage.localArticleCreationDraftFingerprint,
      flush: flush ?? NativeRecoveryStorage.flush,
    );
  }
  final LocalStore store;
  final LocalComplexNotesRepository repository;
  final LocalArticleCreationVault vault;
  final DraftVault legacy;
  final Future<String?> Function(String key) fingerprint;
  final Future<void> Function() flush;
  LocalArticleCreationLegacyHandoff handoff(bool Function() current) =>
      LocalArticleCreationLegacyHandoff(
        legacy: legacy,
        expectedLegacyNamespace: legacy.namespace,
        ownedNamespaces: {store.dataPaths!.draftNamespace},
        vault: vault,
        repository: repository,
        maintenance: store.maintenance,
        fingerprintLegacyDraft: () => fingerprint(legacy.metadataKey(null)),
        flushMarker: flush,
        isCurrentScope: current,
      );
  LocalArticleCreationLegacyReader archiveReader({
    required String namespace,
    required Set<String> ownedNamespaces,
    required bool Function() isCurrentScope,
  }) {
    final readonly = DraftVault(
      namespace: namespace,
      maintenance: store.maintenance,
      readValue: legacy.readValue,
      writeValue: (_, _) async =>
          throw StateError('Archive access is read-only'),
      deleteValue: (_) async => throw StateError('Archive access is read-only'),
    );
    return LocalArticleCreationLegacyReader(
      legacy: readonly,
      expectedLegacyNamespace: namespace,
      ownedNamespaces: ownedNamespaces,
      maintenance: store.maintenance,
      fingerprintLegacyDraft: () => fingerprint(readonly.metadataKey(null)),
      flushMarker: flush,
      isCurrentScope: isCurrentScope,
    );
  }

  void dispose() => repository.dispose();
}
