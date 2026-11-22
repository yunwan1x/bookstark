import 'task_creation_draft_namespace.dart';
import 'task_draft_vault.dart';
import 'protected_complex_lifetime.dart';
import 'api_client.dart';
import 'task_creation_attempt.dart';
import 'task_creation_controller.dart';
import 'task_creation_guarded_repository.dart';
import 'task_creation_http_adapter.dart';
import 'task_creation_slot.dart';
import 'task_creation_store.dart';
import 'tasks_repository.dart';

/// One captured account scope owns both HTTP lifetime and recovery writes.
/// Root must register retire() in its awaited owner/backup switch barrier.
class TaskCreationSession implements ProtectedComplexOwner {
  TaskCreationSession({
    required BookstarkClient client,
    required int memberId,
    required String namespace,
    required bool Function() isCurrent,
    required Future<String?> Function(String) read,
    required Future<void> Function(String, String) write,
    required Future<void> Function(String) remove,
    required Future<void> Function() flush,
    this.onRetired,
    this.draftVault,
  }) : adapter = TaskCreationHttpAdapter(
         client: client,
         memberId: memberId,
         namespace: namespace,
         isCurrent: isCurrent,
       ),
       _namespace = namespace,
       _read = read,
       _write = write,
       _remove = remove,
       _flush = flush,
       _outerCurrent = isCurrent {
    slot = TaskCreationSlot(
      scope: adapter.scope,
      read: read,
      write: write,
      remove: remove,
      flush: flush,
      isCurrent: () => current,
    );
  }
  final void Function(TaskCreationSession)? onRetired;
  final TaskCreationHttpAdapter adapter;
  TaskCreationGuardedRepository? _wrapped;
  final TaskDraftVault? draftVault;
  final String _namespace;
  final Future<String?> Function(String) _read;
  final Future<void> Function(String, String) _write;
  final Future<void> Function(String) _remove;
  final Future<void> Function() _flush;
  final bool Function() _outerCurrent;
  late final TaskCreationSlot slot;
  TaskCreationController? controller;
  String? _key;
  final _repositories = <TaskCreationGuardedRepository>[];
  bool _closed = false, _opening = false;
  Future<void>? _retiring;
  @override
  bool get current => !_closed && _outerCurrent();
  Future<bool> hasRetained() => slot.hasRetained();
  Future<TaskCreationController> open({
    Map<String, Object?>? freshBody,
    TaskDraftVault? editorVault,
  }) async {
    if (!current || _opening) throw StateError('Task recovery busy or retired');
    final draftNamespace = freshBody == null
        ? null
        : taskCreationDraftNamespace(
            _namespace,
            freshBody['topic_id'] as int,
            editorVault?.namespace ?? draftVault?.namespace,
          );
    if (controller != null) return controller!;
    _opening = true;
    try {
      final handle = await slot.open();
      if (!current) throw StateError('Task recovery retired');
      _key = handle.key;
      final store = TaskCreationStore(
        scope: adapter.scope,
        key: handle.key,
        read: _read,
        write: _write,
        remove: _remove,
        flush: _flush,
        isCurrent: () => current,
      );
      final c = TaskCreationController(
        store: store,
        prepare: adapter.prepare,
        inspect: adapter.inspect,
        beforeEnd: _beforeEnd,
      );
      controller = c;
      if (handle.created && freshBody != null) {
        await c.begin(
          TaskCreationAttempt(
            scope: adapter.scope,
            key: handle.key,
            body: freshBody,
            draftNamespace: draftNamespace,
          ),
        );
      } else {
        await c.reload();
      }
      if (!current) throw StateError('Task recovery retired');
      return c;
    } finally {
      _opening = false;
    }
  }

  Future<void> _beforeEnd(TaskCreationAttempt input) async {
    final id = input.actualId, c = controller;
    if (id == null) return;
    if (input.draftNamespace == null && input.body['topic_id'] != 0) {
      throw StateError(
        'Legacy topic task draft origin is unconfirmed; preserve all drafts',
      );
    }
    final namespace = taskCreationDraftNamespace(
      _namespace,
      input.body['topic_id'] as int,
      input.draftNamespace,
    );
    final vault = taskCreationBoundVault(
      namespace,
      read: _read,
      write: _write,
      remove: _remove,
    );
    if (!current || c == null)
      throw StateError('Known task cleanup owner retired');
    final parent = input.body['parent_id'] as int;
    final leftover = await vault.read(null, parentId: parent);
    if (!current) throw StateError('Known task cleanup owner retired');
    if (leftover == null) return;
    final fresh = await c.inspect(input, id);
    if (!current ||
        fresh.id != id ||
        fresh.wire['parent_id'] != parent ||
        fresh.wire['topic_id'] != input.body['topic_id']) {
      throw StateError(
        'Actual known task parent differs; retain original draft',
      );
    }
    await vault.bindCreatedDraftToId(
      id,
      parentId: parent,
      flush: _flush,
      isCurrent: () => current,
    );
  }

