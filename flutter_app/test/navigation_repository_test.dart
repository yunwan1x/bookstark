import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/bookmarks_repository.dart';
import 'package:bookstark_flutter/core/local_bookmarks_repository.dart';
import 'package:bookstark_flutter/core/local_store.dart';
import 'package:bookstark_flutter/core/navigation_repository.dart';
import 'package:bookstark_flutter/core/navigation_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqlite3/open.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('remote navigation keeps canonical groups and reported count', () async {
    final client = BookstarkClient(
      'https://example.test/base',
      transport: MockClient((request) async {
        expect(request.url.path, '/base/api/bookmarks-grouped');
        expect(request.url.queryParameters, {
          'keyword': 'a & 中',
          'scope': 'public',
        });
        return http.Response(
          jsonEncode({
            'groups': [
              {
                'name': '开发',
                'bookmarks': [
                  {
                    'bookmark_id': 2,
                    'member_id': 7,
                    'nav_visible': true,
                    'labels': ['开发/Flutter'],
                  },
                ],
              },
            ],
            'pinned': null,
            'ungrouped': null,
            'all_labels': ['开发/Flutter'],
            'total': 5,
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    addTearDown(client.close);
    final result = await RemoteNavigationRepository(
      client,
    ).load(keyword: 'a & 中', scope: BookmarkScope.public);
    expect(result.total, 5);
    expect(result.items.length, 1);
    expect(result.groups.single.name, '开发');
    expect(result.groups.single.items.single.labels, ['开发/Flutter']);
    expect(NavigationResult.fromJson({}).items, isEmpty);
    expect(
      () => NavigationResult.fromJson({'total': -1}),
      throwsFormatException,
    );
  });
  test('navigation preferences are isolated and reject corrupt enum', () async {
    final values = <String, String>{};
    NavigationPreferencesVault vault(String namespace) =>
        NavigationPreferencesVault(
          namespace: namespace,
          readValue: (key) async => values[key],
          writeValue: (key, value) async {
            values[key] = value;
          },
          deleteValue: (key) async {
            values.remove(key);
          },
        );
    final first = vault('server/user1'), other = vault('server/user2');
    await first.write(
      const NavigationPreferences(view: NavigationView.compact, groups: {'开发'}),
    );
    expect((await first.read()).groups, {'开发'});
    expect((await other.read()).groups, isEmpty);
    values.updateAll((key, value) => value.replaceAll('compact', 'bad-view'));
    await expectLater(first.read(), throwsFormatException);
    await first.clear();
    expect((await first.read()).view, NavigationView.cards);
  });
  test(
    'local navigation uses visible active rows, exact labels and pinned separation',
    () async {
      sqfliteFfiInit();
      if (Platform.isLinux) {
        open.overrideFor(
          OperatingSystem.linux,
          () => DynamicLibrary.open('libsqlite3.so.0'),
        );
      }
      final directory = await Directory.systemTemp.createTemp(
        'bookstark-navigation-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final store = LocalStore(
        path: '${directory.path}/data.db',
        factory: databaseFactoryFfiNoIsolate,
      );
      addTearDown(store.close);
      final bookmarks = LocalBookmarksRepository(store);
      final ids = <int>[];
      for (var i = 0; i < 24; i++) {
        ids.add(
          await bookmarks.save(
            BookmarkItem(
              title: '书签$i',
              url: 'https://example.test/$i',
              labels: i < 22 ? ['开发/Flutter', 'a,b'] : [],
            ),
          ),
        );
      }
      await bookmarks.batch(BookmarkBatch.showNav, ids.take(23).toList());
      await bookmarks.batch(BookmarkBatch.pin, [ids.first]);
      final repo = LocalNavigationRepository(store);
      final result = await repo.load();
      expect(result.total, 23);
      expect(result.pinned.single.id, ids.first);
      expect(result.groups.single.items.length, 21);
      expect(result.ungrouped.single.id, ids[22]);
      expect(result.items.map((item) => item.id).toSet().length, 23);
      expect(result.labels, contains('a,b'));
      await bookmarks.setNavVisible(ids[1], false);
      await bookmarks.remove(ids[2]);
      expect((await repo.load()).total, 21);
      await store.close();
      expect((await repo.load()).total, 21);
      await expectLater(
        repo.load(scope: BookmarkScope.public),
        throwsUnsupportedError,
      );
    },
  );
}
