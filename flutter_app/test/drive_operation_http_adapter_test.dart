// Draft only; requires merged reviewed notes07 API working copy; not run.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/drive_operation_http_adapter.dart';
import 'package:bookstark_flutter/core/drive_operation_record.dart';
import 'drive_operation_recovery_test.dart' show DriveEnv;

http.Response json(Object value) => http.Response(
  jsonEncode(value),
  200,
  headers: {'content-type': 'application/json'},
);
void main() {
  test(
    'actual owner metadata preflight then awaited marker then one exact rename ACK',
    () async {
      final env = DriveEnv(), record = env.pending(), events = <String>[];
      final client = BookstarkClient(
        env.scope.server,
        transport: MockClient((r) async {
          expect(r.url.path.startsWith('/prefix/api/'), true);
          if (r.url.path.endsWith('/profile')) {
            return json({
              'code': 0,
              'data': {'member_id': 7},
            });
          }
          if (r.method == 'GET') {
            return json({
              'code': 0,
              'data': [driveNodeMetadata(record.source!.node!)],
            });
          }
          events.add('post');
          expect(r.url.path, '/prefix/api/webdav/files/rename');
          expect(jsonDecode(r.body), {'path': 'a.md', 'new_path': 'b.md'});
          return json({'code': 0, 'message': 'Renamed'});
        }),
      );
      client.restoreSession({
        'token': 'fixture-token',
        'csrf_token': 'fixture-csrf',
      });
      final adapter = DriveOperationHttpAdapter(
        client: client,
        scope: env.scope,
        isCurrent: () => true,
      );
      addTearDown(adapter.retire);
      addTearDown(client.close);
      await adapter.transport.execute(
        record,
        onSubmit: () async {
          events.add('marker-flushed');
        },
      );
      expect(events, ['marker-flushed', 'post']);
    },
  );
  test(
    'fresh source mismatch or failed durable marker sends zero mutation',
    () async {
      for (final changed in [false, true]) {
        final env = DriveEnv(), record = env.pending();
        var sends = 0;
        final client = BookstarkClient(
          env.scope.server,
          transport: MockClient((r) async {
            if (r.url.path.endsWith('/profile')) {
              return json({
                'code': 0,
                'data': {'member_id': 7},
              });
            }
            if (r.method == 'GET') {
              return json({
                'code': 0,
                'data': [
                  {
                    ...driveNodeMetadata(record.source!.node!),
                    if (changed) 'etag': 'changed',
                  },
                ],
              });
            }
            sends++;
            return json({'code': 0, 'message': 'Renamed'});
          }),
        );
        client.restoreSession({
          'token': 'fixture-token',
          'csrf_token': 'fixture-csrf',
        });
        final adapter = DriveOperationHttpAdapter(
          client: client,
          scope: env.scope,
          isCurrent: () => true,
        );
        await expectLater(
          adapter.transport.execute(
            record,
            onSubmit: () async {
              throw StateError('flush');
            },
          ),
          throwsA(anything),
        );
        expect(sends, 0);
        adapter.retire();
        client.close();
      }
    },
  );
  test('403 listing is never reported missing', () async {
    final env = DriveEnv(),
        client = BookstarkClient(
          env.scope.server,
          transport: MockClient(
            (_) async => http.Response(
              'private server detail',
              403,
              headers: {'content-type': 'application/json'},
            ),
          ),
        );
    client.restoreSession({'token': 'fixture-token'});
    final adapter = DriveOperationHttpAdapter(
      client: client,
      scope: env.scope,
      isCurrent: () => true,
    );
    await expectLater(adapter.observe('a.md'), throwsA(isA<ApiFailure>()));
    adapter.retire();
    client.close();
  });
  test(
    'missing data is unreadable; explicit successful null is empty only',
    () async {
      for (final explicitNull in [false, true]) {
        final env = DriveEnv();
        final client = BookstarkClient(
          env.scope.server,
          transport: MockClient(
            (_) async => json(
              explicitNull
                  ? {'code': 0, 'data': null}
                  : {'code': 0, 'message': 'not a list'},
            ),
          ),
        );
        client.restoreSession({'token': 'fixture-token'});
        final adapter = DriveOperationHttpAdapter(
          client: client,
          scope: env.scope,
          isCurrent: () => true,
        );
        if (explicitNull) {
          expect(
            (await adapter.observe('a.md')).state,
            DriveObservationState.missing,
          );
          expect((await adapter.observe('')).state, DriveObservationState.root);
        } else {
          await expectLater(adapter.observe('a.md'), throwsFormatException);
          await expectLater(adapter.observe(''), throwsFormatException);
        }
        adapter.retire();
        client.close();
      }
    },
  );
}
