import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/features/html/html_browser_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  final order = <String>[];
  BookstarkClient client(String token) =>
      BookstarkClient('https://example.test/mount')
        ..restoreSession({'token': token, 'csrf_token': 'csrf'});
  setUp(() {
    calls.clear();
    order.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(HtmlBrowserSession.channel, (call) async {
          calls.add(call);
          order.add(call.method);
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(HtmlBrowserSession.channel, null);
  });
  test(
    'authenticated session passes only current server cookies to native bridge',
    () async {
      final session = await HtmlBrowserSession.open(
        client('first'),
        retire: () async {
          order.add('retire');
        },
      );
      expect(calls.single.arguments['server'], 'https://example.test/mount');
      expect(calls.single.arguments['cookies'], {
        'token': 'first',
        'csrf_token': 'csrf',
      });
      await session.close();
      expect(order, ['open', 'retire', 'close']);
    },
  );
  test(
    'replacement retires old document before cookies; stale close cannot erase new lease',
    () async {
      final first = await HtmlBrowserSession.open(
        client('first'),
        retire: () async {
          order.add('retire-first');
        },
      );
      final second = await HtmlBrowserSession.open(
        client('second'),
        retire: () async {
          order.add('retire-second');
        },
      );
      expect(order, ['open', 'retire-first', 'close', 'open']);
      await first.close();
      expect(order, ['open', 'retire-first', 'close', 'open']);
      await second.close();
      expect(order, [
        'open',
        'retire-first',
        'close',
        'open',
        'retire-second',
        'close',
      ]);
    },
  );
  test(
    'logout while installing cookies closes that lease and rejects preview',
    () async {
      final owner = client('first');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(HtmlBrowserSession.channel, (call) async {
            calls.add(call);
            if (call.method == 'open') owner.restoreSession({});
            return null;
          });
      await expectLater(
        HtmlBrowserSession.open(owner, retire: () async {}),
        throwsStateError,
      );
      expect(calls.map((c) => c.method), ['open', 'close']);
    },
  );
  test(
    'failed retirement prevents next account cookies; queue remains recoverable',
    () async {
      var fail = true;
      final first = await HtmlBrowserSession.open(
        client('first'),
        retire: () async {
          if (fail) throw StateError('retire failed');
        },
      );
      await expectLater(
        HtmlBrowserSession.open(client('second'), retire: () async {}),
        throwsStateError,
      );
      // Failed storage still revokes the original native lease. The next
      // account is blocked until storage retry succeeds, without closing twice.
      expect(calls.map((call) => call.method), ['open', 'close']);
      fail = false;
      await first.close();
      final second = await HtmlBrowserSession.open(
        client('second'),
        retire: () async {},
      );
      await second.close();
      expect(calls.map((c) => c.method), ['open', 'close', 'open', 'close']);
    },
  );
  test('concurrent opens wait for retirement completion', () async {
    final gate = Completer<void>();
    final first = await HtmlBrowserSession.open(
      client('first'),
      retire: () => gate.future,
    );
    final secondFuture = HtmlBrowserSession.open(
      client('second'),
      retire: () async {},
    );
    await Future<void>.delayed(Duration.zero);
    expect(calls.length, 1);
    gate.complete();
    final second = await secondFuture;
    await first.close();
    await second.close();
    expect(calls.map((c) => c.method), ['open', 'close', 'open', 'close']);
  });
  test('closed barrier waits the native close result', () async {
    final gate = Completer<void>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(HtmlBrowserSession.channel, (call) async {
          calls.add(call);
          if (call.method == 'close') await gate.future;
          return null;
        });
    final session = await HtmlBrowserSession.openLocal(retire: () async {});
    var done = false;
    final barrier = session.closed..then((_) => done = true);
    final closing = session.close();
    await Future<void>.delayed(Duration.zero);
    expect(done, isFalse);
    gate.complete();
    await closing;
    await barrier;
    expect(done, isTrue);
  });
  test(
    'failed native close rejects its barrier and permits fresh close retry',
    () async {
      var attempts = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(HtmlBrowserSession.channel, (call) async {
            calls.add(call);
            if (call.method == 'close' && ++attempts == 1) {
              throw PlatformException(code: 'test-failed');
            }
            return null;
          });
      final session = await HtmlBrowserSession.openLocal(retire: () async {});
      final oldBarrier = expectLater(
        session.closed,
        throwsA(isA<PlatformException>()),
      );
      await expectLater(session.close(), throwsA(isA<PlatformException>()));
      await oldBarrier;
      final fresh = session.closed;
      await session.close();
      await fresh;
      expect(attempts, 2);
    },
  );
}
