import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/article_web_scope.dart';
import 'package:bookstark_flutter/features/articles/article_web_session.dart';
import 'package:bookstark_flutter/features/html/html_browser_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <String>[];
  late BookstarkClient client;
  Completer<void>? nativeOpen, nativeClose;
  Map? openArgs;
  var current = true, failClose = false, retired = 0;
  setUp(() async {
    nativeOpen = null;
    nativeClose = null;
    openArgs = null;
    current = true;
    failClose = false;
    retired = 0;
    messenger.setMockMethodCallHandler(HtmlBrowserSession.channel, (
      call,
    ) async {
      calls.add('html:${call.method}');
      return null;
    });
    messenger.setMockMethodCallHandler(ArticleWebSession.channel, (call) async {
      calls.add('article:${call.method}');
      if (call.method == 'open') {
        openArgs = call.arguments as Map;
        await nativeOpen?.future;
      }
      if (call.method == 'close') {
        await nativeClose?.future;
        if (failClose) throw PlatformException(code: 'close_failed');
      }
      if (call.method == 'back') return true;
      return null;
    });
    await HtmlBrowserSession.closeActive();
    calls.clear();
    client = BookstarkClient('https://example.test/app');
    client.restoreSession({
      'token': 'synthetic-token',
      'csrf_token': 'synthetic-csrf',
    });
    client.language = 'en';
  });
  tearDown(() async {
    if (nativeOpen != null && !nativeOpen!.isCompleted) nativeOpen!.complete();
    if (nativeClose != null && !nativeClose!.isCompleted) {
      nativeClose!.complete();
    }
    failClose = false;
    await HtmlBrowserSession.closeActive();
    messenger.setMockMethodCallHandler(HtmlBrowserSession.channel, null);
    messenger.setMockMethodCallHandler(ArticleWebSession.channel, null);
    client.close();
  });
  Future<ArticleWebSession> open() => ArticleWebSession.open(
    client: client,
    scope: ArticleWebScope(client.baseUri, 7),
    isCurrentScope: () => current,
    retire: () async {
      retired++;
    },
  );
  Future<void> tick() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test(
    'typed deep entry is exact and invalid entries never retire another lease',
    () async {
      final scope = ArticleWebScope(client.baseUri, 7);
      final entry = scope.editorEntry({
        'blog_id': 19,
        'member_id': 7,
        'blog_type': 'article',
        'blog_identify': 'deep-19',
      }, id: 19);
      final session = await ArticleWebSession.open(
        client: client,
        scope: scope,
        entry: entry,
        isCurrentScope: () => current,
        retire: () async {},
      );
      expect(openArgs!['entry'], entry.toString());
      await session.close();
      calls.clear();
      await expectLater(
        ArticleWebSession.open(
          client: client,
          scope: scope,
          entry: Uri.parse('https://elsewhere.test/blogs/x/edit'),
          isCurrentScope: () => current,
          retire: () async {},
        ),
        throwsArgumentError,
      );
      expect(calls, isEmpty);
    },
  );

  test(
    'native private profile uses owned local lease and exact account cookies',
    () async {
      final session = await open();
      expect(calls, ['html:openLocal', 'article:open']);
      expect(
        openArgs!['profile'],
        ArticleWebScope(client.baseUri, 7).profileName,
      );
      expect(openArgs!['cookies'], {
        'token': 'synthetic-token',
        'csrf_token': 'synthetic-csrf',
      });
      expect(
        openArgs!['entry'],
        'https://example.test/app/notes?tab=articles&type=article',
      );
      expect(openArgs!['cookiePath'], '/app/');
      expect(openArgs!['language'], 'en');
      expect(await session.command<bool>('back'), isTrue);
      await session.close();
      expect(retired, 1);
      expect(
        calls.indexOf('article:close'),
        lessThan(calls.indexOf('html:close')),
      );
      await session.close();
      expect(calls.where((x) => x == 'article:close').length, 1);
    },
  );
  test(
    'scope mismatch or unauthenticated caller never retires another browser',
    () async {
      client.restoreSession({});
      await expectLater(open(), throwsStateError);
      expect(calls, isEmpty);
      client.restoreSession({'token': 'synthetic-token'});
      await expectLater(
        ArticleWebSession.open(
          client: client,
          scope: ArticleWebScope(Uri.parse('https://other.test'), 7),
          isCurrentScope: () => true,
          retire: () async {},
        ),
        throwsStateError,
      );
      expect(calls, isEmpty);
    },
  );
  test(
    'new authenticated document waits for article cookie cleanup barrier',
    () async {
      await open();
      nativeClose = Completer<void>();
      var nextOpened = false;
      final next = HtmlBrowserSession.open(client, retire: () async {}).then((
        v,
      ) {
        nextOpened = true;
        return v;
      });
      await tick();
      expect(calls, contains('article:close'));
      expect(calls, isNot(contains('html:open')));
      expect(nextOpened, isFalse);
      nativeClose!.complete();
      final html = await next;
      expect(retired, 1);
      expect(
        calls.indexOf('article:close'),
        lessThan(calls.indexOf('html:open')),
      );
      await html.close();
    },
  );
  test(
    'retirement during pending native open never restores the old session',
    () async {
      nativeOpen = Completer<void>();
      final opening = open();
      await tick();
      expect(calls, contains('article:open'));
      var nextOpened = false;
      final next = HtmlBrowserSession.openLocal(retire: () async {}).then((v) {
        nextOpened = true;
        return v;
      });
      final failed = expectLater(opening, throwsStateError);
      await tick();
      expect(nextOpened, isFalse);
      nativeOpen!.complete();
      await failed;
      final html = await next;
      expect(retired, 1);
      expect(calls.where((x) => x == 'article:close').length, 1);
      await html.close();
    },
  );
  test(
    'account change retires commands and unsupported commands cannot cross bridge',
    () async {
      final session = await open();
      await expectLater(
        session.command<void>('evaluateJavascript'),
        throwsArgumentError,
      );
      expect(calls, isNot(contains('article:evaluateJavascript')));
      client.restoreSession({'token': 'other-synthetic-account'});
      expect(session.isCurrent, isFalse);
      await expectLater(session.command<void>('resume'), throwsStateError);
      expect(calls, isNot(contains('article:resume')));
      await session.close();
      expect(retired, 1);
    },
  );
  test(
    'failed native close remains retryable and cannot seed an heir cookie jar',
    () async {
      final session = await open();
      failClose = true;
      await expectLater(session.close(), throwsA(isA<PlatformException>()));
      // Both native layers must close even when the article ACK fails.
      expect(calls.where((x) => x == 'html:close').length, 1);
      expect(calls.where((x) => x == 'html:open').length, 0);
      failClose = false;
      nativeClose = Completer<void>();
      var heirOpened = false;
      final opening = HtmlBrowserSession.open(client, retire: () async {}).then((v) {
        heirOpened = true;
        return v;
      });
      await tick();
      expect(heirOpened, isFalse);
      expect(calls.where((x) => x == 'html:open').length, 0);
      nativeClose!.complete();
      final next = await opening;
      expect(calls.where((x) => x == 'article:close').length, 2);
      expect(calls.where((x) => x == 'html:close').length, 1);
      expect(calls.last, 'html:open');
      await next.close();
    },
  );
  test('export cleanup may name only its old lease after retirement', () async {
    final session = await open();
    final owned = session.lease;
    await session.close();
    Map? released;
    messenger.setMockMethodCallHandler(ArticleWebSession.channel, (call) async {
      if (call.method == 'releaseDownload') released = call.arguments as Map;
      return null;
    });
    await session.releaseDownload('0123456789abcdef0123456789abcdef');
    expect(released, {
      'lease': owned,
      'id': '0123456789abcdef0123456789abcdef',
    });
    await expectLater(
      session.releaseDownload('../foreign'),
      throwsArgumentError,
    );
  });
}
