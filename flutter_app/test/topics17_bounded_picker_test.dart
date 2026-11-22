import 'dart:ffi';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:bookstark_flutter/core/local_store.dart';
import 'package:bookstark_flutter/core/notes_repository.dart';
import 'package:bookstark_flutter/core/local_note_list_source.dart';
import 'package:bookstark_flutter/core/remote_note_list_source.dart';
import 'package:bookstark_flutter/core/topic_resource_picker_repository.dart';
import 'package:bookstark_flutter/core/topics_repository.dart';
import '../tool/fixtures/books.dart';
import '../tool/fixtures/bookmarks.dart';
import '../tool/fixtures/tasks.dart';

class NoBodies implements NotesRepository {
  int calls = 0;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls++;
    throw StateError('No body/list/edit allowed in metadata picker');
  }
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
  test(
    'real local SQLite candidate metadata avoids old body list and preserves large BOM emoji CRLF source',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'topic-picker-metadata-',
      );
      final store = LocalStore(
        path: '${directory.path}/data.db',
        factory: databaseFactoryFfiNoIsolate,
      );
      try {
        final db = await store.database;
        final source = '\ufeff${List.filled(350000, '😀\r\n').join()}';
        final id = await db.insert('notes', {
          'title': 'large exact note',
          'content': source,
          'updated_at': 1,
        });
        await db.insert('notes', {
          'title': 'protected existing',
          'content': '\ufeffENC:v99:opaque bytes',
          'updated_at': 2,
        });
        final repeated = await db.insert('notes', {
          'title': 'repeated BOM preview',
          'content': '\ufeff\ufeff😀\r\nrest',
          'updated_at': 3,
          'collection': 'article',
        });
        final bounded = await store.notesForList(
          collection: 'article',
          previewRunes: 3,
        );
        expect(bounded.single['id'], repeated);
        expect(bounded.single['content_preview'], '\ufeff\ufeff😀');
        await expectLater(
          store.notesForList(previewRunes: 513),
          throwsArgumentError,
        );
        final local = LocalNotesRepository(store), trap = NoBodies();
        final picker = ExistingTopicResourcePickerRepository(
          notes: trap,
          articles: trap,
          noteMetadata: LocalNoteListSource(repository: local),
          bookRepository: BooksFixture(),
          documents: DocumentsFixture(),
          bookmarks: BookmarksFixture(),
          tasks: TaskFixture(),
        );
        final result = await picker.list(TopicResourceType.note);
        final large = result.items.singleWhere((row) => row.id == id);
        expect(large.description, String.fromCharCodes(source.runes.take(200)));
        expect(large.description.startsWith('\ufeff😀\r\n'), isTrue);
        final locked = result.items.singleWhere(
          (row) => row.title == 'protected existing',
        );
        expect(locked.protected, isTrue);
        expect(locked.description, isEmpty);
        expect(
          locked.forTopic(7).writeBody()['desc_snapshot'],
          '受保护笔记 / Protected note',
        );
        expect(result.hasMore, isFalse);
        expect(trap.calls, 0);
        expect((await local.read(id)).content, source);
        final protectedBytes = (await db.rawQuery(
          'SELECT CAST(content AS BLOB) AS bytes FROM notes WHERE title = ?',
          ['protected existing'],
        )).single['bytes'];
        expect(
          protectedBytes,
          orderedEquals(utf8.encode('\ufeffENC:v99:opaque bytes')),
        );
      } finally {
        await store.close();
        await directory.delete(recursive: true);
      }
    },
  );
  test(
    'real remote metadata source uses article collection owner and exact paging without old list',
    () async {
      final trap = NoBodies();
      String? request;
      final preview = '\ufeff${List.filled(100, '😀\r\n').join()}';
      final metadata = RemoteNoteListSource(
        expectedMemberId: 7,
        readBoundedPage: (path) async {
          request = path;
          return {
            'code': 0,
            'total': 1,
            'page': 1,
            'page_size': 20,
            'total_pages': 1,
            'data': [
              {
                'blog_id': 42,
                'member_id': 7,
                'blog_type': 'article',
                'blog_title': 'actual article',
                'content_preview': preview,
                'has_password': false,
                'labels': <String>[],
                'is_pinned': false,
                'visibility': 0,
                'editor_type': 'html',
              },
            ],
          };
        },
      );
      final picker = ExistingTopicResourcePickerRepository(
        notes: trap,
        articles: trap,
        articleMetadata: metadata,
        bookRepository: BooksFixture(),
        documents: DocumentsFixture(),
        bookmarks: BookmarksFixture(),
        tasks: TaskFixture(),
      );
      final result = await picker.list(
        TopicResourceType.article,
        keyword: 'exact keyword',
      );
      final query = Uri.parse(
        'https://example.test${request!}',
      ).queryParameters;
      expect(query['type'], 'article');
      expect(query['metadata_only'], '1');
      expect(query['keyword'], 'exact keyword');
      expect(
        result.items.single.description,
        String.fromCharCodes(preview.runes.take(200)),
      );
      expect(result.items.single.forTopic(9).targetId, 42);
      expect(result.hasMore, isFalse);
      expect(result.total, 1);
      expect(trap.calls, 0);
    },
  );
}
