import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/public_edit_link.dart';
import 'package:bookstark_flutter/core/public_edit_snapshot.dart';
import 'package:bookstark_flutter/core/public_edit_repository.dart';
import 'package:bookstark_flutter/core/public_edit_controller.dart';
import 'package:bookstark_flutter/core/public_share_models.dart';

final server = Uri.parse('https://example.test');
final link = PublicEditLink.parse(
  server,
  'https://example.test/shares/s?token=${List.filled(64, 'c').join()}',
);
PublicEditSnapshot snapshot(
  String content, {
  String modified = '2026-11-05 12:00:00',
}) {
  final context = PublicShareDetail.fromJson(link.reference, {
    'share_type': 'document',
    'share_id': 8,
    'target_id': 3,
    'share_identify': 's',
    'has_password': false,
    'title': 'Actual document',
    'doc_type': 'markdown',
    'content': content,
  });
  return PublicEditSnapshot.parse(context, {
    'editable': true,
    'share_type': 'document',
    'has_password': false,
    'title': 'Actual document',
    'doc_type': 'markdown',
    'content': content,
    'modify_time': modified,
  });
}

class Repository implements PublicEditRepository {
  PublicEditSnapshot current = snapshot('old');
  int writes = 0;
  Object? saveFailure;
  bool failAfterSave = false, failReads = false;
  @override
  Future<PublicEditSnapshot> read(
    PublicEditLink link, {
    String? password,
    Future<void>? abortTrigger,
  }) async {
    if (failReads) throw StateError('read unavailable');
    if (writes > 0 && failAfterSave) throw StateError('read unavailable');
    return current;
  }

  @override
  Future<PublicEditReceipt> save(
    PublicEditLink link,
    PublicEditSnapshot baseline,
    String content, {
    String? password,
  }) async {
    writes++;
    if (saveFailure != null) throw saveFailure!;
    current = snapshot(content, modified: '2026-11-05 12:01:00');
    return PublicEditReceipt(link.reference, current.modified);
  }
}

void main() {
  test(
    'explicit resume recheck can recover a temporary read failure without resetting the baseline',
    () async {
      final repo = Repository();
      final controller = PublicEditController(repo, link);
      await controller.initialize();
      repo.failReads = true;
      await expectLater(
        controller.revalidateForResume('working'),
        throwsStateError,
      );
      expect(controller.phase, PublicEditPhase.blocked);
      expect(controller.pendingBody, 'working');
      repo.failReads = false;
      await controller.revalidateForResume('working');
      expect(controller.phase, PublicEditPhase.ready);
      expect(controller.snapshot!.content, 'old');
      expect(repo.writes, 0);
      controller.close();
    },
  );

  test(
    'resume rereads without writing and retains the original conflict baseline',
    () async {
      final repo = Repository();
      final controller = PublicEditController(repo, link);
      await controller.initialize();
      await controller.revalidateForResume('working');
      expect(controller.phase, PublicEditPhase.ready);
      expect(repo.writes, 0);
      repo.current = snapshot('other', modified: '2026-11-10 12:00:00');
      await controller.revalidateForResume('working');
      expect(controller.phase, PublicEditPhase.conflict);
      expect(controller.pendingBody, 'working');
      expect(controller.snapshot!.content, 'old');
      expect(controller.conflict!.content, 'other');
      expect(repo.writes, 0);
      controller.close();
    },
  );
  test('resume cannot reset an unknown save or issue another write', () async {
    final repo = Repository()..saveFailure = StateError('connection lost');
    final controller = PublicEditController(repo, link);
    await controller.initialize();
    await expectLater(controller.save('working'), throwsStateError);
    await expectLater(
      controller.revalidateForResume('working'),
      throwsStateError,
    );
    expect(controller.phase, PublicEditPhase.unknown);
    expect(controller.pendingBody, 'working');
    expect(repo.writes, 1);
    controller.close();
  });

  test(
    'external change blocks PUT and acknowledged overwrite rechecks the exact displayed version',
    () async {
      final repo = Repository();
      final actual = PublicEditController(repo, link);
      await actual.initialize();
      repo.current = snapshot('other', modified: '2026-11-05 12:00:01');
      await actual.save('local');
      expect(actual.phase, PublicEditPhase.conflict);
      expect(repo.writes, 0);
      final displayed = actual.conflict!;
      repo.current = snapshot('third', modified: '2026-11-05 12:00:02');
      await actual.save('local', overwriteObserved: displayed);
      expect(repo.writes, 0);
      expect(actual.conflict!.content, 'third');
      await actual.save('local', overwriteObserved: actual.conflict);
      expect(repo.writes, 1);
      expect(actual.phase, PublicEditPhase.acknowledged);
      expect(actual.snapshot!.content, 'local');
      expect(actual.receipt, isNotNull);
      actual.close();
    },
  );
  test(
    'acknowledged write survives failed reread and verification never sends another PUT',
    () async {
      final repo = Repository()..failAfterSave = true;
      final controller = PublicEditController(repo, link);
      await controller.initialize();
      await controller.save('desired');
      expect(controller.phase, PublicEditPhase.unverified);
      expect(controller.receipt, isNotNull);
      await expectLater(controller.save('desired'), throwsStateError);
      await expectLater(controller.initialize(), throwsStateError);
      repo.failAfterSave = false;
      await controller.verify();
      expect(controller.phase, PublicEditPhase.acknowledged);
      expect(repo.writes, 1);
      controller.close();
    },
  );
  test(
    'unknown write requires read verification and explicit retry acknowledgement',
    () async {
      final repo = Repository()..saveFailure = StateError('connection lost');
      final controller = PublicEditController(repo, link);
      await controller.initialize();
      await expectLater(controller.save('desired'), throwsStateError);
      expect(controller.phase, PublicEditPhase.unknown);
      expect(repo.writes, 1);
      expect(() => controller.acknowledgeRetry(), throwsStateError);
      await expectLater(controller.initialize(), throwsStateError);
      await controller.verify();
      expect(controller.remoteStillBaseline, isTrue);
      expect(repo.writes, 1);
      controller.acknowledgeRetry();
      repo.saveFailure = null;
      await controller.save('desired');
      expect(repo.writes, 2);
      expect(controller.phase, PublicEditPhase.acknowledged);
      controller.close();
    },
  );
  test(
    'unknown result which already matches desired remote content confirms through GET only',
    () async {
      final repo = Repository()..saveFailure = StateError('lost receipt');
      final controller = PublicEditController(repo, link);
      await controller.initialize();
      await expectLater(controller.save('desired'), throwsStateError);
      repo.current = snapshot('desired', modified: '2026-11-05 12:01:00');
      await controller.verify();
      expect(controller.phase, PublicEditPhase.acknowledged);
      expect(controller.confirmedByRead, isTrue);
      expect(controller.receipt, isNull);
      expect(repo.writes, 1);
      controller.close();
    },
  );
  test(
    'definite rejection can be corrected; unchanged desired body needs no PUT',
    () async {
      final repo = Repository()
        ..saveFailure = const ApiFailure(400, 'rejected');
      final controller = PublicEditController(repo, link);
      await controller.initialize();
      await expectLater(controller.save('desired'), throwsA(isA<ApiFailure>()));
      expect(controller.phase, PublicEditPhase.ready);
      await controller.save('old');
      expect(repo.writes, 1);
      expect(controller.confirmedByRead, isTrue);
      expect(controller.receipt, isNull);
      controller.close();
      expect(controller.snapshot, isNull);
      expect(controller.pendingBody, isNull);
    },
  );
}
