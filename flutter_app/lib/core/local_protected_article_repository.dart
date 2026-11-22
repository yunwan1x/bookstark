import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import 'attachments.dart';
import 'bounded_note_text_reader.dart';
import 'complex_editor_document.dart';
import 'complex_recovery_store.dart';
import 'local_complex_notes_repository.dart';
import 'local_content_crypto_limits.dart';
import 'local_content_protection_format.dart';
import 'local_protected_content.dart';
import 'local_store.dart';
import 'native_local_content_crypto.dart';

/// Existing ordinary article only: ciphertext SQL, authenticated route memory.
final class LocalProtectedArticleRepository implements ComplexNotesRepository {
  LocalProtectedArticleRepository._(
    this.store,
    this.id,
    this.kind,
    this.crypto,
    this.isCurrentScope,
    String password,
    this._row,
    this._baseline,
  ) : _password = password,
      scope = sha256
          .convert(
            utf8.encode(
              jsonEncode(['ordinary-protected-article', store.path, id]),
            ),
          )
          .toString();
  final LocalStore store;
  final int id;
  @override
  final ComplexEditorKind kind;
  final NativeLocalContentCrypto crypto;
  final bool Function() isCurrentScope;
  @override
  final String scope;
  @override
  String get collection => 'article';
  String? _password;
  _CipherRow? _row;
  ComplexNote? _baseline;
  bool _closed = false, _busy = false;
  final _requests = <AttachmentCancellation>{};
  final _inflight = <Future<void>>{};

  static Future<bool> isProtected(LocalStore store, int id) =>
      store.maintenance.use(() async {
        final rows = await (await store.database).rawQuery(
          'SELECT hex(substr(CAST(content AS BLOB),1,7)) AS prefix FROM notes '
          "WHERE id=? AND collection='article' AND deleted=0",
          [id],
        );
        return rows.length == 1 &&
            isLocalProtectedEnvelopeHexPrefix(rows.single['prefix']);
      });

  static Future<LocalProtectedArticleRepository> open({
    required LocalStore store,
    required int id,
    required String password,
    required bool Function() isCurrentScope,
    NativeLocalContentCrypto? crypto,
    AttachmentCancellation? cancellation,
  }) async {
    if (!isCurrentScope()) throw StateError('Protected article retired');
    final worker = crypto ?? NativeLocalContentCrypto();
    final row = await store.maintenance.use(
      () async => (await store.database).transaction((tx) => _capture(tx, id)),
    );
    if (!isCurrentScope()) throw StateError('Protected article retired');
    final plain = await worker.unlockEnvelope(
      password: password,
      body: row.cipher,
      cancellation: cancellation,
    );
    if (!isCurrentScope()) throw StateError('Protected article retired');
    final kind = ComplexEditorKind.parse(row.type);
    final repo = LocalProtectedArticleRepository._(
      store,
      id,
      kind,
      worker,
      isCurrentScope,
      password,
      row,
      null,
    );
    try {
      repo._baseline = repo._note(row, plain);
      final fresh = await store.maintenance.use(
        () async =>
            (await store.database).transaction((tx) => _capture(tx, id)),
      );
      repo._check();
      if (!row.same(fresh))
        throw StateError('Protected article changed during unlock');
      return repo;
    } catch (_) {
      repo.dispose();
      rethrow;
    }
  }

  void _check() {
    if (_closed || _password == null || !isCurrentScope()) {
      throw StateError('Protected article retired');
    }
  }

  Future<T> _run<T>(Future<T> Function(AttachmentCancellation) action) async {
    _check();
    if (_busy) throw StateError('Protected article operation already active');
    _busy = true;
    final request = AttachmentCancellation();
    _requests.add(request);
    final done = Completer<void>();
    _inflight.add(done.future);
    try {
      final result = await action(request);
      _check();
      return result;
    } finally {
      _requests.remove(request);
      _busy = false;
      _inflight.remove(done.future);
      done.complete();
    }
  }

  static Future<_CipherRow> _capture(DatabaseExecutor db, int id) async {
    final rows = await db.rawQuery(
      'SELECT id,CAST(title AS BLOB) AS title_bytes,'
      'CAST(labels AS BLOB) AS labels_bytes,updated_at,editor_type '
      "FROM notes WHERE id=? AND collection='article' AND deleted=0",
      [id],
    );
    if (rows.length != 1) throw StateError('Protected article unavailable');
    final row = rows.single;
    final type = row['editor_type'] as String;
    ComplexEditorKind.parse(type);
    final cipher = await BoundedNoteTextReader.readNoteContent(
      db,
      id: id,
      collection: 'article',
      editorType: type,
      maxRecordBytes: localCryptoMaxWireBytes,
    );
    if (!localProtectedEnvelope(cipher)) {
      throw const LocalContentCryptoFailure(
        LocalContentCryptoReason.unsupported,
      );
    }
    return _CipherRow(
      id,
      BoundedNoteTextReader.decodeUtf8PreservingBom(
        row['title_bytes'] as Uint8List,
      ),
      BoundedNoteTextReader.decodeUtf8PreservingBom(
        row['labels_bytes'] as Uint8List,
      ),
      row['updated_at'] as int,
      type,
      cipher,
    );
  }

