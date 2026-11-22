import 'dart:async';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/features/admin/admin_community_controller.dart';
import 'package:bookstark_flutter/features/admin/admin_community_repository.dart';
import 'package:bookstark_flutter/features/admin/admin_friend_links_models.dart';
import 'package:bookstark_flutter/features/admin/admin_comment_models.dart';
import 'package:bookstark_flutter/features/admin/admin_settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'admin_community_repository_test.dart' as fixture;

const owner = AdminPrincipal(memberId: 1, account: 'fixture-owner', role: 0);
BookstarkClient ownedClient() =>
    BookstarkClient(
      'https://example.invalid',
      transport: MockClient(
        (_) async => throw StateError('Controller fixture cannot make HTTP'),
      ),
    )..restoreSession({
      'token': 'owned-controller-session',
      'csrf_token': 'owned-controller-csrf',
    });
AdminFriendLinksSnapshot linksData() => AdminFriendLinksSnapshot(
  items: [AdminFriendLink.parse(fixture.link())],
  simpleMode: false,
);
AdminCommentPage commentData({
  int page = 1,
  int total = 2,
  int pages = 1,
  List<int> ids = const [2, 1],
}) => AdminCommentPage(
  items: [for (final id in ids) AdminCommentRecord.parse(fixture.comment(id))],
  page: page,
  total: total,
  totalPages: pages,
);

class LinksRepository extends AdminFriendLinksRepository {
  LinksRepository() : super(ownedClient());
  AdminFriendLinksSnapshot data = linksData();
  int reads = 0, writes = 0;
  Object? preflightError, writeError, afterWriteReadError;
  bool apply = true;
  Completer<AdminFriendLinksSnapshot>? readGate;
  Completer<void>? writeGate;
  @override
  Future<AdminFriendLinksSnapshot> read(
    AdminPrincipal owner, {
    Future<void>? abortTrigger,
  }) async {
    reads++;
    if (readGate != null) return readGate!.future;
    if (writes > 0 && afterWriteReadError != null) {
      final error = afterWriteReadError!;
      afterWriteReadError = null;
      throw error;
    }
    return data;
  }

  @override
  Future<AdminFriendLinksReceipt> replace(
    AdminPrincipal owner,
    AdminFriendLinksSnapshot reviewed,
    AdminFriendLinksSnapshot draft, {
    Future<void>? abortTrigger,
    void Function()? onSubmitted,
  }) async {
    if (preflightError != null) throw preflightError!;
    writes++;
    onSubmitted?.call();
    if (writeGate != null) await writeGate!.future;
    if (apply) data = draft;
    if (writeError != null) throw writeError!;
    return const AdminFriendLinksReceipt();
  }

  @override
  void dispose() {
    super.dispose();
    client.close();
  }
}

class CommentsRepository extends AdminCommentsRepository {
  CommentsRepository() : super(ownedClient());
  AdminCommentPage data = commentData();
  int reads = 0, writes = 0, affected = 3;
  Object? preflightError, writeError, afterWriteReadError;
  Future<AdminCommentPage> Function(AdminCommentFilter, int)? readHandler;
  Completer<void>? writeGate;
  @override
  Future<AdminCommentPage> read(
    AdminPrincipal owner,
    AdminCommentFilter filter,
    int page, {
    Future<void>? abortTrigger,
  }) async {
    reads++;
    if (readHandler != null) return readHandler!(filter, page);
    if (writes > 0 && afterWriteReadError != null) {
      final error = afterWriteReadError!;
      afterWriteReadError = null;
      throw error;
    }
    return data;
  }

  @override
  Future<AdminCommentDeleteReceipt> delete(
    AdminPrincipal owner,
    List<AdminCommentRecord> targets, {
    Future<void>? abortTrigger,
    void Function()? onSubmitted,
  }) async {
    if (preflightError != null) throw preflightError!;
    writes++;
    onSubmitted?.call();
    if (writeGate != null) await writeGate!.future;
    if (writeError != null) throw writeError!;
    return AdminCommentDeleteReceipt(affected);
  }

  @override
  void dispose() {
    super.dispose();
    client.close();
  }
}

