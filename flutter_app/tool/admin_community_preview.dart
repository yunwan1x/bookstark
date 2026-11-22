import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/app_theme.dart';
import 'package:bookstark_flutter/features/admin/admin_community_feature.dart';
import 'package:bookstark_flutter/features/admin/admin_community_scope.dart';
import 'package:bookstark_flutter/features/admin/admin_settings_repository.dart';

// Synthetic UI target only. API and image transports stay entirely in memory.
const _imageFixture =
    'iVBORw0KGgoAAAANSUhEUgAAAG8AAABvCAAAAADHrsG8AAABTElEQVR4nO2UOw7DMAxDff9Lp1MDhh+nHdohlIbAkSU+ogy6jv/WGt7whje8J/KWK+rjMF7tFWp5/HO/RU8t7aeO1SzkUXKWagPeKAxPSRrJOZY8DW/Do6hw6yf5PYWXHKAQJZfUh6dFYPskZ1ahkPdJLcnJ6sb1Mp6NAXWJYcFf5NfBo/Nyn77F2P7wjmtaR0h04yaaK+Pd4omKh81YMy8t6Cv17TyLN/FuFUmFGPa8Nvl18Oi8rnX6sGA0OjwlkS7K2cVkupNnw8NO0tKMk61y3rHNT3k4Q47LeXRAUVQnXboaXtqxeWiTDudAJ48mVOu2o/1yXqq0T7bWtYyVJt5yZXbk70ORONnM42v36Scf5Oaj/Ap4SRGDsf7swPCUhx3Lw1tKmleGJylqh2D4OjzrIGmlaIeHy1i4Rgx9TQqdvD/U8IY3vOE9hfcCnsN4SsogY+gAAAAASUVORK5CYII=';
