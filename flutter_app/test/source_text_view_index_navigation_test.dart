import 'package:bookstark_flutter/features/complex_editors/source_chunks.dart';
import 'package:bookstark_flutter/features/complex_editors/source_text_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _dragIndexTo(
  WidgetTester tester, {
  required int count,
  required double fromFraction,
  required double toFraction,
}) async {
  final bar = find.byKey(const ValueKey('source-index-scrollbar'));
  expect(bar, findsOneWidget);
  final rect = tester.getRect(bar);
  final extent = rect.height / count > 48 ? rect.height / count : 48.0;
  final travel = rect.height - extent;
  final startY = rect.top + fromFraction * travel + extent / 2;
  final endY = rect.top + toFraction * travel + extent / 2;
  await tester.dragFrom(
    Offset(rect.center.dx, startY),
    Offset(0, endY - startY),
  );
  await tester.pumpAndSettle();
}

String _heading(int index, int count) => '原文 · 第 ${index + 1} / $count 段';

void main() {
  testWidgets(
    'index bar jumps first to last and back while keeping only nearby chunks built',
    (tester) async {
      final source = List<String>.generate(
        240,
        (index) => 'row-$index ${'😀中' * 1500}',
      ).join('\n');
      final chunks = SourceChunks(source);
      expect(chunks.length, greaterThan(100));

      tester.view.physicalSize = const Size(420, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SourceTextView(source: source, decorated: true)),
        ),
      );

      expect(find.text(_heading(0, chunks.length)), findsOneWidget);
      expect(
        tester.widgetList<SelectableText>(find.byType(SelectableText)).length,
        lessThan(10),
      );

      await _dragIndexTo(
        tester,
        count: chunks.length,
        fromFraction: 0,
        toFraction: 1,
      );
      expect(
        find.text(_heading(chunks.length - 1, chunks.length)),
        findsOneWidget,
      );
      var bodies = tester.widgetList<SelectableText>(
        find.byType(SelectableText),
      );
      expect(bodies, isNotEmpty);
      expect(bodies.length, lessThan(10));
      expect(bodies.every((body) => body.data!.length <= 4096), isTrue);
      expect(
        bodies.any((body) => body.data == chunks.at(chunks.length - 1)),
        isTrue,
      );

      await _dragIndexTo(
        tester,
        count: chunks.length,
        fromFraction: 1,
        toFraction: 0,
      );
      expect(find.text(_heading(0, chunks.length)), findsOneWidget);
      bodies = tester.widgetList<SelectableText>(find.byType(SelectableText));
      expect(bodies.length, lessThan(10));
      expect(bodies.every((body) => body.data!.length <= 4096), isTrue);
    },
  );

  testWidgets(
    'centered source anchor can be read naturally into earlier chunks',
    (tester) async {
      final source = List<String>.generate(
        180,
        (index) => 'entry-$index ${'body text 😀中\n' * 900}',
      ).join('\n');
      final chunks = SourceChunks(source);
      final anchor = chunks.length ~/ 2;

      tester.view.physicalSize = const Size(420, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SourceTextView(source: source, decorated: true)),
        ),
      );
      await _dragIndexTo(
        tester,
        count: chunks.length,
        fromFraction: 0,
        toFraction: anchor / (chunks.length - 1),
      );
      expect(find.text(_heading(anchor, chunks.length)), findsOneWidget);

      final viewport = find.byType(CustomScrollView);
      final previousHeading = find.text(_heading(anchor - 1, chunks.length));
      for (
        var attempt = 0;
        attempt < 12 && previousHeading.evaluate().isEmpty;
        attempt++
      ) {
        await tester.drag(viewport, const Offset(0, 280));
        await tester.pumpAndSettle();
      }
      expect(
        previousHeading,
        findsOneWidget,
        reason: 'a downward reading gesture should expose the preceding chunk',
      );
      var bodies = tester.widgetList<SelectableText>(
        find.byType(SelectableText),
      );
      expect(bodies.length, lessThan(10));
      expect(bodies.every((body) => body.data!.length <= 4096), isTrue);

      for (
        var attempt = 0;
        attempt < 12 &&
            find.text(_heading(anchor, chunks.length)).evaluate().isEmpty;
        attempt++
      ) {
        await tester.drag(viewport, const Offset(0, -280));
        await tester.pumpAndSettle();
      }
      expect(find.text(_heading(anchor, chunks.length)), findsOneWidget);
      bodies = tester.widgetList<SelectableText>(find.byType(SelectableText));
      expect(bodies.length, lessThan(10));
      expect(bodies.every((body) => body.data!.length <= 4096), isTrue);
    },
  );
}
