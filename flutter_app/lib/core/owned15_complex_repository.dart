import 'owned15_generation_resource_factory.dart';
import 'owned15_generation_resources.dart';
import 'dart:convert';
import 'dart:async';
import 'attachments.dart';
import 'package:crypto/crypto.dart';
import 'complex_editor_document.dart';
import 'local_complex_notes_repository.dart';
import 'local_generation_content_repository.dart';
import 'owned15_save_journal.dart';
import 'owned_writable_generation15.dart';
import 'protected_owned_complex_journal.dart';

/// Existing-ID local15 body/metadata save only. Uses the original generation
/// crypto/full-tuple CAS implementation; it never INSERTs or upgrades a DB.
final class Owned15ComplexRepository implements ComplexNotesRepository {
  Owned15ComplexRepository._({
    required this.owner,
    required this.journal,
    required this.collection,
    required this.resourceId,
    required this.kind,
    required this.scope,
    required this.isCurrentScope,
    required GenerationContentHandle initial,
    this._password,
  }) : _handle = initial;
  final OwnedWritableGeneration15 owner;
  final Owned15SaveJournal journal;
  final int resourceId;
  @override
  final String collection, scope;
  @override
  final ComplexEditorKind kind;
  final bool Function() isCurrentScope;
  GenerationContentHandle? _handle;
  String? _password;
  bool _closed = false;
  final _requests = <AttachmentCancellation>{};
  final _inflight = <Future<void>>{};
  Future<T> _run<T>(Future<T> Function(AttachmentCancellation) action) async {
    _check();
    final request = AttachmentCancellation();
    final done = Completer<void>();
    _requests.add(request);
    _inflight.add(done.future);
    try {
      final result = await action(request);
      _check();
      return result;
    } finally {
      _requests.remove(request);
      _inflight.remove(done.future);
      done.complete();
    }
  }

  final Set<Owned15GenerationResources> _assetScopes = {};
  int _assetEpoch = 0;
  bool _assetsPaused = false;
  Future<void> revokeResources() async {
    _assetEpoch++;
    final scopes = _assetScopes.toList(growable: false);
    await Future.wait(scopes.map((scope) => scope.retire()));
    _assetScopes.removeAll(scopes);
  }

  Future<Owned15GenerationResources?> resourcesForDocument(
    ComplexEditorDocument document,
  ) => _run((request) async {
    final handle = _handle;
    final resourceEpoch = _assetEpoch;
    if (_assetsPaused ||
        handle == null ||
        !handle.isCurrent ||
        document.source != handle.source ||
        await journal.load() != null) {
      return null;
    }
    request.check();
    final resource = await bindOwned15GenerationResources(
      owner: owner,
      content: handle,
      document: document,
      fullFingerprint: _fingerprint(handle),
      isCurrent: () =>
          !_closed &&
          !_assetsPaused &&
          resourceEpoch == _assetEpoch &&
          identical(_handle, handle) &&
          owner.current &&
          isCurrentScope(),
    );
    if (resource != null) {
      if (_closed ||
          _assetsPaused ||
          resourceEpoch != _assetEpoch ||
          !identical(_handle, handle) ||
          request.cancelled) {
        await resource.retire();
        return null;
      }
      _assetScopes.removeWhere((scope) => scope.drained);
      _assetScopes.add(resource);
    }
    return resource;
  });
  Future<void> drain() async {
    await revokeResources();
    while (_inflight.isNotEmpty) {
      await Future.wait(_inflight.toList());
    }
    await owner.content.crypto.drain();
  }

  static Future<Owned15ComplexRepository> open({
    required OwnedWritableGeneration15 owner,
    required Owned15SaveJournal journal,
    required String collection,
    required int resourceId,
    required bool Function() isCurrentScope,
    required AttachmentCancellation cancellation,
    String? password,
  }) async {
    if (!const {'note', 'article'}.contains(collection) ||
        resourceId <= 0 ||
        !owner.current ||
        !isCurrentScope()) {
      throw StateError('Owned15 resource unavailable');
    }
    if (journal.ownerTag !=
            Owned15SaveJournal.ownerTagForGeneration(
              owner.generation.draftNamespace,
            ) ||
        journal.scope !=
            Owned15SaveJournal.scopeForResource(
              draftNamespace: owner.generation.draftNamespace,
              collection: collection,
              resourceId: resourceId,
            )) {
      throw StateError('Owned15 journal belongs to another resource');
    }
    cancellation.check();
    await owner.confirmCurrent();
    cancellation.check();
    final handle = await owner.content.open(
      resourceId,
      collection: collection,
      password: password,
      cancellation: cancellation,
    );
    try {
      if (!owner.current || !isCurrentScope()) {
        throw StateError('Owned15 owner changed');
      }
      final kind = ComplexEditorKind.parse(handle.metadata.format.name);
      if (kind == ComplexEditorKind.markdown && collection == 'note') {
        throw StateError(
          'Owned15 Markdown notes require their native memory editor',
        );
      }
      final scope = sha256
          .convert(
            utf8.encode(
              jsonEncode([
                'owned15-complex-editor-v1',
                owner.pointer.encode(),
                collection,
                resourceId,
                kind.name,
              ]),
            ),
          )
          .toString();
      return Owned15ComplexRepository._(
        owner: owner,
        journal: journal,
        collection: collection,
        resourceId: resourceId,
        kind: kind,
        scope: scope,
        isCurrentScope: isCurrentScope,
        initial: handle,
        password: password,
      );
    } catch (_) {
      handle.close();
      rethrow;
    }
  }

