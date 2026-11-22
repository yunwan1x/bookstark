import 'local_data_maintenance.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'complex_editor_document.dart';
import 'complex_recovery_store.dart';
import 'local_complex_notes_repository.dart';

String complexNoteFingerprint(ComplexNote note) => sha256
    .convert(
      utf8.encode(
        jsonEncode([
          note.scope,
          note.id,
          note.collection,
          note.document.kind.name,
          note.version,
          note.title,
          note.labels,
          note.document.digest,
          if (note.resourceFingerprint != null) note.resourceFingerprint,
        ]),
      ),
    )
    .toString();

/// Local, unprotected content only. One full draft body, exact baseline identity
/// and hashes; no account/password and no second 20 MiB baseline body copy.
class ComplexRecoveryRecord {
  ComplexRecoveryRecord._({
    required this.scope,
    required this.id,
    required this.collection,
    required this.kind,
    required this.baselineFingerprint,
    required this.baselineVersion,
    required this.pending,
    required this.edit,
    this.baselineResourceFingerprint,
  });
  factory ComplexRecoveryRecord.capture(
    ComplexNote baseline,
    ComplexNoteEdit edit, {
    required bool pending,
  }) {
    edit.validate(
      bookDocumentBodyOnly: baseline.collection == 'book-document',
      ownedRemoteBodyOnly: const {
        'remote-note',
        'remote-book-document',
        'shared-complex',
      }.contains(baseline.collection),
    );
    if (baseline.id <= 0 ||
        baseline.version < 0 ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(baseline.scope) ||
        !{
          'note',
          'article',
          'book-document',
          'remote-note',
          'remote-book-document',
          'shared-complex',
        }.contains(baseline.collection) ||
        (baseline.document.kind == ComplexEditorKind.markdown &&
            baseline.collection != 'article') ||
        baseline.document.kind != edit.document.kind ||
        const {
              'book-document',
              'remote-note',
              'remote-book-document',
              'shared-complex',
            }.contains(baseline.collection) &&
            baseline.resourceFingerprint == null) {
      throw const FormatException('Invalid recovery document identity');
    }
    return ComplexRecoveryRecord._(
      scope: baseline.scope,
      id: baseline.id,
      collection: baseline.collection,
      kind: baseline.document.kind,
      baselineFingerprint: complexNoteFingerprint(baseline),
      baselineVersion: baseline.version,
      baselineResourceFingerprint: baseline.resourceFingerprint,
      pending: pending,
      edit: edit,
    );
  }
  final String scope, collection, baselineFingerprint;
  final String? baselineResourceFingerprint;
  final int id, baselineVersion;
  final ComplexEditorKind kind;
  final bool pending;
  final ComplexNoteEdit edit;
  bool owns(ComplexNote actual) =>
      actual.scope == scope &&
      actual.id == id &&
      actual.collection == collection &&
      actual.document.kind == kind;
  bool baselineMatches(ComplexNote actual) =>
      owns(actual) &&
      actual.resourceFingerprint == baselineResourceFingerprint &&
      complexNoteFingerprint(actual) == baselineFingerprint;
  bool observedMatches(ComplexNote actual) =>
      owns(actual) && edit.matches(actual);

  Uint8List encode() {
    final metadata = utf8.encode(
      jsonEncode({
        'version': 1,
        'scope': scope,
        'id': id,
        'collection': collection,
        'kind': kind.name,
        'baseline': baselineFingerprint,
        'baselineVersion': baselineVersion,
        'pending': pending,
        'title': edit.title,
        'labels': edit.labels,
        'sourceBytes': edit.document.byteLength,
        'sourceSHA256': edit.document.digest,
        if (baselineResourceFingerprint != null)
          'resourceFingerprint': baselineResourceFingerprint,
      }),
    );
    if (metadata.length > 128 * 1024) {
      throw const FormatException('Recovery metadata exceeds limit');
    }
    final header = ByteData(4)..setUint32(0, metadata.length, Endian.big);
    return (BytesBuilder(copy: false)
          ..add(header.buffer.asUint8List())
          ..add(metadata)
          ..add(utf8.encode(edit.document.source)))
        .takeBytes();
  }

