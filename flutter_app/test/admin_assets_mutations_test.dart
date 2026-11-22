import 'dart:async';
import 'dart:convert';
import 'package:bookstark_flutter/features/admin/admin_asset_models.dart';
import 'package:bookstark_flutter/features/admin/admin_asset_drafts.dart';
import 'package:bookstark_flutter/features/admin/admin_assets_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'admin_assets_repository_test.dart' as fixture;

class Harness extends fixture.Harness {
  final writes = <http.Request>[];
  final events = <String>[];
  int writeStatus = 200;
  bool lost = false,
      malformedAck = false,
      changedHost = false,
      changedCredential = false,
      wrongUpdateId = false,
      reusedCreateId = false;
  Completer<void>? writeGate;
  final writeReached = Completer<void>();
  @override
  Future<http.Response> handle(http.Request request) async {
    final path = request.url.path;
    if (request.method == 'GET') {
      if (path.endsWith('/ssh-hosts') && changedHost) {
        calls.add(request);
        return reply({
          'code': 0,
          'data': [
            fixture.host(5)..['modify_time'] = '2026-11-07T00:00:00.123456788Z',
          ],
        }, 200);
      }
      if (path.endsWith('/credentials') && changedCredential) {
        calls.add(request);
        return reply({
          'code': 0,
          'data': [
            fixture.credential(9)
              ..['modify_time'] = '2026-11-07T00:00:00.123456788Z',
          ],
        }, 200);
      }
      return super.handle(request);
    }
    calls.add(request);
    writes.add(request);
    events.add('write');
    if (!writeReached.isCompleted) writeReached.complete();
    if (writeGate != null) await writeGate!.future;
    if (lost) throw http.ClientException('owned private transport fault');
    if (writeStatus != 200) {
      return reply({'code': 1, 'message': 'owned-private-error'}, writeStatus);
    }
    if (malformedAck) {
      return reply({
        'code': 0,
        'data': {'id': 0},
      }, 200);
    }
    if (path.endsWith('/test')) {
      return reply({
        'code': 0,
        'data': {
          'status': 'offline',
          'checked_at': '2026-11-07T01:00:00.123456789Z',
          'message':
              'dial owned target: connection refused; owned-private-detail',
        },
      }, 200);
    }
    if (request.method == 'DELETE') {
      return reply({'code': 0, 'message': 'owned receipt'}, 200);
    }
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    if (path.contains('/ssh-hosts')) {
      final id = request.method == 'POST'
          ? (reusedCreateId ? 5 : 13)
          : (wrongUpdateId ? 999 : 5);
      return reply({
        'code': 0,
        'data': {...fixture.host(id), ...body},
      }, 200);
    }
    if (path.contains('/credentials')) {
      final id = request.method == 'POST'
          ? (reusedCreateId ? 9 : 10)
          : (wrongUpdateId ? 999 : 9);
      final data = {...fixture.credential(id), ...body};
      if (body['credential'] == '') {
        data['credential'] = fixture.credential(id)['credential'];
      }
      return reply({'code': 0, 'data': data}, 200);
    }
    throw StateError('Unexpected owned mutation route');
  }
}

