import 'package:bookstark_flutter/features/admin/admin_text_settings_controller.dart';
import 'package:bookstark_flutter/features/admin/admin_text_settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'admin_text_settings_controller_test.dart' as fixture;

void main() {
  testWidgets('320dp large text scene chips and reset cancellation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = fixture.TextRepository();
    final c = AdminTextSettingsController(repo, fixture.owner, prompts: false);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: AdminTextSettingsPage(controller: c, onReturn: () {}),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('书籍'));
    await tester.pumpAndSettle();
    expect(c.selected.key, 'ai_actions_book');
    final reset = find.text('恢复当前场景默认值');
    await tester.scrollUntilVisible(
      reset.hitTestable(),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(reset.hitTestable());
    await tester.pumpAndSettle();
    expect(find.textContaining('立即覆盖'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(repo.resets, 0);
    expect(repo.puts, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(c.drafts, isEmpty);
  });
}
