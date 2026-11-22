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
    'same token and cookies restore invalidates prior native article lease',
    () async {
      final session = await open();
      final saved = client.exportSession();
      client.restoreSession(saved);
      expect(session.isCurrent, isFalse);
      expect(openArgs!['cookies'], saved);
      calls.clear();
      await expectLater(session.command<void>('reload'), throwsStateError);
      expect(calls, isEmpty);
      await session.close();
    },
  );
  test(
    'same-cookie restore during actual native open rejects late lease',
    () async {
      nativeOpen = Completer<void>();
      final opening = open();
      await tick();
      final saved = client.exportSession();
      client.restoreSession(saved);
      final failed = expectLater(opening, throwsStateError);
      nativeOpen!.complete();
      await failed;
      expect(calls.where((v) => v == 'article:close').length, 1);
      expect(client.exportSession(), saved);
      expect(retired, greaterThanOrEqualTo(1));
    },
  );
}
