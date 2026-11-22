import 'complex_editor_document.dart';
import 'owned15_generation_resource_factory.dart';
import 'owned15_generation_resources.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'attachments.dart';
import 'notes_repository.dart';
import 'local_generation_content_repository.dart';
import 'owned15_save_journal.dart';
import 'owned_writable_generation15.dart';
import 'protected_owned_complex_journal.dart';

/// Unknown is deliberately not NoteSaveFailure: no saved-ID acknowledgement.
final class Owned15NativeSaveNeedsReview implements Exception {
  const Owned15NativeSaveNeedsReview();
  @override
  String toString() =>
      '保存结果需只读核对，不会再次提交。 / Read-only review is required; this save will not be replayed.';
}

/// Existing native Markdown NOTE only. Every body/password/known input remains
/// process memory. The caller must pass drafts:null and register real lifetime.
final class Owned15NativeNotesRepository extends NotesRepository {
  Owned15NativeNotesRepository._(
    this.owner,
    this.journal,
    this.resourceId,
    this.isCurrentScope,
    this._handle,
    this._password,
  );
  final OwnedWritableGeneration15 owner;
  final Owned15SaveJournal journal;
  final int resourceId;
  final bool Function() isCurrentScope;
  GenerationContentHandle? _handle;
  String? _password;
  Note? _knownInput;
  bool _closed = false, _unknown = false;
  final ValueNotifier<bool> reviewRequired = ValueNotifier(false);
  final _requests = <AttachmentCancellation>{};
  final _inflight = <Future<void>>{};
  static Future<Owned15NativeNotesRepository> open({
    required OwnedWritableGeneration15 owner,
    required Owned15SaveJournal journal,
    required int resourceId,
    required bool Function() isCurrentScope,
    required AttachmentCancellation cancellation,
    String? password,
  }) async {
    cancellation.check();
    if (resourceId <= 0 ||
        !owner.current ||
        !isCurrentScope() ||
        journal.ownerTag !=
            Owned15SaveJournal.ownerTagForGeneration(
              owner.generation.draftNamespace,
            ) ||
        journal.scope !=
            Owned15SaveJournal.scopeForResource(
              draftNamespace: owner.generation.draftNamespace,
              collection: 'note',
              resourceId: resourceId,
            )) {
      throw StateError('Owned15 native resource identity mismatch');
    }
    await owner.confirmCurrent();
    cancellation.check();
    final handle = await owner.content.open(
      resourceId,
      collection: 'note',
      password: password,
      cancellation: cancellation,
    );
    try {
      if (!owner.current || !isCurrentScope()) {
        throw StateError('Owned15 owner changed');
      }
      if (handle.metadata.format.name != 'markdown') {
        throw DedicatedEditorRequired(resourceId, handle.metadata.format.name);
      }
      return Owned15NativeNotesRepository._(
        owner,
        journal,
        resourceId,
        isCurrentScope,
        handle,
        password,
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
    if (_closed || !current) throw StateError('Owned15 native editor retired');
  }

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
      fullFingerprint: resourceFingerprint,
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

  String get resourceFingerprint {
    _check();
    final handle = _handle;
    if (handle == null || !handle.isCurrent) {
      throw StateError('Owned15 native handle unavailable');
    }
    return sha256
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
  }

  static String inputDigest(Note note) => sha256
      .convert(
        utf8.encode(
          jsonEncode([
            'owned15-save-input-v1',
            note.title,
            note.labels,
            note.content,
          ]),
        ),
      )
      .toString();
  Note _project(GenerationContentHandle handle) {
    _check();
    if (!handle.isCurrent ||
        handle.metadata.id != resourceId ||
        handle.metadata.collection != 'note' ||
        handle.metadata.format.name != 'markdown') {
      throw StateError('Owned15 native actual type changed');
    }
    return Note(
      id: resourceId,
      title: handle.metadata.title,
      content: handle.source,
      labels: handle.metadata.labels,
      isProtected: handle.metadata.isProtected,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(handle.metadata.updatedAt),
    );
    // unlockPassword deliberately stays null; only this repository owns it.
  }

  Note get baseline {
    final handle = _handle;
    if (handle == null) throw StateError('Owned15 native handle unavailable');
    return _project(handle);
  }

  ProtectedComplexObservation observation(Note value) {
    _check();
    if (value.id != resourceId || !_same(value, baseline)) {
      throw StateError(
        'Owned15 native observation is not the current full snapshot',
      );
    }
    return ProtectedComplexObservation(
      fingerprint: resourceFingerprint,
      inputDigest: inputDigest(value),
    );
  }

  static bool _same(Note a, Note b) =>
      a.id == b.id &&
      a.title == b.title &&
      a.content == b.content &&
      jsonEncode(a.labels) == jsonEncode(b.labels);
  @override
  Future<Note> read(int id) => _run((request) async {
    await revokeResources();
    if (id != resourceId) throw ArgumentError('Existing owned15 ID required');
    await owner.confirmCurrent();
    _check();
    final next = await owner.content.open(
      id,
      collection: 'note',
      password: _password,
      cancellation: request,
    );
    try {
      final actual = _project(next);
      final old = _handle;
      _handle = next;
      old?.close();
      return actual;
    } catch (_) {
      next.close();
      rethrow;
    }
  });
  Future<int> _finishKnown() async {
    try {
      await journal.finishKnown();
      _check();
      _knownInput = null;
      return resourceId;
    } catch (_) {
      throw NoteSaveFailure(
        resourceId,
        '已保存，本机确认未完成。再次保存只处理本机确认。 / Saved; local acknowledgement is unfinished. Retry handles local storage only.',
      );
    }
  }

  @override
  Future<int> save(Note note) => _run((request) async {
    _assetsPaused = true;
    await revokeResources();
    if (note.id != resourceId) {
      throw ArgumentError('Native owned15 editor cannot INSERT or change ID');
    }
    final known = _knownInput;
    if (known != null) {
      if (!_same(note, known)) {
        throw StateError(
          '请先返回核对上次保存；不会覆盖新内容。 / Review the previous save before changing its acknowledgement.',
        );
      }
      return _finishKnown();
    }
    if (_unknown) throw const Owned15NativeSaveNeedsReview();
    final handle = _handle;
    if (handle == null || !handle.isCurrent) {
      throw StateError('Owned15 native baseline unavailable');
    }
    try {
      await journal.claimUnknown(
        baselineFingerprint: resourceFingerprint,
        inputDigest: inputDigest(note),
      );
      _check();
      GenerationContentHandle next;
      try {
        next = await owner.content.save(
          handle,
          title: note.title,
          source: note.content,
          labels: note.labels,
          cancellation: request,
        );
      } on GenerationContentWriteUncertain catch (error) {
        if (!error.knownCommitted) rethrow;
        final actual = await read(resourceId);
        if (_handle!.metadata.revision != error.expectedRevision ||
            !_same(note, actual)) {
          throw StateError('Known owned15 native receipt changed');
        }
        next = _handle!;
      }
      _check();
      _handle = next;
      final actual = _project(next);
      if (!_same(note, actual)) {
        throw StateError('Owned15 native receipt differs');
      }
      journal.rememberKnownReceipt(resourceFingerprint);
      _knownInput = actual;
    } catch (_) {
      _unknown = true;
      if (!_closed) reviewRequired.value = true;
      throw const Owned15NativeSaveNeedsReview();
    }
    return _finishKnown();
  });
  Future<void> endWarmReview(Note reviewed) => journal.endReviewed(
    reviewedFingerprint: observation(reviewed).fingerprint,
    fresh: () async => observation(await read(resourceId)),
  );
  @override
  Future<List<Note>> list({String keyword = '', int page = 1}) =>
      throw UnsupportedError('Use the owned generation typed metadata list');
  @override
  Future<void> remove(int id) => throw UnsupportedError(
    'This existing-ID memory editor has no delete capability',
  );
  void dispose() {
    _closed = true;
    for (final scope in _assetScopes) {
      unawaited(scope.retire().catchError((Object _) {}));
    }
    for (final request in _requests) {
      request.cancel();
    }
    _knownInput = null;
    _password = null;
    _handle?.close();
    _handle = null;
  }
}
