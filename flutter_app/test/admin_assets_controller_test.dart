import 'package:bookstark_flutter/features/admin/admin_assets_repository.dart';
import 'dart:async';
import 'package:bookstark_flutter/features/admin/admin_assets_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'admin_assets_repository_test.dart' as base;
import 'admin_assets_mutations_test.dart' as writes;

void main() {
  late writes.Harness h;
  late AdminAssetsController c;
  setUp(() {
    h = writes.Harness();
    c = AdminAssetsController(h.repo, base.owner);
  });
  tearDown(() {
    c.dispose();
    h.close();
  });
  test(
    'independent host and credential loads do not erase each other',
    () async {
      expect(await c.load(AdminAssetCatalog.hosts), isTrue);
      h.credentialsStatus = 503;
      expect(await c.load(AdminAssetCatalog.credentials), isFalse);
      expect(c.hosts!.single.id, 5);
      expect(c.credentials, isNull);
      expect(c.loadState(AdminAssetCatalog.hosts), AdminAssetLoadState.ready);
      expect(
        c.loadState(AdminAssetCatalog.credentials),
        AdminAssetLoadState.failed,
      );
      expect(h.writes, isEmpty);
    },
  );
  test(
    'acknowledged create ID remains distinct from failed current-state read',
    () async {
      expect(
        await c.createCredential(writes.draft, 'owned new secret'),
        isTrue,
      );
      expect(c.operation, AdminAssetOperationState.acknowledged);
      expect(c.savedCredential!.id, 10);
      h.credentialsStatus = 503;
      expect(await c.load(AdminAssetCatalog.credentials), isFalse);
      expect(c.operation, AdminAssetOperationState.acknowledged);
      expect(c.savedCredential!.id, 10);
      expect(h.writes, hasLength(1));
    },
  );
  test(
    'unknown create blocks replay until explicit successful read-only review',
    () async {
      h.lost = true;
      expect(
        await c.createCredential(writes.draft, 'owned new secret'),
        isFalse,
      );
      expect(c.operation, AdminAssetOperationState.unknown);
      expect(c.savedCredential, isNull);
      expect(c.canWrite, isFalse);
      expect(
        await c.createCredential(writes.draft, 'owned new secret'),
        isFalse,
      );
      expect(c.finishUnknownReview(AdminAssetCatalog.credentials), isFalse);
      expect(h.writes, hasLength(1));
      expect(await c.load(AdminAssetCatalog.credentials), isTrue);
      expect(c.operation, AdminAssetOperationState.unknown);
      expect(h.writes, hasLength(1));
      expect(c.finishUnknownReview(AdminAssetCatalog.credentials), isTrue);
      expect(c.savedCredential, isNull);
      expect(c.canWrite, isTrue);
    },
  );
  test('permission loss clears catalogs and all old receipts', () async {
    await c.load(AdminAssetCatalog.hosts);
    await c.load(AdminAssetCatalog.credentials);
    h.role = 1;
    expect(await c.load(AdminAssetCatalog.hosts), isFalse);
    expect(c.operation, AdminAssetOperationState.ownerLost);
    expect(c.hosts, isNull);
    expect(c.credentials, isNull);
    expect(c.canWrite, isFalse);
    expect(await c.createCredential(writes.draft, 'owned new secret'), isFalse);
    expect(h.writes, isEmpty);
    expect(h.transport.closes, 0);
  });
  test('single pending write blocks another write and catalog read', () async {
    h.writeGate = Completer<void>();
    final pending = c.createCredential(writes.draft, 'owned new secret');
    await h.writeReached.future;
    expect(c.operation, AdminAssetOperationState.submitting);
    expect(await c.createCredential(writes.draft, 'owned duplicate'), isFalse);
    expect(await c.load(AdminAssetCatalog.hosts), isFalse);
    expect(h.writes, hasLength(1));
    h.writeGate!.complete();
    expect(await pending, isTrue);
  });
  test(
    'disposal during pending write does not resurrect result or notify',
    () async {
      var notifications = 0;
      c.addListener(() {
        notifications++;
      });
      h.writeGate = Completer<void>();
      final pending = c.createCredential(writes.draft, 'owned new secret');
      await h.writeReached.future;
      c.dispose();
      final count = notifications;
      h.writeGate!.complete();
      expect(await pending, isFalse);
      expect(c.savedCredential, isNull);
      expect(c.credentials, isNull);
      expect(notifications, count);
      expect(h.transport.closes, 0);
    },
  );
  test(
    'actual test receipt stays separate from stored offline or unknown status',
    () async {
      await c.load(AdminAssetCatalog.hosts);
      expect(await c.testHost(c.hosts!.single), isTrue);
      expect(c.connectionReceipt, isNotNull);
      expect(c.hosts, isNull);
      expect(await c.load(AdminAssetCatalog.hosts), isTrue);
      expect(c.hosts!.single.neverChecked, isTrue);
      expect(c.connectionReceipt, isNotNull);
      expect(h.writes, hasLength(1));
    },
  );
  test(
    'wrong-resource read cannot finish an unknown credential operation',
    () async {
      h.lost = true;
      await c.createCredential(writes.draft, 'owned new secret');
      expect(await c.load(AdminAssetCatalog.hosts), isTrue);
      expect(c.finishUnknownReview(AdminAssetCatalog.hosts), isFalse);
      expect(c.canWrite, isFalse);
      expect(await c.load(AdminAssetCatalog.credentials), isTrue);
      expect(c.finishMigrationReview(), isFalse);
      expect(c.finishUnknownReview(AdminAssetCatalog.credentials), isTrue);
      expect(c.lastUnconfirmedOperation, AdminAssetCatalog.credentials);
      expect(h.writes, hasLength(1));
    },
  );
  test(
    'fresh role loss during explicit secret reveal closes the whole controller',
    () async {
      await c.load(AdminAssetCatalog.credentials);
      final row = c.credentials!.single;
      final lease = await c.revealCredential(row);
      expect(lease.value, isNotNull);
      h.role = 1;
      await expectLater(
        c.revealCredential(row),
        throwsA(isA<AdminAssetOwnerLost>()),
      );
      expect(lease.value, isNull);
      expect(c.closed, isTrue);
      expect(c.credentials, isNull);
      expect(h.transport.closes, 0);
    },
  );
}
