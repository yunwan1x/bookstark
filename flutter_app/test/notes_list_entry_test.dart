import 'dart:ffi';
import 'dart:io';

import 'package:bookstark_flutter/core/local_store.dart';
import 'package:bookstark_flutter/core/notes_repository.dart';
import 'package:sqlite3/open.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'list entries bound previews while full list and reads retain source',
    () async {
      sqfliteFfiInit();
      if (Platform.isLinux) {
        open.overrideFor(
          OperatingSystem.linux,
          () => DynamicLibrary.open('libsqlite3.so.0'),
        );
      }
      final directory = await Directory.systemTemp.createTemp(
        'note-list-entry-',
      );
      final store = LocalStore(
        path: '${directory.path}/notes.db',
        factory: databaseFactoryFfiNoIsolate,
      );
      addTearDown(() async {
        await store.close();
        await directory.delete(recursive: true);
      });

      // 600,000 supplementary characters exceed 2 MiB in UTF-8 while keeping
      // rune slicing observably different from UTF-16 code-unit truncation.
      final source = '😀' * 600000;
      final id = await store.createNote('large', source, labels: ['bounded']);
      final repository = LocalNotesRepository(store);

      final entries = await repository.listEntries(label: 'bounded');
      expect(entries, hasLength(1));
      expect(entries.single.id, id);
      expect(entries.single.contentPreview, '😀' * 512);
      expect(entries.single.contentPreview.runes, hasLength(512));

      // The list/read compatibility contracts still return the exact full body.
      expect((await store.notes()).single['content'], source);
      expect((await repository.list()).single.content, source);
      expect((await repository.read(id)).content, source);
      expect((await store.readNote(id))['content'], source);
    },
  );
}
