import 'dart:async';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import '../../core/attachments.dart';
import '../../core/draft_vault.dart';
import '../../core/task_draft_vault.dart';
import '../../core/local_assistant_creation_receipts.dart';
import '../../core/local_assistant_draft_ledger.dart';
import '../../core/local_assistant_draft_payload.dart';
import '../../core/local_assistant_editor_drafts.dart';
import '../../core/local_assistant_editor_repositories.dart';
import '../../core/local_assistant_write_journal.dart';
import '../../core/notes_repository.dart';
import '../../core/tasks_repository.dart';
import '../notes/notes_page.dart';
import '../tasks/task_editor_page.dart';

/// Coordinates an explicit user editor owner. Opening never creates content.
/// Root supplies navigation and review; encrypted vaults include its durability
/// barrier. The vault instances here are also passed to the actual editors.
class LocalAssistantEditorCoordinator {
  LocalAssistantEditorCoordinator({
    required this.receipts,
    required this.ledger,
    required this.journal,
    required this.editorDrafts,
    required this.notes,
    required this.tasks,
    this.isCurrent,
  });

  final LocalAssistantCreationReceipts receipts;
  final LocalAssistantDraftLedger ledger;
  final LocalAssistantWriteJournal journal;
  final LocalAssistantEditorDrafts editorDrafts;
  final NotesRepository notes;
  final TasksRepository tasks;
  final bool Function()? isCurrent;
  static final Set<String> _open = {};
  static bool isDraftOpen({
    required String ledgerKey,
    required String draftId,
  }) => _open.contains(jsonEncode([ledgerKey, draftId]));
  static final Map<String, Future<void> Function()> _owners = {};

  /// Retires only the save owner, without waiting for human navigation.
  static Future<void> retireAndDrainDraft({
    required String ledgerKey,
    required String draftId,
  }) async {
    await _owners[jsonEncode([ledgerKey, draftId])]?.call();
  }

  void _guard() {
    if (isCurrent?.call() == false) {
      throw const LocalAssistantDraftOwnerRetired();
    }
  }

  /// Opens an acknowledged real resource, never a new creation. A changed
  /// resource needs an explicit read-only review fingerprint from the caller.
  Future<bool> resumeSaved({
    required String draftId,
    required Future<void> Function(Widget page) presentPage,
    required Future<void> Function(
      LocalAssistantDraftRecord draft,
      LocalAssistantWriteMarker? marker,
    )
    onReview,
    int? expectedResourceId,
    String? reviewedFingerprint,
    void Function(LocalAssistantDraftKind kind, int id)? onSaved,
    bool english = false,
    AttachmentRepository? attachments,
  }) => open(
    draftId: draftId,
    presentPage: presentPage,
    onReview: onReview,
    onSaved: onSaved,
    english: english,
    attachments: attachments,
    resumeCreated: true,
    expectedResourceId: expectedResourceId,
    reviewedFingerprint: reviewedFingerprint,
  );

