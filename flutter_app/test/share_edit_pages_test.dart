import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/public_edit_link.dart';
import 'package:bookstark_flutter/core/public_edit_snapshot.dart';
import 'package:bookstark_flutter/core/public_edit_repository.dart';
import 'package:bookstark_flutter/core/public_edit_controller.dart';
import 'package:bookstark_flutter/core/public_share_models.dart';
import 'package:bookstark_flutter/core/public_share_attachments.dart';
import 'package:bookstark_flutter/core/public_shares_repository.dart';
import 'package:bookstark_flutter/features/public_shares/share_edit_page.dart';
import 'package:bookstark_flutter/features/public_shares/share_edit_link_page.dart';

final server = Uri.parse('https://example.test');
final url =
    'https://example.test/shares/s?token=${List.filled(64, 'd').join()}';
final link = PublicEditLink.parse(server, url);

class Repository implements PublicEditRepository {
  String content = '# Seed';
  String? blogType = 'note';
  bool protected = false, unknown = false;
  int writes = 0, reads = 0;
  final passwords = <String?>[];
  @override
  Future<PublicEditSnapshot> read(
    PublicEditLink link, {
    String? password,
    Future<void>? abortTrigger,
  }) async {
    reads++;
    passwords.add(password);
    var detail = PublicShareDetail.fromJson(link.reference, {
      'share_type': 'blog',
      'blog_type': ?blogType,
      'share_id': 8,
      'target_id': 3,
      'share_identify': 's',
      'has_password': protected,
      'title': 'Actual shared title',
      'doc_type': 'markdown',
      'content': content,
    });
    if (protected && password != null) {
      if (password != ' correct ') throw const ApiFailure(400, 'wrong');
      detail = detail.unlockMarkdown(content);
    }
    return PublicEditSnapshot.parse(detail, {
      'editable': true,
      'share_type': 'blog',
      'has_password': protected,
      'title': 'Actual shared title',
      'doc_type': 'markdown',
      'content': protected ? 'must not leak' : content,
      'modify_time': '2026-11-05 12:00:00',
    });
  }

  @override
  Future<PublicEditReceipt> save(
    PublicEditLink link,
    PublicEditSnapshot baseline,
    String value, {
    String? password,
  }) async {
    writes++;
    passwords.add(password);
    if (unknown) throw StateError('lost receipt');
    if (protected && password != ' correct ') {
      throw const ApiFailure(403, 'wrong password');
    }
    content = value;
    return PublicEditReceipt(link.reference, '2026-11-05 12:00:00');
  }
}