void main() {
  final query = Uri.base.queryParameters;
  final english = query['lang'] == 'en',
      scale = double.tryParse(query['scale'] ?? '') ?? 1;
  final kind = query['kind'] == 'comments'
      ? AdminCommunityKind.comments
      : AdminCommunityKind.links;
  final role = query['role'] == '1' ? 1 : 0;
  var loseReply = query['fault'] == 'unknown',
      failAfterWrite = query['fault'] == 'known-read',
      failRead = false;
  var simple = false, nextLinkId = 100;
  var links = <Map<String, Object?>>[
    for (var i = 1; i <= 3; i++)
      {
        'link_id': i,
        'link_name': i == 1
            ? '文档中心'
            : i == 2
            ? '项目主页'
            : '联系示例',
        'link_url': i == 1
            ? 'https://docs.example.invalid'
            : i == 2
            ? 'https://project.example.invalid'
            : 'https://example.invalid/contact',
        'group_name': i < 3 ? '资源' : '联系信息',
        'group_order': i < 3 ? 0 : 1,
        'qr_code': i == 3 ? '/upload-files/fixture.png' : '',
        'description': i == 3 ? '用于展示联系方式的二维码示例。' : '',
        'sort_weight': i * 10,
        'is_enabled': 1,
        'create_time': '2026-11-07T09:20:00+08:00',
        'modify_time': '2026-11-07T09:20:00+08:00',
        'created_by': 1,
        'updated_by': 1,
      },
  ];
  var comments = <Map<String, Object?>>[
    for (var i = 24; i >= 1; i--)
      {
        'comment_id': i,
        'target_type': i == 24
            ? 'document'
            : i == 23
            ? 'blog'
            : ['blog', 'book', 'document'][(i - 1) % 3],
        'target_id': i + 100,
        'share_identify': i == 24
            ? 'demo-share'
            : i == 23
            ? 'demo-blog'
            : 'demo-share-$i',
        'parent_comment_id': i == 22 || i == 21
            ? 1
            : i == 20
            ? 2
            : 0,
        'root_comment_id': i == 22 || i == 21
            ? 1
            : i == 20
            ? 2
            : i,
        'reply_to_comment_id': i == 22 || i == 21
            ? 1
            : i == 20
            ? 2
            : 0,
        'reply_to_author_name': i >= 20 && i <= 22 ? '示例读者' : '',
        'author_member_id': 0,
        'author_name': i == 24
            ? 'reader-lin'
            : i == 23
            ? 'reader-zhou'
            : 'reader-$i',
        'content': i == 24
            ? '这段说明很清楚。'
            : i == 23
            ? '旧评论示例。'
            : '这是一条用于界面回归的示例评论 $i。',
        'status': i == 23 ? 'deleted' : 'visible',
        'create_time': '2026-11-07T09:20:00+08:00',
        'modify_time': '2026-11-07T09:20:00+08:00',
      },
  ];
  final client = BookstarkClient(
    'https://fixture.invalid',
    transport: MockClient((request) async {
      final path = request.url.path;
      Object result;
      if (path == '/api/profile') {
        result = {
          'code': 0,
          'data': {'member_id': 1, 'account': 'demo-admin', 'role': role},
        };
      } else if (request.method == 'GET' &&
          (path == '/api/admin/friend-links' ||
              path == '/api/admin/share-comments')) {
        if (failRead) {
          failRead = false;
          return http.Response(
            jsonEncode({'code': 503, 'message': 'owned one-shot read failure'}),
            503,
            headers: {'content-type': 'application/json'},
          );
        }
        if (path == '/api/admin/friend-links') {
          result = {
            'code': 0,
            'data': {'items': links, 'simple_mode': simple},
          };
        } else {
          final q = request.url.queryParameters;
          final filtered = comments.where((row) {
            final status = q['status'],
                type = q['target_type'],
                keyword = (q['keyword'] ?? '').trim().toLowerCase();
            return (status == null || row['status'] == status) &&
                (type == null || row['target_type'] == type) &&
                (keyword.isEmpty ||
                    [
                      row['content'],
                      row['author_name'],
                      row['share_identify'],
                      row['reply_to_author_name'],
                    ].any(
                      (value) =>
                          value.toString().toLowerCase().contains(keyword),
                    ));
          }).toList();
          final page = int.parse(q['page']!),
              pages = (filtered.length + 19) ~/ 20;
          result = {
            'code': 0,
            'data': filtered.skip((page - 1) * 20).take(20).toList(),
            'total': filtered.length,
            'page': page,
            'page_size': 20,
            'total_pages': pages == 0 ? 1 : pages,
          };
        }
      } else if (path == '/api/admin/friend-links' && request.method == 'PUT') {
        final body = jsonDecode(request.body) as Map;
        links = [
          for (final item in body['items'] as List)
            {
              ...Map<String, Object?>.from(item as Map),
              'link_id': ++nextLinkId,
              'is_enabled': item['is_enabled'] == 0 ? 0 : 1,
              for (final key in [
                'link_name',
                'link_url',
                'group_name',
                'qr_code',
                'description',
              ])
                key: (item[key] as String).trim(),
            },
        ];
        links.sort((a, b) {
          final group = (a['group_order'] as int).compareTo(
            b['group_order'] as int,
          );
          if (group != 0) return group;
          final order = (a['sort_weight'] as int).compareTo(
            b['sort_weight'] as int,
          );
          return order != 0
              ? order
              : (a['link_id'] as int).compareTo(b['link_id'] as int);
        });
        simple = body['simple_mode'] as bool;
        result = {'code': 0, 'message': 'saved'};
      } else if (path == '/api/admin/share-comments/delete' &&
          request.method == 'POST') {
        final ids = ((jsonDecode(request.body) as Map)['comment_ids'] as List)
            .cast<int>()
            .toSet();
        final roots = {
          for (final row in comments)
            if (ids.contains(row['comment_id']) &&
                row['parent_comment_id'] == 0)
              row['comment_id'],
        };
        final before = comments.length;
        comments = comments
            .where(
              (row) =>
                  !ids.contains(row['comment_id']) &&
                  !roots.contains(row['root_comment_id']),
            )
            .toList();
        result = {
          'code': 0,
          'data': {'deleted': before - comments.length},
        };
      } else {
        throw StateError('Unexpected visual API route');
      }
      if (request.method == 'PUT' || request.method == 'POST') {
        if (failAfterWrite) {
          failRead = true;
          failAfterWrite = false;
        }
        if (loseReply) {
          loseReply = false;
          throw http.ClientException('Owned visual lost reply');
        }
      }
      return http.Response(
        jsonEncode(result),
        200,
        headers: {'content-type': 'application/json'},
      );
    }),
  );
  client.restoreSession({
    'token': 'owned-visual-session',
    'csrf_token': 'owned-visual-csrf',
  });
  final scope = AdminCommunityScope(
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
      home: AdminCommunityFeature(
        scope: scope,
        kind: kind,
        english: english,
        onReturn: () {},
        qrTransportFactory: () => MockClient((request) async {
          if (request.url.origin != 'https://fixture.invalid' ||
              request.url.path != '/upload-files/fixture.png') {
            throw StateError('Unexpected owned visual image request');
          }
          return http.Response.bytes(
            base64Decode(_imageFixture),
            200,
            headers: {'content-type': 'image/png'},
          );
        }),
      ),
    ),
  );
}
