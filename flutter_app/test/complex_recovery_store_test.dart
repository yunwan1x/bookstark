import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/complex_recovery_store.dart';

const key = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

void main() {
  group('NativeComplexRecoveryStore protocol', () {
    test(
      'round-trips exact binary bytes across multiple 256 KiB chunks',
      () async {
        final bytes = Uint8List(600123);
        for (var i = 0; i < bytes.length; i++) {
          bytes[i] = (i * 73) & 0xff;
        }
        bytes.setRange(0, 13, [
          0,
          0,
          0,
          0xf0,
          0x9f,
          0x99,
          0x82,
          0,
          0xe6,
          0xbc,
          0xa2,
          0,
          255,
        ]);
        final native = _Native()..records[key] = Uint8List.fromList([8, 9]);
        final store = NativeComplexRecoveryStore(invoke: native.invoke);

        await store.write(key, bytes);
        expect(native.writeChunkCount, 3);
        expect(native.records[key], orderedEquals(bytes));
        expect(await store.read(key), orderedEquals(bytes));
        expect(native.calls.where((call) => call == 'endRead'), hasLength(1));
        expect(native.calls.where((call) => call == 'abortWrite'), isEmpty);
      },
    );

    for (final failure in <String>[
      'begin size',
      'chunk receipt',
      'chunk command',
      'commit id',
      'commit size',
      'commit digest',
      'commit flag',
    ]) {
      test('aborts bad $failure and keeps prior fixture visible', () async {
        final previous = Uint8List.fromList(
          utf8.encode('previous committed fixture'),
        );
        final native = _Native()
          ..records[key] = Uint8List.fromList(previous)
          ..writeFailure = failure;
        final store = NativeComplexRecoveryStore(invoke: native.invoke);

        await expectLater(
          store.write(key, Uint8List.fromList(utf8.encode('replacement'))),
          failure == 'chunk command' ? throwsStateError : throwsFormatException,
        );
        expect(native.aborted, ['write-1']);
        expect(await store.read(key), orderedEquals(previous));
      });
    }

    for (final corruption in <String>[
      'length',
      'count',
      'index',
      'type',
      'digest',
    ]) {
      test(
        'rejects $corruption read corruption and releases native reader',
        () async {
          final native = _Native()
            ..records[key] = Uint8List.fromList(utf8.encode('read fixture'))
            ..readCorruption = corruption;
          final store = NativeComplexRecoveryStore(invoke: native.invoke);

          await expectLater(store.read(key), throwsFormatException);
          expect(native.ended, ['read-1']);
        },
      );
    }

    test('invalid keys are rejected before native IO', () async {
      final native = _Native();
      final store = NativeComplexRecoveryStore(invoke: native.invoke);

      expect(() => store.read('bad'), throwsFormatException);
      expect(
        () => store.write('g' * 64, Uint8List.fromList([1])),
        throwsFormatException,
      );
      expect(() => store.remove(''), throwsFormatException);
      expect(native.calls, isEmpty);
    });

    test('input is frozen before the asynchronous write begins', () async {
      final entered = Completer<void>();
      final resume = Completer<void>();
      final input = Uint8List.fromList([0, 1, 0, 255, 3]);
      final native = _Native()
        ..beginWriteEntered = entered
        ..finishBeginWrite = resume;
      final store = NativeComplexRecoveryStore(invoke: native.invoke);
      final pending = store.write(key, input);
      await entered.future;
      input.fillRange(0, input.length, 7);
      resume.complete();

      await pending;
      expect(native.records[key], [0, 1, 0, 255, 3]);
    });

    test(
      'concurrent operations stay ordered and a failed first write does not poison queue',
      () async {
        final entered = Completer<void>();
        final resume = Completer<void>();
        final native = _Native()
          ..writeFailure = 'first begin'
          ..beginWriteEntered = entered
          ..finishBeginWrite = resume;
        final store = NativeComplexRecoveryStore(invoke: native.invoke);
        final first = store.write(key, Uint8List.fromList([1]));
        await entered.future;
        native.writeFailure = null;
        final second = store.write(key, Uint8List.fromList([2, 3]));
        resume.complete();

        await expectLater(first, throwsStateError);
        await second;
        expect(native.calls.take(4), [
          'beginWrite',
          'beginWrite',
          'writeChunk',
          'commitWrite',
        ]);
        expect(native.records[key], [2, 3]);
      },
    );

    test('a false removal receipt is an error', () async {
      final native = _Native()..removeResult = false;
      final store = NativeComplexRecoveryStore(invoke: native.invoke);

      await expectLater(store.remove(key), throwsStateError);
      expect(native.records, isEmpty);
    });
  });
}