class UnusedShares implements PublicSharesRepository {
  @override
  Future<PublicShareDetail> load(
    PublicShareReference reference, {
    Future<void>? abortTrigger,
  }) async => throw UnimplementedError();
  @override
  Future<PublicShareDetail> unlock(
    PublicShareDetail value,
    String password, {
    Future<void>? abortTrigger,
  }) async => throw UnimplementedError();
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
      server,
      publicTransport: MockClient((_) async => http.Response('', 404)),
    ),
  );
  tearDown(() => attachments.close());
  Future<PublicEditController> editor(
    WidgetTester tester,
    Repository repo, {
    bool small = false,
  }) async {
    final controller = PublicEditController(repo, link);
    await controller.initialize();
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
        home: ShareEditPage(
          controller: controller,
          attachments: attachments,
          english: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  Finder getInput() => find.byKey(const ValueKey('shared-markdown-input'));
  testWidgets(
    'link formatting replaces selected text and multi-line list formatting preserves both lines',
    (tester) async {
      final repo = Repository()..content = 'word';
      await editor(tester, repo);
      final text = (tester.widget<TextField>(getInput())).controller!;
      text.selection = const TextSelection(baseOffset: 0, extentOffset: 4);
      await tester.ensureVisible(find.byTooltip('Insert link'));
      await tester.tap(find.byTooltip('Insert link'));
      await tester.pumpAndSettle();
      final fields = find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(TextField),
      );
      expect((tester.widget<TextField>(fields.first)).controller!.text, 'word');
      await tester.enterText(fields.last, 'https://example.test/path');
      await tester.tap(find.widgetWithText(FilledButton, 'Insert'));
      await tester.pumpAndSettle();
      expect(text.text, '[word](<https://example.test/path>)');
      await tester.enterText(getInput(), 'first\nsecond');
      text.selection = const TextSelection(baseOffset: 0, extentOffset: 12);
      await tester.ensureVisible(find.byTooltip('List'));
      await tester.tap(find.byTooltip('List'));
      await tester.pumpAndSettle();
      expect(text.text, '- first\n- second');
      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pumpAndSettle();
      expect(repo.content, '- first\n- second');
      expect(repo.writes, 1);
      await tester.ensureVisible(find.widgetWithText(TextButton, 'Preview'));
      await tester.tap(find.widgetWithText(TextButton, 'Preview'));
      await tester.pumpAndSettle();
      expect(find.text('first', findRichText: true), findsWidgets);
      expect(find.text('second', findRichText: true), findsWidgets);
      expect(getInput(), findsNothing);
    },
  );
  testWidgets(
    'external edit opens conflict; cancel preserves local and explicit observed overwrite saves once',
    (tester) async {
      final repo = Repository();
      final controller = await editor(tester, repo);
      await tester.enterText(getInput(), '# Local');
      repo.content = '# Other';
      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pumpAndSettle();
      expect(find.text('Remote content has changed'), findsOneWidget);
      expect(repo.writes, 0);
      await tester.tapAt(const Offset(4, 100));
      await tester.pumpAndSettle();
      expect(
        (tester.widget<TextField>(getInput())).controller!.text,
        '# Local',
      );
      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Confirm overwrite'),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Confirm overwrite'));
      await tester.pumpAndSettle();
      expect(repo.content, '# Local');
      expect(repo.writes, 1);
      expect(controller.phase, PublicEditPhase.acknowledged);
    },
  );
  testWidgets(
    'unknown save disables another PUT and verification only reads the remote',
    (tester) async {
      final repo = Repository()..unknown = true;
      final controller = await editor(tester, repo);
      await tester.enterText(getInput(), '# Pending');
      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pumpAndSettle();
      expect(controller.phase, PublicEditPhase.unknown);
      expect(repo.writes, 1);
      expect(
        (tester.widget<TextButton>(
          find.widgetWithText(TextButton, 'Save'),
        )).onPressed,
        isNull,
      );
      await tester.ensureVisible(find.text('Reload to verify'));
      await tester.tap(find.text('Reload to verify'));
      await tester.pumpAndSettle();
      expect(controller.remoteStillBaseline, isTrue);
      expect(repo.writes, 1);
      expect(find.text('Save again after verification'), findsOneWidget);
    },
  );
  testWidgets(
    'entry rejects foreign origin before any read and protected edit keeps password only for its real session',
    (tester) async {
      final repo = Repository()..protected = true;
      await tester.pumpWidget(
        MaterialApp(
          home: ShareEditLinkPage(
            server: server,
            repository: repo,
            shares: UnusedShares(),
            attachments: attachments,
            english: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField),
        url.replaceFirst('example.test', 'foreign.test'),
      );
      await tester.ensureVisible(find.text('Verify and open'));
      await tester.tap(find.text('Verify and open'));
      await tester.pumpAndSettle();
      expect(repo.reads, 0);
      await tester.enterText(find.byType(TextFormField), url);
      await tester.ensureVisible(find.text('Verify and open'));
      await tester.tap(find.text('Verify and open'));
      await tester.pumpAndSettle();
      expect(find.text('Verify share password'), findsOneWidget);
      expect(find.text('must not leak'), findsNothing);
      expect(find.text('Reading remains read-only'), findsNothing);
      await tester.enterText(find.byType(TextFormField).last, ' correct ');
      await tester.ensureVisible(find.text('Verify and edit'));
      await tester.tap(find.text('Verify and edit'));
      await tester.pumpAndSettle();
      expect(find.byType(ShareEditPage), findsOneWidget);
      await tester.enterText(getInput(), '# Protected edit');
      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pumpAndSettle();
      expect(repo.content, '# Protected edit');
      expect(repo.writes, 1);
      expect(repo.passwords.last, ' correct ');
    },
  );
  testWidgets(
    'leaving unsaved edits needs explicit discard and never saves automatically',
    (tester) async {
      final repo = Repository();
      await editor(tester, repo);
      await tester.enterText(getInput(), '# Unsaved');
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Leave shared editing?'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(
        (tester.widget<TextField>(getInput())).controller!.text,
        '# Unsaved',
      );
      expect(repo.writes, 0);
    },
  );
  testWidgets(
    '320dp English 200 percent keyboard layout and conflict actions scroll without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = Repository();
      await editor(tester, repo, small: true);
      await tester.enterText(getInput(), '# Local');
      repo.content = '# Current remote';
      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pumpAndSettle();
      expect(find.text('Remote content has changed'), findsOneWidget);
      await tester.ensureVisible(
        find.widgetWithText(OutlinedButton, 'Load remote'),
      );
      await tester.tap(find.widgetWithText(OutlinedButton, 'Load remote'));
      await tester.pumpAndSettle();
      expect(
        (tester.widget<TextField>(getInput())).controller!.text,
        '# Current remote',
      );
      expect(repo.writes, 0);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'protected edit return action closes the password and link routes without a write',
    (tester) async {
      final repo = Repository()..protected = true;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ShareEditLinkPage(
                      server: server,
                      repository: repo,
                      shares: UnusedShares(),
                      attachments: attachments,
                      english: true,
                    ),
                  ),
                ),
                child: const Text('Actual public reader'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Actual public reader'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), url);
      await tester.ensureVisible(find.text('Verify and open'));
      await tester.tap(find.text('Verify and open'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Return to reading'));
      await tester.tap(find.text('Return to reading'));
      await tester.pumpAndSettle();
      expect(find.text('Actual public reader'), findsOneWidget);
      expect(find.byType(ShareEditLinkPage), findsNothing);
      expect(repo.writes, 0);
    },
  );
}
