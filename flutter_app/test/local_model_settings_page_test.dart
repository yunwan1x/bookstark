import 'dart:convert';
import 'package:bookstark_flutter/core/app_theme.dart';
import 'package:bookstark_flutter/core/local_model_config.dart';
import 'package:bookstark_flutter/features/assistant/local_model_settings_controller.dart';
import 'package:bookstark_flutter/features/assistant/local_model_settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late Map<String, String> values;
  late LocalModelSettingsController state;
  var writes = 0, calls = 0, failWrite = false;
  void create() {
    values = {};
    writes = 0;
    calls = 0;
    failWrite = false;
    state = LocalModelSettingsController(
      vault: LocalModelConfigVault(
        namespace: 'db',
        readValue: (k) async => values[k],
        writeValue: (k, v) async {
          values[k] = v;
          writes++;
          if (failWrite) throw StateError('lost receipt');
        },
      ),
      probe: LocalModelProbe(
        createClient: () => MockClient((_) async {
          calls++;
          return http.Response(
            '{"choices":[{"message":{"content":"OK"}}]}',
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      ),
    );
  }

  Future<void> mount(WidgetTester t, {bool large = false}) async {
    t.view.devicePixelRatio = 2;
    t.view.physicalSize = large ? const Size(640, 1280) : const Size(780, 1688);
    t.platformDispatcher.textScaleFactorTestValue = large ? 2 : 1;
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    await t.pumpWidget(
      MaterialApp(
        theme: bookstarkTheme(),
        home: LocalModelSettingsPage(controller: state, english: large),
      ),
    );
    await t.pumpAndSettle();
  }

  Future<void> reveal(WidgetTester t, Finder target, {bool up = false}) async {
    await t.scrollUntilVisible(
      target,
      up ? -150 : 150,
      scrollable: find.byType(Scrollable).first,
    );
    await t.pumpAndSettle();
  }

  Future<void> edit(WidgetTester t) async {
    await reveal(t, find.byKey(const Key('local-model-endpoint')));
    await t.enterText(
      find.byKey(const Key('local-model-endpoint')),
      'https://model.example.invalid/v1',
    );
    await reveal(t, find.byKey(const Key('local-model-name')));
    await t.enterText(
      find.byKey(const Key('local-model-name')),
      'fixture-model',
    );
    await reveal(t, find.byKey(const Key('local-model-key')));
    await t.enterText(
      find.byKey(const Key('local-model-key')),
      'fixture-secret',
    );
    await t.pump();
  }

  testWidgets(
    'masked credential and explicit save persist without automatically testing',
    (t) async {
      create();
      final semantics = t.ensureSemantics();
      try {
        await mount(t);
        expect(calls, 0);
        expect(writes, 0);
        await edit(t);
        expect(
          t
              .widget<TextField>(
                find.descendant(
                  of: find.byKey(const Key('local-model-key')),
                  matching: find.byType(TextField),
                ),
              )
              .obscureText,
          true,
        );
        await reveal(t, find.text('保存配置'));
        await t.tap(find.text('保存配置'));
        await t.pumpAndSettle();
        expect(writes, 1);
        expect(calls, 0);
        expect(state.saved!.model, 'fixture-model');
        expect(find.text('配置已保存'), findsOneWidget);
        await reveal(t, find.text('测试连接'));
        await t.tap(find.text('测试连接'));
        await t.pumpAndSettle();
        expect(calls, 1);
        expect(writes, 1);
        expect(find.text('连接成功（当前表单）'), findsOneWidget);
        expect(
          t
              .getSemantics(find.byKey(const Key('local-model-probe-status')))
              .label,
          '连接成功（当前表单）',
        );
        await t.pumpWidget(const SizedBox());
        await t.pumpAndSettle();
      } finally {
        semantics.dispose();
      }
    },
  );
  testWidgets(
    'unknown save keeps form and blocks duplicate save until explicit readback',
    (t) async {
      create();
      await mount(t);
      await edit(t);
      failWrite = true;
      await reveal(t, find.text('保存配置'));
      await t.tap(find.text('保存配置'));
      await t.pumpAndSettle();
      expect(writes, 1);
      expect(state.unknown, true);
      expect(state.model, 'fixture-model');
      await reveal(t, find.text('重新读取核对'), up: true);
      await t.tap(find.text('重新读取核对'));
      await t.pumpAndSettle();
      expect(writes, 1);
      expect(state.unknown, false);
      expect(state.dirty, false);
      expect(state.saved!.apiKey, 'fixture-secret');
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
    },
  );
  testWidgets(
    'corrupt record needs confirmed reset and preserves unrelated encrypted values',
    (t) async {
      create();
      values[state.vault.key] = '{broken';
      values['other-account'] = 'keep';
      await mount(t);
      expect(writes, 0);
      await t.tap(find.text('清除损坏配置'));
      await t.pumpAndSettle();
      await t.tap(find.text('取消'));
      await t.pumpAndSettle();
      expect(writes, 0);
      await t.tap(find.text('清除损坏配置'));
      await t.pumpAndSettle();
      await t.tap(find.text('清除配置'));
      await t.pumpAndSettle();
      expect(writes, 1);
      expect(jsonDecode(values[state.vault.key]!)['config'], isNull);
      expect(values['other-account'], 'keep');
      expect(state.loaded, true);
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
    },
  );
  testWidgets(
    'English320dp200 keyboard fields errors and actions remain scrollable',
    (t) async {
      create();
      await mount(t, large: true);
      await edit(t);
      t.view.viewInsets = const FakeViewPadding(bottom: 480);
      addTearDown(t.view.resetViewInsets);
      await t.pump();
      await reveal(t, find.text('Save configuration'));
      await t.tap(find.text('Save configuration'));
      await t.pumpAndSettle();
      expect(writes, 1);
      expect(state.saved!.model, 'fixture-model');
      expect(t.takeException(), isNull);
      await reveal(t, find.text('Test connection'));
      await t.tap(find.text('Test connection'));
      await t.pumpAndSettle();
      expect(calls, 1);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
    },
  );
}
