import 'local_protected_content.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import 'bounded_note_text_reader.dart';
import 'local_store.dart';
import 'local_assistant_draft_payload.dart';
import 'notes_repository.dart';
import 'tasks_repository.dart';

/// Reserved for the next active schema16, never lazily during a model request.
/// Candidate-only legacy schema15 and active schema14 remain
/// unchanged until the migration/backup coordinator is ready.
const assistantCreationReceiptSchema =
    "CREATE TABLE assistant_creation_receipts ("
    "creation_key TEXT PRIMARY KEY NOT NULL CHECK(length(creation_key)=32 AND creation_key NOT GLOB '*[^0-9a-f]*'),"
    "resource_type TEXT NOT NULL CHECK(resource_type IN ('note','task')),"
    "resource_id INTEGER NOT NULL CHECK(resource_id>0),"
    "input_hash TEXT NOT NULL CHECK(length(input_hash)=64 AND input_hash NOT GLOB '*[^0-9a-f]*'),"
    "created_at INTEGER NOT NULL CHECK(created_at>0))";

bool _validText(String value, int maxBytes) {
  final bytes = Uint8List.fromList(utf8.encode(value));
  return bytes.length <= maxBytes &&
      BoundedNoteTextReader.decodeUtf8PreservingBom(bytes) == value;
}

/// Constructed from the actual editor snapshot, not the original AI proposal.
final class LocalAssistantCreationInput {
  LocalAssistantCreationInput._(this.kind, this.values);
  factory LocalAssistantCreationInput.note(Note note) {
    if (note.id != null ||
        note.isProtected ||
        note.unlockPassword != null ||
        isLocalProtectedEnvelopePrefix(note.content) ||
        note.title.trim().isEmpty ||
        !_validText(note.title, 4096) ||
        !_validText(note.content, BoundedNoteTextReader.maxBytes) ||
        note.labels.length > 128 ||
        note.labels.any((label) => label.isEmpty || !_validText(label, 512))) {
      throw const FormatException('Invalid assistant note creation input');
    }
    return LocalAssistantCreationInput._(
      LocalAssistantDraftKind.note,
      Map.unmodifiable({
        'kind': 'note',
        'title': note.title,
        'content': note.content,
        'labels': List<String>.unmodifiable(note.labels),
      }),
    );
  }
  factory LocalAssistantCreationInput.task(TaskItem task) {
    if (task.id != null || task.parentId != 0 || (task.topicId ?? 0) != 0) {
      throw const FormatException('Assistant proposal must create a root task');
    }
    final body = task.writeBody();
    if (!_validText(body['content'] as String, 4000)) {
      throw const FormatException('Invalid assistant task creation input');
    }
    return LocalAssistantCreationInput._(
      LocalAssistantDraftKind.task,
      Map.unmodifiable({
        'kind': 'task',
        'content': body['content'],
        'due_date': task.dueDate,
        'done': task.done,
        'parent_id': 0,
        'topic_id': 0,
      }),
    );
  }
  final LocalAssistantDraftKind kind;
  final Map<String, Object?> values;
  String get digest =>
      sha256.convert(utf8.encode(jsonEncode(values))).toString();
}

final class LocalAssistantCreationReceipt {
  const LocalAssistantCreationReceipt({
    required this.key,
    required this.kind,
    required this.resourceId,
    required this.inputHash,
    required this.createdAt,
  });
  final String key, inputHash;
  final LocalAssistantDraftKind kind;
  final int resourceId, createdAt;
  factory LocalAssistantCreationReceipt.fromRow(Map<String, Object?> row) {
    final key = row['creation_key'],
        hash = row['input_hash'],
        id = row['resource_id'],
        time = row['created_at'];
    final kind = LocalAssistantDraftKind.values.where(
      (kind) => kind.name == row['resource_type'],
    );
    if (key is! String ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(key) ||
        hash is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash) ||
        id is! int ||
        id <= 0 ||
        time is! int ||
        time <= 0 ||
        kind.length != 1) {
      throw const FormatException('Invalid assistant creation receipt');
    }
    return LocalAssistantCreationReceipt(
      key: key,
      kind: kind.single,
      resourceId: id,
      inputHash: hash,
      createdAt: time,
    );
  }
}

final class LocalAssistantCreationAlreadyRecorded implements Exception {
  const LocalAssistantCreationAlreadyRecorded(this.receipt);
  final LocalAssistantCreationReceipt receipt;
}

