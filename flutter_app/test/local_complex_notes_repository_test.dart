import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/local_complex_notes_repository.dart';
import 'package:bookstark_flutter/core/local_store.dart';
import 'package:bookstark_flutter/core/spreadsheet_document.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/open.dart';

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
  final repositories = <LocalComplexNotesRepository>[];

  LocalComplexNotesRepository repo(
    ComplexEditorKind kind, {
    String collection = 'note',
  }) {
    final value = LocalComplexNotesRepository(
      store,
      kind: kind,
      collection: collection,
    );
    repositories.add(value);
    return value;
  }

  Future<ComplexNote> create(
    ComplexEditorKind kind,
    String source, {
    String title = '标题',
    List<String> labels = const ['标签📚', 'unknown,label'],
    String collection = 'note',
  }) async {
    final id = await store.createNote(
      title,
      source,
      labels: labels,
      collection: collection,
    );
    await (await store.database).update(
      'notes',
      {'editor_type': kind.name},
      where: 'id = ?',
      whereArgs: [id],
    );
    return repo(kind, collection: collection).read(id);
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('complex-notes-');
    store = LocalStore(
      path: '${directory.path}/notes.db',
      factory: databaseFactoryFfiNoIsolate,
    );
    repositories.clear();
  });

  tearDown(() async {
    for (final repository in repositories) {
      repository.dispose();
    }
    await store.close();
    await directory.delete(recursive: true);
  });

  test(
    'Markdown WebView repository rejects ordinary notes before opening SQL',
    () {
      expect(() => repo(ComplexEditorKind.markdown), throwsArgumentError);
    },
  );

  test(
    'seven explicit WebView kinds read and no-op save exact Unicode source and unknown fields',
    () async {
      final samples = _validSources();
      for (final kind in ComplexEditorKind.values) {
        final source = samples[kind]!;
        final collection = kind == ComplexEditorKind.markdown
            ? 'article'
            : 'note';
        final note = await create(
          kind,
          source,
          title: '文档-${kind.name}',
          collection: collection,
        );
        expect(note.document.kind, kind);
        expect(note.document.source, source);
        expect(note.labels, ['标签📚', 'unknown,label']);
        final saved = await repo(kind, collection: collection).save(
          note,
          ComplexNoteEdit(
            title: note.title,
            document: note.document,
            labels: note.labels,
          ),
        );
        expect(saved.document.source, source);
        expect(saved.document.digest, note.document.digest);
        expect(saved.version, note.version);
        final row = (await (await store.database).query(
          'notes',
          where: 'id = ?',
          whereArgs: [note.id],
        )).single;
        expect(row['editor_type'], kind.name);
        expect(
          await _rawContentBytes(await store.database, note.id),
          utf8.encode(source),
        );
      }
    },
  );

  test(
    'no-op preserves updated_at while a changed save advances version',
    () async {
      final source = _validSources()[ComplexEditorKind.html]!;
      final note = await create(ComplexEditorKind.html, source);
      final html = repo(ComplexEditorKind.html);
      final noop = await html.save(
        note,
        ComplexNoteEdit(
          title: note.title,
          document: note.document,
          labels: note.labels,
        ),
      );
      expect(noop.version, note.version);
      expect(noop.document.source, source);
      expect(
        await _rawContentBytes(await store.database, note.id),
        utf8.encode(source),
      );

      const changedSource = '\ufeff<!doctype html>\r\n<p>新内容😀</p>\r\n';
      final changed = await html.save(
        note,
        ComplexNoteEdit(
          title: '更改标题',
          document: ComplexEditorDocument.parse(
            ComplexEditorKind.html,
            changedSource,
          ),
          labels: const ['新标签'],
        ),
      );
      expect(changed.version, greaterThan(note.version));
      expect(changed.title, '更改标题');
      expect(changed.document.source, changedSource);
      expect(
        await _rawContentBytes(await store.database, note.id),
        utf8.encode(changedSource),
      );
    },
  );

  test(
    'stale version conflicts and does not overwrite the newer source or metadata',
    () async {
      final note = await create(
        ComplexEditorKind.html,
        _validSources()[ComplexEditorKind.html]!,
      );
      final html = repo(ComplexEditorKind.html);
      final newer = await html.save(
        note,
        ComplexNoteEdit(
          title: '新版本',
          document: ComplexEditorDocument.parse(
            ComplexEditorKind.html,
            '<main>更新</main>',
          ),
          labels: const ['new'],
        ),
      );

      ComplexNoteConflict? conflict;
      try {
        await html.save(
          note,
          ComplexNoteEdit(
            title: '陈旧写入',
            document: ComplexEditorDocument.parse(
              ComplexEditorKind.html,
              '<p>stale</p>',
            ),
            labels: const ['stale'],
          ),
        );
        fail('expected a stale baseline conflict');
      } on ComplexNoteConflict catch (error) {
        conflict = error;
      }
      expect(conflict.actual.same(newer), isTrue);
      expect((await html.read(note.id)).same(newer), isTrue);
    },
  );

  test(
    'same-version content, title, or labels changes still fail full-baseline comparison',
    () async {
      final source = _validSources()[ComplexEditorKind.html]!;
      final replacement = '<!doctype html><p>另一个正文</p>';
      for (final changedField in <String>['content', 'title', 'labels']) {
        final baseline = await create(ComplexEditorKind.html, source);
        final db = await store.database;
        final values = <String, Object?>{
          'content': replacement,
          'title': '数据库里的标题',
          'labels': jsonEncode(['database']),
        };
        await db.update(
          'notes',
          {changedField: values[changedField]},
          where: 'id = ?',
          whereArgs: [baseline.id],
        );
        final before = (await db.query(
          'notes',
          where: 'id = ?',
          whereArgs: [baseline.id],
        )).single;

        await expectLater(
          repo(ComplexEditorKind.html).save(
            baseline,
            ComplexNoteEdit(
              title: '绝不覆盖',
              document: ComplexEditorDocument.parse(
                ComplexEditorKind.html,
                '<p>overwrite attempt</p>',
              ),
              labels: const ['overwrite'],
            ),
          ),
          throwsA(isA<ComplexNoteConflict>()),
        );
        expect(
          (await db.query(
            'notes',
            where: 'id = ?',
            whereArgs: [baseline.id],
          )).single,
          before,
        );
        expect(before['updated_at'], baseline.version);
      }
    },
  );

  test(
    'soft deletion, editor type change, and collection change block writes',
    () async {
      final source = _validSources()[ComplexEditorKind.html]!;
      final html = repo(ComplexEditorKind.html);
      final db = await store.database;
      for (final change in <String>['deleted', 'editor_type', 'collection']) {
        final baseline = await create(ComplexEditorKind.html, source);
        final update = switch (change) {
          'deleted' => {'deleted': 1},
          'editor_type' => {'editor_type': 'markdown'},
          _ => {'collection': 'article'},
        };
        await db.update(
          'notes',
          update,
          where: 'id = ?',
          whereArgs: [baseline.id],
        );
        await expectLater(
          html.save(
            baseline,
            ComplexNoteEdit(
              title: '不可写入',
              document: ComplexEditorDocument.parse(
                ComplexEditorKind.html,
                '<p>侵入</p>',
              ),
              labels: const ['wrong'],
            ),
          ),
          throwsStateError,
        );
        final row = (await db.query(
          'notes',
          where: 'id = ?',
          whereArgs: [baseline.id],
        )).single;
        expect(await _rawContentBytes(db, baseline.id), utf8.encode(source));
        expect(row['title'], baseline.title);
        expect(row['labels'], jsonEncode(baseline.labels));
      }
    },
  );

  test(
    'foreign scope, kind, and collection baselines are rejected before any write',
    () async {
      final html = await create(
        ComplexEditorKind.html,
        _validSources()[ComplexEditorKind.html]!,
      );
      final db = await store.database;
      final source = html.document.source;
      final forgedScope = ComplexNote(
        scope: 'other-database-scope',
        id: html.id,
        collection: html.collection,
        title: html.title,
        document: html.document,
        version: html.version,
        labels: html.labels,
      );
      final edit = ComplexNoteEdit(
        title: 'must not change',
        document: ComplexEditorDocument.parse(
          ComplexEditorKind.html,
          '<p>bad</p>',
        ),
        labels: const ['bad'],
      );
      await expectLater(
        repo(ComplexEditorKind.html).save(forgedScope, edit),
        throwsStateError,
      );

      final drawingSource = _validSources()[ComplexEditorKind.drawing]!;
      final drawing = await create(ComplexEditorKind.drawing, drawingSource);
      await expectLater(
        repo(ComplexEditorKind.html).save(drawing, edit),
        throwsStateError,
      );

      final articleRepo = repo(ComplexEditorKind.html, collection: 'article');
      await expectLater(articleRepo.save(html, edit), throwsStateError);
      expect(await _rawContentBytes(db, html.id), utf8.encode(source));
    },
  );

  test(
    'source, title and labels save together without touching other notes, tables or attachments',
    () async {
      final source = _validSources()[ComplexEditorKind.html]!;
      final target = await create(
        ComplexEditorKind.html,
        source,
        title: 'target',
      );
      final unrelated = await store.createNote('markdown peer', '# keep me');
      final otherHtml = await create(
        ComplexEditorKind.html,
        '<p>other HTML</p>',
        title: 'other',
      );
      final db = await store.database;
      await db.insert('local_images', {
        'attachment_id': 'att-fixture',
        'file_name': 'fixture.png',
        'mime_type': 'image/png',
        'file_size': 3,
        'modify_time': '2026-11-06T00:00:00Z',
      });
      final nodeId = await db.insert('local_drive_nodes', {
        'path': '/fixtures/picture.png',
        'parent_path': '/fixtures',
        'name': 'picture.png',
        'directory': 0,
        'file_size': 3,
        'mime_type': 'image/png',
        'blob_key': 'blob-fixture',
        'create_time': '2026-11-06T00:00:00Z',
        'modify_time': '2026-11-06T00:00:00Z',
      });
      await db.insert('html_preview_resources', {
        'note_id': target.id,
        'resource_path': '/picture.png',
        'node_id': nodeId,
        'approved_hash': 'a' * 64,
      });
      final beforeImages = await db.query('local_images');
      final beforeNodes = await db.query('local_drive_nodes');
      final beforeResources = await db.query('html_preview_resources');
      final beforeOtherNotes = (await db.query(
        'notes',
        where: 'id != ?',
        whereArgs: [target.id],
      )).toList();

      const exactSource =
          '\ufeff<!doctype html>\r\n<h1>保存📖</h1><!-- exact -->\n';
      final saved = await repo(ComplexEditorKind.html).save(
        target,
        ComplexNoteEdit(
          title: 'target updated',
          document: ComplexEditorDocument.parse(
            ComplexEditorKind.html,
            exactSource,
          ),
          labels: const ['新,标签', '保留 🧩'],
        ),
      );
      expect(saved.document.source, exactSource);
      expect(saved.title, 'target updated');
      expect(saved.labels, ['新,标签', '保留 🧩']);
      final targetRow = (await db.query(
        'notes',
        where: 'id = ?',
        whereArgs: [target.id],
      )).single;
      expect(await _rawContentBytes(db, target.id), utf8.encode(exactSource));
      expect(targetRow['title'], 'target updated');
      expect(targetRow['labels'], jsonEncode(['新,标签', '保留 🧩']));
      expect(targetRow['editor_type'], 'html');

      final afterOtherNotes = (await db.query(
        'notes',
        where: 'id != ?',
        whereArgs: [target.id],
      )).toList();
      expect(afterOtherNotes, beforeOtherNotes);
      expect(
        (await db.query(
          'notes',
          where: 'id = ?',
          whereArgs: [unrelated],
        )).single['content'],
        '# keep me',
      );
      expect(
        (await db.query(
          'notes',
          where: 'id = ?',
          whereArgs: [otherHtml.id],
        )).single['content'],
        '<p>other HTML</p>',
      );
      expect(await db.query('local_images'), beforeImages);
      expect(await db.query('local_drive_nodes'), beforeNodes);
      expect(await db.query('html_preview_resources'), beforeResources);
    },
  );

  test(
    'near-limit presentation reads and saves in chunks, preserves bytes, and rejects oversize input',
    () async {
      const maximum = 20 * 1024 * 1024;
      const prefix =
          '{"width":1280,"height":720,"slides":[{"id":"slide-1","elements":[]}],"futurePadding":"';
      const suffix = '"}';
      const targetLength = maximum - 256;
      final paddingLength = targetLength - prefix.length - suffix.length;
      final source = '$prefix${'x' * paddingLength}$suffix';
      final sourceBytes = utf8.encode(source);
      expect(sourceBytes, hasLength(targetLength));

      final baseline = await create(
        ComplexEditorKind.presentation,
        source,
        title: 'large presentation',
      );
      expect(baseline.document.source, source);
      final presentation = repo(ComplexEditorKind.presentation);
      final noOp = await presentation.save(
        baseline,
        ComplexNoteEdit(
          title: baseline.title,
          document: baseline.document,
          labels: baseline.labels,
        ),
      );
      expect(noOp.version, baseline.version);
      expect(noOp.document.source, source);
      expect(
        await _rawContentBytes(await store.database, baseline.id),
        sourceBytes,
      );

      final saved = await presentation.save(
        baseline,
        ComplexNoteEdit(
          title: 'large presentation saved',
          document: baseline.document,
          labels: const ['大文件', '未知字段保留'],
        ),
      );
      expect(saved.version, greaterThan(baseline.version));
      expect(saved.document.source, source);
      expect(saved.title, 'large presentation saved');
      expect(
        await _rawContentBytes(await store.database, baseline.id),
        sourceBytes,
      );

      final db = await store.database;
      await db.execute(
        'CREATE TABLE complex_update_probe (id INTEGER NOT NULL)',
      );
      await db.execute(
        'CREATE TRIGGER probe_complex_update AFTER UPDATE ON notes '
        'BEGIN INSERT INTO complex_update_probe(id) VALUES (NEW.id); END',
      );
      final overLimit =
          '$prefix${'x' * (maximum + 1 - prefix.length - suffix.length)}$suffix';
      await expectLater(() async {
        final invalid = ComplexEditorDocument.parse(
          ComplexEditorKind.presentation,
          overLimit,
        );
        await presentation.save(
          saved,
          ComplexNoteEdit(
            title: 'must not persist',
            document: invalid,
            labels: const ['invalid'],
          ),
        );
      }, throwsFormatException);
      expect(await db.query('complex_update_probe'), isEmpty);
      expect(await _rawContentBytes(db, baseline.id), sourceBytes);
      final row = (await db.query(
        'notes',
        where: 'id = ?',
        whereArgs: [baseline.id],
      )).single;
      expect(row['title'], 'large presentation saved');
      expect(row['labels'], jsonEncode(['大文件', '未知字段保留']));
      expect(row['updated_at'], saved.version);
    },
  );

  test(
    'article title uniqueness rolls back content and labels as one failed save',
    () async {
      final source = _validSources()[ComplexEditorKind.html]!;
      final target = await create(
        ComplexEditorKind.html,
        source,
        title: 'article-before',
        collection: 'article',
      );
      await create(
        ComplexEditorKind.html,
        '<p>competitor</p>',
        title: 'already-used',
        collection: 'article',
      );
      final db = await store.database;
      final before = (await db.query(
        'notes',
        where: 'id = ?',
        whereArgs: [target.id],
      )).single;
      await expectLater(
        repo(ComplexEditorKind.html, collection: 'article').save(
          target,
          ComplexNoteEdit(
            title: 'already-used',
            document: ComplexEditorDocument.parse(
              ComplexEditorKind.html,
              '<p>should rollback</p>',
            ),
            labels: const ['changed'],
          ),
        ),
        throwsA(isA<DatabaseException>()),
      );
      expect(
        (await db.query(
          'notes',
          where: 'id = ?',
          whereArgs: [target.id],
        )).single,
        before,
      );
    },
  );

  test(
    'invalid edit is rejected before SQL and disposed repositories reject reads and writes',
    () async {
      final note = await create(
        ComplexEditorKind.html,
        _validSources()[ComplexEditorKind.html]!,
      );
      final html = repo(ComplexEditorKind.html);
      final db = await store.database;
      await db.execute(
        "CREATE TRIGGER fail_complex_update BEFORE UPDATE ON notes BEGIN SELECT RAISE(ABORT, 'SQL must not run for invalid edit'); END",
      );
      await expectLater(
        html.save(
          note,
          ComplexNoteEdit(
            title: String.fromCharCode(0xd800),
            document: note.document,
            labels: note.labels,
          ),
        ),
        throwsFormatException,
      );
      expect(
        (await db.query(
          'notes',
          where: 'id = ?',
          whereArgs: [note.id],
        )).single['title'],
        note.title,
      );
      await db.execute('DROP TRIGGER fail_complex_update');

      html.dispose();
      await expectLater(html.read(note.id), throwsStateError);
      await expectLater(
        html.save(
          note,
          ComplexNoteEdit(
            title: 'no write',
            document: note.document,
            labels: note.labels,
          ),
        ),
        throwsStateError,
      );
      expect(
        (await db.query(
          'notes',
          where: 'id = ?',
          whereArgs: [note.id],
        )).single['title'],
        note.title,
      );
    },
  );
}

