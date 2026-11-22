import 'local_task_creation_metadata.dart';
import 'task_creation_metadata.dart';
import 'local_label_creation_metadata.dart';
import 'label_creation_metadata.dart';
import 'topic_creation_metadata.dart';
import 'bookmark_creation_metadata.dart';
import 'owned15_save_marker_metadata.dart';
import 'owned15_creation_marker_metadata.dart';
import 'protected_owned_marker_metadata.dart';
import 'local_assistant_write_journal.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'complex_recovery_store.dart';
import 'local_data_maintenance.dart';
import 'local_draft_namespace.dart';
import 'native_recovery_storage.dart';
import 'local_article_draft_receipt.dart';
import 'local_article_creation_legacy_metadata.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class LocalRecoveryReference {
  const LocalRecoveryReference({
    required this.store,
    required this.kind,
    required this.key,
    this.namespace,
    this.recordId,
  });
  final String store, kind, key;
  final String? namespace;
  final Object? recordId;
}

class LocalArchivedArticleDraft {
  const LocalArchivedArticleDraft(this.reference, this.disposition);
  final LocalRecoveryReference reference;
  final LocalArticleDraftDisposition disposition;
}

class LocalArchivedArticleCreationDraft {
  const LocalArchivedArticleCreationDraft(
    this.reference,
    this.disposition,
    this.creationKey,
  );
  final LocalRecoveryReference reference;
  final LocalArticleCreationLegacyDisposition disposition;
  final String? creationKey;
}

class LocalRecoverySummary {
  LocalRecoverySummary({
    required List<LocalRecoveryReference> references,
    required List<String> complexKeys,
    required this.unknown,
    required this.activeTransfers,
    required this.overflow,
    List<LocalArchivedArticleDraft> archivedArticles = const [],
    List<LocalArchivedArticleCreationDraft> archivedCreations = const [],
  }) : archivedCreations = List.unmodifiable(archivedCreations),
       archivedArticles = List.unmodifiable(archivedArticles),
       references = List.unmodifiable(references),
       complexKeys = List.unmodifiable(complexKeys);
  final List<LocalRecoveryReference> references;
  final List<LocalArchivedArticleDraft> archivedArticles;
  final List<LocalArchivedArticleCreationDraft> archivedCreations;
  final List<String> complexKeys;
  final int unknown, activeTransfers;
  final bool overflow;
  bool get needsAttention =>
      references.isNotEmpty ||
      complexKeys.isNotEmpty ||
      unknown != 0 ||
      activeTransfers != 0 ||
      overflow;
  void requireClear() {
    if (needsAttention) throw PendingLocalRecovery(this);
  }
}

class PendingLocalRecovery implements Exception {
  const PendingLocalRecovery(this.summary);
  final LocalRecoverySummary summary;
  @override
  String toString() =>
      'Local recovery records need attention before backup or restore';
}

