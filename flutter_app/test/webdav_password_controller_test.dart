import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/webdav_password_repository.dart';
import 'package:bookstark_flutter/core/webdav_password_controller.dart';
import 'webdav_password_repository_test.dart' as fixture;

class Repo implements WebdavPasswordRepository {
  String? password;
  bool loseReset = false,
      loseRevoke = false,
      verifyFails = false,
      readFails = false,
      disposed = false;
  int resets = 0, revokes = 0, verifies = 0;
  @override
  Future<WebdavCredentialProfile> read() async {
    if (readFails) {
      throw StateError('fixture read failed');
    }
    return WebdavCredentialProfile(
      account: 'fixture',
      endpoint: Uri.parse('https://example.test/dav'),
      hasPassword: password != null,
    );
  }

  @override
  Future<String> reset({String? password}) async {
    resets++;
    this.password = password ?? fixture.generated;
    if (loseReset) {
      throw StateError('fixture receipt lost');
    }
    return this.password!;
  }

  @override
  Future<void> verify(String candidate) async {
    verifies++;
    if (verifyFails || candidate != password) {
      throw StateError('fixture verification unavailable');
    }
  }

  @override
  Future<void> revoke() async {
    revokes++;
    password = null;
    if (loseRevoke) {
      throw StateError('fixture revocation receipt lost');
    }
  }

  @override
  void dispose() {
    disposed = true;
  }
}

void main() {
  test(
    'known reset verifies actual new credentials once and keeps result only in memory',
    () async {
      final r = Repo();
      final c = WebdavPasswordController(r);
      await c.load();
      await c.reset();
      expect(c.phase, WebdavPasswordPhase.confirmed);
      expect(c.result!.secret, fixture.generated);
      expect(c.receivedReceipt, true);
      expect([r.resets, r.verifies], [1, 1]);
      expect(c.result.toString(), isNot(contains(fixture.generated)));
      c.clearSecret();
      expect(c.result, isNull);
      c.dispose();
      expect(r.disposed, true);
    },
  );
  test(
    'unknown custom reset never repeats or automatically verifies; explicit probe can confirm candidate',
    () async {
      final r = Repo()..loseReset = true;
      final c = WebdavPasswordController(r);
      await c.load();
      await c.reset(password: ' custom 密码 ');
      expect(c.phase, WebdavPasswordPhase.unknown);
      expect(c.canVerify, true);
      expect(r.verifies, 0);
      await c.reset();
      expect(r.resets, 1);
      await c.verify();
      expect(c.phase, WebdavPasswordPhase.confirmed);
      expect(c.result!.receivedReceipt, false);
      expect(c.result!.secret, ' custom 密码 ');
      expect([r.resets, r.verifies], [1, 1]);
      c.dispose();
    },
  );
  test(
    'unknown random reset cannot recover missing secret from has-password flag',
    () async {
      final r = Repo()..loseReset = true;
      final c = WebdavPasswordController(r);
      await c.load();
      await c.reset();
      expect(c.canVerify, false);
      await c.load();
      expect(c.profile!.hasPassword, true);
      expect(c.phase, WebdavPasswordPhase.unknown);
      expect(c.result, isNull);
      expect(r.resets, 1);
      c.acknowledgeUnknown();
      expect(c.phase, WebdavPasswordPhase.ready);
      expect(r.resets, 1);
      c.dispose();
    },
  );
  test(
    'known receipt plus failed Basic probe retains candidate for read-only retry',
    () async {
      final r = Repo()..verifyFails = true;
      final c = WebdavPasswordController(r);
      await c.load();
      await c.reset();
      expect(c.phase, WebdavPasswordPhase.unverified);
      expect(c.receivedReceipt, true);
      expect(c.result, isNull);
      r.verifyFails = false;
      await c.verify();
      expect(c.phase, WebdavPasswordPhase.confirmed);
      expect([r.resets, r.verifies], [1, 2]);
      c.dispose();
    },
  );
  test(
    'unknown applied revocation confirms actual absence by explicit GET and never another DELETE',
    () async {
      final r = Repo()
        ..password = fixture.generated
        ..loseRevoke = true;
      final c = WebdavPasswordController(r);
      await c.load();
      await c.revoke();
      expect(c.phase, WebdavPasswordPhase.revokeUnknown);
      await c.revoke();
      expect(r.revokes, 1);
      await c.load();
      expect(c.phase, WebdavPasswordPhase.revoked);
      expect(c.receivedReceipt, false);
      expect(c.profile!.hasPassword, false);
      expect(r.revokes, 1);
      c.dispose();
    },
  );
}
