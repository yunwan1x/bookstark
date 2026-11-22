import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/local_generation_state.dart';
import 'package:bookstark_flutter/core/native_local_data_control.dart';

LocalRestoreIntent makeIntent() => LocalRestoreIntent(
  operationId: 'b' * 32,
  sourcePointerRaw: null,
  retainedId: 'c' * 32,
  retainedManifestSHA256: 'd' * 64,
  targetPointerRaw: LocalGenerationPointer(
    generation: 'a' * 32,
    epoch: 1,
    activationId: 'b' * 32,
    sourceSHA256: 'e' * 64,
  ).encode(),
);

/// Simulated IPC replies only: these tests do not claim Android fsync proof.
class _Native {
  String? pointerRaw, intentRaw, retentionRaw;
  bool loseCommitReply = false, wrongReceipt = false;
  final calls = <String>[];
  Map<String, Object?> state() {
    final pending = intentRaw == null
        ? null
        : LocalRestoreIntent.parse(intentRaw!);
    final retention = retentionRaw == null
        ? null
        : LocalRetention.parse(retentionRaw!);
    return {
      'format': 1,
      'pointerRaw': pointerRaw,
      'intentRaw': intentRaw,
      'currentRetentionRaw':
          retention?.sourcePointerSHA256 == localPointerSHA256(pointerRaw)
          ? retentionRaw
          : null,
      'sourceRetentionRaw': pending == null ? null : retentionRaw,
      'metadataOnly': true,
    };
  }

  Map<String, Object?> receipt(String action, String id) => {
    'format': 1,
    'action': action,
    'id': wrongReceipt ? 'f' * 32 : id,
    'durable': true,
    'state': state(),
  };
  Future<Object?> invoke(String method, Map<String, Object?>? args) async {
    calls.add(method);
    if (method == 'readState') return state();
    if (method == 'space') return {'format': 1, 'availableBytes': 123456789};
    if (method == 'prepareRestore') {
      final intent = LocalRestoreIntent.parse(args!['intentRaw'] as String);
      if (intentRaw != null || pointerRaw != intent.sourcePointerRaw) {
        throw StateError('CAS');
      }
      retentionRaw = LocalRetention(
        id: intent.retainedId,
        sourcePointerSHA256: intent.sourcePointerSHA256,
        sourceGeneration: 'legacy',
        manifestSHA256: intent.retainedManifestSHA256,
      ).encode();
      intentRaw = intent.encode();
      return receipt('prepared', intent.operationId);
    }
    if (method == 'reenterUnchangedSource') {
      final lock = LocalRetention.parse(retentionRaw!);
      if (intentRaw != null ||
          args!['retainedId'] != lock.id ||
          args['sourcePointerSHA256'] != localPointerSHA256(pointerRaw)) {
        throw StateError('Changed source');
      }
      retentionRaw = null;
      return receipt('reentered', lock.id);
    }
    final intent = LocalRestoreIntent.parse(intentRaw!);
    if (args!['operationId'] != intent.operationId ||
        args['intentSHA256'] != localPointerSHA256(intent.encode())) {
      throw StateError('Wrong intent binding');
    }
    if (method == 'commitRestore') {
      if (pointerRaw != intent.sourcePointerRaw) throw StateError('CAS');
      pointerRaw = intent.targetPointerRaw;
      if (loseCommitReply) throw StateError('Applied but IPC reply lost');
      return receipt('switched', intent.operationId);
    }
    if (method == 'acknowledgeApplied') {
      if (pointerRaw != intent.targetPointerRaw) {
        throw StateError('Not applied');
      }
      intentRaw = null;
      return receipt('acknowledged', intent.operationId);
    }
    if (method == 'finishUnapplied') {
      if (pointerRaw != intent.sourcePointerRaw) throw StateError('Applied');
      intentRaw = null;
      return receipt('finished-unapplied', intent.operationId);
    }
    throw StateError('Unexpected method');
  }
}

