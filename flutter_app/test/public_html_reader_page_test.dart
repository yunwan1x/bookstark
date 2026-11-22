import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/public_share_models.dart';
import 'package:bookstark_flutter/core/public_share_attachments.dart';
import 'package:bookstark_flutter/core/public_shares_repository.dart';
import 'package:bookstark_flutter/features/public_shares/share_reader_page.dart';

final reference = PublicShareReference(
  Uri.parse('https://example.test'),
  'html',
);
PublicShareDetail htmlDetail({bool locked = false}) {
  final value = PublicShareDetail.fromJson(reference, {
    'share_type': 'blog',
    'share_id': -9,
    'target_id': 9,
    'share_identify': 'html',
    'has_password': locked,
    'doc_type': 'html',
    'title': 'HTML public title',
    'content': 'protected payload must disappear',
    'description': 'protected description',
    'labels': ['protected label'],
    if (!locked) 'content_url': reference.rawPath,
  });
  return locked
      ? value
      : value.withHtmlContent(
          '<h1>Actual HTML heading</h1><script>never executed</script>',
        );
}

class HtmlRepository implements PublicSharesRepository {
  bool locked = false, fail = false, aborted = false;
  Completer<PublicShareDetail>? pendingLoad, pendingUnlock;
  final passwords = <String>[];
  @override
  Future<PublicShareDetail> load(
    PublicShareReference ref, {
    Future<void>? abortTrigger,
  }) async {
    if (fail) throw StateError('offline');
    return pendingLoad?.future ?? htmlDetail(locked: locked);
  }

  @override
  Future<PublicShareDetail> unlock(
    PublicShareDetail detail,
    String password, {
    Future<void>? abortTrigger,
  }) async {
    passwords.add(password);
    abortTrigger?.then((_) => aborted = true);
    if (pendingUnlock != null) return pendingUnlock!.future;
    if (password != ' secret ') throw StateError('must not echo $password');
    return detail.withHtmlContent(
      '<h1>Unlocked HTML heading</h1>',
      unlocking: true,
    );
  }

  @override
  Future<PublicShareChapter> chapter(
    PublicShareDetail book,
    String identify, {
    Future<void>? abortTrigger,
  }) async => throw UnimplementedError();
}

void main() {
  late PublicShareAttachments attachments;
  setUp(
    () => attachments = PublicShareAttachments(
      reference.server,
      publicTransport: MockClient(
        (_) async => throw StateError('Inert HTML must not fetch'),
      ),
    ),
  );
  tearDown(() => attachments.close());
  Future<void> mount(
    WidgetTester tester,
    HtmlRepository repo, {
    bool english = false,
    bool large = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(large ? 2 : 1),
            viewInsets: large
                ? const EdgeInsets.only(bottom: 200)
                : EdgeInsets.zero,
          ),
          child: child!,
        ),
        home: ShareReaderPage(
          reference: reference,
          repository: repo,
          attachments: attachments,
          english: english,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'HTML light reading renders content and refresh failure removes old body and metadata',
    (tester) async {
      final repo = HtmlRepository();
      await mount(tester, repo);
      expect(find.text('Actual HTML heading'), findsOneWidget);
      expect(find.textContaining('never executed'), findsNothing);
      repo.pendingLoad = Completer();
      await tester.tap(find.byTooltip('刷新'));
      await tester.pump();
      expect(find.text('Actual HTML heading'), findsNothing);
      expect(find.text('HTML public title'), findsNothing);
      repo.pendingLoad!.completeError(StateError('revoked'));
      await tester.pumpAndSettle();
      expect(find.text('分享暂不可用'), findsOneWidget);
      expect(find.text('Actual HTML heading'), findsNothing);
      expect(find.text('HTML public title'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'HTML password dialog keeps spaces, clears secrets and refresh relocks content',
    (tester) async {
      final repo = HtmlRepository()..locked = true;
      await mount(tester, repo);
      expect(find.textContaining('protected payload'), findsNothing);
      await tester.ensureVisible(find.widgetWithText(FilledButton, '解锁阅读'));
      await tester.tap(find.widgetWithText(FilledButton, '解锁阅读'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.enterText(find.byType(TextField), ' secret ');
      await tester.tap(find.widgetWithText(FilledButton, '解锁'));
      await tester.pumpAndSettle();
      expect(repo.passwords, [' secret ']);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Unlocked HTML heading'), findsOneWidget);
      expect(find.text('已解锁'), findsOneWidget);
      await tester.tap(find.byTooltip('刷新'));
      await tester.pumpAndSettle();
      expect(find.text('Unlocked HTML heading'), findsNothing);
      expect(find.widgetWithText(FilledButton, '解锁阅读'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'cancel in-flight HTML unlock aborts and late plaintext cannot appear',
    (tester) async {
      final repo = HtmlRepository()
        ..locked = true
        ..pendingUnlock = Completer();
      await mount(tester, repo);
      await tester.ensureVisible(find.widgetWithText(FilledButton, '解锁阅读'));
      await tester.tap(find.widgetWithText(FilledButton, '解锁阅读'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), ' secret ');
      await tester.tap(find.widgetWithText(FilledButton, '解锁'));
      await tester.pump();
      await tester.tap(find.widgetWithText(TextButton, '取消'));
      await tester.pumpAndSettle();
      expect(repo.aborted, isTrue);
      repo.pendingUnlock!.complete(
        htmlDetail(
          locked: true,
        ).withHtmlContent('<h1>Late plaintext</h1>', unlocking: true),
      );
      await tester.pumpAndSettle();
      expect(find.text('Late plaintext'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    '320dp English doubled-text HTML unlock handles keyboard and sanitized retry',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = HtmlRepository()..locked = true;
      await mount(tester, repo, english: true, large: true);
      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Unlock and read'),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Unlock and read'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'wrong-secret');
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Unlock'));
      await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
      await tester.pumpAndSettle();
      expect(find.textContaining('must not echo'), findsNothing);
      expect(find.textContaining('Unable to unlock.'), findsOneWidget);
      await tester.ensureVisible(find.widgetWithText(TextButton, 'Cancel'));
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
