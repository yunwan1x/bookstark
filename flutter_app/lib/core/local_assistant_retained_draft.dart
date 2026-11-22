import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'bounded_note_text_reader.dart';
import 'draft_vault.dart';
import 'local_assistant_creation_receipts.dart';
import 'local_assistant_draft_ledger.dart';
import 'local_assistant_draft_payload.dart';
import 'local_assistant_editor_drafts.dart';
import 'local_assistant_write_journal.dart';
import 'local_store.dart';
import 'notes_repository.dart';
import 'task_draft_vault.dart';
import 'tasks_repository.dart';

class LocalAssistantRetainedDraftSnapshot {
  const LocalAssistantRetainedDraftSnapshot({
    required this.fingerprint,
    required this.note,
    required this.task,
    required this.raw,
  });
  final String fingerprint;
  final Note? note;
  final TaskItem? task;
  // Preserve the entire original encrypted-record plaintext for exact rollback.
  final String raw;
  String get content => note?.content ?? task!.content;
}

/// Explicit archive of a cancelled attempt. Never edits resources, recreates a
/// proposal, deletes a ledger, or treats an unknown read as an empty draft.
class LocalAssistantRetainedDraft {
  LocalAssistantRetainedDraft({
    required this.store,
    required this.identity,
    required this.ledger,
    required this.journal,
    required this.notes,
    required this.tasks,
    required this.drainOriginatingSave,
    this.resourceId,
    this.isCurrent,
  });
  final LocalStore store;
  final LocalAssistantWriteMarker identity;
  final LocalAssistantDraftLedger ledger;
  final LocalAssistantWriteJournal journal;
  final DraftVault notes;
  final TaskDraftVault tasks;
  final int? resourceId;
  final Future<void> Function() drainOriginatingSave;
  final bool Function()? isCurrent;
  bool _busy = false;
  void _guard() {
    if (store.maintenance.retired || isCurrent?.call() == false) {
      throw const LocalAssistantDraftOwnerRetired();
    }
    final namespace = LocalAssistantEditorDrafts.editorNamespace(
      base: store.dataPaths!.draftNamespace,
      binding: identity.bindingId,
      draft: identity.draftId,
      kind: identity.kind,
    );
    if (identity.namespace != store.dataPaths!.draftNamespace ||
        journal.namespace != identity.namespace ||
        journal.bindingId != identity.bindingId ||
        !identical(journal.maintenance, store.maintenance) ||
        identity.inputHash != null ||
        (resourceId != null && resourceId! <= 0) ||
        notes.namespace != namespace ||
        tasks.namespace != namespace ||
        !identical(notes.maintenance, store.maintenance) ||
        !identical(tasks.maintenance, store.maintenance) ||
        ledger.key !=
            jsonEncode([
              'bookstark.ai-drafts-v1',
              LocalAssistantEditorDrafts.ledgerNamespace(
                store.path,
                identity.bindingId,
              ),
            ])) {
      throw StateError('Retained draft scope changed');
    }
  }

  Object? get _recordId => identity.kind == LocalAssistantDraftKind.note
      ? resourceId
      : resourceId ?? 'new:0';
  Future<String?> _read() => identity.kind == LocalAssistantDraftKind.note
      ? notes.readRecord(_recordId)
      : tasks.readRecord(_recordId);
  Future<void> _remove() => identity.kind == LocalAssistantDraftKind.note
      ? notes.removeRecord(_recordId)
      : tasks.removeRecord(_recordId);
  Future<void> _restore(String raw) =>
      identity.kind == LocalAssistantDraftKind.note
      ? notes.writeRecord(_recordId, raw)
      : tasks.writeRecord(_recordId, raw);
  bool _text(String value) =>
      BoundedNoteTextReader.decodeUtf8PreservingBom(
        Uint8List.fromList(utf8.encode(value)),
      ) ==
      value;

  Future<LocalAssistantRetainedDraftSnapshot?> inspect() async {
    _guard();
    await drainOriginatingSave();
    _guard();
    return store.maintenance.exclusive(_inspectDrained);
  }

