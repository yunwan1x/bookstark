import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/task_creation_attempt.dart';
import 'package:bookstark_flutter/core/task_creation_store.dart';
import 'package:bookstark_flutter/core/task_creation_controller.dart';
import 'package:bookstark_flutter/features/tasks/task_creation_recovery_page.dart';

void main() {
  for (final narrow in [false, true]) {
    testWidgets(
      'explicit owned ID adoption never creates task EN320/font2/IME=$narrow',
      (tester) async {
        tester.view.physicalSize = Size(narrow ? 320 : 390, 800);
        tester.view.devicePixelRatio = 1;
        final scope = '7' * 64, key = '8' * 32;
        final unknown = TaskCreationAttempt(
          scope: scope,
          key: key,
          phase: TaskCreationPhase.unknown,
          body: {
            'content': 'Frozen actual full body',
            'due_date': '2026-11-20',
            'done': true,
            'parent_id': 7,
            'topic_id': 9,
          },
        );
        String? raw = unknown.encode();
        var prepares = 0, reads = 0;
        final store = TaskCreationStore(
          scope: scope,
          key: key,
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
          prepare: (_) async {
            prepares++;
            throw StateError('must never create');
          },
          inspect: (_, id) async {
            reads++;
            return TaskCreationReview(
              id: id,
              fingerprint: 'actual-stable-version',
              display: 'Actual content / parent 7 / topic 9',
              matchesFrozenInput: true,
              wire: {'content': 'Frozen actual full body'},
            );
          },
        );
        try {
          await c.reload();
          await tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(
                  size: Size(narrow ? 320 : 390, 800),
                  textScaler: TextScaler.linear(narrow ? 2 : 1),
                  viewInsets: EdgeInsets.only(bottom: narrow ? 180 : 0),
                ),
                child: TaskCreationRecoveryPage(
                  controller: c,
                  serverLabel: 'Fixture server',
                  initiatorId: 7,
                  english: true,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('Frozen actual full body'), findsOneWidget);
          expect(find.text('Submit this draft'), findsNothing);
          final field = find.byType(TextField);
          await tester.ensureVisible(field);
          await tester.enterText(field, '41');
          final review = find.widgetWithText(FilledButton, 'Review read only');
          await tester.ensureVisible(review);
          await tester.tap(review);
          await tester.pumpAndSettle();
          final adopt = find.widgetWithText(FilledButton, 'Adopt this ID');
          await tester.ensureVisible(adopt);
          await tester.tap(adopt);
          await tester.pumpAndSettle();
          expect(reads, 2);
          expect(prepares, 0);
          expect(c.record!.actualId, 41);
          expect(c.record!.origin, TaskCreationOrigin.manualExisting);
          expect(c.record!.body['content'], 'Frozen actual full body');
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
}
