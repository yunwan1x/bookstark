import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/complex_editor_transport.dart';
import 'package:bookstark_flutter/core/public_edit_controller.dart';
import 'package:bookstark_flutter/core/shared_markdown_session.dart';

import 'public_edit_controller_test.dart' as fixture;
import 'support/markdown_creation_host.dart';

void main() {
  late fixture.Repository repo;
  late PublicEditController controller;
  late SharedMarkdownSession session;
  late MarkdownCreationHost host;
  late ComplexEditorTransport transport;
  bool loseInsertionReply = false;
  int acknowledgements = 0;
  setUp(() async {
    acknowledgements = 0;
    loseInsertionReply = false;
    repo = fixture.Repository();
    controller = PublicEditController(repo, fixture.link);
    await controller.initialize();
    session = SharedMarkdownSession(controller);
    host = MarkdownCreationHost();
    transport = ComplexEditorTransport((name, args) async {
      if (name == 'insertMarkdownSnapshot') {
        host.source += args[1] as String;
        host.revision++;
        if (loseInsertionReply) throw StateError('insertion receipt lost');
        await host.call('endSnapshot', [args[0]]);
        return host.state();
      }
      if (name == 'acknowledgeSnapshot') {
        acknowledgements++;
        await host.call('endSnapshot', args);
        return host.state();
      }
      return host.call(name, args);
    });
    await transport.load(
      ComplexEditorDocument.parse(ComplexEditorKind.markdown, session.body),
      readOnly: false,
      sharedMarkdownEditing: true,
      publicResourceRoot: fixture.server,
    );
    await session.attach(transport);
  });
  tearDown(() async {
    session.dispose();
    controller.close();
    await transport.retire();
  });
  test(
    'GET confirmation acknowledges an exact fresh renderer snapshot without another PUT',
    () async {
      host.source = 'working';
      host.revision = 1;
      repo.saveFailure = StateError('response lost');
      await expectLater(session.save(), throwsStateError);
      expect(acknowledgements, 0);
      repo.current = fixture.snapshot('working');
      await session.verify();
      expect(controller.phase, PublicEditPhase.acknowledged);
      expect(acknowledgements, 1);
      expect(repo.writes, 1);
      expect(session.body, 'working');
      expect(host.transfers, isEmpty);
      expect(host.locked, isFalse);
    },
  );
  test(
    'verification retains late live input and does not acknowledge an older confirmed body',
    () async {
      host.source = 'attempted';
      host.revision = 1;
      repo.saveFailure = StateError('response lost');
      await expectLater(session.save(), throwsStateError);
      host.source = 'late live input';
      host.revision = 2;
      repo.current = fixture.snapshot('attempted');
      await session.verify();
      expect(controller.phase, PublicEditPhase.acknowledged);
      expect(acknowledgements, 0);
      expect(session.body, 'late live input');
      expect(session.dirty, isTrue);
      expect(repo.writes, 1);
      expect(host.transfers, isEmpty);
      expect(host.locked, isFalse);
    },
  );
  test(
    'verification while paused confirms remotely without reopening or acknowledging a retired renderer',
    () async {
      host.source = 'working';
      repo.saveFailure = StateError('response lost');
      await expectLater(session.save(), throwsStateError);
      await session.beforeRetire(transport);
      repo.current = fixture.snapshot('working');
      await session.verify();
      expect(controller.phase, PublicEditPhase.acknowledged);
      expect(session.paused, isTrue);
      expect(acknowledgements, 0);
      expect(repo.writes, 1);
      expect(host.locked, isTrue);
    },
  );
  test(
    'uncertain insertion stays locked until a fresh exact capture succeeds',
    () async {
      final insertion = await session.beginInsertion();
      loseInsertionReply = true;
      await expectLater(
        session.finishInsertion(insertion, '[file](upload-files/a.txt)'),
        throwsStateError,
      );
      expect(session.captureFailed, isTrue);
      expect(host.locked, isTrue);
      expect(session.body, 'old');
      expect(session.canRecapture, isTrue);
      await session.capture();
      expect(session.body, 'old[file](upload-files/a.txt)');
      expect(session.captureFailed, isFalse);
      expect(host.locked, isFalse);
      expect(repo.writes, 0);
    },
  );
  test(
    'oversized shared source remains exact and copyable with no PUT',
    () async {
      host.source = 'x' * (500 * 1024 + 1);
      await expectLater(session.save(), throwsFormatException);
      expect(session.body, host.source);
      expect(repo.writes, 0);
      expect(host.locked, isFalse);
      expect(host.transfers, isEmpty);
    },
  );
  test(
    'attachment cancellation preserves exact body and unlocks without writing',
    () async {
      final insertion = await session.beginInsertion();
      expect(host.locked, isTrue);
      expect(session.canEdit, isFalse);
      await session.finishInsertion(insertion, null);
      expect(host.source, 'old');
      expect(host.locked, isFalse);
      expect(session.canEdit, isTrue);
      expect(host.transfers, isEmpty);
      expect(repo.writes, 0);
    },
  );
  test(
    'attachment result is inserted only after a fresh capability read',
    () async {
      final insertion = await session.beginInsertion();
      await session.finishInsertion(insertion, '[file](upload-files/a.txt)');
      expect(host.source, 'old[file](upload-files/a.txt)');
      expect(session.body, host.source);
      expect(host.locked, isFalse);
      expect(host.transfers, isEmpty);
      expect(repo.writes, 0);
    },
  );
  test(
    'attachment arriving after background cannot enter the retired source',
    () async {
      final insertion = await session.beginInsertion();
      await session.beforeRetire(transport);
      await expectLater(
        session.finishInsertion(insertion, '[file](upload-files/a.txt)'),
        throwsStateError,
      );
      expect(host.source, 'old');
      expect(session.body, 'old');
      expect(session.paused, isTrue);
      expect(repo.writes, 0);
    },
  );
  test(
    'permission recheck detects remote change before attachment insertion',
    () async {
      final insertion = await session.beginInsertion();
      repo.current = fixture.snapshot('other', modified: '2026-11-10 14:00:00');
      await expectLater(
        session.finishInsertion(insertion, '[file](upload-files/a.txt)'),
        throwsStateError,
      );
      expect(host.source, 'old');
      expect(controller.phase, PublicEditPhase.conflict);
      expect(host.locked, isTrue);
      expect(host.transfers, isEmpty);
      expect(repo.writes, 0);
    },
  );
  test(
    'paused conflict overwrite still checks the displayed remote version again',
    () async {
      host.source = 'working';
      await session.beforeRetire(transport);
      repo.current = fixture.snapshot('other', modified: '2026-11-10 13:00:00');
      await session.resume();
      final observed = controller.conflict!;
      repo.current = fixture.snapshot('third', modified: '2026-11-10 13:01:00');
      await session.overwriteRetained(observed);
      expect(controller.conflict!.content, 'third');
      expect(repo.writes, 0);
      await session.overwriteRetained(controller.conflict!);
      expect(repo.writes, 1);
      expect(repo.current.content, 'working');
      expect(session.paused, isTrue);
    },
  );
  test(
    'adopting remote requires retirement and keeps subsequent resume read only',
    () async {
      repo.current = fixture.snapshot(
        'remote',
        modified: '2026-11-10 13:00:00',
      );
      await session.save();
      await expectLater(session.adoptRemoteWhilePaused(), throwsStateError);
      await session.beforeRetire(transport);
      await session.adoptRemoteWhilePaused();
      expect(session.body, 'remote');
      expect(session.paused, isTrue);
      await session.resume();
      expect(session.paused, isFalse);
      expect(repo.writes, 0);
    },
  );
  test(
    'copy captures exact live source and releases its frozen buffer',
    () async {
      host.source = '\ufeff# Changed\r\n';
      await session.capture();
      expect(session.body, host.source);
      expect(session.dirty, isTrue);
      expect(host.transfers, isEmpty);
      expect(host.locked, isFalse);
      expect(repo.writes, 0);
    },
  );
  test(
    'unknown PUT keeps source locked and verification sends no second PUT',
    () async {
      host.source = 'working';
      repo.saveFailure = StateError('lost response');
      await expectLater(session.save(), throwsStateError);
      expect(session.body, 'working');
      expect(controller.phase, PublicEditPhase.unknown);
      expect(host.locked, isTrue);
      expect(host.transfers, isEmpty);
      repo.current = fixture.snapshot('working');
      await session.verify();
      expect(repo.writes, 1);
      expect(controller.phase, PublicEditPhase.acknowledged);
      expect(host.locked, isFalse);
    },
  );
  test(
    'successful save acknowledges only the exact verified snapshot',
    () async {
      host.source = 'working';
      await session.save();
      expect(repo.writes, 1);
      expect(controller.phase, PublicEditPhase.acknowledged);
      expect(controller.receipt, isNotNull);
      expect(session.dirty, isFalse);
      expect(host.transfers, isEmpty);
      expect(host.locked, isFalse);
    },
  );
  test(
    'background queues after an active capture and pauses without writing',
    () async {
      host.source = 'working';
      host.snapshotStarted = Completer<void>();
      host.snapshotGate = Completer<void>();
      final copy = session.capture();
      await host.snapshotStarted!.future;
      final retiring = session.beforeRetire(transport);
      host.snapshotGate!.complete();
      await copy;
      await retiring;
      expect(session.body, 'working');
      expect(session.paused, isTrue);
      expect(host.maxConcurrentSnapshots, 1);
      expect(host.locked, isTrue);
      expect(repo.writes, 0);
      await session.resume();
      expect(session.paused, isFalse);
      expect(session.body, 'working');
      expect(repo.writes, 0);
    },
  );
  test(
    'failed final capture reports uncertainty and forbids silent resume',
    () async {
      host.failSnapshot = true;
      await expectLater(session.beforeRetire(transport), throwsStateError);
      expect(session.body, 'old');
      expect(session.captureFailed, isTrue);
      expect(session.paused, isTrue);
      await expectLater(session.resume(), throwsStateError);
      expect(repo.writes, 0);
    },
  );
  for (final operation in ['save', 'beginInsertion']) {
    test('held $operation capture after disposal cannot write RAM or server', () async {
      host.source = 'late body must never be saved';
      host.snapshotStarted = Completer<void>();
      host.snapshotGate = Completer<void>();
      final Future<Object?> pending = operation == 'save'
          ? session.save()
          : session.beginInsertion();
      final failure = expectLater(pending, throwsStateError);
      await host.snapshotStarted!.future;
      session.dispose();
      host.snapshotGate!.complete();
      await failure;
      expect(session.body, '');
      expect(repo.writes, 0);
      expect(acknowledgements, 0);
      expect(host.transfers, isEmpty);
      expect(session.canEdit, isFalse);
    });
  }

  test('disposed owner retirement is idempotent and performs no capture', () async {
    final generation = host.generation;
    final source = host.source;
    session.dispose();
    await session.beforeRetire(transport);
    await session.beforeRetire(transport);
    expect(session.body, '');
    expect(host.generation, generation);
    expect(host.source, source);
    expect(host.transfers, isEmpty);
    expect(repo.writes, 0);
    await expectLater(session.capture(), throwsStateError);
  });

  test('queued retirement observes disposal before touching the runtime', () async {
    final retiring = session.beforeRetire(transport);
    session.dispose();
    host.failSnapshot = true;
    await retiring;
    expect(session.body, '');
    expect(host.transfers, isEmpty);
    expect(repo.writes, 0);
  });

  test('live retirement failure blocks retries until explicit discard', () async {
    host.failSnapshot = true;
    await expectLater(session.beforeRetire(transport), throwsStateError);
    host.failSnapshot = false;
    host.source = 'must not replace retained copy';
    await expectLater(session.beforeRetire(transport), throwsStateError);
    expect(session.body, 'old');
    expect(session.captureFailed, isTrue);
    expect(host.transfers, isEmpty);
    expect(repo.writes, 0);
    session.acknowledgeDiscardForExit();
    await session.beforeRetire(transport);
    expect(session.body, 'old');
    expect(host.transfers, isEmpty);
    expect(repo.writes, 0);
    await expectLater(session.resume(), throwsStateError);
  });

  test('late snapshot cannot repopulate a disposed RAM owner', () async {
    host.source = 'late private working copy';
    host.snapshotStarted = Completer<void>();
    host.snapshotGate = Completer<void>();
    final retiring = session.beforeRetire(transport);
    await host.snapshotStarted!.future;
    session.dispose();
    host.snapshotGate!.complete();
    await retiring;
    expect(session.body, '');
    expect(host.transfers, isEmpty);
    expect(repo.writes, 0);
  });

  test(
    'remote change on resume retains working copy and requires conflict review',
    () async {
      host.source = 'working';
      await session.beforeRetire(transport);
      repo.current = fixture.snapshot('other', modified: '2026-11-10 13:00:00');
      await session.resume();
      expect(session.paused, isTrue);
      expect(session.body, 'working');
      expect(controller.phase, PublicEditPhase.conflict);
      expect(controller.snapshot!.content, 'old');
      expect(controller.conflict!.content, 'other');
      expect(repo.writes, 0);
    },
  );
}
