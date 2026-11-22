import 'package:bookstark_flutter/core/native_recovery_storage.dart';
import 'package:bookstark_flutter/features/assistant/assistant_page.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/main.dart';
import 'package:bookstark_flutter/features/articles/article_web_page.dart';
import 'package:bookstark_flutter/features/articles/article_web_session.dart';
import 'package:bookstark_flutter/features/html/html_browser_session.dart';
import 'package:bookstark_flutter/features/profile/profile_page.dart';
import 'package:bookstark_flutter/features/search/search_page.dart';
import 'profile_root_test.dart' as root;

void main() {
  testWidgets(
    'real root search opens Go article, returns to results and defers module handoff',
    (tester) async {
      root.seed();
      final server = root.Server();
      final calls = <String>[];
      var identityReads = 0;
      var searchReads = 0;
      server.extra = (request) async {
        if (request.url.path == '/api/ai/assistant') {
          return server.data({
            'session': {'id': 'a' * 32, 'busy': false, 'drafts': <Object?>[]},
          });
        }
        if (request.url.path == '/api/home') {
          return server.data({
            'sections': <Object?>[],
            'activity': <String, int>{},
            'layout': null,
            'recent': [
              {
                'type': 'article',
                'id': 19,
                'title': 'Recent article',
                'url': 'https://untrusted.test/not-a-native-route',
              },
            ],
          });
        }
        if (request.url.path == '/api/search') {
          searchReads++;
          return server.data({
            'counts': {
              'documents': 0,
              'blogs': 1,
              'books': 0,
              'bookmarks': 0,
              'tasks': 0,
              'topics': 0,
              'labels': 0,
            },
            'blogs': [
              {
                'id': 19,
                'title': 'Article search result',
                'blog_type': 'article',
                'identify': 'UNTRUSTED-search-identify',
              },
            ],
          });
        }
        if (request.url.path == '/api/blogs/19') {
          identityReads++;
          return server.data({
            'blog_id': 19,
            'member_id': 7,
            'blog_type': 'article',
            'editor_type': 'markdown',
            'has_password': false,
            'blog_identify': 'verified-19',
            'blog_content': 'NEVER_NATIVE_ARTICLE',
          });
        }
        return null;
      };
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const guard = MethodChannel('bookstark/asset_secure_window');
      String? lease;
      int? viewId;
      Completer<void>? closing;
      Future<void> event(String method, Map<String, Object?> args) async {
        final completed = Completer<void>();
        messenger.handlePlatformMessage(
          'bookstark/article_web_view/$viewId',
          const StandardMethodCodec().encodeMethodCall(
            MethodCall(method, {...args, 'lease': lease}),
          ),
          (_) => completed.complete(),
        );
        await completed.future;
      }

      messenger.setMockMethodCallHandler(NativeRecoveryStorage.channel, (
        call,
      ) async {
        calls.add('recovery:${call.method}');
        if (call.method == 'flush') return true;
        if (call.method == 'localMetadata') {
          return {
            'format': 1,
            'secureKeys': <String>[],
            'htmlKeys': <String>[],
            'overflow': false,
            'valuesIncluded': false,
          };
        }
        throw StateError('Article preflight must inspect keys only');
      });
      messenger.setMockMethodCallHandler(guard, (call) async {
        calls.add('guard:${call.method}');
        return true;
      });
      messenger.setMockMethodCallHandler(
        HtmlBrowserSession.channel,
        (_) async => null,
      );
      messenger.setMockMethodCallHandler(ArticleWebSession.channel, (
        call,
      ) async {
        calls.add('article:${call.method}');
        if (call.method == 'open') {
          lease = call.arguments['lease'] as String;
          expect(
            call.arguments['entry'],
            'https://example.test/blogs/verified-19/edit',
          );
        }
        if (call.method == 'prepareLeave') return true;
        if (call.method == 'back') return false;
        if (call.method == 'close') await closing?.future;
        return null;
      });
      messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
        call,
      ) async {
        if (call.method == 'create') {
          viewId = call.arguments['id'] as int;
          unawaited(event('ready', {}));
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
      addTearDown(() async {
        if (closing != null && !closing.isCompleted) closing.complete();
        await HtmlBrowserSession.closeActive();
        messenger.setMockMethodCallHandler(NativeRecoveryStorage.channel, null);
        messenger.setMockMethodCallHandler(guard, null);
        messenger.setMockMethodCallHandler(HtmlBrowserSession.channel, null);
        messenger.setMockMethodCallHandler(ArticleWebSession.channel, null);
        messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
      });

      await tester.pumpWidget(BookstarkApp(clientFactory: server.client));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Recent article'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Recent article'));
      await tester.pumpAndSettle();
      expect(find.byType(ArticleWebPage), findsOneWidget);
      expect(
        calls,
        containsAllInOrder([
          'recovery:flush',
          'recovery:localMetadata',
          'article:open',
        ]),
      );
      // Collection resolution and page-entry ownership each read authoritative metadata.
      expect(identityReads, 2);
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      expect(find.byType(ArticleWebPage), findsNothing);
      await tester.scrollUntilVisible(
        find.text('Recent article'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Recent article'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('全局搜索'),
        -180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('全局搜索'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Article');
      final result = find.byKey(const ValueKey('search-blog-19'));
      Future<void> awaitActualSearchResult() async {
        // Prepared authenticated GET drains a real response stream. Do not
        // advance fake20s cancellation while starving its event-loop delivery.
        for (var i = 0; i < 100; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 1)),
          );
          await tester.pump();
          if (result.evaluate().length == 1 &&
              find.byType(LinearProgressIndicator).evaluate().isEmpty) {
            break;
          }
        }
        expect(result, findsOneWidget);
        expect(find.byType(LinearProgressIndicator), findsNothing);
        await tester.pumpAndSettle();
      }

      await tester.runAsync(
        () => tester.testTextInput.receiveAction(TextInputAction.search),
      );
      await awaitActualSearchResult();
      expect(searchReads, 1);
      await tester.runAsync(() => tester.tap(result));
      await tester.pumpAndSettle();
      expect(find.byType(ArticleWebPage), findsOneWidget);
      expect(find.text('NEVER_NATIVE_ARTICLE'), findsNothing);
      expect(identityReads, 3);

      await tester.tap(find.byTooltip('返回'));
      await awaitActualSearchResult();
      expect(find.byType(SearchPage), findsOneWidget);
      expect(result, findsOneWidget);
      expect(searchReads, 2);
      await tester.runAsync(() => tester.tap(result));
      await tester.pumpAndSettle();
      expect(identityReads, 4);

      closing = Completer<void>();
      var navigationAcknowledged = false;
      final navigating = event('navigation', {'url': '/profile'}).then((_) {
        navigationAcknowledged = true;
      });
      for (var i = 0; i < 8; i++) {
        await tester.pump();
      }
      expect(find.byType(ProfilePage), findsNothing);
      closing.complete();
      var handoffReady = false;
      // Closing the real article route also resolves SearchPage's opener and
      // may start its fresh prepared GET before Root removes that search route.
      // Yield the real stream loop while advancing only bounded route animation
      // frames, rather than starving the stream with pumpAndSettle.
      for (var i = 0; i < 100; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 1)),
        );
        await tester.pump(const Duration(milliseconds: 16));
        if (navigationAcknowledged &&
            find.byType(ProfilePage).evaluate().length == 1 &&
            find.byType(ArticleWebPage).evaluate().isEmpty &&
            find.byType(SearchPage).evaluate().isEmpty &&
            find.byType(LinearProgressIndicator).evaluate().isEmpty &&
            find.byType(CircularProgressIndicator).evaluate().isEmpty) {
          handoffReady = true;
          break;
        }
      }
      expect(handoffReady, isTrue);
      expect(navigationAcknowledged, isTrue);
      await navigating;
      expect(find.byType(ArticleWebPage), findsNothing);
      expect(find.byType(SearchPage), findsNothing);
      expect(find.byType(ProfilePage), findsOneWidget);
      expect(calls.where((c) => c == 'article:close').length, 3);
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('打开 AI 助手'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('打开 AI 助手'));
      await tester.pumpAndSettle();
      final assistant = tester.widget<AssistantPage>(
        find.byType(AssistantPage),
      );
      expect(assistant.local, isFalse);
      final sourceOpen = assistant.onOpenSource!({
        'kind': 'note',
        'id': 19,
        'url': 'https://untrusted.test/not-a-native-route',
      });
      unawaited(sourceOpen);
      await tester.pumpAndSettle();
      expect(find.byType(ArticleWebPage), findsOneWidget);
      expect(find.text('NEVER_NATIVE_ARTICLE'), findsNothing);
      expect(identityReads, 6);
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      await sourceOpen;
      expect(find.byType(AssistantPage), findsOneWidget);
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      expect(calls.where((call) => call == 'article:close').length, 4);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}
