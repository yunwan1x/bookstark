import 'package:flutter_test/flutter_test.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/features/admin/admin_settings_repository.dart';
import 'package:bookstark_flutter/features/admin/admin_members_models.dart';
import 'package:bookstark_flutter/features/admin/admin_members_repository.dart';

const owner = AdminPrincipal(memberId: 1, account: 'owner-fixture', role: 0);
void check(bool value, String label) {
  expect(value, isTrue, reason: label);
}

Future<T> fails<T>(Future<dynamic> Function() call) async {
  try {
    await call();
  } catch (error) {
    check(error is T, 'expected error type');
    return error as T;
  }
  throw StateError('Expected member contract refusal');
}

http.Response response(Object? body, [int status = 200]) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
Map<String, Object?> row(int id, int role, int status) => {
  'member_id': id,
  'account': id == 1 ? 'owner-fixture' : 'member-fixture',
  'role': role,
  'status': status,
  'create_time': '2026-11-07T08:00:00+08:00',
  'create_at': 1794009600,
  'last_login_time': null,
  'email': '',
  'default_home': '',
};

class Harness {
  Harness() {
    client = BookstarkClient(
      'https://example.invalid/root',
      transport: MockClient(handle),
    );
    client.restoreSession({
      'token': 'owned-fixture-token',
      'csrf_token': 'owned-fixture-csrf',
    });
    repo = AdminMembersRepository(client);
  }
  late final BookstarkClient client;
  late final AdminMembersRepository repo;
  final calls = <http.Request>[];
  int ownerRole = 0, memberRole = 1, memberStatus = 1, putStatus = 200;
  bool losePutReply = false,
      badReceipt = false,
      csrfFail = false,
      profileFault = false,
      swapOnList = false,
      demoteOnPut = false;
  int get puts => calls.where((r) => r.method == 'PUT').length;
  Future<http.Response> handle(http.Request request) async {
    calls.add(request);
    final path = request.url.path;
    if (path.endsWith('/api/profile')) {
      if (profileFault) {
        throw http.ClientException('owned fixture preflight fault');
      }
      return response({
        'code': 0,
        'data': {'member_id': 1, 'account': 'owner-fixture', 'role': ownerRole},
      });
    }
    if (path.endsWith('/api/admin/members')) {
      if (swapOnList) {
        client.restoreSession({
          'token': 'replacement-fixture',
          'csrf_token': 'owned-fixture-csrf',
        });
      }
      final page = int.parse(request.url.queryParameters['page']!);
      return response({
        'code': 0,
        'data': [row(1, 0, 1), row(2, memberRole, memberStatus)],
        'page': page,
        'page_size': 20,
        'total': 2,
        'total_pages': 1,
      });
    }
    if (path.endsWith('/api/csrf-token')) {
      return response({
        'code': csrfFail ? 503 : 0,
        'data': {'csrf_token': 'owned-fixture-csrf'},
      }, csrfFail ? 503 : 200);
    }
    if (request.method == 'PUT' && path.contains('/api/admin/members/')) {
      if (demoteOnPut) ownerRole = 1;
      if (losePutReply) throw http.ClientException('owned fixture lost reply');
      if (putStatus != 200) {
        return response({
          'code': putStatus,
          'message': 'owned refusal',
        }, putStatus);
      }
      return response(badReceipt ? {'code': 0} : {'code': 0, 'message': '完成'});
    }
    throw StateError('Unexpected fixed member route');
  }

  Future<AdminMemberRecord> reviewed() async =>
      (await repo.read(owner, 1)).items.last;
  void close() {
    repo.dispose();
    client.close();
  }
}

