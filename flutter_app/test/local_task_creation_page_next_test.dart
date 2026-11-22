import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/task_creation_attempt.dart';
import 'package:bookstark_flutter/core/task_creation_store.dart';
import 'package:bookstark_flutter/core/task_creation_controller.dart';
import 'package:bookstark_flutter/features/tasks/task_creation_recovery_page.dart';

void main() {
  testWidgets(
    'local EN320/font2/IME receipt lookup needs no guessed ID and cannot create',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      final a = TaskCreationAttempt(
        scope: 'a' * 64,
        key: 'b' * 32,
        phase: TaskCreationPhase.unknown,
        body: {
          'content': 'Complete local submitted task',
          'due_date': '2026-11-20',
          'done': true,
          'parent_id': 7,
          'topic_id': 9,
        },
      );
      String? raw = a.encode();
      var inserts = 0, inspections = 0;
      final store = TaskCreationStore(
        scope: a.scope,
        key: a.key,
        local: true,
        read: (_) async => raw,
        write: (_, v) async {
          raw = v;
        },
        remove: (_) async {
          raw = null;
        },
        flush: () async {},
        isCurrent: () => true,
      );
      final c = TaskCreationController(
        store: store,
        local: true,
        localSubmit: (_, _) async {
          inserts++;
          return 41;
        },
        inspect: (_, id) async {
          inspections++;
          expect([0, 41], contains(id));
          return const TaskCreationReview(
            id: 41,
            fingerprint: 'receipt-full-tuple',
            display: 'Actual atomic task receipt / parent 7 / topic 9',
            matchesFrozenInput: true,
            wire: {'content': 'Complete local submitted task'},
          );
        },
      );
      try {
        await c.reload();
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(320, 800),
                textScaler: TextScaler.linear(2),
                viewInsets: EdgeInsets.only(bottom: 180),
              ),
              child: TaskCreationRecoveryPage(
                controller: c,
                local: true,
                english: true,
                serverLabel: 'Owned local space',
                initiatorId: 0,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(TextField), findsNothing);
        final review = find.widgetWithText(
          FilledButton,
          'Review local atomic receipt',
        );
        await tester.ensureVisible(review);
        await tester.tap(review);
        await tester.pumpAndSettle();
        final confirm = find.widgetWithText(
          FilledButton,
          'Confirm local receipt',
        );
        await tester.ensureVisible(confirm);
        await tester.tap(confirm);
        await tester.pumpAndSettle();
        expect(
          c.record!.origin,
          TaskCreationOrigin.localTransactionAcknowledgement,
        );
        expect(c.record!.actualId, 41);
        expect(inserts, 0);
        expect(inspections, 2);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        c.dispose();
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      }
    },
  );
}
