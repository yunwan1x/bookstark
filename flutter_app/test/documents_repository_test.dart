import 'dart:convert';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/documents_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'tree decoder preserves types and hierarchy, rejects duplicate and mismatched parents',
    () {
      final rows = [
        {
          'document_id': 1,
          'document_name': '章',
          'children': [
            {'document_id': 2, 'parent_id': 1, 'doc_type': 'drawing'},
          ],
        },
      ];
      final tree = decodeDocumentTree(rows);
      expect(flattenDocuments(tree).map((node) => node.id), [1, 2]);
      expect(tree.single.children.single.type, 'drawing');
      expect(
        () => decodeDocumentTree([
          {'document_id': 1},
          {'document_id': 1},
        ]),
        throwsFormatException,
      );
      expect(
        () => decodeDocumentTree([
          {
            'document_id': 1,
            'children': [
              {'document_id': 2},
            ],
          },
        ]),
        throwsFormatException,
      );
    },
  );
  test(
    'document save sends only markdown so empty body actually clears; advanced types refuse writes',
    () async {
      final requests = <http.Request>[];
      var type = 'markdown';
      final client = BookstarkClient(
        'https://example.test',
        transport: MockClient((request) async {
          requests.add(request);
          if (request.url.path.endsWith('csrf-token')) {
            return http.Response(
              '{}',
              200,
              headers: {'set-cookie': 'csrf_token=x'},
            );
          }
          if (request.method == 'GET') {
            return http.Response(
              jsonEncode({
                'data': {'document_id': 2, 'book_id': 1, 'doc_type': type},
              }),
              200,
            );
          }
          return http.Response('{}', 200);
        }),
      );
      addTearDown(client.close);
      final repo = RemoteDocumentsRepository(client);
      await repo.saveMarkdown(2, '');
      expect(jsonDecode(requests.last.body), {'markdown': ''});
      type = 'richdoc';
      final writes = requests
          .where((request) => request.method == 'PUT')
          .length;
      await expectLater(repo.saveMarkdown(2, 'overwrite'), throwsStateError);
      expect(
        requests.where((request) => request.method == 'PUT').length,
        writes,
      );
      await expectLater(
        repo.saveMarkdown(2, List.filled(125001, '📖').join()),
        throwsFormatException,
      );
    },
  );
  test(
    'move validates tree before HTTP mutation and parent create rejects foreign parent',
    () async {
      var writes = 0;
      final client = BookstarkClient(
        'https://example.test',
        transport: MockClient((request) async {
          if (request.method != 'GET') writes++;
          return http.Response(
            '{"data":[{"document_id":1,"children":[{"document_id":2,"parent_id":1}]}]}',
            200,
          );
        }),
      );
      addTearDown(client.close);
      final repo = RemoteDocumentsRepository(client);
      await expectLater(repo.move(1, 1, 2), throwsStateError);
      await expectLater(repo.move(1, 2, 2), throwsStateError);
      await expectLater(repo.move(1, 2, 9), throwsStateError);
      await expectLater(repo.create(1, 'child', parentId: 9), throwsStateError);
      expect(writes, 0);
      expect(
        () => validateDocumentName(List.filled(67, '书').join()),
        throwsFormatException,
      );
    },
  );
}
