import 'package:bookstark_flutter/features/admin/admin_ai_settings_controller.dart';
import 'package:bookstark_flutter/features/admin/admin_ai_settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'admin_ai_settings_controller_test.dart' as fixture;

void main() {
  testWidgets(
    'provider selection preserves URL model and secret until explicit save',
    (tester) async {
      final repo = fixture.FakeRepository();
      final c = AdminAiSettingsController(repo, fixture.owner);
      await tester.pumpWidget(
        MaterialApp(
          home: AdminAiSettingsPage(
            controller: c,
            onReturn: () {},
            onPrompts: () {},
            onActions: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final before = Map<String, String>.of(c.draft);
      await tester.tap(find.byKey(const ValueKey('ai_provider')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Anthropic（Claude）').last);
      await tester.pumpAndSettle();
      expect(c.draft['ai_provider'], 'anthropic');
      for (final key in ['ai_base_url', 'ai_model', 'ai_api_key']) {
        expect(c.draft[key], before[key]);
      }
      expect(repo.puts, 0);
      await c.save();
      expect(repo.patch, {'ai_provider': 'anthropic'});
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final width in [390.0, 320.0]) {
    testWidgets('AI form masks secret and remains usable at width $width', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      try {
        tester.view.physicalSize = Size(width, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final c = AdminAiSettingsController(
          fixture.FakeRepository(),
          fixture.owner,
        );
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: AdminAiSettingsPage(
              controller: c,
              onReturn: () {},
              onPrompts: () {},
              onActions: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        final key = find.byKey(const ValueKey('ai_api_key'));
        await tester.ensureVisible(key);
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(key).obscureText, isTrue);
        expect(
          tester
              .getSemantics(
                find.descendant(of: key, matching: find.byType(EditableText)),
              )
              .getSemanticsData()
              .label,
          contains('API Key'),
        );
        expect(find.text('保存配置'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('AI 累计用量'),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('未提供'), findsNWidgets(3));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        expect(c.draft, isEmpty);
      } finally {
        semantics.dispose();
      }
    });
  }
}
