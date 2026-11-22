import 'dart:async';
import 'dart:convert';
import 'package:bookstark_flutter/features/admin/admin_asset_migration.dart';
import 'package:bookstark_flutter/features/admin/admin_assets_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'admin_assets_repository_test.dart' as base;

class MigrationHarness extends base.Harness {
  final writes = <http.Request>[];
  String original = ' owned synthetic first\r\n第二行\n尾部 ';
  Map<String, Object?>? created;
  int cid = 0, returnedId = 10;
  bool dropCreate = false, dropBind = false, changedHost = false;
  bool wrongSecretReceipt = false;
  Completer<void>? createGate;
  final createReached = Completer<void>();
  @override
  Future<http.Response> handle(http.Request request) async {
    final path = request.url.path;
    if (request.method == 'GET' && path.endsWith('/ssh-hosts')) {
      calls.add(request);
      return reply({
        'code': 0,
        'data': [
          {
            ...base.host(5),
            'credential_id': cid,
            'credential': original,
            if (changedHost) 'modify_time': '2026-11-07T00:00:00.123456788Z',
          },
        ],
      }, 200);
    }
    if (request.method == 'GET' && path.endsWith('/credentials')) {
      calls.add(request);
      return reply({
        'code': 0,
        'data': [base.credential(9), if (created != null) created],
      }, 200);
    }
    if (request.method == 'POST' && path.endsWith('/credentials')) {
      calls.add(request);
      writes.add(request);
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      created = {
        ...base.credential(returnedId),
        ...body,
        if (wrongSecretReceipt) 'credential': 'different owned secret',
      };
      if (!createReached.isCompleted) createReached.complete();
      if (createGate != null) await createGate!.future;
      if (dropCreate) {
        throw http.ClientException('owned dropped creation response');
      }
      return reply({'code': 0, 'data': created}, 200);
    }
    if (request.method == 'PUT' && path.endsWith('/ssh-hosts/5')) {
      calls.add(request);
      writes.add(request);
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      cid = body['credential_id'] as int;
      if (dropBind) {
        throw http.ClientException('owned dropped binding response');
      }
      return reply({
        'code': 0,
        'data': {...base.host(5), ...body},
      }, 200);
    }
    return super.handle(request);
  }

  Future<AdminAssetMigrationPlan> prepare() async {
    final host = (await repo.readHosts(base.owner)).single;
    return repo.prepareLegacyMigration(
      base.owner,
      host,
      ' owned migrated credential ',
    );
  }
}

