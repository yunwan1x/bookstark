import 'dart:convert';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/label_management_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response reply(Object value) => http.Response(
  jsonEncode({'code': 0, 'data': value}),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
void main() {
  test('names count UTF8 bytes and keep exact identity', () {
    validateLabelName(List.filled(25, '📚').join());
    expect(
      () => validateLabelName(List.filled(26, '📚').join()),
      throwsFormatException,
    );
    validateLabelName(' 阅读 ');
    expect(() => validateLabelName('   '), throwsFormatException);
  });
  test(
    'member cannot mutate global settings or existing labels before HTTP',
    () async {
      var calls = 0;
      final client = BookstarkClient(
        'https://example.test',
        transport: MockClient((_) async {
          calls++;
          return reply({});
        }),
      );
      addTearDown(client.close);
      final repo = RemoteLabelManagementRepository(client, canManage: false);
      await expectLater(repo.remove(1), throwsA(isA<ApiFailure>()));
      await expectLater(repo.removeUnused(), throwsA(isA<ApiFailure>()));
      await expectLater(repo.save('阅读', id: 1), throwsA(isA<ApiFailure>()));
      await expectLater(repo.merge(1, [2]), throwsA(isA<ApiFailure>()));
      await expectLater(
        repo.saveRecommendationSettings(
          const LabelRecommendationSettings(
            strategy: LabelRecommendationStrategy.recent,
          ),
        ),
        throwsA(isA<ApiFailure>()),
      );
      expect(calls, 0);
    },
  );
  test(
    'zero displayed counters do not imply no document association',
    () async {
      final client = BookstarkClient(
        'https://example.test',
        transport: MockClient(
          (request) async => reply({
            'label_id': 1,
            'label_name': '文档标签',
            'book_count': 0,
            'blog_count': 0,
            'bookmark_count': 0,
            'items': [
              {
                'resource_id': 44,
                'relation_type': 'document',
                'title': '',
                'identify': '',
              },
            ],
          }),
        ),
      );
      addTearDown(client.close);
      final detail = await RemoteLabelManagementRepository(
        client,
        canManage: false,
      ).read(1);
      expect(detail.verifiedUnused, isFalse);
      expect(detail.items.single.type, LabelResourceType.document);
      expect(detail.items.single.title, isEmpty);
    },
  );
  test('merge refuses missing target without any transaction write', () async {
    final methods = <String>[];
    final client = BookstarkClient(
      'https://example.test',
      transport: MockClient((request) async {
        methods.add(request.method);
        return http.Response(
          jsonEncode({'code': 404, 'message': 'Label missing'}),
          404,
        );
      }),
    );
    addTearDown(client.close);
    await expectLater(
      RemoteLabelManagementRepository(
        client,
        canManage: true,
      ).merge(99, [1, 2]),
      throwsA(isA<ApiFailure>()),
    );
    expect(methods, ['GET']);
  });
  test(
    'recommendation input cannot silently split selected tag identities',
    () {
      expect(
        () => const LabelRecommendationSettings(
          strategy: LabelRecommendationStrategy.manual,
          manualLabels: ['a,b'],
        ).writeBody(),
        throwsFormatException,
      );
      final body = const LabelRecommendationSettings(
        strategy: LabelRecommendationStrategy.manual,
        manualLabels: [' 阅读 ', '阅读', '学习'],
        pageSize: 50,
      ).writeBody();
      expect(body['manual_labels'], ['阅读', '学习']);
      expect(
        () => const LabelRecommendationSettings(
          strategy: LabelRecommendationStrategy.total,
          pageSize: 51,
        ).writeBody(),
        throwsFormatException,
      );
    },
  );
}
