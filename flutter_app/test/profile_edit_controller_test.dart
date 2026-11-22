import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/profile_repository.dart';
import 'package:bookstark_flutter/core/profile_edit_controller.dart';

MemberProfile member({
  String email = 'old@example.test',
  String home = 'notes',
}) => MemberProfile(
  id: 7,
  account: 'fixture',
  email: email,
  role: 1,
  defaultHome: home,
);

class Repo implements ProfileRepository {
  MemberProfile current = member();
  int writes = 0, reads = 0;
  bool lose = false, readFails = false, failAfterWrite = false;
  Completer<void>? wait;
  @override
  Future<MemberProfile> read() async {
    reads++;
    if (readFails) {
      throw StateError('read unavailable');
    }
    return current;
  }

  @override
  Future<void> update(ProfileDraft draft) async {
    writes++;
    if (wait != null) {
      await wait!.future;
    }
    current = member(email: draft.email, home: draft.defaultHome);
    if (failAfterWrite) {
      readFails = true;
    }
    if (lose) {
      throw TimeoutException('lost receipt');
    }
  }
}

void main() {
  ProfileDraft draft() =>
      ProfileDraft(email: 'new@example.test', defaultHome: 'books');
  test(
    'unchanged actual fields confirm by read with no PUT; changed fields get receipt then exact re-read',
    () async {
      final r = Repo(), c = ProfileEditController(Repo(), member());
      await c.save(
        ProfileDraft(email: 'old@example.test', defaultHome: 'notes'),
      );
      expect(c.phase, ProfileEditPhase.confirmed);
      expect((c.repository as Repo).writes, 0);
      expect(c.receivedWriteReceipt, isFalse);
      c.dispose();
      final edit = ProfileEditController(r, member());
      await edit.save(draft());
      expect(edit.phase, ProfileEditPhase.confirmed);
      expect(edit.receivedWriteReceipt, isTrue);
      expect(r.writes, 1);
      expect(edit.baseline.email, 'new@example.test');
      edit.dispose();
    },
  );
  test(
    'preflight conflict blocks PUT; explicit observed overwrite checks third-party changes again',
    () async {
      final r = Repo()..current = member(email: 'other@example.test');
      final c = ProfileEditController(r, member());
      await c.save(draft());
      expect(c.phase, ProfileEditPhase.conflict);
      expect(r.writes, 0);
      final seen = c.observed!;
      r.current = member(email: 'third@example.test');
      await c.save(draft(), overwriteObserved: seen);
      expect(c.phase, ProfileEditPhase.conflict);
      expect(c.observed!.email, 'third@example.test');
      expect(r.writes, 0);
      await c.save(draft(), overwriteObserved: c.observed);
      expect(c.phase, ProfileEditPhase.confirmed);
      expect(r.writes, 1);
      c.dispose();
    },
  );
  test(
    'lost applied update is never automatically resent and can be confirmed by GET',
    () async {
      final r = Repo()..lose = true;
      final c = ProfileEditController(r, member());
      await c.save(draft());
      expect(c.phase, ProfileEditPhase.unknown);
      await c.save(draft());
      expect(r.writes, 1);
      await c.inspect();
      expect(c.phase, ProfileEditPhase.confirmed);
      expect(c.receivedWriteReceipt, isFalse);
      expect(r.writes, 1);
      c.dispose();
    },
  );
  test(
    'received update followed by read failure retains receipt and read retry never PUTs',
    () async {
      final r = Repo()..failAfterWrite = true;
      final c = ProfileEditController(r, member());
      await c.save(draft());
      expect(c.phase, ProfileEditPhase.unverified);
      expect(c.receivedWriteReceipt, isTrue);
      r.readFails = false;
      await c.inspect();
      expect(c.phase, ProfileEditPhase.confirmed);
      expect(r.writes, 1);
      c.dispose();
    },
  );
  test(
    'adopting observed remote data is explicit and cannot bypass unresolved operations',
    () async {
      final r = Repo()..current = member(email: 'remote@example.test');
      final c = ProfileEditController(r, member());
      await c.save(draft());
      expect(c.useObserved().email, 'remote@example.test');
      expect(c.submitted, isNull);
      expect(r.writes, 0);
      r.lose = true;
      await c.save(draft());
      expect(c.phase, ProfileEditPhase.unknown);
      expect(c.useObserved, throwsStateError);
      c.dispose();
    },
  );
  test(
    'concurrent saves blocked and late response after disposal cannot restore submitted data',
    () async {
      final r = Repo()..wait = Completer<void>();
      final c = ProfileEditController(r, member());
      final pending = c.save(draft());
      await Future<void>.delayed(Duration.zero);
      await c.save(draft());
      expect(r.writes, 1);
      c.dispose();
      r.wait!.complete();
      await pending;
      expect(c.submitted, isNull);
      expect(c.observed, isNull);
      c.dispose();
    },
  );
}