  /// Returns false if this identity already has an editor/review open.
  /// Save notifications are emitted on return, including a known SQL commit
  /// whose later encrypted acknowledgement failed. No result implies replay.
  Future<bool> open({
    required String draftId,
    required Future<void> Function(Widget page) presentPage,
    required Future<void> Function(
      LocalAssistantDraftRecord draft,
      LocalAssistantWriteMarker? marker,
    )
    onReview,
    void Function(LocalAssistantDraftKind kind, int id)? onSaved,
    bool english = false,
    AttachmentRepository? attachments,
    bool resumeCreated = false,
    int? expectedResourceId,
    String? reviewedFingerprint,
  }) async {
    _guard();
    final lock = jsonEncode([ledger.key, draftId]);
    if (!_open.add(lock)) return false;
    var ownerActive = true, lockOwned = true;
    bool current() => ownerActive && isCurrent?.call() != false;
    Future<void> Function()? retire;
    int? Function()? savedId;
    LocalAssistantDraftKind? kind;
    void guardOwner() {
      _guard();
      if (!ownerActive) throw const LocalAssistantDraftOwnerRetired();
    }

    _owners[lock] = () async {
      ownerActive = false;
      await retire?.call();
    };
    Future<void> handOffReview(
      LocalAssistantDraftRecord draft,
      LocalAssistantWriteMarker? marker,
    ) async {
      ownerActive = false;
      await retire?.call();
      _owners.remove(lock);
      _open.remove(lock);
      lockOwned = false;
      await onReview(draft, marker);
    }

    try {
      final records = await ledger.load();
      guardOwner();
      final candidates = records.where((record) => record.id == draftId);
      if (candidates.length != 1) {
        throw StateError('Assistant draft is unavailable');
      }
      final draft = candidates.single;
      kind = draft.payload.kind;
      final identity = LocalAssistantWriteMarker(
        namespace: journal.namespace,
        bindingId: journal.bindingId,
        draftId: draft.id,
        kind: kind,
      );
      final marker = await journal.readMarker(identity);
      guardOwner();

      if (resumeCreated &&
          draft.state == LocalAssistantDraftState.created &&
          marker == null) {
        final inspected = await receipts.inspect(draft.id);
        guardOwner();
        final receipt = inspected.receipt;
        if (receipt == null ||
            receipt.kind != kind ||
            receipt.resourceId != draft.resourceId ||
            receipt.inputHash != draft.inputHash ||
            (expectedResourceId != null &&
                expectedResourceId != receipt.resourceId)) {
          throw StateError('Saved assistant resource identity does not match');
        }
        final editable =
            inspected.state == LocalAssistantCreationResourceState.matching ||
            (inspected.state == LocalAssistantCreationResourceState.changed &&
                reviewedFingerprint == inspected.fingerprint);
        if (!editable) {
          await handOffReview(draft, marker);
          return true;
        }
        final namespace = LocalAssistantEditorDrafts.editorNamespace(
          base: journal.namespace,
          binding: journal.bindingId,
          draft: draft.id,
          kind: kind,
        );
        if (editorDrafts.notes.namespace != namespace ||
            editorDrafts.tasks.namespace != namespace) {
          throw StateError('Assistant editor draft scope does not match');
        }
        final id = receipt.resourceId;
        final owner = _SavedOwner(id, current);
        retire = owner.retireAndDrain;
        savedId = () => owner.savedId;
        if (kind == LocalAssistantDraftKind.note) {
          await _bridgeLegacy<Note>(
            read: (value) => editorDrafts.notes.read(value),
            write: (value) => editorDrafts.notes.write(value),
            removeLegacy: () => editorDrafts.notes.remove(null),
            withId: (value) => value.copyWith(id: id),
            signature: (value) =>
                jsonEncode([value.title, value.content, value.labels]),
            id: id,
            guard: guardOwner,
          );
          guardOwner();
          final actual = inspected.note;
          if (actual == null || actual.id != id) {
            throw StateError('Saved note is unavailable');
          }
          await presentPage(
            NoteEditorPage(
              repository: _SavedNotes(notes, owner, editorDrafts.notes),
              note: actual,
              drafts: editorDrafts.notes,
              attachments: attachments,
              english: english,
            ),
          );
        } else {
          await _bridgeLegacy<TaskItem>(
            read: (value) => editorDrafts.tasks.read(value, parentId: 0),
            write: (value) => editorDrafts.tasks.write(value),
            removeLegacy: () => editorDrafts.tasks.remove(null, parentId: 0),
            withId: (value) => value.copyWith(id: id),
            signature: (value) => jsonEncode([
              value.content,
              value.dueDate,
              value.done,
              value.parentId,
              value.topicId,
            ]),
            id: id,
            guard: guardOwner,
          );
          guardOwner();
          final actual = inspected.task;
          if (actual == null || actual.id != id) {
            throw StateError('Saved task is unavailable');
          }
          await presentPage(
            TaskEditorPage(
              repository: _SavedTasks(tasks, owner, editorDrafts.tasks),
              task: actual,
              vault: editorDrafts.tasks,
              attachments: attachments,
              english: english,
            ),
          );
        }
        return true;
      }
      if (draft.state != LocalAssistantDraftState.pending || marker != null) {
        await handOffReview(draft, marker);
        return true;
      }
      final namespace = LocalAssistantEditorDrafts.editorNamespace(
        base: journal.namespace,
        binding: journal.bindingId,
        draft: draft.id,
        kind: kind,
      );
      if (editorDrafts.notes.namespace != namespace ||
          editorDrafts.tasks.namespace != namespace) {
        throw StateError('Assistant editor draft scope does not match');
      }

      if (kind == LocalAssistantDraftKind.note) {
        final recovered = await editorDrafts.notes.read(null);
        guardOwner();
        final note =
            recovered ??
            Note(title: draft.payload.title, content: draft.payload.content);
        final repository = LocalAssistantNotesRepository(
          underlying: notes,
          receipts: receipts,
          ledger: ledger,
          journal: journal,
          draft: draft,
          editorDrafts: editorDrafts,
          isCurrent: current,
        );
        retire = repository.retireAndDrain;
        savedId = () => repository.savedId;
        await presentPage(
          NoteEditorPage(
            repository: repository,
            note: note,
            drafts: editorDrafts.notes,
            attachments: attachments,
            english: english,
          ),
        );
      } else {
        final recovered = await editorDrafts.tasks.read(null, parentId: 0);
        guardOwner();
        final task =
            recovered ??
            TaskItem(
              content: draft.payload.content,
              dueDate: draft.payload.dueDate,
            );
        final repository = LocalAssistantTasksRepository(
          underlying: tasks,
          receipts: receipts,
          ledger: ledger,
          journal: journal,
          draft: draft,
          editorDrafts: editorDrafts,
          isCurrent: current,
        );
        retire = repository.retireAndDrain;
        savedId = () => repository.savedId;
        await presentPage(
          TaskEditorPage(
            repository: repository,
            task: task,
            vault: editorDrafts.tasks,
            attachments: attachments,
            english: english,
          ),
        );
      }
      return true;
    } finally {
      ownerActive = false;
      try {
        await retire?.call();
        final id = savedId?.call();
        if (id != null && kind != null && isCurrent?.call() != false) {
          onSaved?.call(kind, id);
        }
      } finally {
        if (lockOwned) {
          _owners.remove(lock);
          _open.remove(lock);
        }
      }
    }
  }
}

