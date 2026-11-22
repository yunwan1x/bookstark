part of 'remote_owned_complex_store.dart';

class ProtectedOwnedComplexStore extends RemoteOwnedComplexStore {
  ProtectedOwnedComplexStore({
    required super.client,
    required super.memberId,
    required super.resourceId,
    required super.kind,
    required String recoveryNamespace,
    required super.isCurrent,
    required String password,
    required this.journal,
  }) : _password = password,
       super(
         bookId: 0,
         note: true,
         protectedSource: true,
         recoveryNamespace: recoveryNamespace,
       ) {
    final expected = ProtectedOwnedComplexJournal.scopeFor(
      server: client.baseUri.toString(),
      memberId: memberId,
      namespace: recoveryNamespace,
      resourceId: resourceId,
      kind: kind.name,
    );
    final expectedOwner = ProtectedOwnedComplexJournal.ownerTagFor(
      server: client.baseUri.toString(),
      memberId: memberId,
      namespace: recoveryNamespace,
    );
    if (journal.scope != expected ||
        journal.ownerTag != expectedOwner ||
        password.isEmpty) {
      throw ArgumentError('Wrong protected journal');
    }
  }
  final ProtectedOwnedComplexJournal journal;
  String? _password;
  String editDigest(ComplexNoteEdit edit) => sha256
      .convert(
        utf8.encode(
          jsonEncode([
            scope,
            resourceId,
            kind.name,
            edit.title,
            edit.labels,
            edit.document.source,
          ]),
        ),
      )
      .toString();
  ProtectedComplexObservation observation(ComplexNote actual) =>
      ProtectedComplexObservation(
        fingerprint: actual.resourceFingerprint!,
        inputDigest: editDigest(
          ComplexNoteEdit(
            title: actual.title,
            labels: actual.labels,
            document: actual.document,
          ),
        ),
      );
  @override
  Future<ComplexNote> read(int id) async {
    _guard();
    if (id != resourceId || _password == null) {
      throw StateError('Protected identity changed');
    }
    final response = await client.unlockProtectedOwnedComplexJson(
      resourceId,
      kind: kind.name,
      password: _password!,
      expectedSessionRevision: revision,
      abortTrigger: _abort.future,
    );
    _guard();
    return _decode(response);
  }

  @override
  Future<ComplexNote> save(ComplexNote baseline, ComplexNoteEdit edit) async {
    _guard();
    if (_password == null ||
        _owned[baseline] != true ||
        baseline.id != resourceId ||
        baseline.scope != scope ||
        baseline.collection != collection ||
        baseline.resourceFingerprint == null ||
        edit.document.kind != kind ||
        edit.title != baseline.title ||
        jsonEncode(edit.labels) != jsonEncode(baseline.labels)) {
      throw StateError('Protected body-only baseline required');
    }
    final source = ComplexEditorDocument.parse(kind, edit.document.source);
    if (isLocalProtectedEnvelopePrefix(source.source)) {
      throw NoteLocked(resourceId);
    }
    final prepared = await client.prepareProtectedOwnedComplexSourcePut(
      resourceId,
      kind: kind.name,
      password: _password!,
      expectedFingerprint: baseline.resourceFingerprint!,
      sourceBytes: utf8.encode(source.source),
      expectedSessionRevision: revision,
      abortTrigger: _abort.future,
    );
    try {
      _guard();
      final response = await prepared.sendAfter(
        onSubmit: () => journal.claimUnknown(
          baselineFingerprint: baseline.resourceFingerprint!,
          inputDigest: editDigest(edit),
        ),
      );
      _guard();
      final saved = _decode(response);
      if (!edit.matches(saved)) {
        throw StateError('Protected save receipt mismatch');
      }
      journal.rememberKnownReceipt(saved.resourceFingerprint!);
      return saved;
    } on ApiFailure catch (error) {
      if (error.status == 409) {
        final actual = await read(resourceId);
        throw ComplexNoteConflict(actual);
      }
      rethrow;
    } finally {
      prepared.retire();
    }
  }

  Future<void> endWarmReview(ComplexNote actual) => journal.endReviewed(
    reviewedFingerprint: actual.resourceFingerprint!,
    fresh: () async => observation(await read(resourceId)),
  );
  @override
  void dispose() {
    _password = null;
    super.dispose();
  }
}