Map<ComplexEditorKind, String> _validSources() {
  final workbook =
      jsonDecode(
            SpreadsheetDocument.empty(
              workbookId: 'workbook-1',
              sheetId: 'sheet-1',
            ).source,
          )
          as Map<String, Object?>;
  workbook['unknownFutureField'] = {'title': '未知字段', 'keep': true};

  return {
    ComplexEditorKind.markdown: '\ufeff# 本地文章\r\n\r\n- **原文😀**\r\n',
    ComplexEditorKind.html: '\ufeff<!doctype html>\r\n<p>原文😀</p>\r\n',
    ComplexEditorKind.spreadsheet: jsonEncode(workbook),
    ComplexEditorKind.drawing: jsonEncode({
      'elements': <Object?>[],
      'appState': <String, Object?>{'zoom': 1},
      'future': '保留绘图字段',
    }),
    ComplexEditorKind.mindmap: jsonEncode({
      'nodeData': {'id': 'root-1', 'topic': '思维导图📚', 'children': <Object?>[]},
      'future': {'retain': true},
    }),
    ComplexEditorKind.richdoc: jsonEncode({
      'schema': 'bookstark-richdoc',
      'schema_version': 1,
      'data': {
        'main': [
          {'value': '富文本😀'},
        ],
      },
      'future': ['retain', '未知'],
    }),
    ComplexEditorKind.presentation: jsonEncode({
      'width': 1280,
      'height': 720,
      'slides': [
        {'id': 'slide-1', 'elements': <Object?>[]},
      ],
      'future': {'keep': '演示稿'},
    }),
  };
}

Future<List<int>> _rawContentBytes(DatabaseExecutor db, int id) async {
  final rows = await db.rawQuery(
    'SELECT CAST(content AS BLOB) AS body FROM notes WHERE id = ?',
    [id],
  );
  return (rows.single['body'] as List).cast<int>();
}