/// An existing receipt binds every update to one positive resource identity.
class _SavedOwner {
  _SavedOwner(this.id, this.isCurrent);
  final int id;
  final bool Function() isCurrent;
  bool retired = false, busy = false;
  int? savedId;
  Completer<void>? _saving;
  Future<int> save(int? requestedId, Future<int> Function() update) async {
    if (retired || !isCurrent()) throw const LocalAssistantDraftOwnerRetired();
    if (requestedId != id || id <= 0) {
      throw StateError('Saved assistant resource identity changed');
    }
    if (busy) throw StateError('An editor save is already running');
    busy = true;
    _saving = Completer<void>();
    try {
      final saved = await update();
      if (saved != id) throw StateError('Saved resource identity changed');
      savedId = id;
      if (retired || !isCurrent()) {
        throw const LocalAssistantDraftOwnerRetired();
      }
      return id;
    } on NoteSaveFailure catch (error) {
      if (error.savedId == id) savedId = id;
      rethrow;
    } on TaskSaveFailure catch (error) {
      if (error.savedId == id) savedId = id;
      rethrow;
    } finally {
      busy = false;
      _saving!.complete();
    }
  }

  Future<void> retireAndDrain() async {
    retired = true;
    await _saving?.future;
  }
}

class _SavedNotes implements NotesRepository {
  _SavedNotes(this.underlying, this.owner, this.vault);
  final DraftVault vault;
  String? _savedHash;
  final NotesRepository underlying;
  final _SavedOwner owner;
  @override
  Future<int> save(Note note) => owner.save(note.id, () async {
    await vault.write(note);
    if (!owner.isCurrent() || owner.retired) {
      throw const LocalAssistantDraftOwnerRetired();
    }
    final hash = LocalAssistantCreationInput.note(
      Note(
        title: note.title,
        content: note.content,
        labels: note.labels,
        isProtected: note.isProtected,
        unlockPassword: note.unlockPassword,
      ),
    ).digest;
    final id = _savedHash == hash ? owner.id : await underlying.save(note);
    if (id != owner.id) throw StateError('Saved resource identity changed');
    _savedHash = hash;
    return id;
  });
  @override
  Future<Note> read(int id) => underlying.read(id);
  @override
  Future<List<Note>> list({String keyword = '', int page = 1}) =>
      underlying.list(keyword: keyword, page: page);
  @override
  Future<void> remove(int id) => underlying.remove(id);
}

