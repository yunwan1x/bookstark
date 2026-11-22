import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/local_assistant_creation_receipts.dart';
import 'package:bookstark_flutter/core/notes_repository.dart';
import 'package:bookstark_flutter/features/assistant/local_assistant_save_review_page.dart';

LocalAssistantCreationInspection review(
  String fingerprint, {
  LocalAssistantCreationResourceState state =
      LocalAssistantCreationResourceState.absent,
  Note? note,
}) => LocalAssistantCreationInspection(
  key: 'a' * 32,
  receipt: null,
  state: state,
  fingerprint: fingerprint,
  note: note,
);

void main() {
  testWidgets(
    'changed readback blocks resolution until the new content is reviewed',
    (tester) async {
      var current = review('first');
      var resolutions = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: LocalAssistantSaveReviewPage(
            inspect: () async => current,
            resolve: (_) async {
              resolutions++;
            },
            onOpenResource: (_) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      current = review('changed');
      await tester.tap(find.text('放弃这次保存尝试'));
      await tester.pumpAndSettle();
      expect(resolutions, 0);
      expect(find.text('资料状态已变化，请重新核对。'), findsOneWidget);
      await tester.tap(find.text('放弃这次保存尝试'));
      await tester.pumpAndSettle();
      expect(resolutions, 1);
    },
  );
  testWidgets('failed inspection cannot resolve or claim an empty result', (
    tester,
  ) async {
    var resolutions = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: LocalAssistantSaveReviewPage(
          inspect: () async => throw StateError('private details'),
          resolve: (_) async {
            resolutions++;
          },
          onOpenResource: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('private details'), findsNothing);
    expect(find.textContaining('暂时无法核对'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(resolutions, 0);
  });
  testWidgets(
    'large text remains scrollable and complex resource bodies stay hidden',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var opened = 0;
      final value = review(
        'html',
        state: LocalAssistantCreationResourceState.formatChanged,
      );
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: LocalAssistantSaveReviewPage(
            english: true,
            inspect: () async => value,
            resolve: (_) async {},
            onOpenResource: (_) async {
              opened++;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Open resource'),
        150,
        scrollable: find.byType(Scrollable),
      );
      await tester.ensureVisible(find.text('Open resource'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open resource'));
      await tester.pumpAndSettle();
      expect(opened, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
