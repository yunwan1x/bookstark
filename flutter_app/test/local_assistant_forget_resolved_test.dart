import 'dart:async';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/local_assistant_creation_receipts.dart';
import 'package:bookstark_flutter/core/local_assistant_draft_ledger.dart';
import 'package:bookstark_flutter/core/local_assistant_draft_payload.dart';
import 'package:bookstark_flutter/core/local_assistant_knowledge.dart';
import 'package:bookstark_flutter/core/local_assistant_repository.dart';
import 'package:bookstark_flutter/core/local_model_config.dart';
import 'package:bookstark_flutter/core/local_model_stream.dart';
import 'package:bookstark_flutter/core/local_store.dart';

void main() {
  final values = <String, String>{};
  var current = true, loseWrite = false, writes = 0;
  LocalAssistantDraftLedger ledger() => LocalAssistantDraftLedger(
    namespace: 'explicit-terminal-cleanup',
    isCurrent: () => current,
    readValue: (key) async => values[key],
    writeValue: (key, value) async {
      writes++;
      values[key] = value;
      if (loseWrite) throw StateError('lost storage acknowledgement');
    },
  );
  final payload = LocalAssistantDraftPayload.note(
    title: 'Proposal',
    content: 'Body',
  );
  setUp(() {
    values.clear();
    current = true;
    loseWrite = false;
    writes = 0;
  });
  test(
    'more than six explicit propose cancel forget rounds work without automatic pruning',
    () async {
      var checks = 0;
      for (var round = 0; round < 14; round++) {
        final record = await ledger().propose(payload);
        await ledger().cancel(record.id);
        expect((await ledger().load()).length, 1);
        await ledger().forgetResolved(
          record.id,
          canForget: (fresh) async {
            checks++;
            expect(fresh.state, LocalAssistantDraftState.cancelled);
            return true;
          },
        );
        expect(await ledger().load(), isEmpty);
      }
      expect(checks, 14);
    },
  );
  test(
    'unresolved pending committing unknown records never invoke safety callback or prune',
    () async {
      var checks = 0;
      for (final state in ['pending', 'committing', 'unknown']) {
        final record = await ledger().propose(payload);
        if (state != 'pending') await ledger().prepare(record.id, 'c' * 64);
        if (state == 'unknown') await ledger().markUnknown(record.id);
        final before = Map<String, String>.of(values), beforeWrites = writes;
        await expectLater(
          ledger().forgetResolved(
            record.id,
            canForget: (_) async {
              checks++;
              return true;
            },
          ),
          throwsA(isA<LocalAssistantDraftNeedsAttention>()),
        );
        expect(values, before);
        expect(writes, beforeWrites);
      }
      expect(checks, 0);
      expect((await ledger().load()).length, 3);
    },
  );
  test(
    'false safety callback retains all six terminal records and does not free quota',
    () async {
      final records = <LocalAssistantDraftRecord>[];
      for (var i = 0; i < 6; i++) {
        final record = await ledger().propose(payload);
        records.add(record);
        await ledger().cancel(record.id);
      }
      final before = Map<String, String>.of(values);
      await expectLater(
        ledger().forgetResolved(
          records.first.id,
          canForget: (_) async => false,
        ),
        throwsA(isA<LocalAssistantDraftNeedsAttention>()),
      );
      expect(values, before);
      await expectLater(ledger().propose(payload), throwsStateError);
      expect((await ledger().load()).length, 6);
    },
  );
  test(
    'created record removal preserves all other record bytes and does not touch receipt object',
    () async {
      final first = await ledger().propose(payload);
      final other = await ledger().propose(payload);
      await ledger().prepare(first.id, 'c' * 64);
      final receipt = LocalAssistantCreationReceipt(
        key: first.id,
        kind: LocalAssistantDraftKind.note,
        resourceId: 89,
        inputHash: 'c' * 64,
        createdAt: 123,
      );
      await ledger().acknowledge(first.id, receipt);
      final originalOther = (await ledger().load()).last.toJson();
      await ledger().forgetResolved(
        first.id,
        canForget: (fresh) async {
          expect(fresh.resourceId, 89);
          expect(fresh.inputHash, receipt.inputHash);
          return true;
        },
      );
      expect((await ledger().load()).single.id, other.id);
      expect((await ledger().load()).single.toJson(), originalOther);
      expect(receipt.resourceId, 89);
    },
  );
  test(
    'metadata I/O failure and retiring owner retain record without a storage write',
    () async {
      final record = await ledger().propose(payload);
      await ledger().cancel(record.id);
      final before = Map<String, String>.of(values), beforeWrites = writes;
      await expectLater(
        ledger().forgetResolved(
          record.id,
          canForget: (_) async => throw StateError('private I/O detail'),
        ),
        throwsA(isA<LocalAssistantDraftNeedsAttention>()),
      );
      expect(values, before);
      expect(writes, beforeWrites);
      await expectLater(
        ledger().forgetResolved(
          record.id,
          canForget: (_) async {
            current = false;
            return true;
          },
        ),
        throwsA(isA<LocalAssistantDraftOwnerRetired>()),
      );
      expect(values, before);
      expect(writes, beforeWrites);
    },
  );
  test(
    'applied ledger removal with lost acknowledgement never reports success',
    () async {
      final record = await ledger().propose(payload);
      await ledger().cancel(record.id);
      loseWrite = true;
      await expectLater(
        ledger().forgetResolved(record.id, canForget: (_) async => true),
        throwsA(isA<LocalAssistantDraftStorageUnknown>()),
      );
      loseWrite = false;
      expect(await ledger().load(), isEmpty);
    },
  );
  test(
    'static queue serializes safety check with another owner proposal and keeps new record',
    () async {
      final record = await ledger().propose(payload);
      await ledger().cancel(record.id);
      final started = Completer<void>(), release = Completer<bool>();
      final forget = ledger().forgetResolved(
        record.id,
        canForget: (_) {
          started.complete();
          return release.future;
        },
      );
      await started.future;
      var proposed = false;
      final next = ledger().propose(payload).then((value) {
        proposed = true;
        return value;
      });
      await Future<void>.delayed(Duration.zero);
      expect(proposed, false);
      release.complete(true);
      await forget;
      final newer = await next;
      expect((await ledger().load()).single.id, newer.id);
    },
  );
  test(
    'repository explicit safety callback removes only record and fresh open makes no HTTP or SQL access',
    () async {
      final record = await ledger().propose(payload);
      await ledger().cancel(record.id);
      var requests = 0, checks = 0;
      final path =
          '${Platform.environment['BOOKSTARK_APK_TEST_ROOT'] ?? Directory.systemTemp.path}/unopened-forget-store.db';
      final store = LocalStore(
        path: path,
        factory: databaseFactoryFfiNoIsolate,
      );
      final transport = LocalModelStreamTransport(
        LocalModelConfig(
          endpoint: 'https://model.invalid/v1',
          model: 'fixture',
        ),
        createClient: () => MockClient((_) async {
          requests++;
          return http.Response('', 500);
        }),
      );
      final repository = LocalAssistantRepository(
        sessionId: 'a' * 32,
        transport: transport,
        knowledge: LocalAssistantKnowledge(store, permitted: () => false),
        allowKnowledge: false,
        draftLedger: ledger(),
        canForgetResolved: (fresh) async {
          checks++;
          expect(fresh.id, record.id);
          return true;
        },
      );
      expect((await repository.open()).drafts.length, 1);
      await repository.forgetResolved(record.id);
      expect((await repository.open()).drafts, isEmpty);
      expect(requests, 0);
      expect(checks, 1);
      expect(File(path).existsSync(), false);
      repository.close();
      await store.close();
    },
  );
}
