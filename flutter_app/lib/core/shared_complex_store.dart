import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'anonymous_shared_capability.dart';
import 'complex_editor_document.dart';
import 'local_complex_notes_repository.dart';

/// Explicit capability namespace, never an owned note/article or fake account.
class SharedComplexStore implements ComplexNotesRepository {
  SharedComplexStore({
    required this.transport,
    required this.initial,
    required this.isCurrent,
    this._password,
    this.beforeSubmit,
    this.onKnownReceipt,
  }) : scope = sha256
           .convert(
             utf8.encode(
               jsonEncode([
                 'shared-complex-v1',
                 transport.link.reference.server.toString(),
                 transport.link.requestPath,
               ]),
             ),
           )
           .toString() {
    if (initial.identity.kind == ComplexEditorKind.markdown) {
      throw StateError('Use existing shared Markdown route');
    }
  }
  final AnonymousSharedCapability transport;
  final SharedCapabilitySource initial;
  final bool Function() isCurrent;
  final Future<void> Function(SharedCapabilitySource, ComplexEditorDocument)?
  beforeSubmit;
  final Future<void> Function(String sourceDigest, String modified)?
  onKnownReceipt;
  String? _password;
  bool _closed = false;
  final _owned = Expando<SharedCapabilitySource>();
  @override
  final String scope;
  @override
  String get collection => 'shared-complex';
  @override
  ComplexEditorKind get kind => initial.identity.kind;
  int get resourceId => initial.identity.targetId;
  void _guard() {
    if (_closed || !isCurrent()) throw StateError('Shared editor retired');
  }

  ComplexNote _note(SharedCapabilitySource value) {
    if (!value.identity.same(initial.identity)) {
      throw const SharedCapabilityFailure(409);
    }
    final result = ComplexNote(
      scope: scope,
      id: resourceId,
      collection: collection,
      title: value.title,
      labels: const [],
      version: 0,
      document: value.document,
      resourceFingerprint: value.fingerprint,
    );
    _owned[result] = value;
    return result;
  }

  @override
  Future<ComplexNote> read(int id) async {
    _guard();
    if (id != resourceId) throw StateError('Shared resource changed');
    final actual = await transport.read(password: _password);
    _guard();
    return _note(actual);
  }

  @override
  Future<ComplexNote> save(ComplexNote baseline, ComplexNoteEdit edit) async {
    _guard();
    final original = _owned[baseline];
    if (original == null ||
        baseline.id != resourceId ||
        baseline.scope != scope ||
        baseline.collection != collection ||
        edit.title != baseline.title ||
        edit.labels.isNotEmpty ||
        edit.document.kind != kind) {
      throw StateError('Shared editing is body-only');
    }
    final doc = ComplexEditorDocument.parse(kind, edit.document.source);
    final current = await read(resourceId);
    _guard();
    if (current.resourceFingerprint != baseline.resourceFingerprint) {
      throw ComplexNoteConflict(current);
    }
    final prepared = await transport.prepare(
      original,
      doc,
      password: _password,
    );
    try {
      _guard();
      final receipt = await prepared.sendAfter(
        onSubmit: () async {
          _guard();
          await beforeSubmit?.call(original, doc);
          _guard();
        },
      );
      _guard();
      if (receipt['source_sha256'] != doc.digest ||
          receipt['modify_time'] is! String ||
          (receipt['modify_time'] as String).isEmpty) {
        throw StateError('Shared receipt requires read-only review');
      }
      await onKnownReceipt?.call(doc.digest, receipt['modify_time'] as String);
      _guard();
      final actual = await read(resourceId);
      _guard();
      if (!actual.document.same(doc)) {
        throw StateError('Shared save needs read-only review');
      }
      return actual;
    } on SharedCapabilityFailure catch (error) {
      if (error.status == 409) {
        throw ComplexNoteConflict(await read(resourceId));
      }
      rethrow;
    } finally {
      prepared.retire();
    }
  }

  @override
  void dispose() {
    if (_closed) return;
    _closed = true;
    _password = null;
    transport.close();
  }
}