void main() {
  test(
    'retained catalog preserves unknown/overflow without arbitrary paths',
    () async {
      final retained = LocalRetention(
        id: 'a' * 32,
        sourcePointerSHA256: localPointerSHA256(null),
        sourceGeneration: 'legacy',
        manifestSHA256: 'b' * 64,
      );
      final control = NativeLocalDataControl(
        invoke: (method, arguments) async {
          expect(method, 'listRetained');
          expect(arguments, isNull);
          return {
            'format': 1,
            'retentions': [retained.encode()],
            'unknown': 2,
            'overflow': true,
            'metadataOnly': true,
          };
        },
      );
      final catalog = await control.listRetained();
      expect(catalog.entries.single.id, retained.id);
      expect(catalog.unknown, 2);
      expect(catalog.overflow, isTrue);
    },
  );
  test('duplicate retained IDs fail closed', () async {
    final retained = LocalRetention(
      id: 'a' * 32,
      sourcePointerSHA256: localPointerSHA256(null),
      sourceGeneration: 'legacy',
      manifestSHA256: 'b' * 64,
    );
    final control = NativeLocalDataControl(
      invoke: (_, _) async => {
        'format': 1,
        'retentions': [retained.encode(), retained.encode()],
        'unknown': 0,
        'overflow': false,
        'metadataOnly': true,
      },
    );
    await expectLater(control.listRetained(), throwsFormatException);
  });
  test(
    'applied file review must bind operation/pointer/intent before parsing content',
    () async {
      final control = NativeLocalDataControl(
        invoke: (_, _) async => {
          'format': 1,
          'operationId': 'f' * 32,
          'pointerSHA256': 'a' * 64,
          'intentSHA256': 'b' * 64,
          'manifestRaw': '{}',
          'metadataOnly': true,
        },
      );
      await expectLater(
        control.reviewApplied(makeIntent()),
        throwsFormatException,
      );
    },
  );

  test(
    'explicit prepare, commit and acknowledgement bind durable receipts',
    () async {
      final native = _Native();
      final control = NativeLocalDataControl(invoke: native.invoke);
      final intent = makeIntent();
      expect((await control.readState()).observation.needsReview, isFalse);
      expect(await control.availableBytes(), 123456789);
      expect((await control.prepare(intent)).action, 'prepared');
      expect((await control.commit(intent)).action, 'switched');
      expect((await control.readState()).observation.needsReview, isTrue);
      final receipt = await control.acknowledgeApplied(intent);
      expect(receipt.state.observation.phase, LocalGenerationPhase.ready);
      expect(receipt.state.pointerRaw, intent.targetPointerRaw);
      expect(native.calls.where((m) => m == 'commitRestore'), hasLength(1));
    },
  );

  test(
    'lost applied commit reply does not retry, read, acknowledge or clean up',
    () async {
      final native = _Native()..loseCommitReply = true;
      final control = NativeLocalDataControl(invoke: native.invoke);
      final intent = makeIntent();
      await control.prepare(intent);
      await expectLater(
        control.commit(intent),
        throwsA(isA<LocalControlUnconfirmed>()),
      );
      expect(native.calls, ['prepareRestore', 'commitRestore']);
      expect(native.intentRaw, intent.encode());
      final observed = await control.readState();
      expect(observed.observation.phase, LocalGenerationPhase.switched);
      expect(observed, isNot(isA<LocalControlReceipt>()));
      expect(native.calls, ['prepareRestore', 'commitRestore', 'readState']);
    },
  );

  test(
    'an unbound reply remains unknown even after the native side applied',
    () async {
      final native = _Native();
      final control = NativeLocalDataControl(invoke: native.invoke);
      final intent = makeIntent();
      await control.prepare(intent);
      native.wrongReceipt = true;
      await expectLater(
        control.commit(intent),
        throwsA(isA<LocalControlUnconfirmed>()),
      );
      expect(native.pointerRaw, intent.targetPointerRaw);
      expect(native.intentRaw, isNotNull);
      expect(native.calls, ['prepareRestore', 'commitRestore']);
    },
  );

  test(
    'finishing unapplied intent keeps retained data until explicit reentry',
    () async {
      final native = _Native();
      final control = NativeLocalDataControl(invoke: native.invoke);
      final intent = makeIntent();
      await control.prepare(intent);
      final finished = await control.finishUnapplied(intent);
      expect(finished.state.observation.phase, LocalGenerationPhase.retained);
      expect(native.retentionRaw, isNotNull);
      final reentered = await control.reenterUnchangedSource(finished.state);
      expect(reentered.state.observation.needsReview, isFalse);
      expect(reentered.state.pointerRaw, isNull);
      expect(native.calls, [
        'prepareRestore',
        'finishUnapplied',
        'reenterUnchangedSource',
      ]);
    },
  );

  test('changed pointer cannot be treated as an unapplied operation', () async {
    final native = _Native();
    final control = NativeLocalDataControl(invoke: native.invoke);
    final intent = makeIntent();
    await control.prepare(intent);
    await control.commit(intent);
    await expectLater(
      control.finishUnapplied(intent),
      throwsA(isA<LocalControlUnconfirmed>()),
    );
    expect(native.pointerRaw, intent.targetPointerRaw);
    expect(native.intentRaw, isNotNull);
    expect(native.calls.where((m) => m == 'commitRestore'), hasLength(1));
  });

  test(
    'reentry requires a retained observation before any native call',
    () async {
      final native = _Native();
      final control = NativeLocalDataControl(invoke: native.invoke);
      final ready = await control.readState();
      expect(() => control.reenterUnchangedSource(ready), throwsStateError);
      expect(native.calls, ['readState']);
    },
  );

  test(
    'timeout preserves uncertainty and cannot trigger an automatic replay',
    () async {
      final native = _Native();
      final pending = Completer<Object?>();
      final control = NativeLocalDataControl(
        timeout: const Duration(milliseconds: 5),
        invoke: (method, args) {
          if (method == 'commitRestore') {
            native.calls.add(method);
            return pending.future;
          }
          return native.invoke(method, args);
        },
      );
      final intent = makeIntent();
      await control.prepare(intent);
      await expectLater(
        control.commit(intent),
        throwsA(isA<LocalControlUnconfirmed>()),
      );
      expect(native.calls, ['prepareRestore', 'commitRestore']);
      native.pointerRaw = intent.targetPointerRaw;
      pending.complete(native.receipt('switched', intent.operationId));
      final observed = await control.readState();
      expect(observed.observation.canAcknowledgeApplied, isTrue);
      expect(native.calls, ['prepareRestore', 'commitRestore', 'readState']);
    },
  );

  test(
    'unsupported metadata and nondurable mutation replies never pass',
    () async {
      final native = _Native();
      final control = NativeLocalDataControl(
        invoke: (method, args) async {
          if (method == 'readState') {
            return {...native.state(), 'metadataOnly': false};
          }
          return {
            'format': 1,
            'action': 'prepared',
            'id': 'b' * 32,
            'durable': false,
            'state': native.state(),
          };
        },
      );
      await expectLater(control.readState(), throwsFormatException);
      await expectLater(
        control.prepare(makeIntent()),
        throwsA(isA<LocalControlUnconfirmed>()),
      );
    },
  );
  test(
    'candidate discard is bound to its exact unreferenced identity',
    () async {
      final native = _Native();
      Map<String, Object?>? sent;
      final control = NativeLocalDataControl(
        invoke: (method, args) async {
          expect(method, 'discardCandidate');
          sent = args;
          return native.receipt('discarded', args!['generation'] as String);
        },
      );
      expect((await control.discardCandidate('d' * 32)).action, 'discarded');
      expect(sent, {'generation': 'd' * 32});
      expect(
        () => control.discardCandidate('../outside'),
        throwsFormatException,
      );
    },
  );
}
