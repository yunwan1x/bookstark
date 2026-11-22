import 'package:bookstark_flutter/features/admin/admin_asset_credential_editor_page.dart';
import 'package:bookstark_flutter/features/admin/admin_asset_models.dart';
import 'package:bookstark_flutter/features/admin/admin_asset_drafts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'admin_assets_repository_test.dart' as base;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('bookstark/asset_secure_window');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  String? replacement;
  AdminAssetCredentialDraft? submittedDraft;
  var saves = 0;
  setUp(() {
    replacement = null;
    submittedDraft = null;
    saves = 0;
    messenger.setMockMethodCallHandler(channel, (_) async => true);
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });
  Future<void> open(
    WidgetTester tester, {
    bool existing = false,
    void Function(ValueChanged<String>)? editKey,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AdminAssetCredentialEditorPage(
          initial: existing
              ? AdminAssetCredentialMetadata.parse(base.credential(9))
              : null,
          onReturn: () {},
          onEditPrivateKey: editKey ?? (_) {},
          onSave: (draft, secret, sent) async {
            saves++;
            submittedDraft = draft;
            replacement = secret;
            sent();
            return false;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester) async {
    await tester.scrollUntilVisible(
      find.text('保存凭据'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存凭据'));
    await tester.pumpAndSettle();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  testWidgets(
    'existing metadata defaults to explicit keep without server secret field',
    (tester) async {
      await open(tester, existing: true);
      expect(
        find.byKey(const ValueKey('asset-credential-password')),
        findsNothing,
      );
      expect(
        find.textContaining('owned synthetic response secret'),
        findsNothing,
      );
      await save(tester);
      expect(saves, 1);
      expect(replacement, isNull);
      expect(submittedDraft!.name, 'owned credential');
      await close(tester);
    },
  );
  testWidgets(
    'new password is obscured, byte-preserving and cleared at actual submission',
    (tester) async {
      await open(tester);
      await tester.enterText(
        find.byKey(const ValueKey('asset-credential-name')),
        'owned new credential',
      );
      await tester.enterText(
        find.byKey(const ValueKey('asset-credential-username')),
        'owned-user',
      );
      final field = find.byKey(const ValueKey('asset-credential-password'));
      await tester.scrollUntilVisible(
        field,
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).obscureText, isTrue);
      await tester.enterText(field, ' owned 密码 ');
      await save(tester);
      expect(saves, 1);
      expect(replacement, ' owned 密码 ');
      expect(tester.widget<TextField>(field).controller!.text, isEmpty);
      await close(tester);
    },
  );
  testWidgets('background-cleared replacement cannot silently save as keep', (
    tester,
  ) async {
    await open(tester);
    await tester.enterText(
      find.byKey(const ValueKey('asset-credential-name')),
      'owned new credential',
    );
    await tester.enterText(
      find.byKey(const ValueKey('asset-credential-username')),
      'owned-user',
    );
    final field = find.byKey(const ValueKey('asset-credential-password'));
    await tester.scrollUntilVisible(
      field,
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.enterText(field, 'owned transient');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    await save(tester);
    expect(saves, 0);
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);
    await close(tester);
  });
  testWidgets(
    'changing auth requires explicit private-key replacement without exposing bytes',
    (tester) async {
      const key = ' owned synthetic first\r\n第二行\n尾部 ';
      await open(
        tester,
        existing: true,
        editKey: (apply) {
          apply(key);
        },
      );
      await tester.tap(find.byType(DropdownButtonFormField<AdminAssetAuth>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('SSH 私钥').last);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('编辑私钥'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('编辑私钥'));
      await tester.pumpAndSettle();
      expect(find.text(key), findsNothing);
      expect(find.text('已填写私钥 · 保留原始换行'), findsOneWidget);
      await save(tester);
      expect(saves, 1);
      expect(replacement, key);
      expect(submittedDraft!.auth, AdminAssetAuth.key);
      await close(tester);
    },
  );
}
