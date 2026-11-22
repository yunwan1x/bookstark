import 'package:bookstark_flutter/features/admin/admin_settings_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'long settings title stays complete at320dp200% with unsaved badge',
    (tester) async {
      tester.view.physicalSize = const Size(320, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const title = 'AI models and system prompts';
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 1100),
              textScaler: TextScaler.linear(2),
            ),
            child: Builder(
              builder: (context) => Scaffold(
                appBar: adminSettingsAppBar(
                  context,
                  title: title,
                  dirty: true,
                  onReturn: () {},
                  dirtyLabel: 'Unsaved',
                  backLabel: 'Back',
                ),
                body: const Text('Form remains scrollable'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final render = tester.renderObject<RenderParagraph>(find.text(title));
      expect(render.didExceedMaxLines, isFalse);
      expect(find.text('Unsaved'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
