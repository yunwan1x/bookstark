import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';

void main() {
  test(
    'explicit abort ends bounded metadata even while error-body cancellation is pending',
    () async {
      final cancelEntered = Completer<void>(),
          cancelRelease = Completer<void>(),
          abort = Completer<void>();
      final body = StreamController<List<int>>(
        onCancel: () {
          cancelEntered.complete();
          return cancelRelease.future;
        },
      );
      final client = BookstarkClient(
        'https://owned.test',
        transport: MockClient.streaming(
          (_, _) async => http.StreamedResponse(
            body.stream,
            503,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );
      client.restoreSession({'token': 'fixture-only'});
      addTearDown(client.close);
      final work = client.articleMetadata(19, abortTrigger: abort.future);
      final assertion = expectLater(
        work.timeout(const Duration(seconds: 1)),
        throwsA(
          isA<ApiFailure>().having((e) => e.status, 'cancelled status', 499),
        ),
      );
      await cancelEntered.future;
      abort.complete();
      try {
        await assertion;
      } finally {
        cancelRelease.complete();
        await body.close();
      }
    },
  );
  testWidgets(
    'aborting held error-body cancel leaves no pending deadline timer at disposal',
    (tester) async {
      final cancelEntered = Completer<void>(),
          cancelRelease = Completer<void>(),
          abort = Completer<void>();
      var posts = 0;
      final body = StreamController<List<int>>(
        onCancel: () {
          cancelEntered.complete();
          return cancelRelease.future;
        },
      );
      final client = BookstarkClient(
        'https://owned.test',
        transport: MockClient.streaming((request, _) async {
          if (request.method != 'GET') posts++;
          return http.StreamedResponse(
            body.stream,
            503,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      client.restoreSession({'token': 'fixture-only'});
      addTearDown(client.close);
      final work = client.articleMetadata(19, abortTrigger: abort.future);
      final assertion = expectLater(
        work,
        throwsA(
          isA<ApiFailure>().having((e) => e.status, 'cancelled status', 499),
        ),
      );
      await tester.pump();
      expect(cancelEntered.isCompleted, true);
      abort.complete();
      await tester.pump();
      await assertion;
      // The API's timer/abort operation and assertion remain in fake async. Only
      // the fake transport's StreamController.close waits in the real event loop.
      cancelRelease.complete();
      await tester.pump();
      await tester.runAsync(() => body.close());
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(posts, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