const draft = AdminAssetCredentialDraft(
  name: ' owned credential ',
  username: ' fixture-user ',
  auth: AdminAssetAuth.password,
);
Future<void> failure(
  Future<Object?> Function() action,
  TypeMatcher<Object> matcher,
) => expectLater(Future<Object?>.sync(action), throwsA(matcher));
void main() {
  late Harness h;
  setUp(() {
    h = Harness();
  });
  tearDown(() {
    h.close();
  });

  test(
    'credential creation uses POST and a genuinely new acknowledged ID, never a same-name upsert',
    () async {
      final result = await h.repo.createCredential(
        fixture.owner,
        draft,
        ' owned replacement ',
      );
      expect(result.id, 10);
      expect(h.writes.single.method, 'POST');
      expect(
        (jsonDecode(h.writes.single.body) as Map)['credential'],
        ' owned replacement ',
      );
      expect(result.reviewFingerprint, isNot(contains('owned replacement')));
      expect(h.repo.reviewedCredentials, isNull);
    },
  );
  test(
    'same-name existing ID returned by create is unknown rather than silently adopted',
    () async {
      h.reusedCreateId = true;
      await failure(
        () =>
            h.repo.createCredential(fixture.owner, draft, 'owned replacement'),
        isA<AdminAssetWriteUnknown>(),
      );
      expect(h.writes, hasLength(1));
    },
  );
  test(
    'credential update keeps empty-marker secret only through explicit keep mode',
    () async {
      final reviewed = (await h.repo.readCredentials(fixture.owner)).single;
      final result = await h.repo.updateCredential(
        fixture.owner,
        reviewed,
        draft,
      );
      expect(result.id, 9);
      expect(h.writes.single.method, 'PUT');
      expect((jsonDecode(h.writes.single.body) as Map)['credential'], '');
    },
  );
  test(
    'changing authentication type requires a new secret before any HTTP',
    () async {
      final reviewed = (await h.repo.readCredentials(fixture.owner)).single;
      final before = h.calls.length;
      await failure(
        () => h.repo.updateCredential(
          fixture.owner,
          reviewed,
          const AdminAssetCredentialDraft(
            name: 'owned',
            username: 'fixture-user',
            auth: AdminAssetAuth.key,
          ),
        ),
        isA<AdminAssetDraftInvalid>(),
      );
      expect(h.calls, hasLength(before));
      expect(h.writes, isEmpty);
    },
  );
  test(
    'automatically cleared replacement cannot fall back to keeping the old secret',
    () async {
      final reviewed = (await h.repo.readCredentials(fixture.owner)).single;
      await failure(
        () => h.repo.updateCredential(
          fixture.owner,
          reviewed,
          draft,
          replacement: '',
        ),
        isA<AdminAssetDraftInvalid>(),
      );
      expect(h.writes, isEmpty);
    },
  );
  test(
    'actual submission clears UI buffer after encoding but before transport',
    () async {
      final reviewed = (await h.repo.readCredentials(fixture.owner)).single;
      var input = ' owned replacement \n';
      await h.repo.updateCredential(
        fixture.owner,
        reviewed,
        draft,
        replacement: input,
        onSubmitted: () {
          input = '';
          h.events.add('submitted');
        },
      );
      expect(input, isEmpty);
      expect(h.events, ['submitted', 'write']);
      expect(
        (jsonDecode(h.writes.single.body) as Map)['credential'],
        ' owned replacement \n',
      );
    },
  );
  test('unreviewed deletion is rejected before even profile HTTP', () async {
    final value = AdminAssetCredentialMetadata.parse(fixture.credential(9));
    await failure(
      () => h.repo.deleteCredential(fixture.owner, value),
      isA<AdminAssetTargetChanged>(),
    );
    expect(h.calls, isEmpty);
  });
  test(
    'nanosecond-only credential change prevents overwrite before submission',
    () async {
      final reviewed = (await h.repo.readCredentials(fixture.owner)).single;
      h.changedCredential = true;
      var submitted = false;
      await failure(
        () => h.repo.updateCredential(
          fixture.owner,
          reviewed,
          draft,
          replacement: 'owned replacement',
          onSubmitted: () {
            submitted = true;
          },
        ),
        isA<AdminAssetTargetChanged>(),
      );
      expect(submitted, false);
      expect(h.writes, isEmpty);
    },
  );
  test(
    'fresh demotion blocks mutation and callback before any asset write',
    () async {
      final reviewed = (await h.repo.readCredentials(fixture.owner)).single;
      h.role = 1;
      var submitted = false;
      await failure(
        () => h.repo.updateCredential(
          fixture.owner,
          reviewed,
          draft,
          replacement: 'owned replacement',
          onSubmitted: () {
            submitted = true;
          },
        ),
        isA<AdminAssetOwnerLost>(),
      );
      expect(submitted, false);
      expect(h.writes, isEmpty);
      expect(h.repo.reviewedCredentials, isNull);
    },
  );
  test(
    'lost creation reply does not automatically GET, retry or claim a new ID',
    () async {
      h.lost = true;
      await failure(
        () =>
            h.repo.createCredential(fixture.owner, draft, 'owned replacement'),
        isA<AdminAssetWriteUnknown>(),
      );
      expect(h.writes, hasLength(1));
      expect(h.calls.last.method, 'POST');
      h.lost = false;
      await h.repo.readCredentials(fixture.owner);
      expect(h.writes, hasLength(1));
    },
  );
  for (final status in [400, 404, 429]) {
    test(
      'explicit refusal status $status is distinct from unknown outcome',
      () async {
        final reviewed = (await h.repo.readCredentials(fixture.owner)).single;
        h.writeStatus = status;
        await expectLater(
          h.repo.deleteCredential(fixture.owner, reviewed),
          throwsA(
            isA<AdminAssetOperationRefused>().having(
              (e) => e.status,
              'status',
              status,
            ),
          ),
        );
        expect(h.writes, hasLength(1));
      },
    );
  }
  test(
    'server500 after submission remains unknown without exposing upstream text',
    () async {
      final reviewed = (await h.repo.readCredentials(fixture.owner)).single;
      h.writeStatus = 500;
      await expectLater(
        h.repo.deleteCredential(fixture.owner, reviewed),
        throwsA(
          isA<AdminAssetWriteUnknown>().having(
            (e) => e.toString(),
            'redacted',
            isNot(contains('owned-private')),
          ),
        ),
      );
      expect(h.writes, hasLength(1));
    },
  );
  test(
    'malformed success or wrong update ID remains unknown and is not replayed',
    () async {
      final reviewed = (await h.repo.readCredentials(fixture.owner)).single;
      h.wrongUpdateId = true;
      await failure(
        () => h.repo.updateCredential(fixture.owner, reviewed, draft),
        isA<AdminAssetWriteUnknown>(),
      );
      expect(h.writes, hasLength(1));
    },
  );
  test(
    'concurrent mutations are singleflight and no shared catalog read begins mid-write',
    () async {
      final reviewed = (await h.repo.readCredentials(fixture.owner)).single;
      final gate = Completer<void>();
      h.profileGate = gate;
      final writing = h.repo.updateCredential(fixture.owner, reviewed, draft);
      try {
        await failure(
          () => h.repo.updateCredential(fixture.owner, reviewed, draft),
          isA<AdminAssetOperationBusy>(),
        );
        await failure(
          () => h.repo.readHosts(fixture.owner),
          isA<AdminAssetOperationBusy>(),
        );
      } finally {
        gate.complete();
      }
      await writing;
      expect(h.writes, hasLength(1));
    },
  );
  test(
    'session replacement after actual submission discards old acknowledgement',
    () async {
      final reviewed = (await h.repo.readCredentials(fixture.owner)).single;
      final gate = Completer<void>();
      h.writeGate = gate;
      final writing = h.repo.updateCredential(fixture.owner, reviewed, draft);
      await h.writeReached.future;
      final result = expectLater(writing, throwsA(isA<AdminAssetOwnerLost>()));
      h.client.restoreSession({'token': 'owned-next-session'});
      gate.complete();
      await result;
      expect(h.repo.reviewedCredentials, isNull);
      expect(h.writes, hasLength(1));
    },
  );
  test(
    'host creation uses a reviewed real credential and acknowledges only new host ID',
    () async {
      final chosen = (await h.repo.readCredentials(fixture.owner)).single;
      final existing = AdminAssetHostMetadata.parse(fixture.host(5));
      final result = await h.repo.createHost(
        fixture.owner,
        AdminAssetHostDraft.fromMetadata(existing),
        chosen,
      );
      expect(result.id, 13);
      expect(
        (jsonDecode(h.writes.single.body) as Map).containsKey('credential'),
        false,
      );
      expect(h.writes.single.method, 'POST');
    },
  );
  test(
    'host update cannot silently clear an independent credential to legacy ID0',
    () async {
      final reviewed = (await h.repo.readHosts(fixture.owner)).single;
      final value = AdminAssetHostDraft(
        name: reviewed.name,
        host: reviewed.host,
        port: reviewed.port,
        shell: reviewed.shell,
        cwd: reviewed.cwd,
        dockerSocket: reviewed.dockerSocket,
        credentialId: 0,
        username: reviewed.username,
        auth: reviewed.auth,
      );
      await failure(
        () => h.repo.updateHost(fixture.owner, reviewed, value),
        isA<AdminAssetDraftInvalid>(),
      );
      expect(h.writes, isEmpty);
    },
  );
  test('host changed immediately before delete is not deleted', () async {
    final reviewed = (await h.repo.readHosts(fixture.owner)).single;
    h.changedHost = true;
    await failure(
      () => h.repo.deleteHost(fixture.owner, reviewed),
      isA<AdminAssetTargetChanged>(),
    );
    expect(h.writes, isEmpty);
  });
  test(
    'delete receipt contains requested ID without inventing affected count',
    () async {
      final reviewed = (await h.repo.readHosts(fixture.owner)).single;
      final receipt = await h.repo.deleteHost(fixture.owner, reviewed);
      expect(receipt.requestedId, 5);
      expect(receipt.resource, 'ssh-hosts');
      expect(h.writes.single.method, 'DELETE');
    },
  );
  test(
    'only explicit connection action POSTs and returns controlled offline result',
    () async {
      final reviewed = (await h.repo.readHosts(fixture.owner)).single;
      expect(h.writes, isEmpty);
      final result = await h.repo.testHost(fixture.owner, reviewed);
      expect(
        h.writes.single.url.path,
        '/root/api/admin/assets/ssh-hosts/5/test',
      );
      expect(result.status, AdminAssetStatus.offline);
      expect(result.reason, AdminAssetConnectionReason.refused);
      expect(result.toString(), isNot(contains('owned-private-detail')));
      expect(h.writes, hasLength(1));
    },
  );
}
