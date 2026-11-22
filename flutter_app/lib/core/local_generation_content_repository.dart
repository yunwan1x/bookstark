import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as paths;
import 'package:sqflite/sqflite.dart';
import 'attachments.dart' show AttachmentCancellation;
import 'bounded_note_text_reader.dart';
import 'local_content_protection_format.dart';
import 'local_content_crypto_limits.dart';
import 'local_data_paths.dart';
import 'local_data_maintenance.dart';
import 'local_legacy_format_selection.dart';
import 'native_local_content_crypto.dart';
import 'complex_editor_document.dart';

enum GenerationContentReason {
  incompatibleSchema,
  invalidRecord,
  notFound,
  retired,
  cancelled,
  conflict,
  storage,
  invalidEdit,
}

final class GenerationContentFailure implements Exception {
  const GenerationContentFailure(this.reason);
  final GenerationContentReason reason;
  @override
  String toString() => 'Generation content: ${reason.name}';
}

final class GenerationContentMetadata {
  GenerationContentMetadata._({
    required this.generationId,
    required this.id,
    required this.collection,
    required this.format,
    required this.title,
    required List<String> labels,
    required this.revision,
    required this.updatedAt,
    required this.isProtected,
    required this.isPinned,
    required this.pinOrder,
    required this.visibility,
  }) : labels = List.unmodifiable(labels);
  final String generationId, collection, title;
  final int id, revision, updatedAt, pinOrder, visibility;
  final LegacyContentFormat format;
  final List<String> labels;
  final bool isProtected, isPinned;
}

final class GenerationContentCounts {
  const GenerationContentCounts._(
    this.notes,
    this.articles,
    this.protectedItems,
  );
  final int notes, articles, protectedItems;
  int get total => notes + articles;
}

final class GenerationContentLocked implements Exception {
  const GenerationContentLocked(this.metadata);
  final GenerationContentMetadata metadata;
  @override
  String toString() => 'Generation content requires unlocking';
}

