import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/features/articles/article_web_page.dart';
import 'package:bookstark_flutter/features/articles/article_web_session.dart';
import 'package:bookstark_flutter/features/html/html_browser_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const guard = MethodChannel('bookstark/asset_secure_window');
  final calls = <String>[];
  late BookstarkClient client;
  late ArticleWebPageController controller;
  String? lease;
  Map? openArgs;
  int? viewId;
  Completer<void>? acquire, close;
  bool leave = true, current = true, immediateError = false;
  final destinations = <String>[];
  Future<void> event(
    String method,
    Map<String, Object?> values, {
    String? identity,
  }) async {
    final completion = Completer<void>();
    messenger.handlePlatformMessage(
      'bookstark/article_web_view/$viewId',
      const StandardMethodCodec().encodeMethodCall(
        MethodCall(method, {...values, 'lease': identity ?? lease}),
      ),
      (_) => completion.complete(),
    );
    await completion.future;
  }

  setUp(() {
    calls.clear();
    destinations.clear();
    lease = null;
    openArgs = null;
    viewId = null;
    acquire = null;
    close = null;
    leave = true;
    current = true;
    immediateError = false;
    controller = ArticleWebPageController();
    client = BookstarkClient('https://example.test/bookstark');
    client.restoreSession({'token': 'synthetic-token'});
    messenger.setMockMethodCallHandler(guard, (call) async {
      calls.add('guard:${call.method}');
      if (call.method == 'acquire') await acquire?.future;
      return true;
    });
    messenger.setMockMethodCallHandler(HtmlBrowserSession.channel, (
      call,
    ) async {
      calls.add('html:${call.method}');
      return null;
    });
    messenger.setMockMethodCallHandler(ArticleWebSession.channel, (call) async {
      calls.add('article:${call.method}');
      if (call.method == 'open') {
        lease = call.arguments['lease'] as String;
        openArgs = call.arguments as Map;
      }
      if (call.method == 'close') await close?.future;
      if (call.method == 'prepareLeave') return leave;
      if (call.method == 'back') return false;
      return null;
    });
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
      call,
    ) async {
      if (call.method == 'create') {
        viewId = call.arguments['id'] as int;
        calls.add('view:create');
        if (immediateError) {
          unawaited(event('error', {'reason': 'webview'}));
        } else {
          unawaited(event('ready', {}));
        }
        return 99;
      }
      if (call.method == 'resize') {
        return {
          'width': call.arguments['width'],
          'height': call.arguments['height'],
        };
      }
      return null;
    });
  });
  tearDown(() async {
    if (acquire != null && !acquire!.isCompleted) acquire!.complete();
    if (close != null && !close!.isCompleted) close!.complete();
    await HtmlBrowserSession.closeActive();
    messenger.setMockMethodCallHandler(guard, null);
    messenger.setMockMethodCallHandler(HtmlBrowserSession.channel, null);
    messenger.setMockMethodCallHandler(ArticleWebSession.channel, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
    client.close();
  });
  Future<void> mount(
    WidgetTester tester, {
    int? articleId,
    Future<void> Function()? onBack,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ArticleWebPage(
            client: client,
            memberId: 7,
            articleId: articleId,
            onBack: onBack,
            controller: controller,
            isCurrentScope: () => current,
            onNavigate: (route) async {
              destinations.add(route);
            },
            onConnection: () async {
              destinations.add('connection');
            },
          ),
        ),
      ),
    );
    for (var i = 0; i < 12; i++) {
      await tester.pump();
    }
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    for (var i = 0; i < 12; i++) {
      await tester.pump();
    }
  }

  void articleTest(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      try {
        await body(tester);
      } finally {
        if (acquire != null && !acquire!.isCompleted) acquire!.complete();
        if (close != null && !close!.isCompleted) close!.complete();
        await dispose(tester);
      }
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  }

  void articleClient(Future<http.Response> Function(http.Request) handler) {
    client.close();
    client = BookstarkClient(
      'https://example.test/bookstark',
      transport: MockClient(handler),
    );
    client.restoreSession({'token': 'synthetic-token'});
  }

  Map<String, Object?> articleIdentity() => {
    'code': 0,
    'data': {
      'blog_id': 19,
      'member_id': 7,
      'blog_type': 'article',
      'blog_identify': 'deep-19',
      'blog_content': 'NEVER_NATIVE_BODY',
    },
  };

  articleTest(
    'deep article resolves identity before cookies and opens exact Go editor',
    (tester) async {
      final metadata = Completer<http.Response>();
      articleClient((request) async {
        calls.add('metadata:read');
        expect(request.url.path, '/bookstark/api/blogs/19');
        return metadata.future;
      });
      await mount(tester, articleId: 19);
      expect(find.text('正在打开文章…'), findsOneWidget);
      expect(calls, ['guard:acquire', 'metadata:read']);
      metadata.complete(
        http.Response(
          jsonEncode(articleIdentity()),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
      for (var i = 0; i < 20; i++) {
        await tester.pump();
      }
      expect(
        openArgs!['entry'],
        'https://example.test/bookstark/blogs/deep-19/edit',
      );
      expect(
        calls.indexOf('metadata:read'),
        lessThan(calls.indexOf('article:open')),
      );
      expect(find.text('NEVER_NATIVE_BODY'), findsNothing);
    },
  );

  articleTest(
    'metadata identity mismatch stays outside WebView and retry resolves anew',
    (tester) async {
      var attempts = 0;
      articleClient((_) async {
        final receipt = articleIdentity();
        if (++attempts == 1) {
          (receipt['data'] as Map)['member_id'] = 8;
        }
        return http.Response(
          jsonEncode(receipt),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      await mount(tester, articleId: 19);
      expect(find.text('文章暂时无法打开'), findsOneWidget);
      expect(calls, isNot(contains('article:open')));
      expect(calls, isNot(contains('view:create')));
      await tester.tap(find.text('重试'));
      for (var i = 0; i < 20; i++) {
        await tester.pump();
      }
      expect(attempts, 2);
      expect(openArgs!['entry'], endsWith('/blogs/deep-19/edit'));
    },
  );

  articleTest(
    'deep return waits for native close and returns to source instead of home',
    (tester) async {
      articleClient(
        (_) async => http.Response(
          jsonEncode(articleIdentity()),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
      close = Completer<void>();
      await mount(
        tester,
        articleId: 19,
        onBack: () async => destinations.add('source'),
      );
      await tester.tap(find.byTooltip('返回'));
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }
      expect(calls, contains('article:close'));
      expect(destinations, isEmpty);
      close!.complete();
      for (var i = 0; i < 12; i++) {
        await tester.pump();
      }
      expect(destinations, ['source']);
    },
  );

  articleTest(
    'closing during metadata cannot open late account cookies or view',
    (tester) async {
      final metadata = Completer<http.Response>();
      articleClient((_) => metadata.future);
      await mount(tester, articleId: 19);
      await tester.pumpWidget(const SizedBox());
      metadata.complete(
        http.Response(
          jsonEncode(articleIdentity()),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
      for (var i = 0; i < 20; i++) {
        await tester.pump();
      }
      expect(calls, isNot(contains('article:open')));
      expect(calls, isNot(contains('view:create')));
      expect(calls, contains('guard:release'));
    },
  );

  articleTest(
    'secure window must finish before account cookies or view creation',
    (tester) async {
      acquire = Completer<void>();
      await mount(tester);
      expect(calls, ['guard:acquire']);
      acquire!.complete();
      for (var i = 0; i < 15; i++) {
        await tester.pump();
      }
      expect(
        calls.indexOf('guard:acquire'),
        lessThan(calls.indexOf('article:open')),
      );
      expect(
        calls.indexOf('article:open'),
        lessThan(calls.indexOf('view:create')),
      );
      await dispose(tester);
    },
  );
  articleTest(
    'native constructor failure is received before platform create completes',
    (tester) async {
      immediateError = true;
      await mount(tester);
      expect(find.text('暂时无法连接文章服务'), findsOneWidget);
      expect(find.text('重新加载'), findsOneWidget);
      await dispose(tester);
    },
  );
  articleTest(
    'leave rejection preserves current editor and blocks navigation',
    (tester) async {
      await mount(tester);
      leave = false;
      expect(await controller.prepareLeave(), isFalse);
      await tester.tap(find.byTooltip('返回'));
      await tester.pump();
      expect(destinations, isEmpty);
      expect(calls, isNot(contains('article:back')));
      await dispose(tester);
    },
  );
  articleTest('late old lease error cannot replace the current page', (
    tester,
  ) async {
    await mount(tester);
    await event('error', {'reason': 'http'}, identity: 'stale-lease');
    await tester.pump();
    expect(find.text('暂时无法连接文章服务'), findsNothing);
    await dispose(tester);
  });
  articleTest('background pause and resume preserve the same article lease', (
    tester,
  ) async {
    await mount(tester);
    final original = lease;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(calls, containsAll(['article:pause', 'article:resume']));
    expect(lease, original);
    expect(calls.where((v) => v == 'article:open').length, 1);
    await dispose(tester);
  });
  articleTest('native cookie cleanup finishes before secure window release', (
    tester,
  ) async {
    await mount(tester);
    close = Completer<void>();
    await dispose(tester);
    expect(calls, contains('article:close'));
    expect(calls, isNot(contains('guard:release')));
    close!.complete();
    for (var i = 0; i < 15; i++) {
      await tester.pump();
    }
    expect(
      calls.indexOf('article:close'),
      lessThan(calls.indexOf('guard:release')),
    );
  });
  articleTest('network error overlay keeps the same native editor mounted', (
    tester,
  ) async {
    await mount(tester);
    final original = viewId;
    await event('error', {'reason': 'network'});
    await tester.pump();
    expect(find.text('暂时无法连接文章服务'), findsOneWidget);
    expect(viewId, original);
    expect(calls.where((v) => v == 'view:create').length, 1);
    expect(calls, isNot(contains('article:close')));
    await dispose(tester);
  });
  articleTest('revoked account scope never resumes a background page', (
    tester,
  ) async {
    await mount(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    current = false;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(calls, isNot(contains('article:resume')));
    await dispose(tester);
  });
}
