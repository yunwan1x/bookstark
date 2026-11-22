import 'package:bookstark_flutter/features/admin/admin_asset_host_editor_page.dart';
import 'package:bookstark_flutter/features/admin/admin_asset_models.dart';
import 'package:bookstark_flutter/features/admin/admin_asset_drafts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'admin_assets_repository_test.dart' as base;

void main() {
  AdminAssetHostDraft? saved;
  AdminAssetCredentialMetadata? chosen;
  var saves = 0, newCredentials = 0;
  setUp(() {
    saved = null;
    chosen = null;
    saves = newCredentials = 0;
  });
  Future<void> open(
    WidgetTester tester, {
    bool editing = false,
    bool legacy = false,
    bool empty = false,
    bool duplicate = false,
  }) async {
    final metadata = AdminAssetHostMetadata.parse({
      ...base.host(5),
      if (legacy) 'credential_id': 0,
    });
    await tester.pumpWidget(
      MaterialApp(
        home: AdminAssetHostEditorPage(
          initial: editing ? metadata : null,
          credentials: empty
              ? []
              : [
                  AdminAssetCredentialMetadata.parse(base.credential(9)),
                  if (duplicate)
                    AdminAssetCredentialMetadata.parse(base.credential(10)),
                ],
          onReturn: () {},
          onNewCredential: () {
            newCredentials++;
          },
          onSave: (draft, credential) async {
            saved = draft;
            chosen = credential;
            saves++;
            return false;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester) async {
    await tester.scrollUntilVisible(
      find.text('保存主机'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存主机'));
    await tester.pumpAndSettle();
  }

  testWidgets('new host requires explicit existing credential selection', (
    tester,
  ) async {
    await open(tester);
    await tester.enterText(
      find.byKey(const ValueKey('asset-host-name')),
      ' owned host ',
    );
    await tester.enterText(
      find.byKey(const ValueKey('asset-host-address')),
      'host.example.invalid',
    );
    await save(tester);
    expect(saves, 0);
    await tester.scrollUntilVisible(
      find.byType(DropdownButtonFormField<int>),
      -180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('owned credential #9 · 密码').last);
    await tester.pumpAndSettle();
    await save(tester);
    expect(saves, 1);
    expect(chosen!.id, 9);
    expect(saved!.toRequest(creating: true), {
      'name': 'owned host',
      'host': 'host.example.invalid',
      'port': 22,
      'shell': '/bin/sh',
      'cwd': '',
      'docker_socket_path': '/var/run/docker.sock',
      'credential_id': 9,
      'username': 'fixture-user',
      'auth_type': 'password',
    });
  });
  testWidgets('missing credentials never choose ID zero on new host', (
    tester,
  ) async {
    await open(tester, empty: true);
    await tester.enterText(
      find.byKey(const ValueKey('asset-host-name')),
      'owned host',
    );
    await tester.enterText(
      find.byKey(const ValueKey('asset-host-address')),
      'host.example.invalid',
    );
    await save(tester);
    expect(saves, 0);
    expect(saved, isNull);
    await tester.scrollUntilVisible(
      find.text('新增凭据'),
      -180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('新增凭据'));
    await tester.pump();
    expect(newCredentials, 1);
  });
  testWidgets('legacy metadata-only edit preserves inline reference and auth', (
    tester,
  ) async {
    await open(tester, editing: true, legacy: true);
    await save(tester);
    expect(saves, 1);
    expect(chosen, isNull);
    expect(saved!.credentialId, 0);
    expect(saved!.username, 'fixture-user');
    expect(saved!.auth, AdminAssetAuth.password);
    expect(
      saved!.toRequest(creating: false).containsKey('credential'),
      isFalse,
    );
  });
  testWidgets('invalid port blocks save instead of silently defaulting', (
    tester,
  ) async {
    await open(tester, editing: true);
    await tester.enterText(
      find.byKey(const ValueKey('asset-host-port')),
      '65536',
    );
    await save(tester);
    expect(saves, 0);
  });
  testWidgets(
    'duplicate names stay distinguishable and selection saves actual second ID',
    (tester) async {
      await open(tester, duplicate: true);
      await tester.enterText(
        find.byKey(const ValueKey('asset-host-name')),
        'owned host',
      );
      await tester.enterText(
        find.byKey(const ValueKey('asset-host-address')),
        'host.example.invalid',
      );
      await tester.scrollUntilVisible(
        find.byType(DropdownButtonFormField<int>),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      expect(find.text('owned credential #9 · 密码'), findsOneWidget);
      expect(find.text('owned credential #10 · 密码'), findsOneWidget);
      await tester.tap(find.text('owned credential #10 · 密码'));
      await tester.pumpAndSettle();
      await save(tester);
      expect(saves, 1);
      expect(saved!.credentialId, 10);
      expect(chosen!.id, 10);
    },
  );
}
