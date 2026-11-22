import 'task_creation_controller.dart';
import 'task_draft_vault.dart';
import 'tasks_repository.dart';

/// The exact editor vault travels with this save; wrappers must not substitute
/// an account-global draft namespace after an asynchronous parent/topic read.
abstract interface class TaskDraftSaveRepository {
  Future<bool> hasRetainedTaskCreation();
  Future<int> saveWithDraft(TaskItem task, TaskDraftVault? vault);
  TaskCreationRecoveryController? get taskCreationRecovery;
}