void main() {
  late MigrationHarness h;
  setUp(() {
    h = MigrationHarness();
  });
  tearDown(() {
    h.close();
  });
  test('prepare only reads and retains no raw-secret field', () async {
    final plan = await h.prepare();
    expect(plan.host.id, 5);
    expect(plan.host.credentialId, 0);
    expect(plan.credentialName, 'owned migrated credential');
    expect(plan.toString(), isNot(contains(h.original)));
    expect(h.writes, isEmpty);
  });
  test(
    'creation is a distinct receipt; binding is explicit and verifies actual ID and exact bytes',
    () async {
      final plan = await h.prepare();
      final created = await h.repo.createLegacyMigrationCredential(
        base.owner,
        plan,
      );
      expect(created.credential.id, 10);
      expect(h.cid, 0);
      expect(h.writes, hasLength(1));
      expect(jsonDecode(h.writes.single.body)['credential'], h.original);
      final bound = await h.repo.bindLegacyMigration(base.owner, created);
      expect(bound.host.id, 5);
      expect(bound.host.credentialId, 10);
      expect(h.writes.map((r) => r.method), ['POST', 'PUT']);
      final binding = jsonDecode(h.writes.last.body) as Map;
      expect(binding['credential_id'], 10);
      expect(binding.containsKey('credential'), isFalse);
      expect(h.calls.any((r) => r.url.path.endsWith('/test')), isFalse);
      expect(h.writes.any((r) => r.method == 'DELETE'), isFalse);
    },
  );
  test(
    'secret changed without metadata timestamp is detected before creation',
    () async {
      final plan = await h.prepare();
      h.original = 'different owned secret';
      await expectLater(
        h.repo.createLegacyMigrationCredential(base.owner, plan),
        throwsA(isA<AdminAssetTargetChanged>()),
      );
      expect(h.writes, isEmpty);
    },
  );
  test('lost first reply cannot replay creation or guess ID by name', () async {
    final plan = await h.prepare();
    h.dropCreate = true;
    await expectLater(
      h.repo.createLegacyMigrationCredential(base.owner, plan),
      throwsA(isA<AdminAssetWriteUnknown>()),
    );
    expect(h.created, isNotNull);
    expect(h.cid, 0);
    await expectLater(
      Future.sync(
        () => h.repo.createLegacyMigrationCredential(base.owner, plan),
      ),
      throwsA(isA<AdminAssetTargetChanged>()),
    );
    expect(h.writes, hasLength(1));
    final rows = await h.repo.readCredentials(base.owner);
    expect(rows.map((r) => r.id), contains(10));
    expect(h.cid, 0);
    expect(h.writes, hasLength(1));
  });
  test('existing returned ID is unknown and never bound', () async {
    final plan = await h.prepare();
    h.returnedId = 9;
    await expectLater(
      h.repo.createLegacyMigrationCredential(base.owner, plan),
      throwsA(isA<AdminAssetWriteUnknown>()),
    );
    expect(h.cid, 0);
    expect(h.writes, hasLength(1));
  });
  test('created secret mismatch is unknown and never bound', () async {
    final plan = await h.prepare();
    h.wrongSecretReceipt = true;
    await expectLater(
      h.repo.createLegacyMigrationCredential(base.owner, plan),
      throwsA(isA<AdminAssetWriteUnknown>()),
    );
    expect(h.cid, 0);
    expect(h.writes, hasLength(1));
  });
  test(
    'host changed after known creation stops before binding without deleting credential',
    () async {
      final created = await h.repo.createLegacyMigrationCredential(
        base.owner,
        await h.prepare(),
      );
      h.changedHost = true;
      await expectLater(
        h.repo.bindLegacyMigration(base.owner, created),
        throwsA(isA<AdminAssetTargetChanged>()),
      );
      expect(created.credential.id, 10);
      expect(h.created, isNotNull);
      expect(h.cid, 0);
      expect(h.writes, hasLength(1));
    },
  );
  test(
    'created secret changed without metadata timestamp stops before binding',
    () async {
      final created = await h.repo.createLegacyMigrationCredential(
        base.owner,
        await h.prepare(),
      );
      h.created!['credential'] = 'different owned secret';
      await expectLater(
        h.repo.bindLegacyMigration(base.owner, created),
        throwsA(isA<AdminAssetTargetChanged>()),
      );
      expect(h.cid, 0);
      expect(h.writes, hasLength(1));
    },
  );
  test(
    'lost second reply preserves known creation and forbids automatic PUT replay',
    () async {
      final created = await h.repo.createLegacyMigrationCredential(
        base.owner,
        await h.prepare(),
      );
      h.dropBind = true;
      await expectLater(
        h.repo.bindLegacyMigration(base.owner, created),
        throwsA(isA<AdminAssetWriteUnknown>()),
      );
      expect(created.credential.id, 10);
      expect(h.cid, 10);
      await expectLater(
        Future.sync(() => h.repo.bindLegacyMigration(base.owner, created)),
        throwsA(isA<AdminAssetTargetChanged>()),
      );
      expect(h.writes.map((r) => r.method), ['POST', 'PUT']);
      expect((await h.repo.readHosts(base.owner)).single.credentialId, 10);
      expect(h.writes, hasLength(2));
    },
  );
  test(
    'background retires migration plan so known credential cannot bind afterward',
    () async {
      final created = await h.repo.createLegacyMigrationCredential(
        base.owner,
        await h.prepare(),
      );
      h.repo.closeSecrets();
      await expectLater(
        Future.sync(() => h.repo.bindLegacyMigration(base.owner, created)),
        throwsA(isA<AdminAssetTargetChanged>()),
      );
      expect(h.writes, hasLength(1));
      expect(h.cid, 0);
    },
  );
  test(
    'background during submitted creation drops late plan and never continues to bind',
    () async {
      final plan = await h.prepare();
      h.createGate = Completer<void>();
      final result = expectLater(
        h.repo.createLegacyMigrationCredential(base.owner, plan),
        throwsA(isA<AdminAssetWriteUnknown>()),
      );
      await h.createReached.future;
      h.repo.closeSecrets();
      h.createGate!.complete();
      await result;
      expect(h.writes, hasLength(1));
      expect(h.cid, 0);
    },
  );
  test('fresh role loss after creation blocks second step', () async {
    final created = await h.repo.createLegacyMigrationCredential(
      base.owner,
      await h.prepare(),
    );
    h.role = 1;
    await expectLater(
      h.repo.bindLegacyMigration(base.owner, created),
      throwsA(isA<AdminAssetOwnerLost>()),
    );
    expect(h.writes, hasLength(1));
    expect(h.cid, 0);
  });
}
