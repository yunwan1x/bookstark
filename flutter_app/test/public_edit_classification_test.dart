import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/public_share_models.dart';
import 'package:bookstark_flutter/core/public_edit_snapshot.dart';
import 'package:bookstark_flutter/core/public_edit_link.dart';
import 'package:bookstark_flutter/core/public_edit_repository.dart';
import 'package:bookstark_flutter/core/public_edit_controller.dart';

final reference = PublicShareReference(
  Uri.parse('https://example.test/base'),
  'editing',
);
PublicShareDetail context(String? type) =>
    PublicShareDetail.fromJson(reference, {
      'share_type': 'blog',
      'share_id': 7,
      'target_id': 8,
      'share_identify': 'editing',
      'has_password': false,
      'doc_type': 'markdown',
      'title': 'Shared document',
      'content': '# Seed',
      'blog_type': ?type,
    });
Map<String, Object?> row([String? type]) => {
  'editable': true,
  'share_type': 'blog',
  'has_password': false,
  'doc_type': 'markdown',
  'title': 'Shared document',
  'content': '# Seed',
  'modify_time': 'opaque-version',
  'blog_type': ?type,
};
PublicEditSnapshot snapshot(String? type) =>
    PublicEditSnapshot.parse(context(type), row());

class _Repository implements PublicEditRepository {
  _Repository(this.current);
  PublicEditSnapshot current;
  int writes = 0;
  @override
  Future<PublicEditSnapshot> read(
    PublicEditLink link, {
    String? password,
    Future<void>? abortTrigger,
  }) async => current;
  @override
  Future<PublicEditReceipt> save(
    PublicEditLink link,
    PublicEditSnapshot baseline,
    String content, {
    String? password,
  }) async {
    writes++;
    return PublicEditReceipt(reference, 'next-version');
  }
}

void main() {
  test(
    'editing metadata preserves article note and absent legacy collection',
    () {
      for (final type in <String?>['article', 'note', null]) {
        expect(snapshot(type).detail.blogType, type);
      }
    },
  );
  test(
    'explicit editing metadata can classify a legacy response but cannot contradict a known collection',
    () {
      expect(
        PublicEditSnapshot.parse(context(null), row('article')).detail.blogType,
        'article',
      );
      expect(
        () => PublicEditSnapshot.parse(context('note'), row('article')),
        throwsStateError,
      );
      expect(
        () => PublicEditSnapshot.parse(context('article'), row('note')),
        throwsStateError,
      );
      expect(
        () => PublicEditSnapshot.parse(context(null), row('unexpected')),
        throwsStateError,
      );
    },
  );
  test(
    'same body and wall clock do not make different collections the same version',
    () {
      expect(snapshot('article').sameVersion(snapshot('note')), isFalse);
      expect(snapshot('article').sameVersion(snapshot(null)), isFalse);
    },
  );
  test('fresh collection change blocks saving before any shared PUT', () async {
    final repo = _Repository(snapshot('article'));
    final token = List.filled(64, 'e').join();
    final link = PublicEditLink.parse(
      reference.server,
      'https://example.test/base/shares/editing?token=$token',
    );
    final controller = PublicEditController(repo, link);
    await controller.initialize();
    repo.current = snapshot('note');
    await expectLater(controller.save('# Changed'), throwsStateError);
    expect(controller.phase, PublicEditPhase.blocked);
    expect(repo.writes, 0);
    controller.close();
  });
}
