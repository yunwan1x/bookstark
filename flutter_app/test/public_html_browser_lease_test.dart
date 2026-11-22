import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/features/html/html_browser_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'server to public to server serially retires documents and public transport has no credentials',
    () async {
      final events = <String>[];
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(HtmlBrowserSession.channel, (call) async {
            calls.add(call);
            events.add(call.method);
            return null;
          });
      final client = BookstarkClient('https://books.example')
        ..restoreSession({'token': 'fixture'});
      final server = await HtmlBrowserSession.open(
        client,
        retire: () async {
          events.add('retire-server');
        },
      );
      final local = await HtmlBrowserSession.openPublic(
        retire: () async {
          events.add('retire-local');
        },
      );
      expect(events, ['open', 'retire-server', 'close', 'openPublic']);
      expect(calls.last.arguments.keys.toSet(), {'lease'});
      await server.close();
      expect(events.length, 4);
      final next = await HtmlBrowserSession.open(
        client,
        retire: () async {
          events.add('retire-next');
        },
      );
      expect(events, [
        'open',
        'retire-server',
        'close',
        'openPublic',
        'retire-local',
        'close',
        'open',
      ]);
      await local.close();
      expect(events.length, 7);
      await next.close();
      client.close();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(HtmlBrowserSession.channel, null);
    },
  );
  test(
    'close-active waits for a lease still opening and retires it before returning',
    () async {
      final entered = Completer<void>(), release = Completer<void>();
      final events = <String>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(HtmlBrowserSession.channel, (
        call,
      ) async {
        events.add(call.method);
        if (call.method == 'openPublic') {
          entered.complete();
          await release.future;
        }
        return null;
      });
      final opening = HtmlBrowserSession.openPublic(
        retire: () async {
          events.add('retire');
        },
      );
      await entered.future;
      final closing = HtmlBrowserSession.closeActive();
      await Future<void>.delayed(Duration.zero);
      expect(events, ['openPublic']);
      release.complete();
      final session = await opening;
      await closing;
      expect(events, ['openPublic', 'retire', 'close']);
      await session.close();
      expect(events, ['openPublic', 'retire', 'close']);
      messenger.setMockMethodCallHandler(HtmlBrowserSession.channel, null);
    },
  );
}
