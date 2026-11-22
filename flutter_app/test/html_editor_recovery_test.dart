import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/html_editor_controller.dart';
import 'package:bookstark_flutter/core/html_notes_repository.dart';
import 'package:bookstark_flutter/core/html_recovery_vault.dart';
import 'html_notes_save_test.dart' show Server;

class Memory {
  final values = <String, String>{};
  bool failWrite = false, failRemove = false;
  Future<void>? holdWrite;
  HtmlRecoveryVault vault() => HtmlRecoveryVault(
    server: Uri.parse('https://books.example'),
    memberId: 3,
    collection: 'note',
    readValue: (key) async => values[key],
    writeValue: (key, value) async {
      if (failWrite) throw StateError('storage write failed');
      await holdWrite;
      values[key] = value;
    },
    deleteValue: (key) async {
      if (failRemove) throw StateError('storage cleanup failed');
      values.remove(key);
    },
  );
}

void main() {
  test(
    'unknown commit conflict stays pending until explicit baseline acceptance',
    () async {
      final s = Server(), m = Memory();
      final c = HtmlEditorController(
        s.repo,
        await s.baseline(),
        recovery: m.vault(),
      );
      s.loseContent = true;
      c.edit(s.edit());
      await c.save();
      s.source = '<p>Another device changed this after the uncertain save</p>';
      s.row['version'] = 99;
      await c.verify();
      expect(c.phase, HtmlEditorPhase.conflict);
      expect(c.hasPendingOperation, true);
      expect((await m.vault().read(7))!.pending, true);
      await expectLater(c.discardRecovery(), throwsStateError);
      final record = (await m.vault().read(7))!;
      final repository = RemoteHtmlNotesRepository(s.client, memberId: 3);
      final restored = HtmlEditorController.restore(
        repository,
        await repository.read(7),
        record,
        recovery: m.vault(),
      );
      expect(restored.phase, HtmlEditorPhase.contentUnknown);
      await restored.verify();
      expect(restored.phase, HtmlEditorPhase.conflict);
      expect((await m.vault().read(7))!.pending, true);
      restored.acceptLatestForEditing();
      expect(restored.hasPendingOperation, false);
      expect(await restored.flushRecovery(), true);
      expect((await m.vault().read(7))!.pending, false);
      expect(s.contentWrites, 1);
      expect(s.labelWrites, 0);
      restored.dispose();
      c.dispose();
      s.client.close();
    },
  );

  test('durable pending intent completes before any HTTP mutation', () async {
    final s = Server(), m = Memory(), gate = Completer<void>();
    m.holdWrite = gate.future;
    final c = HtmlEditorController(
      s.repo,
      await s.baseline(),
      recovery: m.vault(),
    );
    c.edit(s.edit());
    final save = c.save();
    await Future<void>.delayed(Duration.zero);
    expect(s.contentWrites, 0);
    expect(c.busy, true);
    gate.complete();
    await save;
    expect(c.phase, HtmlEditorPhase.saved);
    expect(m.values, isEmpty);
    expect(s.contentWrites, 1);
    expect(s.labelWrites, 1);
    c.dispose();
    s.client.close();
  });
  test(
    'failed intent persistence prevents network mutation and can retry explicitly',
    () async {
      final s = Server(), m = Memory()..failWrite = true;
      final c = HtmlEditorController(
        s.repo,
        await s.baseline(),
        recovery: m.vault(),
      );
      c.edit(s.edit());
      await c.save();
      expect(s.contentWrites, 0);
      expect(s.labelWrites, 0);
      expect(c.phase, HtmlEditorPhase.editing);
      expect(c.failure, isNotNull);
      m.failWrite = false;
      await c.save();
      expect(s.contentWrites, 1);
      expect(c.phase, HtmlEditorPhase.saved);
      c.dispose();
      s.client.close();
    },
  );
  test(
    'restart restores unknown intent, verifies read-only, then resumes labels without content replay',
    () async {
      final s = Server(), m = Memory();
      final v = m.vault();
      final c = HtmlEditorController(s.repo, await s.baseline(), recovery: v);
      s.loseContent = true;
      c.edit(s.edit());
      await c.save();
      final record = (await v.read(7))!;
      expect(record.pending, true);
      expect(s.contentWrites, 1);
      c.dispose();
      final repository = RemoteHtmlNotesRepository(s.client, memberId: 3);
      final current = await repository.read(7);
      final restored = HtmlEditorController.restore(
        repository,
        current,
        record,
        recovery: m.vault(),
      );
      expect(restored.phase, HtmlEditorPhase.contentUnknown);
      expect(restored.canSave, false);
      expect(restored.attempt!.contentReceipt, false);
      await expectLater(restored.save(), throwsStateError);
      expect(s.contentWrites, 1);
      await restored.verify();
      expect(restored.phase, HtmlEditorPhase.labelsPending);
      expect(s.labelWrites, 0);
      await restored.continueLabels();
      expect(s.contentWrites, 1);
      expect(s.labelWrites, 1);
      expect(restored.phase, HtmlEditorPhase.observed);
      expect(restored.attempt!.contentReceipt, false);
      expect(m.values, isEmpty);
      restored.dispose();
      s.client.close();
    },
  );
  test(
    'cleanup failure retains saved result and retries only storage',
    () async {
      final s = Server(), m = Memory()..failRemove = true;
      final c = HtmlEditorController(
        s.repo,
        await s.baseline(),
        recovery: m.vault(),
      );
      c.edit(s.edit());
      await c.save();
      expect(c.phase, HtmlEditorPhase.saved);
      expect(c.canSave, false);
      expect(c.recoveryFailure, isNotNull);
      expect(m.values, isNotEmpty);
      m.failRemove = false;
      expect(await c.flushRecovery(), true);
      expect(m.values, isEmpty);
      expect(s.contentWrites, 1);
      expect(s.labelWrites, 1);
      c.dispose();
      s.client.close();
    },
  );
  test(
    'protected unknown commit stores no source/title/labels/password and requires review after restart',
    () async {
      final s = Server(protected: true), m = Memory();
      final baseline = await s.baseline();
      final c = HtmlEditorController(s.repo, baseline, recovery: m.vault());
      s.loseContent = true;
      c.edit(s.edit());
      await c.save();
      final raw = m.values.values.single;
      final row = jsonDecode(raw) as Map;
      expect(row.containsKey('baseline'), false);
      expect(row.containsKey('edit'), false);
      expect(raw, isNot(contains('raw password')));
      expect(raw, isNot(contains(s.edit().source)));
      final record = (await m.vault().read(7))!;
      expect(record.protected, true);
      expect(
        () => HtmlEditorController.restore(s.repo, baseline, record),
        throwsFormatException,
      );
      c.dispose();
      s.client.close();
    },
  );
  test(
    'restoring changed baseline keeps draft and opens conflict without writes',
    () async {
      final s = Server(), m = Memory();
      final baseline = await s.baseline();
      await m.vault().write(
        HtmlRecoveryRecord.capture(baseline, s.edit(), pending: false),
      );
      s.source = '<p>Changed elsewhere</p>';
      s.row['version'] = 2;
      final current = await s.repo.read(7);
      final record = (await m.vault().read(7))!;
      final c = HtmlEditorController.restore(
        s.repo,
        current,
        record,
        recovery: m.vault(),
      );
      expect(c.phase, HtmlEditorPhase.conflict);
      expect(c.draft.source, s.edit().source);
      expect(c.latest!.source, s.source);
      expect(s.contentWrites, 0);
      expect(s.labelWrites, 0);
      c.dispose();
      s.client.close();
    },
  );
  test(
    'disposal while intent write is pending starts no HTTP mutation',
    () async {
      final s = Server(), m = Memory(), gate = Completer<void>();
      m.holdWrite = gate.future;
      final c = HtmlEditorController(
        s.repo,
        await s.baseline(),
        recovery: m.vault(),
      );
      c.edit(s.edit());
      final save = c.save();
      await Future<void>.delayed(Duration.zero);
      c.dispose();
      gate.complete();
      await save;
      expect(s.contentWrites, 0);
      expect(s.labelWrites, 0);
      expect((await m.vault().read(7))!.pending, true);
      s.client.close();
    },
  );
  test(
    'ordinary draft checkpoint and explicit discard remove only local recovery',
    () async {
      final s = Server(), m = Memory();
      final c = HtmlEditorController(
        s.repo,
        await s.baseline(),
        recovery: m.vault(),
      );
      c.edit(s.edit());
      expect(await c.flushRecovery(), true);
      expect((await m.vault().read(7))!.pending, false);
      expect(await c.discardRecovery(), true);
      expect(m.values, isEmpty);
      expect(s.contentWrites, 0);
      expect(s.labelWrites, 0);
      c.dispose();
      s.client.close();
    },
  );
}
