import 'dart:async';
import 'local_assistant_creation_receipts.dart';
import 'local_assistant_draft_creator.dart';
import 'local_assistant_draft_ledger.dart';
import 'local_assistant_editor_drafts.dart';
import 'local_assistant_write_journal.dart';
import 'notes_repository.dart';
import 'tasks_repository.dart';

/// A single explicit editor owner. Unknown creation outcomes are never replayed.
class _CreationOwner {
  _CreationOwner(this.creator, this.isCurrent);
  final bool Function()? isCurrent;
  final LocalAssistantDraftCreator creator;
  int? id;
  String? committedHash;
  bool attempted = false, acknowledgementPending = false, busy = false;
  bool retired = false;
  Completer<void>? _saving;
  void guard() {
    if (retired || isCurrent?.call() == false) {
      throw const LocalAssistantDraftOwnerRetired();
    }
    if (busy) throw StateError('An editor save is already running');
  }

  Future<int> save(
    LocalAssistantCreationInput input,
    int? requestedId,
    Future<int> Function(int) update,
  ) async {
    guard();
    if (requestedId != null && requestedId != id) {
      throw StateError('Editor resource identity changed');
    }
    busy = true;
    _saving = Completer<void>();
    try {
      if (id == null) {
        if (attempted) throw StateError('Creation outcome requires review');
        attempted = true;
        try {
          final receipt = await creator.create(input);
          id = receipt.resourceId;
          committedHash = input.digest;
          _guardAfterAwait();
          return id!;
        } on LocalAssistantCreationCommitted catch (error) {
          id = error.receipt.resourceId;
          committedHash = error.receipt.inputHash;
          acknowledgementPending = true;
          rethrow;
        }
      }
      if (acknowledgementPending) {
        await creator.retryKnownAcknowledgement();
        acknowledgementPending = false;
        _guardAfterAwait();
      }
      if (input.digest == committedHash) return id!;
      _guardAfterAwait();
      final saved = await update(id!);
      if (saved != id) {
        throw StateError('Editor update changed resource identity');
      }
      committedHash = input.digest;
      _guardAfterAwait();
      return saved;
    } finally {
      busy = false;
      _saving!.complete();
    }
  }

  void _guardAfterAwait() {
    if (retired || isCurrent?.call() == false) {
      throw const LocalAssistantDraftOwnerRetired();
    }
  }

  Future<void> retireAndDrain() async {
    retired = true;
    await creator.retireAndDrain();
    await _saving?.future;
  }
}

/// Use the SAME editorDrafts.notes instance in NoteEditorPage.
class LocalAssistantNotesRepository implements NotesRepository {
  LocalAssistantNotesRepository({
    required this.underlying,
    required LocalAssistantCreationReceipts receipts,
    required LocalAssistantDraftLedger ledger,
    required LocalAssistantWriteJournal journal,
    required LocalAssistantDraftRecord draft,
    required LocalAssistantEditorDrafts editorDrafts,
    bool Function()? isCurrent,
  }) {
    _owner = _CreationOwner(
      LocalAssistantDraftCreator(
        receipts: receipts,
        ledger: ledger,
        journal: journal,
        draft: draft,
        isCurrent: isCurrent,
        persistAndReadEditorSnapshot: (input) =>
            editorDrafts.persistNote(_snapshot!, input),
      ),
      isCurrent,
    );
    _isCurrent = isCurrent;
  }
  final NotesRepository underlying;
  late final _CreationOwner _owner;
  late final bool Function()? _isCurrent;
  Note? _snapshot;
  int? get savedId => _owner.id;
  Future<void> retireAndDrain() => _owner.retireAndDrain();
  @override
  Future<int> save(Note note) async {
    _owner.guard();
    if (_isCurrent?.call() == false) {
      throw const LocalAssistantDraftOwnerRetired();
    }
    final snapshot = Note(
      title: note.title,
      content: note.content,
      labels: List.unmodifiable(note.labels),
      isProtected: note.isProtected,
      unlockPassword: note.unlockPassword,
    );
    final input = LocalAssistantCreationInput.note(snapshot);
    _snapshot = snapshot;
    try {
      return await _owner.save(
        input,
        note.id,
        (id) => underlying.save(snapshot.copyWith(id: id)),
      );
    } on LocalAssistantDraftOwnerRetired {
      if (_owner.id case final id?) {
        throw NoteSaveFailure(id, '内容已保存，请重新核对 / Saved; review required');
      }
      rethrow;
    } on LocalAssistantCreationCommitted catch (error) {
      throw NoteSaveFailure(
        error.receipt.resourceId,
        '内容已保存，保存确认尚未完成 / Saved; confirmation is incomplete',
      );
    }
  }

  @override
  Future<List<Note>> list({String keyword = '', int page = 1}) =>
      underlying.list(keyword: keyword, page: page);
  @override
  Future<Note> read(int id) => underlying.read(id);
  @override
  Future<void> remove(int id) => underlying.remove(id);
}

/// Use the SAME editorDrafts.tasks instance in TaskEditorPage.
class LocalAssistantTasksRepository implements TasksRepository {
  LocalAssistantTasksRepository({
    required this.underlying,
    required LocalAssistantCreationReceipts receipts,
    required LocalAssistantDraftLedger ledger,
    required LocalAssistantWriteJournal journal,
    required LocalAssistantDraftRecord draft,
    required LocalAssistantEditorDrafts editorDrafts,
    bool Function()? isCurrent,
  }) {
    _owner = _CreationOwner(
      LocalAssistantDraftCreator(
        receipts: receipts,
        ledger: ledger,
        journal: journal,
        draft: draft,
        isCurrent: isCurrent,
        persistAndReadEditorSnapshot: (input) =>
            editorDrafts.persistTask(_snapshot!, input),
      ),
      isCurrent,
    );
    _isCurrent = isCurrent;
  }
  final TasksRepository underlying;
  late final _CreationOwner _owner;
  late final bool Function()? _isCurrent;
  TaskItem? _snapshot;
  int? get savedId => _owner.id;
  Future<void> retireAndDrain() => _owner.retireAndDrain();
  @override
  Future<int> save(TaskItem task) async {
    _owner.guard();
    if (_isCurrent?.call() == false) {
      throw const LocalAssistantDraftOwnerRetired();
    }
    final snapshot = TaskItem(
      content: task.content,
      dueDate: task.dueDate,
      done: task.done,
      parentId: task.parentId,
      topicId: task.topicId,
    );
    final input = LocalAssistantCreationInput.task(snapshot);
    _snapshot = snapshot;
    try {
      return await _owner.save(
        input,
        task.id,
        (id) => underlying.save(snapshot.copyWith(id: id)),
      );
    } on LocalAssistantDraftOwnerRetired {
      if (_owner.id case final id?) {
        throw TaskSaveFailure(id, '内容已保存，请重新核对 / Saved; review required');
      }
      rethrow;
    } on LocalAssistantCreationCommitted catch (error) {
      throw TaskSaveFailure(
        error.receipt.resourceId,
        '内容已保存，保存确认尚未完成 / Saved; confirmation is incomplete',
      );
    }
  }

  @override
  Future<TaskPage> list(TaskQuery query) => underlying.list(query);
  @override
  Future<TaskItem> read(int id) => underlying.read(id);
  @override
  Future<void> setDone(int id, bool done) => underlying.setDone(id, done);
  @override
  Future<void> remove(int id) => underlying.remove(id);
  @override
  Future<List<TaskDailyCount>> dailyCounts(int year, int month) =>
      underlying.dailyCounts(year, month);
}
