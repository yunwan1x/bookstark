import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/complex_editor_transport.dart';

void main() {
  group('ComplexEditorTransport protocol', () {
    test(
      'round-trips exact BOM and Unicode across multiple 256 KiB chunks',
      () async {
        final source =
            '\ufeff<!doctype html>\r\n<p>原文😀</p>\r\n${'漢🙂' * 50000}';
        final doc = _html(source);
        expect(doc.byteLength, greaterThan(256 * 1024));
        final host = _FakeEditorHost();
        final transport = ComplexEditorTransport(host.command);

        await transport.load(
          doc,
          readOnly: false,
          english: true,
          title: 'fixture',
        );
        expect(host.appendedChunks, hasLength(greaterThan(1)));
        expect(
          host.appendedChunks.first.length,
          ComplexEditorTransport.chunkBytes,
        );
        expect(host.loadedBytes, orderedEquals(utf8.encode(source)));
        expect(host.abortedLoads, isEmpty);
        final snapshot = await transport.capture();
        expect(snapshot.document.source, source);
        expect(snapshot.document.byteLength, doc.byteLength);
        expect(snapshot.document.digest, doc.digest);
        await transport.release(snapshot);
        expect(host.endedSnapshots, ['snapshot-1']);
      },
    );

    for (final corruption in <String>[
      'digest',
      'generation',
      'chunk index',
      'chunk size',
    ]) {
      test(
        'rejects $corruption corruption and releases the snapshot',
        () async {
          final host = _FakeEditorHost()..corruption = corruption;
          final transport = ComplexEditorTransport(host.command);
          await transport.load(_html('<!doctype html><p>safe</p>'));

          await expectLater(transport.capture(), throwsFormatException);
          expect(host.endedSnapshots, ['snapshot-1']);
          expect(host.acknowledgements, isEmpty);
        },
      );
    }

    test('input lock is bound to the current loaded generation', () async {
      final host = _FakeEditorHost();
      final transport = ComplexEditorTransport(host.command);
      await transport.load(_html('<p>first</p>'));
      await transport.load(_html('<p>replacement</p>'));

      await transport.setInputLocked(true);
      expect(host.lockRequests, [(true, 2)]);
      final call = host.calls.singleWhere(
        (entry) => entry.$1 == 'setInputLocked',
      );
      expect(call.$2, [true, 2]);
    });

    for (final corruption in ['lock generation', 'lock flag']) {
      test('rejects mismatched input-lock $corruption receipt', () async {
        final host = _FakeEditorHost()..corruption = corruption;
        final transport = ComplexEditorTransport(host.command);
        await transport.load(_html('<p>lock receipt</p>'));

        await expectLater(
          transport.setInputLocked(true),
          throwsFormatException,
        );
        expect(host.lockRequests, [(true, 1)]);
      });
    }

    test(
      'rejects a self-consistent snapshot from a different generation and releases it',
      () async {
        final host = _FakeEditorHost()..corruption = 'foreign generation';
        final transport = ComplexEditorTransport(host.command);
        await transport.load(_html('<p>active generation</p>'));

        await expectLater(transport.capture(), throwsFormatException);
        expect(host.endedSnapshots, ['snapshot-1']);
      },
    );

    test(
      'snapshot from a replaced load cannot be acknowledged remotely',
      () async {
        final host = _FakeEditorHost();
        final transport = ComplexEditorTransport(host.command);
        final oldDocument = _html('<p>old generation</p>');
        await transport.load(oldDocument);
        final oldSnapshot = await transport.capture();
        await transport.load(_html('<p>new generation</p>'));
        final acknowledgementsBefore = List<String>.from(host.acknowledgements);
        final ackCallsBefore = host.calls
            .where((entry) => entry.$1 == 'acknowledgeSnapshot')
            .length;

        await expectLater(
          transport.acknowledgeSaved(oldSnapshot, committed: oldDocument),
          throwsStateError,
        );
        expect(host.acknowledgements, acknowledgementsBefore);
        expect(
          host.calls.where((entry) => entry.$1 == 'acknowledgeSnapshot').length,
          ackCallsBefore,
        );
      },
    );

    test(
      'retirement invalidates a deferred command and removes the active document',
      () async {
        final entered = Completer<void>();
        final finishBegin = Completer<void>();
        final host = _FakeEditorHost()
          ..beginLoadEntered = entered
          ..finishBeginLoad = finishBegin;
        final transport = ComplexEditorTransport(host.command);
        final pendingLoad = transport.load(_html('<p>pending</p>'));
        await entered.future;

        await transport.retire();
        finishBegin.complete();
        await expectLater(pendingLoad, throwsStateError);
        expect(host.calls.map((call) => call.$1), ['beginLoad', 'retire']);
        await expectLater(transport.capture(), throwsStateError);
        expect(host.endedSnapshots, isEmpty);
      },
    );

    test(
      'a second operation cannot capture while a load transfer is busy',
      () async {
        final entered = Completer<void>();
        final finishBegin = Completer<void>();
        final host = _FakeEditorHost()
          ..beginLoadEntered = entered
          ..finishBeginLoad = finishBegin;
        final transport = ComplexEditorTransport(host.command);
        final pendingLoad = transport.load(_html('<p>busy</p>'));
        await entered.future;

        await expectLater(transport.capture(), throwsStateError);
        finishBegin.complete();
        await pendingLoad;
        final snapshot = await transport.capture();
        await transport.release(snapshot);
      },
    );

    for (final failure in <String>[
      'invalid begin receipt',
      'bad append receipt',
      'append command failure',
    ]) {
      test(
        'aborts $failure and retains the previously active document',
        () async {
          final host = _FakeEditorHost();
          final transport = ComplexEditorTransport(host.command);
          final original = _html('<!doctype html><p>active baseline</p>');
          await transport.load(original);
          host.loadFailure = failure;

          final replacement = _html('<!doctype html><p>replacement</p>');
          await expectLater(
            transport.load(replacement),
            failure == 'append command failure'
                ? throwsStateError
                : throwsFormatException,
          );
          expect(host.abortedLoads, ['load-2']);
          expect(host.calls.last.$1, 'abortLoad');
          expect(host.calls.last.$2, ['load-2']);

          final snapshot = await transport.capture();
          expect(snapshot.document.source, original.source);
          await transport.release(snapshot);
        },
      );
    }

    test(
      'acknowledgement requires this owner and exact committed snapshot, then works once',
      () async {
        final host = _FakeEditorHost();
        final otherHost = _FakeEditorHost();
        final transport = ComplexEditorTransport(host.command);
        final other = ComplexEditorTransport(otherHost.command);
        final original = _html('<!doctype html><p>saved source</p>');
        await transport.load(original);
        await other.load(original);
        final snapshot = await transport.capture();

        await expectLater(
          other.acknowledgeSaved(snapshot, committed: original),
          throwsStateError,
        );
        await expectLater(
          transport.acknowledgeSaved(
            snapshot,
            committed: _html('<p>different</p>'),
          ),
          throwsStateError,
        );
        expect(host.acknowledgements, isEmpty);

        await transport.acknowledgeSaved(snapshot, committed: original);
        expect(host.acknowledgements, ['snapshot-1']);
        await expectLater(
          transport.acknowledgeSaved(snapshot, committed: original),
          throwsStateError,
        );
        expect(host.acknowledgements, ['snapshot-1']);
        await other.retire();
        await transport.retire();
      },
    );

    test(
      'rejects malformed UTF-8 even when the advertised length and digest agree',
      () async {
        final invalidBytes = Uint8List.fromList([0xc3, 0x28]);
        final host = _FakeEditorHost()..snapshotBytesOverride = invalidBytes;
        final transport = ComplexEditorTransport(host.command);
        await transport.load(_html('<p>valid setup</p>'));

        await expectLater(transport.capture(), throwsFormatException);
        expect(host.endedSnapshots, ['snapshot-1']);
      },
    );
  });
}

