import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/features/admin/admin_assets_controller.dart';
import 'dart:async';
import 'package:bookstark_flutter/features/admin/admin_asset_settings.dart';
import 'package:bookstark_flutter/features/admin/admin_assets_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'admin_assets_repository_test.dart' as base;
import 'admin_asset_settings_test.dart' as settings;

void main() {
  test(
    'only explicit reveal returns transient target value; close drops reference',
    () async {
      final h = base.Harness();
      addTearDown(h.close);
      final rows = await h.repo.readCredentials(base.owner);
      final lease = await h.repo.revealCredential(base.owner, rows.single);
      expect(lease.value, 'owned synthetic response secret');
      expect(lease.toString(), isNot(contains(lease.value!)));
      expect(h.calls.map((r) => r.method), everyElement('GET'));
      lease.close();
      expect(lease.value, isNull);
      expect(lease.closed, isTrue);
      lease.close();
    },
  );
  test('revealing another secret retires the first lease', () async {
    final h = base.Harness();
    addTearDown(h.close);
    final rows = await h.repo.readCredentials(base.owner);
    final first = await h.repo.revealCredential(base.owner, rows.single);
    final second = await h.repo.revealCredential(base.owner, rows.single);
    expect(first.value, isNull);
    expect(second.value, isNotNull);
    h.repo.closeSecrets();
    expect(second.value, isNull);
  });
  test('session replacement invalidates existing lease on access', () async {
    final h = base.Harness();
    addTearDown(h.close);
    final rows = await h.repo.readCredentials(base.owner);
    final lease = await h.repo.revealCredential(base.owner, rows.single);
    h.client.restoreSession({'token': 'different-owned-session'});
    expect(lease.value, isNull);
    expect(lease.closed, isTrue);
  });
  test('demotion denies reveal and retires prior secret', () async {
    final h = base.Harness();
    addTearDown(h.close);
    final rows = await h.repo.readCredentials(base.owner);
    final lease = await h.repo.revealCredential(base.owner, rows.single);
    h.role = 1;
    await expectLater(
      h.repo.revealCredential(base.owner, rows.single),
      throwsA(isA<AdminAssetOwnerLost>()),
    );
    expect(lease.value, isNull);
    expect(h.repo.reviewedCredentials, isNull);
  });
  test(
    'background closure cancels late successful reveal before disclosure',
    () async {
      final h = base.Harness();
      addTearDown(h.close);
      final rows = await h.repo.readCredentials(base.owner);
      h.credentialsGate = Completer<void>();
      final result = expectLater(
        h.repo.revealCredential(base.owner, rows.single),
        throwsA(isA<AdminAssetReadSuperseded>()),
      );
      await Future<void>.delayed(Duration.zero);
      h.repo.closeSecrets();
      h.credentialsGate!.complete();
      await result;
    },
  );
  test(
    'dispose drops outstanding value without closing shared client',
    () async {
      final h = base.Harness();
      addTearDown(h.close);
      final rows = await h.repo.readCredentials(base.owner);
      final lease = await h.repo.revealCredential(base.owner, rows.single);
      h.repo.dispose();
      expect(lease.value, isNull);
      expect(h.transport.closes, 0);
    },
  );
  test(
    'current settings key reveal checks exact opaque baseline identity',
    () async {
      final h = settings.SettingsHarness();
      addTearDown(h.close);
      final baseline = await h.repo.readSettings(base.owner);
      final lease = await h.repo.revealSettingsKey(base.owner, baseline);
      expect(lease.value, h.secret);
      h.secret = 'changed owned key';
      await expectLater(
        h.repo.revealSettingsKey(base.owner, baseline),
        throwsA(isA<AdminAssetTargetChanged>()),
      );
      expect(lease.value, isNull);
    },
  );
  test('starting settings mutation closes any explicit key viewer', () async {
    final h = settings.SettingsHarness();
    addTearDown(h.close);
    final baseline = await h.repo.readSettings(base.owner);
    final lease = await h.repo.revealSettingsKey(base.owner, baseline);
    await h.repo.saveSettings(
      base.owner,
      baseline,
      idleSeconds: 2400,
      scrollbackLines: 7000,
      action: AdminAssetKeyAction.keep,
    );
    expect(lease.value, isNull);
  });
  test(
    'settings key owner failure closes whole controller and prior visible lease',
    () async {
      final h = settings.SettingsHarness();
      addTearDown(h.close);
      final c = AdminAssetsController(h.repo, base.owner);
      addTearDown(c.dispose);
      await c.load(AdminAssetCatalog.settings);
      final baseline = c.settings!;
      final lease = await c.revealSettingsKey(baseline);
      expect(lease.value, h.secret);
      h.profileStatus = 403;
      await expectLater(
        c.revealSettingsKey(baseline),
        throwsA(isA<ApiFailure>()),
      );
      expect(c.closed, isTrue);
      expect(c.settings, isNull);
      expect(lease.value, isNull);
      expect(h.transport.closes, 0);
    },
  );
}
