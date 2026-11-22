import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/features/admin/admin_numeric_settings_controller.dart';
import 'package:bookstark_flutter/features/admin/admin_settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:bookstark_flutter/features/admin/admin_numeric_settings_page.dart';

const owner = AdminPrincipal(memberId: 1, account: 'fixture', role: 0);
AdminSettingsSnapshot snapshot() => AdminSettingsSnapshot.parse([
  for (final field in AdminNumericField.values)
    {
      'key': field.key,
      'value': field.minimum.toString(),
      'description': '',
      'update_time': '',
    },
]);

class NumericRepository extends AdminSettingsRepository {
  NumericRepository() : super(BookstarkClient('https://example.invalid'));
  Map<String, String>? patch;
  int puts = 0;
  AdminSettingsSnapshot value = snapshot();
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
    puts++;
    patch = changes.patch(base);
  }
}

void main() {
  for (final scope in [
    (general: true, terminal: false),
    (general: false, terminal: false),
    (general: false, terminal: true),
  ]) {
    final general = scope.general;
    final terminal = scope.terminal;
    testWidgets(
      'numeric settings 320dp200% general=$general terminal=$terminal',
      (tester) async {
        tester.view.physicalSize = const Size(320, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final c = AdminNumericSettingsController(
          NumericRepository(),
          owner,
          general: general,
          terminal: terminal,
        );
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: AdminNumericSettingsPage(
              controller: c,
              onReturn: () {},
              onPagination: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        final last = find.byKey(
          ValueKey(
            terminal
                ? 'asset_terminal_scrollback_lines'
                : general
                ? 'favicon_cache_days'
                : 'label_list_limit',
          ),
        );
        await tester.scrollUntilVisible(
          last,
          300,
          scrollable: find.byType(Scrollable).first,
        );
        expect(last, findsOneWidget);
        expect(find.text(terminal ? '保存终端策略' : '保存设置'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  test(
    'all thirteen numeric fields enforce exact Go ranges and integer grammar',
    () {
      final base = AdminSettingsSnapshot.parse(<Object?>[]);
      for (final field in AdminNumericField.values) {
        for (final valid in [field.minimum, field.maximum]) {
          expect(AdminNumericChanges({field: valid.toString()}).patch(base), {
            field.key: valid.toString(),
          });
        }
        for (final invalid in [
          (field.minimum - 1).toString(),
          (field.maximum + 1).toString(),
          '1.0',
          ' 20',
          '20 ',
          '1e2',
          'NaN',
          '9999999999999999999999999999',
        ]) {
          expect(
            () => AdminNumericChanges({field: invalid}).patch(base),
            throwsFormatException,
          );
        }
      }
    },
  );
  test(
    'numeric form isolates general and pagination fields and preserves raw changed spelling',
    () async {
      final repo = NumericRepository();
      final c = AdminNumericSettingsController(repo, owner, general: true);
      await c.load();
      c.edit('page_size_books', '25');
      expect(c.dirty, isFalse);
      c.edit('login_session_days', '+030');
      await c.save();
      expect(repo.patch, {'login_session_days': '+030'});
      expect(repo.puts, 1);
      c.dispose();
    },
  );
  test(
    'missing numeric values do not receive defaults or become dirty',
    () async {
      final repo = NumericRepository()
        ..value = AdminSettingsSnapshot.parse(<Object?>[]);
      final c = AdminNumericSettingsController(repo, owner, general: false);
      expect(c.draft, isEmpty);
      await c.load();
      expect(c.dirty, isFalse);
      expect(c.draft.values.every((value) => value.isEmpty), isTrue);
      c.edit('page_size_notes', '201');
      await c.save();
      expect(repo.puts, 0);
      expect(c.message, contains('有效整数'));
      c.dispose();
    },
  );
}
