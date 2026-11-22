import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/features/html/html_preview.dart';

Future<void> open(
  WidgetTester tester,
  String source, {
  bool english = false,
  ValueChanged<Uri>? link,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: NativeHtmlPreview(
            source: source,
            english: english,
            onOpenLink: link,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'real HTML heading, paragraphs, lists and table become native selectable structure',
    (tester) async {
      await open(
        tester,
        '<article><h1>周末旅行</h1><p>清晰的<strong>计划</strong></p><ul><li>确认车票</li><li>整理行李</li></ul><table><tr><th>事项</th><th>状态</th></tr><tr><td>车票</td><td>已完成</td></tr></table></article>',
      );
      expect(find.text('周末旅行'), findsOneWidget);
      expect(find.textContaining('清晰的', findRichText: true), findsWidgets);
      expect(find.text('确认车票', findRichText: true), findsWidgets);
      expect(find.byType(Table), findsOneWidget);
      expect(find.byType(SelectionArea), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'scripts, frames, styles, hidden data and form controls are inert and external images never create an image provider',
    (tester) async {
      await open(
        tester,
        '<p>Visible</p><script>FORBIDDEN_SCRIPT</script><style>FORBIDDEN_STYLE</style><iframe src="https://tracking.test/"><p>FORBIDDEN_FRAME</p></iframe><div hidden>FORBIDDEN_HIDDEN</div><form action="https://tracking.test/"><input value="FORBIDDEN_INPUT"><button>FORBIDDEN_SUBMIT</button><p>Form explanation</p></form><img src="https://tracking.test/pixel.png" alt="sample">',
      );
      expect(find.text('Visible', findRichText: true), findsWidgets);
      expect(find.text('Form explanation', findRichText: true), findsWidgets);
      for (final value in [
        'FORBIDDEN_SCRIPT',
        'FORBIDDEN_STYLE',
        'FORBIDDEN_FRAME',
        'FORBIDDEN_HIDDEN',
        'FORBIDDEN_INPUT',
        'FORBIDDEN_SUBMIT',
      ]) {
        expect(find.textContaining(value, findRichText: true), findsNothing);
      }
      expect(find.byType(Image), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(Form), findsNothing);
      expect(find.text('图片未加载: sample'), findsOneWidget);
    },
  );
  testWidgets(
    'only explicit safe link taps call the host, while script data and credential-bearing links stay inert',
    (tester) async {
      final opened = <Uri>[];
      await open(
        tester,
        '<p><a href="/notes/7">Open native</a> <a href="javascript:alert(1)">Bad script</a> <a href="data:text/html,script">Bad data</a> <a href="https://user:password@example.test/">Bad credentials</a></p>',
        link: opened.add,
      );
      expect(opened, isEmpty);
      expect(find.byType(TextButton), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Open native'));
      await tester.pump();
      expect(opened, [Uri.parse('/notes/7')]);
    },
  );
  testWidgets(
    'code preserves literal markup and disclosure opens only through native control',
    (tester) async {
      await open(
        tester,
        '<pre>&lt;script&gt;sample&lt;/script&gt;\n  two spaces</pre><details><summary>Details</summary><p>Hidden until opened</p></details>',
      );
      expect(
        find.text('<script>sample</script>\n  two spaces'),
        findsOneWidget,
      );
      expect(find.byType(ExpansionTile), findsOneWidget);
      await tester.tap(find.text('Details'));
      await tester.pumpAndSettle();
      expect(
        find.text('Hidden until opened', findRichText: true),
        findsWidgets,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'large or deeply nested previews explain the bound, and source updates replace the prior tree',
    (tester) async {
      await open(
        tester,
        "${List.filled(49, '<div>').join()}Deep${List.filled(49, '</div>').join()}",
      );
      expect(find.textContaining('内容较大或结构复杂'), findsOneWidget);
      await open(tester, 'x' * 500001);
      expect(find.textContaining('内容较大或结构复杂'), findsOneWidget);
      await open(tester, '<h1>New source</h1><p>Current text</p>');
      expect(find.text('New source'), findsOneWidget);
      expect(find.textContaining('内容较大或结构复杂'), findsNothing);
    },
  );
  testWidgets(
    'English narrow200 percent table and ordinary content remain native and scroll without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await open(
        tester,
        '<h1>A weekend itinerary</h1><p>Prepare your trip carefully.</p><ol start="3"><li>Confirm tickets and accommodation</li></ol><table><tr><th>Task</th><th>Status</th></tr><tr><td>Tickets</td><td>Completed</td></tr></table>',
        english: true,
      );
      expect(find.byType(Table), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
