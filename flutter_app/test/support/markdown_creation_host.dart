import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/complex_editor_transport.dart';

/// Owned protocol fake, not an actual browser or Android execution proof.
class MarkdownCreationHost {
  String source = '';
  int generation = 0, revision = 0, received = 0;
  bool readOnly = true;
  bool locked = true, failUnlock = false, failSnapshot = false;
  Completer<void>? snapshotStarted, snapshotGate;
  int activeSnapshots = 0, maxConcurrentSnapshots = 0;
  final Map<String, Uint8List> transfers = {};
  final BytesBuilder loadBuffer = BytesBuilder(copy: false);
  int endCount = 0;
  Future<Object?> call(String name, List<Object?> args) async {
    switch (name) {
      case 'beginLoad':
        loadBuffer.clear();
        received = 0;
        readOnly = (args[3] as Map)['readOnly'] as bool;
        return {
          'id': 'load',
          'bytes': args[1],
          'chunkBytes': ComplexEditorTransport.chunkBytes,
        };
      case 'appendLoad':
        final part = base64Decode(args[2] as String);
        loadBuffer.add(part);
        received += part.length;
        return {'id': args[0], 'index': args[1], 'received': received};
      case 'commitLoad':
        generation++;
        locked = readOnly;
        source = ComplexEditorDocument.fromBytes(
          ComplexEditorKind.markdown,
          loadBuffer.takeBytes(),
        ).source;
        return {...state(), 'readOnly': readOnly};
      case 'setInputLocked':
        final nextLocked = args[0] as bool;
        if (!nextLocked && failUnlock) throw StateError('unlock failed');
        locked = nextLocked;
        return state();
      case 'beginSnapshot':
        if (failSnapshot) throw StateError('Owned snapshot failure');
        activeSnapshots++;
        if (activeSnapshots > maxConcurrentSnapshots) {
          maxConcurrentSnapshots = activeSnapshots;
        }
        if (snapshotStarted != null && !snapshotStarted!.isCompleted) {
          snapshotStarted!.complete();
        }
        await snapshotGate?.future;
        final bytes = Uint8List.fromList(utf8.encode(source));
        transfers['s'] = bytes;
        return {
          'id': 's',
          'bytes': bytes.length,
          'chunks':
              (bytes.length + ComplexEditorTransport.chunkBytes - 1) ~/
              ComplexEditorTransport.chunkBytes,
          'generation': generation,
          'revision': revision,
          'sha256': sha256.convert(bytes).toString(),
        };
      case 'readSnapshot':
        final bytes = transfers[args[0] as String]!;
        final index = args[1] as int;
        final start = index * ComplexEditorTransport.chunkBytes;
        final end = (start + ComplexEditorTransport.chunkBytes).clamp(
          0,
          bytes.length,
        );
        return {
          'id': 's',
          'generation': generation,
          'index': index,
          'base64': base64Encode(bytes.sublist(start, end)),
        };
      case 'endSnapshot':
        transfers.remove(args[0]);
        activeSnapshots--;
        endCount++;
        return null;
      case 'retire':
        return null;
      default:
        throw StateError('unexpected command $name');
    }
  }

  Map<String, Object?> state() => {
    'version': 1,
    'kind': 'markdown',
    'generation': generation,
    'revision': revision,
    'ready': true,
    'dirty': revision > 0,
    'inputLocked': locked,
  };
}