/// Protocol mock only. It does not test Android encryption, key storage, or
/// process-restart durability.
class _Native {
  final calls = <String>[];
  final records = <String, Uint8List>{};
  final aborted = <String>[];
  final ended = <String>[];
  final staging = <String, _Staged>{};
  String? writeFailure;
  String? readCorruption;
  bool removeResult = true;
  Completer<void>? beginWriteEntered;
  Completer<void>? finishBeginWrite;
  int sequence = 0;
  int writeChunkCount = 0;
  String? readKey;

  Future<Object?> invoke(String method, Map<String, Object?> args) async {
    calls.add(method);
    switch (method) {
      case 'beginWrite':
        if (writeFailure == 'first begin' && sequence == 0) {
          sequence++;
          if (beginWriteEntered != null && !beginWriteEntered!.isCompleted) {
            beginWriteEntered!.complete();
          }
          await finishBeginWrite?.future;
          throw StateError('injected begin failure');
        }
        sequence++;
        final id = 'write-$sequence';
        if (beginWriteEntered != null && !beginWriteEntered!.isCompleted) {
          beginWriteEntered!.complete();
        }
        await finishBeginWrite?.future;
        staging[id] = _Staged(args['key']! as String);
        return {
          'id': id,
          'bytes': writeFailure == 'begin size'
              ? (args['bytes']! as int) + 1
              : args['bytes'],
          'chunkBytes': NativeComplexRecoveryStore.chunkBytes,
        };
      case 'writeChunk':
        if (writeFailure == 'chunk command') {
          throw StateError('injected chunk failure');
        }
        final id = args['id']! as String;
        final state = staging[id]!;
        state.bytes.addAll(args['data']! as Uint8List);
        writeChunkCount++;
        return {
          'id': id,
          'index': writeFailure == 'chunk receipt'
              ? (args['index']! as int) + 1
              : args['index'],
          'received': state.bytes.length,
        };
      case 'commitWrite':
        final id = args['id']! as String;
        final state = staging[id]!;
        if (writeFailure == null) {
          records[state.key] = Uint8List.fromList(state.bytes);
        }
        return {
          'id': writeFailure == 'commit id' ? 'wrong' : id,
          'bytes': writeFailure == 'commit size'
              ? state.bytes.length + 1
              : state.bytes.length,
          'sha256': writeFailure == 'commit digest'
              ? 'f' * 64
              : sha256.convert(state.bytes).toString(),
          'committed': writeFailure == 'commit flag' ? false : true,
        };
      case 'abortWrite':
        final id = args['id']! as String;
        aborted.add(id);
        staging.remove(id);
        return true;
      case 'beginRead':
        readKey = args['key']! as String;
        final bytes = records[readKey];
        if (bytes == null) return null;
        final count =
            (bytes.length + NativeComplexRecoveryStore.chunkBytes - 1) ~/
            NativeComplexRecoveryStore.chunkBytes;
        return {
          'id': 'read-1',
          'bytes': readCorruption == 'length' ? bytes.length + 1 : bytes.length,
          'chunks': readCorruption == 'count' ? count + 1 : count,
          'sha256': readCorruption == 'digest'
              ? 'f' * 64
              : sha256.convert(bytes).toString(),
        };
      case 'readChunk':
        final bytes = records[readKey]!;
        final index = args['index']! as int;
        final start = index * NativeComplexRecoveryStore.chunkBytes;
        final end = (start + NativeComplexRecoveryStore.chunkBytes).clamp(
          0,
          bytes.length,
        );
        final chunk = Uint8List.sublistView(bytes, start, end);
        return {
          'id': args['id'],
          'index': readCorruption == 'index' ? index + 1 : index,
          'data': readCorruption == 'type' ? chunk.toList() : chunk,
        };
      case 'endRead':
        ended.add(args['id']! as String);
        return true;
      case 'remove':
        if (removeResult) records.remove(args['key']! as String);
        return removeResult;
      default:
        throw StateError('Unexpected native method: $method');
    }
  }
}

class _Staged {
  _Staged(this.key);
  final String key;
  final bytes = <int>[];
}
