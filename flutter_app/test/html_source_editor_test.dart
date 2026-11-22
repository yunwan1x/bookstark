import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';
import 'package:bookstark_flutter/features/html/html_source_editor.dart';

Future<void> open(
  WidgetTester tester,
  String source,
  ValueChanged<String> changed, {
  bool readOnly = false,
  bool narrow = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(narrow ? 320 : 780, 800),
          textScaler: TextScaler.linear(narrow ? 2 : 1),
        ),
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: narrow ? 320 : 700,
              height: 700,
              child: HtmlSourceEditor(
                source: source,
                onChanged: changed,
                readOnly: readOnly,
                english: true,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Flutter line-number editor and wrap toggle do not mutate initial exact source',
    (tester) async {
      final changes = <String>[];
      await open(tester, '<p>你好</p>\r\n<script>run()</script>', changes.add);
      expect(find.byType(CodeEditor), findsOneWidget);
      expect(find.byType(DefaultCodeLineNumber), findsOneWidget);
      await tester.tap(find.byTooltip('Word wrap'));
      await tester.pump();
      expect(
        tester.widget<CodeEditor>(find.byType(CodeEditor)).wordWrap,
        isTrue,
      );
      expect(changes, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'real text-input channel edits Unicode source and native toolbar undo/redo restores it',
    (tester) async {
      final changes = <String>[];
      await open(tester, '', changes.add);
      await tester.tap(find.byType(CodeEditor));
      await tester.pump();
      expect(tester.testTextInput.hasAnyClients, isTrue);
      // Android's requested delta protocol, through the real platform channel.
      final state = tester.testTextInput.editingState!;
      final client =
          tester.testTextInput.log
                  .lastWhere((c) => c.method == 'TextInput.setClient')
                  .arguments
              as List;
      expect((client[1] as Map)['enableDeltaModel'], isTrue);
      final oldText = state['text'] as String;
      final offset = state['selectionBase'] as int;
      const inserted = '<p>你好 🌍</p>';
      tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        SystemChannels.textInput.name,
        const JSONMethodCodec().encodeMethodCall(
          MethodCall('TextInputClient.updateEditingStateWithDeltas', [
            client[0],
            {
              'deltas': [
                {
                  'oldText': oldText,
                  'deltaText': inserted,
                  'deltaStart': offset,
                  'deltaEnd': offset,
                  'selectionBase': offset + inserted.length,
                  'selectionExtent': offset + inserted.length,
                  'composingBase': -1,
                  'composingExtent': -1,
                },
              ],
            },
          ]),
        ),
        (_) {},
      );
      await tester.pump();
      expect(changes.last, '<p>你好 🌍</p>');
      await tester.tap(find.byTooltip('Undo'));
      await tester.pump();
      expect(changes.last, '');
      await tester.tap(find.byTooltip('Redo'));
      await tester.pump();
      expect(changes.last, '<p>你好 🌍</p>');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'actual find fields and replace-all retain original CRLF source',
    (tester) async {
      final changes = <String>[];
      await open(tester, '<p>foo</p>\r\n<p>foo</p>', changes.add);
      await tester.tap(find.byTooltip('Find and replace'));
      await tester.pump();
      await tester.enterText(find.byKey(const ValueKey('html-find')), 'foo');
      await tester.pump(const Duration(milliseconds: 400));
      for (
        var i = 0;
        i < 40 && find.text('2 matches').evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('2 matches'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('html-replace')), 'bar');
      await tester.pump();
      await tester.tap(find.text('Replace all'));
      await tester.pump();
      expect(changes.last, '<p>bar</p>\r\n<p>bar</p>');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'read-only narrow double-text editor exposes find and wrap but cannot replace',
    (tester) async {
      final changes = <String>[];
      await open(
        tester,
        '<h1>Protected review</h1>',
        changes.add,
        readOnly: true,
        narrow: true,
      );
      await tester.tap(find.byTooltip('Find and replace'));
      await tester.pump();
      expect(find.byKey(const ValueKey('html-find')), findsOneWidget);
      expect(find.byKey(const ValueKey('html-replace')), findsNothing);
      expect(
        tester.widget<CodeEditor>(find.byType(CodeEditor)).readOnly,
        isTrue,
      );
      expect(changes, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
