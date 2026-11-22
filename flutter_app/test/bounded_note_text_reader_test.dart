import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:bookstark_flutter/core/bounded_note_text_reader.dart';
import 'package:bookstark_flutter/core/local_store.dart';
import 'package:bookstark_flutter/core/notes_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/open.dart';

class _RecordingExecutor implements DatabaseExecutor {
  _RecordingExecutor(this.body, this.reportedLength);
  final Uint8List body;
  final int reportedLength;
  final queries = <String>[];

  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) async {
    queries.add(sql);
    if (sql.contains('length(CAST(content AS BLOB))')) {
      return [
        <String, Object?>{'byte_length': reportedLength},
      ];
    }
    final offset = arguments![0] as int;
    final count = arguments[1] as int;
    return [
      <String, Object?>{
        'body_chunk': Uint8List.sublistView(
          body,
          offset - 1,
          offset - 1 + count,
        ),
      },
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    if (Platform.isLinux) {
      open.overrideFor(
        OperatingSystem.linux,
        () => DynamicLibrary.open('libsqlite3.so.0'),
      );
    }
  });

  late Directory directory;
  late LocalStore store;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('bounded-local-text-');
    store = LocalStore(
      path: '${directory.path}/notes.db',
      factory: databaseFactoryFfiNoIsolate,
    );
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  test(
    'bounded note read assembles UTF-8 chunks and restores BOM exactly',
    () async {
      final source = '\ufeff<!doctype html>\r\n${'中文😀abc' * 70000}';
      final bytes = Uint8List.fromList(utf8.encode(source));
      final executor = _RecordingExecutor(bytes, bytes.length);
      final actual = await BoundedNoteTextReader.readNoteContent(
        executor,
        id: 8,
        collection: 'note',
        editorType: 'html',
      );

      expect(actual, source);
      expect(utf8.encode(actual), bytes);
      expect(executor.queries.first, contains('length(CAST(content AS BLOB))'));
      expect(
        executor.queries.skip(1),
        everyElement(contains('substr(CAST(content AS BLOB)')),
      );
      expect(executor.queries.length, 1 + (bytes.length / 262144).ceil());
      expect(executor.queries, everyElement(isNot(contains('SELECT content'))));
    },
  );

  test('repeated leading BOMs survive bounded strict UTF-8 decoding', () async {
    for (final count in [0, 1, 2, 3]) {
      final source = '${List<String>.filled(count, '\ufeff').join()}A';
      final bytes = Uint8List.fromList(utf8.encode(source));
      final actual = await BoundedNoteTextReader.readNoteContent(
        _RecordingExecutor(bytes, bytes.length),
        id: 80 + count,
        collection: 'note',
        editorType: 'html',
      );
      expect(actual, source, reason: 'leading BOM count $count');
      expect(utf8.encode(actual), bytes, reason: 'leading BOM count $count');
    }
    final emptyBomSource = List<String>.filled(3, '\ufeff').join();
    final emptyBomBytes = Uint8List.fromList(utf8.encode(emptyBomSource));
    expect(
      await BoundedNoteTextReader.readNoteContent(
        _RecordingExecutor(emptyBomBytes, emptyBomBytes.length),
        id: 84,
        collection: 'note',
        editorType: 'html',
      ),
      emptyBomSource,
    );
  });

  test(
    'over-limit metadata is rejected before any content chunk is selected',
    () async {
      final executor = _RecordingExecutor(
        Uint8List(1),
        BoundedNoteTextReader.maxBytes + 1,
      );
      await expectLater(
        BoundedNoteTextReader.readNoteContent(
          executor,
          id: 9,
          collection: 'article',
          editorType: 'presentation',
        ),
        throwsFormatException,
      );
      expect(executor.queries, hasLength(1));
      expect(
        executor.queries.single,
        contains('length(CAST(content AS BLOB))'),
      );
    },
  );

  test('malformed UTF-8 is rejected instead of replacement decoding', () async {
    final id = await (await store.database).insert('notes', {
      'title': 'Malformed',
      'content': Uint8List.fromList([0xc3, 0x28]),
      'updated_at': 1,
      'labels': '[]',
      'collection': 'note',
      'editor_type': 'markdown',
    });
    await expectLater(
      LocalNotesRepository(store).read(id),
      throwsFormatException,
    );
  });

  test(
    'Markdown read is metadata-first and retains long source byte-for-byte',
    () async {
      final source = '${'## heading 文档 😀\r\n' * 50000}# tail\r\n';
      final id = await (await store.database).insert('notes', {
        'title': 'Large markdown',
        'content': source,
        'updated_at': 1793923200000,
        'labels': '["literal,label","标签😀"]',
        'collection': 'article',
        'editor_type': 'markdown',
      });

      final note = await LocalNotesRepository(
        store,
        collection: NoteCollection.article,
      ).read(id);
      expect(note.content, source);
      expect(note.title, 'Large markdown');
      expect(note.labels, ['literal,label', '标签😀']);
      expect(note.updatedAt!.millisecondsSinceEpoch, 1793923200000);
      // Existing full-row API keeps its full-content default for other callers.
      final legacy = await store.readNote(id, collection: 'article');
      expect(legacy['content'], source);
    },
  );

  test(
    'Markdown read keeps the legacy unbounded document size via chunks',
    () async {
      final source = '${'m' * (BoundedNoteTextReader.maxBytes + 257)}尾';
      final id = await (await store.database).insert('notes', {
        'title': 'Over prior bounded limit',
        'content': source,
        'updated_at': 1793923200001,
        'labels': '[]',
        'collection': 'note',
        'editor_type': 'markdown',
      });

      final actual = await LocalNotesRepository(store).read(id);
      expect(
        actual.content.length,
        greaterThan(BoundedNoteTextReader.maxBytes),
      );
      expect(actual.content, source);
    },
  );

  test(
    'typed note dispatch reports editor type before bounded body decoding',
    () async {
      final id = await (await store.database).insert('notes', {
        'title': 'HTML',
        // A malformed blob proves typed dispatch does not try to decode source
        // through the Markdown path before reporting the required editor.
        'content': Uint8List.fromList([0xc3, 0x28]),
        'updated_at': 1,
        'labels': '[]',
        'collection': 'note',
        'editor_type': 'html',
      });

      await expectLater(
        LocalNotesRepository(store).read(id),
        throwsA(
          isA<DedicatedEditorRequired>().having(
            (error) => error.editorType,
            'editorType',
            'html',
          ),
        ),
      );
    },
  );

  test('document Markdown is also read through bounded byte chunks', () async {
    final db = await store.database;
    final bookId = await db.insert('books', {
      'book_name': 'Book',
      'identify': 'bounded-reader-book',
      'create_time': '2026-11-06',
      'modify_time': '2026-11-06',
    });
    final source = '\ufeff# 标题\r\n${'正文😀' * 90000}';
    final documentId = await db.insert('documents', {
      'book_id': bookId,
      'document_name': 'Large document',
      'identify': 'bounded-reader-document',
      'doc_type': 'markdown',
      'markdown': source,
      'create_time': '2026-11-06',
      'modify_time': '2026-11-06',
    });
    final actual = await db.transaction(
      (tx) => BoundedNoteTextReader.readDocumentMarkdown(tx, id: documentId),
    );
    expect(actual, source);

    final richDocId = await db.insert('documents', {
      'book_id': bookId,
      'document_name': 'Non HTML document type',
      'identify': 'bounded-reader-richdoc',
      'doc_type': 'richdoc',
      'markdown': '非HTML检索正文😀',
      'create_time': '2026-11-06',
      'modify_time': '2026-11-06',
    });
    expect(
      await db.transaction(
        (tx) => BoundedNoteTextReader.readDocumentMarkdown(
          tx,
          id: richDocId,
          maxRecordBytes: null,
        ),
      ),
      '非HTML检索正文😀',
    );

    final htmlId = await db.insert('documents', {
      'book_id': bookId,
      'document_name': 'HTML excluded from Markdown scan',
      'identify': 'bounded-reader-html',
      'doc_type': 'html',
      'markdown': '<p>not scanned as Markdown</p>',
      'create_time': '2026-11-06',
      'modify_time': '2026-11-06',
    });
    await expectLater(
      db.transaction(
        (tx) => BoundedNoteTextReader.readDocumentMarkdown(
          tx,
          id: htmlId,
          maxRecordBytes: null,
        ),
      ),
      throwsStateError,
    );
  });
}
