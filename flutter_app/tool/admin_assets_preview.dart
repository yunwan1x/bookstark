import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/app_theme.dart';
import 'package:bookstark_flutter/core/go_text.dart';
import 'package:bookstark_flutter/features/admin/admin_asset_secure_window.dart';
import 'package:bookstark_flutter/features/admin/admin_assets_feature.dart';
import 'package:bookstark_flutter/features/admin/admin_assets_scope.dart';
import 'package:bookstark_flutter/features/admin/admin_settings_repository.dart';

// Synthetic preview only. This guard makes no claim about browser security.
// Production Android always acquires its real native FLAG_SECURE lease.
class _PreviewWindow implements AdminAssetWindowGuard {
  @override
  Future<void> acquire() async {}
  @override
  Future<void> close() async {}
}

void main() {
  final query = Uri.base.queryParameters;
  final english = query['lang'] == 'en';
  final scale = double.tryParse(query['scale'] ?? '') ?? 1;
  final fault = query['fault'];
  final role = query['role'] == '1' ? 1 : 0;
  const timestamp = '2026-11-07T08:00:00+08:00';
  var sequence = 0,
      nextCredential = 3,
      nextHost = 4,
      failRead = fault == 'read';
  var lost = false;
  String tick() =>
      '2026-11-07T08:01:${(++sequence).toString().padLeft(2, '0')}+08:00';
  Map<String, Object?> credential(
    int id,
    String name,
    String user,
    String auth,
  ) => {
    'id': id,
    'name': name,
    'username': user,
    'auth_type': auth,
    'credential': auth == 'key'
        ? 'synthetic preview key\nsecond line\n'
        : 'synthetic preview password',
    'credential_hint': auth == 'key' ? 'SSH 私钥' : '密码',
    'created_by': 1,
    'create_time': timestamp,
    'modify_time': timestamp,
  };
  final credentials = <Map<String, Object?>>[
    credential(1, '演示密码凭据', 'operator', 'password'),
    credential(2, '演示私钥', 'deploy', 'key'),
  ];
  Map<String, Object?> host(
    int id,
    String name,
    String address,
    int cid,
    String status,
  ) => {
    'id': id,
    'name': name,
    'host': address,
    'port': 22,
    'credential_id': cid,
    'credential_name': '',
    'username': 'devuser',
    'auth_type': 'password',
    'credential_hint': '密码',
    'credential': 'synthetic preview legacy password',
    'shell': '/bin/sh',
    'cwd': '/workspace',
    'docker_socket_path': '/var/run/docker.sock',
    'status': status,
    if (status != 'unknown') 'last_check_time': timestamp,
    'created_by': 1,
    'create_time': timestamp,
    'modify_time': timestamp,
  };
  final hosts = <Map<String, Object?>>[
    host(1, '开发机 A', 'dev.example.invalid', 2, 'unknown'),
    host(2, '演示机 B', 'demo.example.invalid', 1, 'offline'),
    if (query['legacy'] == '1' ||
        fault == 'unknown-bind' ||
        fault == 'legacy-changed')
      host(3, '旧式开发主机', 'legacy.example.invalid', 0, 'unknown'),
  ];
  if (fault == 'empty') {
    hosts.clear();
    credentials.clear();
  }
  var settings = <String, Object?>{
    'terminal_idle_timeout_seconds': 1800,
    'terminal_scrollback_lines': 5000,
    'credential_secret': 'synthetic-preview-key-only',
  };
  Map<String, Object?> hydrate(Map<String, Object?> host) {
    final linked = credentials
        .where((row) => row['id'] == host['credential_id'])
        .firstOrNull;
    return {
      ...host,
      if (linked != null) ...{
        'credential_name': linked['name'],
        'username': linked['username'],
        'auth_type': linked['auth_type'],
        'credential': linked['credential'],
        'credential_hint': linked['credential_hint'],
      },
    };
  }

  http.Response response(Object? data, {int status = 200}) =>
      http.Response.bytes(
        utf8.encode(jsonEncode({'code': status == 200 ? 0 : 1, 'data': data})),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
  final client = BookstarkClient(
    'https://fixture.invalid',
    transport: MockClient((request) async {
      final path = request.url.path;
      if (path == '/api/profile') {
        return response({
          'member_id': 1,
          'account': 'demo-admin',
          'role': role,
        });
      }
      if (request.method == 'GET') {
        if (failRead) {
          failRead = false;
          return response(null, status: 503);
        }
        if (path.endsWith('/ssh-hosts')) {
          final search = request.url.queryParameters['q'] ?? '';
          final status = request.url.queryParameters['status'];
          return response(
            hosts
                .map(hydrate)
                .where(
                  (row) =>
                      (status == null || row['status'] == status) &&
                      (search.isEmpty ||
                          search == '%' ||
                          ['name', 'host', 'username', 'credential_name'].any(
                            (key) => (row[key] as String)
                                .toLowerCase()
                                .contains(search.toLowerCase()),
                          )),
                )
                .toList(),
          );
        }
        if (path.endsWith('/credentials')) return response(credentials);
        if (path.endsWith('/assets/settings')) return response(settings);
        return response(null, status: 404);
      }
      final body = request.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(request.body) as Map<String, dynamic>;
      final parts = path.split('/');
      final id = int.tryParse(parts.last);
      Object? result;
      if (path.endsWith('/test')) {
        final target = hosts.singleWhere(
          (row) => row['id'] == int.parse(parts[parts.length - 2]),
        );
        target['status'] = query['test'] == 'online' ? 'online' : 'offline';
        target['last_check_time'] = tick();
        result = {
          'status': target['status'],
          'checked_at': target['last_check_time'],
          'message': target['status'] == 'online'
              ? '连接成功'
              : 'dial synthetic fixture: connection refused',
        };
      } else if (path == '/api/admin/settings') {
        settings['terminal_idle_timeout_seconds'] = int.parse(
          body['asset_terminal_idle_timeout_seconds'] as String,
        );
        settings['terminal_scrollback_lines'] = int.parse(
          body['asset_terminal_scrollback_lines'] as String,
        );
        result = null;
      } else if (path.endsWith('/assets/settings')) {
        settings = {
          ...body,
          'credential_secret': trimGoSpace(body['credential_secret'] as String),
        };
        result = settings;
      } else if (path.contains('/credentials')) {
        if (request.method == 'DELETE') {
          if (hosts.any((row) => row['credential_id'] == id)) {
            return response(null, status: 400);
          }
          credentials.removeWhere((row) => row['id'] == id);
          result = null;
        } else if (request.method == 'POST') {
          final created = {
            ...credential(
              nextCredential++,
              body['name'] as String,
              body['username'] as String,
              body['auth_type'] as String,
            ),
            ...body,
          };
          credentials.add(created);
          result = created;
          if (fault == 'legacy-changed') hosts.last['name'] = '旧式开发主机已更新';
        } else {
          final target = credentials.singleWhere((row) => row['id'] == id);
          final secret = body['credential'];
          target.addAll({
            ...body,
            'credential': secret == '' ? target['credential'] : secret,
            'modify_time': tick(),
          });
          result = target;
        }
      } else if (path.contains('/ssh-hosts')) {
        if (request.method == 'DELETE') {
          hosts.removeWhere((row) => row['id'] == id);
          result = null;
        } else if (request.method == 'POST') {
          final created = {
            ...host(
              nextHost++,
              body['name'] as String,
              body['host'] as String,
              body['credential_id'] as int,
              'unknown',
            ),
            ...body,
            'create_time': tick(),
          };
          hosts.add(created);
          result = hydrate(created);
        } else {
          final target = hosts.singleWhere((row) => row['id'] == id);
          target.addAll({...body, 'modify_time': tick()});
          result = hydrate(target);
        }
      } else {
        return response(null, status: 404);
      }
      if (!lost &&
          (fault == 'unknown' ||
              fault == 'unknown-create' &&
                  request.method == 'POST' &&
                  path.endsWith('/credentials') ||
              fault == 'unknown-bind' &&
                  request.method == 'PUT' &&
                  path.contains('/ssh-hosts/'))) {
        lost = true;
        throw http.ClientException('synthetic dropped response');
      }
      if (fault == 'known-read') failRead = true;
      return response(result);
    }),
  );
  client.restoreSession({
    'token': 'synthetic-preview-token',
    'csrf_token': 'synthetic-preview-csrf',
  });
  final scope = AdminAssetsScope(
    client,
    AdminPrincipal(memberId: 1, account: 'demo-admin', role: role),
  );
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: bookstarkTheme().copyWith(platform: TargetPlatform.android),
      locale: Locale(english ? 'en' : 'zh'),
      supportedLocales: const [Locale('zh'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: AdminAssetsFeature(
        scope: scope,
        english: english,
        onReturn: scope.close,
        secureWindowFactory: _PreviewWindow.new,
      ),
    ),
  );
}
