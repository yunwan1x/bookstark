import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/features/admin/admin_numeric_settings_controller.dart';
import 'package:bookstark_flutter/features/admin/admin_numeric_settings_page.dart';
import 'package:bookstark_flutter/features/admin/admin_settings_repository.dart';
import 'package:bookstark_flutter/features/admin/admin_text_settings_controller.dart';
import 'package:bookstark_flutter/features/admin/admin_text_settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const owner = AdminPrincipal(memberId: 1, account: 'fixture', role: 0);

class FocusRepository extends AdminSettingsRepository {
  FocusRepository() : super(BookstarkClient('https://example.invalid'));
  AdminSettingsSnapshot value = AdminSettingsSnapshot.parse([
    for (final field in AdminNumericField.values)
      {
        'key': field.key,
        'value': field.minimum.toString(),
        'description': '',
        'update_time': '',
      },
    for (final field in AdminAiTextField.values)
      {
        'key': field.key,
        'value': '# raw\nA | {subject}\n',
        'description': '',
        'update_time': '',
      },
  ]);
  void apply(Map<String, String> patch) {
    value = AdminSettingsSnapshot.parse([
      for (final entry in value.records.entries)
        {
          'key': entry.key,
          'value': patch[entry.key] ?? entry.value.value,
          'description': '',
          'update_time': '',
        },
    ]);
  }

  @override
  Future<AdminSettingsSnapshot> read(
    AdminPrincipal owner, {
    Future<void>? abortTrigger,
  }) async => value;
  @override
  Future<void> saveNumeric(
    AdminPrincipal owner,
    AdminSettingsSnapshot base,
    AdminNumericChanges changes, {
    Future<void>? abortTrigger,
  }) async {
    apply(changes.patch(base));
  }

  @override
  Future<void> saveText(
    AdminPrincipal owner,
    AdminSettingsSnapshot base,
    AdminTextChanges changes, {
    Future<void>? abortTrigger,
  }) async {
    apply(changes.patch(base));
  }
}

Future<void> continueWithPlatformInput(
  WidgetTester tester,
  Finder field,
  String first,
  String second,
) async {
  await tester.tap(field);
  await tester.pump();
  // The first update removes the status notice. The input client must survive.
  tester.testTextInput.updateEditingValue(
    TextEditingValue(
      text: first,
      selection: TextSelection.collapsed(offset: first.length),
    ),
  );
  await tester.pump();
  final editable = find.descendant(
    of: field,
    matching: find.byType(EditableText),
  );
  expect(
    tester.widget<EditableText>(editable).focusNode.hasFocus,
    isTrue,
    reason: 'Removing a status notice must not destroy the active input',
  );
  expect(tester.testTextInput.hasAnyClients, isTrue);
  tester.testTextInput.updateEditingValue(
    TextEditingValue(
      text: second,
      selection: TextSelection.collapsed(offset: second.length),
    ),
  );
  await tester.pump();
  expect(tester.widget<EditableText>(editable).controller.text, second);
}

void main() {
  for (final scope in [
    (
      general: true,
      terminal: false,
      key: 'login_session_days',
      initial: '31',
      first: '3',
      next: '34',
    ),
    (
      general: false,
      terminal: false,
      key: 'page_size_books',
      initial: '21',
      first: '2',
      next: '24',
    ),
    (
      general: false,
      terminal: true,
      key: 'asset_terminal_idle_timeout_seconds',
      initial: '120',
      first: '1',
      next: '121',
    ),
  ]) {
    testWidgets(
      'saved numeric form retains consecutive IME input: ${scope.key}',
      (tester) async {
        final controller = AdminNumericSettingsController(
          FocusRepository(),
          owner,
          general: scope.general,
          terminal: scope.terminal,
        );
        await tester.pumpWidget(
          MaterialApp(
            home: AdminNumericSettingsPage(
              controller: controller,
              onReturn: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        final field = find.byKey(ValueKey(scope.key));
        await tester.tap(field);
        await tester.enterText(field, scope.initial);
        await tester.pump();
        await tester.tap(find.text(scope.terminal ? '保存终端策略' : '保存设置'));
        await tester.pumpAndSettle();
        expect(controller.phase, AdminNumericPhase.saved);
        expect(find.text('服务器已确认保存，并已读取当前配置。'), findsOneWidget);
        await continueWithPlatformInput(tester, field, scope.first, scope.next);
        expect(controller.draft[scope.key], scope.next);
        expect(controller.dirty, isTrue);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  for (final prompts in [true, false]) {
    testWidgets(
      'saved raw text retains consecutive IME input: prompts=$prompts',
      (tester) async {
        final controller = AdminTextSettingsController(
          FocusRepository(),
          owner,
          prompts: prompts,
        );
        await tester.pumpWidget(
          MaterialApp(
            home: AdminTextSettingsPage(
              controller: controller,
              onReturn: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        final field = find.byKey(const ValueKey('admin-raw-text'));
        await tester.scrollUntilVisible(
          field.hitTestable(),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(field.hitTestable());
        await tester.enterText(field, '# saved\nA | {subject}\n');
        await tester.pump();
        await tester.tap(find.text('保存文本'));
        await tester.pumpAndSettle();
        expect(controller.phase, AdminTextPhase.editing);
        expect(find.text('服务器已确认操作，并已读取当前文本。'), findsOneWidget);
        await tester.scrollUntilVisible(
          field.hitTestable(),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await continueWithPlatformInput(
          tester,
          field,
          '# n',
          '# next\r\nA | {subject}\r\n',
        );
        expect(controller.text, '# next\r\nA | {subject}\r\n');
        expect(controller.dirty, isTrue);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
