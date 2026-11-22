import 'dart:convert';
import 'api_client.dart';
import 'local_store.dart';

abstract interface class LabelsRepository {
  Future<List<String>> search(String keyword, {int page = 1});
}

class RemoteLabelsRepository implements LabelsRepository {
  RemoteLabelsRepository(this.client);
  final BookstarkClient client;
  @override
  Future<List<String>> search(String keyword, {int page = 1}) async {
    final result = await client.get(
      '/api/labels?${Uri(queryParameters: {'keyword': keyword, 'page': '$page'}).query}',
    );
    return (result['data'] as List? ?? [])
        .map((row) => (row as Map)['label_name'] as String)
        .toList();
  }
}

class LocalLabelsRepository implements LabelsRepository {
  LocalLabelsRepository(this.store);
  final LocalStore store;
  @override
  Future<List<String>> search(
    String keyword, {
    int page = 1,
  }) => store.maintenance.use(() async {
    final db = await store.database;
    final rows = await db.rawQuery(
      'SELECT labels FROM notes WHERE deleted = 0 UNION ALL SELECT labels FROM books WHERE deleted = 0 UNION ALL SELECT labels FROM bookmarks WHERE deleted = 0 UNION ALL SELECT labels FROM documents WHERE deleted = 0',
    );
    final names = <String>{
      for (final row in await db.query('local_labels', columns: ['label_name']))
        row['label_name'] as String,
    };
    for (final row in rows) {
      names.addAll(
        (jsonDecode(row['labels'] as String) as List).cast<String>(),
      );
    }
    final matches =
        names
            .where((name) => name.toLowerCase().contains(keyword.toLowerCase()))
            .toList()
          ..sort();
    return matches.skip((page - 1) * 20).take(20).toList();
  });
}
