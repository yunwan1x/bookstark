import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/label_creation_attempt.dart';
import 'package:bookstark_flutter/core/label_creation_controller.dart';
import 'package:bookstark_flutter/core/local_label_creation_controller.dart';
import 'package:bookstark_flutter/core/local_label_creation_store.dart';
import 'package:bookstark_flutter/features/labels/label_creation_recovery_page.dart';

Future<void> press(WidgetTester tester, Finder target) async {
  final scroll = find.byType(Scrollable).first;
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(target, 70, scrollable: scroll);
  }
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  for (var i = 0; i < 12 && target.hitTestable().evaluate().isEmpty; i++) {
    final parents = find.ancestor(
      of: target,
      matching: find.byType(Scrollable),
    );
    await tester.drag(
      parents.evaluate().isEmpty ? scroll : parents.first,
      const Offset(0, -60),
    );
    await tester.pumpAndSettle();
  }
  expect(target.hitTestable(), findsOneWidget);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'local EN320200 keyboard read-only adoption never claims HTTP or atomic cold proof',
    (tester) async {
      tester.view.physicalSize = const Size(320, 760);
      tester.view.devicePixelRatio = 1;
      final values = <String, String>{};
      var sqlCalls = 0;
      final a = LabelCreationAttempt(
        scope: '5' * 64,
        key: '5' * 32,
        body: {'label_name': 'Exact 😀'},
        phase: LabelCreationPhase.unknown,
      );
      final journal = LocalLabelCreationStore(
        scope: a.scope,
        key: a.key,
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
      values[journal.metadataKey] = a.encode();
      const display =
          '{"label_id":42,"label_name":"Exact 😀","relation_count":1,"relations":[{"resource_id":7,"relation_type":"document","modify_time":12}]}';
      final c = LocalLabelCreationController(
        store: journal,
        create: (_) async {
          sqlCalls++;
          throw StateError('No replay');
        },
        inspect: (_, id) async => LabelCreationReview(
          id: id,
          fingerprint: display,
          display: display,
          matchesFrozenInput: true,
          wire: {'label_id': id, 'label_name': 'Exact 😀', 'relation_count': 1},
        ),
      );
      try {
        await c.reload();
        await tester.pumpWidget(
          MaterialApp(
            builder: (ctx, child) => MediaQuery(
              data: MediaQuery.of(ctx).copyWith(
                textScaler: const TextScaler.linear(2),
                viewInsets: const EdgeInsets.only(bottom: 180),
              ),
              child: child!,
            ),
            home: LabelCreationRecoveryPage(
              controller: c,
              local: true,
              serverLabel: 'local-generation:${'6' * 32}',
              initiatorId: 0,
              english: true,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Local space'), findsOneWidget);
        expect(find.text('Current server'), findsNothing);
        expect(find.textContaining('Initiating account'), findsNothing);
        await tester.scrollUntilVisible(
          find.byType(TextField),
          70,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.enterText(find.byType(TextField), '42');
        await press(
          tester,
          find.widgetWithText(FilledButton, 'Review read only'),
        );
        await press(tester, find.widgetWithText(FilledButton, 'Adopt this ID'));
        expect(c.record!.origin, LabelCreationOrigin.manualExisting);
        final notice = find.text(
          'Existing local label explicitly adopted; this is not creation proof.',
        );
        await tester.scrollUntilVisible(
          notice,
          70,
          scrollable: find.byType(Scrollable).first,
        );
        expect(notice, findsOneWidget);
        expect(find.textContaining('actual POST ID'), findsNothing);
        await press(
          tester,
          find.widgetWithText(OutlinedButton, 'End recovery record'),
        );
        expect(
          find.text(
            'This does not prove local creation never happened. No local label or association will be deleted.',
          ),
          findsOneWidget,
        );
        await press(tester, find.widgetWithText(FilledButton, 'End record'));
        expect(values, isEmpty);
        expect(sqlCalls, 0);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        c.dispose();
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      }
    },
  );
}
