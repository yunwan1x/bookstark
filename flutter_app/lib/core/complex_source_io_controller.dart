import 'package:flutter/foundation.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/local_complex_editor_controller.dart';
import 'package:bookstark_flutter/core/local_complex_notes_repository.dart';
import 'native_complex_source_io.dart';

enum ComplexSourceIoPhase {
  idle,
  preparing,
  picking,
  confirming,
  checkpointing,
  writing,
  completed,
  cancelled,
  failed,
  retired,
}

/// No repository save method is called here. Durable draft remains the sole
/// imported output until the existing explicit Save coordinator is invoked.
class ComplexSourceIoController extends ChangeNotifier {
  ComplexSourceIoController({
    required this.editor,
    required this.owner,
    required this.capture,
    required this.prepareNative,
    required this.replaceSurface,
    required this.isCurrent,
    required this.onDurableHandoff,
    this.allowMemoryOnlyHandoff = false,
  });
  final LocalComplexEditorController editor;
  final ComplexSourceIoScope owner;
  final Future<ComplexEditorDocument> Function() capture;
  final Future<NativeComplexSourceIo> Function() prepareNative;
  final Future<void> Function() replaceSurface;
  final bool allowMemoryOnlyHandoff;
  final bool Function() isCurrent;
  final void Function(bool) onDurableHandoff;
  NativeComplexSourceIo? _native;
  bool _retired = false, _cancelRequested = false;
  ComplexSourceIoPhase phase = ComplexSourceIoPhase.idle;
  String? safeError;
  int written = 0, total = 0;
  bool get busy => {
    ComplexSourceIoPhase.preparing,
    ComplexSourceIoPhase.picking,
    ComplexSourceIoPhase.confirming,
    ComplexSourceIoPhase.checkpointing,
    ComplexSourceIoPhase.writing,
  }.contains(phase);
  void _guard() {
    owner.guard();
    if (editor.ephemeralDrafts && !allowMemoryOnlyHandoff) {
      throw StateError('Explicit memory-only handoff required');
    }
    if (_cancelRequested) throw const ComplexSourceIoCancelled();
    if (_retired || !isCurrent() || !editor.editable) {
      throw StateError('I/O owner unavailable');
    }
  }

  void _set(ComplexSourceIoPhase value) {
    phase = value;
    if (!_retired) notifyListeners();
  }

  ComplexNoteEdit _edit(ComplexEditorDocument document) => ComplexNoteEdit(
    title: editor.edit.title,
    document: document,
    labels: editor.edit.labels,
  );
  bool _beginExplicit() {
    owner.guard();
    if (_retired || !isCurrent() || !editor.editable) {
      throw StateError('I/O owner unavailable');
    }
    if (busy) {
      return false; // must not clear cancellation of an active operation
    }
    _cancelRequested = false;
    _guard();
    return true;
  }

  Future<ComplexEditorDocument> _freeze() async {
    _guard();
    final before = editor.baseline, document = await capture();
    _guard();
    if (!identical(before, editor.baseline) ||
        document.kind != before.document.kind) {
      throw StateError('Editor changed');
    }
    await editor.checkpoint(_edit(document));
    _guard();
    if (!editor.ephemeralDrafts && editor.dirty && !editor.draftDurable) {
      throw StateError('Durable source checkpoint required');
    }
    return document;
  }

