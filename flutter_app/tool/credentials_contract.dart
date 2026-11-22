import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/api_tokens_repository.dart';
import 'package:bookstark_flutter/core/api_tokens_controller.dart';
import 'package:bookstark_flutter/core/webdav_password_repository.dart';
import 'package:bookstark_flutter/core/webdav_password_controller.dart';
import 'package:bookstark_flutter/core/profile_repository.dart';

void check(bool condition, String reason) {
  if (!condition) {
    throw StateError(reason);
  }
}

class LostCredentialReceipt extends http.BaseClient {
  LostCredentialReceipt(this.path);
  final String path;
  final _transport = http.Client();
  bool drop = true;
  int writes = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final matching = request.method == 'POST' && request.url.path == path;
    if (matching) {
      writes++;
    }
    final response = await _transport.send(request);
    if (matching && drop) {
      drop = false;
      await readBoundedResponse(response, maxBytes: 128 * 1024);
      throw TimeoutException('Owned fixture deliberately discarded receipt');
    }
    return response;
  }

  @override
  void close() => _transport.close();
}

Future<int> tokenAccess(BookstarkClient owner, String token) async {
  final transport = http.Client();
  try {
    final request = http.Request(
      'GET',
      owner.baseUri.replace(path: '${owner.baseUri.path}/api/profile'),
    )..followRedirects = false;
    request.headers['authorization'] = 'Token $token';
    final response = await transport.send(request);
    await readBoundedResponse(response, maxBytes: 128 * 1024);
    return response.statusCode;
  } finally {
    transport.close();
  }
}

