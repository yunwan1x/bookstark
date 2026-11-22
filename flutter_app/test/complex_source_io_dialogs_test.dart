// NOT RUN. Widget drafts do not prove real system picker/SAF or lifecycle.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/native_complex_source_io.dart';
import 'package:bookstark_flutter/features/complex_editors/complex_source_io_dialogs.dart';

void main() {
  testWidgets(
    'source sheet exposes source actions only, no fabricated Office export',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showComplexSourceIoSheet(
                  context,
                  format: 'drawing JSON',
                  english: true,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Import same-format source'), findsOneWidget);
      expect(find.text('Export current source'), findsOneWidget);
      expect(find.textContaining('No Office conversion'), findsOneWidget);
      expect(find.text('PPTX'), findsNothing);
      expect(find.text('XLSX'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    '320dp 200 percent keyboard inset import needs actual checkbox confirmation',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
              viewInsets: const EdgeInsets.only(bottom: 180),
            ),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await confirmComplexSourceImport(
                    context,
                    ComplexSourceFile(
                      name: 'exact-source.json',
                      document: ComplexEditorDocument.parse(
                        ComplexEditorKind.drawing,
                        '{"elements":[]}',
                      ),
                    ),
                    english: true,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final accept = find.widgetWithText(FilledButton, 'Import as draft');
      expect(tester.widget<FilledButton>(accept).onPressed, isNull);
      final checkbox = find.byType(Checkbox);
      await tester.scrollUntilVisible(
        checkbox,
        80,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(checkbox);
      await tester.pump();
      await tester.ensureVisible(accept);
      await tester.tap(accept);
      await tester.pumpAndSettle();
      expect(result, true);
      expect(tester.takeException(), isNull);
    },
  );
}
