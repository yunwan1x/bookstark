import 'package:bookstark_flutter/features/admin/admin_settings_feature.dart';
import 'package:bookstark_flutter/features/admin/admin_settings_l10n.dart';
import 'package:bookstark_flutter/features/admin/admin_settings_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'admin_settings_feature_test.dart' show Fixture, owner;

void main() {
  test(
    'settings formatting translates labels without changing inserted data',
    () {
      expect(adminSettingsTranslate('系统设置', english: true), 'System settings');
      expect(
        adminSettingsTranslate('温度超出有效整数范围。', english: true),
        'Temperature must be an integer within the allowed range.',
      );
      expect(
        adminSettingsTranslate(
          '普通说明 / Shared English validator',
          english: true,
        ),
        'Shared English validator',
      );
      expect(
        adminSettingsTranslate('Manual / Automatic', english: true),
        'Manual / Automatic',
      );
    },
  );
  testWidgets(
    'English large-text navigation covers all settings routes without Chinese chrome',
    (tester) async {
      tester.view.physicalSize = const Size(320, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fixture = Fixture();
      final scope = AdminSettingsScope(fixture.client, owner);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: AdminSettingsFeature(
            scope: scope,
            english: true,
            onReturn: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      void verify() {
        final texts = tester
            .widgetList<Text>(find.byType(Text))
            .map((text) => text.data ?? '')
            .where((text) => text.isNotEmpty);
        expect(
          texts.where((text) => RegExp(r'[\u3400-\u9fff]').hasMatch(text)),
          isEmpty,
        );
        expect(tester.takeException(), isNull);
      }

      Future<void> open(String label) async {
        final target = find.text(label);
        await tester.scrollUntilVisible(
          target.hitTestable(),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(target.hitTestable());
        await tester.pumpAndSettle();
        verify();
      }

      Future<void> back() async {
        await tester.tap(find.byTooltip('Back'));
        await tester.pumpAndSettle();
        verify();
      }

      verify();
      await open('General settings');
      await open('Pagination and lists');
      await back();
      await back();
      await open('Content and uploads');
      await open('Tag recommendations');
      await back();
      await open('Public page tags');
      await back();
      await back();
      await open('Access and registration');
      await open('Collaboration signaling');
      await back();
      await back();
      await open('AI models and system prompts');
      final title = find.text('AI models and system prompts');
      expect(
        tester.renderObject<RenderParagraph>(title).didExceedMaxLines,
        isFalse,
      );
      await open('System prompts');
      await back();
      await open('Editor actions');
      await back();
      await back();
      await open('Mail service');
      await open('SMTP connection');
      await back();
      await back();
      await open('WebDAV service');
      await back();
      await open('Terminal policy');
      await back();
      expect(fixture.paths.every((path) => path.startsWith('GET ')), isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      scope.dispose();
    },
  );
  testWidgets(
    'formatting never recursively substitutes user data placeholders',
    (tester) async {
      String? rendered;
      await tester.pumpWidget(
        MaterialApp(
          home: AdminSettingsLanguage(
            english: true,
            child: Builder(
              builder: (context) {
                rendered = adminSettingsFormat(context, '恢复 {0} 默认值？', [
                  'literal {1} 技术',
                ]);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      expect(rendered, 'Restore literal {1} 技术 defaults?');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'changing interface language preserves an unsaved raw prompt exactly',
    (tester) async {
      final fixture = Fixture();
      final scope = AdminSettingsScope(fixture.client, owner);
      final language = ValueNotifier(false);
      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<bool>(
            valueListenable: language,
            builder: (context, english, child) => AdminSettingsFeature(
              scope: scope,
              english: english,
              onReturn: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> tapLabel(String label) async {
        final target = find.text(label).hitTestable();
        await tester.scrollUntilVisible(
          target,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(target);
        await tester.pumpAndSettle();
      }

      await tapLabel('AI 模型与提示词');
      await tapLabel('系统提示词');
      const raw = '笔记 {1}\n# unchanged';
      final editor = find.byKey(const ValueKey('admin-raw-text'));
      await tester.scrollUntilVisible(
        editor.hitTestable(),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(editor, raw);
      await tester.pump();
      language.value = true;
      await tester.pumpAndSettle();
      expect(find.text('System prompts'), findsOneWidget);
      expect(tester.widget<TextField>(editor).controller!.text, raw);
      expect(fixture.paths.every((path) => path.startsWith('GET ')), isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      scope.dispose();
      language.dispose();
    },
  );
}
