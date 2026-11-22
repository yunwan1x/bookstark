// Draft only: NOT RUN. Memory flush is not Native durability evidence.
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/drive_models.dart';
import 'package:bookstark_flutter/core/drive_operation_record.dart';
import 'package:bookstark_flutter/core/drive_operation_store.dart';
import 'package:bookstark_flutter/core/drive_operation_transport.dart';
import 'package:bookstark_flutter/core/drive_operation_recovery_controller.dart';

class DriveEnv {
  static int next = 0;
  final scope = DriveOperationScope(
    server: 'https://example.test/prefix',
    member: 7,
    binding: (++next).toRadixString(16).padLeft(32, '0'),
  );
  final values = <String, String>{};
  int sends = 0, reads = 0, writes = 0;
  bool current = true,
      drop = false,
      prepareFails = false,
      claimFlushFails = false,
      ackWriteFails = false,
      readFails = false,
      endFlushFails = false;
  Future<void> Function()? sendHook;
  Future<DriveOperationObservation> Function(String)? readHook;
  late final DriveOperationStore store = DriveOperationStore(
    scope: scope,
    isCurrent: () => current,
    readValue: (k) async => values[k],
    writeValue: (k, v) async {
      writes++;
      final record = DriveOperationRecord.decode(v);
      if (ackWriteFails && record.state == DriveOperationState.acknowledged) {
        ackWriteFails = false;
        throw StateError('write');
      }
      values[k] = v;
    },
    deleteValue: (k) async {
      values.remove(k);
    },
    flush: () async {
      if (endFlushFails && values.isEmpty) {
        endFlushFails = false;
        throw StateError('delete flush');
      }
      final raw = values[store.metadataKey];
      if (claimFlushFails &&
          raw != null &&
          DriveOperationRecord.decode(raw).state ==
              DriveOperationState.unknown) {
        claimFlushFails = false;
        throw StateError('claim flush');
      }
    },
  );
  late final transport = ExactDriveOperationTransport(
    isCurrent: () => current,
    prepare: (r) async {
      if (prepareFails) throw StateError('auth/CSRF failed before send');
      return PreparedDriveOperation(
        recordFingerprint: r.fingerprint,
        scopeIdentity: r.scope.identity,
        send: () async {
          sends++;
          if (sendHook != null) return sendHook!();
          if (drop) throw StateError('response lost');
        },
      );
    },
    observe: (path) async {
      reads++;
      if (readHook != null) return readHook!(path);
      if (readFails) throw StateError('403');
      return path.isEmpty
          ? root()
          : DriveOperationObservation(
              path: path,
              state: DriveObservationState.missing,
            );
    },
  );
  DriveOperationRecoveryController controller() =>
      DriveOperationRecoveryController(store: store, transport: transport);
  DriveOperationRecord pending({
    String key = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
  }) => DriveOperationRecord(
    scope: scope,
    key: key,
    kind: DriveOperationKind.rename,
    state: DriveOperationState.pending,
    source: DriveOperationObservation(
      path: 'a.md',
      state: DriveObservationState.found,
      node: node(),
    ),
    sourceParent: root(),
    destination: 'b.md',
    destinationParent: root(),
    destinationBefore: DriveOperationObservation(
      path: 'b.md',
      state: DriveObservationState.missing,
    ),
    createdAt: DateTime.utc(2026, 11, 11),
  );
}

DriveOperationObservation root() =>
    DriveOperationObservation(path: '', state: DriveObservationState.root);
