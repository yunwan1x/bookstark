import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/app_theme.dart';
import 'package:bookstark_flutter/features/admin/admin_members_feature.dart';
import 'package:bookstark_flutter/features/admin/admin_members_scope.dart';
import 'package:bookstark_flutter/features/admin/admin_settings_repository.dart';

// Standalone visual fixture. All API traffic stays in memory.
void main() {
  final english = Uri.base.queryParameters['lang'] == 'en';
  final scale = double.tryParse(Uri.base.queryParameters['scale'] ?? '') ?? 1;
  final rows = <Map<String, Object?>>[
    for (var i = 1; i <= 31; i++)
      {
        'member_id': i,
        'account': i == 1 ? 'demo-admin' : 'demo-member-$i',
        'role': i == 1 ? 0 : 1,
        'status': i == 1 ? 1 : (i - 2) % 3,
        'create_time': '2026-11-07T08:30:00+08:00',
        'create_at': 1794011400,
        'last_login_time': i % 3 == 0 ? null : '2026-11-07T09:00:00+08:00',
      },
  ];
  final client = BookstarkClient(
    'https://fixture.invalid',
    transport: MockClient((request) async {
      Object result;
      if (request.url.path == '/api/profile') {
        result = {
          'code': 0,
          'data': {'member_id': 1, 'account': 'demo-admin', 'role': 0},
        };
      } else if (request.url.path == '/api/admin/members' &&
          request.method == 'GET') {
        final page = int.parse(request.url.queryParameters['page']!);
        result = {
          'code': 0,
          'data': rows.skip((page - 1) * 20).take(20).toList(),
          'page': page,
          'page_size': 20,
          'total': rows.length,
          'total_pages': 2,
        };
      } else if (request.method == 'PUT' &&
          request.url.path.startsWith('/api/admin/members/')) {
        final parts = request.url.path.split('/');
        final id = int.parse(parts[4]);
        final row = rows.singleWhere((row) => row['member_id'] == id);
        switch (parts.last) {
          case 'approve':
            row['status'] = 1;
          case 'reject':
            row['status'] = 2;
          case 'role':
            row['role'] = (jsonDecode(request.body) as Map)['role'];
          case 'reset-password':
            break;
          default:
            throw StateError('Unexpected visual mutation');
        }
        result = {'code': 0, 'message': 'fixture accepted'};
      } else {
        throw StateError(
          'Unexpected visual request: ${request.method} ${request.url.path}',
        );
      }
      return http.Response(
        jsonEncode(result),
        200,
        headers: {'content-type': 'application/json'},
      );
    }),
  );
  client.restoreSession({
    'token': 'visual-owned-session',
    'csrf_token': 'visual-owned-csrf',
  });
  final scope = AdminMembersScope(
    client,
    const AdminPrincipal(memberId: 1, account: 'demo-admin', role: 0),
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
      home: AdminMembersFeature(
        scope: scope,
        english: english,
        onReturn: () {},
      ),
    ),
  );
}
