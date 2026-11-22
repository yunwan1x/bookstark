import 'dart:async';
import 'support/markdown_creation_host.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/complex_editor_transport.dart';
import 'package:bookstark_flutter/core/local_complex_notes_repository.dart';

import 'package:bookstark_flutter/features/complex_editors/local_article_creation_source_coordinator.dart';

void main() {
  test(
    'captured BOM/CRLF/Unicode source is frozen with metadata then flushed before create',
    () async {
      const source = '\ufeff<!doctype html>\r\n<h1>雪 café</h1>\r\n';
      final host = MarkdownCreationHost();
      final transport = ComplexEditorTransport(host.call);
      await transport.load(
        ComplexEditorDocument.parse(ComplexEditorKind.markdown, source),
        readOnly: false,
      );
      String title = 'title at capture';
      List<String> labels = ['标签'];
      ComplexNoteEdit? frozen;
      var flushed = false, creates = 0;
      final c = LocalArticleCreationSourceCoordinator(
        freezeEdit: (body) => ComplexNoteEdit(
          title: title,
          document: ComplexEditorDocument.parse(
            ComplexEditorKind.markdown,
            body,
          ),
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
      expect(frozen!.document.source, source);
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
      const source = '# draft';
      final host = MarkdownCreationHost();
      final transport = ComplexEditorTransport(host.call);
      await transport.load(
        ComplexEditorDocument.parse(ComplexEditorKind.markdown, source),
        readOnly: false,
      );
      var allow = false, creates = 0, flushes = 0;
      final c = LocalArticleCreationSourceCoordinator(
        freezeEdit: (body) => ComplexNoteEdit(
          title: 'draft',
          document: ComplexEditorDocument.parse(
            ComplexEditorKind.markdown,
            body,
          ),
          labels: const [],
        ),
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
      const source = '# identity';
      final first = ComplexEditorTransport(MarkdownCreationHost().call);
      final second = ComplexEditorTransport(MarkdownCreationHost().call);
      final document = ComplexEditorDocument.parse(
        ComplexEditorKind.markdown,
        source,
      );
      await first.load(document, readOnly: false);
      await second.load(document, readOnly: false);
      final c = LocalArticleCreationSourceCoordinator(
        freezeEdit: (body) => ComplexNoteEdit(
          title: 'draft',
          document: ComplexEditorDocument.parse(
            ComplexEditorKind.markdown,
            body,
          ),
          labels: const [],
        ),
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
      const source = '# review';
      final host = MarkdownCreationHost();
      final transport = ComplexEditorTransport(host.call);
      await transport.load(
        ComplexEditorDocument.parse(ComplexEditorKind.markdown, source),
        readOnly: false,
      );
      var creates = 0;
      final c = LocalArticleCreationSourceCoordinator(
        freezeEdit: (body) => ComplexNoteEdit(
          title: 'draft',
          document: ComplexEditorDocument.parse(
            ComplexEditorKind.markdown,
            body,
          ),
          labels: const [],
        ),
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
      const source = '# checkpoint';
      final host = MarkdownCreationHost();
      final transport = ComplexEditorTransport(host.call);
      await transport.load(
        ComplexEditorDocument.parse(ComplexEditorKind.markdown, source),
        readOnly: false,
      );
      final c = LocalArticleCreationSourceCoordinator(
        freezeEdit: (body) => ComplexNoteEdit(
          title: 'title',
          document: ComplexEditorDocument.parse(
            ComplexEditorKind.markdown,
            body,
          ),
          labels: const [],
        ),
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
    const source = '# invalid metadata';
    final host = MarkdownCreationHost();
    final transport = ComplexEditorTransport(host.call);
    await transport.load(
      ComplexEditorDocument.parse(ComplexEditorKind.markdown, source),
      readOnly: false,
    );
    final c = LocalArticleCreationSourceCoordinator(
      freezeEdit: (body) => ComplexNoteEdit(
        title: 'title',
        document: ComplexEditorDocument.parse(ComplexEditorKind.markdown, body),
        labels: const [],
      ),
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
      const source = '# seed';
      const latest = '# last keystroke\r\n';
      final host = MarkdownCreationHost();
      final transport = ComplexEditorTransport(host.call);
      await transport.load(
        ComplexEditorDocument.parse(ComplexEditorKind.markdown, source),
        readOnly: false,
      );
      final started = Completer<void>();
      final delayedWrite = Completer<bool>();
      ComplexNoteEdit? captured;
      final c = LocalArticleCreationSourceCoordinator(
        freezeEdit: (body) => ComplexNoteEdit(
          title: 'latest title',
          document: ComplexEditorDocument.parse(
            ComplexEditorKind.markdown,
            body,
          ),
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
      expect(captured!.document.source, latest);
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
      final firstHost = MarkdownCreationHost();
      final firstTransport = ComplexEditorTransport(firstHost.call);
      await firstTransport.load(
        ComplexEditorDocument.parse(ComplexEditorKind.markdown, 'first'),
        readOnly: false,
      );
      final c = LocalArticleCreationSourceCoordinator(
        freezeEdit: (body) => ComplexNoteEdit(
          title: 'title',
          document: ComplexEditorDocument.parse(
            ComplexEditorKind.markdown,
            body,
          ),
          labels: const [],
        ),
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

      final secondHost = MarkdownCreationHost();
      final secondTransport = ComplexEditorTransport(secondHost.call);
      await secondTransport.load(
        ComplexEditorDocument.parse(ComplexEditorKind.markdown, 'second'),
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
      const seed = '# seed';
      const latest = '# last keystroke\r\n';
      final host = MarkdownCreationHost()
        ..snapshotStarted = Completer<void>()
        ..snapshotGate = Completer<void>();
      final transport = ComplexEditorTransport(host.call);
      await transport.load(
        ComplexEditorDocument.parse(ComplexEditorKind.markdown, seed),
        readOnly: false,
      );
      ComplexNoteEdit? captured;
      final c = LocalArticleCreationSourceCoordinator(
        freezeEdit: (body) => ComplexNoteEdit(
          title: 'title at retirement',
          document: ComplexEditorDocument.parse(
            ComplexEditorKind.markdown,
            body,
          ),
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
      expect(captured!.document.source, latest);
      expect(captured!.title, 'title at retirement');
      expect(captured!.labels, ['label at retirement']);
      expect(c.ready, isFalse);
      await transport.retire();
      await c.dispose();
    },
  );
}
