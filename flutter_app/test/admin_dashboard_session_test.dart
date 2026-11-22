import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/features/admin/admin_dashboard_repository.dart';

void main() {
  test('changed dashboard owner blocks a request before dispatch', () async {
    var calls = 0;
    final client = BookstarkClient(
      'https://fixture.invalid',
      transport: MockClient((_) async {
        calls++;
        return http.Response(
          '{"code":0,"data":{"total_visits":1,"unique_ips":1}}',
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    client.restoreSession({'token': 'fixture-first'});
    final repository = AdminDashboardRepository(client);
    client.restoreSession({'token': 'fixture-second'});
    await expectLater(
      repository.stats(DashboardRange.days7),
      throwsA(isA<ApiFailure>().having((e) => e.status, 'status', 401)),
    );
    expect(calls, 0);
  });
  test('late dashboard data is discarded after session replacement', () async {
    final seen = Completer<void>();
    final receipt = Completer<http.Response>();
    final client = BookstarkClient(
      'https://fixture.invalid',
      transport: MockClient((_) async {
        seen.complete();
        return receipt.future;
      }),
    );
    client.restoreSession({'token': 'fixture-first'});
    final repository = AdminDashboardRepository(client);
    final request = repository.stats(DashboardRange.days7);
    final check = expectLater(
      request,
      throwsA(isA<ApiFailure>().having((e) => e.status, 'status', 401)),
    );
    await seen.future;
    client.restoreSession({'token': 'fixture-second'});
    receipt.complete(
      http.Response(
        '{"code":0,"data":{"total_visits":1,"unique_ips":1}}',
        200,
        headers: {'content-type': 'application/json'},
      ),
    );
    await check;
  });
}
