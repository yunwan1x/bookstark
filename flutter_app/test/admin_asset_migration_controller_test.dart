import 'package:bookstark_flutter/features/admin/admin_assets_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'admin_assets_repository_test.dart' as base;
import 'admin_asset_migration_test.dart' as fixture;

void main() {
  late fixture.MigrationHarness h;
  late AdminAssetsController c;
  setUp(() {
    h = fixture.MigrationHarness();
    c = AdminAssetsController(h.repo, base.owner);
  });
  tearDown(() {
    c.dispose();
    h.close();
  });
  Future<void> prepare() async {
    expect(await c.load(AdminAssetCatalog.hosts), isTrue);
    expect(
      await c.prepareMigration(c.hosts!.single, 'owned migrated credential'),
      isTrue,
    );
  }

  test(
    'separate create and bind retain actual first receipt without assuming completion',
    () async {
      await prepare();
      expect(h.writes, isEmpty);
      expect(await c.createMigrationCredential(), isTrue);
      expect(c.migrationPartial, isTrue);
      expect(c.migrationCreated!.credential.id, 10);
      expect(c.migrationBound, isNull);
      expect(h.cid, 0);
      expect(await c.bindMigration(), isTrue);
      expect(c.migrationPartial, isFalse);
      expect(c.migrationBound!.host.credentialId, 10);
      expect(h.writes.map((r) => r.method), ['POST', 'PUT']);
    },
  );
  test(
    'lost second reply preserves known creation and requires explicit read-only finish',
    () async {
      await prepare();
      await c.createMigrationCredential();
      h.dropBind = true;
      expect(await c.bindMigration(), isFalse);
      expect(c.operation, AdminAssetOperationState.unknown);
      expect(c.migrationCreated!.credential.id, 10);
      expect(c.migrationPartial, isTrue);
      expect(await c.bindMigration(), isFalse);
      expect(h.writes, hasLength(2));
      expect(c.finishMigrationReview(), isFalse);
      expect(await c.load(AdminAssetCatalog.hosts), isTrue);
      expect(await c.load(AdminAssetCatalog.credentials), isTrue);
      expect(c.operation, AdminAssetOperationState.unknown);
      expect(c.finishMigrationReview(), isTrue);
      expect(c.migrationCreated, isNull);
      expect(h.writes, hasLength(2));
    },
  );
  test(
    'background retires partial plan while retaining safe creation receipt',
    () async {
      await prepare();
      await c.createMigrationCredential();
      c.background();
      expect(c.migrationRetired, isTrue);
      expect(c.migrationCreated!.credential.id, 10);
      expect(await c.bindMigration(), isFalse);
      expect(h.writes, hasLength(1));
      expect(
        await c.prepareMigration(
          (await h.repo.readHosts(base.owner)).single,
          'another owned name',
        ),
        isFalse,
      );
    },
  );
  test('role loss clears partial receipt and every owned catalog', () async {
    await prepare();
    await c.createMigrationCredential();
    h.role = 1;
    expect(await c.bindMigration(), isFalse);
    expect(c.operation, AdminAssetOperationState.ownerLost);
    expect(c.migrationCreated, isNull);
    expect(c.migrationPlan, isNull);
    expect(c.hosts, isNull);
    expect(h.writes, hasLength(1));
  });
}