  ComplexNote _note(_CipherRow row, String plain) => ComplexNote(
    scope: scope,
    id: id,
    collection: collection,
    title: row.title,
    document: ComplexEditorDocument.parse(kind, plain),
    version: row.updated,
    labels: (jsonDecode(row.labels) as List).cast<String>(),
    resourceFingerprint: sha256.convert(utf8.encode(row.identity)).toString(),
  );

  @override
  Future<ComplexNote> read(int resourceId) => _run((request) async {
    if (resourceId != id)
      throw StateError('Protected article identity mismatch');
    final row = await store.maintenance.use(
      () async => (await store.database).transaction((tx) => _capture(tx, id)),
    );
    _check();
    if (row.type != kind.name)
      throw StateError('Protected article format changed');
    if (_row?.same(row) == true && _baseline != null) return _baseline!;
    final plain = await crypto.unlockEnvelope(
      password: _password!,
      body: row.cipher,
      cancellation: request,
    );
    _check();
    final note = _note(row, plain);
    _row = row;
    _baseline = note;
    return note;
  });

  @override
  Future<ComplexNote> save(ComplexNote baseline, ComplexNoteEdit edit) => _run((
    request,
  ) async {
    edit.validate();
    if (_baseline == null ||
        !baseline.same(_baseline!) ||
        edit.document.kind != kind) {
      throw StateError('Protected article baseline mismatch');
    }
    final original = _row!;
    // Even no-op must compare current SQL; it never re-encrypts or updates time.
    final noChange = edit.matches(baseline);
    final encrypted = noChange
        ? original.cipher
        : await crypto.encryptEnvelope(
            password: _password!,
            plaintext: edit.document.source,
            cancellation: request,
          );
    _check();
    request.check();
    late _CipherRow saved;
    try {
      saved = await store.maintenance.use(
        () async => (await store.database).transaction((tx) async {
          _check();
          request.check();
          final current = await _capture(tx, id);
          if (!current.same(original)) throw _CipherConflict();
          if (noChange) return current;
          final now = DateTime.now().millisecondsSinceEpoch;
          final updated = now > current.updated ? now : current.updated + 1;
          final count = await tx.update(
            'notes',
            {
              'title': edit.title,
              'labels': jsonEncode(edit.labels),
              'content': encrypted,
              'updated_at': updated,
            },
            where:
                "id=? AND collection='article' AND editor_type=? AND deleted=0",
            whereArgs: [id, kind.name],
          );
          if (count != 1)
            throw StateError('Protected article save not applied');
          _check();
          request.check();
          return _CipherRow(
            id,
            edit.title,
            jsonEncode(edit.labels),
            updated,
            kind.name,
            encrypted,
          );
        }),
      );
    } on _CipherConflict {
      // No write occurred; controller displays conflict using freshly unlocked source.
      final current = await store.maintenance.use(
        () async =>
            (await store.database).transaction((tx) => _capture(tx, id)),
      );
      if (current.type != kind.name)
        throw StateError('Protected article format changed');
      final plain = await crypto.unlockEnvelope(
        password: _password!,
        body: current.cipher,
        cancellation: request,
      );
      _check();
      throw ComplexNoteConflict(_note(current, plain));
    }
    _check();
    final result = _note(saved, edit.document.source);
    _row = saved;
    _baseline = result;
    return result;
  });

  Future<void> drain() async {
    dispose();
    while (_inflight.isNotEmpty) {
      await Future.wait(_inflight.toList());
    }
  }

  @override
  void dispose() {
    _closed = true;
    for (final request in _requests) {
      request.cancel();
    }
    _password = null;
    _row = null;
    _baseline = null;
  }
}

final class _CipherConflict implements Exception {}

final class _CipherRow {
  const _CipherRow(
    this.id,
    this.title,
    this.labels,
    this.updated,
    this.type,
    this.cipher,
  );
  final int id, updated;
  final String title, labels, type, cipher;
  String get identity => jsonEncode([id, title, labels, updated, type, cipher]);
  bool same(_CipherRow other) => identity == other.identity;
}

/// Only this route's transient recovery bytes; never delegates to disk storage.
final class LocalProtectedArticleMemoryStore
    implements ComplexRecoveryBytesStore {
  final _values = <String, Uint8List>{};
  bool _closed = false;
  void _check() {
    if (_closed) throw StateError('Protected memory retired');
  }

  @override
  Future<Uint8List?> read(String key) async {
    _check();
    final value = _values[key];
    return value == null ? null : Uint8List.fromList(value);
  }

  @override
  Future<void> write(String key, Uint8List value) async {
    _check();
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(key) ||
        value.length > NativeComplexRecoveryStore.maxBytes) {
      throw const FormatException('Protected memory bound');
    }
    final old = _values.remove(key);
    if (old != null) old.fillRange(0, old.length, 0);
    _values[key] = Uint8List.fromList(value);
  }

  @override
  Future<void> remove(String key) async {
    _check();
    final old = _values.remove(key);
    if (old != null) old.fillRange(0, old.length, 0);
  }

  void close() {
    _closed = true;
    for (final value in _values.values) {
      value.fillRange(0, value.length, 0);
    }
    _values.clear();
  }
}
