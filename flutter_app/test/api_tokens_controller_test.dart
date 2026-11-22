import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/api_tokens_repository.dart';
import 'package:bookstark_flutter/core/api_tokens_controller.dart';
import 'api_tokens_repository_test.dart' as fixture;

class Repo implements ApiTokensRepository {
  final rows = <ApiTokenEntry>[];
  bool loseCreate = false,
      loseDelete = false,
      readFails = false,
      disposed = false;
  int creates = 0, deletes = 0;
  @override
  Future<ApiTokensPage> read() async {
    if (readFails) {
      throw StateError('fixture read unavailable');
    }
    return ApiTokensPage(rows);
  }

  @override
  Future<CreatedApiToken> create(String name) async {
    creates++;
    final row = ApiTokenEntry.fromJson(
      fixture.entry(id: creates, name: name.isEmpty ? 'default' : name),
      7,
    );
    rows.add(row);
    if (loseCreate) {
      throw StateError('fixture receipt lost');
    }
    return CreatedApiToken(row, fixture.secret);
  }

  @override
  Future<void> revoke(ApiTokenEntry entry) async {
    deletes++;
    rows.removeWhere((row) => row.id == entry.id);
    if (loseDelete) {
      throw StateError('fixture delete receipt lost');
    }
  }

  @override
  void dispose() {
    disposed = true;
  }
}

void main() {
  test(
    'one-time secret exists only after actual create and can be explicitly cleared',
    () async {
      final r = Repo();
      final c = ApiTokensController(r);
      await c.load();
      expect(r.creates, 0);
      await c.create('fixture');
      expect(c.phase, ApiTokenPhase.created);
      expect(c.created!.secret, fixture.secret);
      expect(c.page!.entries.length, 1);
      c.clearSecret();
      expect(c.created, isNull);
      expect(c.latestCreated!.id, 1);
      c.dispose();
      expect(r.disposed, true);
    },
  );
  test(
    'unknown create blocks automatic repetition; refresh reads only masks and does not recover secret',
    () async {
      final r = Repo()..loseCreate = true;
      final c = ApiTokensController(r);
      await c.load();
      await c.create('fixture');
      expect(c.phase, ApiTokenPhase.createUnknown);
      expect(c.created, isNull);
      await c.create('again');
      expect(r.creates, 1);
      await c.load();
      expect(c.phase, ApiTokenPhase.createUnknown);
      expect(c.page!.entries.length, 1);
      expect(c.created, isNull);
      expect(r.creates, 1);
      c.acknowledgeUnknownCreate();
      expect(c.phase, ApiTokenPhase.ready);
      c.dispose();
    },
  );
  test(
    'known revoke requires actual readback and clears result secret after observed absence',
    () async {
      final r = Repo();
      final c = ApiTokensController(r);
      await c.load();
      await c.create('fixture');
      await c.revoke(c.created!.entry);
      expect(c.phase, ApiTokenPhase.revoked);
      expect(c.receivedRevocationReceipt, true);
      expect(c.page!.entries, isEmpty);
      expect(c.created, isNull);
      expect(r.deletes, 1);
      c.dispose();
    },
  );
  test(
    'unknown revoke is verified by explicit read without repeating DELETE',
    () async {
      final r = Repo()..loseDelete = true;
      final c = ApiTokensController(r);
      await c.load();
      await c.create('fixture');
      await c.revoke(c.created!.entry);
      expect(c.phase, ApiTokenPhase.revokeUnknown);
      expect(r.deletes, 1);
      await c.load();
      expect(c.phase, ApiTokenPhase.revoked);
      expect(c.receivedRevocationReceipt, false);
      expect(r.deletes, 1);
      c.dispose();
    },
  );
  test(
    'failed read after known revocation preserves its receipt for later verification',
    () async {
      final r = Repo();
      final c = ApiTokensController(r);
      await c.load();
      await c.create('fixture');
      r.readFails = true;
      await c.revoke(c.created!.entry);
      expect(c.phase, ApiTokenPhase.revokeUnverified);
      expect(c.receivedRevocationReceipt, true);
      r.readFails = false;
      await c.load();
      expect(c.phase, ApiTokenPhase.revoked);
      expect(r.deletes, 1);
      c.dispose();
    },
  );
}
