import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:sqlite3/open.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/local_store.dart';
import 'package:bookstark_flutter/core/local_search_repository.dart';
import 'package:bookstark_flutter/core/local_search_content_reader.dart';
import 'package:bookstark_flutter/core/search_repository.dart';

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
  for (final cumulative in [false, true]) {
    test(
      cumulative
          ? 'streamed candidates over32MiB aggregate retain all hits without resident body copies'
          : 'legacy source larger than20MiB remains searchable through fixed blocks',
      () async {
        final store = LocalStore(
          path: inMemoryDatabasePath,
          factory: databaseFactoryFfiNoIsolate,
        );
        try {
          final db = await store.database;
          final length = cumulative
              ? 17 * 1024 * 1024
              : LocalSearchContentReader.maxRecordBytes + 1;
          for (var i = 0; i < (cumulative ? 2 : 1); i++) {
            await db.rawInsert(
              "INSERT INTO notes(collection,title,content,labels,updated_at,editor_type) VALUES('note','Budget',CAST(zeroblob(?) AS TEXT),'[]',?,'markdown')",
              [length, i + 1],
            );
          }
          final before = await db.rawQuery(
            'SELECT id,length(CAST(content AS BLOB)) AS n,labels,updated_at FROM notes ORDER BY id',
          );
          final found = await LocalSearchRepository(store).search('Budget');
          expect(found.groups[SearchKind.blog], hasLength(cumulative ? 2 : 1));
          expect(
            await db.rawQuery(
              'SELECT id,length(CAST(content AS BLOB)) AS n,labels,updated_at FROM notes ORDER BY id',
            ),
            before,
          );
        } finally {
          await store.close();
        }
      },
    );
  }
  test(
    'topic question and all context fields use bounded BLOB chunks preserving cross-chunk BOM emoji CRLF',
    () async {
      final store = LocalStore(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfiNoIsolate,
      );
      try {
        final db = await store.database;
        final question =
            '\ufeff${'x' * 65532}😀\r\n${'q' * (3 * 1024 * 1024)} Needle tail';
        final id = await db.insert('topics', {
          'title': 'Plain topic',
          'question': question,
          'create_time': '2026-11-11',
          'modify_time': '2026-11-11',
        });
        await db.insert('topic_summaries', {
          'topic_id': id,
          'content': 'summary one\r\n😀',
          'create_time': '2026-11-11',
          'modify_time': '2026-11-11',
        });
        await db.insert('topic_summaries', {
          'topic_id': id,
          'content': 'summary two',
          'create_time': '2026-11-11',
          'modify_time': '2026-11-11',
        });
        await db.insert('topic_resources', {
          'topic_id': id,
          'resource_type': 'note',
          'target_id': 99,
          'title_snapshot': 'resource title',
          'desc_snapshot': 'resource description',
          'create_time': '2026-11-11',
        });
        await db.insert('tasks', {
          'topic_id': id,
          'content': 'topic task',
          'due_date': '',
          'create_time': '2026-11-11',
          'modify_time': '2026-11-11',
        });
        final helper = LocalSearchContentReader(guard: () {});
        final actual = await db.transaction(
          (tx) => helper.topicContext(tx, id),
        );
        expect(actual.question, question);
        expect(
          actual.context,
          '$question\nsummary one\r\n😀\nsummary two\nresource title\nresource description\ntopic task',
        );
        final results = await LocalSearchRepository(store).search('Needle');
        final topics = results.groups[SearchKind.topic]!;
        expect(topics, hasLength(1));
        expect(topics.single.id, id);
        expect(topics.single.question, question);
        expect(topics.single.snippet, contains('Needle'));
        expect(topics.single.itemCount, 1);
        final unchanged = (await db.rawQuery(
          'SELECT length(CAST(question AS BLOB)) AS n,hex(substr(CAST(question AS BLOB),1,7)) AS prefix,hex(substr(CAST(question AS BLOB),-4)) AS suffix FROM topics WHERE topic_id=?',
          [id],
        )).single;
        expect(unchanged, {
          'n': utf8.encode(question).length,
          'prefix': 'EFBBBF78787878',
          'suffix': '7461696C',
        });
      } finally {
        await store.close();
      }
    },
  );
  test(
    'malformed topic UTF8 tail never returns early matching partial text',
    () async {
      final store = LocalStore(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfiNoIsolate,
      );
      try {
        final db = await store.database;
        final id = await db.insert('topics', {
          'title': 'Needle',
          'question': '',
          'create_time': '2026-11-11',
          'modify_time': '2026-11-11',
        });
        await db.rawInsert(
          "INSERT INTO topic_summaries(topic_id,content,summary_type,order_sort,create_time,modify_time) VALUES(?,CAST(? AS TEXT),'manual',0,'2026-11-11','2026-11-11')",
          [
            id,
            Uint8List.fromList([
              78,
              101,
              101,
              100,
              108,
              101,
              32,
              ...List.filled(65530, 97),
              255,
            ]),
          ],
        );
        final before = (await db.rawQuery(
          'SELECT length(CAST(content AS BLOB)) AS n,hex(substr(CAST(content AS BLOB),-1)) AS tail FROM topic_summaries',
        )).single;
        await expectLater(
          LocalSearchRepository(store).search('Needle'),
          throwsFormatException,
        );
        expect(
          (await db.rawQuery(
            'SELECT length(CAST(content AS BLOB)) AS n,hex(substr(CAST(content AS BLOB),-1)) AS tail FROM topic_summaries',
          )).single,
          before,
        );
      } finally {
        await store.close();
      }
    },
  );
  test(
    'HTML source remains excluded while real title metadata is searchable',
    () async {
      final store = LocalStore(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfiNoIsolate,
      );
      try {
        await store.createNote(
          'Visible',
          '<script>HiddenNeedle</script>',
          collection: 'article',
        );
        final db = await store.database;
        await db.update('notes', {'editor_type': 'html'});
        final repo = LocalSearchRepository(store);
        expect(
          (await repo.search('HiddenNeedle')).groups[SearchKind.blog],
          isEmpty,
        );
        final title = (await repo.search('Visible')).groups[SearchKind.blog]!;
        expect(title, hasLength(1));
        expect(title.single.snippet, isEmpty);
      } finally {
        await store.close();
      }
    },
  );
}
