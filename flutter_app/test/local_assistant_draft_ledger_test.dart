import 'package:bookstark_flutter/core/local_assistant_creation_receipts.dart';
import 'dart:async';
import 'package:bookstark_flutter/core/local_assistant_draft_payload.dart';
import 'package:bookstark_flutter/core/local_assistant_draft_ledger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final payload = LocalAssistantDraftPayload.note(
    title: 'Proposal',
    content: '## Review before saving',
  );
  test(
    'prepared intent survives reopening and cannot be cancelled or replayed',
    () async {
      final values = <String, String>{};
      LocalAssistantDraftLedger ledger() => LocalAssistantDraftLedger(
        namespace: 'db/session',
        readValue: (key) async => values[key],
        writeValue: (key, value) async {
          values[key] = value;
        },
      );
      final draft = await ledger().propose(payload);
      final prepared = await ledger().prepare(draft.id, payload.digest);
      expect(prepared.state, LocalAssistantDraftState.committing);
      expect((await ledger().load()).single.resourceId, isNull);
      await expectLater(ledger().cancel(draft.id), throwsStateError);
      await expectLater(
        ledger().prepare(draft.id, payload.digest),
        throwsStateError,
      );
      await ledger().markUnknown(draft.id);
      expect(
        (await ledger().load()).single.state,
        LocalAssistantDraftState.unknown,
      );
    },
  );
  test(
    'applied intent with lost acknowledgement loads without another storage write',
    () async {
      final values = <String, String>{};
      var lose = false, writes = 0;
      LocalAssistantDraftLedger ledger() => LocalAssistantDraftLedger(
        namespace: 'lost',
        readValue: (key) async => values[key],
        writeValue: (key, value) async {
          writes++;
          values[key] = value;
          if (lose) throw StateError('lost ack');
        },
      );
      final draft = await ledger().propose(payload);
      lose = true;
      await expectLater(
        ledger().prepare(draft.id, payload.digest),
        throwsA(isA<LocalAssistantDraftStorageUnknown>()),
      );
      expect(
        (await ledger().load()).single.state,
        LocalAssistantDraftState.committing,
      );
      expect(writes, 2);
      await expectLater(
        ledger().prepare(draft.id, payload.digest),
        throwsStateError,
      );
      expect(writes, 2);
    },
  );
  test('corrupt draft metadata is retained rather than replaced', () async {
    var writes = 0;
    final ledger = LocalAssistantDraftLedger(
      namespace: 'corrupt',
      readValue: (_) async => '{"version":1,"drafts":[{"id":"bad"}]}',
      writeValue: (_, _) async {
        writes++;
      },
    );
    await expectLater(ledger.propose(payload), throwsFormatException);
    expect(writes, 0);
  });
  test(
    'independent ledger owners serialize and preserve both proposals',
    () async {
      String? value;
      final started = Completer<void>(), release = Completer<void>();
      final first = LocalAssistantDraftLedger(
        namespace: 'ordered-drafts',
        readValue: (_) async => value,
        writeValue: (_, next) async {
          started.complete();
          await release.future;
          value = next;
        },
      );
      final old = first.propose(payload);
      await started.future;
      final second = LocalAssistantDraftLedger(
        namespace: 'ordered-drafts',
        readValue: (_) async => value,
        writeValue: (_, next) async {
          value = next;
        },
      );
      final newer = second.propose(
        LocalAssistantDraftPayload.task(content: 'Task'),
      );
      release.complete();
      await old;
      await newer;
      expect(
        (await second.load()).map((record) => record.payload.kind).toList(),
        [LocalAssistantDraftKind.note, LocalAssistantDraftKind.task],
      );
    },
  );
  test(
    'retired owner cannot mutate proposals and database namespaces isolate data',
    () async {
      final values = <String, String>{};
      var current = true;
      final first = LocalAssistantDraftLedger(
        namespace: 'db-a',
        isCurrent: () => current,
        readValue: (key) async => values[key],
        writeValue: (key, next) async {
          values[key] = next;
        },
      );
      await first.propose(payload);
      current = false;
      await expectLater(
        first.propose(payload),
        throwsA(isA<LocalAssistantDraftOwnerRetired>()),
      );
      final second = LocalAssistantDraftLedger(
        namespace: 'db-b',
        readValue: (key) async => values[key],
        writeValue: (key, next) async {
          values[key] = next;
        },
      );
      expect(await second.load(), isEmpty);
      expect(values.length, 1);
    },
  );
  test(
    'only fresh receipt absence can cancel an uncertain intent without retrying it',
    () async {
      final values = <String, String>{};
      final ledger = LocalAssistantDraftLedger(
        namespace: 'review-absent',
        readValue: (key) async => values[key],
        writeValue: (key, value) async {
          values[key] = value;
        },
      );
      final draft = await ledger.propose(payload);
      await ledger.prepare(draft.id, payload.digest);
      final existing = LocalAssistantCreationReceipt(
        key: draft.id,
        kind: payload.kind,
        resourceId: 7,
        inputHash: payload.digest,
        createdAt: 1,
      );
      await expectLater(
        ledger.cancelAfterReadOnlyReview(
          draft.id,
          expectedInputHash: payload.digest,
          readReceipt: () async => existing,
        ),
        throwsStateError,
      );
      expect(
        (await ledger.load()).single.state,
        LocalAssistantDraftState.committing,
      );
      await ledger.cancelAfterReadOnlyReview(
        draft.id,
        expectedInputHash: payload.digest,
        readReceipt: () async => null,
      );
      expect(
        (await ledger.load()).single.state,
        LocalAssistantDraftState.cancelled,
      );
      await expectLater(
        ledger.prepare(draft.id, payload.digest),
        throwsStateError,
      );
    },
  );
  test(
    'retirement during read-only review cannot cancel a durable intent',
    () async {
      final values = <String, String>{};
      var current = true;
      final ledger = LocalAssistantDraftLedger(
        namespace: 'review-retired',
        isCurrent: () => current,
        readValue: (key) async => values[key],
        writeValue: (key, value) async {
          values[key] = value;
        },
      );
      final draft = await ledger.propose(payload);
      await ledger.prepare(draft.id, payload.digest);
      await expectLater(
        ledger.cancelAfterReadOnlyReview(
          draft.id,
          expectedInputHash: payload.digest,
          readReceipt: () async {
            current = false;
            return null;
          },
        ),
        throwsA(isA<LocalAssistantDraftOwnerRetired>()),
      );
      current = true;
      expect(
        (await ledger.load()).single.state,
        LocalAssistantDraftState.committing,
      );
    },
  );
}
