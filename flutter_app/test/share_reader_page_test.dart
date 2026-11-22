import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/public_share_models.dart';
import 'package:bookstark_flutter/core/public_share_attachments.dart';
import 'package:bookstark_flutter/core/public_shares_repository.dart';
import 'package:bookstark_flutter/features/public_shares/share_reader_page.dart';

final server = Uri.parse('https://example.test');
PublicShareReference ref(String id) => PublicShareReference(server, id);
PublicShareDetail detail(String id, {bool locked = false}) =>
    PublicShareDetail.fromJson(ref(id), {
      'share_type': 'blog',
      'share_id': -3,
      'target_id': 3,
      'share_identify': id,
      'has_password': locked,
      'doc_type': 'markdown',
      'blog_type': 'note',
      'title': 'Actual public title',
      'content': '# Native heading\n\n**Actual body**',
      'labels': ['hidden protected label'],
    });

class Repository implements PublicSharesRepository {
  bool fail = false;
  final requests = <String, Completer<PublicShareDetail>>{};
  final passwords = <String>[];
  @override
  Future<PublicShareDetail> load(
    PublicShareReference reference, {
    Future<void>? abortTrigger,
  }) async {
    if (fail) throw StateError('offline');
    return requests[reference.identify]?.future ??
        detail(reference.identify, locked: reference.identify == 'locked');
  }

  @override
  Future<PublicShareDetail> unlock(
    PublicShareDetail value,
    String password, {
    Future<void>? abortTrigger,
  }) async {
    passwords.add(password);
    if (password != ' correct ') {
      throw StateError('server echoed secret: $password');
    }
    return value.unlockMarkdown('# Unlocked native body');
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
      server,
      publicTransport: MockClient((_) async => http.Response('', 404)),
    ),
  );
  tearDown(() => attachments.close());
  Future<void> mount(
    WidgetTester tester,
    Repository repository,
    String id, {
    bool english = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(english ? 'en' : 'zh'),
        supportedLocales: const [Locale('zh'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: ShareReaderPage(
          reference: ref(id),
          repository: repository,
          attachments: attachments,
          english: english,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'locked content never enters UI; failed unlock masks secrets and successful unlock is ephemeral',
    (tester) async {
      final repo = Repository();
      await mount(tester, repo, 'locked');
      expect(find.text('Native heading'), findsNothing);
      expect(find.textContaining('hidden protected label'), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, '解锁阅读'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'bad-secret');
      await tester.ensureVisible(find.widgetWithText(FilledButton, '解锁阅读'));
      await tester.tap(find.widgetWithText(FilledButton, '解锁阅读'));
      await tester.pumpAndSettle();
      expect(find.textContaining('server echoed'), findsNothing);
      expect(find.text('无法解锁，请核对密码和网络后重试。'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), ' correct ');
      await tester.ensureVisible(find.widgetWithText(FilledButton, '解锁阅读'));
      await tester.tap(find.widgetWithText(FilledButton, '解锁阅读'));
      await tester.pumpAndSettle();
      expect(find.text('Unlocked native body'), findsOneWidget);
      expect(repo.passwords, ['bad-secret', ' correct ']);
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('重新加载'));
      await tester.pumpAndSettle();
      expect(find.text('Unlocked native body'), findsNothing);
      expect(find.widgetWithText(FilledButton, '解锁阅读'), findsOneWidget);
    },
  );
  testWidgets('late public responses cannot replace the current reference', (
    tester,
  ) async {
    final repo = Repository();
    repo.requests['old'] = Completer();
    Widget app(String id) => MaterialApp(
      home: ShareReaderPage(
        reference: ref(id),
        repository: repo,
        attachments: attachments,
      ),
    );
    await tester.pumpWidget(app('old'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpWidget(app('new'));
    await tester.pumpAndSettle();
    expect(find.text('Native heading'), findsOneWidget);
    repo.requests['old']!.complete(detail('old', locked: true));
    await tester.pumpAndSettle();
    expect(find.text('Native heading'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '解锁阅读'), findsNothing);
  });
  testWidgets(
    'failed load retries and canonical copied link has no credentials or tokens',
    (tester) async {
      final repo = Repository()..fail = true;
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await mount(tester, repo, '真实%2F+');
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(find.text('Native heading'), findsNothing);
      repo.fail = false;
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(find.text('Native heading'), findsOneWidget);
      await tester.tap(find.text('复制链接'));
      await tester.pumpAndSettle();
      expect(Uri.parse(copied!).pathSegments, ['shares', '真实%2F+']);
      expect(Uri.parse(copied!).hasQuery, isFalse);
    },
  );
  testWidgets(
    'English 320dp 200 percent unlock scrolls with keyboard and no overflow',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = Repository();
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
              viewInsets: const EdgeInsets.only(bottom: 180),
            ),
            child: child!,
          ),
          home: ShareReaderPage(
            reference: ref('locked'),
            repository: repo,
            attachments: attachments,
            english: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Unlock and read'),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Unlock and read'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(TextFormField));
      await tester.enterText(find.byType(TextFormField), ' correct ');
      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Unlock and read'),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Unlock and read'));
      await tester.pumpAndSettle();
      expect(find.text('Unlocked native body'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('return to feed leaves both unlock and locked reader routes', (
    tester,
  ) async {
    final repo = Repository();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => ShareReaderPage(
                    reference: ref('locked'),
                    repository: repo,
                    attachments: attachments,
                  ),
                ),
              ),
              child: const Text('Actual feed'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Actual feed'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '解锁阅读'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('返回广场'));
    await tester.tap(find.text('返回广场'));
    await tester.pumpAndSettle();
    expect(find.text('Actual feed'), findsOneWidget);
    expect(find.byType(ShareReaderPage), findsNothing);
  });
}