  Future<void> importSource({
    required Future<bool> Function(ComplexSourceFile) confirm,
  }) async {
    if (!_beginExplicit()) return;
    safeError = null;
    _set(ComplexSourceIoPhase.preparing);
    var handoff = false, draftChanged = false;
    try {
      final frozen = await _freeze(), baseline = editor.baseline;
      _native = await prepareNative();
      _guard();
      onDurableHandoff(true);
      handoff = true;
      _set(ComplexSourceIoPhase.picking);
      final selected = await _native!.pick(frozen.kind);
      _guard();
      if (selected == null) {
        _set(ComplexSourceIoPhase.cancelled);
        return;
      }
      if (!identical(baseline, editor.baseline) ||
          !editor.edit.document.same(frozen)) {
        throw StateError('Draft changed while selecting');
      }
      _set(ComplexSourceIoPhase.confirming);
      final yes = await confirm(selected);
      _guard();
      if (!yes) {
        _set(ComplexSourceIoPhase.cancelled);
        return;
      }
      if (!identical(baseline, editor.baseline) ||
          !editor.edit.document.same(frozen)) {
        throw StateError('Draft changed after review');
      }
      _set(ComplexSourceIoPhase.checkpointing);
      await editor.checkpoint(_edit(selected.document));
      _guard();
      draftChanged = true;
      await replaceSurface();
      _guard();
      _set(ComplexSourceIoPhase.completed);
    } catch (_) {
      if (!_retired && _cancelRequested) {
        _set(ComplexSourceIoPhase.cancelled);
      } else if (!_retired) {
        safeError = editor.ephemeralDrafts
            ? '受保护草稿仅在本次会话内存中，关闭应用将丢失。操作未完成，未保存文档。 / Protected draft exists only in session memory and is lost when the app closes. Operation incomplete; document was not saved.'
            : draftChanged
            ? '导入草稿已保留；编辑器需重新打开，没有保存文档。 / Imported draft retained. Reopen editor; document was not saved.'
            : '未完成导入。原草稿与已保存内容保留，没有保存文档。 / Import incomplete. Original draft and saved content retained.';
        _set(ComplexSourceIoPhase.failed);
      }
    } finally {
      _native?.retire();
      _native = null;
      if (handoff) onDurableHandoff(false);
      // SAF retirement can happen even on cancel/invalid input. Recreate from
      // the last durable draft; never reload unconfirmed incoming bytes.
      if (handoff && !draftChanged && !_retired && isCurrent()) {
        try {
          await replaceSurface();
        } catch (_) {}
      }
    }
  }

  Future<void> exportSource({required String name}) async {
    if (!_beginExplicit()) return;
    safeError = null;
    written = 0;
    _set(ComplexSourceIoPhase.preparing);
    var handoff = false;
    try {
      final frozen = await _freeze();
      _native = await prepareNative();
      _guard();
      total = frozen.byteLength;
      onDurableHandoff(true);
      handoff = true;
      _set(ComplexSourceIoPhase.writing);
      final saved = await _native!.export(
        frozen,
        name: name,
        progress: (n, size) {
          written = n;
          total = size;
          if (!_retired) notifyListeners();
        },
      );
      _guard();
      _set(
        saved ? ComplexSourceIoPhase.completed : ComplexSourceIoPhase.cancelled,
      );
    } catch (_) {
      if (!_retired && _cancelRequested) {
        safeError =
            '导出已取消；目标可能包含部分内容。文档未保存。 / Export cancelled; destination may contain partial content. Editor document was not saved.';
        _set(ComplexSourceIoPhase.cancelled);
      } else if (!_retired) {
        safeError =
            '导出写入未确认；目标可能包含部分内容。没有保存编辑中的文档。 / Export unconfirmed; destination may contain partial data. Editor document was not saved.';
        _set(ComplexSourceIoPhase.failed);
      }
    } finally {
      _native?.retire();
      _native = null;
      if (handoff) onDurableHandoff(false);
      if (handoff && !_retired && isCurrent()) {
        try {
          await replaceSurface();
        } catch (_) {}
      }
    }
  }

  Future<void> cancel() async {
    _cancelRequested = true;
    await _native?.cancel();
  }

  void retire() {
    if (_retired) return;
    _retired = true;
    _native?.retire();
    phase = ComplexSourceIoPhase.retired;
    onDurableHandoff(false);
  }

  @override
  void dispose() {
    retire();
    super.dispose();
  }
}
