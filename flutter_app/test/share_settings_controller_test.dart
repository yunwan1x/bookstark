import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/public_share_models.dart';
import 'package:bookstark_flutter/core/share_settings_repository.dart';
import 'package:bookstark_flutter/core/share_settings_controller.dart';

class Repo implements ShareSettingsRepository {
  bool visible = false;
  int writes = 0, reads = 0;
  bool lose = false;
  Object? reject;
  Completer<void>? wait;
  final token = List.filled(64, 'b').join();
  @override
  Future<bool> status(OwnerShareTarget t) async {
    reads++;
    return visible;
  }

  @override
  Future<OwnerShareReceipt> publish(OwnerShareTarget t) async {
    writes++;
    if (wait != null) {
      await wait!.future;
    }
    if (reject != null) {
      throw reject!;
    }
    visible = true;
    return OwnerShareReceipt(
      t,
      PublicShareReference(Uri.parse('https://example.test'), 'actual'),
      token,
    );
  }

  @override
  Future<OwnerShareReceipt> changeToken(
    OwnerShareTarget t,
    OwnerShareReceipt old,
    ShareTokenAction a,
  ) async {
    writes++;
    if (lose) {
      throw StateError('lost receipt');
    }
    return OwnerShareReceipt(
      t,
      old.reference,
      a == ShareTokenAction.disable ? '' : token,
    );
  }

  @override
  Future<void> unpublish(OwnerShareTarget t) async {
    writes++;
    visible = false;
    if (lose) {
      throw StateError('lost delete receipt');
    }
  }
}

void main() {
  OwnerShareTarget resource() => OwnerShareTarget(
    kind: PublicShareKind.blog,
    id: 3,
    title: 'Saved resource',
  );
  test(
    'opening and refreshing only GET status and never fabricate share links',
    () async {
      final r = Repo()..visible = true;
      final c = ShareSettingsController(r, resource());
      await c.load();
      expect(c.published, isTrue);
      expect(c.receipt, isNull);
      expect(r.writes, 0);
      await c.publish();
      expect(c.receipt!.editingEnabled, isTrue);
      await c.load();
      expect(c.receipt, isNull);
      expect(r.writes, 1);
      c.dispose();
    },
  );
  test(
    'lost token mutation hides old capability and blocks implicit repeat even after status GET',
    () async {
      final r = Repo();
      final c = ShareSettingsController(r, resource());
      await c.publish();
      r.lose = true;
      await c.changeToken(ShareTokenAction.reset);
      expect(c.phase, ShareSettingsPhase.unknown);
      expect(c.receipt, isNull);
      final writes = r.writes;
      await c.load();
      await c.publish();
      await c.changeToken(ShareTokenAction.reset);
      await c.unpublish();
      await c.inspectUnknown();
      expect(c.observedAfterUnknown, isTrue);
      expect(c.uncertain, isTrue);
      expect(r.writes, writes);
      c.dispose();
    },
  );
  test(
    'explicit recovery republishes to recover current receipt rather than resetting again',
    () async {
      final r = Repo();
      final c = ShareSettingsController(r, resource());
      await c.publish();
      r.lose = true;
      await c.changeToken(ShareTokenAction.reset);
      r.lose = false;
      await c.publish(acknowledgeUnknown: true);
      expect(c.phase, ShareSettingsPhase.ready);
      expect(c.receipt, isNotNull);
      expect(r.writes, 3);
      c.dispose();
    },
  );
  test(
    'lost revoke stays unknown even when GET confirms unpublished and never automatically republishes',
    () async {
      final r = Repo();
      final c = ShareSettingsController(r, resource());
      await c.publish();
      r.lose = true;
      await c.unpublish();
      await c.inspectUnknown();
      expect(c.observedAfterUnknown, isFalse);
      expect(c.uncertain, isTrue);
      expect(c.receipt, isNull);
      expect(r.writes, 2);
      c.dispose();
    },
  );
  test(
    'definite permissions failure differs from unknown and never exposes server error details',
    () async {
      final r = Repo()
        ..reject = const ApiFailure(403, 'sensitive server details');
      final c = ShareSettingsController(r, resource());
      await c.publish();
      expect(c.phase, ShareSettingsPhase.failed);
      expect(c.receipt, isNull);
      expect(r.writes, 1);
      c.dispose();
    },
  );
  test(
    'concurrent writes are blocked and disposed controller discards late receipt',
    () async {
      final r = Repo()..wait = Completer<void>();
      final c = ShareSettingsController(r, resource());
      final pending = c.publish();
      await c.publish();
      await c.unpublish();
      expect(r.writes, 1);
      c.dispose();
      r.wait!.complete();
      await pending;
      expect(c.receipt, isNull);
      c.dispose();
    },
  );
}
