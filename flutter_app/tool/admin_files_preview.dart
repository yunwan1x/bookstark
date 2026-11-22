// Synthetic Flutter shell preview. The text body is validated separately in actual CodeMirror.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/app_theme.dart';
import 'package:bookstark_flutter/features/admin/admin_asset_models.dart';
import 'package:bookstark_flutter/features/admin/admin_asset_secure_window.dart';
import 'package:bookstark_flutter/features/admin/admin_assets_scope.dart';
import 'package:bookstark_flutter/features/admin/admin_settings_repository.dart';
import 'package:bookstark_flutter/features/admin/admin_files_page.dart';

class _PreviewGuard implements AdminAssetWindowGuard {
  @override
  Future<void> acquire() async {}
  @override
  Future<void> close() async {}
}

void main() {
  final query = Uri.base.queryParameters;
  final english = query['lang'] == 'en', fault = query['fault'];
  final scale = double.tryParse(query['scale'] ?? '1') ?? 1;
  const stamp = '2026-11-07T08:00:00.123456789Z', root = '/srv/bookstark';
  const source = '\ufefftitle: BookStark\r\nlanguage: 中文\n';
  final host = <String, Object?>{
    'id': 42,
    'name': english ? 'BookStark server' : 'BookStark 服务器',
    'host': 'owned.invalid',
    'port': 22,
    'username': 'operator',
    'auth_type': 'key',
    'credential_id': 9,
    'credential_name': 'owned-key',
    'credential_hint': 'key',
    'shell': '/bin/sh',
    'cwd': root,
    'docker_socket_path': '/var/run/docker.sock',
    'status': 'unknown',
    'created_by': 1,
    'create_time': stamp,
    'modify_time': stamp,
  };
  Map<String, Object?> row(
    String name, {
    String type = 'file',
    String? path,
    int? size,
    String mode = '0640',
  }) => {
    'name': name,
    'path': path ?? '$root/$name',
    'type': type,
    'size': size ?? utf8.encode(source).length,
    'mode': mode,
    'mod_time': stamp,
  };
  final items = <Map<String, Object?>>[
    row('config.yaml'),
    row('images', type: 'dir', size: 4096, mode: '0750'),
    row('README.md'),
    row('dir-link', type: 'symlink', size: 16),
    row('trailing space.txt '),
  ];
  if (fault == 'truncated') {
    for (var i = items.length; i < 1000; i++) {
      items.add(row('file-$i.txt'));
    }
  }
  var failedRead = fault == 'read', lost = false;
  http.Response response(Object? data, {int status = 200}) => http.Response(
    jsonEncode({'code': status == 200 ? 0 : 1, 'data': data}),
    status,
    headers: {'content-type': 'application/json'},
  );
  final client = BookstarkClient(
    'https://owned.invalid/prefix',
    transport: MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/profile')) {
        return response({'member_id': 1, 'account': 'owned-admin', 'role': 0});
      }
      if (path.endsWith('/ssh-hosts')) return response([host]);
      if (request.method == 'GET' && path.endsWith('/files')) {
        if (failedRead) {
          failedRead = false;
          return response(null, status: 503);
        }
        final directory = request.url.queryParameters['path'];
        return response({
          'items': fault == 'empty'
              ? []
              : directory == root
              ? items
              : [],
          'limit': 1000,
          'truncated': fault == 'truncated',
        });
      }
      if (request.method == 'GET' && path.endsWith('/content')) {
        return response({
          'path': request.url.queryParameters['path'],
          'content': source,
        });
      }
      if (path.endsWith('/mkdir')) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final target = body['path'] as String;
        items.add(
          row(
            target.split('/').last,
            type: 'dir',
            path: target,
            size: 4096,
            mode: '0750',
          ),
        );
        if (fault == 'unknown' && !lost) {
          lost = true;
          throw http.ClientException('owned fixture response dropped');
        }
      }
      if (fault == 'known-read') failedRead = true;
      return response(null);
    }),
  );
  client.restoreSession({
    'token': 'owned-preview-token',
    'csrf_token': 'owned-preview-csrf',
  });
  final scope = AdminAssetsScope(
    client,
    const AdminPrincipal(memberId: 1, account: 'owned-admin', role: 0),
  );
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: bookstarkTheme(),
      locale: Locale(english ? 'en' : 'zh'),
      supportedLocales: const [Locale('zh'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: AdminFilesPage(
        scope: scope,
        host: AdminAssetHostMetadata.parse(host),
        secureWindow: _PreviewGuard(),
        english: english,
        onReturn: scope.close,
      ),
    ),
  );
}
