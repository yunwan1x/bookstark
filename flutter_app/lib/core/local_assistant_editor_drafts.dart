import 'dart:convert';
import 'draft_vault.dart';
import 'task_draft_vault.dart';
import 'notes_repository.dart';
import 'tasks_repository.dart';
import 'local_assistant_creation_receipts.dart';
import 'local_assistant_draft_payload.dart';

/// Stable local identities used by both the editor owner and explicit recovery.
/// Storage callbacks include the native commit barrier at the application root.
class LocalAssistantEditorDrafts {
  LocalAssistantEditorDrafts({required this.notes, required this.tasks});
  final DraftVault notes;
  final TaskDraftVault tasks;
  static String ledgerNamespace(String databasePath, String binding) {
    if (databasePath.isEmpty || !RegExp(r'^[a-f0-9]{32}$').hasMatch(binding)) {
      throw const FormatException('Invalid assistant draft scope');
    }
    return jsonEncode([databasePath, binding]);
  }

  static String editorNamespace({
    required String base,
    required String binding,
    required String draft,
    required LocalAssistantDraftKind kind,
  }) {
    if (!(base == 'local' ||
            RegExp(r'^local-generation:[a-f0-9]{32}$').hasMatch(base)) ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(binding) ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(draft)) {
      throw const FormatException('Invalid assistant editor scope');
    }
    return jsonEncode([base, 'assistant', binding, draft, kind.name]);
  }

  Future<LocalAssistantCreationInput> persistNote(
    Note snapshot,
    LocalAssistantCreationInput expected,
  ) async {
    if (LocalAssistantCreationInput.note(snapshot).digest != expected.digest) {
      throw StateError('Editor snapshot changed before persistence');
    }
    await notes.write(snapshot);
    final readback = await notes.read(null);
    if (readback == null) throw StateError('Editor note draft is unavailable');
    final observed = LocalAssistantCreationInput.note(readback);
    if (observed.digest != expected.digest) {
      throw StateError('Editor draft changed during readback');
    }
    return observed;
  }

  Future<LocalAssistantCreationInput> persistTask(
    TaskItem snapshot,
    LocalAssistantCreationInput expected,
  ) async {
    if (LocalAssistantCreationInput.task(snapshot).digest != expected.digest) {
      throw StateError('Editor snapshot changed before persistence');
    }
    // Keep original whitespace in the recoverable snapshot; task SQL uses the
    // canonical TaskItem.writeBody value after the user presses Save.
    await tasks.write(snapshot);
    final readback = await tasks.read(null, parentId: 0);
    if (readback == null) throw StateError('Editor task draft is unavailable');
    final observed = LocalAssistantCreationInput.task(readback);
    if (observed.digest != expected.digest) {
      throw StateError('Editor draft changed during readback');
    }
    return observed;
  }
}
