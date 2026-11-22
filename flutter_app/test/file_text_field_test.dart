import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/widgets/file_text_field.dart';

void main() {
  testWidgets(
    'native editor supports undo redo and preserves source newlines',
    (tester) async {
      final text = TextEditingController(text: '第一行\r\nsecond');
      final undo = UndoHistoryController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FileTextField(controller: text, undoController: undo),
          ),
        ),
      );
      final input = find.byKey(const ValueKey('file-content-input'));
      await tester.tap(input);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.enterText(input, '第一行\r\nsecond\n新增');
      await tester.pump(const Duration(milliseconds: 600));
      expect(text.text, '第一行\r\nsecond\n新增');
      expect(undo.value.canUndo, isTrue);
      undo.undo();
      await tester.pump();
      expect(text.text, '第一行\r\nsecond');
      undo.redo();
      await tester.pump();
      expect(text.text, '第一行\r\nsecond\n新增');
      await tester.pumpWidget(const SizedBox());
      text.dispose();
      undo.dispose();
    },
  );

  testWidgets(
    'wrapped long document stays editable at narrow width and 200 percent text',
    (tester) async {
      tester.view.resetPhysicalSize();
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final content = List.generate(
        80,
        (i) => '第$i行 很长的内容 abcdefghijklmnopqrstuvwxyz',
      ).join('\n');
      final text = TextEditingController(text: content);
      final undo = UndoHistoryController();
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: FileTextField(controller: text, undoController: undo),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      final scroll = find.byType(SingleChildScrollView);
      await tester.drag(scroll, const Offset(0, -480));
      await tester.pumpAndSettle();
      expect(
        tester
            .state<ScrollableState>(
              find
                  .descendant(of: scroll, matching: find.byType(Scrollable))
                  .first,
            )
            .position
            .pixels,
        greaterThan(0),
      );
      expect(text.text, content);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      text.dispose();
      undo.dispose();
    },
  );
}
