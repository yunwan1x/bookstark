import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/note_pin_actions.dart';
import 'package:bookstark_flutter/core/note_list_selection_controller.dart';

void main() {
  const member = 7;
  Map<String, Object?> metadata(
    int id, {
    int owner = member,
    int pin = 0,
    int visibility = 0,
    String type = 'note',
  }) => {
    'blog_id': id,
    'member_id': owner,
    'blog_type': type,
    'editor_type': 'markdown',
    'is_pinned': pin,
    'visibility': visibility,
    'blog_content': '\uFEFFLarge body discarded by the metadata parser',
  };
  http.Response reply(Object data, {int status = 200}) => http.Response(
    jsonEncode({'code': 0, 'data': data}),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
  BookstarkClient client(Future<http.Response> Function(http.Request) handler) {
    final client = BookstarkClient(
      'https://owned.invalid/prefix',
      transport: MockClient(handler),
    );
    client.restoreSession({
      'token': 'fixture-token',
      'csrf_token': 'fixture-csrf',
    });
    return client;
  }

  NotePinActions actions(
    BookstarkClient client, {
    bool Function()? current,
    String scope = 'owned/server/member7',
  }) => NotePinActions(
    client: client,
    memberId: member,
    scope: scope,
    isCurrent: current,
  );
  test('same desired state uses one bounded GET and never toggles', () async {
    final requests = <String>[];
    final c = client((request) async {
      requests.add(request.method);
      return reply(metadata(19, pin: 1));
    });
    final result = await actions(c).setPinned(19, true);
    expect(result.confirmed, true);
    expect(result.mutationAttempted, false);
    expect(result.observed!.memberId, member);
    expect(requests, ['GET']);
  });
  test(
    'one real PATCH with existing CSRF client and path prefix then fresh GET verifies',
    () async {
      var pinned = false;
      final requests = <String>[];
      final c = client((request) async {
        requests.add('${request.method} ${request.url.path}');
        expect(
          request.headers['x-csrf-token'],
          request.method == 'PATCH' ? 'fixture-csrf' : isNull,
        );
        if (request.method == 'PATCH') {
          expect(request.url.path, '/prefix/api/blogs/19/pin');
          expect(jsonDecode(request.body), isEmpty);
          pinned = !pinned;
          return reply({'is_pinned': pinned});
        }
        return reply(metadata(19, pin: pinned ? 1 : 0));
      });
      final result = await actions(c).setPinned(19, true);
      expect(result.confirmed, true);
      expect(result.mutationAttempted, true);
      expect(requests, [
        'GET /prefix/api/blogs/19',
        'PATCH /prefix/api/blogs/19/pin',
        'GET /prefix/api/blogs/19',
      ]);
    },
  );
  test(
    'applied toggle with dropped response is only read back and never replayed',
    () async {
      var pinned = false, patches = 0, reads = 0;
      final c = client((request) async {
        if (request.method == 'PATCH') {
          patches++;
          pinned = true;
          throw TimeoutException('dropped owned response');
        }
        reads++;
        return reply(metadata(19, pin: pinned ? 1 : 0));
      });
      final result = await actions(c).setPinned(19, true);
      expect(result.confirmed, true);
      expect(result.recoveredAfterFailure, true);
      expect(patches, 1);
      expect(reads, 2);
    },
  );
  test(
    'unknown after lost write and failed reread is honest and does not toggle twice',
    () async {
      var patches = 0, reads = 0;
      final c = client((request) async {
        if (request.method == 'PATCH') {
          patches++;
          throw TimeoutException('unknown');
        }
        if (++reads == 2) throw StateError('read unavailable');
        return reply(metadata(19));
      });
      final result = await actions(c).setPinned(19, true);
      expect(result.confirmed, false);
      expect(result.observed, isNull);
      expect(result.issue, NoteActionIssue.unknown);
      expect(patches, 1);
      expect(reads, 2);
    },
  );
  test(
    'admin-readable foreign owner and wrong note type are not writable',
    () async {
      var patches = 0;
      for (final row in [
        metadata(19, owner: 99),
        metadata(19, type: 'article'),
      ]) {
        final c = client((request) async {
          if (request.method == 'PATCH') patches++;
          return reply(row);
        });
        await expectLater(
          actions(c).setPinned(19, true),
          throwsA(isA<NoteActionUnavailable>()),
        );
      }
      expect(patches, 0);
    },
  );
  test(
    'current Go missing flags fails closed rather than assuming unpinned or private',
    () async {
      final row = metadata(19)
        ..remove('visibility')
        ..remove('is_pinned');
      final requests = <String>[];
      final c = client((request) async {
        requests.add(request.method);
        return reply(row);
      });
      await expectLater(
        actions(c).setPinned(19, true),
        throwsA(
          isA<NoteActionUnavailable>().having(
            (e) => e.issue,
            'issue',
            NoteActionIssue.invalidMetadata,
          ),
        ),
      );
      expect(requests, ['GET']);
    },
  );
  test(
    'visibility response does not override a conflicting fresh actual state',
    () async {
      var patches = 0;
      final c = client((request) async {
        if (request.method == 'PATCH') {
          patches++;
          expect(request.url.path.endsWith('/visibility'), true);
          return reply({'visibility': 1});
        }
        return reply(metadata(19, visibility: 0));
      });
      final result = await actions(c).setPublic(19, true);
      expect(result.confirmed, false);
      expect(result.observed!.isPublic, false);
      expect(result.issue, NoteActionIssue.unconfirmed);
      expect(patches, 1);
    },
  );
  test(
    'known forbidden mutation is not turned into success or another toggle',
    () async {
      final requests = <String>[];
      final c = client((request) async {
        requests.add(request.method);
        if (request.method == 'PATCH') return reply({}, status: 403);
        return reply(metadata(19));
      });
      await expectLater(
        actions(c).setPinned(19, true),
        throwsA(isA<ApiFailure>()),
      );
      expect(requests, ['GET', 'PATCH']);
    },
  );
  test(
    'scope retirement after fresh read prevents PATCH and cross-owner duplicate IDs lock',
    () async {
      var current = true, patches = 0;
      final c = client((request) async {
        if (request.method == 'PATCH') patches++;
        current = false;
        return reply(metadata(19));
      });
      await expectLater(
        actions(c, current: () => current).setPinned(19, true),
        throwsA(isA<NoteActionScopeRetired>()),
      );
      expect(patches, 0);
      final started = Completer<void>(), release = Completer<http.Response>();
      final c2 = client((request) {
        started.complete();
        return release.future;
      });
      final first = actions(c2, scope: 'shared-lock');
      final next = first.setPinned(19, true);
      await started.future;
      await expectLater(
        actions(c2, scope: 'shared-lock').setPinned(19, true),
        throwsA(isA<NoteActionBusy>()),
      );
      release.complete(reply(metadata(19, pin: 1)));
      expect((await next).confirmed, true);
    },
  );
  test(
    'batch freezes explicit IDs, owner verifies, affected alone never proves each item',
    () async {
      final selected = [2, 1, 2], posts = <List<dynamic>>[];
      final reads = <int, int>{};
      final firstRead = Completer<void>(), continueRead = Completer<void>();
      final c = client((request) async {
        if (request.method == 'POST') {
          posts.add((jsonDecode(request.body) as Map)['ids'] as List);
          return reply({'affected': 2});
        }
        final id = int.parse(request.url.pathSegments.last);
        reads[id] = (reads[id] ?? 0) + 1;
        if (id == 2 && reads[id] == 1) {
          firstRead.complete();
          await continueRead.future;
        }
        return reply(metadata(id, pin: id == 1 && reads[id]! > 1 ? 1 : 0));
      });
      final future = actions(c).pinSelected(selected);
      await firstRead.future;
      selected.add(999);
      continueRead.complete();
      final result = await future;
      expect(posts, [
        [1, 2],
      ]);
      expect(reads.containsKey(999), false);
      expect(result.affected, 2);
      expect(result.verifiedIds, {1});
      expect(result.remainingIds, {2});
      expect(result.issues[2], NoteActionIssue.unconfirmed);
    },
  );
  test(
    'batch partial owner filtering and failed offscreen IDs preserve selection',
    () async {
      final selection = NoteListSelectionController(
        scope: 'owned/server/member7',
      )..selectLoaded([1, 2, 3]);
      final snapshot = selection.capture();
      var posted = false;
      final requests = <String>[];
      final c = client((request) async {
        requests.add('${request.method} ${request.url.path}');
        if (request.method == 'POST') {
          expect((jsonDecode(request.body) as Map)['ids'], [1, 2]);
          posted = true;
          return reply({'affected': 1});
        }
        final id = int.parse(request.url.pathSegments.last);
        return reply(
          metadata(
            id,
            owner: id == 3 ? 99 : member,
            pin: posted && id == 1 ? 1 : 0,
          ),
        );
      });
      final result = await actions(c).pinSelected(snapshot.ids);
      selection.reconcile(snapshot, verifiedIds: result.verifiedIds);
      expect(selection.selectedIds, {2, 3});
      expect(selection.offscreenCount([1, 2]), 1);
      expect(result.issues[3], NoteActionIssue.notOwner);
      expect(result.issues[2], NoteActionIssue.unconfirmed);
      expect(requests.where((r) => r.startsWith('POST')).length, 1);
    },
  );
  test(
    'batch already-pinned entries need no POST and expired metadata never writes',
    () async {
      var posts = 0;
      final c = client((request) async {
        if (request.method == 'POST') posts++;
        return reply(
          metadata(int.parse(request.url.pathSegments.last), pin: 1),
        );
      });
      final result = await actions(c).pinSelected([8, 9]);
      expect(result.verifiedIds, {8, 9});
      expect(result.mutationAttempted, false);
      expect(posts, 0);
      final expired = client((request) async {
        if (request.method == 'POST') posts++;
        return reply({}, status: 401);
      });
      await expectLater(
        actions(expired).pinSelected([8, 9]),
        throwsA(isA<ApiFailure>()),
      );
      expect(posts, 0);
    },
  );
}
