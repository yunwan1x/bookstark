import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/bounded_note_text_reader.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/local_complex_notes_repository.dart';
import 'package:bookstark_flutter/core/local_protected_content.dart';
import 'package:bookstark_flutter/core/notes_repository.dart' show NoteLocked;
import 'protected_owned_complex_journal.dart';
part 'protected_owned_complex_store.dart';

/// Existing owned resources only. Actual numeric chapter ID remains a chapter.
class RemoteOwnedComplexStore implements ComplexNotesRepository {
  RemoteOwnedComplexStore({
    required this.client,
    required this.memberId,
    required this.resourceId,
    required this.bookId,
    required this.kind,
    required this.note,
    required String recoveryNamespace,
    required this.isCurrent,
    this.protectedSource = false,
  }) : revision = client.sessionRevision,
       scope = sha256
           .convert(
             utf8.encode(
               jsonEncode([
                 'owned-remote-complex-v1',
                 client.baseUri.toString(),
                 memberId,
                 recoveryNamespace,
                 note ? 'remote-note' : 'remote-book-document',
                 bookId,
                 kind.name,
                 if (protectedSource) 'protected',
               ]),
             ),
           )
           .toString() {
    if (protectedSource &&
        (!note ||
            !const {
              ComplexEditorKind.spreadsheet,
              ComplexEditorKind.drawing,
              ComplexEditorKind.mindmap,
              ComplexEditorKind.richdoc,
              ComplexEditorKind.presentation,
            }.contains(kind))) {
      throw ArgumentError('Protected note5 only');
    }
    if (memberId <= 0 ||
        resourceId <= 0 ||
        recoveryNamespace.isEmpty ||
        recoveryNamespace.length > 4096 ||
        kind == ComplexEditorKind.markdown ||
        (note ? bookId != 0 : bookId <= 0)) {
      throw ArgumentError('Owned existing complex identity required');
    }
  }
  final BookstarkClient client;
  final int memberId, resourceId, bookId, revision;
  @override
  final ComplexEditorKind kind;
  final bool note, protectedSource;
  final bool Function() isCurrent;
  @override
  final String scope;
  @override
  String get collection => note ? 'remote-note' : 'remote-book-document';
  final _abort = Completer<void>(), _owned = Expando<bool>();
  bool _closed = false;
  void _guard() {
    if (_closed || !isCurrent() || client.sessionRevision != revision) {
      throw StateError('Remote complex owner retired');
    }
  }

  ComplexNote _decode(Map<String, Object?> envelope) {
    _guard();
    final data = envelope['data'];
    final keys = {
      'resource',
      'id',
      'book_id',
      'member_id',
      'kind',
      'title',
      'labels',
      'resource_fp',
      'source_base64',
      'bytes',
      'sha256',
      if (protectedSource) 'protected',
    };
    if (envelope['code'] != 0 ||
        data is! Map ||
        data.length != keys.length ||
        data.keys.toSet().difference(keys).isNotEmpty ||
        protectedSource && data['protected'] != true ||
        data['resource'] != collection ||
        data['id'] != resourceId ||
        data['book_id'] != bookId ||
        data['member_id'] != memberId ||
        data['kind'] != kind.name ||
        data['title'] is! String ||
        data['labels'] is! List ||
        (data['labels'] as List).length > 100 ||
        (data['labels'] as List).any((v) => v is! String) ||
        data['bytes'] is! int ||
        (data['bytes'] as int) < 0 ||
        (data['bytes'] as int) > kind.maxBytes ||
        data['source_base64'] is! String ||
        data['resource_fp'] is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(data['resource_fp'] as String) ||
        data['sha256'] is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(data['sha256'] as String)) {
      throw const FormatException('Invalid owned complex identity response');
    }
    final title = data['title'] as String,
        labels = (data['labels'] as List).cast<String>();
    ComplexEditorDocument.validateText(title);
    if (utf8.encode(title).length > 65536 ||
        utf8.encode(jsonEncode(labels)).length > 60 * 1024) {
      throw const FormatException('Remote metadata exceeds bound');
    }
    for (final label in labels) {
      ComplexEditorDocument.validateText(label);
    }
    final encoded = data['source_base64'] as String;
    if (encoded.length > ((kind.maxBytes + 2) ~/ 3) * 4 ||
        !RegExp(r'^[A-Za-z0-9+/]*={0,2}$').hasMatch(encoded)) {
      throw const FormatException('Invalid bounded source encoding');
    }
    final bytes = base64Decode(encoded);
    if (bytes.length != data['bytes'] ||
        bytes.length > kind.maxBytes ||
        base64Encode(bytes) != encoded ||
        sha256.convert(bytes).toString() != data['sha256']) {
      throw const FormatException('Source bytes mismatch');
    }
    final source = BoundedNoteTextReader.decodeUtf8PreservingBom(bytes);
    if (isLocalProtectedEnvelopePrefix(source)) throw NoteLocked(resourceId);
    final result = ComplexNote(
      scope: scope,
      id: resourceId,
      collection: collection,
      title: title,
      labels: labels,
      version: 0,
      document: ComplexEditorDocument.parse(kind, source),
      resourceFingerprint: data['resource_fp'] as String,
    );
    _owned[result] = true;
    return result;
  }

