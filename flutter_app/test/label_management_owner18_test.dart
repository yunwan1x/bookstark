import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/label_management_repository.dart';

http.Response jsonResponse(Object value) => http.Response(
  jsonEncode(value),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
void main() {
  for (final mode in [
    'new',
    'rename',
    'remove',
    'unused',
    'merge',
    'unbind',
    'settings',
  ]) {
    test(
      '$mode held actual CSRF cannot write after owner retirement',
      () async {
        final reached = Completer<void>(), release = Completer<http.Response>();
        var current = true, writes = 0;
        final client = BookstarkClient(
          'https://labels.test',
          transport: MockClient((request) async {
            if (request.url.path == '/api/csrf-token') {
              reached.complete();
              return release.future;
            }
            if (request.method == 'GET' &&
                request.url.path.endsWith('/detail')) {
              final id = int.parse(request.url.pathSegments[2]);
              return jsonResponse({
                'label_id': id,
                'label_name': 'Exact $id',
                'items': [],
              });
            }
            writes++;
            return jsonResponse({'label_id': 1, 'label_name': 'actual'});
          }),
        );
        client.restoreSession({'token': 'fixture-token'});
        final repo = RemoteLabelManagementRepository(
          client,
          canManage: true,
          isCurrent: () => current,
        );
        Future<void> operation() async {
          switch (mode) {
            case 'new':
              await repo.save('Exact');
              break;
            case 'rename':
              await repo.save('Renamed', id: 1);
              break;
            case 'remove':
              await repo.remove(1);
              break;
            case 'unused':
              await repo.removeUnused();
              break;
            case 'merge':
              await repo.merge(1, [2]);
              break;
            case 'unbind':
              await repo.unbind(
                1,
                const LabelResource(
                  id: 3,
                  type: LabelResourceType.blog,
                  title: 'Actual',
                ),
              );
              break;
            case 'settings':
              await repo.saveRecommendationSettings(
                const LabelRecommendationSettings(
                  strategy: LabelRecommendationStrategy.manual,
                  manualLabels: ['Exact'],
                ),
              );
              break;
          }
        }

        try {
          final checked = expectLater(operation(), throwsStateError);
          await reached.future;
          current = false;
          release.complete(
            http.Response(
              '{}',
              200,
              headers: {
                'content-type': 'application/json',
                'set-cookie': 'csrf_token=${'a' * 64}; Path=/',
              },
            ),
          );
          await checked;
          expect(writes, 0);
        } finally {
          if (!release.isCompleted) release.complete(jsonResponse({}));
          client.close();
        }
      },
    );
  }
  test(
    'same client revision switch blocks old writer even if optional current is omitted',
    () async {
      final reached = Completer<void>(), release = Completer<http.Response>();
      var writes = 0;
      final client = BookstarkClient(
        'https://labels.test',
        transport: MockClient((request) async {
          if (request.url.path == '/api/csrf-token') {
            reached.complete();
            return release.future;
          }
          writes++;
          return jsonResponse({'label_id': 1, 'label_name': 'Actual'});
        }),
      );
      client.restoreSession({'token': 'owner-a'});
      final repo = RemoteLabelManagementRepository(client, canManage: true);
      try {
        final checked = expectLater(repo.save('Exact'), throwsStateError);
        await reached.future;
        client.restoreSession({'token': 'owner-b'});
        release.complete(
          http.Response(
            '{}',
            200,
            headers: {
              'content-type': 'application/json',
              'set-cookie': 'csrf_token=${'b' * 64}; Path=/',
            },
          ),
        );
        await checked;
        expect(writes, 0);
      } finally {
        if (!release.isCompleted) release.complete(jsonResponse({}));
        client.close();
      }
    },
  );
  test('late label read never returns old-owner data to new scope', () async {
    final reached = Completer<void>(), release = Completer<http.Response>();
    var current = true;
    final client = BookstarkClient(
      'https://labels.test',
      transport: MockClient((request) async {
        reached.complete();
        return release.future;
      }),
    );
    final repo = RemoteLabelManagementRepository(
      client,
      canManage: false,
      isCurrent: () => current,
    );
    try {
      final checked = expectLater(repo.read(1), throwsStateError);
      await reached.future;
      current = false;
      release.complete(
        jsonResponse({'label_id': 1, 'label_name': 'Old owner', 'items': []}),
      );
      await checked;
    } finally {
      if (!release.isCompleted) release.complete(jsonResponse({}));
      client.close();
    }
  });
  test(
    'non-admin mutation permissions remain enforced before transport',
    () async {
      var requests = 0;
      final client = BookstarkClient(
        'https://labels.test',
        transport: MockClient((_) async {
          requests++;
          return jsonResponse({});
        }),
      );
      final repo = RemoteLabelManagementRepository(client, canManage: false);
      try {
        await expectLater(
          repo.save('Exact', id: 1),
          throwsA(isA<ApiFailure>()),
        );
        await expectLater(repo.remove(1), throwsA(isA<ApiFailure>()));
        await expectLater(repo.removeUnused(), throwsA(isA<ApiFailure>()));
        await expectLater(repo.merge(1, [2]), throwsA(isA<ApiFailure>()));
        await expectLater(
          repo.saveRecommendationSettings(
            const LabelRecommendationSettings(
              strategy: LabelRecommendationStrategy.recent,
            ),
          ),
          throwsA(isA<ApiFailure>()),
        );
        expect(requests, 0);
      } finally {
        client.close();
      }
    },
  );
}
