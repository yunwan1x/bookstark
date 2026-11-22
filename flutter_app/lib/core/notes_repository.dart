import 'dart:convert';
import 'local_protected_content.dart';
import 'api_client.dart';
import 'bounded_note_text_reader.dart';
import 'local_store.dart';
import 'note_list_entry.dart';
import 'resource_labels.dart';

class DedicatedEditorRequired implements Exception {
  const DedicatedEditorRequired(this.id, this.editorType);
  final int id;
  final String editorType;
}

class Note {
  const Note({
    this.id,
    required this.title,
    required this.content,
    this.labels = const [],
    this.isProtected = false,
    this.unlockPassword,
    this.updatedAt,
  });
  final int? id;
  final DateTime? updatedAt;
  final String title, content;
  final List<String> labels;
  final bool isProtected;
  // Ephemeral: never serialize this value or retain it outside an open editor.
  final String? unlockPassword;
  Note copyWith({
    int? id,
    String? title,
    String? content,
    List<String>? labels,
  }) => Note(
    id: id ?? this.id,
    title: title ?? this.title,
    content: content ?? this.content,
    labels: labels ?? this.labels,
    isProtected: isProtected,
    unlockPassword: unlockPassword,
    updatedAt: updatedAt,
  );
}

enum NoteCollection { note, article }

abstract interface class NoteListRepository {
  Future<List<NoteListEntry>> listEntries({
    String keyword = '',
    int page = 1,
    String label = '',
    String pinned = '',
  });
}

abstract interface class FilteredNotesRepository {
  Future<List<Note>> listFiltered({
    String keyword = '',
    int page = 1,
    String label = '',
    String pinned = '',
  });
}

abstract class NotesRepository {
  Future<List<Note>> list({String keyword = '', int page = 1});
  Future<Note> read(int id);
  Future<int> save(Note note);
  Future<void> remove(int id);
}

class NoteSaveFailure implements Exception {
  const NoteSaveFailure(this.savedId, this.message);
  final int savedId;
  final String message;
  @override
  String toString() => message;
}

class NoteLocked implements Exception {
  const NoteLocked(this.id);
  final int id;
}

abstract interface class ProtectedNotesRepository {
  Future<Note> unlock(int id, String password);
}

