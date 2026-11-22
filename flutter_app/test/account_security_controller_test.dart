import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/account_password_repository.dart';
import 'package:bookstark_flutter/core/account_security_controller.dart';

class Repo implements AccountPasswordRepository {
  String password = 'current-pass';
  bool lose = false,
      verifyFails = false,
      storeFails = false,
      preflightFails = false;
  int writes = 0, verifies = 0, stores = 0;
  Completer<void>? wait;
  @override
  Future<void> change(String current, String next) async {
    if (preflightFails) {
      throw const AccountPasswordPreflightFailure();
    }
    writes++;
    if (current != password) {
      throw const ApiFailure(400, 'wrong fixture password');
    }
    if (wait != null) {
      await wait!.future;
    }
    password = next;
    if (lose) {
      throw TimeoutException('lost receipt');
    }
  }

  @override
  Future<void> verifyAndAdopt(String candidate) async {
    verifies++;
    if (verifyFails || candidate != password) {
      throw const ApiFailure(401, 'fixture verification unavailable');
    }
  }

  @override
  Future<bool> persistSession() async {
    stores++;
    if (storeFails) {
      throw StateError('fixture storage unavailable');
    }
    return true;
  }
}

void main() {
  test(
    'known password change verifies new raw credentials and separately saves actual session',
    () async {
      final r = Repo();
      final state = AccountSecurityController(r);
      await state.change('current-pass', ' raw new ');
      expect(state.phase, AccountSecurityPhase.complete);
      expect(state.receivedWriteReceipt, isTrue);
      expect(state.credentialsVerified, isTrue);
      expect(r.password, ' raw new ');
      expect([r.writes, r.verifies, r.stores], [1, 1, 1]);
      state.dispose();
    },
  );
  test(
    'lost applied change never resends or automatically logs in; explicit candidate verification works',
    () async {
      final r = Repo()..lose = true;
      final c = AccountSecurityController(r);
      await c.change('current-pass', 'new-pass');
      expect(c.phase, AccountSecurityPhase.unknown);
      expect(r.verifies, 0);
      await c.change('current-pass', 'again-pass');
      expect(r.writes, 1);
      await c.verify();
      expect(c.phase, AccountSecurityPhase.complete);
      expect(c.receivedWriteReceipt, isFalse);
      expect([r.writes, r.verifies, r.stores], [1, 1, 1]);
      c.dispose();
    },
  );
  test(
    'verification failure retains change receipt and an explicit retry does not PUT again',
    () async {
      final r = Repo()..verifyFails = true;
      final c = AccountSecurityController(r);
      await c.change('current-pass', 'new-pass');
      expect(c.phase, AccountSecurityPhase.unverified);
      expect(c.receivedWriteReceipt, isTrue);
      expect(r.stores, 0);
      r.verifyFails = false;
      await c.verify();
      expect(c.phase, AccountSecurityPhase.complete);
      expect([r.writes, r.verifies, r.stores], [1, 2, 1]);
      c.dispose();
    },
  );
  test(
    'storage retry saves only session without redoing credentials or password mutation',
    () async {
      final r = Repo()..storeFails = true;
      final c = AccountSecurityController(r);
      await c.change('current-pass', 'new-pass');
      expect(c.phase, AccountSecurityPhase.sessionUnstored);
      expect(c.credentialsVerified, isTrue);
      await c.change('new-pass', 'again-pass');
      await c.verify();
      expect([r.writes, r.verifies, r.stores], [1, 1, 1]);
      r.storeFails = false;
      await c.persist();
      expect(c.phase, AccountSecurityPhase.complete);
      expect([r.writes, r.verifies, r.stores], [1, 1, 2]);
      c.dispose();
    },
  );
  test(
    'preflight and wrong current password are definite rejections and do not verify new candidate',
    () async {
      for (final preflight in [false, true]) {
        final r = Repo()..preflightFails = preflight;
        final c = AccountSecurityController(r);
        await c.change('wrong-current', 'new-pass');
        expect(c.phase, AccountSecurityPhase.rejected);
        await c.verify();
        expect(r.verifies, 0);
        expect(r.stores, 0);
        expect(r.password, 'current-pass');
        c.dispose();
      }
    },
  );
  test(
    'concurrent changes are blocked; disposal suppresses later credential or storage operations',
    () async {
      final r = Repo()..wait = Completer<void>();
      final c = AccountSecurityController(r);
      final pending = c.change('current-pass', 'new-pass');
      await c.change('current-pass', 'again-pass');
      expect(r.writes, 1);
      c.dispose();
      r.wait!.complete();
      await pending;
      expect(r.verifies, 0);
      expect(r.stores, 0);
      c.dispose();
    },
  );
}
