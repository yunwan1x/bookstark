import 'task_draft_save_context.dart';
import 'task_draft_vault.dart';
import 'tasks_repository.dart';
import 'task_creation_attempt.dart';
import 'task_creation_controller.dart';

/// A normal exception cannot mean "retry POST". The editor must switch to
/// readonly recovery when this typed result is raised.
class TaskCreationNeedsReview implements Exception {
  const TaskCreationNeedsReview();
}

typedef BeginTaskCreation =
    Future<TaskCreationRecoveryController> Function(
      Map<String, Object?> frozenBody,
    );

class TaskCreationGuardedRepository
    implements TasksRepository, TaskDraftSaveRepository {
  TaskCreationGuardedRepository({
    required this.existing,
    required this.begin,
    required this.isCurrent,
    this.beginWithDraft,
    this.hasRetainedCreation,
    this.completeAcknowledged,
    this.acknowledgementOrigin = TaskCreationOrigin.postAcknowledgement,
  });
  final TaskCreationOrigin acknowledgementOrigin;
  final TasksRepository existing;
  final Future<bool> Function()? hasRetainedCreation;
  @override
  Future<bool> hasRetainedTaskCreation() async {
    guard();
    final retained = hasRetainedCreation == null
        ? controller?.record != null
        : await hasRetainedCreation!();
    guard();
    return retained;
  }

  // Only the live submit path may request normal acknowledged completion.
  // Cold/unknown recovery keeps its explicit review/end flow.
  final Future<void> Function(
    TaskCreationRecoveryController controller,
    TaskCreationAttempt acknowledged,
  )?
  completeAcknowledged;
  final BeginTaskCreation begin;
  final Future<TaskCreationRecoveryController> Function(
    Map<String, Object?> body,
    TaskDraftVault? vault,
  )?
  beginWithDraft;
  @override
  TaskCreationRecoveryController? get taskCreationRecovery => controller;
  final bool Function() isCurrent;
  bool _starting = false, _creationConsumed = false;
  TaskCreationRecoveryController? controller;
  void resetAfterExplicitEnd() {
    if (_starting) throw StateError('Task creation still running');
    _creationConsumed = false;
    controller = null;
  }

  void guard() {
    if (!isCurrent()) throw StateError('Task initiating scope retired');
  }

  @override
  Future<int> save(TaskItem task) => saveWithDraft(task, null);
  @override
  Future<int> saveWithDraft(TaskItem task, TaskDraftVault? vault) async {
    guard();
    if (task.id != null) {
      if (controller?.record?.actualId == task.id)
        throw const TaskCreationNeedsReview();
      return existing.save(task);
    }
    if (_starting || _creationConsumed) throw const TaskCreationNeedsReview();
    _starting = true;
    try {
      final body = task.writeBody();
      body.putIfAbsent('topic_id', () => 0);
      final c = await (beginWithDraft?.call(body, vault) ?? begin(body));
      guard();
      controller = c;
      // begin() can return a retained cold record: never submit that record.
      if (c.record == null || c.record!.phase != TaskCreationPhase.pending) {
        throw const TaskCreationNeedsReview();
      }
      _creationConsumed = true;
      await c.submit();
      guard();
      final record = c.record;
      if (c.storageUnconfirmed ||
          record == null ||
          record.phase != TaskCreationPhase.knownID ||
          record.origin != acknowledgementOrigin ||
          record.actualId == null) {
        throw const TaskCreationNeedsReview();
      }
      final id = record.actualId!;
      final complete = completeAcknowledged;
      if (complete != null) {
        // submit has drained. Keep the consumed guard while the session verifies
        // and durably clears metadata; resetAfterExplicitEnd may then release it.
        _starting = false;
        await complete(c, record);
        guard();
        if (c.record != null || c.storageUnconfirmed || c.error != null) {
          throw const TaskCreationNeedsReview();
        }
      }
      return id;
    } catch (_) {
      _creationConsumed = true;
      throw const TaskCreationNeedsReview();
    } finally {
      _starting = false;
    }
  }

  @override
  Future<TaskPage> list(TaskQuery q) {
    guard();
    return existing.list(q);
  }

  @override
  Future<TaskItem> read(int id) {
    guard();
    return existing.read(id);
  }

  @override
  Future<void> setDone(int id, bool done) {
    guard();
    return existing.setDone(id, done);
  }

  @override
  Future<void> remove(int id) {
    guard();
    return existing.remove(id);
  }

  @override
  Future<List<TaskDailyCount>> dailyCounts(int y, int m) {
    guard();
    return existing.dailyCounts(y, m);
  }
}