class RemoteNotesRepository
    implements
        NotesRepository,
        ProtectedNotesRepository,
        FilteredNotesRepository,
        NoteListRepository {
  RemoteNotesRepository(this.client, {this.collection = NoteCollection.note});
  final NoteCollection collection;
  final BookstarkClient client;
  @override
  Future<List<Note>> list({String keyword = '', int page = 1}) =>
      listFiltered(keyword: keyword, page: page);
  @override
  Future<List<Note>> listFiltered({
    String keyword = '',
    int page = 1,
    String label = '',
    String pinned = '',
  }) async {
    final result = await client.get(
      '/api/blogs?type=${collection.name}&page=$page&keyword=${Uri.encodeQueryComponent(keyword)}&label=${Uri.encodeQueryComponent(label)}&pinned=${Uri.encodeQueryComponent(pinned)}',
    );
    return (result['data'] as List? ?? const []).map((value) {
      final row = value as Map;
      return Note(
        id: row['blog_id'] as int,
        title: row['blog_title'] as String? ?? '',
        content: row['content_preview'] as String? ?? '',
        isProtected: row['has_password'] == true,
        labels: (row['labels'] as List? ?? []).cast<String>(),
        updatedAt: DateTime.tryParse(row['modify_time'] as String? ?? ''),
      );
    }).toList();
  }

  @override
  Future<List<NoteListEntry>> listEntries({
    String keyword = '',
    int page = 1,
    String label = '',
    String pinned = '',
  }) async =>
      (await listFiltered(
            keyword: keyword,
            page: page,
            label: label,
            pinned: pinned,
          ))
          .map(
            (note) => NoteListEntry(
              id:
                  note.id ??
                  (throw const FormatException('List item has no ID')),
              title: note.title,
              contentPreview: String.fromCharCodes(
                note.content.runes.take(512),
              ),
              labels: note.labels,
              updatedAt: note.updatedAt,
              isProtected: note.isProtected,
            ),
          )
          .toList();

  @override
  Future<Note> read(int id) => _read(id);
  @override
  Future<Note> unlock(int id, String password) => _read(id, password: password);
  Future<Note> _read(int id, {String? password}) async {
    final row = await client.get('/api/blogs/$id');
    if (row['blog_type'] != null && row['blog_type'] != collection.name) {
      throw StateError('Resource belongs to a different collection');
    }
    if ((row['editor_type'] ?? 'markdown') != 'markdown') {
      throw DedicatedEditorRequired(id, row['editor_type'] as String);
    }
    final protected = row['has_password'] == true;
    if (protected && (password == null || password.isEmpty)) {
      throw NoteLocked(id);
    }
    var content = row['blog_content'];
    if (protected) {
      final result = await client.post('/api/blogs/$id/verify-password', {
        'password': password,
      });
      content = result['blog_content'];
    }
    if (content is! String) throw const FormatException('Invalid note content');
    final labels = await client.get('/api/labels/resource/blog/$id');
    return Note(
      id: id,
      title: row['blog_title'] as String? ?? '',
      content: content,
      labels: (labels['data'] as List? ?? const []).cast<String>(),
      isProtected: protected,
      unlockPassword: protected ? password : null,
    );
  }

  @override
  Future<int> save(Note note) async {
    final labels = encodeResourceLabels(note.labels);
    if (note.isProtected &&
        (note.unlockPassword == null ||
            note.unlockPassword!.isEmpty ||
            note.id == null)) {
      throw StateError('Unlock the note before saving');
    }
    final body = <String, Object?>{
      'blog_title': note.title,
      'blog_content': note.content,
      'labels': labels,
      if (note.isProtected) 'password': note.unlockPassword,
    };
    final int id;
    if (note.id != null) {
      await client.mutate('PUT', '/api/blogs/${note.id}', body);
      id = note.id!;
    } else {
      final result = await client.post('/api/blogs', {
        ...body,
        'blog_type': collection.name,
        'editor_type': 'markdown',
        'visibility': 0,
      });
      id = result['blog_id'] as int;
    }
    // Blog PUT skips empty labels and ignores label binding errors. This owner
    // uses the dedicated endpoint for verified replacement, including clearing.
    try {
      await client.mutate('PUT', '/api/labels/resource/blog/$id', {
        'labels': labels,
      });
    } catch (error) {
      // Creation may already have succeeded. Preserve its ID to prevent a
      // second POST from creating a duplicate when the user retries.
      throw NoteSaveFailure(id, error.toString());
    }
    return id;
  }

  @override
  Future<void> remove(int id) async {
    await client.mutate('DELETE', '/api/blogs/$id', {});
  }
}

