// Draft only. Imports this actual API working copy; no tests/toolchain run.
import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';

http.Response ok(Object data) => http.Response(
  jsonEncode(data),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
void main() {
  test(
    'auth CSRF preparation precedes awaited durable boundary; one fixed send',
    () async {
      final events = <String>[];
      final client = BookstarkClient(
        'https://demo.invalid/mount',
        transport: MockClient((r) async {
          expect(r.followRedirects, false);
          expect(r.url.path.startsWith('/mount/api/'), true);
          if (r.url.path.endsWith('/csrf-token')) {
            events.add('csrf');
            return ok({'code': 0, 'csrf_token': 'fixture-csrf'});
          }
          events.add('post');
          expect(r.method, 'POST');
          expect(r.url.path, '/mount/api/webdav/files/mkdir');
          expect(jsonDecode(r.body), {'path': 'parent', 'name': 'new'});
          expect(r.headers['x-csrf-token'], 'fixture-csrf');
          return ok({
            'code': 0,
            'data': {'id': 12, 'name': 'new', 'path': '', 'type': 'dir'},
          });
        }),
      );
      addTearDown(client.close);
      client.restoreSession({'token': 'fixture-token'});
      final prepared = await client.prepareDriveMutationJson(
        DriveMutationAction.mkdir,
        sourcePath: 'parent',
        name: 'new',
        expectedSessionRevision: client.sessionRevision,
      );
      expect(events, ['csrf']);
      final gate = Completer<void>();
      final pending = prepared.sendAfter(
        onSubmit: () async {
          events.add('marker');
          await gate.future;
          events.add('flushed');
        },
      );
      await Future<void>.delayed(Duration.zero);
      expect(events, ['csrf', 'marker']);
      gate.complete();
      await pending;
      expect(events, ['csrf', 'marker', 'flushed', 'post']);
      expect(() => prepared.sendOnce(), throwsA(isA<ApiFailure>()));
      expect(events.last, 'post');
    },
  );
  test(
    'onSubmit failure sends zero mutation and request cannot be retried',
    () async {
      var requests = 0;
      final client = BookstarkClient(
        'https://demo.invalid',
        transport: MockClient((r) async {
          requests++;
          return ok({'code': 0});
        }),
      );
      addTearDown(client.close);
      client.restoreSession({
        'token': 'fixture-token',
        'csrf_token': 'fixture-csrf',
      });
      final p = await client.prepareBookCreateJson({
        'book_name': 'Exact',
        'description': '',
        'labels': '',
      }, expectedSessionRevision: client.sessionRevision);
      await expectLater(
        p.sendAfter(
          onSubmit: () async {
            throw StateError('flush');
          },
        ),
        throwsStateError,
      );
      expect(requests, 0);
      expect(() => p.sendOnce(), throwsA(isA<ApiFailure>()));
    },
  );
  test(
    'session change during durable await prevents mutation; abort does too',
    () async {
      for (final logout in [false, true]) {
        var requests = 0;
        final client = BookstarkClient(
          'https://demo.invalid',
          transport: MockClient((r) async {
            requests++;
            return ok({'code': 0});
          }),
        );
        client.restoreSession({
          'token': 'fixture-token',
          'csrf_token': 'fixture-csrf',
        });
        final abort = Completer<void>(), gate = Completer<void>();
        final p = await client.prepareDriveMutationJson(
          DriveMutationAction.remove,
          sourcePath: 'a%2Fb.txt',
          expectedSessionRevision: client.sessionRevision,
          abortTrigger: abort.future,
        );
        final result = p.sendAfter(onSubmit: () => gate.future);
        final check = expectLater(result, throwsA(isA<ApiFailure>()));
        if (logout) {
          client.restoreSession({});
        } else {
          abort.complete();
        }
        await Future<void>.delayed(Duration.zero);
        gate.complete();
        await check;
        expect(requests, 0);
        client.close();
      }
    },
  );
  test(
    'metadata bounded errors never disclose raw server error or follow redirect',
    () async {
      const privateError = 'PRIVATE_ERROR_MUST_NOT_ESCAPE';
      final client = BookstarkClient(
        'https://demo.invalid',
        transport: MockClient(
          (r) async => http.Response(
            privateError,
            302,
            headers: {
              'content-type': 'application/json',
              'location': 'https://evil.invalid',
            },
          ),
        ),
      );
      addTearDown(client.close);
      client.restoreSession({'token': 'fixture-token'});
      try {
        await client.boundedDriveListJson(
          '',
          expectedSessionRevision: client.sessionRevision,
        );
        fail('must reject');
      } catch (e) {
        expect(e.toString().contains(privateError), false);
      }
    },
  );
  test('path injection and invalid Unicode rejected before any HTTP', () async {
    var count = 0;
    final client = BookstarkClient(
      'https://demo.invalid',
      transport: MockClient((r) async {
        count++;
        return ok({'code': 0});
      }),
    );
    addTearDown(client.close);
    client.restoreSession({'token': 'fixture-token'});
    expect(
      () => client.prepareDriveMutationJson(
        DriveMutationAction.rename,
        sourcePath: 'a',
        destinationPath: '../escape',
        expectedSessionRevision: client.sessionRevision,
      ),
      throwsFormatException,
    );
    await expectLater(
      client.prepareBookCreateJson({
        'book_name': String.fromCharCode(0xd800),
        'description': '',
        'labels': '',
      }, expectedSessionRevision: client.sessionRevision),
      throwsFormatException,
    );
    expect(count, 0);
  });
}