/// Returns identifiers only. Never reads/decrypts record bodies or account data.
/// Lease acquisition precedes the native barriers and both metadata snapshots.
class LocalRecoveryInventory {
  LocalRecoveryInventory({
    required this.maintenance,
    required Set<String> localNamespaces,
    Future<Object?> Function()? preferencesMetadata,
    Future<Object?> Function()? complexMetadata,
    Future<String?> Function(String key)? readArticleReceipt,
    Future<String?> Function(String key)? fingerprintArticleDraft,
    Future<String?> Function(String key)? readArticleCreationReceipt,
    Future<String?> Function(String key)? fingerprintArticleCreationDraft,
  }) : localNamespaces = Set.unmodifiable(localNamespaces),
       _readArticleCreationReceipt =
           readArticleCreationReceipt ??
           ((key) => _receiptStorage.read(key: key)),
       _fingerprintArticleCreationDraft =
           fingerprintArticleCreationDraft ??
           NativeRecoveryStorage.localArticleCreationDraftFingerprint,
       _readArticleReceipt =
           readArticleReceipt ?? ((key) => _receiptStorage.read(key: key)),
       _fingerprintArticleDraft =
           fingerprintArticleDraft ??
           NativeRecoveryStorage.localArticleDraftFingerprint,
       _preferences =
           preferencesMetadata ??
           (() => NativeRecoveryStorage.channel.invokeMethod<Object?>(
             'localMetadata',
           )),
       _complex =
           complexMetadata ??
           (() => NativeComplexRecoveryStore.channel.invokeMethod<Object?>(
             'metadata',
           )) {
    if (localNamespaces.isEmpty ||
        localNamespaces.any(
          (namespace) => !LocalDraftNamespace.isLocal(namespace),
        )) {
      throw const FormatException('Owned local recovery namespaces required');
    }
  }
  static const _receiptStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(sharedPreferencesName: 'FlutterSecureStorage'),
  );
  final Future<String?> Function(String key) _readArticleReceipt;
  final Future<String?> Function(String key) _readArticleCreationReceipt;
  final Future<String?> Function(String key) _fingerprintArticleCreationDraft;
  final Future<String?> Function(String key) _fingerprintArticleDraft;
  final LocalDataMaintenance maintenance;
  final Set<String> localNamespaces;
  final Future<Object?> Function() _preferences, _complex;

  static const _prefixes = {
    'bookstark.draft.v1.': 'note',
    'bookstark.file-draft.v1.': 'file',
    'bookstark.topic-draft.v1.': 'topic',
    'bookstark.bookmark-draft.v1.': 'bookmark',
    'bookstark.book-draft.v1.': 'book',
    'bookstark.task-draft.v1.': 'task',
    'bookstark.local-html-recovery.v1.': 'html',
    'bookstark.local-html-create.v1.': 'html-create',
    LocalAssistantWriteMarker.prefix: 'ai-create',
  };
  static const _documentPrefix = 'bookstark.document-create.v1.';

  void _active() {
    if (maintenance.retired) {
      throw StateError('Recovery inventory scope retired');
    }
  }

  Future<LocalRecoverySummary> read() => maintenance.exclusive(() async {
    final values = await Future.wait([_preferences(), _complex()]);
    _active();
    final prefs = _map(values[0], {
      'format',
      'secureKeys',
      'htmlKeys',
      'overflow',
      'valuesIncluded',
    });
    final complex = _map(values[1], {
      'format',
      'keys',
      'unknownFiles',
      'overflow',
      'activeTransfers',
      'valuesIncluded',
    });
    final secureKeys = _keys(prefs['secureKeys']);
    final htmlKeys = _keys(prefs['htmlKeys']);
    final complexKeys = _keys(complex['keys']);
    if (complexKeys.any((key) => !RegExp(r'^[a-f0-9]{64}$').hasMatch(key))) {
      throw const FormatException('Invalid complex recovery metadata');
    }
    final unknownFiles = complex['unknownFiles'],
        transfers = complex['activeTransfers'];
    if (unknownFiles is! int ||
        unknownFiles < 0 ||
        unknownFiles > 1000000 ||
        transfers is! int ||
        transfers < 0 ||
        transfers > 10000) {
      throw const FormatException('Invalid recovery transfer metadata');
    }
    final documentKeys = {
      for (final namespace in localNamespaces)
        '$_documentPrefix${sha256.convert(utf8.encode(namespace))}': namespace,
    };
    final references = <LocalRecoveryReference>[];
    var unknown = unknownFiles;
    final archived = <String, LocalArchivedArticleDraft>{};
    final archivedCreations = <String, LocalArchivedArticleCreationDraft>{};
    // Only receipt metadata is decrypted here. The legacy draft body and
    // account preferences are never read by this inventory.
    for (final key in secureKeys.where(
      (key) => key.startsWith(LocalArticleDraftReceipt.keyPrefix),
    )) {
      _active();
      try {
        final scope = LocalArticleDraftReceiptScope.parse(key, localNamespaces);
        final raw = await _readArticleReceipt(key);
        _active();
        if (raw == null) throw const FormatException('Missing article receipt');
        final receipt = LocalArticleDraftReceipt.parse(raw);
        if (receipt.ciphertextSHA256 == null ||
            !secureKeys.contains(scope.legacyKey)) {
          continue;
        }
        final fingerprint = await _fingerprintArticleDraft(scope.legacyKey);
        _active();
        if (fingerprint != receipt.ciphertextSHA256) continue;
        archived[scope.legacyKey] = LocalArchivedArticleDraft(
          LocalRecoveryReference(
            store: 'secure',
            kind: 'article-archive',
            key: scope.legacyKey,
            namespace: scope.namespace,
            recordId: scope.id,
          ),
          receipt.disposition,
        );
      } catch (_) {
        if (maintenance.retired) rethrow;
        unknown++;
      }
    }
    for (final key in secureKeys.where(
      (key) => key.startsWith(LocalArticleCreationLegacyScope.markerPrefix),
    )) {
      _active();
      try {
        final scope = LocalArticleCreationLegacyScope.fromMarkerKey(
          key,
          localNamespaces,
        );
        final raw = await _readArticleCreationReceipt(key);
        _active();
        if (raw == null) {
          throw const FormatException('Missing new-article receipt');
        }
        final receipt = LocalArticleCreationLegacyReceipt.parse(raw);
        if (!secureKeys.contains(scope.legacyKey)) continue;
        final fingerprint = await _fingerprintArticleCreationDraft(
          scope.legacyKey,
        );
        _active();
        if (fingerprint != receipt.ciphertextSHA256) continue;
        archivedCreations[scope.legacyKey] = LocalArchivedArticleCreationDraft(
          LocalRecoveryReference(
            store: 'secure',
            kind: 'article-create-archive',
            key: scope.legacyKey,
            namespace: scope.namespace,
          ),
          receipt.disposition,
          receipt.creationKey,
        );
      } catch (_) {
        if (maintenance.retired) rethrow;
        unknown++;
      }
    }
    for (final entry in {'secure': secureKeys, 'html': htmlKeys}.entries) {
      for (final key in entry.value) {
        if (entry.key == 'secure' &&
            (key.startsWith(LocalArticleDraftReceipt.keyPrefix) ||
                key.startsWith(LocalArticleCreationLegacyScope.markerPrefix) ||
                archived.containsKey(key) ||
                archivedCreations.containsKey(key))) {
          continue;
        }
        // Upload markers are account/document opaque identities, across all
        // owners. Keys prove no phase/URL/receipt and values are never read here.
        const imageUploadPrefix = 'bookstark.owned-image-upload.v1.';
        if (key.startsWith(imageUploadPrefix)) {
          try {
            if (entry.key != 'secure' || key.length > 4096) {
              throw const FormatException('Upload marker storage mismatch');
            }
            final suffix = key.substring(imageUploadPrefix.length);
            final decoded = jsonDecode(utf8.decode(base64Url.decode(suffix)));
            if (decoded is! List ||
                decoded.length != 2 ||
                decoded.any(
                  (part) =>
                      part is! String ||
                      !RegExp(r'^[a-f0-9]{64}$').hasMatch(part),
                ) ||
                base64Url.encode(utf8.encode(jsonEncode(decoded))) != suffix) {
              throw const FormatException('Invalid upload marker identity');
            }
            references.add(
              LocalRecoveryReference(
                store: entry.key,
                kind: 'owned-image-upload',
                key: key,
                namespace: decoded[0] as String,
                recordId: decoded[1],
              ),
            );
          } catch (_) {
            unknown++;
          }
          continue;
        }
        if (key.startsWith(BookmarkCreationMetadata.recordPrefix) ||
            key.startsWith(BookmarkCreationMetadata.slotPrefix)) {
          try {
            if (entry.key != 'secure') {
              throw const FormatException('Bookmark creation store mismatch');
            }
            final metadata = BookmarkCreationMetadata.parse(key);
            references.add(
              LocalRecoveryReference(
                store: entry.key,
                kind: metadata.slot
                    ? 'bookmark-create-slot'
                    : 'bookmark-create',
                key: key,
                namespace: metadata.scope,
                recordId: metadata.identity,
              ),
            );
          } catch (_) {
            unknown++;
          }
          continue;
        }
        if (key.startsWith(TopicCreationMetadata.recordPrefix) ||
            key.startsWith(TopicCreationMetadata.slotPrefix)) {
          try {
            if (entry.key != 'secure') {
              throw const FormatException('Creation storage mismatch');
            }
            final parsed = TopicCreationMetadata.parse(key);
            references.add(
              LocalRecoveryReference(
                store: entry.key,
                kind: parsed.slot ? 'topic-create-slot' : 'topic-create',
                key: key,
                namespace: parsed.scope,
                recordId: parsed.identity,
              ),
            );
          } catch (_) {
            unknown++;
          }
          continue;
        }
        if (key.startsWith(LocalLabelCreationMetadata.recordPrefix) ||
            key.startsWith(LocalLabelCreationMetadata.slotPrefix)) {
          try {
            if (entry.key != 'secure') {
              throw const FormatException(
                'Local label creation store mismatch',
              );
            }
            final metadata = LocalLabelCreationMetadata.parse(key);
            references.add(
              LocalRecoveryReference(
                store: entry.key,
                kind: metadata.slot
                    ? 'local-label-create-slot'
                    : 'local-label-create',
                key: key,
                namespace: metadata.scope,
                recordId: metadata.identity,
              ),
            );
          } catch (_) {
            unknown++;
          }
          continue;
        }
        if (key.startsWith(LocalTaskCreationMetadata.recordPrefix) ||
            key.startsWith(LocalTaskCreationMetadata.slotPrefix)) {
          try {
            if (entry.key != 'secure') {
              throw const FormatException('Task creation store mismatch');
            }
            final metadata = LocalTaskCreationMetadata.parse(key);
            references.add(
              LocalRecoveryReference(
                store: entry.key,
                kind: metadata.slot
                    ? 'local-task-create-slot'
                    : 'local-task-create',
                key: key,
                namespace: metadata.scope,
                recordId: metadata.identity,
              ),
            );
          } catch (_) {
            unknown++;
          }
          continue;
        }
        if (key.startsWith(TaskCreationMetadata.recordPrefix) ||
            key.startsWith(TaskCreationMetadata.slotPrefix)) {
          try {
            if (entry.key != 'secure') {
              throw const FormatException('Task creation store mismatch');
            }
            final metadata = TaskCreationMetadata.parse(key);
            references.add(
              LocalRecoveryReference(
                store: entry.key,
                kind: metadata.slot ? 'task-create-slot' : 'task-create',
                key: key,
                namespace: metadata.scope,
                recordId: metadata.identity,
              ),
            );
          } catch (_) {
            unknown++;
          }
          continue;
        }
        if (key.startsWith(LabelCreationMetadata.recordPrefix) ||
            key.startsWith(LabelCreationMetadata.slotPrefix)) {
          try {
            if (entry.key != 'secure') {
              throw const FormatException('Label creation store mismatch');
            }
            final metadata = LabelCreationMetadata.parse(key);
            references.add(
              LocalRecoveryReference(
                store: entry.key,
                kind: metadata.slot ? 'label-create-slot' : 'label-create',
                key: key,
                namespace: metadata.scope,
                recordId: metadata.identity,
              ),
            );
          } catch (_) {
            unknown++;
          }
          continue;
        }
        // Frozen shared key contract: opaque 64-hex principal only.
        const sharedMarkerPrefix = 'bookstark.protectedSharedOp.v1.';
        if (key.startsWith(sharedMarkerPrefix)) {
          final principal = key.substring(sharedMarkerPrefix.length);
          if (entry.key != 'secure' ||
              !RegExp(r'^[a-f0-9]{64}$').hasMatch(principal)) {
            unknown++;
          } else {
            references.add(
              LocalRecoveryReference(
                store: entry.key,
                kind: 'protected-shared',
                key: key,
                namespace: principal,
                recordId: 0,
              ),
            );
          }
          continue;
        }
        if (key.startsWith(Owned15CreationMarkerMetadata.prefix)) {
          try {
            if (entry.key != 'secure') {
              throw const FormatException('Creation marker in wrong storage');
            }
            final marker = Owned15CreationMarkerMetadata.parse(key);
            references.add(
              LocalRecoveryReference(
                store: entry.key,
                kind: 'owned15-create',
                key: key,
                namespace: marker.ownerTag,
                recordId: 0,
              ),
            );
          } on FormatException {
            unknown++;
          }
          continue;
        }
        if (key.startsWith(Owned15SaveMarkerMetadata.prefix)) {
          try {
            if (entry.key != 'secure') {
              throw const FormatException('Owned15 marker in wrong storage');
            }
            final marker = Owned15SaveMarkerMetadata.parse(key);
            // All-owner keys-only presence. This does not establish a phase,
            // full stored tuple, plaintext snapshot or SQLite save receipt.
            references.add(
              LocalRecoveryReference(
                store: entry.key,
                kind: 'owned15-save',
                key: key,
                namespace: jsonEncode([marker.ownerTag, marker.scope]),
                recordId: 0,
              ),
            );
          } on FormatException {
            unknown++;
          }
          continue;
        }
        if (key.startsWith(ProtectedOwnedMarkerMetadata.keyPrefix)) {
          try {
            if (entry.key != 'secure') {
              throw const FormatException('Protected marker in wrong storage');
            }
            final marker = ProtectedOwnedMarkerMetadata.parse(key);
            // Keys prove neither journal phase nor any server/SQL receipt.
            references.add(
              LocalRecoveryReference(
                store: entry.key,
                kind: 'protected-owned',
                key: key,
                namespace: jsonEncode([marker.ownerTag, marker.scope]),
                recordId: 0,
              ),
            );
          } on FormatException {
            unknown++;
          }
          continue;
        }
        if (key.startsWith(_documentPrefix)) {
          if (!RegExp(
            r'^[a-f0-9]{64}$',
          ).hasMatch(key.substring(_documentPrefix.length))) {
            unknown++;
            continue;
          }
          final namespace = documentKeys[key];
          if (namespace != null) {
            references.add(
              LocalRecoveryReference(
                store: entry.key,
                kind: 'document-create',
                key: key,
                namespace: namespace,
              ),
            );
          } else {
            // Old hashed keys do not reveal local versus remote ownership.
            // Preserve and block rather than silently omit an orphan journal.
            unknown++;
          }
          continue;
        }
        final prefix = _prefixes.keys.where(key.startsWith).firstOrNull;
        if (prefix == null) {
          // Native bridge includes unknown bookstark.local-* keys so they can
          // never silently disappear from local preflight.
          unknown++;
          continue;
        }
        try {
          final decoded = jsonDecode(
            utf8.decode(base64Url.decode(key.substring(prefix.length))),
          );
          if (decoded is! List ||
              decoded.length != 2 ||
              decoded.first is! String ||
              (decoded[1] != null &&
                  decoded[1] is! int &&
                  decoded[1] is! String)) {
            throw const FormatException('Invalid recovery key scope');
          }
          if (prefix == LocalAssistantWriteMarker.prefix) {
            LocalAssistantWriteMarker.fromKey(key);
          }
          final namespace = decoded.first as String;
          if (namespace.length > 32768) {
            throw const FormatException('Oversized recovery namespace');
          }
          if (!prefix.startsWith('bookstark.local-') &&
              !LocalDraftNamespace.isLocal(namespace)) {
            continue;
          }
          references.add(
            LocalRecoveryReference(
              store: entry.key,
              kind: _prefixes[prefix]!,
              key: key,
              namespace: namespace,
              recordId: decoded[1],
            ),
          );
        } on FormatException {
          unknown++;
        }
      }
    }
    _active();
    return LocalRecoverySummary(
      references: references,
      archivedArticles: archived.values.toList(),
      archivedCreations: archivedCreations.values.toList(),
      complexKeys: complexKeys,
      unknown: unknown,
      activeTransfers: transfers,
      overflow: (prefs['overflow'] as bool) || (complex['overflow'] as bool),
    );
  });

  Map<String, Object?> _map(Object? value, Set<String> expected) {
    if (value is! Map || value.keys.any((key) => key is! String)) {
      throw const FormatException('Invalid recovery inventory metadata');
    }
    final result = value.cast<String, Object?>();
    if (result.length != expected.length ||
        !result.keys.toSet().containsAll(expected) ||
        result['format'] is! int ||
        result['format'] != 1 ||
        result['valuesIncluded'] != false ||
        result['overflow'] is! bool) {
      throw const FormatException('Unsupported recovery inventory metadata');
    }
    return result;
  }

  List<String> _keys(Object? value) {
    if (value is! List ||
        value.length > 4096 ||
        value.any((key) => key is! String)) {
      throw const FormatException('Invalid recovery identifier list');
    }
    final keys = value.cast<String>();
    var bytes = 0;
    for (final key in keys) {
      final size = utf8.encode(key).length;
      bytes += size;
      if (size > 65536 || bytes > 1048576) {
        throw const FormatException('Recovery inventory exceeds its limit');
      }
    }
    if (keys.toSet().length != keys.length) {
      throw const FormatException('Duplicate recovery inventory identifier');
    }
    return keys;
  }
}
