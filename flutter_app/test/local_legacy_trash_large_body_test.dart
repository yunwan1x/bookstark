// Draft regressions for legacy negative-ID trash. NOT RUN.
// Uses bounded SQL BLOB chunks for byte assertions, never reads a giant TEXT row.
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/local_store.dart';
import 'package:bookstark_flutter/core/trash_repository.dart';
import 'package:sqlite3/open.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:bookstark_flutter/core/local_trash_repository.dart';

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
  Future<LocalStore> fixture() async {
    final root =
        Platform.environment['BOOKSTARK_APK_TEST_ROOT'] ??
        Directory.systemTemp.path;
    final dir = await Directory(root).createTemp('legacy-trash-large-');
    final store = LocalStore(
      path: '${dir.path}/data.db',
      factory: databaseFactoryFfiNoIsolate,
    );
    addTearDown(() async {
      await store.close();
      await dir.delete(recursive: true);
    });
    return store;
  }

  Future<int> insert(
    LocalStore store,
    String title,
    String source,
    String collection,
  ) async {
    final db = await store.database;
    return db.rawInsert(
      'INSERT INTO notes(title,content,updated_at,deleted,labels,collection,editor_type) '
      'VALUES(?,CAST(? AS TEXT),123456789,1,?,?,?)',
      [
        title,
        Uint8List.fromList(utf8.encode(source)),
        jsonEncode(['保留', 'comma,value']),
        collection,
        'markdown',
      ],
    );
  }

  Future<Map<String, Object?>> metadata(LocalStore store, int id) async =>
      (await (await store.database).query(
        'notes',
        columns: [
          'id',
          'title',
          'updated_at',
          'deleted',
          'labels',
          'collection',
          'editor_type',
        ],
        where: 'id=?',
        whereArgs: [id],
      )).single;
  Future<String> bodyHash(LocalStore store, int id) async {
    final db = await store.database;
    final size =
        (await db.rawQuery(
              'SELECT length(CAST(content AS BLOB)) AS n FROM notes WHERE id=?',
              [id],
            )).single['n']
            as int;
    final bytes = BytesBuilder(copy: false);
    for (var offset = 0; offset < size;) {
      final count = size - offset > 65536 ? 65536 : size - offset;
      final rows = await db.rawQuery(
        'SELECT substr(CAST(content AS BLOB),?,?) AS bytes FROM notes WHERE id=?',
        [offset + 1, count, id],
      );
      bytes.add(rows.single['bytes'] as Uint8List);
      offset += count;
    }
    return sha256.convert(bytes.takeBytes()).toString();
  }

  String largeSource() =>
      '\ufeff\ufeff${'a' * (262144 - 7)}🙂\r\n${'body\u0000\r\n' * 400000}';

  test(
    'restore large legacy note flips only deleted and preserves exact original body/metadata',
    () async {
      final store = await fixture(), source = largeSource();
      final id = await insert(store, 'legacy-large', source, 'note');
      final before = await metadata(store, id),
          hash = sha256.convert(utf8.encode(source)).toString();
      final trash = LocalTrashRepository(store);
      addTearDown(trash.dispose);
      final entry = (await trash.read(
        type: 'blog',
      )).entries.singleWhere((entry) => entry.id == -id);
      expect(entry.deletedAt, isEmpty);
      await trash.apply(entry, TrashOperation.restore);
      expect(await metadata(store, id), {...before, 'deleted': 0});
      expect(await bodyHash(store, id), hash);
      expect(await trash.isAbsent(entry), true);
      expect(await (await store.database).query('trash_entries'), isEmpty);
    },
  );

  test(
    'purge large legacy article removes target only, keeping another large row exact',
    () async {
      final store = await fixture(), source = largeSource();
      final keep = await insert(store, 'keep-large', source, 'note');
      final remove = await insert(
        store,
        'remove-large',
        '${source}article-tail',
        'article',
      );
      final before = await metadata(store, keep),
          hash = await bodyHash(store, keep);
      final trash = LocalTrashRepository(store);
      addTearDown(trash.dispose);
      final entry = (await trash.read(
        type: 'blog',
      )).entries.singleWhere((entry) => entry.id == -remove);
      await trash.apply(entry, TrashOperation.delete);
      expect(
        await (await store.database).query(
          'notes',
          columns: ['id'],
          where: 'id=?',
          whereArgs: [remove],
        ),
        isEmpty,
      );
      expect(await metadata(store, keep), before);
      expect(await bodyHash(store, keep), hash);
      expect(await trash.isAbsent(entry), true);
    },
  );

  test(
    'large legacy restore uniqueness failure keeps negative entry and all bytes',
    () async {
      final store = await fixture(), source = largeSource();
      final id = await insert(store, 'same-title', source, 'article');
      await (await store.database).insert('notes', {
        'title': 'same-title',
        'content': 'active-original',
        'updated_at': 7,
        'deleted': 0,
        'labels': '[]',
        'collection': 'article',
        'editor_type': 'markdown',
      });
      final before = await metadata(store, id),
          hash = await bodyHash(store, id);
      final trash = LocalTrashRepository(store);
      addTearDown(trash.dispose);
      final entry = (await trash.read(
        type: 'blog',
      )).entries.singleWhere((entry) => entry.id == -id);
      await expectLater(
        trash.apply(entry, TrashOperation.restore),
        throwsA(isA<TrashPreflightFailure>()),
      );
      expect(await metadata(store, id), before);
      expect(await bodyHash(store, id), hash);
      expect(await trash.isAbsent(entry), false);
    },
  );
}