Future<void> runCredentialsContract(
  BookstarkClient owner,
  int memberId,
  String loginPassword,
) async {
  final tokens = RemoteApiTokensRepository(owner, memberId: memberId);
  final cleanup = <ApiTokenEntry>[];
  try {
    check(
      (await tokens.read()).entries.isEmpty,
      'Empty fixture has no API tokens',
    );
    final first = await tokens.create(' API 原样 '),
        second = await tokens.create('other tool');
    cleanup.addAll([first.entry, second.entry]);
    check(
      first.entry.name == ' API 原样 ' &&
          first.entry.masked == maskApiToken(first.secret),
      'Actual nested token receipt preserves raw name and mask',
    );
    check(
      await tokenAccess(owner, first.secret) == 200,
      'Actual Token header authenticates current account',
    );
    await tokens.revoke(first.entry);
    check(
      (await tokens.read()).provesAbsent(first.entry.id),
      'Actual token DELETE is verified by uncapped list',
    );
    check(
      await tokenAccess(owner, first.secret) == 401,
      'Deleted token cached access is invalidated immediately',
    );
    check(
      await tokenAccess(owner, second.secret) == 200,
      'Independent token remains valid',
    );
    await tokens.revoke(second.entry);
    final transport = LostCredentialReceipt(
      '${owner.baseUri.path}/api/api-tokens',
    );
    final lostClient = BookstarkClient(
      owner.baseUri.toString(),
      transport: transport,
    )..restoreSession(owner.exportSession());
    final lostRepo = RemoteApiTokensRepository(lostClient, memberId: memberId),
        lost = ApiTokensController(
          RemoteApiTokensRepository(lostClient, memberId: memberId),
        );
    try {
      await lost.load();
      await lost.create('lost create');
      check(
        lost.phase == ApiTokenPhase.createUnknown && lost.created == null,
        'Lost actual create receipt cannot recover full secret',
      );
      await lost.create('must not repeat');
      check(
        transport.writes == 1,
        'Unknown actual token create never automatically repeats',
      );
      await lost.load();
      check(
        lost.page!.entries.length == 1 && lost.created == null,
        'Refresh returns only actual mask, not full token',
      );
      final observed = (await lostRepo.read()).entries.single;
      await lostRepo.revoke(observed);
    } finally {
      lost.dispose();
      lostRepo.dispose();
      lostClient.close();
    }
    final cap = <CreatedApiToken>[];
    for (var index = 0; index < 101; index++) {
      final created = await tokens.create('cap ${index + 1}');
      cap.add(created);
      cleanup.add(created.entry);
    }
    final page = await tokens.read();
    check(
      page.entries.length == 100 &&
          page.truncated &&
          !page.provesAbsent(cap.last.entry.id),
      'Actual100-row ascending cap cannot prove an unlisted ID absent',
    );
    check(
      await tokenAccess(owner, cap.last.secret) == 200,
      'Unlisted actual token is still valid',
    );
    await tokens.revoke(cap.last.entry);
    check(
      await tokenAccess(owner, cap.last.secret) == 401,
      'Known one-time receipt authorizes exact unlisted token revocation',
    );
    check(
      !(await tokens.read()).provesAbsent(cap.last.entry.id),
      'Full capped list still does not fabricate absence proof after deletion',
    );
    stdout.writeln(
      'PASS actual API tokens: nested one-time64-hex receipt, raw Unicode name, masked100-row ascending list, independent Token header access and immediate revocation cache invalidation; actual lost receipt does not recover secret or repeat create; known unlisted ID can be revoked without inventing list absence',
    );
  } finally {
    for (final entry in cleanup) {
      await tokens.revoke(entry);
    }
    tokens.dispose();
  }
  final dav = RemoteWebdavPasswordRepository(owner, memberId: memberId);
  try {
    final initial = await dav.read();
    check(
      !initial.hasPassword,
      'Empty fixture starts without DAV app password',
    );
    const custom = ' app 密码 raw ';
    check(
      await dav.reset(password: custom) == custom,
      'Actual custom app password preserves exact spaces and Unicode',
    );
    await dav.verify(custom);
    final actual = await dav.read();
    check(
      actual.hasPassword,
      'Actual DAV profile reports configured app password',
    );
    var rejected = false;
    try {
      await dav.verify(loginPassword);
    } on ApiFailure catch (e) {
      rejected = e.status == 401;
    }
    check(
      rejected,
      'Account login password does not substitute for DAV app password',
    );
    final generated = await dav.reset();
    check(
      generated != custom,
      'Empty request actually generates a new app password',
    );
    await dav.verify(generated);
    rejected = false;
    try {
      await dav.verify(custom);
    } on ApiFailure catch (e) {
      rejected = e.status == 401;
    }
    check(rejected, 'Old DAV app password is immediately rejected after reset');
    final transport = LostCredentialReceipt(
      '${owner.baseUri.path}/api/webdav/app-password/reset',
    );
    final lostClient = BookstarkClient(
      owner.baseUri.toString(),
      transport: transport,
    )..restoreSession(owner.exportSession());
    final state = WebdavPasswordController(
      RemoteWebdavPasswordRepository(lostClient, memberId: memberId),
    );
    try {
      await state.load();
      await state.reset(password: custom);
      check(
        state.phase == WebdavPasswordPhase.unknown && state.canVerify,
        'Actual applied custom reset with lost receipt stays unknown',
      );
      await state.reset();
      check(
        transport.writes == 1,
        'Unknown reset does not send another mutation',
      );
      await state.verify();
      check(
        state.phase == WebdavPasswordPhase.confirmed &&
            state.result != null &&
            !state.result!.receivedReceipt,
        'Explicit actual Basic PROPFIND confirms candidate while receipt remains unknown',
      );
    } finally {
      state.dispose();
      lostClient.close();
    }
    await dav.revoke();
    check(
      !(await dav.read()).hasPassword,
      'Actual revoke reports no app password',
    );
    rejected = false;
    try {
      await dav.verify(custom);
    } on ApiFailure catch (e) {
      rejected = e.status == 401;
    }
    check(rejected, 'Revoked app password cannot authenticate DAV');
    final profile = await RemoteProfileRepository(
          owner,
          memberId: memberId,
        ).read(),
        login = BookstarkClient(owner.baseUri.toString());
    try {
      await login.credentialLoginJson(profile.account, loginPassword);
      check(
        login.exportSession().containsKey('token'),
        'Login credentials remain valid independently of DAV reset/revoke',
      );
    } finally {
      login.close();
    }
    stdout.writeln(
      'PASS actual DAV credentials: custom raw Unicode/spaces, truly empty random reset, fixed-server Basic depth0 PROPFIND207, independent login password, old/revoked password401, exact has-password readback and lost actual custom-reset receipt verified with no repeated POST',
    );
  } finally {
    await dav.revoke();
    dav.dispose();
  }
}
