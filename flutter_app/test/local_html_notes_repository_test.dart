import 'dart:ffi';
import 'dart:io';
import 'package:sqlite3/open.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/local_store.dart';
import 'package:bookstark_flutter/core/local_html_notes_repository.dart';
import 'package:bookstark_flutter/core/html_notes_repository.dart';
import 'package:bookstark_flutter/core/notes_repository.dart';
import 'package:bookstark_flutter/core/local_trash_repository.dart';
import 'package:bookstark_flutter/core/trash_repository.dart';
import 'package:bookstark_flutter/core/html_creation_vault.dart';

void main() {
  late Directory directory;
  late LocalStore store;
  late LocalHtmlNotesRepository repo;
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
    ).createTemp('local-html-');
    store = LocalStore(
      path: '${directory.path}/notes.db',
      factory: databaseFactoryFfiNoIsolate,
    );
    repo = LocalHtmlNotesRepository(store);
  });
  tearDown(() async {
    repo.dispose();
    await store.close();
    await directory.delete(recursive: true);
  });
  HtmlNoteEdit edit(
    String title, {
    String source = '<!doctype html>\r\n<p>你好</p>\n<!-- 🧪 -->\r',
    List<String> labels = const ['one,literal,label'],
  }) => HtmlNoteEdit(title: title, source: source, labels: labels);

  test(
    'same creation key observes same original ID without a second insert or revision change',
    () async {
      final key = newHtmlCreationKey(), draft = edit('Created once');
      final first = await repo.createOnce(draft, creationKey: key);
      final second = await repo.createOnce(draft, creationKey: key);
      expect(first.inserted, true);
      expect(second.inserted, false);
      expect(second.note.metadata.id, first.note.metadata.id);
      expect(second.note.metadata.version, first.note.metadata.version);
      expect((await repo.findCreation(key))!.source, draft.source);
      final db = await store.database;
      expect((await db.query('notes')).length, 1);
      expect((await db.query('html_creation_receipts')).length, 1);
      await expectLater(
        repo.createOnce(edit('Different input'), creationKey: key),
        throwsStateError,
      );
    },
  );
  test(
    'failed creation receipt insertion rolls back the note and retry with same key creates once',
    () async {
      final db = await store.database, key = newHtmlCreationKey();
      await db.execute(
        "CREATE TRIGGER fail_html_receipt BEFORE INSERT ON html_creation_receipts BEGIN SELECT RAISE(ABORT, 'injected'); END",
      );
      await expectLater(
        repo.createOnce(edit('Atomic create'), creationKey: key),
        throwsA(isA<DatabaseException>()),
      );
      expect(await db.query('notes'), isEmpty);
      expect(await db.query('html_creation_receipts'), isEmpty);
      expect(await db.query('html_preview_resources'), isEmpty);
      await db.execute('DROP TRIGGER fail_html_receipt');
      final result = await repo.createOnce(
        edit('Atomic create'),
        creationKey: key,
      );
      expect(result.inserted, true);
      expect((await db.query('notes')).length, 1);
    },
  );
  test(
    'permanent deletion cannot turn an old uncertain create into a new note',
    () async {
      final key = newHtmlCreationKey();
      final original = (await repo.createOnce(
        edit('Deleted creation'),
        creationKey: key,
      )).note;
      await store.deleteNote(original.metadata.id);
      final trash = LocalTrashRepository(store);
      final entry = (await trash.read()).entries.single;
      await trash.apply(entry, TrashOperation.delete);
      await expectLater(
        repo.findCreation(key),
        throwsA(isA<HtmlCreationTargetUnavailable>()),
      );
      await expectLater(
        repo.createOnce(edit('Deleted creation'), creationKey: key),
        throwsA(isA<HtmlCreationTargetUnavailable>()),
      );
      expect(await (await store.database).query('notes'), isEmpty);
      trash.dispose();
    },
  );
  test(
    'read-only creation lookup exposes later edits and idempotent retry never overwrites them',
    () async {
      final key = newHtmlCreationKey(), draft = edit('Initially created');
      final created = (await repo.createOnce(draft, creationKey: key)).note;
      final changed = (await repo.save(
        created,
        edit('Changed elsewhere', source: 'new body'),
      )).note;
      await expectLater(
        repo.createOnce(draft, creationKey: key),
        throwsA(isA<HtmlNoteConflict>()),
      );
      final observed = (await repo.findCreation(key))!;
      expect(observed.source, 'new body');
      expect(observed.metadata.version, changed.metadata.version);
    },
  );
  test(
    'v12 upgrade adds empty creation/resource tables and keeps existing HTML bytes and type',
    () async {
      final html = await repo.create(edit('Existing v12 HTML'));
      var db = await store.database;
      await db.execute('DROP TRIGGER html_preview_resources_note_delete');
      await db.execute('DROP TABLE html_preview_resources');
      await db.execute('DROP TABLE html_creation_receipts');
      await db.execute('DROP TABLE assistant_creation_receipts');
      await db.setVersion(12);
      final before = await db.query('notes');
      await store.close();
      db = await store.database;
      expect(await db.getVersion(), 16);
      expect(await db.query('notes'), before);
      expect(await db.query('html_creation_receipts'), isEmpty);
      expect((await repo.read(html.metadata.id)).source, html.source);
      expect((await store.readNote(html.metadata.id))['editor_type'], 'html');
    },
  );
  test(
    'local HTML create/update commits exact source and JSON labels with monotonic revision',
    () async {
      final created = await repo.create(edit('Local HTML'));
      final saved = await repo.save(
        created,
        edit(
          'Changed',
          source: '${created.source}<script>1</script>',
          labels: ['changed,one,label'],
        ),
      );
      expect(saved.note.metadata.id, created.metadata.id);
      expect(saved.note.source, '${created.source}<script>1</script>');
      expect(saved.note.labels, ['changed,one,label']);
      expect(
        saved.note.metadata.version,
        greaterThan(created.metadata.version),
      );
      expect(saved.allReceiptsKnown, true);
      final db = await store.database;
      expect((await db.query('notes')).single['editor_type'], 'html');
      await store.close();
      expect((await repo.read(created.metadata.id)).source, saved.note.source);
    },
  );
  test('Markdown read/save cannot reinterpret or overwrite HTML', () async {
    final html = await repo.create(edit('Owned HTML'));
    final markdown = LocalNotesRepository(store);
    await expectLater(
      markdown.read(html.metadata.id),
      throwsA(isA<DedicatedEditorRequired>()),
    );
    await expectLater(
      markdown.save(
        Note(id: html.metadata.id, title: 'Wrong editor', content: '# damage'),
      ),
      throwsA(isA<DedicatedEditorRequired>()),
    );
    expect((await repo.read(html.metadata.id)).source, html.source);
    final md = await markdown.save(
      const Note(title: 'Markdown', content: '# Original'),
    );
    await expectLater(repo.read(md), throwsStateError);
    expect((await markdown.read(md)).content, '# Original');
  });
  test(
    'conflict and cross-collection writes preserve newer HTML and labels',
    () async {
      final original = await repo.create(edit('Original'));
      final newer = await repo.save(
        original,
        edit('Newer', labels: ['new,label']),
      );
      await expectLater(
        repo.save(original, edit('Stale')),
        throwsA(isA<HtmlNoteConflict>()),
      );
      final article = LocalHtmlNotesRepository(store, collection: 'article');
      await expectLater(
        article.save(newer.note, edit('Wrong collection')),
        throwsStateError,
      );
      expect((await repo.read(original.metadata.id)).metadata.title, 'Newer');
      expect((await repo.read(original.metadata.id)).labels, ['new,label']);
      article.dispose();
    },
  );
  test(
    'article title constraint rolls back content and labels together',
    () async {
      final article = LocalHtmlNotesRepository(store, collection: 'article');
      final first = await article.create(edit('First article'));
      await article.create(edit('Second article'));
      await expectLater(
        article.save(
          first,
          edit('Second article', source: 'changed', labels: ['changed,label']),
        ),
        throwsA(isA<DatabaseException>()),
      );
      final actual = await article.read(first.metadata.id);
      expect(actual.source, first.source);
      expect(actual.labels, first.labels);
      expect(actual.metadata.version, first.metadata.version);
      article.dispose();
    },
  );
  test(
    'soft-delete and explicit trash restore preserve HTML type and original ID',
    () async {
      final html = await repo.create(edit('Restore HTML'));
      await store.deleteNote(html.metadata.id);
      await expectLater(repo.read(html.metadata.id), throwsStateError);
      final trash = LocalTrashRepository(store);
      final page = await trash.read();
      final entry = page.entries.single;
      await trash.apply(entry, TrashOperation.restore);
      final restored = await repo.read(html.metadata.id);
      expect(restored.source, html.source);
      expect(restored.labels, html.labels);
      expect(restored.metadata.id, html.metadata.id);
      expect((await store.readNote(html.metadata.id))['editor_type'], 'html');
      trash.dispose();
    },
  );
  test(
    'v11 schema upgrade preserves every old note field and defaults Markdown',
    () async {
      final first = await store.createNote(
        'Old Markdown',
        '# text\r\n',
        labels: ['old,label'],
      );
      final deleted = await store.createNote(
        'Old deleted article',
        'body',
        collection: 'article',
      );
      await store.deleteNote(deleted, collection: 'article');
      var db = await store.database;
      await db.execute('DROP TRIGGER html_preview_resources_note_delete');
      await db.execute('DROP TABLE html_preview_resources');
      await db.execute('DROP TABLE html_creation_receipts');
      await db.execute('ALTER TABLE notes DROP COLUMN editor_type');
      await db.execute('DROP TABLE assistant_creation_receipts');
      await db.setVersion(11);
      final before = await db.query('notes', orderBy: 'id');
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT IN ('html_creation_receipts','html_preview_resources','assistant_creation_receipts') ORDER BY name",
      );
      await store.close();
      db = await store.database;
      expect(await db.getVersion(), 16);
      expect(
        await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name NOT IN ('html_creation_receipts','html_preview_resources','assistant_creation_receipts') ORDER BY name",
        ),
        tables,
      );
      final after = await db.query('notes', orderBy: 'id');
      expect(
        after
            .map((r) => Map<String, Object?>.from(r)..remove('editor_type'))
            .toList(),
        before,
      );
      expect(after.every((r) => r['editor_type'] == 'markdown'), true);
      expect(
        (await LocalNotesRepository(store).read(first)).content,
        '# text\r\n',
      );
      expect(after.singleWhere((r) => r['id'] == deleted)['deleted'], 1);
    },
  );
  test('disposed editors and invalid labels create no rows', () async {
    await expectLater(
      repo.create(edit('Invalid', labels: [''])),
      throwsFormatException,
    );
    repo.dispose();
    await expectLater(repo.create(edit('Closed')), throwsStateError);
    expect(await (await store.database).query('notes'), isEmpty);
  });
}
