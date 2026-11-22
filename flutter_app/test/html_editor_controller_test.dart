import 'dart:async';
import 'package:bookstark_flutter/core/html_editor_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'html_notes_save_test.dart' show Server;

void main() {
  test(
    'real save becomes complete only after both receipts and content/labels readback',
    () async {
      final s = Server();
      final c = HtmlEditorController(s.repo, await s.baseline());
      expect(c.phase, HtmlEditorPhase.clean);
      c.edit(s.edit());
      await c.save();
      expect(c.phase, HtmlEditorPhase.saved);
      expect(c.baseline.source, s.edit().source);
      expect(s.contentWrites, 1);
      expect(s.labelWrites, 1);
      c.dispose();
      s.client.close();
    },
  );
  test(
    'partial save blocks editing/resubmit and resumes only labels explicitly',
    () async {
      final s = Server();
      final c = HtmlEditorController(s.repo, await s.baseline());
      s.failLabels = true;
      c.edit(s.edit());
      await c.save();
      expect(c.phase, HtmlEditorPhase.labelsPending);
      expect(c.canEdit, isFalse);
      await expectLater(c.save(), throwsStateError);
      expect(() => c.edit(s.edit()), throwsStateError);
      s.failLabels = false;
      await c.continueLabels();
      expect(c.phase, HtmlEditorPhase.saved);
      expect(s.contentWrites, 1);
      expect(s.labelWrites, 2);
      c.dispose();
      s.client.close();
    },
  );
  test(
    'lost content receipt needs explicit readonly verification before labels, without fabricating receipt',
    () async {
      final s = Server();
      final c = HtmlEditorController(s.repo, await s.baseline());
      s.loseContent = true;
      c.edit(s.edit());
      await c.save();
      expect(c.phase, HtmlEditorPhase.contentUnknown);
      expect(c.attempt!.contentReceipt, isFalse);
      expect(s.labelWrites, 0);
      await expectLater(c.continueLabels(), throwsStateError);
      await c.verify();
      expect(c.phase, HtmlEditorPhase.labelsPending);
      expect(c.attempt!.contentObserved, isTrue);
      expect(c.attempt!.contentReceipt, isFalse);
      expect(s.contentWrites, 1);
      expect(s.labelWrites, 0);
      await c.continueLabels();
      expect(c.phase, HtmlEditorPhase.observed);
      expect(c.baseline.labels, isEmpty);
      expect(c.attempt!.contentReceipt, isFalse);
      expect(s.contentWrites, 1);
      expect(s.labelWrites, 1);
      c.dispose();
      s.client.close();
    },
  );
  test(
    'lost label receipt is observed by read, without repeating any mutation',
    () async {
      final s = Server();
      final c = HtmlEditorController(s.repo, await s.baseline());
      s.loseLabels = true;
      c.edit(s.edit());
      await c.save();
      expect(c.phase, HtmlEditorPhase.labelsPending);
      await c.verify();
      expect(c.phase, HtmlEditorPhase.observed);
      expect(s.contentWrites, 1);
      expect(s.labelWrites, 1);
      expect(c.attempt!.labelsReceipt, isFalse);
      c.dispose();
      s.client.close();
    },
  );
  test(
    'conflict preserves unsaved source; accepted baseline does not write until a separate save',
    () async {
      final s = Server();
      final c = HtmlEditorController(s.repo, await s.baseline());
      c.edit(s.edit());
      s.row['version'] = 10;
      s.source = '<p>External version</p>';
      await c.save();
      expect(c.phase, HtmlEditorPhase.conflict);
      expect(c.draft.source, s.edit().source);
      expect(c.latest!.source, '<p>External version</p>');
      expect(s.contentWrites, 0);
      c.acceptLatestForEditing();
      expect(c.phase, HtmlEditorPhase.editing);
      expect(s.contentWrites, 0);
      expect(c.draft.source, s.edit().source);
      await c.save();
      expect(c.phase, HtmlEditorPhase.saved);
      expect(s.contentWrites, 1);
      c.dispose();
      s.client.close();
    },
  );
  test(
    'unknown readback that differs from expected source remains a reviewable conflict',
    () async {
      final s = Server();
      final c = HtmlEditorController(s.repo, await s.baseline());
      c.edit(s.edit());
      s.loseContent = true;
      s.afterContent = () {
        s.source = '<p>Another writer</p>';
      };
      await c.save();
      expect(c.phase, HtmlEditorPhase.contentUnknown);
      await c.verify();
      expect(c.phase, HtmlEditorPhase.conflict);
      expect(c.latest!.source, '<p>Another writer</p>');
      expect(c.draft.source, s.edit().source);
      expect(s.contentWrites, 1);
      expect(s.labelWrites, 0);
      c.dispose();
      s.client.close();
    },
  );
  test(
    'protected editing never permits an ordinary persistent draft',
    () async {
      final s = Server(protected: true);
      final c = HtmlEditorController(s.repo, await s.baseline());
      expect(c.canPersistDraft, isFalse);
      c.edit(s.edit());
      await c.save();
      expect(c.canPersistDraft, isFalse);
      expect(c.phase, HtmlEditorPhase.saved);
      c.dispose();
      s.client.close();
    },
  );
  test(
    'dispose during applied content request suppresses late notifications and label mutation',
    () async {
      final s = Server();
      final c = HtmlEditorController(s.repo, await s.baseline());
      final gate = Completer<void>();
      s.holdContent = gate.future;
      var events = 0;
      c.addListener(() => events++);
      c.edit(s.edit());
      final saving = c.save();
      while (s.contentWrites == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      c.dispose();
      final count = events;
      gate.complete();
      await saving;
      expect(events, count);
      expect(s.contentWrites, 1);
      expect(s.labelWrites, 0);
      s.client.close();
    },
  );
}
