import 'dart:async';
import 'dart:convert';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/features/admin/admin_asset_drafts.dart';
import 'package:bookstark_flutter/features/admin/admin_asset_settings.dart';
import 'package:bookstark_flutter/features/admin/admin_assets_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'admin_assets_repository_test.dart' as base;

class SettingsHarness extends base.Harness {
  int idle = 1800, scroll = 5000, settingsStatus = 200;
  String secret = 'owned private settings key';
  bool legacy = false, dangling = false, lost = false, malformed = false;
  bool wrongReceipt = false;
  final writes = <http.Request>[];
  Completer<void>? settingsGate;
  final settingsReached = Completer<void>();
  Map<String, Object?> current() => {
    'terminal_idle_timeout_seconds': idle,
    'terminal_scrollback_lines': scroll,
    'credential_secret': secret,
  };
  @override
  Future<http.Response> handle(http.Request request) async {
    if (request.url.path.endsWith('/assets/settings')) {
      calls.add(request);
      if (request.method == 'GET') {
        final data = current();
        if (!settingsReached.isCompleted) settingsReached.complete();
        if (settingsGate != null) await settingsGate!.future;
        return reply({
          'code': settingsStatus == 200 ? 0 : 1,
          'data': malformed ? {'credential_secret': secret} : data,
        }, settingsStatus);
      }
      writes.add(request);
      final body = jsonDecode(request.body) as Map;
      idle = body['terminal_idle_timeout_seconds'] as int;
      scroll = body['terminal_scrollback_lines'] as int;
      secret = body['credential_secret'] as String;
      if (lost) throw http.ClientException('owned private upstream');
      return reply({
        'code': 0,
        'data': {
          ...current(),
          if (wrongReceipt) 'credential_secret': 'different',
        },
      }, 200);
    }
    if (request.url.path.endsWith('/api/admin/settings')) {
      calls.add(request);
      writes.add(request);
      final body = jsonDecode(request.body) as Map;
      idle = int.parse(body['asset_terminal_idle_timeout_seconds'] as String);
      scroll = int.parse(body['asset_terminal_scrollback_lines'] as String);
      if (lost) throw http.ClientException('owned private upstream');
      return reply({'code': 0, 'data': null}, 200);
    }
    if (request.url.path.endsWith('/ssh-hosts') && (legacy || dangling)) {
      calls.add(request);
      return reply({
        'code': 0,
        'data': [
          {...base.host(5), 'credential_id': legacy ? 0 : 777},
        ],
      }, 200);
    }
    return super.handle(request);
  }
}

