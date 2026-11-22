import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/attachments.dart';
import 'package:bookstark_flutter/core/owned15_editor_lifetime.dart';
import 'package:bookstark_flutter/core/owned15_save_journal.dart';

void main() {
  late Owned15SaveJournal journal;
  late Owned15EditorLifetime owner;
  bool scope = true;
  int reported = 0;
  Future<void> Function()? crypto;
  setUp(() {
    scope = true;
    reported = 0;
    crypto = null;
    journal = Owned15SaveJournal(
      draftNamespace: 'local-generation:${'a' * 32}',
      collection: 'note',
      resourceId: 9,
      isCurrent: () => owner.current,
      readValue: (_) async => null,
      writeValue: (_, _) async {},
      deleteValue: (_) async {},
      flush: () async {},
    );
    owner = Owned15EditorLifetime(
      journal: journal,
      isCurrentScope: () => scope,
      drainCrypto: () => crypto?.call() ?? Future<void>.value(),
      onDrained: (_) {
        reported++;
      },
    );
  });
  tearDown(() async {
    crypto = null;
    await owner.retire();
  });
  test(
    'retire synchronously cancels opening and joins late result plus actual crypto drain',
    () async {
      final opening = Completer<String>(), ack = Completer<void>();
      AttachmentCancellation? request;
      var disposed = 0, done = false;
      crypto = () => ack.future;
      final work = owner.run(
        (c) {
          request = c;
          return opening.future;
        },
        onLateResult: (_) {
          disposed++;
        },
      );
      final failure = expectLater(work, throwsStateError);
      final closing = owner.retire().then((_) => done = true);
      expect(owner.current, isFalse);
      expect(request!.cancelled, isTrue);
      expect(done, isFalse);
      expect(reported, 0);
      opening.complete('memory-only-result');
      await failure;
      await Future<void>.delayed(Duration.zero);
      expect(disposed, 1);
      expect(done, isFalse);
      expect(reported, 0);
      ack.complete();
      await closing;
      expect(done, isTrue);
      expect(reported, 1);
    },
  );
  test(
    'real repository drain failure blocks owner removal and permits explicit retry',
    () async {
      var failed = true, closed = 0;
      owner.bindRepository(
        close: () {
          closed++;
        },
        drain: () async {
          if (failed) throw StateError('Worker acknowledgement missing');
        },
      );
      await expectLater(owner.retire(), throwsStateError);
      expect(owner.current, isFalse);
      expect(reported, 0);
      expect(closed, 1);
      failed = false;
      await owner.retire();
      expect(reported, 1);
      expect(closed, 2);
    },
  );
  test(
    'synchronous route disposal reentry observes same already-published retirement future',
    () async {
      Future<void>? reentered;
      owner.bindRoute(() async {
        reentered = owner.retire();
      });
      final closing = owner.retire();
      await closing;
      expect(identical(reentered, closing), isTrue);
      expect(reported, 1);
    },
  );
  test(
    'preview retirement failure cannot activate a fresh preview before retry',
    () async {
      var failed = true;
      owner.preview.bind(Object(), () async {
        if (failed) throw StateError('Native lease retained');
      });
      await expectLater(owner.retire(), throwsStateError);
      expect(reported, 0);
      expect(owner.current, isFalse);
      await expectLater(owner.nextPreview(), throwsStateError);
      failed = false;
      await owner.retire();
      expect(reported, 1);
    },
  );
}
