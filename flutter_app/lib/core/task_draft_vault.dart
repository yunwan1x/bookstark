import 'local_legacy_json.dart';
import 'dart:convert';
import 'secure_record_store.dart';
import 'tasks_repository.dart';

class TaskDraftVault extends SecureRecordStore {
  TaskDraftVault({
    required super.namespace,
    super.maintenance,
    required super.readValue,
    required super.writeValue,
    required super.deleteValue,
  }) : super(prefix: 'bookstark.task-draft.v1');
  Object _record(int? id, int parentId) => id ?? 'new:$parentId';
  Future<TaskItem?> read(int? id, {required int parentId}) async {
    final value = await readRecord(_record(id, parentId));
    if (value == null) return null;
    if (utf8.encode(value).length > 128 * 1024) {
      throw const FormatException('Task draft exceeds storage limit');
    }
    final row = jsonDecode(value) as Map;
    final topic = row['topic_id'];
    if (row['version'] != 1 ||
        row['id'] != id ||
        row['parent_id'] != parentId ||
        row['content'] is! String ||
        row['due_date'] is! String ||
        row['done'] is! bool ||
        (topic != null && (topic is! int || topic < 0))) {
      throw const FormatException(
        'Invalid task draft or changed parent relationship',
      );
    }
    return TaskItem(
      id: id,
      content: row['content'] as String,
      dueDate: row['due_date'] as String,
      done: row['done'] as bool,
      parentId: parentId,
      topicId: topic as int?,
    );
  }

  Future<void> write(TaskItem task) {
    final value = jsonEncode({
      'version': 1,
      'id': task.id,
      'parent_id': task.parentId,
      'topic_id': task.topicId,
      'content': task.content,
      'due_date': task.dueDate,
      'done': task.done,
    });
    if (utf8.encode(value).length > 128 * 1024) {
      return Future<void>.error(
        const FormatException('Task draft exceeds storage limit'),
      );
    }
    return writeRecord(_record(task.id, task.parentId), value);
  }

  Future<void> remove(int? id, {required int parentId}) =>
      removeRecord(_record(id, parentId));

  /// Remove only the unchanged submitted new draft after a verified live ACK.
  /// A revised draft stays available for the existing known-ID binding path.
  Future<void> clearAcknowledgedNewDraft(
    Map<String, Object?> body, {
    required Future<void> Function() flush,
    required bool Function() isCurrent,
  }) => withRecordLock(() async {
    void guard() {
      if (!isCurrent()) throw StateError('Task draft cleanup owner retired');
    }

    guard();
    final key = metadataKey(_record(null, body['parent_id'] as int));
    final raw = await readValue(key);
    guard();
    if (raw == null) return;
    if (utf8.encode(raw).length > 128 * 1024) {
      throw const FormatException('Task draft exceeds storage limit');
    }
    final value = jsonDecode(raw);
    if (value is! Map ||
        value.length != 7 ||
        value['version'] != 1 ||
        value['id'] != null ||
        value['parent_id'] != body['parent_id'] ||
        (value['topic_id'] ?? 0) != body['topic_id'] ||
        value['content'] != body['content'] ||
        value['due_date'] != body['due_date'] ||
        value['done'] != body['done'])
      return;
    await deleteValue(key);
    guard();
    await flush();
    guard();
    if (await readValue(key) != null) {
      throw StateError('Acknowledged task draft cleanup unconfirmed');
    }
    guard();
  });

  /// Storage-only binding of a known creation's leftover new draft.
  Future<void> bindCreatedDraftToId(
    int id, {
    required int parentId,
    required Future<void> Function() flush,
    required bool Function() isCurrent,
  }) => withRecordLock(() async {
    void guard() {
      if (!isCurrent()) throw StateError('Task draft binding owner retired');
    }

    guard();
    await flush();
    guard();
    final sourceKey = metadataKey(_record(null, parentId));
    final targetKey = metadataKey(id);
    if (id <= 0) throw const FormatException('Known task ID required');
    final raw = await readValue(sourceKey);
    guard();
    if (raw == null) return;
    if (utf8.encode(raw).length > 128 * 1024) {
      throw const FormatException('Task draft exceeds storage limit');
    }
    final decoded = decodeLegacyJson(
      utf8.encode(raw),
      limits: const LegacyJsonLimits(
        maxBytes: 128 * 1024,
        maxStringBytes: 128 * 1024,
        maxEncodedStringCharacters: 128 * 1024,
        maxDepth: 3,
        maxNodes: 32,
        maxObjectMembers: 7,
        maxArrayLength: 8,
      ),
    );
    if (decoded is! Map ||
        decoded.length != 7 ||
        !decoded.keys.toSet().containsAll({
          'version',
          'id',
          'parent_id',
          'topic_id',
          'content',
          'due_date',
          'done',
        }) ||
        decoded['version'] != 1 ||
        decoded['id'] != null ||
        decoded['parent_id'] != parentId ||
        decoded['content'] is! String ||
        decoded['due_date'] is! String ||
        decoded['done'] is! bool ||
        (decoded['topic_id'] != null &&
            (decoded['topic_id'] is! int ||
                (decoded['topic_id'] as int) < 0))) {
      throw const FormatException('Unconfirmed original task draft');
    }
    final desired = jsonEncode({
      'version': 1,
      'id': id,
      'parent_id': parentId,
      'topic_id': decoded['topic_id'],
      'content': decoded['content'],
      'due_date': decoded['due_date'],
      'done': decoded['done'],
    });
    if (utf8.encode(desired).length > 128 * 1024) {
      throw const FormatException('Bound task draft exceeds storage limit');
    }
    final target = await readValue(targetKey);
    guard();
    if (target != null && target != desired) {
      throw StateError('Existing same-ID draft differs; retain both drafts');
    }
    if (target == null) {
      await writeValue(targetKey, desired);
      guard();
    }
    await flush();
    guard();
    if (await readValue(targetKey) != desired) {
      throw StateError('Bound task draft durability unconfirmed');
    }
    guard();
    if (await readValue(sourceKey) != raw) {
      throw StateError('Original task draft changed');
    }
    guard();
    await deleteValue(sourceKey);
    guard();
    await flush();
    guard();
    final retainedSource = await readValue(sourceKey);
    guard();
    final retainedTarget = await readValue(targetKey);
    guard();
    if (retainedSource != null || retainedTarget != desired) {
      throw StateError('Task draft binding cleanup unconfirmed');
    }
  });
}