  void _check() {
    bool current = false;
    try {
      current = owner.current && isCurrentScope();
    } catch (_) {}
    if (_closed || !current) throw StateError('Owned15 editor retired');
  }

  String _fingerprint(GenerationContentHandle handle) => sha256
      .convert(
        utf8.encode(
          jsonEncode([
            'owned15-actual-fulltuple-v1',
            owner.pointer.encode(),
            handle.resourceFingerprint,
          ]),
        ),
      )
      .toString();
  ComplexNote _project(GenerationContentHandle handle) {
    _check();
    if (!handle.isCurrent ||
        handle.metadata.id != resourceId ||
        handle.metadata.collection != collection ||
        handle.metadata.format.name != kind.name) {
      throw StateError('Owned15 actual resource identity changed');
    }
    return ComplexNote(
      scope: scope,
      id: resourceId,
      collection: collection,
      title: handle.metadata.title,
      document: ComplexEditorDocument.parse(kind, handle.source),
      version: handle.metadata.revision,
      labels: handle.metadata.labels,
      resourceFingerprint: _fingerprint(handle),
    );
  }

  ComplexNote get baseline {
    final handle = _handle;
    if (handle == null) throw StateError('Owned15 unlocked handle unavailable');
    return _project(handle);
  }

  ProtectedComplexObservation observation(ComplexNote note) {
    _check();
    if (note.scope != scope ||
        note.id != resourceId ||
        note.collection != collection ||
        note.document.kind != kind ||
        note.resourceFingerprint == null) {
      throw StateError('Owned15 observation identity mismatch');
    }
    return ProtectedComplexObservation(
      fingerprint: note.resourceFingerprint!,
      inputDigest: inputDigest(note.title, note.document.source, note.labels),
    );
  }

  static String inputDigest(String title, String source, List<String> labels) =>
      sha256
          .convert(
            utf8.encode(
              jsonEncode(['owned15-save-input-v1', title, labels, source]),
            ),
          )
          .toString();
  @override
  Future<ComplexNote> read(int id) => _run((cancellation) async {
    await revokeResources();
    _check();
    if (id != resourceId) throw ArgumentError('Existing owned15 ID required');
    await owner.confirmCurrent();
    _check();
    final next = await owner.content.open(
      id,
      collection: collection,
      password: _password,
      cancellation: cancellation,
    );
    try {
      final actual = _project(next);
      final old = _handle;
      _handle = next;
      if (!identical(old, next)) old?.close();
      return actual;
    } catch (_) {
      next.close();
      rethrow;
    }
  });
  @override
  Future<ComplexNote> save(ComplexNote before, ComplexNoteEdit edit) => _run((
    cancellation,
  ) async {
    _assetsPaused = true;
    await revokeResources();
    _check();
    final handle = _handle;
    if (handle == null ||
        !handle.isCurrent ||
        !baseline.same(before) ||
        edit.document.kind != kind) {
      throw StateError('Owned15 save baseline changed');
    }
    edit.validate();
    final digest = inputDigest(edit.title, edit.document.source, edit.labels);
    // A successful durable claim is the sole authorization for ONE UPDATE.
    await journal.claimUnknown(
      baselineFingerprint: before.resourceFingerprint!,
      inputDigest: digest,
    );
    _check();
    try {
      final next = await owner.content.save(
        handle,
        title: edit.title,
        source: edit.document.source,
        labels: edit.labels,
        cancellation: cancellation,
      );
      _check();
      final actual = _project(next);
      _handle = next;
      if (!edit.matches(actual)) {
        throw StateError('Owned15 save receipt differs');
      }
      journal.rememberKnownReceipt(actual.resourceFingerprint!);
      // The memory store's explicit remove/cleanup persists+finishes the known
      // receipt. A storage failure therefore retries storage, never this UPDATE.
      return actual;
    } on GenerationContentWriteUncertain catch (error) {
      if (!error.knownCommitted) rethrow;
      _check();
      final actual = await read(resourceId);
      if (actual.version != error.expectedRevision || !edit.matches(actual)) {
        throw StateError('Known owned15 commit cannot be freshly bound');
      }
      journal.rememberKnownReceipt(actual.resourceFingerprint!);
      return actual;
    }
  });
  Future<void> endWarmReview(ComplexNote reviewed) => journal.endReviewed(
    reviewedFingerprint: observation(reviewed).fingerprint,
    fresh: () async => observation(await read(resourceId)),
  );
  @override
  void dispose() {
    _closed = true;
    for (final scope in _assetScopes) {
      unawaited(scope.retire().catchError((Object _) {}));
    }
    for (final request in _requests) {
      request.cancel();
    }
    _password = null;
    _handle?.close();
    _handle = null;
    // Journal/preview/memory retirement belongs to the registered lifetime.
  }
}
