import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/content_password_controller.dart';
import 'package:bookstark_flutter/core/content_password_repository.dart';

class Repo implements ContentPasswordRepository {
  String? password;
  bool lost = false, readFails = false, verifyFails = false;
  int writes = 0, reads = 0, verifies = 0;
  @override
  Future<ContentProtection> read(int id) async {
    reads++;
    if (readFails) {
      throw StateError('read lost');
    }
    return ContentProtection(
      id: id,
      title: 'actual',
      protected: password != null,
    );
  }

  @override
  Future<void> change(
    ContentProtection baseline, {
    required String newPassword,
    String? currentPassword,
  }) async {
    writes++;
    if (password != null && currentPassword != password) {
      throw const ApiFailure(400, 'wrong current password');
    }
    password = newPassword.isEmpty ? null : newPassword;
    if (lost) {
      throw StateError('receipt lost');
    }
  }

  @override
  Future<void> verify(int id, String value) async {
    verifies++;
    if (verifyFails || password != value) {
      throw const ApiFailure(400, 'verification failed');
    }
  }
}

void main() {
  test(
    'acknowledged set verifies actual new password, not only the boolean, and preserves spaces',
    () async {
      final r = Repo();
      final c = ContentPasswordController(r, 7);
      await c.load();
      await c.change(newPassword: ' raw spaces ');
      expect(c.phase, ContentPasswordPhase.confirmed);
      expect(c.receivedWriteReceipt, isTrue);
      expect(r.password, ' raw spaces ');
      expect(r.verifies, 1);
      expect(r.writes, 1);
      expect(c.protection!.protected, isTrue);
      c.dispose();
    },
  );
  test(
    'lost applied mutation is not resent; explicit read verification confirms actual desired password',
    () async {
      final r = Repo()..lost = true;
      final c = ContentPasswordController(r, 7);
      await c.load();
      await c.change(newPassword: 'new');
      expect(c.phase, ContentPasswordPhase.unknown);
      await c.change(newPassword: 'again');
      await c.load();
      expect(r.writes, 1);
      await c.inspect();
      expect(c.phase, ContentPasswordPhase.confirmed);
      expect(c.receivedWriteReceipt, isFalse);
      expect(r.verifies, 1);
      expect(r.writes, 1);
      c.dispose();
    },
  );
  test(
    'protected true with wrong candidate stays unresolved and cannot overwrite another change',
    () async {
      final r = Repo()..lost = true;
      final c = ContentPasswordController(r, 7);
      await c.load();
      await c.change(newPassword: 'candidate');
      r.password = 'third party';
      await c.inspect();
      expect(c.phase, ContentPasswordPhase.unknown);
      expect(c.protection!.protected, isTrue);
      await c.change(newPassword: 'again');
      expect(r.writes, 1);
      c.dispose();
    },
  );
  test(
    'receipt followed by read failure retains receipt and only verifies on retry',
    () async {
      final r = Repo();
      final c = ContentPasswordController(r, 7);
      await c.load();
      r.readFails = true;
      await c.change(newPassword: 'new');
      expect(c.phase, ContentPasswordPhase.unverified);
      expect(c.receivedWriteReceipt, isTrue);
      r.readFails = false;
      await c.inspect();
      expect(c.phase, ContentPasswordPhase.confirmed);
      expect(r.writes, 1);
      c.dispose();
    },
  );
  test(
    'wrong current password is definite failure and clear requires actual current password',
    () async {
      final r = Repo()..password = 'old';
      final c = ContentPasswordController(r, 7);
      await c.load();
      await c.change(newPassword: 'new', currentPassword: 'wrong');
      expect(c.phase, ContentPasswordPhase.failed);
      expect(r.password, 'old');
      await c.load();
      await c.change(newPassword: '', currentPassword: 'old');
      expect(c.phase, ContentPasswordPhase.confirmed);
      expect(c.protection!.protected, isFalse);
      expect(r.verifies, 0);
      c.dispose();
    },
  );
  test(
    'disposing clears metadata and ignores read-only verification late callbacks',
    () async {
      final r = Repo()..lost = true;
      final c = ContentPasswordController(r, 7);
      await c.load();
      await c.change(newPassword: 'new');
      c.dispose();
      await c.inspect();
      expect(c.protection, isNull);
      expect(r.verifies, 0);
      c.dispose();
    },
  );
}
