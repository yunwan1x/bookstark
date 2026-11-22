import 'dart:ffi';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:bookstark_flutter/core/bookmarks_repository.dart';
import 'package:bookstark_flutter/core/local_bookmarks_repository.dart';
import 'package:bookstark_flutter/core/local_store.dart';

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
    'real SQLite site root query fragment and exact port exclude lookalike authority',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'bookmark-exact-site-',
      );
      final store = LocalStore(
        path: '${directory.path}/data.db',
        factory: databaseFactoryFfiNoIsolate,
      );
      try {
        final repo = LocalBookmarksRepository(store);
        final urls = [
          'https://example.test',
          'http://example.test',
          'https://example.test/',
          'https://example.test?x=1',
          'https://example.test#anchor',
          'https://EXAMPLE.test/path',
          'https://example.test:8443',
          'https://example.test:8443?x=1',
          'http://example.test:8443/path',
          'https://example.test.evil/path',
          'https://evil-example.test/path',
          'https://example.test:84430/path',
        ];
        final ids = <String, int>{};
        for (final url in urls) {
          if (url == 'https://example.test:84430/path') {
            // Historical persisted data may contain a now-invalid port; ordinary saves must still reject it.
            final db = await store.database;
            final template =
                Map<String, Object?>.from(
                    (await db.query(
                      'bookmarks',
                      where: 'bookmark_id = ?',
                      whereArgs: [ids[urls.first]],
                    )).single,
                  )
                  ..remove('bookmark_id')
                  ..['title'] = 'legacy invalid port'
                  ..['url'] = url;
            ids[url] = await db.insert('bookmarks', template);
          } else {
            ids[url] = await repo.save(
              BookmarkItem(
                title: 'title $url',
                url: url,
                labels: ['a,b', ' exact '],
              ),
            );
          }
        }
        await expectLater(
          repo.save(
            const BookmarkItem(
              title: 'new invalid port',
              url: 'https://example.test:84430/new',
            ),
          ),
          throwsFormatException,
        );
        for (final pair in [
          ('example.test', urls.sublist(0, 6)),
          ('example.test:8443', urls.sublist(6, 9)),
          ('EXAMPLE.TEST', urls.sublist(0, 6)),
        ]) {
          final result = await repo.list(BookmarkQuery(site: pair.$1));
          expect(result.total, pair.$2.length);
          expect(
            result.items.map((item) => item.id).toSet(),
            pair.$2.map((url) => ids[url]).toSet(),
          );
        }
        for (final entry in ids.entries) {
          final actual = await repo.read(entry.value);
          expect(actual.url, entry.key);
          expect(actual.labels, ['a,b', ' exact ']);
        }
      } finally {
        await store.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
