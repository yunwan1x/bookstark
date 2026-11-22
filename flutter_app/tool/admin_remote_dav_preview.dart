// Synthetic shell only. No real API request or native editor proof.
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
import 'package:bookstark_flutter/features/admin/admin_remote_dav_models.dart';
import 'package:bookstark_flutter/features/admin/admin_remote_dav_repository.dart';
import 'package:bookstark_flutter/features/admin/admin_remote_dav_page.dart';
import 'package:bookstark_flutter/features/admin/admin_remote_dav_files_page.dart';

class _Guard implements AdminAssetWindowGuard {
  @override
  Future<void> acquire() async {}
  @override
  Future<void> close() async {}
}

void main() {
  final query = Uri.base.queryParameters;
  final english = query['lang'] == 'en', fault = query['fault'];
  final scale = double.tryParse(query['scale'] ?? '1') ?? 1;
  const stamp = '2026-11-08T08:00:00.123456789Z',
      source = '\ufefftitle: BookStark\r\nlanguage: 中文\n';
  final server = <String, dynamic>{
    'id': 42,
    'name': english ? 'Remote document storage' : '远程文档存储',
    'url': 'https://dav.example.invalid/prefix',
    'root_path': '/documents',
    'credential_id': 7,
    'credential_name': english ? 'DAV password' : 'DAV 密码',
    'username': 'operator',
    'status': 'online',
    'created_by': 1,
    'create_time': stamp,
    'modify_time': stamp,
    'last_check_time': stamp,
  };
  final credential = <String, dynamic>{
    'id': 7,
    'name': english ? 'DAV password' : 'DAV 密码',
    'username': 'operator',
    'auth_type': 'password',
    'credential_hint': 'hidden',
    'created_by': 1,
    'create_time': stamp,
    'modify_time': stamp,
  };
  Map<String, Object?> row(String name, {String type = 'file', int? size}) => {
    'name': name,
    'path': name,
    'type': type,
    'size': size ?? utf8.encode(source).length,
    'mode': type == 'dir' ? 'drwxr-xr-x' : '-rw-r--r--',
    'mod_time': stamp,
  };
  final items = <Map<String, Object?>>[
    row('config.yaml'),
    row('images', type: 'dir', size: 0),
    row('README.md'),
    row('trailing space.txt '),
  ];
  if (fault == 'truncated') {
    for (var i = items.length; i < 1000; i++) {
      items.add(row('file-$i.txt'));
    }
  }
  var failed = fault == 'read', lost = false;
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
      if (path.endsWith('/credentials')) {
        return response([credential]);
      }
      if (request.method == 'GET' && path.endsWith('/webdav-servers')) {
        return response([
          {
            'id': 'local',
            'built_in': true,
            'name': english
                ? 'BookStark built-in WebDAV'
                : 'BookStark 内置 WebDAV',
          },
          server,
        ]);
      }
      if (request.method == 'GET' && path.endsWith('/files')) {
        if (failed) {
          failed = false;
          return response(null, status: 503);
        }
        return response({
          'items': fault == 'empty'
              ? []
              : request.url.queryParameters['path'] == '.'
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
      if (path.endsWith('/test')) {
        return response({'status': 'online', 'checked_at': stamp});
      }
      if (path.endsWith('/mkdir')) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        items.add(row(body['path'] as String, type: 'dir', size: 0));
        if (fault == 'unknown' && !lost) {
          lost = true;
          throw http.ClientException('Owned preview reply dropped');
        }
      }
      if (path.endsWith('/webdav-servers') ||
          request.method == 'PUT' && path.endsWith('/42')) {
        server.addAll(jsonDecode(request.body) as Map<String, dynamic>);
        return response(server);
      }
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
  final Widget home = query['mode'] == 'files'
      ? AdminDavFilesPage(
          scope: scope,
          binding: AdminDavBinding(
            AdminDavServer.parse(server),
            AdminAssetCredentialMetadata.parse(credential),
          ),
          secureWindow: _Guard(),
          english: english,
          onReturn: scope.close,
        )
      : AdminDavPage(
          scope: scope,
          onReturn: scope.close,
          onBuiltin: () {},
          english: english,
          secureWindowFactory: () => _Guard(),
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
      home: home,
    ),
  );
}
