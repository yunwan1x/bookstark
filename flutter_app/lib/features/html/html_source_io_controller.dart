import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/html_editor_controller.dart';
import 'package:bookstark_flutter/core/html_notes_repository.dart';
import 'package:bookstark_flutter/core/native_complex_source_io.dart';
import 'html_source_coordinator.dart';

/// Existing HTML journal only. Never saves SQL or manufactures a complex-note
/// repository. The page retires the old source generation before applying bytes.
class HtmlSourceIoController {
  HtmlSourceIoController({
    required this.editor,
    required this.source,
    required this.scope,
    required this.isCurrent,
    required this.prepareNative,
    required this.retireSurface,
    required this.remount,
  });
  final HtmlEditorController editor;
  final HtmlSourceCoordinator source;
  final ComplexSourceIoScope scope;
  final bool Function() isCurrent;
  final Future<NativeComplexSourceIo> Function() prepareNative;
  final Future<void> Function() retireSurface, remount;
  NativeComplexSourceIo? _native;
  bool _retired = false, busy = false, completed = false, cancelled = false;
  bool draftChanged = false;
  String? safeError;
  void _guard() {
    scope.guard();
    if (_retired ||
        !isCurrent() ||
        !editor.canEdit ||
        editor.busy ||
        editor.hasPendingOperation ||
        !editor.canPersistDraft) {
      throw StateError('HTML source I/O unavailable');
    }
  }

  bool _sameDraft(HtmlNoteEdit expected) {
    final actual = editor.draft;
    if (actual.title != expected.title ||
        actual.source != expected.source ||
        actual.labels.length != expected.labels.length) {
      return false;
    }
    for (var i = 0; i < actual.labels.length; i++) {
      if (actual.labels[i] != expected.labels[i]) return false;
    }
    return true;
  }

  Future<void> run({
    required bool importing,
    required Future<bool> Function(ComplexSourceFile) confirm,
  }) async {
    _guard();
    if (busy) return;
    if (!source.ready || source.busy) {
      throw StateError('HTML source generation unavailable');
    }
    busy = true;
    safeError = null;
    completed = false;
    cancelled = false;
    draftChanged = false;
    var nativeStarted = false;
    try {
      // Coordinator serializes genuine immutable engine capture and durable
      // checkpoint in the legacy journal before acquiring any picker grant.
      if (!await source.checkpoint(keepLocked: true)) {
        throw StateError('HTML durable checkpoint unconfirmed');
      }
      _guard();
      final baseline = editor.baseline, frozen = editor.draft;
      final document = ComplexEditorDocument.parse(
        ComplexEditorKind.html,
        frozen.source,
      );
      _native = await prepareNative();
      _guard();
      nativeStarted = true;
      if (importing) {
        final incoming = await _native!.pick(ComplexEditorKind.html);
        _guard();
        // Join the old browser's forced capture queue before inspecting or
        // replacing its frozen draft. A stale old capture cannot follow import.
        await retireSurface();
        _guard();
        if (!identical(baseline, editor.baseline) || !_sameDraft(frozen)) {
          throw StateError('HTML draft changed during source selection');
        }
        if (incoming == null) {
          cancelled = true;
          return;
        }
        if (!await confirm(incoming)) {
          _guard();
          cancelled = true;
          return;
        }
        _guard();
        if (!identical(baseline, editor.baseline) || !_sameDraft(frozen)) {
          throw StateError('HTML draft changed after source confirmation');
        }
        editor.edit(
          HtmlNoteEdit(
            title: frozen.title,
            source: incoming.document.source,
            labels: frozen.labels,
          ),
        );
        draftChanged = true;
        if (!await editor.flushRecovery()) {
          throw StateError('Imported HTML recovery unconfirmed');
        }
        _guard();
        completed = true;
      } else {
        completed = await _native!.export(document, name: 'html-source.html');
        _guard();
        cancelled = !completed;
        await retireSurface();
        _guard();
      }
    } catch (_) {
      if (!_retired) {
        safeError = draftChanged
            ? 'Imported HTML remains in this page; recovery is unconfirmed. Do not close before retrying. No document was saved.'
            : 'HTML source operation incomplete. The original draft and saved document remain; an export target may contain partial data.';
      }
    } finally {
      _native?.retire();
      _native = null;
      // Rebuild only from the current controller draft, never unconfirmed picker
      // bytes. This also restores editability after cancel/expected SAF pause.
      if (!_retired && isCurrent()) {
        if (nativeStarted) {
          try {
            await retireSurface();
            _guard();
            await remount();
          } catch (_) {}
        } else {
          try {
            await source.unlock();
          } catch (_) {}
        }
      }
      busy = false;
    }
  }

  Future<void> cancel() async {
    await _native?.cancel();
  }

  void retire() {
    _retired = true;
    _native?.retire();
  }
}
