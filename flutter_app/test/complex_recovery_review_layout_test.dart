import 'dart:async';

import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/local_complex_notes_repository.dart';
import 'package:bookstark_flutter/features/complex_editors/complex_recovery_review_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final platformViewCalls = <MethodCall>[];

  setUp(() {
    platformViewCalls.clear();
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
      call,
    ) async {
      platformViewCalls.add(call);
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
  });

  testWidgets(
    'max metadata remains scrollable at 320dp and 200% text scale, both versions and action stay reachable',
    (tester) async {
      // 640 physical pixels at DPR 2 gives a 320dp-wide, 640dp-tall viewport.
      tester.view.physicalSize = const Size(640, 1280);
      tester.view.devicePixelRatio = 2;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final result = Completer<ComplexRecoveryChoice?>();
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () {
                    Navigator.of(context)
                        .push<ComplexRecoveryChoice>(
                          MaterialPageRoute(
                            builder: (_) => ComplexRecoveryReviewPage(
                              saved: _saved,
                              draft: _draft,
                            ),
                          ),
                        )
                        .then(result.complete);
                  },
                  child: const Text('Open review'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open review'));
      await tester.pumpAndSettle();

      expect(find.byType(ComplexRecoveryReviewPage), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Review the saved version in raw mode so this layout test never depends
      // on a platform WebView.
      await tester.ensureVisible(find.text('原文'));
      await tester.tap(find.text('原文'));
      await tester.pumpAndSettle();
      expect(find.text(_saved.document.source), findsOneWidget);

      // Reach metadata at the far end of the 100-chip list. The title and first
      // label must remain reachable after scrolling back to the start.
      await tester.ensureVisible(find.text(_saved.labels.last));
      await tester.pumpAndSettle();
      _expectOnScreen(tester, find.text(_saved.labels.last));
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(find.text(_saved.title));
      await tester.pumpAndSettle();
      _expectOnScreen(tester, find.text(_saved.title));
      await tester.ensureVisible(find.text(_saved.labels.first));
      await tester.pumpAndSettle();
      _expectOnScreen(tester, find.text(_saved.labels.first));

      // Switching versions resets raw mode; select raw again immediately.
      await tester.ensureVisible(find.text('本机草稿'));
      await tester.tap(find.text('本机草稿'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('原文'));
      await tester.tap(find.text('原文'));
      await tester.pumpAndSettle();
      expect(find.text(_draft.document.source), findsOneWidget);

      await tester.ensureVisible(find.text(_draft.title));
      await tester.pumpAndSettle();
      _expectOnScreen(tester, find.text(_draft.title));
      await tester.ensureVisible(find.text(_draft.labels.last));
      await tester.pumpAndSettle();
      _expectOnScreen(tester, find.text(_draft.labels.last));

      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, '保留草稿继续编辑'),
            )
            .onPressed,
        isNotNull,
      );
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '采用已保存版本'))
            .onPressed,
        isNotNull,
      );
      await tester.ensureVisible(find.text('采用已保存版本'));
      await tester.tap(find.text('采用已保存版本'));
      await tester.pumpAndSettle();
      expect(await result.future, ComplexRecoveryChoice.useSaved);
      expect(platformViewCalls, isEmpty);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );
}

void _expectOnScreen(WidgetTester tester, Finder finder) {
  final rect = tester.getRect(finder);
  final logicalSize = tester.view.physicalSize / tester.view.devicePixelRatio;
  expect(rect.top, greaterThanOrEqualTo(0));
  expect(rect.bottom, lessThanOrEqualTo(logicalSize.height));
}

final _labels = List<String>.generate(
  100,
  (index) => "${List<String>.filled(10, '标签😀').join()}-$index",
  growable: false,
);

final _saved = ComplexNote(
  scope: 'a' * 64,
  id: 32,
  collection: 'note',
  title: List<String>.filled(50, '📘').join(), // 200 UTF-8 bytes.
  document: ComplexEditorDocument.parse(
    ComplexEditorKind.html,
    '<!doctype html>\r\n<p>Saved version</p>\r\n',
  ),
  version: 100,
  labels: _labels,
);

final _draft = ComplexNoteEdit(
  title: List<String>.filled(20, '🌿草稿').join(), // 200 UTF-8 bytes.
  document: ComplexEditorDocument.parse(
    ComplexEditorKind.html,
    '<!doctype html>\r\n<p>Local draft</p>\r\n',
  ),
  labels: _labels,
);
