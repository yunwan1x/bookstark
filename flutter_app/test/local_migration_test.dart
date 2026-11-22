import 'dart:io';
import 'dart:ffi';
import 'dart:convert';
import 'package:sqlite3/open.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:bookstark_flutter/core/local_store.dart';
import 'package:bookstark_flutter/core/notes_repository.dart';

void main() {
  test(
    'v1 database upgrades without losing text and labels survive reopen',
    () async {
      sqfliteFfiInit();
      if (Platform.isLinux) {
        open.overrideFor(
          OperatingSystem.linux,
          () => DynamicLibrary.open('libsqlite3.so.0'),
        );
      }
      final directory = await Directory.systemTemp.createTemp(
        'bookstark-migration-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = '${directory.path}/notes.db';
      final db = await databaseFactoryFfiNoIsolate.openDatabase(
        file,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, version) async {
            await db.execute(
              'CREATE TABLE notes (id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL, content TEXT NOT NULL, updated_at INTEGER NOT NULL, deleted INTEGER NOT NULL DEFAULT 0)',
            );
          },
        ),
      );
      final id = await db.insert('notes', {
        'title': '已有笔记',
        'content': '原始正文',
        'updated_at': 123,
      });
      await db.close();
      var store = LocalStore(path: file, factory: databaseFactoryFfiNoIsolate);
      var repository = LocalNotesRepository(store);
      var note = await repository.read(id);
      expect(note.content, '原始正文');
      expect(note.labels, isEmpty);
      await repository.save(note.copyWith(labels: ['中文标签']));
      await store.close();
      store = LocalStore(path: file, factory: databaseFactoryFfiNoIsolate);
      repository = LocalNotesRepository(store);
      note = await repository.read(id);
      expect(note.labels, ['中文标签']);
      expect(note.content, '原始正文');
      expect(jsonDecode((await store.readNote(id))['labels'] as String), [
        '中文标签',
      ]);
      await store.close();
    },
  );
}
