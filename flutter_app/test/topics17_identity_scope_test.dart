import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/topics_repository.dart';
import 'package:bookstark_flutter/features/topics/topics_feature.dart';
import '../tool/fixtures/topics.dart';
import '../tool/fixtures/topic_picker.dart';

void main() {
  testWidgets(
    'actual feature topic change creates a fresh task scope instead of mixing topic B with A tasks',
    (tester) async {
      final repo = TopicsFixture(), picker = TopicPickerFixture();
      Widget page(int id) => MaterialApp(
        home: TopicsFeature(
          initialTopicId: id,
          repository: repo,
          tasks: repo.taskRepository,
          picker: picker,
          onOpenResource: (_, _) async {},
        ),
      );
      await tester.pumpWidget(page(1));
      await tester.pumpAndSettle();
      expect(find.text('任务1'), findsOneWidget);
      await tester.pumpWidget(page(2));
      await tester.pumpAndSettle();
      expect(find.text('任务3'), findsOneWidget);
      expect(find.text('任务1'), findsNothing);
      await tester.tap(find.text('任务3'));
      await tester.pumpAndSettle();
      expect(find.text('3条匹配任务'), findsOneWidget);
      expect(find.text('每周回顾一次'), findsNothing);
    },
  );
  test(
    'all topic writes recheck actual owner after held CSRF and submit zero mutations',
    () async {
      final calls = <Future<void> Function(RemoteTopicsRepository)>[
        (r) async {
          await r.save(
            const TopicItem(
              id: 1,
              memberId: 7,
              title: 'exact',
              question: 'question',
            ),
          );
        },
        (r) => r.setPinned(1, true),
        (r) => r.remove(1),
        (r) async {
          await r.saveSummary(
            const TopicSummary(topicId: 1, content: 'new summary'),
          );
        },
        (r) async {
          await r.saveSummary(
            const TopicSummary(id: 2, topicId: 1, content: 'existing summary'),
          );
        },
        (r) => r.removeSummary(1, 2),
        (r) => r.sortSummaries(1, {2: 0}),
        (r) async {
          await r.addResource(
            const TopicResource(
              topicId: 1,
              type: TopicResourceType.note,
              targetId: 3,
            ),
          );
        },
        (r) => r.removeResource(1, 4),
        (r) => r.sortResources(1, {4: 0}),
        (r) async {
          await r.saveComment(
            const TopicComment(
              topicId: 1,
              target: TopicCommentTarget.summary,
              targetId: 2,
              content: 'exact comment',
            ),
          );
        },
        (r) async {
          await r.saveComment(
            const TopicComment(
              id: 5,
              topicId: 1,
              target: TopicCommentTarget.summary,
              targetId: 2,
              content: 'exact comment',
            ),
          );
        },
        (r) => r.removeComment(1, 5),
      ];
      for (final call in calls) {
        final reached = Completer<void>(), csrf = Completer<http.Response>();
        var current = true, writes = 0;
        final client = BookstarkClient(
          'https://topic.test',
          transport: MockClient((request) async {
            if (request.url.path == '/api/csrf-token') {
              reached.complete();
              return csrf.future;
            }
            if (request.method != 'GET') writes++;
            return http.Response(
              '{}',
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        );
        final repo = RemoteTopicsRepository(
          client,
          memberId: 7,
          isCurrent: () => current,
        );
        try {
          final rejected = expectLater(call(repo), throwsA(isA<StateError>()));
          await reached.future;
          current = false;
          csrf.complete(
            http.Response(
              '{}',
              200,
              headers: {
                'content-type': 'application/json',
                'set-cookie': 'csrf_token=${'a' * 64}; Path=/',
              },
            ),
          );
          await rejected;
          expect(writes, 0);
        } finally {
          client.close();
        }
      }
    },
  );
  test(
    'held old-owner topic list cannot be delivered after scope retirement',
    () async {
      final reached = Completer<void>(), reply = Completer<http.Response>();
      var current = true;
      final client = BookstarkClient(
        'https://topic.test',
        transport: MockClient((request) async {
          reached.complete();
          return reply.future;
        }),
      );
      try {
        final repo = RemoteTopicsRepository(
          client,
          memberId: 7,
          isCurrent: () => current,
        );
        final rejected = expectLater(
          repo.list(const TopicQuery()),
          throwsA(isA<StateError>()),
        );
        await reached.future;
        current = false;
        reply.complete(
          http.Response(
            jsonEncode({
              'code': 0,
              'total': 1,
              'page': 1,
              'page_size': 20,
              'data': [
                {'topic_id': 1, 'member_id': 7, 'title': 'old private title'},
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          ),
        );
        await rejected;
      } finally {
        client.close();
      }
    },
  );
}
