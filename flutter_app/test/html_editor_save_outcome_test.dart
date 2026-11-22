import 'dart:async';

import 'package:bookstark_flutter/core/html_editor_controller.dart';
import 'package:bookstark_flutter/core/html_notes_repository.dart';
import 'package:bookstark_flutter/core/html_recovery_vault.dart';
import 'package:flutter_test/flutter_test.dart';

import 'html_notes_save_test.dart' show Server;

class _MemoryRecovery {
  final values = <String, String>{};
  bool failWrite = false, failRemove = false;
  Future<void>? holdRemove;
  Completer<void>? removeStarted;

  HtmlRecoveryVault vault() => HtmlRecoveryVault(
    server: Uri.parse('https://books.example'),
    memberId: 3,
    collection: 'note',
    readValue: (key) async => values[key],
    writeValue: (key, value) async {
      if (failWrite) throw StateError('storage write failed');
      values[key] = value;
    },
    deleteValue: (key) async {
      final signal = removeStarted;
      if (signal != null && !signal.isCompleted) signal.complete();
      if (failRemove) throw StateError('storage cleanup failed');
      await holdRemove;
      values.remove(key);
    },
  );
}

void main() {
  test('invalid draft returns null without repository mutation', () async {
    final server = Server();
    final controller = HtmlEditorController(
      server.repo,
      await server.baseline(),
    );
    controller.edit(
      HtmlNoteEdit(
        title: ' ',
        source: '<p>invalid title</p>',
        labels: const [],
      ),
    );

    final outcome = await controller.saveWithOutcome();

    expect(outcome, isNull);
    expect(controller.failure, isNotNull);
    expect(server.contentWrites, 0);
    expect(server.labelWrites, 0);
    controller.dispose();
    server.close();
  });

  test(
    'pending recovery write failure returns null before repository mutation',
    () async {
      final server = Server();
      final memory = _MemoryRecovery()..failWrite = true;
      final controller = HtmlEditorController(
        server.repo,
        await server.baseline(),
        recovery: memory.vault(),
      );
      controller.edit(server.edit());

      final outcome = await controller.saveWithOutcome();

      expect(outcome, isNull);
      expect(controller.phase, HtmlEditorPhase.editing);
      expect(controller.failure, isNotNull);
      expect(server.contentWrites, 0);
      expect(server.labelWrites, 0);
      controller.dispose();
      server.close();
    },
  );

  test(
    'unknown response returns null; later read is observed, never a receipt',
    () async {
      final server = Server();
      final baseline = await server.baseline();
      final controller = HtmlEditorController(server.repo, baseline);
      server.loseContent = true;
      controller.edit(server.edit(labels: baseline.labels));

      final outcome = await controller.saveWithOutcome();

      expect(outcome, isNull);
      expect(controller.phase, HtmlEditorPhase.contentUnknown);
      expect(controller.attempt!.contentReceipt, isFalse);
      expect(server.contentWrites, 1);
      expect(server.labelWrites, 0);

      await controller.verify();

      expect(controller.phase, HtmlEditorPhase.observed);
      expect(controller.attempt!.contentReceipt, isFalse);
      expect(controller.attempt!.contentObserved, isTrue);
      expect(server.contentWrites, 1);
      expect(server.labelWrites, 0);
      controller.dispose();
      server.close();
    },
  );

  test(
    'incomplete label response returns null and preserves recovery phase',
    () async {
      final server = Server();
      final controller = HtmlEditorController(
        server.repo,
        await server.baseline(),
      );
      server.failLabels = true;
      controller.edit(server.edit());

      final outcome = await controller.saveWithOutcome();

      expect(outcome, isNull);
      expect(controller.phase, HtmlEditorPhase.labelsPending);
      expect(controller.attempt!.contentReceipt, isTrue);
      expect(controller.attempt!.labelsReceipt, isFalse);
      expect(server.contentWrites, 1);
      expect(server.labelWrites, 1);
      controller.dispose();
      server.close();
    },
  );

  test('known complete repository outcome is returned unchanged', () async {
    final server = Server();
    final controller = HtmlEditorController(
      server.repo,
      await server.baseline(),
    );
    final edit = server.edit();
    controller.edit(edit);

    final outcome = await controller.saveWithOutcome();

    expect(outcome, isA<HtmlSaveOutcome>());
    expect(outcome!.allReceiptsKnown, isTrue);
    expect(outcome.note.source, edit.source);
    expect(outcome.note.metadata.title, edit.title);
    expect(outcome.note.labels, edit.labels);
    expect(controller.phase, HtmlEditorPhase.saved);
    expect(server.contentWrites, 1);
    expect(server.labelWrites, 1);
    controller.dispose();
    server.close();
  });

  test(
    'actual receipt survives disposal while final recovery cleanup is pending',
    () async {
      final server = Server();
      final memory = _MemoryRecovery();
      final gate = Completer<void>();
      memory.holdRemove = gate.future;
      memory.removeStarted = Completer<void>();
      final controller = HtmlEditorController(
        server.repo,
        await server.baseline(),
        recovery: memory.vault(),
      );
      final edit = server.edit();
      controller.edit(edit);

      final saving = controller.saveWithOutcome();
      await memory.removeStarted!.future;
      expect(server.contentWrites, 1);
      expect(server.labelWrites, 1);
      controller.dispose();
      gate.complete();

      final outcome = await saving;

      expect(outcome, isNotNull);
      expect(outcome!.allReceiptsKnown, isTrue);
      expect(outcome.note.source, edit.source);
      expect(server.contentWrites, 1);
      expect(server.labelWrites, 1);
      server.close();
    },
  );

  test(
    'cleanup failure does not erase known receipt or repeat repository mutation',
    () async {
      final server = Server();
      final memory = _MemoryRecovery()..failRemove = true;
      final controller = HtmlEditorController(
        server.repo,
        await server.baseline(),
        recovery: memory.vault(),
      );
      final edit = server.edit();
      controller.edit(edit);

      final outcome = await controller.saveWithOutcome();

      expect(outcome, isNotNull);
      expect(outcome!.allReceiptsKnown, isTrue);
      expect(outcome.note.source, edit.source);
      expect(controller.phase, HtmlEditorPhase.saved);
      expect(controller.recoveryFailure, isNotNull);
      expect(memory.values, isNotEmpty);
      expect(server.contentWrites, 1);
      expect(server.labelWrites, 1);

      memory.failRemove = false;
      expect(await controller.flushRecovery(), isTrue);
      expect(memory.values, isEmpty);
      expect(server.contentWrites, 1);
      expect(server.labelWrites, 1);
      controller.dispose();
      server.close();
    },
  );
}