  @override
  Future<ComplexNote> read(int id) async {
    _guard();
    if (id != resourceId) throw StateError('Resource ID changed');
    try {
      final envelope = await client.ownedComplexSourceJson(
        resourceId,
        bookId: bookId,
        note: note,
        kind: kind.name,
        expectedSessionRevision: revision,
        abortTrigger: _abort.future,
      );
      _guard();
      return _decode(envelope);
    } on ApiFailure catch (e) {
      if (e.status == 423) throw NoteLocked(resourceId);
      rethrow;
    }
  }

  @override
  Future<ComplexNote> save(ComplexNote baseline, ComplexNoteEdit edit) async {
    _guard();
    if (_owned[baseline] != true ||
        baseline.scope != scope ||
        baseline.id != resourceId ||
        baseline.collection != collection ||
        baseline.document.kind != kind ||
        baseline.resourceFingerprint == null ||
        (!note &&
            (edit.title != baseline.title ||
                jsonEncode(edit.labels) != jsonEncode(baseline.labels))) ||
        edit.document.kind != kind) {
      throw StateError('Owned body-only baseline required');
    }
    final metadataChanged =
        note &&
        (edit.title != baseline.title ||
            jsonEncode(edit.labels) != jsonEncode(baseline.labels));
    if (metadataChanged) edit.validate();
    final source = ComplexEditorDocument.parse(kind, edit.document.source);
    if (isLocalProtectedEnvelopePrefix(source.source)) {
      throw NoteLocked(resourceId);
    }
    final prepared = await client.prepareOwnedComplexSourcePut(
      resourceId,
      bookId: bookId,
      note: note,
      kind: kind.name,
      expectedFingerprint: baseline.resourceFingerprint!,
      sourceBytes: utf8.encode(source.source),
      title: metadataChanged ? edit.title : null,
      labels: metadataChanged ? edit.labels : null,
      expectedSessionRevision: revision,
      abortTrigger: _abort.future,
    );
    try {
      _guard();
      final envelope = await prepared.sendOnce();
      _guard();
      final saved = _decode(envelope);
      if (saved.title != (note ? edit.title : baseline.title) ||
          jsonEncode(saved.labels) !=
              jsonEncode(note ? edit.labels : baseline.labels) ||
          !saved.document.same(source)) {
        throw StateError('Body-only save receipt mismatch');
      }
      return saved;
    } on ApiFailure catch (error) {
      if (error.status == 409) {
        final actual = await read(resourceId);
        _guard();
        throw ComplexNoteConflict(actual);
      }
      if (error.status == 423) throw NoteLocked(resourceId);
      rethrow;
    } finally {
      prepared.retire();
    }
  }

  @override
  void dispose() {
    _closed = true;
    if (!_abort.isCompleted) _abort.complete();
  }
}
