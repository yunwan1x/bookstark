import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'local_attachments.dart';
import 'local_store.dart';
import 'local_complex_notes_repository.dart';
import 'local_complex_editor_controller.dart';
import 'complex_editor_document.dart';
import 'complex_recovery_vault.dart';
import 'native_complex_source_io.dart';
import 'local_drawing_image_references.dart';
import 'local_drawing_image_resources.dart';

/// Only actual ordinary local positive-ID note/article repositories can create
/// this capability. Remote, book, generation15 and ephemeral protected editors
/// cannot acquire it by passing a plausible attachment URI.
final class LocalDrawingImageOwner {
  LocalDrawingImageOwner._(
    this.store,
    this.controller,
    this.sourceOwner,
    this.attachments,
    this.isCurrentScope,
  ) : _resourceId = controller.baseline.id,
      _collection = controller.baseline.collection,
      _repositoryScope = controller.baseline.scope {
    _scopeDrain = retireAndDrain;
    sourceOwner.addRetirementDrain(_scopeDrain);
  }
  final LocalStore store;
  final LocalComplexEditorController controller;
  final ComplexSourceIoScope sourceOwner;
  final LocalAttachments attachments;
  final bool Function() isCurrentScope;
  final int _resourceId;
  final String _collection, _repositoryScope;
  late final Future<void> Function() _scopeDrain;
  final Set<LocalDrawingImageResources> _bodies = {};
  bool _retired = false;
  void Function()? onReadFailure;
  final Set<void Function()> _retirementListeners = {};
  Future<void>? _retirement;

  static LocalDrawingImageOwner open({
    required LocalStore store,
    required LocalComplexEditorController controller,
    required ComplexSourceIoScope sourceOwner,
    required bool Function() isCurrentScope,
  }) {
    sourceOwner.guard();
    final repository = controller.repository;
    final baseline = controller.baseline;
    final paths = store.dataPaths;
    if (paths == null ||
        repository is! LocalComplexNotesRepository ||
        !identical(repository.store, store) ||
        baseline.id < 1 ||
        !{'note', 'article'}.contains(baseline.collection) ||
        baseline.document.kind != ComplexEditorKind.drawing ||
        repository.kind != ComplexEditorKind.drawing ||
        repository.scope != baseline.scope ||
        repository.collection != baseline.collection ||
        controller.ephemeralDrafts ||
        controller.busy ||
        !isCurrentScope() ||
        store.maintenance.retired) {
      throw StateError('Actual ordinary-local drawing owner required');
    }
    return LocalDrawingImageOwner._(
      store,
      controller,
      sourceOwner,
      LocalAttachments(paths.attachments, maintenance: store.maintenance),
      isCurrentScope,
    );
  }

  bool get rootCurrent {
    try {
      sourceOwner.guard();
      return !_retired &&
          isCurrentScope() &&
          !store.maintenance.retired &&
          !controller.ephemeralDrafts &&
          controller.baseline.id == _resourceId &&
          controller.baseline.collection == _collection &&
          controller.baseline.scope == _repositoryScope &&
          controller.baseline.document.kind == ComplexEditorKind.drawing;
    } catch (_) {
      return false;
    }
  }

  bool get current =>
      rootCurrent && controller.editable && !controller.requiresReview;
  void guard() {
    if (!current) throw StateError('Local drawing image owner retired');
  }

  LocalDrawingImageResources bind(ComplexEditorDocument document) {
    guard();
    if (document.kind != ComplexEditorKind.drawing ||
        !document.same(controller.edit.document)) {
      throw StateError('Actual current drawing source required');
    }
    final baseline = controller.baseline;
    final baselineFingerprint = complexNoteFingerprint(baseline);
    final identity = sha256
        .convert(
          utf8.encode(
            jsonEncode([
              'ordinary-local-drawing-images-v1',
              store.path,
              baseline.scope,
              baseline.collection,
              baseline.id,
              'drawing',
              baselineFingerprint,
              document.digest,
              sourceOwner.scope,
              sourceOwner.epoch,
            ]),
          ),
        )
        .toString();
    LocalDrawingImageReferences references;
    try {
      references = LocalDrawingImageReferences.capture(document);
    } on FormatException {
      references = LocalDrawingImageReferences.unavailable(document);
    }
    late final LocalDrawingImageResources resources;
    resources = LocalDrawingImageResources(
      attachments: attachments,
      references: references,
      onReadFailure: () {
        if (current && resources.current) onReadFailure?.call();
      },
      identity: identity,
      // A real same-resource Save acknowledgement does not change this native
      // body's captured source grant. Only initial exact source references and
      // separately verified explicit selections remain authorized until retire.
      isCurrentScope: () => current,
      onRetired: () {
        _bodies.remove(resources);
      },
    );
    _bodies.add(resources);
    return resources;
  }

  late final LocalDrawingImageResources Function(ComplexEditorDocument)
  resourceFactory = bind;

  LocalDrawingImageResources get currentBody {
    guard();
    final bodies = _bodies.where((body) => body.current).toList();
    if (bodies.length != 1) {
      throw StateError('One actual current drawing resource body required');
    }
    return bodies.single;
  }

  bool ownsBody(LocalDrawingImageResources resources) =>
      current && resources.current && _bodies.contains(resources);

  Future<void> release(LocalDrawingImageResources resources) async {
    if (!_bodies.contains(resources)) return;
    await resources.retireAndDrain();
    _bodies.remove(resources);
  }

  void addRetirementListener(void Function() listener) {
    if (!_retired) _retirementListeners.add(listener);
  }

  void removeRetirementListener(void Function() listener) {
    _retirementListeners.remove(listener);
  }

  Future<void> retireAndDrain() {
    if (!_retired) {
      _retired = true;
      final listeners = _retirementListeners.toList();
      _retirementListeners.clear();
      for (final listener in listeners) {
        listener();
      }
    }
    return _retirement ??=
        Future.wait<void>([
          for (final body in _bodies.toList()) body.retireAndDrain(),
        ]).then((_) {
          _bodies.clear();
          sourceOwner.removeRetirementDrain(_scopeDrain);
        });
  }
}
