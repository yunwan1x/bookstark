import 'local_article_creation_controller.dart';
import 'local_complex_notes_repository.dart';
import 'native_complex_source_io.dart';

/// Operates only on the existing durable creation draft, never creates a row.
class LocalArticleCreationSourceIo {
  LocalArticleCreationSourceIo({
    required this.controller,
    required this.owner,
    required this.isCurrent,
    required this.checkpoint,
    required this.prepareNative,
    required this.retireSurface,
    required this.remount,
  });
  final LocalArticleCreationController controller;
  final ComplexSourceIoScope owner;
  final bool Function() isCurrent;
  final Future<bool> Function() checkpoint;
  final Future<NativeComplexSourceIo> Function() prepareNative;
  final Future<void> Function() retireSurface, remount;
  NativeComplexSourceIo? _native;
  bool _busy = false, _cancelled = false, _retired = false;
  bool get busy => _busy;
  bool completed = false;
  void _guard() {
    owner.guard();
    if (_retired || _cancelled || !isCurrent() || !controller.canEdit) {
      throw StateError('Creation source I/O retired');
    }
  }

  Future<void> run({
    required bool importing,
    required Future<bool> Function(ComplexSourceFile) confirm,
  }) async {
    if (_busy) return;
    _cancelled = false;
    completed = false;
    _guard();
    _busy = true;
    var handoff = false;
    try {
      if (!await checkpoint()) {
        throw StateError('Creation checkpoint unconfirmed');
      }
      _guard();
      final frozen = controller.draft;
      _native = await prepareNative();
      _guard();
      handoff = true;
      if (importing) {
        final file = await _native!.pick(frozen.document.kind);
        _guard();
        if (file == null) return;
        if (!controller.draft.document.same(frozen.document)) {
          throw StateError('Creation draft changed');
        }
        if (!await confirm(file)) return;
        _guard();
        // Complete old capture/timer writes before any new imported draft.
        await retireSurface();
        _guard();
        if (!controller.draft.document.same(frozen.document)) {
          throw StateError('Creation draft changed');
        }
        controller.edit(
          ComplexNoteEdit(
            title: frozen.title,
            labels: frozen.labels,
            document: file.document,
          ),
        );
        if (!await controller.flush()) {
          throw StateError('Imported draft durability unconfirmed');
        }
        _guard();
        completed = true;
      } else {
        if (!await _native!.export(
          frozen.document,
          name: 'article-source.md',
        )) {
          return;
        }
        _guard();
        completed = true;
      }
    } finally {
      _native?.retire();
      _native = null;
      _busy = false;
      if (handoff && !_retired && isCurrent() && controller.canEdit) {
        await remount();
      }
    }
  }

  Future<void> cancel() async {
    _cancelled = true;
    await _native?.cancel();
  }

  void retire() {
    _retired = true;
    _native?.retire();
  }
}
