import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/features/admin/admin_content_settings_controller.dart';
import 'package:bookstark_flutter/features/admin/admin_content_settings_page.dart';
import 'package:bookstark_flutter/features/admin/admin_settings_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const owner = AdminPrincipal(memberId: 1, account: 'fixture', role: 0);
AdminSettingsSnapshot snapshot() => AdminSettingsSnapshot.parse([
  for (final entry in {
    'upload_max_size': '10485760',
    'upload_allowed_types': 'image/png,image/jpeg',
    'upload_max_width': '2048',
    'upload_thumb_width': '300',
    'page_size_uploads': '20',
    'share_comments_enabled': '1',
    'share_comment_max_length': '1000',
  }.entries)
    {
      'key': entry.key,
      'value': entry.value,
      'description': '',
      'update_time': '',
    },
]);

class ContentRepository extends AdminSettingsRepository {
  ContentRepository() : super(BookstarkClient('https://example.invalid'));
  Map<String, String>? patch;
  int puts = 0;
  @override
  Future<AdminSettingsSnapshot> read(
    AdminPrincipal owner, {
    Future<void>? abortTrigger,
  }) async => snapshot();
  @override
  Future<void> saveContent(
    AdminPrincipal owner,
    AdminSettingsSnapshot base,
    AdminContentChanges changes, {
    Future<void>? abortTrigger,
  }) async {
    puts++;
    patch = changes.patch(base);
  }
}

void main() {
  test('content numeric constraints retain API upload page minimum one', () {
    final empty = AdminSettingsSnapshot.parse(<Object?>[]);
    for (final field in AdminContentField.values) {
      if (field.minimum == null) continue;
      for (final value in [field.minimum!, field.maximum!]) {
        expect(AdminContentChanges({field: value.toString()}).patch(empty), {
          field.key: value.toString(),
        });
      }
      for (final value in [field.minimum! - 1, field.maximum! + 1]) {
        expect(
          () => AdminContentChanges({field: value.toString()}).patch(empty),
          throwsFormatException,
        );
      }
    }
    expect(
      () =>
          AdminContentChanges({AdminContentField.comments: '+1'}).patch(empty),
      throwsFormatException,
    );
  });
  test(
    'MIME raw text and explicit empty remain distinct from untouched',
    () async {
      final repo = ContentRepository();
      final c = AdminContentSettingsController(repo, owner);
      await c.load();
      c.edit('upload_allowed_types', '');
      await c.save();
      expect(repo.patch, {'upload_allowed_types': ''});
      expect(repo.puts, 1);
      c.dispose();
    },
  );
  test(
    'content form never writes unrelated config or clamps invalid input',
    () async {
      final repo = ContentRepository();
      final c = AdminContentSettingsController(repo, owner);
      await c.load();
      c.edit('ai_model', 'do-not-submit');
      expect(c.dirty, isFalse);
      c.edit('upload_thumb_width', '2001');
      await c.save();
      expect(repo.puts, 0);
      expect(c.draft['upload_thumb_width'], '2001');
      c.dispose();
    },
  );
  testWidgets('content 320dp200% supports long MIME and both section links', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = AdminContentSettingsController(ContentRepository(), owner);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: AdminContentSettingsPage(
          controller: c,
          onReturn: () {},
          onRecommendations: () {},
          onPublicTags: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    final last = find.text('公开页面标签');
    await tester.scrollUntilVisible(
      last,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(last, findsOneWidget);
    expect(find.text('保存本页设置'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