final class LocalAssistantCreationOwnerRetired implements Exception {
  const LocalAssistantCreationOwnerRetired();
}

enum LocalAssistantCreationResourceState {
  absent,
  matching,
  changed,
  missing,
  protected,
  formatChanged,
  unreadable,
}

final class LocalAssistantCreationInspection {
  const LocalAssistantCreationInspection({
    required this.key,
    required this.receipt,
    required this.state,
    required this.fingerprint,
    this.note,
    this.task,
  });
  final String key;
  final LocalAssistantCreationReceipt? receipt;
  final LocalAssistantCreationResourceState state;
  final String fingerprint;
  final Note? note;
  final TaskItem? task;
}

/// Atomically binds a new resource to its durable, body-free receipt. Existing
/// receipts always require read-only review; this method never replays them.
final class LocalAssistantCreationReceipts {
  LocalAssistantCreationReceipts(
    this.store, {
    this.isCurrent,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;
  final LocalStore store;
  final bool Function()? isCurrent;
  final DateTime Function() now;
  void _guard() {
    if (store.maintenance.retired || isCurrent?.call() == false) {
      throw const LocalAssistantCreationOwnerRetired();
    }
  }

  void _key(String key) {
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(key)) {
      throw const FormatException('Invalid assistant creation identity');
    }
  }

  Future<void> _schema(DatabaseExecutor tx) async {
    final rows = await tx.rawQuery('PRAGMA user_version');
    if (rows.length != 1 || rows.single.values.single != 16) {
      throw const FormatException(
        'Assistant creation requires active schema16',
      );
    }
  }

  Future<LocalAssistantCreationReceipt?> _lookup(
    DatabaseExecutor tx,
    String key,
  ) async {
    await _schema(tx);
    final rows = await tx.rawQuery(
      "SELECT creation_key,"
      "CASE WHEN typeof(resource_type)='text' AND length(resource_type)<=8 THEN resource_type ELSE NULL END AS resource_type,"
      "CASE WHEN typeof(input_hash)='text' AND length(input_hash)=64 THEN input_hash ELSE NULL END AS input_hash,"
      "CASE WHEN typeof(resource_id)='integer' THEN resource_id ELSE NULL END AS resource_id,"
      "CASE WHEN typeof(created_at)='integer' THEN created_at ELSE NULL END AS created_at "
      "FROM assistant_creation_receipts WHERE creation_key=?",
      [key],
    );
    if (rows.isEmpty) return null;
    return LocalAssistantCreationReceipt.fromRow(rows.single);
  }

  Future<LocalAssistantCreationReceipt?> lookup(String key) {
    _key(key);
    _guard();
    return store.maintenance.use(() async {
      _guard();
      final result = await (await store.database).transaction(
        (tx) => _lookup(tx, key),
        exclusive: false,
      );
      _guard();
      return result;
    });
  }

  LocalAssistantCreationInspection _inspection(
    String key,
    LocalAssistantCreationReceipt? receipt,
    LocalAssistantCreationResourceState state, {
    String? currentHash,
    Object? metadata,
    Note? note,
    TaskItem? task,
  }) {
    final fingerprint = sha256
        .convert(
          utf8.encode(
            jsonEncode([
              key,
              if (receipt != null)
                [
                  receipt.key,
                  receipt.kind.name,
                  receipt.resourceId,
                  receipt.inputHash,
                  receipt.createdAt,
                ],
              state.name,
              currentHash,
              metadata,
            ]),
          ),
        )
        .toString();
    return LocalAssistantCreationInspection(
      key: key,
      receipt: receipt,
      state: state,
      fingerprint: fingerprint,
      note: note,
      task: task,
    );
  }

  String _smallText(Object? bytes, Object? count, int maximum) {
    if (count == 0 && bytes == null) return '';
    if (bytes is! Uint8List ||
        count is! int ||
        count < 0 ||
        count > maximum ||
        bytes.length != count) {
      throw const FormatException('Creation review text exceeds its limit');
    }
    return BoundedNoteTextReader.decodeUtf8PreservingBom(bytes);
  }

  Future<LocalAssistantCreationInspection> inspect(String key) {
    _key(key);
    _guard();
    return store.maintenance.use(() async {
      final result = await (await store.database).transaction((tx) async {
        _guard();
        final receipt = await _lookup(tx, key);
        if (receipt == null) {
          return _inspection(
            key,
            null,
            LocalAssistantCreationResourceState.absent,
          );
        }
        if (receipt.kind == LocalAssistantDraftKind.note) {
          final rows = await tx.rawQuery(
            "SELECT substr(CAST(title AS BLOB),1,4096) AS title,length(CAST(title AS BLOB)) AS title_bytes,"
            "substr(CAST(labels AS BLOB),1,65536) AS labels,length(CAST(labels AS BLOB)) AS labels_bytes,"
            "substr(collection,1,64) AS collection,substr(editor_type,1,64) AS editor_type,"
            "CASE WHEN typeof(deleted)='integer' THEN deleted ELSE NULL END AS deleted,"
            "CASE WHEN typeof(updated_at)='integer' THEN updated_at ELSE NULL END AS updated_at,"
            "length(CAST(content AS BLOB)) AS body_bytes,"
            "CASE WHEN hex(substr(CAST(content AS BLOB),1,4))='454E433A' OR hex(substr(CAST(content AS BLOB),1,7))='EFBBBF454E433A' THEN 1 ELSE 0 END AS protected "
            "FROM notes WHERE id=?",
            [receipt.resourceId],
          );
          if (rows.isEmpty) {
            return _inspection(
              key,
              receipt,
              LocalAssistantCreationResourceState.missing,
            );
          }
          final row = rows.single;
          final meta = [
            row['collection'],
            row['editor_type'],
            row['deleted'],
            row['updated_at'],
            row['title_bytes'],
            row['labels_bytes'],
            row['body_bytes'],
          ];
          if (row['deleted'] == 1) {
            return _inspection(
              key,
              receipt,
              LocalAssistantCreationResourceState.missing,
              metadata: meta,
            );
          }
          if (row['collection'] != 'note' || row['editor_type'] != 'markdown') {
            return _inspection(
              key,
              receipt,
              LocalAssistantCreationResourceState.formatChanged,
              metadata: meta,
            );
          }
          if (row['protected'] == 1) {
            return _inspection(
              key,
              receipt,
              LocalAssistantCreationResourceState.protected,
              metadata: meta,
            );
          }
          try {
            if (row['deleted'] != 0) {
              throw const FormatException('Invalid current note flags');
            }
            final title = _smallText(row['title'], row['title_bytes'], 4096);
            final rawLabels = jsonDecode(
              _smallText(row['labels'], row['labels_bytes'], 65536),
            );
            if (rawLabels is! List ||
                rawLabels.any((label) => label is! String)) {
              throw const FormatException('Invalid current note labels');
            }
            _guard();
            final content = await BoundedNoteTextReader.readNoteContent(
              tx,
              id: receipt.resourceId,
              collection: 'note',
              editorType: 'markdown',
            );
            final input = LocalAssistantCreationInput.note(
              Note(
                title: title,
                content: content,
                labels: rawLabels.cast<String>(),
              ),
            );
            return _inspection(
              key,
              receipt,
              input.digest == receipt.inputHash
                  ? LocalAssistantCreationResourceState.matching
                  : LocalAssistantCreationResourceState.changed,
              currentHash: input.digest,
              metadata: meta,
              note: Note(
                id: receipt.resourceId,
                title: title,
                content: content,
                labels: rawLabels.cast<String>(),
              ),
            );
          } on FormatException {
            return _inspection(
              key,
              receipt,
              LocalAssistantCreationResourceState.unreadable,
              metadata: meta,
            );
          }
        }
        final rows = await tx.rawQuery(
          "SELECT substr(CAST(content AS BLOB),1,4000) AS content,length(CAST(content AS BLOB)) AS content_bytes,"
          "substr(due_date,1,11) AS due_date,"
          "CASE WHEN typeof(done)='integer' THEN done ELSE NULL END AS done,"
          "CASE WHEN typeof(parent_id)='integer' THEN parent_id ELSE NULL END AS parent_id,"
          "CASE WHEN typeof(topic_id)='integer' THEN topic_id ELSE NULL END AS topic_id,"
          "CASE WHEN typeof(deleted)='integer' THEN deleted ELSE NULL END AS deleted,"
          "substr(modify_time,1,64) AS modify_time "
          "FROM tasks WHERE task_id=?",
          [receipt.resourceId],
        );
        if (rows.isEmpty) {
          return _inspection(
            key,
            receipt,
            LocalAssistantCreationResourceState.missing,
          );
        }
        final row = rows.single;
        final meta = [
          row['content_bytes'],
          row['due_date'],
          row['done'],
          row['parent_id'],
          row['topic_id'],
          row['deleted'],
          row['modify_time'],
        ];
        if (row['deleted'] == 1) {
          return _inspection(
            key,
            receipt,
            LocalAssistantCreationResourceState.missing,
            metadata: meta,
          );
        }
        try {
          if (row['deleted'] != 0 ||
              !{0, 1}.contains(row['done']) ||
              row['parent_id'] is! int ||
              row['topic_id'] is! int ||
              row['due_date'] is! String) {
            throw const FormatException('Invalid current task metadata');
          }
          final content = _smallText(
            row['content'],
            row['content_bytes'],
            4000,
          );
          final task = TaskItem(
            id: receipt.resourceId,
            content: content,
            dueDate: row['due_date'] as String,
            done: row['done'] == 1,
            parentId: row['parent_id'] as int,
            topicId: row['topic_id'] as int,
          );
          task.writeBody();
          final hash = sha256
              .convert(
                utf8.encode(
                  jsonEncode({
                    'kind': 'task',
                    'content': content,
                    'due_date': task.dueDate,
                    'done': task.done,
                    'parent_id': task.parentId,
                    'topic_id': task.topicId ?? 0,
                  }),
                ),
              )
              .toString();
          return _inspection(
            key,
            receipt,
            hash == receipt.inputHash
                ? LocalAssistantCreationResourceState.matching
                : LocalAssistantCreationResourceState.changed,
            currentHash: hash,
            metadata: meta,
            task: task,
          );
        } on FormatException {
          return _inspection(
            key,
            receipt,
            LocalAssistantCreationResourceState.unreadable,
            metadata: meta,
          );
        }
      }, exclusive: false);
      _guard();
      return result;
    });
  }

  Future<LocalAssistantCreationReceipt> create(
    String key,
    LocalAssistantCreationInput input, {
    required String preparedHash,
  }) {
    _key(key);
    _guard();
    if (preparedHash != input.digest) {
      throw const FormatException('Prepared editor input changed');
    }
    final stamp = now();
    if (stamp.millisecondsSinceEpoch <= 0) {
      throw StateError('Invalid creation clock');
    }
    return store.maintenance.use(() async {
      _guard();
      final receipt = await (await store.database).transaction((tx) async {
        _guard();
        final old = await _lookup(tx, key);
        if (old != null) throw LocalAssistantCreationAlreadyRecorded(old);
        final data = input.values;
        final int id;
        if (input.kind == LocalAssistantDraftKind.note) {
          id = await tx.rawInsert(
            "INSERT INTO notes (collection,editor_type,title,content,labels,updated_at) "
            "VALUES ('note','markdown',CAST(? AS TEXT),CAST(? AS TEXT),?,?)",
            [
              Uint8List.fromList(utf8.encode(data['title'] as String)),
              Uint8List.fromList(utf8.encode(data['content'] as String)),
              jsonEncode(data['labels']),
              stamp.millisecondsSinceEpoch,
            ],
          );
        } else {
          final time = stamp.toIso8601String();
          id = await tx.rawInsert(
            'INSERT INTO tasks (content,due_date,done,parent_id,topic_id,create_time,modify_time,complete_time) '
            'VALUES (CAST(? AS TEXT),?,?,0,0,?,?,?)',
            [
              Uint8List.fromList(utf8.encode(data['content'] as String)),
              data['due_date'],
              data['done'] == true ? 1 : 0,
              time,
              time,
              data['done'] == true ? time : null,
            ],
          );
        }
        await tx.insert('assistant_creation_receipts', {
          'creation_key': key,
          'resource_type': input.kind.name,
          'resource_id': id,
          'input_hash': preparedHash,
          'created_at': stamp.millisecondsSinceEpoch,
        });
        _guard();
        return LocalAssistantCreationReceipt(
          key: key,
          kind: input.kind,
          resourceId: id,
          inputHash: preparedHash,
          createdAt: stamp.millisecondsSinceEpoch,
        );
      });
      _guard();
      return receipt;
    });
  }
}
