import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';

void main() {
  for (final upload in [false, true]) {
    test('scope retires during CSRF: zero image mutation $upload', () async {
      var current = true, mutations = 0;
      final client = BookstarkClient(
        'https://fixture.invalid',
        transport: MockClient((request) async {
          if (request.url.path == '/api/csrf-token') {
            current = false;
            return http.Response(
              jsonEncode({'code': 0, 'data': null}),
              200,
              headers: {'set-cookie': 'csrf_token=owned-fixture; Path=/'},
            );
          }
          mutations++;
          return http.Response('unexpected', 500);
        }),
      );
      void guard() {
        if (!current) throw StateError('Image owner retired');
      }

      final future = upload
          ? client.upload(
              '/api/uploads',
              name: 'fixture.png',
              data: Stream.value([1]),
              length: 1,
              beforeSubmit: guard,
            )
          : client.mutate('DELETE', '/api/uploads/47', {}, beforeSubmit: guard);
      await expectLater(future, throwsStateError);
      expect(mutations, 0);
    });
  }
}
