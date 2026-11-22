import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/reminder_repository.dart';
import 'package:bookstark_flutter/core/reminder_controller.dart';

ReminderDraft draft({
  bool enabled = false,
  String time = '09:00',
  int days = 1,
  bool overdue = true,
}) => ReminderDraft(
  enabled: enabled,
  sendTime: time,
  days: days,
  overdue: overdue,
);
ReminderSettings settings({
  ReminderDraft? prefs,
  bool available = true,
  String email = 'fixture@example.invalid',
}) => ReminderSettings(
  preferences: prefs ?? draft(),
  email: email,
  available: available,
  processedDate: '',
);

class Repo implements ReminderRepository {
  ReminderSettings current = settings();
  bool lose = false,
      readFails = false,
      afterWriteFails = false,
      mailLose = false;
  int writes = 0, mails = 0;
  int? mailStatus;
  Completer<void>? wait;
  @override
  Future<ReminderSettings> read() async {
    if (readFails) {
      throw StateError('fixture read failure');
    }
    return current;
  }

  @override
  Future<void> update(ReminderDraft value) async {
    writes++;
    if (wait != null) {
      await wait!.future;
    }
    current = settings(
      prefs: value,
      available: current.available,
      email: current.email,
    );
    if (afterWriteFails) {
      readFails = true;
    }
    if (lose) {
      throw TimeoutException('fixture lost receipt');
    }
  }

  @override
  Future<void> sendTest(String email) async {
    mails++;
    if (email != current.email) {
      throw const ReminderPreflightFailure();
    }
    if (mailStatus != null) {
      throw ApiFailure(mailStatus!, 'SMTP secret must never be displayed');
    }
    if (mailLose) {
      throw TimeoutException('fixture unknown delivery');
    }
  }
}

void main() {
  test(
    'save gets actual receipt and readback; equal current preferences need no mutation',
    () async {
      final r = Repo();
      final state = ReminderController(r, r.current);
      await state.save(draft());
      expect(r.writes, 0);
      expect(state.receivedReceipt, false);
      await state.save(draft(enabled: true, time: '23:59', days: 30));
      expect(state.phase, ReminderPhase.confirmed);
      expect(state.receivedReceipt, true);
      expect(r.writes, 1);
      expect(state.baseline.preferences.days, 30);
      state.dispose();
    },
  );
  test(
    'changed preferences or recipient produce observed conflict without writing',
    () async {
      for (final email in [false, true]) {
        final r = Repo();
        final state = ReminderController(r, r.current);
        r.current = settings(
          prefs: email ? draft() : draft(days: 5),
          email: email ? 'changed@example.invalid' : 'fixture@example.invalid',
        );
        await state.save(draft(enabled: true));
        expect(state.phase, ReminderPhase.conflict);
        expect(r.writes, 0);
        state.useObserved();
        await state.save(draft(enabled: true));
        expect(r.writes, 1);
        expect(state.phase, ReminderPhase.confirmed);
        state.dispose();
      }
    },
  );
  test(
    'unknown applied mutation only verifies on explicit read and never repeats PUT',
    () async {
      final r = Repo()..lose = true;
      final c = ReminderController(r, r.current);
      await c.save(draft(days: 7));
      expect(c.phase, ReminderPhase.unknown);
      await c.save(draft(days: 8));
      expect(r.writes, 1);
      await c.inspect();
      expect(c.phase, ReminderPhase.confirmed);
      expect(c.receivedReceipt, false);
      expect(r.writes, 1);
      c.dispose();
    },
  );
  test(
    'known receipt keeps unverified state after failed read; unavailable service can be disabled explicitly',
    () async {
      final r = Repo()..afterWriteFails = true;
      final c = ReminderController(r, r.current);
      await c.save(draft(days: 2));
      expect(c.phase, ReminderPhase.unverified);
      expect(c.receivedReceipt, true);
      r.readFails = false;
      await c.inspect();
      expect(c.phase, ReminderPhase.confirmed);
      c.dispose();
      final off = Repo()
        ..current = settings(prefs: draft(enabled: true), available: false);
      final state = ReminderController(off, off.current);
      await state.save(draft(enabled: true, days: 5));
      expect(off.writes, 0);
      expect(state.phase, ReminderPhase.failed);
      await state.save(draft(enabled: false));
      expect(off.writes, 1);
      expect(state.phase, ReminderPhase.confirmed);
      state.dispose();
    },
  );
  test(
    'test mail is explicit even if scheduling unavailable; unknown delivery never retries; limiter preserved',
    () async {
      final r = Repo()
        ..current = settings(available: false)
        ..mailLose = true;
      final c = ReminderController(r, r.current);
      expect(r.mails, 0);
      await c.sendTest(r.current.email);
      expect(c.mailPhase, ReminderMailPhase.unknown);
      expect(r.mails, 1);
      expect(r.writes, 0);
      r.mailLose = false;
      r.mailStatus = 429;
      await c.sendTest(r.current.email);
      expect(c.mailPhase, ReminderMailPhase.limited);
      expect(r.mails, 2);
      c.dispose();
    },
  );
  test(
    'disposed pending mutation performs no later reads or mail; invalid ranges are rejected',
    () async {
      final r = Repo()..wait = Completer<void>();
      final c = ReminderController(r, r.current);
      final pending = c.save(draft(days: 3));
      await Future<void>.delayed(Duration.zero);
      expect(r.writes, 1);
      c.dispose();
      r.wait!.complete();
      await pending;
      expect(r.mails, 0);
      for (final value in [
        draft(time: '24:00'),
        draft(time: '9:00'),
        draft(days: -1),
        draft(days: 31),
      ]) {
        expect(value.validate, throwsFormatException);
      }
    },
  );
}