class LocalNotesRepository
    implements NotesRepository, FilteredNotesRepository, NoteListRepository {
  LocalNotesRepository(this.store, {this.collection = NoteCollection.note});
  final NoteCollection collection;
  final LocalStore store;
  Note _note(Map<String, Object?> row) => Note(
    id: row['id'] as int,
    title: row['title'] as String,
    content: isLocalProtectedEnvelopePrefix(row['content'] as String)
        ? ''
        : row['content'] as String,
    isProtected: isLocalProtectedEnvelopePrefix(row['content'] as String),
    labels: (jsonDecode(row['labels'] as String) as List).cast<String>(),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
  );
  @override
  Future<List<Note>> list({String keyword = '', int page = 1}) => store
      .maintenance
      .use(() async => listFiltered(keyword: keyword, page: page));
  @override
  Future<List<Note>> listFiltered({
    String keyword = '',
    int page = 1,
    String label = '',
    String pinned = '',
  }) => store.maintenance.use(
    () async => (await store.notes(
      keyword: keyword,
      offset: (page - 1) * 20,
      collection: collection.name,
      label: label,
    )).map(_note).toList(),
  );
  @override
  Future<List<NoteListEntry>> listEntries({
    String keyword = '',
    int page = 1,
    String label = '',
    String pinned = '',
  }) => store.maintenance.use(
    () async =>
        (await store.notesForList(
              keyword: keyword,
              offset: (page - 1) * 20,
              collection: collection.name,
              label: label,
            ))
            .map(
              (row) => NoteListEntry(
                id: row['id'] as int,
                title: row['title'] as String,
                contentPreview:
                    isLocalProtectedEnvelopePrefix(
                      row['content_preview'] as String,
                    )
                    ? ''
                    : row['content_preview'] as String,
                isProtected: isLocalProtectedEnvelopePrefix(
                  row['content_preview'] as String,
                ),
                labels: (jsonDecode(row['labels'] as String) as List)
                    .cast<String>(),
                updatedAt: DateTime.fromMillisecondsSinceEpoch(
                  row['updated_at'] as int,
                ),
              ),
            )
            .toList(),
  );

  /// Metadata only: article routing must not materialize a Markdown body first.
  Future<String> editorTypeOf(int id) => store.maintenance.use(() async {
    if (id <= 0) throw const FormatException('Invalid local note identity');
    final rows = await (await store.database).query(
      'notes',
      columns: ['editor_type'],
      where: 'id = ? AND collection = ? AND deleted = 0',
      whereArgs: [id, collection.name],
    );
    if (rows.length != 1 || rows.single['editor_type'] is! String) {
      throw StateError('Local note metadata unavailable');
    }
    return rows.single['editor_type'] as String;
  });

  @override
  Future<Note> read(int id) => store.maintenance.use(() async {
    final db = await store.database;
    return db.transaction((tx) async {
      final rows = await tx.rawQuery(
        'SELECT id,title,labels,updated_at,collection,editor_type,'
        'hex(substr(CAST(content AS BLOB),1,7)) AS protected_prefix '
        'FROM notes WHERE id = ? AND deleted = 0 AND collection = ?',
        [id, collection.name],
      );
      if (rows.isEmpty) throw StateError('Note no longer exists');
      final metadata = rows.single;
      final type = metadata['editor_type'];
      if (type is! String) {
        throw const FormatException('Invalid local note editor type');
      }
      if (type != 'markdown') throw DedicatedEditorRequired(id, type);
      if (isLocalProtectedEnvelopeHexPrefix(metadata['protected_prefix'])) {
        throw NoteLocked(id);
      }
      final content = await BoundedNoteTextReader.readNoteContent(
        tx,
        id: id,
        collection: collection.name,
        editorType: 'markdown',
        maxRecordBytes: null,
      );
      return _note({...metadata, 'content': content});
    });
  });

  @override
  Future<int> save(Note note) => store.maintenance.use(() async {
    if (note.isProtected) {
      if (note.id != null) throw NoteLocked(note.id!);
      throw const FormatException(
        'Local protected Markdown requires its dedicated owner',
      );
    }
    if (isLocalProtectedEnvelopePrefix(note.content)) {
      throw const FormatException(
        'ENC: is reserved for protected local content',
      );
    }
    if (note.id == null) {
      return store.createNote(
        note.title,
        note.content,
        labels: note.labels,
        collection: collection.name,
      );
    }
    final id = note.id!;
    final db = await store.database;
    return db.transaction((tx) async {
      // Check the CURRENT stored identity, format and bounded protection marker
      // in the same transaction as UPDATE, not the editor's stale snapshot.
      final rows = await tx.rawQuery(
        'SELECT editor_type,hex(substr(CAST(content AS BLOB),1,7)) AS protected_prefix '
        'FROM notes WHERE id = ? AND deleted = 0 AND collection = ?',
        [id, collection.name],
      );
      if (rows.length != 1) throw StateError('Note no longer exists');
      final type = rows.single['editor_type'];
      if (type is! String) {
        throw const FormatException('Invalid local note editor type');
      }
      if (type != 'markdown') throw DedicatedEditorRequired(id, type);
      if (isLocalProtectedEnvelopeHexPrefix(rows.single['protected_prefix'])) {
        throw NoteLocked(id);
      }
      final count = await tx.rawUpdate(
        'UPDATE notes SET title=CAST(? AS TEXT),content=CAST(? AS TEXT),'
        'labels=?,updated_at=? '
        "WHERE id = ? AND deleted = 0 AND collection = ? AND editor_type = 'markdown'",
        [
          utf8.encode(note.title),
          utf8.encode(note.content),
          jsonEncode(note.labels),
          DateTime.now().millisecondsSinceEpoch,
          id,
          collection.name,
        ],
      );
      if (count != 1) throw StateError('Note no longer exists');
      return id;
    });
  });

  @override
  Future<void> remove(int id) => store.maintenance.use(
    () async => store.deleteNote(id, collection: collection.name),
  );
}