ComplexEditorDocument _html(String source) =>
    ComplexEditorDocument.parse(ComplexEditorKind.html, source);

/// Models the native side of the message contract, independently of the Dart
/// transfer implementation. Corruptions are injected into returned receipts.
class _FakeEditorHost {
  final calls = <(String, List<Object?>)>[];
  final appendedChunks = <Uint8List>[];
  final endedSnapshots = <String>[];
  final acknowledgements = <String>[];
  final lockRequests = <(bool, int)>[];
  final abortedLoads = <String>[];
  BytesBuilder _loadBytes = BytesBuilder(copy: false);
  Uint8List loadedBytes = Uint8List(0);
  String loadedKind = 'html';
  bool loadedReadOnly = true;
  String? corruption;
  String? loadFailure;
  Uint8List? snapshotBytesOverride;
  Completer<void>? beginLoadEntered;
  Completer<void>? finishBeginLoad;
  int _snapshotNumber = 0;
  int _loadNumber = 0;
  int _loadedGeneration = 0;
  String _pendingLoadId = '';
  bool inputLocked = false;
  final _snapshotGenerations = <String, int>{};

  Future<Object?> command(String name, List<Object?> args) async {
    calls.add((name, List<Object?>.from(args)));
    switch (name) {
      case 'beginLoad':
        beginLoadEntered?.complete();
        await finishBeginLoad?.future;
        _loadNumber++;
        _pendingLoadId = 'load-$_loadNumber';
        _loadBytes = BytesBuilder(copy: false);
        appendedChunks.clear();
        loadedKind = args[0] as String;
        loadedReadOnly = (args[3] as Map)['readOnly'] as bool;
        return {
          'id': _pendingLoadId,
          'bytes': args[1],
          'chunkBytes': loadFailure == 'invalid begin receipt'
              ? ComplexEditorTransport.chunkBytes ~/ 2
              : ComplexEditorTransport.chunkBytes,
        };
      case 'appendLoad':
        if (loadFailure == 'append command failure') {
          throw StateError('injected append failure');
        }
        final index = args[1] as int;
        final chunk = Uint8List.fromList(base64Decode(args[2] as String));
        if (index != appendedChunks.length) {
          throw StateError('host got wrong index');
        }
        appendedChunks.add(chunk);
        _loadBytes.add(chunk);
        return {
          'id': args[0],
          'index': index,
          'received': loadFailure == 'bad append receipt'
              ? _loadBytes.length + 1
              : _loadBytes.length,
        };
      case 'commitLoad':
        loadedBytes = _loadBytes.takeBytes();
        _loadedGeneration++;
        inputLocked = loadedReadOnly;
        return {
          'ready': true,
          'kind': loadedKind,
          'readOnly': loadedReadOnly,
          'generation': _loadedGeneration,
        };
      case 'setInputLocked':
        final value = args[0] as bool;
        final generation = args[1] as int;
        lockRequests.add((value, generation));
        inputLocked = value;
        return {
          'generation': corruption == 'lock generation'
              ? _loadedGeneration + 1
              : _loadedGeneration,
          'ready': true,
          'kind': loadedKind,
          'inputLocked': corruption == 'lock flag' ? !value : value,
        };
      case 'beginSnapshot':
        _snapshotNumber++;
        final bytes = snapshotBytesOverride ?? loadedBytes;
        final id = 'snapshot-$_snapshotNumber';
        final generation = corruption == 'foreign generation'
            ? _loadedGeneration + 1
            : _loadedGeneration;
        _snapshotGenerations[id] = generation;
        return {
          'id': id,
          'bytes': bytes.length,
          'chunks':
              (bytes.length + ComplexEditorTransport.chunkBytes - 1) ~/
              ComplexEditorTransport.chunkBytes,
          'generation': generation,
          'revision': 0,
          'sha256': corruption == 'digest'
              ? '0' * 64
              : sha256.convert(bytes).toString(),
        };
      case 'readSnapshot':
        final bytes = snapshotBytesOverride ?? loadedBytes;
        final id = args[0] as String;
        final index = args[1] as int;
        final start = index * ComplexEditorTransport.chunkBytes;
        final end = (start + ComplexEditorTransport.chunkBytes).clamp(
          0,
          bytes.length,
        );
        var chunkBytes = bytes.sublist(start, end);
        var encoded = base64Encode(chunkBytes);
        var generation = _snapshotGenerations[id]!;
        var responseIndex = index;
        if (corruption == 'generation') generation++;
        if (corruption == 'chunk index') responseIndex = index + 1;
        if (corruption == 'chunk size' && chunkBytes.isNotEmpty) {
          chunkBytes = chunkBytes.sublist(0, chunkBytes.length - 1);
          encoded = base64Encode(chunkBytes);
        }
        return {
          'id': id,
          'generation': generation,
          'index': responseIndex,
          'base64': encoded,
        };
      case 'endSnapshot':
        endedSnapshots.add(args[0] as String);
        _snapshotGenerations.remove(args[0] as String);
        return null;
      case 'abortLoad':
        abortedLoads.add(args[0] as String);
        if (args[0] == _pendingLoadId) {
          _loadBytes = BytesBuilder(copy: false);
          appendedChunks.clear();
        }
        return null;
      case 'acknowledgeSnapshot':
        final id = args[0] as String;
        acknowledgements.add(id);
        return {
          'generation': _snapshotGenerations[id],
          'ready': true,
          'kind': loadedKind,
        };
      case 'retire':
        return null;
      default:
        throw StateError('unexpected protocol command: $name');
    }
  }
}
