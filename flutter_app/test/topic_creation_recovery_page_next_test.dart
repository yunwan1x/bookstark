import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/topic_creation_attempt.dart';
import 'package:bookstark_flutter/core/topic_creation_controller.dart';
import 'package:bookstark_flutter/core/topic_creation_store.dart';
import 'package:bookstark_flutter/features/topics/topic_creation_recovery_page.dart';

void main() {
  testWidgets('A end confirmation cannot apply to replacement B controller', (
    tester,
  ) async {
    final values = <String, String>{}, scope = 'e' * 64;
    TopicCreationController make(String key) {
      final store = TopicCreationStore(
        scope: scope,
        key: key,
        read: (k) async => values[k],
        write: (k, v) async {
          values[k] = v;
        },
        remove: (k) async {
          values.remove(k);
        },
        flush: () async {},
        isCurrent: () => true,
      );
      final attempt = TopicCreationAttempt(
        scope: scope,
        key: key,
        kind: TopicCreationKind.topic,
        topicId: 0,
        target: '',
        targetId: 0,
        body: {'title': key, 'question': 'Exact\r\n😀', 'is_pinned': false},
        phase: TopicCreationPhase.unknown,
      );
      values[store.metadataKey] = attempt.encode();
      return TopicCreationController(
        store: store,
        prepare: (_) async => throw StateError('No POST allowed'),
        inspect: (_, id) async => throw StateError('No implicit read'),
      );
    }

    final a = make('f' * 32), b = make('a' * 32);
    try {
      await tester.runAsync(() async {
        await a.reload();
        await b.reload();
      });
      final before = Map<String, String>.of(values);
      await tester.pumpWidget(
        MaterialApp(home: TopicCreationRecoveryPage(controller: a)),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('结束恢复记录'),
        120,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.text('结束恢复记录'));
      await tester.pumpAndSettle();
      expect(find.text('结束恢复记录？'), findsOneWidget);
      await tester.pumpWidget(
        MaterialApp(home: TopicCreationRecoveryPage(controller: b)),
      );
      await tester.pump();
      await tester.tap(find.text('确认结束'));
      await tester.pumpAndSettle();
      expect(values, before);
      expect(b.record!.key, 'a' * 32);
      // An old controller notification cannot replace B's actual source.
      await tester.runAsync(a.reload);
      await tester.pump();
      expect(
        find.byWidgetPredicate(
          (w) => w is SelectableText && w.data?.contains('a' * 32) == true,
        ),
        findsOneWidget,
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      a.dispose();
      b.dispose();
    }
  });
  testWidgets('EN320 large text unknown actions remain reachable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    final scope = 'c' * 64, key = 'd' * 32, values = <String, String>{};
    final store = TopicCreationStore(
      scope: scope,
      key: key,
      read: (k) async => values[k],
      write: (k, v) async {
        values[k] = v;
      },
      remove: (k) async {
        values.remove(k);
      },
      flush: () async {},
      isCurrent: () => true,
    );
    final attempt = TopicCreationAttempt(
      scope: scope,
      key: key,
      kind: TopicCreationKind.comment,
      topicId: 9,
      target: 'summary',
      targetId: 3,
      body: {
        'content': 'Complete source\r\n😀',
        'target_type': 'summary',
        'target_id': 3,
        'parent_comment_id': 0,
      },
      phase: TopicCreationPhase.unknown,
    );
    values[store.metadataKey] = attempt.encode();
    final c = TopicCreationController(
      store: store,
      prepare: (_) async => throw StateError('No POST'),
      inspect: (_, id) async => TopicCreationReview(
        id: id,
        fingerprint: 'f' * 64,
        display: 'Full actual content\r\n😀',
        matchesFrozenInput: true,
        wire: const {},
      ),
    );
    try {
      await tester.runAsync(c.reload);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: TopicCreationRecoveryPage(controller: c, english: true),
        ),
      );
      await tester.pumpAndSettle();
      final scroll = find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.text('Actual resource ID'),
        180,
        scrollable: scroll,
      );
      await tester.enterText(find.byType(TextField), '12');
      await tester.scrollUntilVisible(
        find.text('Review read only'),
        100,
        scrollable: scroll,
      );
      await tester.tap(find.text('Review read only'));
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is SelectableText &&
              w.data?.contains('Full actual content') == true,
        ),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.text('Adopt this ID'),
        120,
        scrollable: scroll,
      );
      expect(find.text('Adopt this ID').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      c.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }
  });
}
