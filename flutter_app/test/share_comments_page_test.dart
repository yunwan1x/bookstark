import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/public_share_models.dart';
import 'package:bookstark_flutter/core/share_comment_models.dart';
import 'package:bookstark_flutter/core/share_comments_repository.dart';
import 'package:bookstark_flutter/features/public_shares/share_comments_page.dart';

final detail = PublicShareDetail.fromJson(
  PublicShareReference(Uri.parse('https://example.test'), 'share'),
  {
    'share_type': 'blog',
    'share_id': -9,
    'target_id': 9,
    'share_identify': 'share',
    'has_password': false,
    'title': 'Actual shared title',
    'doc_type': 'markdown',
    'content': 'Body',
  },
);
Map<String, Object?> row(int id, {bool canDelete = false}) => {
  'comment_id': id,
  'parent_comment_id': 0,
  'root_comment_id': id,
  'reply_to_comment_id': 0,
  'target_type': 'blog',
  'target_id': 9,
  'share_identify': 'share',
  'author_name': 'Actual author',
  'reply_to_author_name': '',
  'content': 'Actual public comment $id',
  'create_time': '2026-11-05T08:00:00Z',
  'can_delete': canDelete,
  'is_deleted': false,
};

class Repository implements ShareCommentsRepository {
  bool unknownCapability = false, enabled = true;
  Completer<PublicShareComment>? pending;
  int creates = 0, deletes = 0;
  final rows = <Map<String, Object?>>[row(1, canDelete: true), row(2)];
  @override
  Future<ShareCommentCapabilities> capabilities(
    PublicShareDetail context, {
    Future<void>? abortTrigger,
  }) async {
    if (unknownCapability) throw StateError('offline');
    return ShareCommentCapabilities(
      enabled: enabled,
      maxLength: 100,
      account: 'Actual account',
    );
  }

  @override
  Future<PublicShareCommentPage> list(
    PublicShareDetail context,
    int page, {
    Future<void>? abortTrigger,
  }) async => PublicShareCommentPage.parse(
    {
      'page': page,
      'page_size': 20,
      'total': rows.length,
      'data': enabled ? rows : [],
    },
    context,
    requestedPage: page,
  );
  @override
  Future<PublicShareComment> create(
    PublicShareDetail context,
    ShareCommentCapabilities cap,
    PublicCommentInput input,
  ) async {
    creates++;
    if (pending != null) return pending!.future;
    final value = row(3, canDelete: true)..['content'] = input.content;
    rows.insert(0, value);
    return PublicShareComment.parse(value, context);
  }

  @override
  Future<void> remove(
    PublicShareDetail context,
    PublicShareComment comment,
  ) async {
    deletes++;
    rows.removeWhere((row) => row['comment_id'] == comment.id);
  }
}

Future<void> mount(
  WidgetTester tester,
  Repository repo, {
  bool english = true,
  bool small = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      builder: small
          ? (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(2),
                viewInsets: const EdgeInsets.only(bottom: 160),
              ),
              child: child!,
            )
          : null,
      home: ShareCommentsPage(
        detail: detail,
        repository: repo,
        english: english,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'capability failure remains unknown rather than disabled; retry enables actual composer',
    (tester) async {
      final repo = Repository()..unknownCapability = true;
      await mount(tester, repo);
      expect(find.text('Actual public comment 1'), findsOneWidget);
      final semantics = tester.ensureSemantics();
      expect(
        tester.getSemantics(find.text('Actual public comment 1')).label,
        contains('Actual public comment 1'),
      );
      semantics.dispose();
      expect(find.text('Comments are disabled.'), findsNothing);
      expect(find.text('Write comment'), findsNothing);
      await tester.ensureVisible(find.text('Retry comment settings'));
      repo.unknownCapability = false;
      await tester.tap(find.text('Retry comment settings'));
      await tester.pumpAndSettle();
      expect(find.text('Write comment'), findsOneWidget);
    },
  );
  testWidgets(
    'unknown publication cannot repeat after returning to list and reopening form',
    (tester) async {
      final repo = Repository()..pending = Completer();
      await mount(tester, repo);
      await tester.tap(find.text('Write comment'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).last,
        'Unique pending body',
      );
      await tester.tap(find.text('Publish comment'));
      await tester.pump();
      expect(repo.creates, 1);
      expect(find.text('Publishing…'), findsOneWidget);
      repo.pending!.completeError(StateError('connection lost'));
      await tester.pumpAndSettle();
      expect(find.text('Publish comment'), findsNothing);
      await tester.tap(find.text('Review comments'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Review pending comment'));
      await tester.pumpAndSettle();
      expect(find.text('Unique pending body'), findsOneWidget);
      expect(find.text('Publish comment'), findsNothing);
      expect(repo.creates, 1);
      await tester.ensureVisible(find.text('Discard pending record'));
      await tester.tap(find.text('Discard pending record'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard record'));
      await tester.pumpAndSettle();
      expect(find.text('Write comment'), findsOneWidget);
      expect(repo.creates, 1);
    },
  );
  testWidgets(
    'successful create has one receipt and deleting requires actual permission plus confirmation',
    (tester) async {
      final repo = Repository();
      await mount(tester, repo);
      expect(find.byTooltip('Delete'), findsOneWidget);
      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(repo.deletes, 0);
      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(repo.deletes, 1);
      expect(find.text('Actual public comment 1'), findsNothing);
      expect(find.byTooltip('Delete'), findsNothing);
      await tester.tap(find.text('Write comment'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).last,
        'New actual comment',
      );
      await tester.tap(find.text('Publish comment'));
      await tester.pumpAndSettle();
      expect(repo.creates, 1);
      expect(find.text('New actual comment'), findsOneWidget);
      await tester.tap(find.text('Write comment'));
      await tester.pumpAndSettle();
      expect(find.text('Previous comment published'), findsOneWidget);
      expect(find.text('Actual comment ID: 3'), findsOneWidget);
      expect(repo.creates, 1);
    },
  );
  testWidgets(
    '320dp English 200 percent form scrolls with keyboard and cancels without a write',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = Repository();
      await mount(tester, repo, small: true);
      await tester.tap(find.text('Write comment'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(TextFormField).last);
      await tester.enterText(
        find.byType(TextFormField).last,
        '📚 Real comment',
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(repo.creates, 0);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'pending comment remains reviewable after the server disables comments',
    (tester) async {
      final repo = Repository()..pending = Completer();
      await mount(tester, repo);
      await tester.tap(find.text('Write comment'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).last,
        'Pending before disabled',
      );
      await tester.tap(find.text('Publish comment'));
      await tester.pump();
      repo.pending!.completeError(StateError('offline'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Review comments'));
      await tester.pumpAndSettle();
      repo.enabled = false;
      await tester.tap(find.byTooltip('Reload'));
      await tester.pumpAndSettle();
      expect(find.text('Comments are disabled.'), findsOneWidget);
      await tester.ensureVisible(find.text('Review pending comment'));
      await tester.tap(find.text('Review pending comment'));
      await tester.pumpAndSettle();
      expect(find.text('Pending before disabled'), findsOneWidget);
      expect(find.text('Publish comment'), findsNothing);
      expect(repo.creates, 1);
    },
  );
}