void main() {
  test('fixed list namespace and page20 without unsupported query', () async {
    final h = Harness();
    await h.reviewed();
    final request = h.calls.last;
    check(request.url.path == '/root/api/admin/members', 'base path preserved');
    check(
      request.url.queryParameters.length == 2 &&
          request.url.queryParameters['pageSize'] == '20',
      'fixed page query',
    );
    check(!request.followRedirects, 'administrator redirects disabled');
    h.close();
  });
  test('fresh target approval sends one bodyless CSRF PUT', () async {
    final h = Harness();
    h.memberStatus = 0;
    final target = await h.reviewed();
    await h.repo.write(owner, target, AdminMemberAction.approve);
    final request = h.calls.last;
    check(
      h.puts == 1 && request.url.path.endsWith('/members/2/approve'),
      'exact approval route',
    );
    check(
      request.body.isEmpty &&
          request.headers['x-csrf-token'] == 'owned-fixture-csrf',
      'bodyless and CSRF',
    );
    await fails<StateError>(
      () => h.repo.write(owner, target, AdminMemberAction.approve),
    );
    check(h.puts == 1, 'old reviewed list cannot silently write again');
    h.close();
  });
  test('changed reviewed target stops before mutation', () async {
    final h = Harness();
    final target = await h.reviewed();
    h.memberStatus = 0;
    await fails<AdminMemberTargetChanged>(
      () => h.repo.write(owner, target, AdminMemberAction.reject),
    );
    check(h.puts == 0, 'changed target no PUT');
    h.close();
  });
  test('own role change is refused before preflight or PUT', () async {
    final h = Harness();
    final self = (await h.repo.read(owner, 1)).items.first;
    final before = h.calls.length;
    await fails<FormatException>(
      () => h.repo.write(
        owner,
        self,
        AdminMemberAction.role,
        newRole: AdminMemberRole.member,
      ),
    );
    check(h.calls.length == before, 'self role no request');
    h.close();
  });
  test(
    'reset preserves exact password and has no implicit followup mutation',
    () async {
      final h = Harness();
      final target = await h.reviewed();
      const password = ' owned fixture ';
      final receipt = await h.repo.write(
        owner,
        target,
        AdminMemberAction.resetPassword,
        newPassword: password,
      );
      check(
        receipt.action == AdminMemberAction.resetPassword,
        'real receipt kind',
      );
      check(
        jsonDecode(h.calls.last.body)['new_password'] == password,
        'password bytes not trimmed',
      );
      check(h.puts == 1, 'one reset');
      h.close();
    },
  );
  test('pending target password reset is refused without I/O', () async {
    final h = Harness();
    h.memberStatus = 0;
    final target = await h.reviewed();
    final before = h.calls.length;
    await fails<FormatException>(
      () => h.repo.write(
        owner,
        target,
        AdminMemberAction.resetPassword,
        newPassword: 'abcdef',
      ),
    );
    check(h.calls.length == before, 'pending target no request');
    h.close();
  });
  test('preflight transport failure is not an unknown write', () async {
    final h = Harness();
    final target = await h.reviewed();
    h.profileFault = true;
    await fails<http.ClientException>(
      () => h.repo.write(owner, target, AdminMemberAction.approve),
    );
    check(h.puts == 0, 'preflight no PUT');
    h.close();
  });
  test('CSRF failure does not signal mutation submission', () async {
    final h = Harness();
    h.client.restoreSession({'token': 'owned-fixture-token'});
    h.csrfFail = true;
    final target = await h.reviewed();
    bool submitted = false;
    await fails<ApiFailure>(
      () => h.repo.write(
        owner,
        target,
        AdminMemberAction.approve,
        onSubmitted: () {
          submitted = true;
        },
      ),
    );
    check(!submitted && h.puts == 0, 'CSRF failure before submission');
    h.close();
  });
  test('lost PUT reply is unknown and read never replays it', () async {
    final h = Harness();
    final target = await h.reviewed();
    h.losePutReply = true;
    bool submitted = false;
    await fails<AdminMemberWriteUnknown>(
      () => h.repo.write(
        owner,
        target,
        AdminMemberAction.reject,
        onSubmitted: () {
          submitted = true;
        },
      ),
    );
    check(submitted && h.puts == 1, 'one potentially submitted PUT');
    await h.repo.read(owner, 1);
    check(h.puts == 1, 'GET review no replay');
    h.close();
  });
  test('malformed successful receipt stays unknown', () async {
    final h = Harness();
    final target = await h.reviewed();
    h.badReceipt = true;
    await fails<AdminMemberWriteUnknown>(
      () => h.repo.write(owner, target, AdminMemberAction.approve),
    );
    check(h.puts == 1, 'malformed receipt no replay');
    h.close();
  });
  test('HTTP400 is an operation refusal', () async {
    final h = Harness();
    final target = await h.reviewed();
    h.putStatus = 400;
    final error = await fails<AdminMemberOperationRefused>(
      () => h.repo.write(owner, target, AdminMemberAction.reject),
    );
    check(error.status == 400 && h.puts == 1, 'known refusal');
    h.close();
  });
  test(
    'role403 verifies operator before protected-target classification',
    () async {
      final h = Harness();
      final target = await h.reviewed();
      h.putStatus = 403;
      final error = await fails<AdminMemberOperationRefused>(
        () => h.repo.write(
          owner,
          target,
          AdminMemberAction.role,
          newRole: AdminMemberRole.administrator,
        ),
      );
      check(error.protectedTarget && h.puts == 1, 'protected target refusal');
      check(
        h.calls.where((r) => r.url.path.endsWith('/api/profile')).length == 3,
        'fresh operator profile after403',
      );
      h.close();
    },
  );
  test('role403 with actual owner demotion remains ownership loss', () async {
    final h = Harness();
    final target = await h.reviewed();
    h.putStatus = 403;
    h.demoteOnPut = true;
    await fails<StateError>(
      () => h.repo.write(
        owner,
        target,
        AdminMemberAction.role,
        newRole: AdminMemberRole.administrator,
      ),
    );
    check(h.puts == 1, 'no retry after owner loss');
    h.close();
  });
  test('session replacement during fresh target read blocks PUT', () async {
    final h = Harness();
    final target = await h.reviewed();
    h.swapOnList = true;
    await fails<StateError>(
      () => h.repo.write(owner, target, AdminMemberAction.approve),
    );
    check(h.puts == 0, 'stale token cannot mutate');
    h.close();
  });
  test('unsupported direct mutation arguments send no request', () async {
    final h = Harness();
    await fails<FormatException>(
      () => h.client.adminMemberActionJson(2, action: 'delete'),
    );
    await fails<FormatException>(
      () => h.client.adminMemberActionJson(
        2,
        action: 'approve',
        password: 'abcdef',
      ),
    );
    await fails<FormatException>(
      () => h.client.adminMemberActionJson(2, action: 'role', role: 3),
    );
    check(h.calls.isEmpty, 'allowlist before I/O');
    h.close();
  });
  test('missing session clears cached reviewed authority', () async {
    final h = Harness();
    final target = await h.reviewed();
    h.client.restoreSession({});
    await fails<StateError>(() => h.repo.read(owner, 1));
    h.client.restoreSession({
      'token': 'owned-fixture-token',
      'csrf_token': 'owned-fixture-csrf',
    });
    await fails<StateError>(
      () => h.repo.write(owner, target, AdminMemberAction.approve),
    );
    check(h.puts == 0, 'logout cannot reuse cached reviewed authority');
    h.close();
  });
  test('disposed repository cannot write reviewed target', () async {
    final h = Harness();
    final target = await h.reviewed();
    h.repo.dispose();
    await fails<StateError>(
      () => h.repo.write(owner, target, AdminMemberAction.approve),
    );
    check(h.puts == 0, 'disposed repository no PUT');
    h.close();
  });
}
