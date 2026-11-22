import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/app_theme.dart';
import 'package:bookstark_flutter/features/admin/admin_dashboard_controller.dart';
import 'package:bookstark_flutter/features/admin/admin_dashboard_page.dart';
import 'package:bookstark_flutter/features/admin/admin_dashboard_repository.dart';

// Synthetic visual target only; every request is intercepted in memory.
void main() {
  final english = Uri.base.queryParameters['lang'] == 'en';
  final scale = double.tryParse(Uri.base.queryParameters['scale'] ?? '') ?? 1;
  final client = BookstarkClient(
    'https://fixture.invalid',
    transport: MockClient((request) async {
      final Object body;
      if (request.url.path.endsWith('/stats')) {
        body = {
          'code': 0,
          'data': {'total_visits': 12480, 'unique_ips': 2160},
        };
      } else if (request.url.path.endsWith('/trend')) {
        const pv = [1140, 1580, 1480, 1820, 2020, 2260, 2180];
        const uv = [240, 280, 260, 310, 340, 370, 360];
        body = {
          'code': 0,
          'data': [
            for (var i = 0; i < 7; i++)
              {
                'time': '2026-11-0${i + 1}',
                'page_views': pv[i],
                'unique_ips': uv[i],
              },
          ],
        };
      } else if (request.url.path.endsWith('/logs')) {
        final page = int.parse(request.url.queryParameters['page'] ?? '1');
        body = {
          'code': 0,
          'data': [
            for (var i = 0; i < 3; i++)
              {
                'visit_id': (page - 1) * 20 + i + 1,
                'ip': '192.0.2.${i + 1}',
                'path': ['/notes', '/books/31', '/topics/7'][i],
                'member_id': i == 1 ? 1 : 0,
                'account': i == 1 ? 'demo-admin' : '',
                'visit_time': DateTime.utc(
                  2026,
                  11,
                  7,
                  9,
                  38 - i * 4,
                ).toIso8601String(),
              },
          ],
          'total': 83,
          'page': page,
          'page_size': 20,
          'total_pages': 5,
        };
      } else {
        throw StateError('Visual fixture rejected unexpected route');
      }
      return http.Response(
        jsonEncode(body),
        200,
        headers: {'content-type': 'application/json'},
      );
    }),
  );
  final controller = AdminDashboardController(AdminDashboardRepository(client));
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
      home: AdminDashboardPage(
        controller: controller,
        english: english,
        onReturn: () {},
      ),
    ),
  );
}