void main() {
  late SettingsHarness h;
  setUp(() {
    h = SettingsHarness();
  });
  tearDown(() {
    h.close();
  });
  test(
    'metadata exposes policy and enabled state without retaining key',
    () async {
      final value = await h.repo.readSettings(base.owner);
      expect(value.idleSeconds, 1800);
      expect(value.scrollbackLines, 5000);
      expect(value.encryptionEnabled, isTrue);
      expect(value.toString(), isNot(contains(h.secret)));
      expect(identical(h.repo.reviewedSettings, value), isTrue);
      expect(h.calls.map((r) => r.method), everyElement('GET'));
    },
  );
  test('BOM key remains enabled and Go whitespace key is disabled', () async {
    h.secret = '\ufeff';
    expect((await h.repo.readSettings(base.owner)).encryptionEnabled, isTrue);
    h.secret = '\u0085 \n';
    expect((await h.repo.readSettings(base.owner)).encryptionEnabled, isFalse);
  });
  test(
    'keep sends exactly two string keys without current secret or host test',
    () async {
      final baseline = await h.repo.readSettings(base.owner);
      h.legacy = true;
      final receipt = await h.repo.saveSettings(
        base.owner,
        baseline,
        idleSeconds: 2400,
        scrollbackLines: 7000,
        action: AdminAssetKeyAction.keep,
      );
      expect(receipt.action, AdminAssetKeyAction.keep);
      expect(h.writes.single.url.path, '/root/api/admin/settings');
      expect(jsonDecode(h.writes.single.body), {
        'asset_terminal_idle_timeout_seconds': '2400',
        'asset_terminal_scrollback_lines': '7000',
      });
      expect(h.writes.single.body, isNot(contains(h.secret)));
      expect(h.calls.where((r) => r.url.path.endsWith('/ssh-hosts')), isEmpty);
      expect(h.repo.reviewedSettings, isNull);
    },
  );
  test(
    'replacement preflights full references and preserves Go BOM key',
    () async {
      final baseline = await h.repo.readSettings(base.owner);
      var submitted = 0;
      await h.repo.saveSettings(
        base.owner,
        baseline,
        idleSeconds: 3000,
        scrollbackLines: 8000,
        action: AdminAssetKeyAction.replace,
        replacement: ' \ufeff ',
        onSubmitted: () {
          submitted++;
        },
      );
      expect(h.secret, '\ufeff');
      expect(submitted, 1);
      expect(h.writes.single.url.path, '/root/api/admin/assets/settings');
      final hosts = h.calls.singleWhere(
        (r) => r.url.path.endsWith('/ssh-hosts'),
      );
      expect(hosts.url.queryParameters, isEmpty);
      expect(hosts.url.queryParameters['status'], isNull);
      expect(h.calls.any((r) => r.url.path.endsWith('/credentials')), isTrue);
      expect(h.calls.any((r) => r.url.path.endsWith('/test')), isFalse);
    },
  );
  test('disable requires explicit action and submits empty secret', () async {
    final baseline = await h.repo.readSettings(base.owner);
    await h.repo.saveSettings(
      base.owner,
      baseline,
      idleSeconds: 1800,
      scrollbackLines: 5000,
      action: AdminAssetKeyAction.disable,
    );
    expect(jsonDecode(h.writes.single.body)['credential_secret'], '');
  });
  for (final dangling in [false, true]) {
    test('rotation blocks legacy or dangling references: $dangling', () async {
      final baseline = await h.repo.readSettings(base.owner);
      h.dangling = dangling;
      h.legacy = !dangling;
      await expectLater(
        h.repo.saveSettings(
          base.owner,
          baseline,
          idleSeconds: 1800,
          scrollbackLines: 5000,
          action: AdminAssetKeyAction.replace,
          replacement: 'owned new key',
        ),
        throwsA(
          isA<AdminAssetLegacyMigrationRequired>().having(
            (e) => e.hostIds,
            'affected host IDs',
            [5],
          ),
        ),
      );
      expect(h.writes, isEmpty);
    });
  }
  test(
    'concurrent key change blocks even when encryption remains enabled',
    () async {
      final baseline = await h.repo.readSettings(base.owner);
      h.secret = 'different';
      await expectLater(
        h.repo.saveSettings(
          base.owner,
          baseline,
          idleSeconds: 1800,
          scrollbackLines: 5000,
          action: AdminAssetKeyAction.keep,
        ),
        throwsA(isA<AdminAssetTargetChanged>()),
      );
      expect(h.writes, isEmpty);
    },
  );
  test('concurrent policy change blocks write', () async {
    final baseline = await h.repo.readSettings(base.owner);
    h.idle = 1234;
    await expectLater(
      h.repo.saveSettings(
        base.owner,
        baseline,
        idleSeconds: 1800,
        scrollbackLines: 5000,
        action: AdminAssetKeyAction.disable,
      ),
      throwsA(isA<AdminAssetTargetChanged>()),
    );
    expect(h.writes, isEmpty);
  });
  test('cleared replacement cannot silently become keep or disable', () async {
    final baseline = await h.repo.readSettings(base.owner);
    for (final replacement in <String?>[null, '', ' \n']) {
      await expectLater(
        Future.sync(
          () => h.repo.saveSettings(
            base.owner,
            baseline,
            idleSeconds: 1800,
            scrollbackLines: 5000,
            action: AdminAssetKeyAction.replace,
            replacement: replacement,
          ),
        ),
        throwsA(isA<AdminAssetDraftInvalid>()),
      );
    }
    expect(h.writes, isEmpty);
  });
  test('lost reply retires review without automatic read or retry', () async {
    final baseline = await h.repo.readSettings(base.owner);
    h.lost = true;
    await expectLater(
      h.repo.saveSettings(
        base.owner,
        baseline,
        idleSeconds: 1800,
        scrollbackLines: 5000,
        action: AdminAssetKeyAction.replace,
        replacement: 'new owned key',
      ),
      throwsA(isA<AdminAssetWriteUnknown>()),
    );
    expect(h.writes, hasLength(1));
    expect(h.repo.reviewedSettings, isNull);
    final count = h.calls.length;
    await Future<void>.delayed(Duration.zero);
    expect(h.calls.length, count);
    expect(h.writes, hasLength(1));
  });
  test('wrong key in successful receipt is unknown', () async {
    final baseline = await h.repo.readSettings(base.owner);
    h.wrongReceipt = true;
    await expectLater(
      h.repo.saveSettings(
        base.owner,
        baseline,
        idleSeconds: 1800,
        scrollbackLines: 5000,
        action: AdminAssetKeyAction.replace,
        replacement: 'new owned key',
      ),
      throwsA(isA<AdminAssetWriteUnknown>()),
    );
    expect(h.writes, hasLength(1));
  });
  test('403 retires every private catalog', () async {
    await h.repo.readHosts(base.owner);
    await h.repo.readCredentials(base.owner);
    await h.repo.readSettings(base.owner);
    h.settingsStatus = 403;
    await expectLater(
      h.repo.readSettings(base.owner),
      throwsA(isA<ApiFailure>()),
    );
    expect(h.repo.reviewedHosts, isNull);
    expect(h.repo.reviewedCredentials, isNull);
    expect(h.repo.reviewedSettings, isNull);
  });
  test('503 does not invent disabled encryption', () async {
    await h.repo.readSettings(base.owner);
    h.settingsStatus = 503;
    await expectLater(
      h.repo.readSettings(base.owner),
      throwsA(isA<ApiFailure>()),
    );
    expect(h.repo.reviewedSettings, isNull);
  });
  test('malformed settings never become default policy', () async {
    h.malformed = true;
    await expectLater(h.repo.readSettings(base.owner), throwsFormatException);
    expect(h.repo.reviewedSettings, isNull);
  });
  test('late read cannot cross session replacement', () async {
    h.settingsGate = Completer<void>();
    final result = expectLater(
      h.repo.readSettings(base.owner),
      throwsA(isA<AdminAssetOwnerLost>()),
    );
    await h.settingsReached.future;
    h.client.restoreSession({'token': 'replacement-session'});
    h.settingsGate!.complete();
    await result;
    expect(h.repo.reviewedSettings, isNull);
  });
}
