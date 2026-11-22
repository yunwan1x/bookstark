import 'dart:convert';
import 'dart:async';
import 'package:bookstark_flutter/core/local_assistant_creation_receipts.dart';
import 'package:bookstark_flutter/core/local_assistant_draft_ledger.dart';
import 'package:bookstark_flutter/core/local_assistant_draft_payload.dart';
import 'package:bookstark_flutter/core/local_assistant_write_journal.dart';
import 'package:bookstark_flutter/core/local_data_maintenance.dart';
import 'package:bookstark_flutter/core/local_recovery_inventory.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const binding = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
  const id = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  final payload = LocalAssistantDraftPayload.note(
    title: 'Sensitive title',
    content: 'Sensitive original body',
  );
  LocalAssistantDraftRecord record(
    LocalAssistantDraftState state, {
    int? resourceId,
    String? hash,
  }) => LocalAssistantDraftRecord(
    id: id,
    payload: payload,
    state: state,
    resourceId: resourceId,
    inputHash: hash,
  );
  LocalAssistantCreationReceipt receipt() => LocalAssistantCreationReceipt(
    key: id,
    kind: payload.kind,
    resourceId: 7,
    inputHash: payload.digest,
    createdAt: 1,
  );
  LocalRecoveryInventory inventory(Map<String, String> values) =>
      LocalRecoveryInventory(
        maintenance: LocalDataMaintenance(),
        localNamespaces: {'local'},
        preferencesMetadata: () async => {
          'format': 1,
          'secureKeys': values.keys
              .where((key) => key.startsWith('bookstark.local-'))
              .toList(),
          'htmlKeys': <String>[],
          'overflow': false,
          'valuesIncluded': false,
        },
        complexMetadata: () async => {
          'format': 1,
          'keys': <String>[],
          'unknownFiles': 0,
          'activeTransfers': 0,
          'overflow': false,
          'valuesIncluded': false,
        },
      );
  test(
    'body-free marker blocks backup using key metadata only until matching resolution',
    () async {
      final values = <String, String>{};
      var reads = 0;
      final journal = LocalAssistantWriteJournal(
        namespace: 'local',
        bindingId: binding,
        maintenance: LocalDataMaintenance(),
        readValue: (key) async {
          reads++;
          return values[key];
        },
        writeValue: (key, value) async {
          values[key] = value;
        },
        deleteValue: (key) async {
          values.remove(key);
        },
      );
      final marker = await journal.prepare(
        record(LocalAssistantDraftState.pending),
        payload.digest,
      );
      expect(marker.key, isNot(contains('Sensitive')));
      expect(values[marker.key], isNot(contains('Sensitive')));
      final before = reads;
      final summary = await inventory(values).read();
      expect(reads, before);
      expect(summary.references.single.kind, 'ai-create');
      expect(summary.references.single.recordId, marker.recordId);
      expect(summary.requireClear, throwsA(isA<PendingLocalRecovery>()));
      expect(LocalAssistantWriteMarker.fromKey(marker.key).inputHash, isNull);
      expect(
        (await journal.readMarker(
          LocalAssistantWriteMarker.fromKey(marker.key),
        ))!.inputHash,
        payload.digest,
      );
      await journal.clearAfterResolution(
        marker,
        record(
          LocalAssistantDraftState.created,
          resourceId: 7,
          hash: payload.digest,
        ),
        readReceipt: () async => receipt(),
      );
      expect((await inventory(values).read()).needsAttention, isFalse);
    },
  );
  test(
    'lost marker acknowledgement remains blocking and cannot be prepared again',
    () async {
      final values = <String, String>{};
      var writes = 0;
      final journal = LocalAssistantWriteJournal(
        namespace: 'local',
        bindingId: binding,
        maintenance: LocalDataMaintenance(),
        readValue: (key) async => values[key],
        writeValue: (key, value) async {
          values[key] = value;
          writes++;
          throw StateError('lost ack');
        },
        deleteValue: (key) async {
          values.remove(key);
        },
      );
      await expectLater(
        journal.prepare(
          record(LocalAssistantDraftState.pending),
          payload.digest,
        ),
        throwsA(isA<LocalAssistantWriteMarkerUnknown>()),
      );
      final marker = (await journal.readMarker(
        LocalAssistantWriteMarker.fromKey(values.keys.single),
      ))!;
      await expectLater(
        journal.prepare(
          record(LocalAssistantDraftState.pending),
          payload.digest,
        ),
        throwsStateError,
      );
      expect(writes, 1);
      expect((await inventory(values).read()).needsAttention, isTrue);
      await journal.clearAfterResolution(
        marker,
        record(LocalAssistantDraftState.cancelled),
        readReceipt: () async => null,
      );
      expect(values, isEmpty);
    },
  );
  test(
    'failed cleanup retries storage only while keeping a blocking marker',
    () async {
      final values = <String, String>{};
      var fail = true, deletes = 0, writes = 0, lookups = 0;
      final journal = LocalAssistantWriteJournal(
        namespace: 'local',
        bindingId: binding,
        maintenance: LocalDataMaintenance(),
        readValue: (key) async => values[key],
        writeValue: (key, value) async {
          values[key] = value;
          writes++;
        },
        deleteValue: (key) async {
          deletes++;
          if (fail) throw StateError('storage failure');
          values.remove(key);
        },
      );
      final marker = await journal.prepare(
        record(LocalAssistantDraftState.pending),
        payload.digest,
      );
      final resolved = record(
        LocalAssistantDraftState.created,
        resourceId: 7,
        hash: payload.digest,
      );
      Future<LocalAssistantCreationReceipt?> inspect() async {
        lookups++;
        return receipt();
      }

      await expectLater(
        journal.clearAfterResolution(marker, resolved, readReceipt: inspect),
        throwsA(isA<LocalAssistantWriteMarkerUnknown>()),
      );
      expect((await inventory(values).read()).needsAttention, isTrue);
      fail = false;
      await journal.clearAfterResolution(
        marker,
        resolved,
        readReceipt: inspect,
      );
      expect(deletes, 2);
      expect(lookups, 2);
      expect(writes, 1);
      expect(values, isEmpty);
    },
  );
  test('unresolved or mismatched receipts never remove the marker', () async {
    final values = <String, String>{};
    final journal = LocalAssistantWriteJournal(
      namespace: 'local',
      bindingId: binding,
      maintenance: LocalDataMaintenance(),
      readValue: (key) async => values[key],
      writeValue: (key, value) async {
        values[key] = value;
      },
      deleteValue: (key) async {
        values.remove(key);
      },
    );
    final marker = await journal.prepare(
      record(LocalAssistantDraftState.pending),
      payload.digest,
    );
    expect(
      () => journal.clearAfterResolution(
        marker,
        record(LocalAssistantDraftState.unknown, hash: payload.digest),
        readReceipt: () async => receipt(),
      ),
      throwsStateError,
    );
    await expectLater(
      journal.clearAfterResolution(
        marker,
        record(
          LocalAssistantDraftState.created,
          resourceId: 8,
          hash: payload.digest,
        ),
        readReceipt: () async => receipt(),
      ),
      throwsStateError,
    );
    expect(values.length, 1);
  });
  test(
    'retired delayed marker writer cannot resurrect a marker after newer cleanup',
    () async {
      final values = <String, String>{};
      final started = Completer<void>(), release = Completer<void>();
      var current = true;
      final gate = LocalDataMaintenance();
      final old = LocalAssistantWriteJournal(
        namespace: 'local',
        bindingId: binding,
        maintenance: gate,
        isCurrent: () => current,
        readValue: (key) async => values[key],
        writeValue: (key, value) async {
          started.complete();
          await release.future;
          values[key] = value;
        },
        deleteValue: (key) async {
          values.remove(key);
        },
      );
      final pending = old.prepare(
        record(LocalAssistantDraftState.pending),
        payload.digest,
      );
      final failed = expectLater(
        pending,
        throwsA(isA<LocalAssistantDraftOwnerRetired>()),
      );
      await started.future;
      current = false;
      final fresh = LocalAssistantWriteJournal(
        namespace: 'local',
        bindingId: binding,
        maintenance: gate,
        readValue: (key) async => values[key],
        writeValue: (key, value) async {
          values[key] = value;
        },
        deleteValue: (key) async {
          values.remove(key);
        },
      );
      final marker = LocalAssistantWriteMarker(
        namespace: 'local',
        bindingId: binding,
        draftId: id,
        kind: payload.kind,
        inputHash: payload.digest,
      );
      final cleanup = fresh.clearAfterResolution(
        marker,
        record(LocalAssistantDraftState.cancelled),
        readReceipt: () async => null,
      );
      release.complete();
      await failed;
      await cleanup;
      expect(values, isEmpty);
    },
  );
  test(
    'changed edited hash cannot create a second marker for the same draft',
    () async {
      final values = <String, String>{};
      final journal = LocalAssistantWriteJournal(
        namespace: 'local',
        bindingId: binding,
        maintenance: LocalDataMaintenance(),
        readValue: (key) async => values[key],
        writeValue: (key, value) async {
          values[key] = value;
        },
        deleteValue: (key) async {
          values.remove(key);
        },
      );
      final first = await journal.prepare(
        record(LocalAssistantDraftState.pending),
        payload.digest,
      );
      await expectLater(
        journal.prepare(record(LocalAssistantDraftState.pending), '0' * 64),
        throwsStateError,
      );
      expect(values.length, 1);
      expect(
        (await journal.readMarker(
          LocalAssistantWriteMarker.fromKey(first.key),
        ))!.inputHash,
        payload.digest,
      );
    },
  );
  test(
    'malformed metadata identity remains unknown and blocking without reading its value',
    () async {
      final bad =
          '${LocalAssistantWriteMarker.prefix}${base64Url.encode(utf8.encode(jsonEncode(['local', '["invalid"]'])))}';
      final summary = await inventory({bad: 'DO_NOT_READ'}).read();
      expect(summary.references, isEmpty);
      expect(summary.unknown, 1);
      expect(summary.requireClear, throwsA(isA<PendingLocalRecovery>()));
    },
  );
}
