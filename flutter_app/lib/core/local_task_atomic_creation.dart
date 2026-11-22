import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import 'local_store.dart';
import 'task_creation_attempt.dart';

enum LocalTaskCreationState { absent, matching, changed, missing }

class LocalTaskCreationReview {
  const LocalTaskCreationReview({
    required this.state,
    required this.fingerprint,
    this.id,
    this.row,
  });
  final LocalTaskCreationState state;
  final String fingerprint;
  final int? id;
  final Map<String, Object?>? row;
}

/// Ordinary tasks have their own hash domain; AI root-only input is not reused.
class LocalTaskAtomicCreation {
  LocalTaskAtomicCreation(
    this.store, {
    required this.scope,
    required this.isCurrent,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;
  final LocalStore store;
  final String scope;
  final bool Function() isCurrent;
  final DateTime Function() clock;
  void guard() {
    if (!isCurrent() || store.maintenance.retired) {
      throw StateError('Ordinary task creation owner retired');
    }
  }

  void _identity(TaskCreationAttempt input) {
    guard();
    if (input.scope != scope)
      throw const FormatException('Local task generation scope differs');
  }

  String inputHash(TaskCreationAttempt input) => sha256
      .convert(utf8.encode(jsonEncode(['ordinary-task-v1', input.body])))
      .toString();
  Future<void> _schema(DatabaseExecutor db) async {
    final rows = await db.rawQuery('PRAGMA user_version');
    guard();
    if (rows.length != 1 || rows.single.values.single != 16) {
      throw const FormatException(
        'Ordinary task receipts require active schema16',
      );
    }
  }

  Future<Map<String, Object?>?> _receipt(
    DatabaseExecutor db,
    TaskCreationAttempt input,
  ) async {
    await _schema(db);
    final rows = await db.rawQuery(
      "SELECT creation_key,"
      "CASE WHEN typeof(resource_type)='text' AND length(resource_type)<=8 THEN resource_type END AS resource_type,"
      "CASE WHEN typeof(input_hash)='text' AND length(input_hash)=64 THEN input_hash END AS input_hash,"
      "CASE WHEN typeof(resource_id)='integer' THEN resource_id END AS resource_id,"
      "CASE WHEN typeof(created_at)='integer' THEN created_at END AS created_at "
      "FROM assistant_creation_receipts WHERE creation_key=?",
      [input.key],
    );
    guard();
    if (rows.isEmpty) return null;
    final r = rows.single;
    if (r['creation_key'] != input.key ||
        r['resource_type'] != 'task' ||
        r['input_hash'] != inputHash(input) ||
        r['resource_id'] is! int ||
        (r['resource_id'] as int) <= 0 ||
        r['created_at'] is! int ||
        (r['created_at'] as int) <= 0) {
      throw const FormatException('Ordinary task receipt identity differs');
    }
    return r;
  }

  Future<int> create(
    TaskCreationAttempt input, {
    required Future<void> Function() onSubmit,
    Future<void> Function(int)? afterCommit,
  }) => store.maintenance.use(() async {
    _identity(input);
    if (input.phase != TaskCreationPhase.pending) {
      throw StateError('Only fresh pending task can enter creation');
    }
    final db = await store.database;
    guard();
    await _schema(db);
    // Journal is flushed/read back before the first possible mutation.
    await onSubmit();
    guard();
    final id = await db.transaction((tx) async {
      if (await _receipt(tx, input) != null) {
        throw StateError('Existing receipt requires readonly review');
      }
      var parent = input.body['parent_id'] as int;
      final visited = <int>{};
      while (parent != 0) {
        if (!visited.add(parent)) throw StateError('Cyclic task parent');
        final rows = await tx.rawQuery(
          'SELECT parent_id FROM tasks WHERE task_id=? AND deleted=0',
          [parent],
        );
        guard();
        if (rows.length != 1 ||
            rows.single['parent_id'] is! int ||
            (rows.single['parent_id'] as int) < 0) {
          throw StateError('Task parent no longer exists');
        }
        parent = rows.single['parent_id'] as int;
      }
      final now = clock().toIso8601String();
      final created = await tx.insert('tasks', {
        'content': input.body['content'],
        'due_date': input.body['due_date'],
        'done': input.body['done'] == true ? 1 : 0,
        'parent_id': input.body['parent_id'],
        'topic_id': input.body['topic_id'],
        'create_time': now,
        'modify_time': now,
        'complete_time': input.body['done'] == true ? now : null,
      });
      guard();
      await tx.insert('assistant_creation_receipts', {
        'creation_key': input.key,
        'resource_type': 'task',
        'resource_id': created,
        'input_hash': inputHash(input),
        'created_at': clock().millisecondsSinceEpoch,
      });
      guard();
      return created;
    });
    guard();
    if (afterCommit != null) {
      await afterCommit(id);
      guard();
    }
    return id;
  });

  Future<LocalTaskCreationReview> inspect(
    TaskCreationAttempt input,
  ) => store.maintenance.use(() async {
    _identity(input);
    final db = await store.database;
    guard();
    final result = await db.transaction((tx) async {
      final receipt = await _receipt(tx, input);
      if (receipt == null)
        return const LocalTaskCreationReview(
          state: LocalTaskCreationState.absent,
          fingerprint: 'absent',
        );
      final id = receipt['resource_id'] as int;
      final header = await tx.rawQuery(
        "SELECT typeof(content) AS content_type,length(CAST(content AS BLOB)) AS content_bytes,"
        "typeof(due_date) AS due_type,length(CAST(due_date AS BLOB)) AS due_bytes,"
        "typeof(create_time) AS create_type,length(CAST(create_time AS BLOB)) AS create_bytes,"
        "typeof(modify_time) AS modify_type,length(CAST(modify_time AS BLOB)) AS modify_bytes,"
        "typeof(complete_time) AS complete_type,length(CAST(complete_time AS BLOB)) AS complete_bytes "
        "FROM tasks WHERE task_id=?",
        [id],
      );
      guard();
      if (header.isEmpty)
        return LocalTaskCreationReview(
          state: LocalTaskCreationState.missing,
          id: id,
          fingerprint: sha256
              .convert(utf8.encode(jsonEncode(receipt)))
              .toString(),
        );
      final h = header.single;
      for (final field in ['content', 'due', 'create', 'modify']) {
        final max = field == 'content' ? 4000 : 128;
        if (h[field + '_type'] != 'text' ||
            h[field + '_bytes'] is! int ||
            (h[field + '_bytes'] as int) > max) {
          throw const FormatException(
            'Unbounded or nontext actual task metadata',
          );
        }
      }
      if (h['complete_type'] != 'null' &&
          (h['complete_type'] != 'text' ||
              h['complete_bytes'] is! int ||
              (h['complete_bytes'] as int) > 128)) {
        throw const FormatException('Invalid task completion metadata');
      }
      final rows = await tx.rawQuery(
        'SELECT task_id,content,due_date,done,parent_id,topic_id,create_time,modify_time,complete_time,deleted FROM tasks WHERE task_id=?',
        [id],
      );
      guard();
      if (rows.length != 1)
        throw StateError('Task changed inside read transaction');
      final row = rows.single;
      if (row['done'] != 0 && row['done'] != 1 ||
          row['parent_id'] is! int ||
          row['topic_id'] is! int ||
          row['deleted'] is! int) {
        throw const FormatException('Invalid actual task tuple');
      }
      for (final field in ['create_time', 'modify_time']) {
        final value = row[field];
        if (value is! String ||
            value.isEmpty ||
            DateTime.tryParse(value) == null) {
          throw const FormatException('Invalid actual local task version');
        }
      }
      final completion = row['complete_time'];
      if (completion != null &&
          (completion is! String || DateTime.tryParse(completion) == null)) {
        throw const FormatException('Invalid actual local task completion');
      }
      final actual = TaskCreationAttempt(
        scope: input.scope,
        key: input.key,
        body: {
          'content': row['content'],
          'due_date': row['due_date'],
          'done': row['done'] == 1,
          'parent_id': row['parent_id'],
          'topic_id': row['topic_id'],
        },
      );
      final matching =
          row['deleted'] == 0 && actual.inputDigest == input.inputDigest;
      return LocalTaskCreationReview(
        id: id,
        row: Map.unmodifiable(row),
        state: matching
            ? LocalTaskCreationState.matching
            : LocalTaskCreationState.changed,
        fingerprint: sha256
            .convert(
              utf8.encode(
                jsonEncode([
                  receipt,
                  {
                    for (final key in (row.keys.toList()..sort()))
                      key: row[key],
                  },
                ]),
              ),
            )
            .toString(),
      );
    }, exclusive: false);
    guard();
    return result;
  });
}