void main() {
  test(
    'friend editor apply and removal remain local until explicit full save',
    () async {
      final repo = LinksRepository();
      final controller = AdminFriendLinksController(repo, owner);
      addTearDown(controller.dispose);
      await controller.load();
      final originalKey = controller.rows.single.key;
      expect(
        controller.applyRow(
          originalKey,
          controller.rows.single.link.edit(name: 'changed'),
          expectedRevision: controller.revision,
        ),
        isTrue,
      );
      expect(controller.dirty, isTrue);
      expect(repo.writes, 0);
      expect(await controller.load(), isFalse);
      expect(repo.reads, 1);
      final before = controller.revision;
      expect(
        controller.removeRow(originalKey, expectedRevision: before),
        isTrue,
      );
      expect(controller.rows, isEmpty);
      expect(repo.writes, 0);
      await controller.submit(expectedRevision: controller.revision);
      expect(repo.writes, 1);
      expect(repo.data.items, isEmpty);
      expect(controller.notice, AdminCommunityNotice.knownLinksRead);
      expect(controller.dirty, isFalse);
    },
  );
  test(
    'new friend rows use stable local keys and old editor revision cannot apply',
    () async {
      final repo = LinksRepository();
      final controller = AdminFriendLinksController(repo, owner);
      addTearDown(controller.dispose);
      await controller.load();
      final key = controller.rows.single.key, revision = controller.revision;
      controller.setSimpleMode(true);
      expect(
        controller.applyRow(
          key,
          controller.rows.single.link.edit(name: 'stale'),
          expectedRevision: revision,
        ),
        isFalse,
      );
      await controller.load(discardDraft: true);
      expect(controller.rows.single.key, greaterThan(key));
      expect(
        controller.removeRow(key, expectedRevision: controller.revision),
        isFalse,
      );
      expect(repo.writes, 0);
    },
  );
  test('friend known acknowledgement read failure retries GET only', () async {
    final repo = LinksRepository()
      ..afterWriteReadError = const ApiFailure(503, 'fixture');
    final c = AdminFriendLinksController(repo, owner);
    addTearDown(c.dispose);
    await c.load();
    c.setSimpleMode(true);
    await c.submit(expectedRevision: c.revision);
    expect(c.phase, AdminCommunityPhase.knownNeedsRead);
    expect(repo.writes, 1);
    expect(c.pendingKind, AdminCommunityPendingKind.known);
    await c.readCurrent();
    expect(c.ready, isTrue);
    expect(c.notice, AdminCommunityNotice.knownLinksRead);
    expect(repo.writes, 1);
  });
  test(
    'friend dropped reply does not infer success from identical fresh configuration',
    () async {
      final repo = LinksRepository()
        ..writeError = const AdminCommunityWriteUnknown();
      final c = AdminFriendLinksController(repo, owner);
      addTearDown(c.dispose);
      await c.load();
      c.setSimpleMode(true);
      await c.submit(expectedRevision: c.revision);
      expect(c.phase, AdminCommunityPhase.unknown);
      expect(repo.reads, 1);
      expect(await c.load(discardDraft: true), isFalse);
      expect(c.acknowledgeCurrent(), isFalse);
      await c.readCurrent();
      expect(c.phase, AdminCommunityPhase.reviewing);
      expect(c.notice, AdminCommunityNotice.unknownCurrent);
      expect(c.currentReview!.semanticKey, c.pendingDraft!.semanticKey);
      await c.submit(expectedRevision: c.revision);
      expect(repo.writes, 1);
      expect(c.acknowledgeCurrent(), isTrue);
      expect(c.notice, AdminCommunityNotice.reviewEnded);
      expect(c.ready, isTrue);
      expect(repo.writes, 1);
    },
  );
  test(
    'friend concurrent change preserves local draft until explicit current adoption',
    () async {
      final repo = LinksRepository()
        ..preflightError = const AdminCommunityTargetChanged();
      final c = AdminFriendLinksController(repo, owner);
      addTearDown(c.dispose);
      await c.load();
      c.setSimpleMode(true);
      await c.submit(expectedRevision: c.revision);
      expect(repo.writes, 0);
      expect(c.pendingKind, AdminCommunityPendingKind.notSubmitted);
      expect(c.dirty, isTrue);
      await c.readCurrent();
      expect(c.notice, AdminCommunityNotice.changedCurrent);
      expect(c.currentReview!.simpleMode, isFalse);
      expect(c.simpleMode, isTrue);
      c.acknowledgeCurrent();
      expect(c.simpleMode, isFalse);
      expect(c.dirty, isFalse);
      expect(c.notice, AdminCommunityNotice.staleDraftDiscarded);
      expect(repo.writes, 0);
    },
  );
  test(
    'friend actual readback difference is reported without fabricated saved match',
    () async {
      final repo = LinksRepository()..apply = false;
      final c = AdminFriendLinksController(repo, owner);
      addTearDown(c.dispose);
      await c.load();
      c.setSimpleMode(true);
      await c.submit(expectedRevision: c.revision);
      expect(c.notice, AdminCommunityNotice.knownLinksDifferent);
      expect(c.simpleMode, isFalse);
      expect(repo.writes, 1);
    },
  );
  test(
    'friend submitted singleflight blocks concurrent saves and local edits',
    () async {
      final repo = LinksRepository()..writeGate = Completer<void>();
      final c = AdminFriendLinksController(repo, owner);
      addTearDown(c.dispose);
      await c.load();
      c.setSimpleMode(true);
      final pending = c.submit(expectedRevision: c.revision);
      expect(c.busy, isTrue);
      expect(c.setSimpleMode(false), isFalse);
      await c.submit(expectedRevision: c.revision);
      expect(repo.writes, 1);
      repo.writeGate!.complete();
      await pending;
      expect(c.ready, isTrue);
    },
  );
  test(
    'friend permission loss during known readback clears all owned drafts',
    () async {
      final repo = LinksRepository()
        ..afterWriteReadError = const ApiFailure(401, 'fixture');
      final c = AdminFriendLinksController(repo, owner);
      addTearDown(c.dispose);
      await c.load();
      c.setSimpleMode(true);
      await c.submit(expectedRevision: c.revision);
      expect(c.phase, AdminCommunityPhase.permissionLost);
      expect(c.notice, AdminCommunityNotice.knownWriteOwnerLost);
      expect(c.rows, isEmpty);
      expect(c.baseline, isNull);
      expect(c.pendingDraft, isNull);
    },
  );
  test(
    'friend disposal rejects late read and leaves no recovered draft',
    () async {
      final repo = LinksRepository()
        ..readGate = Completer<AdminFriendLinksSnapshot>();
      final c = AdminFriendLinksController(repo, owner);
      final pending = c.load();
      c.dispose();
      repo.readGate!.complete(linksData());
      await pending;
      expect(c.rows, isEmpty);
      expect(c.baseline, isNull);
      expect(c.currentReview, isNull);
    },
  );
  test('comment filter/page changes retire all selected identities', () async {
    final repo = CommentsRepository();
    final controller = AdminCommentsController(repo, owner);
    addTearDown(controller.dispose);
    await controller.load();
    expect(controller.reviewedSelection(), isEmpty);
    controller.select(2, true);
    expect(controller.selected, {2});
    expect(controller.select(99, true), isFalse);
    await controller.load(
      filter: const AdminCommentFilter(keyword: 'new filter'),
    );
    expect(controller.selected, isEmpty);
    expect(controller.filter.keyword, 'new filter');
    expect(repo.writes, 0);
  });
  for (final count in [0, 3]) {
    test(
      'comment known delete uses real count $count and clears selection',
      () async {
        final repo = CommentsRepository()..affected = count;
        final c = AdminCommentsController(repo, owner);
        addTearDown(c.dispose);
        await c.load();
        c.select(2, true);
        final targets = c.reviewedSelection();
        await c.submitDelete(expectedRevision: c.revision, targets: targets);
        expect(c.actualDeleted, count);
        expect(c.selected, isEmpty);
        expect(c.ready, isTrue);
        expect(repo.writes, 1);
        expect(
          c.notice,
          count == 0
              ? AdminCommunityNotice.knownDeleteZero
              : AdminCommunityNotice.knownDeletedRead,
        );
      },
    );
  }
  test(
    'comment known delete readback retry never sends another POST',
    () async {
      final repo = CommentsRepository()
        ..afterWriteReadError = const ApiFailure(503, 'fixture');
      final c = AdminCommentsController(repo, owner);
      addTearDown(c.dispose);
      await c.load();
      c.select(2, true);
      await c.submitDelete(
        expectedRevision: c.revision,
        targets: c.reviewedSelection(),
      );
      expect(c.phase, AdminCommunityPhase.knownNeedsRead);
      expect(c.actualDeleted, 3);
      await c.readCurrent();
      expect(c.ready, isTrue);
      expect(c.actualDeleted, 3);
      expect(repo.writes, 1);
    },
  );
  test(
    'comment unknown delete requires explicit GET and adoption without old selection',
    () async {
      final repo = CommentsRepository()
        ..writeError = const AdminCommunityWriteUnknown();
      final c = AdminCommentsController(repo, owner);
      addTearDown(c.dispose);
      await c.load();
      c.select(2, true);
      final targets = c.reviewedSelection();
      await c.submitDelete(expectedRevision: c.revision, targets: targets);
      expect(c.phase, AdminCommunityPhase.unknown);
      expect(c.actualDeleted, isNull);
      expect(repo.reads, 1);
      expect(await c.load(), isFalse);
      expect(c.select(1, true), isFalse);
      await c.readCurrent();
      expect(c.phase, AdminCommunityPhase.reviewing);
      expect(c.notice, AdminCommunityNotice.unknownCurrent);
      await c.submitDelete(expectedRevision: c.revision, targets: targets);
      expect(repo.writes, 1);
      c.acknowledgeCurrent();
      expect(c.ready, isTrue);
      expect(c.selected, isEmpty);
      expect(c.actualDeleted, isNull);
      expect(repo.writes, 1);
    },
  );
  test(
    'comment confirmation version and exact selection prevent changed-target submit',
    () async {
      final repo = CommentsRepository();
      final controller = AdminCommentsController(repo, owner);
      addTearDown(controller.dispose);
      await controller.load();
      controller.select(2, true);
      final revision = controller.revision,
          targets = controller.reviewedSelection();
      controller.select(1, true);
      await controller.submitDelete(
        expectedRevision: revision,
        targets: targets,
      );
      await controller.submitDelete(
        expectedRevision: controller.revision,
        targets: targets,
      );
      expect(repo.writes, 0);
    },
  );
  test(
    'comment preflight changed target clears selection and requires a fresh read',
    () async {
      final repo = CommentsRepository()
        ..preflightError = const AdminCommunityTargetChanged();
      final c = AdminCommentsController(repo, owner);
      addTearDown(c.dispose);
      await c.load();
      c.select(2, true);
      await c.submitDelete(
        expectedRevision: c.revision,
        targets: c.reviewedSelection(),
      );
      expect(c.phase, AdminCommunityPhase.needsReload);
      expect(c.selected, isEmpty);
      expect(repo.writes, 0);
      expect(c.notice, AdminCommunityNotice.changedBeforeWrite);
      await c.load();
      expect(c.ready, isTrue);
      expect(c.selected, isEmpty);
    },
  );
  test(
    'comment page shrink explicitly clamps to valid page without a delete',
    () async {
      final requested = <int>[];
      final repo = CommentsRepository()
        ..readHandler = (filter, page) async {
          requested.add(page);
          return page == 2
              ? commentData(page: 2, total: 1, pages: 1, ids: [])
              : commentData(total: 1, ids: [1]);
        };
      final c = AdminCommentsController(repo, owner);
      addTearDown(c.dispose);
      await c.load(page: 2);
      expect(requested, [2, 1]);
      expect(c.page!.page, 1);
      expect(c.pageAdjusted, isTrue);
      expect(repo.writes, 0);
    },
  );
  test(
    'comment permission loss clears content, filters, targets and selection',
    () async {
      final repo = CommentsRepository()
        ..preflightError = AdminCommunityOwnerLost();
      final c = AdminCommentsController(repo, owner);
      addTearDown(c.dispose);
      await c.load(filter: const AdminCommentFilter(keyword: 'private query'));
      c.select(2, true);
      await c.submitDelete(
        expectedRevision: c.revision,
        targets: c.reviewedSelection(),
      );
      expect(c.phase, AdminCommunityPhase.permissionLost);
      expect(c.page, isNull);
      expect(c.pendingTargets, isEmpty);
      expect(c.selected, isEmpty);
      expect(c.filter.keyword, isEmpty);
    },
  );
  test(
    'comment late beyond-page read cannot set flags or restore content after disposal',
    () async {
      final gate = Completer<AdminCommentPage>();
      final repo = CommentsRepository()
        ..readHandler = (filter, page) => gate.future;
      final c = AdminCommentsController(repo, owner);
      final pending = c.load(page: 2);
      c.dispose();
      gate.complete(commentData(page: 2, total: 1, pages: 1, ids: []));
      await pending;
      expect(c.page, isNull);
      expect(c.pageAdjusted, isFalse);
      expect(repo.reads, 1);
    },
  );
}
