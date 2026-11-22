import 'package:bookstark_flutter/core/local_complex_notes_repository.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/remote_markdown_creation_controller.dart';
import 'package:bookstark_flutter/core/remote_markdown_creation_vault.dart';
import 'package:bookstark_flutter/features/complex_editors/local_article_creation_source_coordinator.dart';

/// Uses the already exercised capture/lock/release ordering, while the remote
/// controller alone owns durable intent and the single POST boundary.
class RemoteArticleCreationSourceBinding {
  RemoteArticleCreationSourceBinding({
    required this.controller,
    required this.isCurrent,
  }) {
    if (controller.vault.scope.collection != 'article') {
      throw StateError('Article creation scope required');
    }
    source = LocalArticleCreationSourceCoordinator(
      freezeEdit: (body) => ComplexNoteEdit(
        title: controller.record.input.title,
        document: _document(body),
        labels: controller.record.input.labels,
      ),
      applyCapturedEdit: (edit) {
        _guard();
        // Input validation happens before mutating the remote controller.
        _captured = MarkdownCreationInput(
          title: edit.title,
          content: edit.document.source,
          labels: edit.labels,
        );
      },
      flushCreationJournal: () async {
        _guard();
        final captured = _captured;
        if (captured == null || !controller.canEdit) return false;
        await controller.edit(captured);
        _guard();
        final durable =
            controller.canEdit &&
            !controller.record.pending &&
            controller.record.input.fingerprint == captured.fingerprint;
        if (durable && identical(_captured, captured)) _captured = null;
        return durable;
      },
      create: () async {
        _guard();
        if (!controller.canEdit || _captured != null) {
          throw StateError('Durable complete source required');
        }
        await controller.save();
      },
      creationStillEditable: () =>
          !_retired && isCurrent() && controller.canEdit,
      pendingOrUnknown: () => _retired || !isCurrent() || !controller.canEdit,
    );
  }
  final RemoteMarkdownCreationController controller;
  final bool Function() isCurrent;
  late final LocalArticleCreationSourceCoordinator source;
  MarkdownCreationInput? _captured;
  bool _retired = false;
  ComplexEditorDocument _document(String body) =>
      ComplexEditorDocument.parse(ComplexEditorKind.markdown, body);
  void _guard() {
    if (_retired || !isCurrent()) throw StateError('Article creation retired');
  }

  Future<void> retireAndDrain() async {
    _retired = true;
    source.invalidate();
    await source.dispose();
  }
}
