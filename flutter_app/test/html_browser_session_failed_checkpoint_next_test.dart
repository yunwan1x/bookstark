import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/features/html/html_browser_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'failed checkpoint closes native lease, blocks heir, retries storage only',
    () async {
      final calls = <String>[];
      var fail = true;
      var writes = 0;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(HtmlBrowserSession.channel, (
        call,
      ) async {
        calls.add(call.method);
        return null;
      });
      final first = await HtmlBrowserSession.openLocal(
        retire: () async {
          writes++;
          if (fail) throw StateError('held storage failure');
        },
      );
      try {
        await expectLater(HtmlBrowserSession.closeActive(), throwsStateError);
        expect(calls, ['openLocal', 'close']);
        await expectLater(
          HtmlBrowserSession.openLocal(retire: () async {}),
          throwsStateError,
        );
        expect(calls, ['openLocal', 'close']);
        expect(writes, 2);
        fail = false;
        await HtmlBrowserSession.closeActive();
        expect(writes, 3);
        expect(calls, ['openLocal', 'close']);
        final heir = await HtmlBrowserSession.openLocal(retire: () async {});
        expect(calls, ['openLocal', 'close', 'openLocal']);
        await heir.close();
      } finally {
        fail = false;
        await first.close();
        await HtmlBrowserSession.closeActive();
        messenger.setMockMethodCallHandler(HtmlBrowserSession.channel, null);
      }
    },
  );

  test(
    'failed store still waits actual native close ACK before failing barrier',
    () async {
      final gate = Completer<void>();
      var closeEntered = false;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(HtmlBrowserSession.channel, (
        call,
      ) async {
        if (call.method == 'close') {
          closeEntered = true;
          await gate.future;
        }
        return null;
      });
      var fail = true;
      final first = await HtmlBrowserSession.openLocal(
        retire: () async {
          if (fail) throw StateError('store failed');
        },
      );
      var ended = false;
      final close = HtmlBrowserSession.closeActive();
      final checked = expectLater(
        close,
        throwsStateError,
      ).then((_) => ended = true);
      try {
        await Future<void>.delayed(Duration.zero);
        expect(closeEntered, isTrue);
        expect(ended, isFalse);
        gate.complete();
        await checked;
        expect(ended, isTrue);
      } finally {
        if (!gate.isCompleted) gate.complete();
        fail = false;
        await first.close();
        messenger.setMockMethodCallHandler(HtmlBrowserSession.channel, null);
      }
    },
  );
  test(
    'store and native-close failures both block heirs until separately ACKed',
    () async {
      var storeFails = true;
      var closeFails = true;
      var nativeAttempts = 0;
      var stores = 0;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(HtmlBrowserSession.channel, (
        call,
      ) async {
        if (call.method == 'close') {
          nativeAttempts++;
          if (closeFails) throw PlatformException(code: 'held_native_close');
        }
        return null;
      });
      final session = await HtmlBrowserSession.openLocal(
        retire: () async {
          stores++;
          if (storeFails) throw StateError('store failure');
        },
      );
      try {
        await expectLater(session.close(), throwsA(isA<PlatformException>()));
        expect(nativeAttempts, 1);
        closeFails = false;
        await expectLater(session.close(), throwsStateError);
        expect(nativeAttempts, 2);
        storeFails = false;
        await session.close();
        expect(stores, 3);
        expect(nativeAttempts, 2);
      } finally {
        storeFails = false;
        closeFails = false;
        await session.close();
        messenger.setMockMethodCallHandler(HtmlBrowserSession.channel, null);
      }
    },
  );
}