  static ComplexRecoveryRecord decode(Uint8List bytes) {
    if (bytes.length < 4 ||
        bytes.length > NativeComplexRecoveryStore.maxBytes) {
      throw const FormatException('Invalid recovery byte limit');
    }
    final count = ByteData.sublistView(bytes, 0, 4).getUint32(0, Endian.big);
    if (count < 1 || count > 128 * 1024 || count + 4 > bytes.length) {
      throw const FormatException('Invalid recovery metadata length');
    }
    final raw = jsonDecode(
      utf8.decode(
        Uint8List.sublistView(bytes, 4, 4 + count),
        allowMalformed: false,
      ),
    );
    if (raw is! Map ||
        raw['version'] != 1 ||
        raw['scope'] is! String ||
        raw['id'] is! int ||
        (raw['id'] as int) <= 0 ||
        !{
          'note',
          'article',
          'book-document',
          'remote-note',
          'remote-book-document',
          'shared-complex',
        }.contains(raw['collection']) ||
        raw['kind'] is! String ||
        raw['baseline'] is! String ||
        raw['baselineVersion'] is! int ||
        (raw['baselineVersion'] as int) < 0 ||
        raw['pending'] is! bool ||
        raw['resourceFingerprint'] != null &&
            (raw['resourceFingerprint'] is! String ||
                !RegExp(
                  r'^[a-f0-9]{64}$',
                ).hasMatch(raw['resourceFingerprint'] as String)) ||
        const {
              'book-document',
              'remote-note',
              'remote-book-document',
              'shared-complex',
            }.contains(raw['collection']) &&
            raw['resourceFingerprint'] == null ||
        raw['title'] is! String ||
        raw['labels'] is! List ||
        (raw['labels'] as List).any((label) => label is! String) ||
        raw['sourceBytes'] is! int ||
        raw['sourceSHA256'] is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(raw['scope'] as String) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(raw['baseline'] as String)) {
      throw const FormatException('Invalid recovery envelope');
    }
    final kind = ComplexEditorKind.parse(raw['kind'] as String);
    if (kind == ComplexEditorKind.markdown && raw['collection'] != 'article') {
      throw const FormatException('Markdown recovery is for articles only');
    }
    final body = Uint8List.sublistView(bytes, 4 + count);
    if (raw['sourceBytes'] != body.length || body.length > kind.maxBytes) {
      throw const FormatException('Invalid recovery source length');
    }
    final document = ComplexEditorDocument.fromBytes(kind, body);
    if (document.digest != raw['sourceSHA256']) {
      throw const FormatException('Recovery source integrity mismatch');
    }
    final edit = ComplexNoteEdit(
      title: raw['title'] as String,
      document: document,
      labels: (raw['labels'] as List).cast<String>(),
    );
    edit.validate(
      bookDocumentBodyOnly: raw['collection'] == 'book-document',
      ownedRemoteBodyOnly: const {
        'remote-note',
        'remote-book-document',
        'shared-complex',
      }.contains(raw['collection']),
    );
    return ComplexRecoveryRecord._(
      scope: raw['scope'] as String,
      id: raw['id'] as int,
      collection: raw['collection'] as String,
      kind: kind,
      baselineFingerprint: raw['baseline'] as String,
      baselineVersion: raw['baselineVersion'] as int,
      baselineResourceFingerprint: raw['resourceFingerprint'] as String?,
      pending: raw['pending'] as bool,
      edit: edit,
    );
  }
}

class ComplexRecoveryVault {
  ComplexRecoveryVault({
    required this.scope,
    required this.collection,
    required this.kind,
    required this.store,
    this.maintenance,
  }) {
    if (const {
          'book-document',
          'remote-note',
          'remote-book-document',
          'shared-complex',
        }.contains(collection) &&
        kind == ComplexEditorKind.markdown) {
      throw ArgumentError('Book Markdown uses its native editor');
    }
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(scope) ||
        !{
          'note',
          'article',
          'book-document',
          'remote-note',
          'remote-book-document',
          'shared-complex',
        }.contains(collection)) {
      throw ArgumentError('Invalid recovery scope');
    }
  }
  final String scope, collection;
  final ComplexEditorKind kind;
  final ComplexRecoveryBytesStore store;
  final LocalDataMaintenance? maintenance;
  Future<void>? _tail;
  Future<T> _withMaintenance<T>(Future<T> Function() action) =>
      maintenance?.use(action) ?? Future<T>.sync(action);
  Future<T> _ordered<T>(Future<T> Function() action) => _withMaintenance(() {
    final previous = _tail;
    final next = previous == null
        ? Future<T>.sync(action)
        : previous.then((_) => action());
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  });

  String metadataKey(int id) {
    if (id <= 0) throw ArgumentError.value(id);
    return sha256
        .convert(
          utf8.encode(
            jsonEncode([
              'bookstark.local-complex-recovery.v1',
              scope,
              collection,
              kind.name,
              id,
            ]),
          ),
        )
        .toString();
  }

  Future<ComplexRecoveryRecord?> read(int id) => _ordered(() async {
    final bytes = await store.read(metadataKey(id));
    if (bytes == null) return null;
    final record = ComplexRecoveryRecord.decode(bytes);
    if (record.scope != scope ||
        record.collection != collection ||
        record.kind != kind ||
        record.id != id) {
      throw const FormatException('Recovery belongs to another document');
    }
    return record;
  });
  Future<void> write(ComplexRecoveryRecord record) => _ordered(() async {
    if (record.scope != scope ||
        record.collection != collection ||
        record.kind != kind) {
      throw StateError('Recovery identity mismatch');
    }
    await store.write(metadataKey(record.id), record.encode());
  });
  Future<void> remove(int id) => _ordered(() => store.remove(metadataKey(id)));
}
