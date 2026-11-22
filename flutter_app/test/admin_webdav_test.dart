import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/features/admin/admin_settings_repository.dart';
import 'package:bookstark_flutter/features/admin/admin_webdav_controller.dart';
import 'package:bookstark_flutter/features/admin/admin_webdav_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const owner = AdminPrincipal(memberId: 1, account: 'fixture', role: 0);
AdminSettingsSnapshot snapshot({String url = ''}) =>
    AdminSettingsSnapshot.parse([
      for (final entry in {
        'webdav_file_max_bytes': '104857600',
        'webdav_user_quota_bytes': '1073741824',
        'webdav_public_file_max_bytes': '52428800',
        'webdav_max_concurrent_transfers': '4',
        'webdav_public_asset_separate_url_enabled': '0',
        'webdav_public_asset_base_url': url,
      }.entries)
        {
          'key': entry.key,
          'value': entry.value,
          'description': '',
          'update_time': '',
        },
    ]);

class WebDavRepository extends AdminSettingsRepository {
  WebDavRepository() : super(BookstarkClient('https://example.invalid'));
  Map<String, String>? patch;
  int puts = 0;
  String url = '';
  @override
  Future<AdminSettingsSnapshot> read(
    AdminPrincipal owner, {
    Future<void>? abortTrigger,
  }) async => snapshot(url: url);
  @override
  Future<void> saveWebDav(
    AdminPrincipal owner,
    AdminSettingsSnapshot base,
    AdminWebDavChanges changes, {
    Future<void>? abortTrigger,
  }) async {
    puts++;
    patch = changes.patch(base);
    if (patch!.containsKey('webdav_public_asset_base_url')) {
      url = patch!['webdav_public_asset_base_url']!.trim().replaceFirst(
        RegExp(r'/+$'),
        '',
      );
    }
  }
}

void main() {
  test('WebDAV integer limits include exact 1TiB without rounded units', () {
    final empty = AdminSettingsSnapshot.parse(<Object?>[]);
    for (final field in AdminWebDavField.values) {
      if (field.minimum == null) continue;
      for (final value in [field.minimum!, field.maximum!]) {
        expect(AdminWebDavChanges({field: value.toString()}).patch(empty), {
          field.key: value.toString(),
        });
      }
      for (final value in [field.minimum! - 1, field.maximum! + 1]) {
        expect(
          () => AdminWebDavChanges({field: value.toString()}).patch(empty),
          throwsFormatException,
        );
      }
    }
    expect(
      AdminWebDavChanges({
        AdminWebDavField.userQuota: '1099511627776',
      }).patch(empty),
      {'webdav_user_quota_bytes': '1099511627776'},
    );
  });
  test(
    'WebDAV rejects credential query fragment and missing required base',
    () {
      final base = snapshot();
      for (final url in [
        'https://user:pass@example.invalid/a',
        'https://example.invalid/a?q=x',
        'https://example.invalid/a#part',
        'file:///a',
        'https:///a',
      ]) {
        expect(
          () => AdminWebDavChanges({AdminWebDavField.baseUrl: url}).patch(base),
          throwsFormatException,
        );
      }
      expect(
        () =>
            AdminWebDavChanges({AdminWebDavField.separateUrl: '1'}).patch(base),
        throwsFormatException,
      );
    },
  );
  test(
    'WebDAV only dirty URL submits and readback adopts server normalization',
    () async {
      final repo = WebDavRepository();
      final c = AdminWebDavSettingsController(repo, owner);
      await c.load();
      c.edit(
        'webdav_public_asset_base_url',
        ' https://example.invalid/assets/// ',
      );
      await c.save();
      expect(repo.patch, {
        'webdav_public_asset_base_url': ' https://example.invalid/assets/// ',
      });
      expect(
        c.draft['webdav_public_asset_base_url'],
        'https://example.invalid/assets',
      );
      c.dispose();
    },
  );
  testWidgets('WebDAV 320dp200% reaches base URL without layout errors', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = AdminWebDavSettingsController(WebDavRepository(), owner);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: AdminWebDavSettingsPage(controller: c, onReturn: () {}),
      ),
    );
    await tester.pumpAndSettle();
    final last = find.byKey(const ValueKey('webdav_public_asset_base_url'));
    await tester.scrollUntilVisible(
      last,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(last, findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
