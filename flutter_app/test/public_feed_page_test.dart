import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/public_feed_models.dart';
import 'package:bookstark_flutter/core/public_feed_repository.dart';
import 'package:bookstark_flutter/features/public_feed/public_feed_page.dart';
import 'package:bookstark_flutter/features/public_feed/resource_create_page.dart';

class PendingFeed implements PublicFeedRepository {
  final requests =
      <
        ({
          PublicFeedQuery query,
          Completer<PublicFeedPageData> result,
          Future<void>? abort,
        })
      >[];
  @override
  Future<PublicFeedPageData> load(
    PublicFeedQuery query, {
    Future<void>? abortTrigger,
  }) {
    final result = Completer<PublicFeedPageData>();
    requests.add((query: query, result: result, abort: abortTrigger));
    return result.future;
  }

  void finish(int index, String title, {bool locked = false}) {
    final request = requests[index];
    request.result.complete(
      PublicFeedPageData(
        query: request.query,
        items: [
          PublicFeedItem(
            kind: request.query.kind,
            identity: title,
            shareIdentify: title,
            title: title,
            author: 'Actual owner',
            date: '2026-11-05',
            format: 'markdown',
            locked: locked,
            pinned: false,
            excerpt: 'PROTECTED BODY',
            labels: ['PROTECTED LABEL'],
          ),
        ],
        categories: [const PublicFeedCategory(label: '', selected: true)],
        previous: null,
        next: null,
      ),
    );
  }
}

void main() {
  testWidgets(
    'resource selector returns chosen kind without executing creation',
    (tester) async {
      ResourceCreateKind? chosen;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  chosen = await Navigator.of(context).push<ResourceCreateKind>(
                    MaterialPageRoute(
                      builder: (_) => const ResourceCreatePage(),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('书签'));
      await tester.pumpAndSettle();
      expect(chosen, ResourceCreateKind.bookmark);
      expect(find.text('Open'), findsOneWidget);
    },
  );
  testWidgets('English feed and chooser stay usable at 320dp and 200 percent', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = PendingFeed();
    Widget app(Widget page) => MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: const TextScaler.linear(2)),
        child: child!,
      ),
      home: page,
    );
    await tester.pumpWidget(
      app(
        PublicFeedPage(
          repository: repo,
          english: true,
          onOpen: (_) async {},
          onCreate: () async {},
        ),
      ),
    );
    repo.finish(0, 'Actual title');
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Actual title'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Null check'), findsNothing);
    await tester.pumpWidget(app(const ResourceCreatePage(english: true)));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Document'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'changed filters cancel old load and stale completion cannot overwrite current cards',
    (tester) async {
      final repo = PendingFeed();
      PublicFeedItem? opened;
      await tester.pumpWidget(
        MaterialApp(
          home: PublicFeedPage(
            repository: repo,
            onOpen: (item) async {
              opened = item;
            },
            onCreate: () async {},
          ),
        ),
      );
      var cancelled = false;
      repo.requests.first.abort!.then((_) => cancelled = true);
      await tester.tap(find.widgetWithText(ChoiceChip, '笔记'));
      await tester.pump();
      expect(cancelled, true);
      expect(repo.requests[1].query.kind, PublicFeedKind.note);
      repo.finish(1, 'Current', locked: true);
      await tester.pumpAndSettle();
      repo.finish(0, 'Stale');
      await tester.pumpAndSettle();
      expect(find.text('Stale'), findsNothing);
      expect(find.text('PROTECTED BODY'), findsNothing);
      expect(find.text('PROTECTED LABEL'), findsNothing);
      expect(find.text('需密码查看'), findsOneWidget);
      await tester.tap(find.text('Current'));
      await tester.pumpAndSettle();
      expect(opened?.shareIdentify, 'Current');
      expect(opened?.kind, PublicFeedKind.note);
    },
  );
  testWidgets(
    'repository error stays visible with retry and no fabricated empty results',
    (tester) async {
      final repo = PendingFeed();
      await tester.pumpWidget(
        MaterialApp(
          home: PublicFeedPage(
            repository: repo,
            onOpen: (_) async {},
            onCreate: () async {},
          ),
        ),
      );
      repo.requests.first.result.completeError(
        const FormatException('actual failure'),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('actual failure'), findsOneWidget);
      expect(find.text('暂无匹配的公开内容'), findsNothing);
      await tester.tap(find.text('重试'));
      await tester.pump();
      expect(repo.requests.length, 2);
      repo.finish(1, 'Recovered');
      await tester.pumpAndSettle();
      expect(find.text('Recovered'), findsOneWidget);
    },
  );
}
