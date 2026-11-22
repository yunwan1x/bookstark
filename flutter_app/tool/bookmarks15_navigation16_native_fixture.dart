// PREPARED/UNRUN owned alternate entry; never promote as the production entry.
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/local_store.dart';
import 'package:bookstark_flutter/core/bookmarks_repository.dart';
import 'package:bookstark_flutter/core/local_bookmarks_repository.dart';
import 'package:bookstark_flutter/core/labels_repository.dart';
import 'package:bookstark_flutter/core/navigation_repository.dart';
import 'package:bookstark_flutter/features/bookmarks/bookmarks_page.dart';
import 'package:bookstark_flutter/features/navigation/navigation_page.dart';

void main() => runApp(const MaterialApp(home: OwnedBookmarksFixture()));

class OwnedBookmarksFixture extends StatefulWidget {
  const OwnedBookmarksFixture({super.key});
  @override
  State<OwnedBookmarksFixture> createState() => _State();
}

class _State extends State<OwnedBookmarksFixture> {
  static const run = String.fromEnvironment('OWNED_BOOKMARKS_RUN');
  static const port = int.fromEnvironment('OWNED_BOOKMARKS_PORT');
  LocalStore? store;
  BookstarkClient? client;
  BookmarksRepository? localBooks, remoteBooks;
  LabelsRepository? localLabels, remoteLabels;
  NavigationRepository? localNav, remoteNav;
  bool current = true, ready = false;
  String? error;
  String sql = '';
  @override
  void initState() {
    super.initState();
    unawaited(_prepare());
  }

  Future<void> _prepare() async {
    try {
      if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(run) ||
          port < 1024 ||
          port > 65535) {
        throw StateError('Owned fixture binding');
      }
      final temp = await getTemporaryDirectory();
      final local = LocalStore(path: '${temp.path}/owned_bookmarks15_$run.db');
      store = local;
      final db = await local.database;
      await db.transaction((txn) async {
        if ((await txn.query(
          'bookmarks',
          columns: ['bookmark_id'],
          limit: 1,
        )).isNotEmpty) {
          throw StateError('Never replay a used owned fixture');
        }
        for (var i = 1; i <= 205; i++) {
          await txn.insert('bookmarks', {
            'bookmark_id': i,
            'title': 'Owned Bookmark ${i.toString().padLeft(3, '0')}',
            'url': i == 1
                ? 'https://example.test'
                : i == 2
                ? 'https://example.test?root=2'
                : i == 3
                ? 'http://example.test#root'
                : 'https://other.test/$i',
            'description': 'exact description $i',
            'favicon': 'http://127.0.0.1:$port/icon.png',
            'labels': jsonEncode([
              i.isOdd ? 'GroupA/Sub' : 'GroupB/Sub',
              'exact,tag',
            ]),
            'is_pinned': i == 1 ? 1 : 0,
            'nav_visible': i <= 5 ? 1 : 0,
            'create_time': DateTime(2026, 11, 1).millisecondsSinceEpoch,
            'modify_time':
                DateTime(2026, 11, 11, 12).millisecondsSinceEpoch - i * 1000,
          });
        }
      });
      final transport = BookstarkClient('http://127.0.0.1:$port');
      client = transport;
      localBooks = LocalBookmarksRepository(local);
      localLabels = LocalLabelsRepository(local);
      localNav = LocalNavigationRepository(local);
      remoteBooks = RemoteBookmarksRepository(
        transport,
        memberId: 7,
        isCurrent: () => mounted && current,
      );
      remoteLabels = RemoteLabelsRepository(transport);
      remoteNav = RemoteNavigationRepository(transport);
      if (mounted) setState(() => ready = true);
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Owned fixture initialization failed');
      }
    }
  }

  Future<void> _inspect() async {
    final db = await store!.database;
    final count = await db.rawQuery(
      'SELECT COUNT(*) AS total,SUM(is_public) AS public,SUM(CASE WHEN bookmark_id>200 THEN is_public ELSE 0 END) AS tailPublic FROM bookmarks WHERE deleted=0',
    );
    final row = count.single;
    if (mounted) {
      setState(
        () => sql =
            'SQL total=${row['total']} public=${row['public']} tailPublic=${row['tailPublic']}',
      );
    }
  }

  void _open({required bool remote, required bool navigation}) {
    final books = remote ? remoteBooks! : localBooks!,
        labels = remote ? remoteLabels! : localLabels!;
    final page = navigation
        ? NavigationPage(
            repository: remote ? remoteNav! : localNav!,
            bookmarks: books,
            labels: labels,
            english: true,
            local: !remote,
            faviconIsCurrent: () => mounted && current,
          )
        : BookmarksPage(
            repository: books,
            labelsRepository: labels,
            english: true,
            local: !remote,
            faviconScopeKey: (run, remote),
            faviconIsCurrent: () => mounted && current,
          );
    Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => page));
  }

  @override
  void dispose() {
    current = false;
    client?.close();
    unawaited(store?.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Owned 15/16 fixture')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (error != null)
          Text(error!)
        else if (!ready)
          const CircularProgressIndicator()
        else ...[
          const Text('Owned fixture ready'),
          for (final remote in [false, true]) ...[
            FilledButton(
              onPressed: () => _open(remote: remote, navigation: false),
              child: Text(remote ? 'Remote bookmarks' : 'Local bookmarks'),
            ),
            FilledButton(
              onPressed: () => _open(remote: remote, navigation: true),
              child: Text(remote ? 'Remote navigation' : 'Local navigation'),
            ),
          ],
          OutlinedButton(
            onPressed: _inspect,
            child: const Text('Inspect local SQL'),
          ),
          Text(sql),
        ],
      ],
    ),
  );
}