  TaskCreationGuardedRepository wrap(TasksRepository existing) {
    if (_wrapped != null) return _wrapped!;
    final wrapped = TaskCreationGuardedRepository(
      existing: existing,
      isCurrent: () => current,
      begin: (body) => open(freshBody: body),
      hasRetainedCreation: hasRetained,
      completeAcknowledged: _completeAcknowledged,
      beginWithDraft: (body, vault) =>
          open(freshBody: body, editorVault: vault),
    );
    _repositories.add(wrapped);
    _wrapped = wrapped;
    return wrapped;
  }

  Future<void> _completeAcknowledged(
    TaskCreationRecoveryController submitted,
    TaskCreationAttempt acknowledged,
  ) async {
    final active = controller;
    if (!current ||
        active == null ||
        !identical(active, submitted) ||
        !identical(active.record, acknowledged) ||
        acknowledged.phase != TaskCreationPhase.knownID ||
        acknowledged.origin != TaskCreationOrigin.postAcknowledgement ||
        !active.hasKnownAcknowledgement ||
        active.storageUnconfirmed) {
      throw StateError('Fresh acknowledged task required');
    }
    final review = active.reviewed;
    if (review == null ||
        !await active.verifyKnown(review) ||
        !current ||
        !identical(controller, active) ||
        !identical(active.record, acknowledged)) {
      throw StateError('Acknowledged task changed; retain recovery record');
    }
    final namespace = taskCreationDraftNamespace(
      _namespace,
      acknowledged.body['topic_id'] as int,
      acknowledged.draftNamespace,
    );
    final vault = taskCreationBoundVault(
      namespace,
      read: _read,
      write: _write,
      remove: _remove,
    );
    await vault.clearAcknowledgedNewDraft(
      acknowledged.body,
      flush: _flush,
      isCurrent: () => current,
    );
    if (!current || !identical(controller, active)) {
      throw StateError('Acknowledged task owner retired');
    }
    await active.end(acknowledged);
    if (!current ||
        !active.endedDurably ||
        active.storageUnconfirmed ||
        active.record != null ||
        active.error != null) {
      throw StateError('Acknowledged task cleanup remains unconfirmed');
    }
    await clearEndedSlot();
  }

  void _ended() {
    controller?.dispose();
    controller = null;
    _key = null;
    for (final repository in _repositories) {
      repository.resetAfterExplicitEnd();
    }
  }

  /// Caller must first explicitly end the exact record through the controller.
  Future<void> clearEndedSlot() async {
    final c = controller, key = _key;
    if (!current || c == null || key == null || !c.endedDurably) {
      throw StateError('Explicit durable end required');
    }
    await c.drain();
    if (!current) throw StateError('Task recovery retired');
    await slot.clear(key);
    if (!current) throw StateError('Task recovery retired');
    _ended();
  }

  /// Explicit user action for an allocated slot whose record is genuinely absent.
  /// Never initialises pending and never sends a task request.
  Future<void> endMissing() async {
    final c = controller, key = _key;
    if (!current ||
        c == null ||
        key == null ||
        c.busy ||
        c.storageUnconfirmed ||
        c.error != null ||
        c.record != null)
      throw StateError('Fresh missing record required');
    await _flush();
    if (!current) throw StateError('Task recovery retired');
    if (await c.store.load() != null) throw StateError('Task record appeared');
    if (!current) throw StateError('Task recovery retired');
    await slot.clear(key);
    if (!current) throw StateError('Task recovery retired');
    _ended();
  }

  @override
  Future<void> retire() => _retiring ??= _retire();
  Future<void> _retire() async {
    _closed = true;
    adapter.retire();
    await slot.drain();
    final c = controller;
    if (c != null) {
      c.dispose();
      await c.drain();
    }
    onRetired?.call(this);
  }
}
