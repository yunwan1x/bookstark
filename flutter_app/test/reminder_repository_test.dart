import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/reminder_repository.dart';
import 'profile_repository_test.dart' as fixture;

Map<String, Object?> row() => {
  'enabled': false,
  'send_time': '09:00',
  'remind_before_days': 1,
  'include_overdue': true,
  'email': 'fixture@example.invalid',
  'available': false,
  'last_processed_date': '',
};
void main() {
  test(
    'fixed current member reminder GET PUT and test body use bounded same origin transport',
    () async {
      final paths = <String>[];
      var writes = 0, mails = 0;
      final client = BookstarkClient(
        'https://example.test/base',
        transport: MockClient((r) async {
          paths.add(r.url.path);
          expect(r.followRedirects, false);
          expect(r.headers['cache-control'], 'no-store');
          if (r.url.path == '/base/api/profile') {
            return fixture.data(fixture.profile());
          }
          if (r.method == 'GET') {
            return fixture.data(row());
          }
          expect(r.headers['x-csrf-token'], 'csrf');
          if (r.url.path.endsWith('/test')) {
            mails++;
            expect(jsonDecode(r.body), isEmpty);
          } else {
            writes++;
            expect(jsonDecode(r.body), {
              'enabled': false,
              'send_time': '23:59',
              'remind_before_days': 30,
              'include_overdue': false,
            });
          }
          return http.Response(
            '{"code":0,"message":"accepted"}',
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      )..restoreSession({'token': 'fixture', 'csrf_token': 'csrf'});
      final repo = RemoteReminderRepository(client, memberId: 7);
      const desired = ReminderDraft(
        enabled: false,
        sendTime: '23:59',
        days: 30,
        overdue: false,
      );
      await expectLater(
        repo.update(desired),
        throwsA(isA<ReminderPreflightFailure>()),
      );
      await repo.read();
      await repo.update(desired);
      await repo.sendTest('fixture@example.invalid');
      expect([writes, mails], [1, 1]);
      expect(paths.every((p) => p.startsWith('/base/api/profile')), true);
      client.close();
    },
  );
  test(
    'recipient change and different member block test mail before any POST',
    () async {
      for (final wrongMember in [false, true]) {
        var mails = 0;
        final client = BookstarkClient(
          'https://example.test',
          transport: MockClient((r) async {
            if (r.method == 'POST') {
              mails++;
            }
            return fixture.data(
              r.url.path == '/api/profile'
                  ? fixture.profile(id: wrongMember ? 8 : 7)
                  : row(),
            );
          }),
        );
        final repo = RemoteReminderRepository(client, memberId: 7);
        await expectLater(
          repo.sendTest('different@example.invalid'),
          throwsA(isA<ReminderPreflightFailure>()),
        );
        expect(mails, 0);
        client.close();
      }
    },
  );
  test('strict reminder payload rejects invalid types and ranges', () async {
    for (final entry in <MapEntry<String, Object?>>[
      const MapEntry('enabled', 1),
      const MapEntry('send_time', '24:00'),
      const MapEntry('remind_before_days', 31),
      const MapEntry('include_overdue', 'true'),
      const MapEntry('available', null),
      const MapEntry('last_processed_date', 'unknown'),
    ]) {
      final client = BookstarkClient(
        'https://example.test',
        transport: MockClient(
          (r) async => fixture.data(
            r.url.path == '/api/profile'
                ? fixture.profile()
                : (row()..[entry.key] = entry.value),
          ),
        ),
      );
      await expectLater(
        RemoteReminderRepository(client, memberId: 7).read(),
        throwsFormatException,
      );
      client.close();
    }
  });
  test(
    'session switch after identity verification blocks preference mutation',
    () async {
      var writes = 0;
      final client = BookstarkClient(
        'https://example.test',
        transport: MockClient((r) async {
          if (r.method == 'PUT') {
            writes++;
          }
          return fixture.data(
            r.url.path == '/api/profile' ? fixture.profile() : row(),
          );
        }),
      )..restoreSession({'token': 'first', 'csrf_token': 'csrf'});
      final repo = RemoteReminderRepository(client, memberId: 7);
      await repo.read();
      client.restoreSession({'token': 'second', 'csrf_token': 'csrf'});
      await expectLater(
        repo.update(
          const ReminderDraft(
            enabled: false,
            sendTime: '10:00',
            days: 0,
            overdue: false,
          ),
        ),
        throwsA(isA<ReminderPreflightFailure>()),
      );
      expect(writes, 0);
      client.close();
    },
  );
}
