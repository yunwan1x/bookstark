import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/features/admin/admin_asset_models.dart';
import 'package:bookstark_flutter/features/admin/admin_assets_scope.dart';
import 'package:bookstark_flutter/features/admin/admin_settings_repository.dart';
import 'package:bookstark_flutter/features/admin/admin_files_models.dart';
import 'package:bookstark_flutter/features/admin/admin_files_repository.dart';
import '../admin_terminal_access_test.dart' as terminal;
import '../admin_files_models_test.dart' as models;

class AdminFilesHarness {
  AdminFilesHarness() {
    host = {...terminal.host(), 'cwd': '/work'};
    client = BookstarkClient(
      'https://owned.invalid/root',
      transport: MockClient(handle),
    );
    client.restoreSession({
      'token': 'owned-files-token',
      'csrf_token': 'owned-files-csrf',
    });
    scope = AdminAssetsScope(
      client,
      const AdminPrincipal(memberId: 1, account: 'owned-owner', role: 0),
    );
    repository = AdminFilesRepository(
      scope,
      AdminAssetHostMetadata.parse(host),
    );
  }
  late final BookstarkClient client;
  late final AdminAssetsScope scope;
  late final AdminFilesRepository repository;
  late final Map<String, dynamic> host;
  String content = '\ufeffone\r\n中文\n';
  int mutations = 0, role = 0;
  bool dropped = false, truncated = false, empty = false;
  final requests = <http.Request>[];
  Future<http.Response?> Function(http.Request)? intercept;
  Map<String, dynamic> get row => models.row(
    name: 'a.txt',
    path: '/work/a.txt',
    size: utf8.encode(content).length,
  );
  AdminFileEntry get entry => AdminFileEntry.parse(row, '/work');
  http.Response json(Object? data) => http.Response(
    jsonEncode({'code': 0, 'data': data}),
    200,
    headers: {'content-type': 'application/json'},
  );
  Future<http.Response> handle(http.Request request) async {
    requests.add(request);
    final intercepted = await intercept?.call(request);
    if (intercepted != null) return intercepted;
    if (request.url.path.endsWith('/profile')) {
      if (role < 0) return http.Response('owned forbidden', 401);
      return json({'member_id': 1, 'account': 'owned-owner', 'role': role});
    }
    if (request.url.path.endsWith('/ssh-hosts')) return json([host]);
    if (request.method == 'GET' && request.url.path.endsWith('/files')) {
      return json({
        'items': empty ? [] : [row],
        'limit': 1000,
        'truncated': truncated,
      });
    }
    if (request.method == 'GET' && request.url.path.endsWith('/content')) {
      return json({'path': '/work/a.txt', 'content': content});
    }
    mutations++;
    if (dropped) throw http.ClientException('owned response dropped');
    return json(null);
  }

  void close() {
    repository.dispose();
    scope.dispose();
    client.close();
  }
}