DriveNode node({int id = 184, String path = 'a.md'}) => DriveNode(
  id: id,
  name: path,
  path: path,
  directory: false,
  size: 12,
  etag: 'original-etag',
  mime: 'text/markdown',
  modified: '2026-11-11T00:00:00Z',
);
void main() {
  test('dropped response survives restart and review never resends', () async {
    final e = DriveEnv()..drop = true, c = e.controller();
    addTearDown(c.dispose);
    await c.load();
    await c.beginAndSubmit(e.pending());
    expect(e.sends, 1);
    final cold = e.controller();
    addTearDown(cold.dispose);
    await cold.load();
    await cold.inspect();
    await cold.beginAndSubmit(e.pending());
    expect(e.sends, 1);
    expect(cold.record!.state, DriveOperationState.unknown);
    expect(cold.blocked, true);
  });
  test(
    'auth preparation failure and durable claim failure both send zero',
    () async {
      for (final claimFailure in [false, true]) {
        final e = DriveEnv();
        e.prepareFails = !claimFailure;
        e.claimFlushFails = claimFailure;
        final c = e.controller();
        addTearDown(c.dispose);
        await c.load();
        await c.beginAndSubmit(e.pending());
        expect(e.sends, 0);
        await c.load();
        expect(c.blocked, true);
        await c.beginAndSubmit(e.pending());
        expect(e.sends, 0);
      }
    },
  );
  test('two loaded controllers cannot send the same operation twice', () async {
    final e = DriveEnv(), a = e.controller(), b = e.controller();
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    await a.load();
    await b.load();
    final entered = Completer<void>(), response = Completer<void>();
    e.sendHook = () {
      entered.complete();
      return response.future;
    };
    final action = a.beginAndSubmit(e.pending());
    await entered.future;
    await b.beginAndSubmit(e.pending());
    expect(e.sends, 1);
    response.complete();
    await action;
    expect(e.sends, 1);
  });
  test('acknowledgment storage retry has zero additional sends', () async {
    final e = DriveEnv()..ackWriteFails = true, c = e.controller();
    addTearDown(c.dispose);
    await c.load();
    await c.beginAndSubmit(e.pending());
    expect(c.serverAcknowledged, true);
    expect(e.sends, 1);
    await c.retryAcknowledgmentStorage();
    expect(e.sends, 1);
    expect(c.record!.state, DriveOperationState.acknowledged);
  });
  test('permission failure is not a missing-path observation', () async {
    final e = DriveEnv()
          ..drop = true
          ..readFails = true,
        c = e.controller();
    addTearDown(c.dispose);
    await c.load();
    await c.beginAndSubmit(e.pending());
    await c.load();
    await c.inspect();
    expect(c.review, isNull);
    expect(c.safeError, isNotNull);
    expect(c.blocked, true);
    expect(e.sends, 1);
  });
  test(
    'ending record needs explicit confirmation and late ack cannot resurrect it',
    () async {
      final e = DriveEnv()..drop = true, c = e.controller();
      addTearDown(c.dispose);
      await c.load();
      await c.beginAndSubmit(e.pending());
      await c.load();
      final unknown = c.record!, raw = e.values[e.store.metadataKey];
      await c.endRecord(
        expectedFingerprint: unknown.fingerprint,
        explicitlyConfirmed: false,
      );
      expect(e.values[e.store.metadataKey], raw);
      await c.endRecord(
        expectedFingerprint: unknown.fingerprint,
        explicitlyConfirmed: true,
      );
      expect(e.values, isEmpty);
      expect(e.sends, 1);
      await expectLater(
        e.store.acknowledge(unknown),
        throwsA(isA<DriveOperationStorageUnconfirmed>()),
      );
      await expectLater(
        e.store.insert(e.pending()),
        throwsA(isA<DriveOperationStorageUnconfirmed>()),
      );
      expect(e.values, isEmpty);
    },
  );
  test(
    'failed end flush remains blocked until storage-only barrier confirms missing',
    () async {
      final e = DriveEnv()..drop = true, c = e.controller();
      addTearDown(c.dispose);
      await c.load();
      await c.beginAndSubmit(e.pending());
      await c.load();
      e.endFlushFails = true;
      await c.endRecord(
        expectedFingerprint: c.record!.fingerprint,
        explicitlyConfirmed: true,
      );
      expect(c.blocked, true);
      expect(e.sends, 1);
      await c.load();
      expect(c.blocked, false);
      expect(e.sends, 1);
    },
  );
  test(
    'retired account late reply cannot touch another scope or old slot',
    () async {
      final e = DriveEnv(), c = e.controller();
      addTearDown(c.dispose);
      await c.load();
      final entered = Completer<void>(), reply = Completer<void>();
      e.sendHook = () {
        entered.complete();
        return reply.future;
      };
      final action = c.beginAndSubmit(e.pending());
      await entered.future;
      final old = e.values[e.store.metadataKey], writes = e.writes;
      e.current = false;
      reply.complete();
      await action;
      expect(e.writes, writes);
      expect(e.values[e.store.metadataKey], old);
      final other = DriveEnv();
      expect(other.store.metadataKey, isNot(e.store.metadataKey));
    },
  );
  test('corrupt slot stays intact and blocks directory writes', () async {
    final e = DriveEnv(), c = e.controller();
    addTearDown(c.dispose);
    e.values[e.store.metadataKey] = '{broken';
    await c.load();
    await c.beginAndSubmit(e.pending());
    expect(c.blocked, true);
    expect(e.sends, 0);
    expect(e.values[e.store.metadataKey], '{broken');
  });
}
