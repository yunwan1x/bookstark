import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/profile_repository.dart';

Map<String, Object?> profile({int id = 7, String home = 'notes'}) => {
  'member_id': id,
  'account': 'profile-fixture',
  'email': 'old@example.test',
  'role': 1,
  'default_home': home,
};
http.Response data(Map<String, Object?> row) => http.Response.bytes(
  utf8.encode(jsonEncode({'code': 0, 'data': row})),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
void main() {
  test(
    'profile is current-member bound; exact owner GET and PUT save only real email/default fields',
    () async {
      var writes = 0;
      final client = BookstarkClient(
        'https://example.test/base',
        transport: MockClient((r) async {
          expect(r.url.path, '/base/api/profile');
          expect(r.url.hasQuery, isFalse);
          expect(r.followRedirects, isFalse);
          expect(r.headers['cache-control'], 'no-store');
          if (r.method == 'GET') {
            return data(profile());
          }
          writes++;
          expect(r.method, 'PUT');
          expect(r.headers['x-csrf-token'], 'csrf');
          expect(jsonDecode(r.body), {
            'email': 'new@example.test',
            'default_home': 'books',
          });
          return http.Response(
            '{"code":0,"message":"updated"}',
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      )..restoreSession({'token': 'fixture-session', 'csrf_token': 'csrf'});
      final repo = RemoteProfileRepository(client, memberId: 7),
          draft = ProfileDraft(
            email: ' new@example.test ',
            defaultHome: 'books',
          );
      await expectLater(repo.update(draft), throwsStateError);
      expect(writes, 0);
      expect((await repo.read()).account, 'profile-fixture');
      await repo.update(draft);
      expect(writes, 1);
      client.close();
    },
  );
  test(
    'changed member, unknown module and invalid role are rejected without normalizing or writing',
    () async {
      var variant = 0;
      final client = BookstarkClient(
        'https://example.test',
        transport: MockClient((r) async {
          expect(r.method, 'GET');
          variant++;
          return data(
            variant == 1
                  ? profile(id: 8)
                  : variant == 2
                  ? profile(home: 'invented')
                  : profile()
              ..['role'] = 9,
          );
        }),
      );
      final repo = RemoteProfileRepository(client, memberId: 7);
      for (var i = 0; i < 3; i++) {
        await expectLater(repo.read(), throwsFormatException);
      }
      client.close();
    },
  );
  test(
    'session change after verified read blocks update before request',
    () async {
      var calls = 0;
      final client = BookstarkClient(
        'https://example.test',
        transport: MockClient((r) async {
          calls++;
          return data(profile());
        }),
      )..restoreSession({'token': 'first-fixture', 'csrf_token': 'csrf'});
      final repo = RemoteProfileRepository(client, memberId: 7);
      await repo.read();
      client.restoreSession({'token': 'second-fixture', 'csrf_token': 'csrf'});
      await expectLater(
        repo.update(
          ProfileDraft(email: 'new@example.test', defaultHome: 'home'),
        ),
        throwsStateError,
      );
      expect(calls, 1);
      client.close();
    },
  );
  test('updates enforce real email byte limit, Unicode and known modules', () {
    ProfileDraft(email: 'person@example.test', defaultHome: 'home').validate();
    for (final draft in [
      ProfileDraft(email: '', defaultHome: 'home'),
      ProfileDraft(email: 'x@example.test', defaultHome: 'invented'),
      ProfileDraft(email: '${'中' * 70}@example.test', defaultHome: 'home'),
      ProfileDraft(
        email: '${String.fromCharCode(0xd800)}@example.test',
        defaultHome: 'home',
      ),
    ]) {
      expect(draft.validate, throwsFormatException);
    }
  });
  test(
    'malformed update receipt is unknown rather than fabricated success',
    () async {
      final client = BookstarkClient(
        'https://example.test',
        transport: MockClient(
          (r) async => r.method == 'GET' ? data(profile()) : data({}),
        ),
      )..restoreSession({'csrf_token': 'csrf'});
      final repo = RemoteProfileRepository(client, memberId: 7);
      await repo.read();
      await expectLater(
        repo.update(
          ProfileDraft(email: 'new@example.test', defaultHome: 'notes'),
        ),
        throwsFormatException,
      );
      client.close();
    },
  );
  testWidgets(
    'stalled profile mutation aborts at45 seconds without any repeated PUT',
    (tester) async {
      final stream = StreamController<List<int>>();
      Future<void>? abort;
      var calls = 0;
      final client = BookstarkClient(
        'https://example.test',
        transport: MockClient.streaming((request, _) async {
          calls++;
          if (request is http.AbortableRequest) {
            abort = request.abortTrigger;
          }
          return http.StreamedResponse(
            stream.stream,
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      )..restoreSession({'csrf_token': 'csrf'});
      final pending = client.profileSettingsJson(
        update: true,
        body: {'email': 'new@example.test', 'default_home': 'notes'},
      );
      final done = expectLater(pending, throwsA(isA<TimeoutException>()));
      await tester.pump();
      expect(abort, isNotNull);
      var cancelled = false;
      abort!.then((_) {
        cancelled = true;
      });
      await tester.pump(const Duration(seconds: 46));
      await done;
      expect(cancelled, isTrue);
      expect(calls, 1);
      await stream.close();
      client.close();
    },
  );
}
