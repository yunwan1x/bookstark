import 'dart:async';

import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/local_complex_notes_repository.dart';
import 'package:bookstark_flutter/features/complex_editors/complex_recovery_review_page.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final platformViewCalls = <MethodCall>[];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

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
    'source mode requires viewing both versions before returning keep-draft intent',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      final routeResult = await _openReview(tester);
      _expectDisabled(tester);

      await _tapSource(tester);
      expect(find.text(_saved.document.source), findsOneWidget);
      _expectDisabled(tester);

      await tester.tap(find.text('本机草稿'));
      await tester.pumpAndSettle();
      await _tapSource(tester);
      expect(find.text(_draft.document.source), findsOneWidget);
      _expectEnabled(tester);

      await tester.tap(find.text('保留草稿继续编辑'));
      await tester.pumpAndSettle();
      expect(await routeResult.future, ComplexRecoveryChoice.keepDraft);
      expect(platformViewCalls, isEmpty);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'use-saved returns only an intent after both raw versions were viewed',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      final routeResult = await _openReview(tester);
      await _reviewBothSources(tester);
      _expectEnabled(tester);

      await tester.tap(find.text('采用已保存版本'));
      await tester.pumpAndSettle();
      expect(await routeResult.future, ComplexRecoveryChoice.useSaved);
      expect(platformViewCalls, isEmpty);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'app-bar back cancels without choosing or invoking platform storage',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      final routeResult = await _openReview(tester);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(await routeResult.future, isNull);
      expect(platformViewCalls, isEmpty);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'source chunks preserve a surrogate pair crossing the 4096 UTF-16 boundary',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final source = '${'a' * 4095}😀${'b' * 4100}';

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ComplexSourceView(source: source)),
        ),
      );
      await tester.pumpAndSettle();

      final chunks = tester
          .widgetList<SelectableText>(find.byType(SelectableText))
          .map((widget) => widget.data!)
          .toList();
      expect(chunks, hasLength(3));
      expect(chunks.first.length, 4095);
      final lastUnit = chunks.first.codeUnitAt(chunks.first.length - 1);
      expect(lastUnit < 0xd800 || lastUnit > 0xdbff, isTrue);
      expect(chunks.join(), source);
    },
  );

  testWidgets(
    'near-20-MiB raw source is displayed in bounded lazy text nodes',
    (tester) async {
      final source = 'x' * (20 * 1024 * 1024);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ComplexSourceView(source: source)),
        ),
      );
      await tester.pump();

      final visible = tester
          .widgetList<SelectableText>(find.byType(SelectableText))
          .toList();
      expect(visible, isNotEmpty);
      expect(visible.length, lessThan(16));
      expect(visible.every((widget) => widget.data!.length <= 4096), isTrue);
    },
  );
}

Future<Completer<ComplexRecoveryChoice?>> _openReview(
  WidgetTester tester,
) async {
  final routeResult = Completer<ComplexRecoveryChoice?>();
  await tester.pumpWidget(
    MaterialApp(
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
                    .then(routeResult.complete);
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
  return routeResult;
}

Future<void> _tapSource(WidgetTester tester) async {
  await tester.tap(find.text('原文'));
  await tester.pumpAndSettle();
}

Future<void> _reviewBothSources(WidgetTester tester) async {
  await _tapSource(tester);
  expect(find.text(_saved.document.source), findsOneWidget);
  await tester.tap(find.text('本机草稿'));
  await tester.pumpAndSettle();
  await _tapSource(tester);
  expect(find.text(_draft.document.source), findsOneWidget);
}

void _expectDisabled(WidgetTester tester) {
  expect(
    tester
        .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '保留草稿继续编辑'))
        .onPressed,
    isNull,
  );
  expect(
    tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, '采用已保存版本'))
        .onPressed,
    isNull,
  );
}

void _expectEnabled(WidgetTester tester) {
  expect(
    tester
        .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '保留草稿继续编辑'))
        .onPressed,
    isNotNull,
  );
  expect(
    tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, '采用已保存版本'))
        .onPressed,
    isNotNull,
  );
}

final _saved = ComplexNote(
  scope: 'a' * 64,
  id: 31,
  collection: 'note',
  title: '已保存版本',
  document: ComplexEditorDocument.parse(
    ComplexEditorKind.html,
    '<!doctype html>\r\n<p>已保存📘</p>\r\n',
  ),
  version: 100,
  labels: const ['saved'],
);

final _draft = ComplexNoteEdit(
  title: '本机草稿版本',
  document: ComplexEditorDocument.parse(
    ComplexEditorKind.html,
    '<!doctype html>\r\n<p>草稿😀</p>\r\n',
  ),
  labels: const ['draft'],
);
