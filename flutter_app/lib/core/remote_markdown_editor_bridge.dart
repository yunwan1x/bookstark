import 'dart:async';
import 'draft_vault.dart';
import 'notes_repository.dart';
import 'remote_markdown_creation_controller.dart';
import 'remote_markdown_creation_vault.dart';

/// One real NoteEditorPage lease. Review retains the controller's separate lease.
class RemoteMarkdownEditorBridge extends NotesRepository {
  RemoteMarkdownEditorBridge({
    required this.controller,
    required this.underlying,
    required this.isCurrent,
    required this.onReview,
  }) {
    drafts = _CreationEditorDrafts(this);
  }
  final RemoteMarkdownCreationController controller;
  final NotesRepository underlying;
  final bool Function() isCurrent;
  final void Function() onReview;
  late final DraftVault drafts;
  Future<void> _tail = Future<void>.value();
  int _epoch = 0;
  bool _retired = false, _accepting = true;
  bool get current => !_retired && isCurrent();
  bool get editable => current && _accepting && controller.canEdit;
  Future<T> _serial<T>(Future<T> Function() work) {
    final result = _tail.then((_) => work());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  void retireEditor() {
    _retired = true;
    _accepting = false;
    _epoch++;
  }

  Future<void> drain() => _tail;
  Future<Note?> readDraft(int? id) async {
    if (id != null || !editable) return null;
    await _tail;
    if (!editable) return null;
    final input = controller.record.input;
    if (input.title.isEmpty && input.content.isEmpty && input.labels.isEmpty) {
      return null;
    }
    return Note(
      title: input.title,
      content: input.content,
      labels: input.labels,
    );
  }

  Future<void> writeDraft(Note note) {
    final epoch = _epoch;
    if (note.id != null || !editable) return Future<void>.value();
    final input = _input(note);
    return _serial(() async {
      if (epoch != _epoch || !editable) return;
      await controller.edit(input);
    });
  }

  Future<void> removeDraft(int? id) {
    // Success ack's remove cannot delete another attempt or the normal ID vault.
    if (controller.phase == MarkdownCreationPhase.finished) {
      return Future<void>.value();
    }
    if (id != null || !editable) return Future<void>.value();
    _accepting = false;
    ++_epoch; // queued stale autosaves cannot revive a discarded attempt
    return _serial(() async {
      if (!current) return;
      try {
        await controller.discardEditing();
      } finally {
        _accepting = current && controller.canEdit;
      }
    });
  }

  MarkdownCreationInput _input(Note note) {
    if (note.id != null || note.isProtected || note.unlockPassword != null) {
      throw StateError('Only a new unprotected Markdown snapshot is allowed');
    }
    return MarkdownCreationInput(
      title: note.title,
      content: note.content,
      labels: List.of(note.labels),
    );
  }

  @override
  Future<int> save(Note note) {
    if (!editable) return Future<int>.error(StateError('Review required'));
    final input = _input(note);
    _accepting = false;
    ++_epoch;
    return _serial(() async {
      try {
        if (!current) throw StateError('Editor owner retired');
        await controller.edit(input);
        if (!current) throw StateError('Editor owner retired');
        await controller.save();
        if (!current) throw StateError('Editor owner retired');
        if (controller.phase == MarkdownCreationPhase.finished &&
            controller.record.knownId != null) {
          return controller.record.knownId!;
        }
      } catch (_) {
        if (current && !controller.canEdit) {
          retireEditor();
          onReview();
        } else if (current) {
          _accepting = true;
        }
        throw StateError(
          'Save requires review; the complete draft is retained',
        );
      }
      if (controller.canEdit) {
        _accepting = true;
      } else {
        retireEditor();
        onReview();
      }
      throw StateError('Save requires review; the complete draft is retained');
    });
  }

  @override
  Future<Note> read(int id) => underlying.read(id);
  @override
  Future<List<Note>> list({String keyword = '', int page = 1}) =>
      underlying.list(keyword: keyword, page: page);
  @override
  Future<void> remove(int id) =>
      Future<void>.error(StateError('Creation editor cannot delete resources'));
}

class _CreationEditorDrafts extends DraftVault {
  _CreationEditorDrafts(this.owner)
    : super(
        namespace: owner.controller.vault.namespace,
        readValue: (_) async => null,
        writeValue: (_, _) async {},
        deleteValue: (_) async {},
      );
  final RemoteMarkdownEditorBridge owner;
  @override
  Future<Note?> read(int? id) => owner.readDraft(id);
  @override
  Future<void> write(Note note) => owner.writeDraft(note);
  @override
  Future<void> remove(int? id) => owner.removeDraft(id);
}