class _SavedTasks implements TasksRepository {
  _SavedTasks(this.underlying, this.owner, this.vault);
  final TaskDraftVault vault;
  String? _savedHash;
  final TasksRepository underlying;
  final _SavedOwner owner;
  @override
  Future<int> save(TaskItem task) => owner.save(task.id, () async {
    await vault.write(task);
    if (!owner.isCurrent() || owner.retired) {
      throw const LocalAssistantDraftOwnerRetired();
    }
    final hash = LocalAssistantCreationInput.task(
      TaskItem(
        content: task.content,
        dueDate: task.dueDate,
        done: task.done,
        parentId: task.parentId,
        topicId: task.topicId,
      ),
    ).digest;
    final id = _savedHash == hash ? owner.id : await underlying.save(task);
    if (id != owner.id) throw StateError('Saved resource identity changed');
    _savedHash = hash;
    return id;
  });
  @override
  Future<TaskItem> read(int id) => underlying.read(id);
  @override
  Future<TaskPage> list(TaskQuery query) => underlying.list(query);
  @override
  Future<void> remove(int id) => underlying.remove(id);
  @override
  Future<void> setDone(int id, bool done) => underlying.setDone(id, done);
  @override
  Future<List<TaskDailyCount>> dailyCounts(int year, int month) =>
      underlying.dailyCounts(year, month);
}

/// Move a legacy new-resource draft only after a durable positive-ID copy
/// and readback agree. Different existing versions remain separate and blocking.
Future<void> _bridgeLegacy<T>({
  required Future<T?> Function(int?) read,
  required Future<void> Function(T) write,
  required Future<void> Function() removeLegacy,
  required T Function(T) withId,
  required String Function(T) signature,
  required int id,
  required void Function() guard,
}) async {
  var positive = await read(id);
  guard();
  final legacy = await read(null);
  guard();
  if (legacy == null) return;
  final expected = signature(legacy);
  if (positive != null && signature(positive) != expected) return;
  if (positive == null) {
    positive = await read(id);
    guard();
    if (positive != null && signature(positive) != expected) return;
    if (positive == null) {
      await write(withId(legacy));
      guard();
    }
  }
  final observed = await read(id);
  guard();
  if (observed == null || signature(observed) != expected) {
    throw StateError('Assistant draft copy could not be verified');
  }
  final latest = await read(null);
  guard();
  if (latest == null) return;
  if (signature(latest) != expected) {
    throw StateError('Assistant legacy draft changed during recovery');
  }
  await removeLegacy();
  guard();
  if (await read(null) != null) {
    throw StateError('Assistant legacy draft cleanup could not be verified');
  }
  guard();
}
