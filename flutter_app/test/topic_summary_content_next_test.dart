import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:bookstark_flutter/core/local_store.dart';
import 'package:bookstark_flutter/core/local_topics_repository.dart';
import 'package:bookstark_flutter/core/topics_repository.dart';
import 'package:bookstark_flutter/core/summary_editor_repository.dart';
import 'package:bookstark_flutter/core/notes_repository.dart';

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
    'real local body-only editor keeps concurrent type/order and rejects changed body with exact rollback',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'summary-body-cas-',
      );
      final store = LocalStore(
        path: '${directory.path}/data.db',
        factory: databaseFactoryFfiNoIsolate,
      );
      try {
        final topics = LocalTopicsRepository(store), db = await store.database;
        final id = await topics.save(
          const TopicItem(title: 'same title', question: 'same question'),
        );
        final summary = await topics.saveSummary(
          TopicSummary(
            topicId: id,
            content: 'initial body',
            type: 'manual',
            order: 3,
          ),
        );
        final baseline = await topics.readSummaryForEditing(id, summary.id!);
        final editor = SummaryEditorRepository(topics, baseline);
        await db.update(
          'topic_summaries',
          {'summary_type': 'ai', 'order_sort': 99},
          where: 'summary_id=?',
          whereArgs: [summary.id],
        );
        await editor.save(Note(id: summary.id, title: '', content: 'new body'));
        final actual = await topics.readSummaryForEditing(id, summary.id!);
        expect(actual.type, 'ai');
        expect(actual.order, 99);
        expect(actual.content, 'new body');
        expect(actual.createdAt, baseline.createdAt);
        final stale = SummaryEditorRepository(topics, actual);
        await db.update(
          'topic_summaries',
          {'content': 'externally changed'},
          where: 'summary_id=?',
          whereArgs: [summary.id],
        );
        final before = await db.query(
          'topic_summaries',
          where: 'summary_id=?',
          whereArgs: [summary.id],
        );
        await expectLater(
          stale.save(Note(id: summary.id, title: '', content: 'stale body')),
          throwsStateError,
        );
        expect(
          await db.query(
            'topic_summaries',
            where: 'summary_id=?',
            whereArgs: [summary.id],
          ),
          before,
        );
        expect((await topics.read(id)).topic.title, 'same title');
        // Source-only reads preserve every BOM/CRLF byte even when the TEXT cursor decoder would consume BOM.
        await db.update(
          'topic_summaries',
          {'content': '\ufeff\ufeff# exact😀\r\nbody'},
          where: 'summary_id=?',
          whereArgs: [summary.id],
        );
        final exact = await topics.readSummaryForEditing(id, summary.id!);
        expect(
          utf8.encode(exact.content),
          orderedEquals(utf8.encode('\ufeff\ufeff# exact😀\r\nbody')),
        );
      } finally {
        await store.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