/// Ephemeral only. No password/hash/ciphertext serialization or file handle.
final class GenerationContentHandle {
  GenerationContentHandle._(
    this._owner,
    _StoredContent record,
    this._plaintext,
    this._password,
  ) : _record = record,
      metadata = record.header.metadata;
  final LocalGenerationContentRepository _owner;
  _StoredContent? _record;
  String? _plaintext, _password;
  bool _closed = false;
  final GenerationContentMetadata metadata;
  bool get isCurrent {
    if (_closed) {
      return false;
    }
    try {
      _owner._check();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Opaque complete stored identity only. It includes original password-hash
  /// metadata and ciphertext bytes, but returns neither of them to a journal.
  String get resourceFingerprint {
    _owner._check();
    final record = _record;
    if (_closed || record == null) {
      throw const GenerationContentFailure(GenerationContentReason.retired);
    }
    return sha256
        .convert(
          utf8.encode(
            jsonEncode([
              'generation-content-fulltuple-v1',
              metadata.generationId,
              record.header.signature,
              record.bodySha256,
            ]),
          ),
        )
        .toString();
  }

  String get source {
    _owner._check();
    if (_closed || _plaintext == null) {
      throw const GenerationContentFailure(GenerationContentReason.retired);
    }
    return _plaintext!;
  }

  void close() {
    _closed = true;
    _plaintext = null;
    _password = null;
    _record = null;
    _owner._handles.remove(this);
  }
}

final class _ContentOperation {
  _ContentOperation(this.cancellation);
  final AttachmentCancellation cancellation;
}

final class _StoredHeader {
  const _StoredHeader(
    this.metadata,
    this.passwordHash,
    this.labelsJson,
    this.bodyBytes,
    this.signature,
    this.legacyVersion,
  );
  final GenerationContentMetadata metadata;
  final String passwordHash, labelsJson, signature;
  final int bodyBytes, legacyVersion;
}

final class _StoredContent {
  _StoredContent(this.header, this.body)
    : bodySha256 = sha256.convert(utf8.encode(body)).toString();
  final _StoredHeader header;
  final String body, bodySha256;
  bool same(_StoredContent other) =>
      header.signature == other.header.signature &&
      bodySha256 == other.bodySha256;
}

/// Unreleased named schema15 generation only. Never opens a source/active14 DB.
/// UI must secure its window and retire plaintext/drafts on lifecycle changes.
final class LocalGenerationContentRepository {
  LocalGenerationContentRepository({
    required Database database,
    required this.generation,
    required bool Function() isCurrent,
    NativeLocalContentCrypto? crypto,
    LocalDataMaintenance? maintenance,
    DateTime Function()? clock,
    this.beforeWrite,
  }) : _database = database,
       _current = isCurrent,
       crypto = crypto ?? NativeLocalContentCrypto(),
       _clock = clock ?? DateTime.now,
       maintenance =
           maintenance ??
           LocalDataMaintenance.forStorage(generation.databasePath) {
    if (generation.generationId == null ||
        !paths.isAbsolute(database.path) ||
        paths.normalize(database.path) !=
            paths.normalize(generation.databasePath)) {
      throw ArgumentError('Expected a matching owned generation database');
    }
  }
  final Database _database;
  final LocalDataPaths generation;
  final bool Function() _current;
  final NativeLocalContentCrypto crypto;
  final Future<void> Function()? beforeWrite;
  final DateTime Function() _clock;
  final LocalDataMaintenance maintenance;
  final _operations = <_ContentOperation>{};
  final _handles = <GenerationContentHandle>{};
  bool _closed = false;
  void dispose() {
    if (_closed) {
      return;
    }
    _closed = true;
    for (final operation in _operations.toList()) {
      operation.cancellation.cancel();
    }
    for (final handle in _handles.toList()) {
      handle.close();
    }
  }

  void _check([_ContentOperation? operation]) {
    var current = false;
    try {
      current = _current();
    } catch (_) {
      current = false;
    }
    if (_closed || !current || maintenance.retired) {
      dispose();
      throw const GenerationContentFailure(GenerationContentReason.retired);
    }
    if (operation?.cancellation.cancelled == true) {
      throw const GenerationContentFailure(GenerationContentReason.cancelled);
    }
  }

  Future<T> _run<T>(
    Future<T> Function(_ContentOperation operation) action,
    AttachmentCancellation? cancellation,
  ) async {
    final operation = _ContentOperation(
      cancellation ?? AttachmentCancellation(),
    );
    _operations.add(operation);
    try {
      return await maintenance.use(() async {
        _check(operation);
        return action(operation);
      });
    } catch (error) {
      if (error is GenerationContentWriteUncertain ||
          error is GenerationContentFailure ||
          error is GenerationContentLocked ||
          error is LocalContentCryptoFailure ||
          error is LocalStorageRetired) {
        rethrow;
      }
      if (error is FormatException) {
        throw const GenerationContentFailure(
          GenerationContentReason.invalidRecord,
        );
      }
      throw const GenerationContentFailure(GenerationContentReason.storage);
    } finally {
      _operations.remove(operation);
    }
  }

  Future<void> _schema(DatabaseExecutor tx, _ContentOperation operation) async {
    final version = await tx.rawQuery('PRAGMA user_version');
    _check(operation);
    if (version.length != 1 || version.single.values.single != 15) {
      throw const GenerationContentFailure(
        GenerationContentReason.incompatibleSchema,
      );
    }
  }

  Future<_StoredHeader> _header(
    DatabaseExecutor tx,
    int id,
    String collection,
    _ContentOperation operation, {
    bool metadataOnly = false,
  }) async {
    if (id <= 0 || !{'note', 'article'}.contains(collection)) {
      throw ArgumentError('Expected a content identity');
    }
    final rows = await tx.rawQuery(
      'SELECT id,collection,editor_type,revision,updated_at,legacy_version,is_pinned,pin_order,visibility,'
      'typeof(title) AS title_type,typeof(labels) AS labels_type,typeof(password_hash) AS hash_type,typeof(content) AS body_type,'
      'CASE WHEN length(CAST(title AS BLOB))<=262144 THEN CAST(title AS BLOB) END AS title_bytes,'
      'CASE WHEN length(CAST(labels AS BLOB))<=262144 THEN CAST(labels AS BLOB) END AS labels_bytes,'
      'CASE WHEN length(CAST(password_hash AS BLOB))<=128 THEN CAST(password_hash AS BLOB) END AS hash_bytes,'
      'length(CAST(content AS BLOB)) AS body_bytes FROM notes '
      'WHERE id=? AND collection=? AND deleted=0',
      [id, collection],
    );
    _check(operation);
    if (rows.length != 1) {
      throw const GenerationContentFailure(GenerationContentReason.notFound);
    }
    final row = rows.single;
    for (final key in [
      'id',
      'revision',
      'updated_at',
      'legacy_version',
      'is_pinned',
      'pin_order',
      'visibility',
      'body_bytes',
    ]) {
      if (row[key] is! int) {
        throw const GenerationContentFailure(
          GenerationContentReason.invalidRecord,
        );
      }
    }
    if (row['id'] != id ||
        row['collection'] != collection ||
        row['editor_type'] is! String ||
        row['title_type'] != 'text' ||
        row['labels_type'] != 'text' ||
        row['hash_type'] != 'text' ||
        (row['body_type'] != 'text' &&
            !(metadataOnly && row['body_type'] == 'blob')) ||
        (row['revision'] as int) <= 0 ||
        (row['body_bytes'] as int) < 0 ||
        !{0, 1}.contains(row['is_pinned']) ||
        row['title_bytes'] is! Uint8List ||
        row['labels_bytes'] is! Uint8List ||
        row['hash_bytes'] is! Uint8List) {
      throw const GenerationContentFailure(
        GenerationContentReason.invalidRecord,
      );
    }
    final title = BoundedNoteTextReader.decodeUtf8PreservingBom(
          row['title_bytes'] as Uint8List,
        ),
        labelsJson = BoundedNoteTextReader.decodeUtf8PreservingBom(
          row['labels_bytes'] as Uint8List,
        ),
        hash = BoundedNoteTextReader.decodeUtf8PreservingBom(
          row['hash_bytes'] as Uint8List,
        );
    final labels = jsonDecode(labelsJson);
    if (labels is! List ||
        labels.any((v) => v is! String || v.isEmpty) ||
        labels.toSet().length != labels.length ||
        hash.isNotEmpty && !localPasswordHashSupported(hash)) {
      throw const GenerationContentFailure(
        GenerationContentReason.invalidRecord,
      );
    }
    final meta = GenerationContentMetadata._(
      generationId: generation.generationId!,
      id: id,
      collection: collection,
      format: LegacyContentFormat.parse(row['editor_type'] as String),
      title: title,
      labels: labels.cast<String>(),
      revision: row['revision'] as int,
      updatedAt: row['updated_at'] as int,
      isProtected: hash.isNotEmpty,
      isPinned: row['is_pinned'] == 1,
      pinOrder: row['pin_order'] as int,
      visibility: row['visibility'] as int,
    );
    final signature = sha256
        .convert(
          utf8.encode(
            jsonEncode([
              for (final key in [
                'id',
                'collection',
                'editor_type',
                'revision',
                'updated_at',
                'legacy_version',
                'is_pinned',
                'pin_order',
                'visibility',
                'body_bytes',
              ])
                row[key],
              title,
              labelsJson,
              hash,
            ]),
          ),
        )
        .toString();
    return _StoredHeader(
      meta,
      hash,
      labelsJson,
      row['body_bytes'] as int,
      signature,
      row['legacy_version'] as int,
    );
  }

  Future<_StoredContent> _readStored(
    DatabaseExecutor tx,
    int id,
    String collection,
    _ContentOperation operation, {
    String? password,
    bool requireUnlock = true,
  }) async {
    final header = await _header(tx, id, collection, operation);
    if (requireUnlock &&
        header.metadata.isProtected &&
        (password == null || password.isEmpty)) {
      throw GenerationContentLocked(header.metadata);
    }
    final limit = header.metadata.isProtected
        ? localCryptoMaxWireBytes
        : (header.metadata.format == LegacyContentFormat.presentation ||
                  header.metadata.format == LegacyContentFormat.markdown
              ? localCryptoMaxPlaintextBytes
              : 5 * 1024 * 1024);
    if (header.bodyBytes > limit) {
      throw const GenerationContentFailure(
        GenerationContentReason.invalidRecord,
      );
    }
    final body = await BoundedNoteTextReader.readNoteContent(
      tx,
      id: id,
      collection: collection,
      editorType: header.metadata.format.name,
      maxRecordBytes: limit,
    );
    _check(operation);
    if (header.metadata.isProtected
        ? !localProtectedRecordSupported(header.passwordHash, body)
        : body.startsWith('ENC:')) {
      throw const GenerationContentFailure(
        GenerationContentReason.invalidRecord,
      );
    }
    return _StoredContent(header, body);
  }

  Future<GenerationContentCounts> counts({
    AttachmentCancellation? cancellation,
  }) => _run((operation) async {
    return _database.transaction((tx) async {
      await _schema(tx, operation);
      final row = (await tx.rawQuery(
        "SELECT COALESCE(SUM(collection='note'),0) AS notes,"
        "COALESCE(SUM(collection='article'),0) AS articles,"
        "COALESCE(SUM(password_hash!=''),0) AS protected_items "
        "FROM notes WHERE deleted=0",
      )).single;
      _check(operation);
      for (final key in ['notes', 'articles', 'protected_items']) {
        if (row[key] is! int || (row[key] as int) < 0) {
          throw const GenerationContentFailure(
            GenerationContentReason.invalidRecord,
          );
        }
      }
      final result = GenerationContentCounts._(
        row['notes'] as int,
        row['articles'] as int,
        row['protected_items'] as int,
      );
      if (result.protectedItems > result.total) {
        throw const GenerationContentFailure(
          GenerationContentReason.invalidRecord,
        );
      }
      return result;
    }, exclusive: false);
  }, cancellation);

  Future<List<GenerationContentListEntry>> list({
    String collection = 'note',
    String keyword = '',
    String label = '',
    String pinned = '',
    int page = 1,
    AttachmentCancellation? cancellation,
  }) => _run((operation) async {
    if (!{'note', 'article', 'all'}.contains(collection) ||
        !{'', '0', '1'}.contains(pinned) ||
        page < 1 ||
        page > 1000000 ||
        keyword.length > 4096 ||
        label.length > 4096) {
      throw const GenerationContentFailure(GenerationContentReason.invalidEdit);
    }
    final pattern =
        '%${keyword.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_')}%';
    return _database.transaction((tx) async {
      await _schema(tx, operation);
      final rows = await tx.rawQuery(
        "SELECT id,collection,typeof(content) AS body_type FROM notes WHERE deleted=0 AND (?=\x27all\x27 OR collection=?) "
        "AND (?='' OR instr(labels,?)>0) AND (?='' OR is_pinned=?) "
        "AND (?='' OR title LIKE ? ESCAPE '\\' OR (password_hash='' AND content LIKE ? ESCAPE '\\')) "
        'ORDER BY updated_at DESC,id DESC LIMIT 20 OFFSET ?',
        [
          collection,
          collection,
          label,
          jsonEncode(label),
          pinned,
          pinned == '1' ? 1 : 0,
          keyword,
          pattern,
          pattern,
          (page - 1) * 20,
        ],
      );
      _check(operation);
      final result = <GenerationContentListEntry>[];
      for (final row in rows) {
        if (row['id'] is! int ||
            !{'note', 'article'}.contains(row['collection'])) {
          throw const GenerationContentFailure(
            GenerationContentReason.invalidRecord,
          );
        }
        final header = await _header(
          tx,
          row['id'] as int,
          row['collection'] as String,
          operation,
          metadataOnly: true,
        );
        var preview = '';
        var previewUnavailable = row['body_type'] == 'blob';
        if (!previewUnavailable &&
            !header.metadata.isProtected &&
            header.metadata.format == LegacyContentFormat.markdown) {
          final cells = await tx.rawQuery(
            'SELECT CAST(substr(content,1,512) AS BLOB) AS preview FROM notes WHERE id=? AND collection=? AND deleted=0',
            [header.metadata.id, header.metadata.collection],
          );
          _check(operation);
          if (cells.length != 1 || cells.single['preview'] is! Uint8List) {
            throw const GenerationContentFailure(
              GenerationContentReason.invalidRecord,
            );
          }
          try {
            preview = BoundedNoteTextReader.decodeUtf8PreservingBom(
              cells.single['preview'] as Uint8List,
            );
          } on FormatException {
            previewUnavailable = true;
          }
        }
        result.add(
          GenerationContentListEntry._(
            header.metadata,
            preview,
            previewUnavailable: previewUnavailable,
          ),
        );
      }
      _check(operation);
      return List<GenerationContentListEntry>.unmodifiable(result);
    }, exclusive: false);
  }, cancellation);

