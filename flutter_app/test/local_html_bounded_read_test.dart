import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:bookstark_flutter/core/html_notes_repository.dart';
import 'package:bookstark_flutter/core/local_html_notes_repository.dart';
import 'package:bookstark_flutter/core/local_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory directory;
  late LocalStore store;
  late LocalHtmlNotesRepository repository;

  setUp(() async {
    sqfliteFfiInit();
    if (Platform.isLinux) {
      open.overrideFor(
        OperatingSystem.linux,
        () => DynamicLibrary.open('libsqlite3.so.0'),
      );
    }
    final root = Platform.environment['BOOKSTARK_APK_TEST_ROOT'];
    directory = await Directory(
      root ?? Directory.systemTemp.path,
    ).createTemp('local-html-bounded-');
    store = LocalStore(
      path: '${directory.path}/notes.db',
      factory: databaseFactoryFfiNoIsolate,
    );
    repository = LocalHtmlNotesRepository(store);
  });

  tearDown(() async {
    repository.dispose();
    await store.close();
    await directory.delete(recursive: true);
  });

  HtmlNoteEdit edit(
    String title, {
    String source = '<!doctype html>\r\n<p>原始内容 🧪</p>\r\n',
    List<String> labels = const ['one,literal,label'],
  }) => HtmlNoteEdit(title: title, source: source, labels: labels);

  test(
    'BOM creation keeps TEXT storage and a retry adopts the same exact row',
    () async {
      const source = '\ufeff<!doctype html>\r\n<p>创建 🧪</p>\r\n';
      const key = '0123456789abcdef0123456789abcdef';
      final input = edit('Exact creation', source: source);
      final created = await repository.createOnce(input, creationKey: key);
      final retried = await repository.createOnce(input, creationKey: key);
      expect(created.inserted, isTrue);
      expect(retried.inserted, isFalse);
      expect(retried.note.metadata.id, created.note.metadata.id);
      expect(retried.note.source, source);
      final db = await store.database;
      final row = (await db.rawQuery(
        'SELECT typeof(content) AS storage, CAST(content AS BLOB) AS bytes '
        'FROM notes WHERE id = ?',
        [created.note.metadata.id],
      )).single;
      expect(row['storage'], 'text');
      expect(row['bytes'], orderedEquals(utf8.encode(source)));
    },
  );

  test(
    'near-5MiB BOM, CRLF and emoji source saves and reads exact SQLite bytes',
    () async {
      const limit = 5 * 1024 * 1024;
      const unit = '<p>你好🧪</p>\r\n';
      const prefix = '\ufeff<!doctype html>\r\n';
      const suffix = '<!-- exact tail -->\r\n';
      final unitBytes = utf8.encode(unit).length;
      final fixedBytes =
          utf8.encode(prefix).length + utf8.encode(suffix).length;
      final repeats = (limit - fixedBytes) ~/ unitBytes;
      final buffer = StringBuffer()
        ..write(prefix)
        ..writeAll(List<String>.filled(repeats, unit))
        ..write(suffix);
      final source = buffer.toString();
      final sourceBytes = utf8.encode(source);
      expect(sourceBytes.length, lessThanOrEqualTo(limit));
      expect(sourceBytes.length, greaterThan(limit - unitBytes));

      final created = await repository.create(edit('Before large update'));
      final saved = await repository.save(
        created,
        edit('Near limit', source: source, labels: ['bom,crlf,emoji']),
      );
      expect(saved.allReceiptsKnown, isTrue);
      expect(saved.note.source, source);
      expect(saved.note.metadata.title, 'Near limit');
      expect(saved.note.labels, ['bom,crlf,emoji']);

      final readBack = await repository.read(created.metadata.id);
      expect(readBack.source, source);
      expect(utf8.encode(readBack.source), orderedEquals(sourceBytes));

      final db = await store.database;
      final raw = await db.rawQuery(
        'SELECT CAST(content AS BLOB) AS content_bytes FROM notes WHERE id = ?',
        [created.metadata.id],
      );
      expect(raw, hasLength(1));
      final physicalBytes = raw.single['content_bytes'];
      expect(physicalBytes, isA<Uint8List>());
      expect(physicalBytes as Uint8List, orderedEquals(sourceBytes));
    },
  );

  test(
    'oversized legacy HTML is rejected without overwriting original SQLite fields',
    () async {
      const limit = 5 * 1024 * 1024;
      final baseline = await repository.create(edit('Original record'));
      final oversized = ''.padRight(limit + 1, 'x');
      final db = await store.database;
      await db.update(
        'notes',
        {'content': oversized},
        where: 'id = ? AND collection = ?',
        whereArgs: [baseline.metadata.id, 'note'],
      );
      final before = await db.rawQuery(
        'SELECT CAST(content AS BLOB) AS content_bytes FROM notes WHERE id = ?',
        [baseline.metadata.id],
      );
      final beforeBytes = before.single['content_bytes'] as Uint8List;

      await expectLater(
        repository.save(
          baseline,
          edit('Must not overwrite', source: '<p>safe update</p>'),
        ),
        throwsA(isA<FormatException>()),
      );

      final after = await db.rawQuery(
        'SELECT title, labels, updated_at, CAST(content AS BLOB) AS content_bytes '
        'FROM notes WHERE id = ?',
        [baseline.metadata.id],
      );
      expect(after, hasLength(1));
      expect(after.single['title'], 'Original record');
      expect(after.single['labels'], jsonEncode(baseline.labels));
      expect(after.single['updated_at'], baseline.metadata.version);
      expect(
        after.single['content_bytes'] as Uint8List,
        orderedEquals(beforeBytes),
      );
    },
  );
}
