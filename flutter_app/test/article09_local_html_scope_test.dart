import 'package:bookstark_flutter/core/html_creation_vault.dart';
import 'dart:ffi';
import 'dart:io';
import 'package:sqlite3/open.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/local_store.dart';
import 'package:bookstark_flutter/core/local_html_notes_repository.dart';
import 'package:bookstark_flutter/core/html_notes_repository.dart';

void main() {
  late Directory directory;
  late LocalStore store;
  late LocalHtmlNotesRepository repo;
  var current = true;
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
    current = true;
    repo = LocalHtmlNotesRepository(
      store,
      collection: 'article',
      isCurrentScope: () => current,
    );
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
    'retired article HTML cannot update or create and retains source/receipt',
    () async {
      final original = await repo.createOnce(
        edit('Original'),
        creationKey: newHtmlCreationKey(),
      );
      final db = await store.database;
      final rows = await db.query('notes'),
          receipts = await db.query('html_creation_receipts');
      current = false;
      await expectLater(
        repo.save(original.note, edit('Unsaved')),
        throwsStateError,
      );
      await expectLater(
        repo.createOnce(edit('New'), creationKey: newHtmlCreationKey()),
        throwsStateError,
      );
      expect(await db.query('notes'), rows);
      expect(await db.query('html_creation_receipts'), receipts);
      current = true;
      expect(
        (await repo.read(original.note.metadata.id)).source,
        original.note.source,
      );
    },
  );
}