  Future<GenerationContentHandle> open(
    int id, {
    String collection = 'note',
    String? password,
    AttachmentCancellation? cancellation,
  }) => _run((operation) async {
    final stored = await _database.transaction((tx) async {
      await _schema(tx, operation);
      return _readStored(tx, id, collection, operation, password: password);
    }, exclusive: false);
    _check(operation);
    final plain = stored.header.metadata.isProtected
        ? await crypto.unlock(
            password: password!,
            passwordHash: stored.header.passwordHash,
            body: stored.body,
            cancellation: operation.cancellation,
          )
        : stored.body;
    _check(operation);
    final fresh = await _database.transaction((tx) async {
      await _schema(tx, operation);
      return _readStored(tx, id, collection, operation, requireUnlock: false);
    }, exclusive: false);
    _check(operation);
    if (!stored.same(fresh)) {
      throw const GenerationContentFailure(GenerationContentReason.conflict);
    }
    final handle = GenerationContentHandle._(
      this,
      stored,
      plain,
      stored.header.metadata.isProtected ? password : null,
    );
    _handles.add(handle);
    return handle;
  }, cancellation);
  Future<GenerationContentHandle> save(
    GenerationContentHandle baseline, {
    required String title,
    required String source,
    required List<String> labels,
    AttachmentCancellation? cancellation,
  }) => _run((operation) async {
    _check(operation);
    if (!identical(baseline._owner, this) ||
        !baseline.isCurrent ||
        !_handles.contains(baseline)) {
      throw const GenerationContentFailure(GenerationContentReason.retired);
    }
    final before = baseline._record;
    if (before == null) {
      throw const GenerationContentFailure(GenerationContentReason.retired);
    }
    final meta = baseline.metadata;
    final labelValues = List<String>.unmodifiable(labels);
    final labelsJson = jsonEncode(labelValues);
    if (!localProtectionUnicode(title) ||
        title.trim().isEmpty ||
        utf8.encode(title).length > 200 ||
        labelValues.length > 100 ||
        labelValues.any((v) => v.isEmpty || !localProtectionUnicode(v)) ||
        labelValues.toSet().length != labelValues.length ||
        utf8.encode(labelsJson).length > 60 * 1024 ||
        !localProtectionUnicode(source)) {
      throw const GenerationContentFailure(GenerationContentReason.invalidEdit);
    }
    try {
      if (meta.format == LegacyContentFormat.markdown) {
        if (utf8.encode(source).length > localGenerationMarkdownSaveBytes ||
            !localProtectedPlaintext(source) ||
            !meta.isProtected && source.startsWith('ENC:')) {
          throw const FormatException('Reserved or oversized source');
        }
      } else {
        ComplexEditorDocument.parse(
          ComplexEditorKind.parse(meta.format.name),
          source,
        );
      }
    } on FormatException {
      throw const GenerationContentFailure(GenerationContentReason.invalidEdit);
    }
    if (BigInt.from(meta.revision) >= (BigInt.one << 63) - BigInt.one) {
      throw const GenerationContentFailure(
        GenerationContentReason.invalidRecord,
      );
    }
    final unchanged =
        title == meta.title &&
        source == baseline.source &&
        labelsJson == before.header.labelsJson;
    if (unchanged) {
      final fresh = await _database.transaction((tx) async {
        await _schema(tx, operation);
        return _readStored(
          tx,
          meta.id,
          meta.collection,
          operation,
          requireUnlock: false,
        );
      }, exclusive: false);
      _check(operation);
      if (!fresh.same(before)) {
        baseline.close();
        throw const GenerationContentFailure(GenerationContentReason.conflict);
      }
      return baseline;
    }
    var body = source;
    if (meta.isProtected) {
      final password = baseline._password;
      if (password == null) {
        throw const GenerationContentFailure(GenerationContentReason.retired);
      }
      body = await crypto.encryptExisting(
        password: password,
        passwordHash: before.header.passwordHash,
        plaintext: source,
        cancellation: operation.cancellation,
      );
    }
    _check(operation);
    final stamp = _clock().millisecondsSinceEpoch,
        nextRevision = meta.revision + 1;
    var attempted = false, committed = false;
    try {
      // The owned generation factory rechecks its real native pointer after
      // crypto awaits and immediately before entering a write transaction.
      await beforeWrite?.call();
      _check(operation);
      final stored = await _database.transaction((tx) async {
        await _schema(tx, operation);
        final current = await _readStored(
          tx,
          meta.id,
          meta.collection,
          operation,
          requireUnlock: false,
        );
        _check(operation);
        if (!current.same(before)) {
          throw const GenerationContentFailure(
            GenerationContentReason.conflict,
          );
        }
        if (meta.collection == 'article') {
          final duplicates = await tx.rawQuery(
            "SELECT id FROM notes WHERE collection='article' AND deleted=0 AND title=CAST(? AS TEXT) AND id!=?",
            [Uint8List.fromList(utf8.encode(title)), meta.id],
          );
          _check(operation);
          if (duplicates.isNotEmpty) {
            throw const GenerationContentFailure(
              GenerationContentReason.invalidEdit,
            );
          }
        }
        attempted = true;
        final changed = await tx.rawUpdate(
          'UPDATE notes SET title=CAST(? AS TEXT),content=CAST(? AS TEXT),labels=CAST(? AS TEXT),'
          'updated_at=?,revision=? WHERE id=? AND collection=? AND editor_type=? AND deleted=0 AND revision=?',
          [
            Uint8List.fromList(utf8.encode(title)),
            Uint8List.fromList(utf8.encode(body)),
            Uint8List.fromList(utf8.encode(labelsJson)),
            stamp,
            nextRevision,
            meta.id,
            meta.collection,
            meta.format.name,
            meta.revision,
          ],
        );
        _check(operation);
        if (changed != 1) {
          throw const GenerationContentFailure(
            GenerationContentReason.conflict,
          );
        }
        final verified = await _readStored(
          tx,
          meta.id,
          meta.collection,
          operation,
          requireUnlock: false,
        );
        _check(operation);
        if (verified.header.metadata.revision != nextRevision ||
            verified.header.metadata.title != title ||
            verified.header.metadata.updatedAt != stamp ||
            verified.header.labelsJson != labelsJson ||
            verified.header.passwordHash != before.header.passwordHash ||
            verified.body != body ||
            verified.header.legacyVersion != before.header.legacyVersion ||
            verified.header.metadata.format != meta.format ||
            verified.header.metadata.isPinned != meta.isPinned ||
            verified.header.metadata.pinOrder != meta.pinOrder ||
            verified.header.metadata.visibility != meta.visibility) {
          throw const GenerationContentFailure(
            GenerationContentReason.invalidRecord,
          );
        }
        return verified;
      });
      committed = true;
      _check(operation);
      final password = baseline._password;
      for (final old in _handles.toList()) {
        if (old.metadata.id == meta.id &&
            old.metadata.collection == meta.collection) {
          old.close();
        }
      }
      final result = GenerationContentHandle._(this, stored, source, password);
      _handles.add(result);
      return result;
    } catch (error) {
      if (attempted || committed) {
        for (final old in _handles.toList()) {
          if (old.metadata.id == meta.id &&
              old.metadata.collection == meta.collection) {
            old.close();
          }
        }
        throw GenerationContentWriteUncertain(
          generation.generationId!,
          meta.id,
          nextRevision,
          knownCommitted: committed,
        );
      }
      if (error is GenerationContentFailure &&
          error.reason == GenerationContentReason.conflict) {
        baseline.close();
      }
      rethrow;
    }
  }, cancellation);
}

final class GenerationContentWriteUncertain implements Exception {
  const GenerationContentWriteUncertain(
    this.generationId,
    this.id,
    this.expectedRevision, {
    required this.knownCommitted,
  });
  final String generationId;
  final int id, expectedRevision;
  final bool knownCommitted;
  @override
  String toString() => 'Content write requires read-only reconciliation';
}

/// A bounded preview cannot be passed to save(), which requires an open handle.
final class GenerationContentListEntry {
  const GenerationContentListEntry._(
    this.metadata,
    this.preview, {
    this.previewUnavailable = false,
  });
  final GenerationContentMetadata metadata;
  final String preview;

  /// A list status, never a full editable body.
  final bool previewUnavailable;
}
