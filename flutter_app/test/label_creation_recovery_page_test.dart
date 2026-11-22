import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/label_creation_attempt.dart';
import 'package:bookstark_flutter/core/label_creation_controller.dart';
import 'package:bookstark_flutter/core/label_creation_store.dart';
import 'package:bookstark_flutter/features/labels/label_creation_recovery_page.dart';

Future<void> hit(WidgetTester tester, Finder target) async {
  final pageScroll = find.byType(Scrollable).first;
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(target, 80, scrollable: pageScroll);
  }
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  final ancestors = find.ancestor(
    of: target,
    matching: find.byType(Scrollable),
  );
  final scroll = ancestors.evaluate().isEmpty ? pageScroll : ancestors.first;
  for (var i = 0; i < 12 && target.hitTestable().evaluate().isEmpty; i++) {
    await tester.drag(scroll, const Offset(0, -60));
    await tester.pumpAndSettle();
  }
  expect(target.hitTestable(), findsOneWidget);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'EN320 200 percent keyboard shows exact global metadata and explicit end without POST',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      final values = <String, String>{};
      var posts = 0;
      final a = LabelCreationAttempt(
        scope: 'a' * 64,
        key: 'a' * 32,
        body: {'label_name': ' 研究/Flutter '},
        phase: LabelCreationPhase.unknown,
      );
      final store = LabelCreationStore(
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
      values[store.metadataKey] = a.encode();
      final wire = <String, Object?>{
        'label_id': 42,
        'label_name': a.body['label_name'],
        'book_count': 1,
        'blog_count': 1,
        'bookmark_count': 0,
        'document_count': 0,
        'relation_count': 2,
        'relations': [
          {
            'id': 1,
            'resource_id': 91,
            'relation_type': 'book',
            'created_at': '2026-11-11T01:00:00Z',
          },
          {
            'id': 2,
            'resource_id': 92,
            'relation_type': 'blog',
            'created_at': '2026-11-11T02:00:00Z',
          },
        ],
      };
      final display = jsonEncode(wire);
      final c = LabelCreationController(
        store: store,
        prepare: (_) async {
          posts++;
          throw StateError('No replay');
        },
        inspect: (_, id) async => LabelCreationReview(
          id: id,
          fingerprint: display,
          display: display,
          matchesFrozenInput: true,
          wire: wire,
        ),
      );
      try {
        await c.reload();
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(2),
                viewInsets: const EdgeInsets.only(bottom: 180),
              ),
              child: child!,
            ),
            home: LabelCreationRecoveryPage(
              controller: c,
              serverLabel: 'https://fixture.invalid',
              initiatorId: 7,
              english: true,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('16 / 100 UTF-8 bytes'),
          80,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('16 / 100 UTF-8 bytes'), findsOneWidget);
        // The frozen-name card can fill the small keyboard viewport; the actual
        // ID field is lazy-built later and must be reached before showKeyboard.
        final actualIdField = find.byType(TextField);
        await tester.scrollUntilVisible(
          actualIdField,
          80,
          scrollable: find.byType(Scrollable).first,
        );
        expect(actualIdField, findsOneWidget);
        await tester.ensureVisible(actualIdField);
        await tester.pumpAndSettle();
        await tester.enterText(actualIdField, '42');
        await hit(
          tester,
          find.widgetWithText(FilledButton, 'Review read only'),
        );
        expect(c.busy,isFalse);expect(c.error,isNull);
        expect(c.reviewed?.display,display);
        // Review replaces the long frozen-input panel. Its retained scroll
        // offset can now be below the newly inserted metadata card. Reach the
        // actual outer ListView top with real gestures before searching down.
        final outerScroll=find.descendant(of:find.byType(ListView),matching:find.byType(Scrollable)).first;
        for(var i=0;i<30;i++){
          final position=tester.state<ScrollableState>(outerScroll).position;
          if(position.pixels<=position.minScrollExtent+1)break;
          await tester.drag(outerScroll,const Offset(0,400));
          await tester.pumpAndSettle();
        }
        final topPosition=tester.state<ScrollableState>(outerScroll).position;
        expect(topPosition.pixels,lessThanOrEqualTo(topPosition.minScrollExtent+1));
        final full = find.byWidgetPredicate(
          (w) => w is SelectableText && w.data == display,
        );
        await tester.scrollUntilVisible(
          full,
          80,
          scrollable: outerScroll,
        );
        expect(full, findsOneWidget);
        expect(display, contains('"resource_id":92'));
        await hit(tester, find.widgetWithText(FilledButton, 'Adopt this ID'));
        expect(c.record!.origin, LabelCreationOrigin.manualExisting);
        expect(
          LabelCreationAttempt.decode(values.values.single).origin,
          LabelCreationOrigin.manualExisting,
        );
        await hit(
          tester,
          find.widgetWithText(OutlinedButton, 'End recovery record'),
        );
        expect(find.text('End recovery record?'), findsOneWidget);
        await hit(tester, find.widgetWithText(FilledButton, 'End record'));
        expect(values, isEmpty);
        expect(posts, 0);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        c.dispose();
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      }
    },
  );
  testWidgets('A confirmation cannot end B replacement ledger', (tester) async {
    final maps = [<String, String>{}, <String, String>{}];
    final controllers = <LabelCreationController>[];
    for (var i = 0; i < 2; i++) {
      final a = LabelCreationAttempt(
        scope: (i == 0 ? 'b' : 'c') * 64,
        key: (i == 0 ? 'b' : 'c') * 32,
        body: {'label_name': i == 0 ? 'A' : 'B'},
        phase: LabelCreationPhase.unknown,
      );
      final values = maps[i];
      final store = LabelCreationStore(
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
      values[store.metadataKey] = a.encode();
      final c = LabelCreationController(
        store: store,
        prepare: (_) async => throw StateError('No POST'),
        inspect: (_, _) async => throw StateError('No read'),
      );
      await c.reload();
      controllers.add(c);
    }
    Widget page(int i) => MaterialApp(
      home: LabelCreationRecoveryPage(
        controller: controllers[i],
        serverLabel: 'https://fixture.invalid',
        initiatorId: i + 1,
        english: true,
      ),
    );
    final before = maps.map((v) => Map<String, String>.of(v)).toList();
    try {
      await tester.pumpWidget(page(0));
      await tester.pumpAndSettle();
      await hit(
        tester,
        find.widgetWithText(OutlinedButton, 'End recovery record'),
      );
      await tester.pumpWidget(page(1));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'End record'));
      await tester.pumpAndSettle();
      expect(maps, before);
      expect(controllers[1].record!.body['label_name'], 'B');
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      for (final c in controllers) {
        c.dispose();
      }
    }
  });
}
