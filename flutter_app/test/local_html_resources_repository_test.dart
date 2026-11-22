import 'dart:ffi' show DynamicLibrary;
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:file_selector/file_selector.dart';
import 'package:sqlite3/open.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:bookstark_flutter/core/local_store.dart';
import 'package:bookstark_flutter/core/local_drive_repository.dart';
import 'package:bookstark_flutter/core/drive_models.dart';
import 'package:bookstark_flutter/core/drive_source.dart';
import 'package:bookstark_flutter/core/html_notes_repository.dart';
import 'package:bookstark_flutter/core/local_html_notes_repository.dart';
import 'package:bookstark_flutter/core/local_html_resources_repository.dart';
import 'package:bookstark_flutter/core/local_trash_repository.dart';
import 'package:bookstark_flutter/core/trash_repository.dart';

void main() {
  sqfliteFfiInit();
  if (Platform.isLinux) {
    open.overrideFor(
      OperatingSystem.linux,
      () => DynamicLibrary.open('libsqlite3.so.0'),
    );
  }
  late Directory space;
  late LocalStore store;
  late LocalDriveRepository drive;
  late LocalHtmlNotesRepository notes;
  late LocalHtmlResourcesRepository resources;
  late int id;
  var sequence = 0;
  const source =
      '<!doctype html>\r\n<html><link rel="stylesheet" href="theme.css"><p>原文</p></html>\n';
  setUp(() async {
    final base = Directory(
      Platform.environment['BOOKSTARK_APK_TEST_ROOT'] ??
          Directory.systemTemp.path,
    );
    await base.create(recursive: true);
    space = await base.createTemp('html-resources-');
    store = LocalStore(
      path: '${space.path}/data.db',
      factory: databaseFactoryFfiNoIsolate,
    );
    drive = LocalDriveRepository(store, Directory('${space.path}/drive-blobs'));
    notes = LocalHtmlNotesRepository(store);
    resources = LocalHtmlResourcesRepository(store, drive, collection: 'note');
    id = (await notes.create(
      HtmlNoteEdit(title: 'Local HTML', source: source, labels: ['original']),
    )).metadata.id;
    sequence = 0;
  });
  tearDown(() async {
    notes.dispose();
    drive.dispose();
    await store.close();
    await space.delete(recursive: true);
  });
  Future<DriveNode> upload(
    String target,
    String body, {
    DriveNode? expected,
  }) async {
    final file = File('${space.path}/input-${sequence++}.css');
    await file.writeAsString(body, flush: true);
    return (await drive.upload(
      await DriveSourceSnapshot.prepare(
        XFile(file.path),
        maxBytes: 5 * 1024 * 1024,
      ),
      target: target,
      expected: expected,
    )).node;
  }

  test(
    'binding loads exact approved bytes without changing note rows or drive metadata',
    () async {
      final node = await upload('theme.css', 'body{color:blue}\r\n');
      final db = await store.database;
      final beforeNote = await db.query('notes');
      final beforeDrive = await db.query('local_drive_nodes');
      final bindings = await resources.replace(id, [
        HtmlResourceChoice(path: 'theme.css', node: node),
      ], baseline: []);
      final document = await resources.load(id, source);
      expect(document.source, source);
      expect(
        String.fromCharCodes(document.resources.single.bytes),
        'body{color:blue}\r\n',
      );
      expect(document.resources.single.path, 'theme.css');
      expect(bindings.single.nodeId, node.id);
      expect(await db.query('notes'), beforeNote);
      expect(await db.query('local_drive_nodes'), beforeDrive);
      await store.close();
      expect(
        (await resources.load(id, source)).fingerprint,
        document.fingerprint,
      );
    },
  );
  test(
    'changed file needs explicit approval and does not execute replacement bytes automatically',
    () async {
      final first = await upload('theme.css', 'body{color:blue}');
      final baseline = await resources.replace(id, [
        HtmlResourceChoice(path: 'theme.css', node: first),
      ], baseline: []);
      final next = await upload(
        'theme.css',
        'body{color:red}',
        expected: first,
      );
      expect((await resources.list(id)).single.changed, isTrue);
      await expectLater(
        resources.load(id, source),
        throwsA(isA<HtmlResourceUnavailable>()),
      );
      await resources.replace(id, [
        HtmlResourceChoice(path: 'theme.css', node: next),
      ], baseline: baseline);
      expect(
        String.fromCharCodes(
          (await resources.load(id, source)).resources.single.bytes,
        ),
        'body{color:red}',
      );
    },
  );
  test(
    'stale selection baseline cannot erase another resource binding',
    () async {
      final first = await upload('first.css', 'a{}'),
          second = await upload('second.css', 'b{}');
      await resources.replace(id, [
        HtmlResourceChoice(path: 'first.css', node: first),
      ], baseline: []);
      await expectLater(
        resources.replace(id, [
          HtmlResourceChoice(path: 'second.css', node: second),
        ], baseline: []),
        throwsA(isA<HtmlResourceConflict>()),
      );
      expect((await resources.list(id)).single.binding.path, 'first.css');
    },
  );
  test(
    'deleted and recreated drive path does not acquire an old resource approval',
    () async {
      final first = await upload('theme.css', 'a{}');
      await resources.replace(id, [
        HtmlResourceChoice(path: 'theme.css', node: first),
      ], baseline: []);
      await drive.remove(first);
      final next = await upload('theme.css', 'b{}');
      expect(next.id, isNot(first.id));
      expect((await resources.list(id)).single.node, isNull);
      await expectLater(
        resources.load(id, source),
        throwsA(isA<HtmlResourceUnavailable>()),
      );
    },
  );
  test(
    'trash restore keeps approved resources; permanent delete removes bindings but preserves original file and creation receipt',
    () async {
      final node = await upload('theme.css', 'a{}');
      await resources.replace(id, [
        HtmlResourceChoice(path: 'theme.css', node: node),
      ], baseline: []);
      final db = await store.database;
      final trash = LocalTrashRepository(store);
      await db.update('notes', {'deleted': 1}, where: 'id=?', whereArgs: [id]);
      await expectLater(resources.load(id, source), throwsFormatException);
      await trash.apply(
        (await trash.read()).entries.single,
        TrashOperation.restore,
      );
      expect((await resources.load(id, source)).resources.length, 1);
      await db.update('notes', {'deleted': 1}, where: 'id=?', whereArgs: [id]);
      await trash.apply(
        (await trash.read()).entries.single,
        TrashOperation.delete,
      );
      expect(await db.query('html_preview_resources'), isEmpty);
      expect(await db.query('html_creation_receipts'), hasLength(1));
      expect(await drive.bytes(node), isNotEmpty);
      trash.dispose();
    },
  );
  test(
    'v13 upgrade creates empty resource table and delete trigger while preserving original HTML and ledger',
    () async {
      var db = await store.database;
      final before = await db.query('notes');
      final receipts = await db.query('html_creation_receipts');
      await db.execute('DROP TRIGGER html_preview_resources_note_delete');
      await db.execute('DROP TABLE html_preview_resources');
      await db.execute('DROP TABLE assistant_creation_receipts');
      await db.setVersion(13);
      await store.close();
      db = await store.database;
      expect(await db.getVersion(), 16);
      expect(await db.query('notes'), before);
      expect(await db.query('html_creation_receipts'), receipts);
      expect(await db.query('html_preview_resources'), isEmpty);
      expect(
        await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='trigger' AND name='html_preview_resources_note_delete'",
        ),
        hasLength(1),
      );
      expect((await notes.read(id)).source, source);
    },
  );
  test(
    'wrong collection, Markdown ownership and duplicate paths create no bindings',
    () async {
      final node = await upload('theme.css', 'a{}');
      final wrong = LocalHtmlResourcesRepository(
        store,
        drive,
        collection: 'article',
      );
      await expectLater(
        wrong.replace(id, [
          HtmlResourceChoice(path: 'theme.css', node: node),
        ], baseline: []),
        throwsFormatException,
      );
      final md = await store.createNote('Markdown', '# original');
      await expectLater(
        resources.replace(md, [
          HtmlResourceChoice(path: 'theme.css', node: node),
        ], baseline: []),
        throwsFormatException,
      );
      await expectLater(
        resources.replace(id, [
          HtmlResourceChoice(path: 'theme.css', node: node),
          HtmlResourceChoice(path: 'theme.css', node: node),
        ], baseline: []),
        throwsFormatException,
      );
      expect(
        await (await store.database).query('html_preview_resources'),
        isEmpty,
      );
    },
  );
}
