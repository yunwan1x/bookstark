import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/complex_editor_transport.dart';
import 'package:bookstark_flutter/core/html_notes_repository.dart';

import 'package:bookstark_flutter/features/html/html_creation_source_coordinator.dart';

class _Host {
  String source = '';
  int generation = 0, revision = 0, received = 0;
  bool readOnly = true;
  bool locked = true, failUnlock = false;
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
        source = utf8.decode(loadBuffer.takeBytes());
        return {..._state(), 'readOnly': readOnly};
      case 'setInputLocked':
        final nextLocked = args[0] as bool;
        if (!nextLocked && failUnlock) throw StateError('unlock failed');
        locked = nextLocked;
        return _state();
      case 'beginSnapshot':
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

  Map<String, Object?> _state() => {
    'version': 1,
    'kind': 'html',
    'generation': generation,
    'revision': revision,
    'ready': true,
    'dirty': revision > 0,
    'inputLocked': locked,
  };
}

void main() {
  test(
    'captured BOM/CRLF/Unicode source is frozen with metadata then flushed before create',
    () async {
      const source = '\ufeff<!doctype html>\r\n<h1>雪 café</h1>\r\n';
      final host = _Host();
      final transport = ComplexEditorTransport(host.call);
      await transport.load(
        ComplexEditorDocument.parse(ComplexEditorKind.html, source),
        readOnly: false,
      );
      String title = 'title at capture';
      List<String> labels = ['标签'];
      HtmlNoteEdit? frozen;
      var flushed = false, creates = 0;
      final c = HtmlCreationSourceCoordinator(
        freezeEdit: (body) => HtmlNoteEdit(
          title: title,
          source: body,
          labels: List<String>.of(labels),
        ),
        applyCapturedEdit: (value) => frozen = value,
        flushCreationJournal: () async {
          flushed = true;
          return true;
        },
        create: () async {
          expect(flushed, isTrue);
          creates++;
        },
        creationStillEditable: () => true,
        pendingOrUnknown: () => false,
      );
      c.beginGeneration(source);
      await c.bind(transport, generation: transport.generation!);
      host.source = source;
      title = 'latest title';
      labels = ['x', 'y'];
      expect(await c.submit(), isTrue);
      expect(frozen!.source, source);
      expect(frozen!.title, 'latest title');
      expect(frozen!.labels, ['x', 'y']);
      expect(creates, 1);
      expect(host.endCount, 1);
      await transport.retire();
      c.dispose();
    },
  );

  test(
    'journal failure never invokes create and ordinary leave can retry',
    () async {
      const source = '<p>draft</p>';
      final host = _Host();
      final transport = ComplexEditorTransport(host.call);
      await transport.load(
        ComplexEditorDocument.parse(ComplexEditorKind.html, source),
        readOnly: false,
      );
      var allow = false, creates = 0, flushes = 0;
      final c = HtmlCreationSourceCoordinator(
        freezeEdit: (body) =>
            HtmlNoteEdit(title: 'draft', source: body, labels: const []),
        applyCapturedEdit: (_) {},
        flushCreationJournal: () async {
          flushes++;
          return allow;
        },
        create: () async {
          creates++;
        },
        creationStillEditable: () => true,
        pendingOrUnknown: () => false,
      );
      c.beginGeneration(source);
      await c.bind(transport, generation: transport.generation!);
      expect(await c.submit(), isFalse);
      expect(creates, 0);
      allow = true;
      expect(await c.prepareLeave(), isTrue);
      expect(flushes, 2);
      await transport.retire();
      c.dispose();
    },
  );

  test(
    'another transport cannot replace the generation and stale ready cannot rebind after retire',
    () async {
      const source = '<p>identity</p>';
      final first = ComplexEditorTransport(_Host().call);
      final second = ComplexEditorTransport(_Host().call);
      final document = ComplexEditorDocument.parse(
        ComplexEditorKind.html,
        source,
      );
      await first.load(document, readOnly: false);
      await second.load(document, readOnly: false);
      final c = HtmlCreationSourceCoordinator(
        freezeEdit: (body) =>
            HtmlNoteEdit(title: 'draft', source: body, labels: const []),
        applyCapturedEdit: (_) {},
        flushCreationJournal: () async => true,
        create: () async {},
        creationStillEditable: () => true,
        pendingOrUnknown: () => false,
      );
      c.beginGeneration(source);
      await c.bind(first, generation: first.generation!);
      await expectLater(
        c.bind(second, generation: second.generation!),
        throwsStateError,
      );
      await c.beforeForcedRetire(first);
      await expectLater(
        c.bind(second, generation: second.generation!),
        throwsStateError,
      );
      await first.retire();
      await second.retire();
      await c.dispose();
    },
  );

  test(
    'pending or unknown creation cannot resubmit even if a candidate exists',
    () async {
      const source = '<p>review</p>';
      final host = _Host();
      final transport = ComplexEditorTransport(host.call);
      await transport.load(
        ComplexEditorDocument.parse(ComplexEditorKind.html, source),
        readOnly: false,
      );
      var creates = 0;
      final c = HtmlCreationSourceCoordinator(
        freezeEdit: (body) =>
            HtmlNoteEdit(title: 'draft', source: body, labels: const []),
        applyCapturedEdit: (_) {},
        flushCreationJournal: () async => true,
        create: () async {
          creates++;
        },
        creationStillEditable: () => false,
        pendingOrUnknown: () => true,
      );
      c.beginGeneration(source);
      await c.bind(transport, generation: transport.generation!);
      expect(await c.submit(), isFalse);
      expect(creates, 0);
      expect(await c.prepareLeave(), isFalse);
      await transport.retire();
      c.dispose();
    },
  );

  test(
    'unlock receipt failure makes checkpoint fail instead of returning early success',
    () async {
      const source = '<p>checkpoint</p>';
      final host = _Host();
      final transport = ComplexEditorTransport(host.call);
      await transport.load(
        ComplexEditorDocument.parse(ComplexEditorKind.html, source),
        readOnly: false,
      );
      final c = HtmlCreationSourceCoordinator(
        freezeEdit: (body) =>
            HtmlNoteEdit(title: 'title', source: body, labels: const []),
        applyCapturedEdit: (_) {},
        flushCreationJournal: () async => true,
        create: () async {},
        creationStillEditable: () => true,
        pendingOrUnknown: () => false,
      );
      c.beginGeneration(source);
      await c.bind(transport, generation: transport.generation!);
      host.failUnlock = true;
      expect(await c.checkpoint(), isFalse);
      expect(c.failure, isA<StateError>());
      await transport.retire();
      await c.dispose();
    },
  );

  test('rejected create unlocks editable source for correction', () async {
    const source = '<p>invalid metadata</p>';
    final host = _Host();
    final transport = ComplexEditorTransport(host.call);
    await transport.load(
      ComplexEditorDocument.parse(ComplexEditorKind.html, source),
      readOnly: false,
    );
    final c = HtmlCreationSourceCoordinator(
      freezeEdit: (body) =>
          HtmlNoteEdit(title: 'title', source: body, labels: const []),
      applyCapturedEdit: (_) {},
      flushCreationJournal: () async => true,
      create: () async => throw const FormatException('validation rejected'),
      creationStillEditable: () => true,
      pendingOrUnknown: () => false,
    );
    c.beginGeneration(source);
    await c.bind(transport, generation: transport.generation!);
    expect(await c.submit(), isFalse);
    expect(host.locked, isFalse);
    expect(c.failure, isA<FormatException>());
    await transport.retire();
    await c.dispose();
  });

  test(
    'forced retirement captures latest source and starts journal without awaiting storage',
    () async {
      const source = '<p>seed</p>';
      const latest = '<p>last keystroke</p>\r\n';
      final host = _Host();
      final transport = ComplexEditorTransport(host.call);
      await transport.load(
        ComplexEditorDocument.parse(ComplexEditorKind.html, source),
        readOnly: false,
      );
      final started = Completer<void>();
      final delayedWrite = Completer<bool>();
      HtmlNoteEdit? captured;
      final c = HtmlCreationSourceCoordinator(
        freezeEdit: (body) => HtmlNoteEdit(
          title: 'latest title',
          source: body,
          labels: const ['latest'],
        ),
        applyCapturedEdit: (value) => captured = value,
        flushCreationJournal: () {
          started.complete();
          return delayedWrite.future;
        },
        create: () async {},
        creationStillEditable: () => true,
        pendingOrUnknown: () => false,
      );
      c.beginGeneration(source);
      await c.bind(transport, generation: transport.generation!);
      host.source = latest;
      final epoch = c.epoch;
      await c.beforeForcedRetire(transport);
      expect(captured!.source, latest);
      expect(captured!.title, 'latest title');
      expect(captured!.labels, ['latest']);
      expect(started.isCompleted, isTrue);
      expect(delayedWrite.isCompleted, isFalse);
      expect(c.isCurrentEpoch(epoch), isFalse);
      await transport.retire();
      delayedWrite.complete(true);
      await Future<void>.delayed(Duration.zero);
      await c.dispose();
    },
  );
  test(
    'a new generation after preview retirement becomes ready and editable',
    () async {
      final firstHost = _Host();
      final firstTransport = ComplexEditorTransport(firstHost.call);
      await firstTransport.load(
        ComplexEditorDocument.parse(ComplexEditorKind.html, 'first'),
        readOnly: false,
      );
      final c = HtmlCreationSourceCoordinator(
        freezeEdit: (body) =>
            HtmlNoteEdit(title: 'title', source: body, labels: const []),
        applyCapturedEdit: (_) {},
        flushCreationJournal: () async => true,
        create: () async {},
        creationStillEditable: () => true,
        pendingOrUnknown: () => false,
      );
      c.beginGeneration('first');
      await c.bind(firstTransport, generation: firstTransport.generation!);
      expect(c.ready, isTrue);
      await c.beforeForcedRetire(firstTransport);
      expect(c.ready, isFalse);
      await firstTransport.retire();

      final secondHost = _Host();
      final secondTransport = ComplexEditorTransport(secondHost.call);
      await secondTransport.load(
        ComplexEditorDocument.parse(ComplexEditorKind.html, 'second'),
        readOnly: false,
      );
      c.beginGeneration('second');
      await c.bind(secondTransport, generation: secondTransport.generation!);
      expect(c.ready, isTrue);
      expect(await c.checkpoint(), isTrue);
      expect(c.failure, isNull);
      await secondTransport.retire();
      await c.dispose();
    },
  );

  test(
    'forced close queues behind capture and never overlaps snapshots',
    () async {
      const seed = '<p>seed</p>';
      const latest = '<p>last keystroke</p>\r\n';
      final host = _Host()
        ..snapshotStarted = Completer<void>()
        ..snapshotGate = Completer<void>();
      final transport = ComplexEditorTransport(host.call);
      await transport.load(
        ComplexEditorDocument.parse(ComplexEditorKind.html, seed),
        readOnly: false,
      );
      HtmlNoteEdit? captured;
      final c = HtmlCreationSourceCoordinator(
        freezeEdit: (body) => HtmlNoteEdit(
          title: 'title at retirement',
          source: body,
          labels: const ['label at retirement'],
        ),
        applyCapturedEdit: (value) => captured = value,
        flushCreationJournal: () async => true,
        create: () async {},
        creationStillEditable: () => true,
        pendingOrUnknown: () => false,
      );
      c.beginGeneration(seed);
      await c.bind(transport, generation: transport.generation!);
      final checkpoint = c.checkpoint();
      await host.snapshotStarted!.future;
      host.source = latest;
      final retirement = c.beforeForcedRetire(transport);
      expect(c.busy, isTrue);
      expect(host.maxConcurrentSnapshots, 1);
      host.snapshotGate!.complete();
      expect(await checkpoint, isFalse);
      await retirement;
      expect(host.maxConcurrentSnapshots, 1);
      expect(captured!.source, latest);
      expect(captured!.title, 'title at retirement');
      expect(captured!.labels, ['label at retirement']);
      expect(c.ready, isFalse);
      await transport.retire();
      await c.dispose();
    },
  );
}