  Future<LocalAssistantRetainedDraftSnapshot?> _inspectDrained() async {
    _guard();
    final records = await ledger.load();
    _guard();
    final record = records
        .where((record) => record.id == identity.draftId)
        .single;
    if (record.state != LocalAssistantDraftState.cancelled ||
        record.payload.kind != identity.kind) {
      throw StateError('Only a cancelled draft may enter this archive');
    }
    if (await journal.readMarker(identity) != null) {
      throw StateError('Pending write still requires review');
    }
    _guard();
    if (await LocalAssistantCreationReceipts(
          store,
          isCurrent: isCurrent,
        ).lookup(identity.draftId) !=
        null) {
      throw StateError('Saved resource requires receipt review');
    }
    _guard();
    final raw = await _read();
    _guard();
    if (raw == null) return null;
    if (utf8.encode(raw).length > 24 * 1024 * 1024) {
      throw const FormatException('Retained draft exceeds review budget');
    }
    final data = jsonDecode(raw);
    if (data is! Map ||
        data['version'] != 1 ||
        data['content'] is! String ||
        !_text(data['content'] as String)) {
      throw const FormatException('Retained draft cannot be read completely');
    }
    Note? note;
    TaskItem? task;
    if (identity.kind == LocalAssistantDraftKind.note) {
      if (data['title'] is! String ||
          !_text(data['title'] as String) ||
          data['labels'] is! List ||
          (data['labels'] as List).length > 4096 ||
          (data['labels'] as List).any(
            (label) => label is! String || !_text(label),
          )) {
        throw const FormatException('Retained note metadata cannot be read');
      }
      note = Note(
        id: resourceId,
        title: data['title'] as String,
        content: data['content'] as String,
        labels: (data['labels'] as List).cast<String>(),
      );
    } else {
      if (data['id'] != resourceId ||
          data['parent_id'] != 0 ||
          data['due_date'] is! String ||
          !_text(data['due_date'] as String) ||
          data['done'] is! bool ||
          (data['topic_id'] != null &&
              (data['topic_id'] is! int || (data['topic_id'] as int) < 0))) {
        throw const FormatException('Retained task metadata cannot be read');
      }
      task = TaskItem(
        id: resourceId,
        parentId: 0,
        content: data['content'] as String,
        dueDate: data['due_date'] as String,
        done: data['done'] as bool,
        topicId: data['topic_id'] as int?,
      );
    }
    final fingerprint = sha256
        .convert(
          utf8.encode(
            jsonEncode([identity.key, _recordId, record.toJson(), raw]),
          ),
        )
        .toString();
    return LocalAssistantRetainedDraftSnapshot(
      fingerprint: fingerprint,
      note: note,
      task: task,
      raw: raw,
    );
  }

  Future<void> clear(LocalAssistantRetainedDraftSnapshot reviewed) async {
    if (_busy) throw StateError('Draft cleanup already in progress');
    _busy = true;
    try {
      _guard();
      await drainOriginatingSave();
      _guard();
      await store.maintenance.exclusive(() async {
        final fresh = await _inspectDrained();
        if (fresh == null || fresh.fingerprint != reviewed.fingerprint) {
          throw StateError('Retained draft changed. Review it again');
        }
        _guard();
        try {
          await _remove();
          _guard();
          if (await _read() != null) {
            throw StateError('Draft deletion was not confirmed');
          }
          _guard();
        } catch (_) {
          // Delete may have applied before a failed native durability barrier.
          // Restore the exact record, including unknown fields and timestamps.
          try {
            _guard();
            await _restore(fresh.raw);
            _guard();
            if (await _read() != fresh.raw) {
              throw StateError('Draft restoration was not confirmed');
            }
          } catch (_) {
            // Storage may be unavailable; never claim successful cleanup.
          }
          throw StateError('Draft cleanup was not confirmed');
        }
      });
    } finally {
      _busy = false;
    }
  }
}
