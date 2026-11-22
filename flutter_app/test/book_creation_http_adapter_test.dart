// Draft only; requires reviewed API working-copy integration. No toolchain run.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/book_creation_attempt.dart';
import 'package:bookstark_flutter/core/book_creation_http_adapter.dart';

http.Response json(Object data) => http.Response(
  jsonEncode(data),
  200,
  headers: {'content-type': 'application/json'},
);
void main() {
  test(
    'book POST positive ID returned directly; no labels followup mutation',
    () async {
      final scope = BookCreationScope(
        server: 'https://demo.invalid/prefix',
        memberId: 7,
        binding: 'a' * 32,
      );
      final events = <String>[];
      final client = BookstarkClient(
        scope.server,
        transport: MockClient((r) async {
          if (r.method == 'GET') {
            expect(r.url.path, '/prefix/api/profile');
            return json({
              'code': 0,
              'data': {'member_id': 7},
            });
          }
          events.add('post');
          expect(r.url.path, '/prefix/api/books');
          expect(jsonDecode(r.body), {
            'book_name': 'Exact',
            'description': '',
            'labels': '',
          });
          return json({
            'code': 0,
            'data': {
              'book_id': 208,
              'member_id': 7,
              'book_name': 'Exact',
              'description': '',
              'identify': 'generated',
            },
          });
        }),
      );
      client.restoreSession({
        'token': 'fixture-token',
        'csrf_token': 'fixture-csrf',
      });
      final adapter = BookCreationHttpAdapter(
        client: client,
        scope: scope,
        isCurrent: () => true,
      );
      final receipt = await adapter.transport.create(
        BookCreationInput(name: 'Exact', description: '', labels: []),
        onSubmit: () async {
          events.add('durable-marker');
        },
      );
      expect(receipt.id, 208);
      expect(events, ['durable-marker', 'post']);
      adapter.retire();
      client.close();
    },
  );
  test(
    'manual review uses strict metadata+dedicated successful null labels bracket',
    () async {
      final scope = BookCreationScope(
            server: 'https://demo.invalid',
            memberId: 7,
            binding: 'a' * 32,
          ),
          paths = <String>[];
      final client = BookstarkClient(
        scope.server,
        transport: MockClient((r) async {
          expect(r.method, 'GET');
          paths.add(r.url.path);
          if (r.url.path.endsWith('/profile')) {
            return json({
              'code': 0,
              'data': {'member_id': 7},
            });
          }
          if (r.url.path.contains('/labels/')) {
            return json({'code': 0, 'data': null});
          }
          return json({
            'code': 0,
            'data': {
              'book_id': 208,
              'member_id': 7,
              'book_name': 'Current',
              'description': '',
              'identify': 'existing',
              'doc_count': 0,
              'modify_time': null,
              'labels': null,
            },
          });
        }),
      );
      client.restoreSession({'token': 'fixture-token'});
      final adapter = BookCreationHttpAdapter(
        client: client,
        scope: scope,
        isCurrent: () => true,
      );
      final actual = await adapter.readExisting(208);
      expect(actual.labels, isEmpty);
      expect(actual.labelsLoaded, true);
      expect(paths, [
        '/api/profile',
        '/api/books/208',
        '/api/labels/resource/book/208',
        '/api/labels/resource/book/208',
        '/api/books/208',
      ]);
      adapter.retire();
      client.close();
    },
  );
  test('metadata changes or labels error refuse adoption read', () async {
    final scope = BookCreationScope(
      server: 'https://demo.invalid',
      memberId: 7,
      binding: 'a' * 32,
    );
    for (final failLabels in [false, true]) {
      var details = 0;
      final client = BookstarkClient(
        scope.server,
        transport: MockClient((r) async {
          if (r.url.path.endsWith('/profile')) {
            return json({
              'code': 0,
              'data': {'member_id': 7},
            });
          }
          if (r.url.path.contains('/labels/')) {
            return failLabels
                ? http.Response(
                    'sensitive',
                    500,
                    headers: {'content-type': 'application/json'},
                  )
                : json({'code': 0, 'data': []});
          }
          details++;
          return json({
            'code': 0,
            'data': {
              'book_id': 208,
              'member_id': 7,
              'book_name': details == 1 ? 'before' : 'after',
              'description': '',
              'identify': 'existing',
              'doc_count': 1,
              'modify_time': null,
            },
          });
        }),
      );
      client.restoreSession({'token': 'fixture-token'});
      final adapter = BookCreationHttpAdapter(
        client: client,
        scope: scope,
        isCurrent: () => true,
      );
      await expectLater(adapter.readExisting(208), throwsA(anything));
      adapter.retire();
      client.close();
    }
  });
}
