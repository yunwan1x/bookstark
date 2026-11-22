import 'dart:convert';

import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/app_theme.dart';
import 'package:bookstark_flutter/features/admin/admin_settings_feature.dart';
import 'package:bookstark_flutter/features/admin/admin_settings_repository.dart';
import 'package:bookstark_flutter/features/admin/admin_settings_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// Visual fixture only. No network request can leave this in-memory transport.
void main() {
  final settings = <String, String>{
    for (final field in AdminNumericField.values)
      field.key: field.minimum.toString(),
    for (final field in AdminContentField.values)
      field.key: field.minimum?.toString() ?? 'image/jpeg,image/png,image/webp',
    for (final field in AdminWebDavField.values)
      field.key: field.minimum?.toString() ?? '',
    'login_session_days': '30',
    'save_interval': '30',
    'nav_max_items': '1000',
    'favicon_cache_days': '7',
    'page_size_books': '20',
    'page_size_blogs': '20',
    'page_size_shares': '20',
    'page_size_bookmarks': '30',
    'page_size_labels': '20',
    'page_size_notes': '30',
    'label_list_limit': '1000',
    'asset_terminal_idle_timeout_seconds': '1800',
    'asset_terminal_scrollback_lines': '5000',
    'upload_max_size': '10485760',
    'upload_max_width': '2048',
    'upload_thumb_width': '300',
    'page_size_uploads': '20',
    'share_comments_enabled': '1',
    'share_comment_max_length': '1000',
    'webdav_file_max_bytes': '104857600',
    'webdav_user_quota_bytes': '1073741824',
    'webdav_public_file_max_bytes': '52428800',
    'webdav_max_concurrent_transfers': '4',
    'webdav_public_asset_separate_url_enabled': '1',
    'webdav_public_asset_base_url': 'https://static.example.com/assets',
    'ai_enabled': '1',
    'ai_provider': 'openai',
    'ai_base_url': 'https://api.example.com/v1',
    'ai_api_key': 'synthetic-visual-key',
    'ai_model': 'sample-model',
    'ai_temperature': '0.7',
    'ai_max_tokens': '4096',
    'ai_total_prompt_tokens': '1200',
    'ai_total_completion_tokens': '360',
    'ai_total_requests': '24',
    'smtp_host': 'smtp.example.com',
    'smtp_port': '587',
    'smtp_encryption': 'starttls',
    'smtp_username': 'sender@example.com',
    'smtp_password': '',
    'mail_timeout_seconds': '10',
    'mail_from_name': 'BookStark',
    'mail_from_address': 'sender@example.com',
    'mail_enabled': '1',
    'task_email_reminder_enabled': '1',
    'password_reset_enabled': '1',
    'mail_public_url': 'https://example.com',
    'password_reset_expiry_minutes': '30',
    'invite_code_enabled': '1',
    'invite_code': 'synthetic-visual-invite',
    'webrtc_signaling_enabled': '1',
    'webrtc_signaling_default_url': 'wss://signal.example.com/ws',
    'webrtc_signaling_max_peers': '8',
    'webrtc_signaling_max_message_kb': '64',
    'webrtc_signaling_allow_local_file': '0',
    'webrtc_signaling_allowed_origins': 'https://example.com',
    'webrtc_signaling_stun_urls': 'stun:stun.example.com:3478',
    'webrtc_signaling_turn_url': 'turns:turn.example.com',
    'webrtc_signaling_turn_username': 'visual-user',
    'webrtc_signaling_turn_credential': 'synthetic-turn-key',
    for (final field in AdminAiTextField.values)
      field.key: field.systemPrompt
          ? '你是一个专业的写作助手。\n请保留原文格式。'
          : '# 示例动作\n总结 | 总结 {subject}\n改写 | 优化表达并保留原意\n',
    for (final kind in ['article', 'note', 'book', 'bookmark'])
      'public_feed_tags_$kind': '{"mode":"manual","labels":["技术","阅读","生活"]}',
  };
  final client = BookstarkClient(
    'https://fixture.invalid/mount',
    transport: MockClient((request) async {
      if (request.method != 'GET') {
        throw StateError('Readonly visual fixture rejected mutation');
      }
      Object data;
      if (request.url.path.endsWith('/api/profile')) {
        data = {
          'member_id': 41,
          'account': 'visual-admin',
          'role': 0,
          'email': 'admin@example.com',
          'default_home': 'home',
        };
      } else if (request.url.path.endsWith('/api/admin/settings')) {
        data = [
          for (final entry in settings.entries)
            {
              'key': entry.key,
              'value': entry.value,
              'description': '',
              'update_time': '',
            },
        ];
      } else if (request.url.path.endsWith(
        '/api/labels/recommendation-settings',
      )) {
        data = {
          'strategy': 'manual',
          'manual_labels': ['技术', '阅读', '生活'],
          'page_size': 10,
        };
      } else if (request.url.path.endsWith('/api/admin/mail/status')) {
        data = {
          'configured': true,
          'enabled': true,
          'task_reminder_enabled': true,
          'password_reset_enabled': true,
          'password_reset_ready': true,
          'summary': {
            'pending': 0,
            'failed': 0,
            'sent': 12,
            'last_sent': null,
            'last_error': '',
          },
        };
      } else {
        throw StateError('Readonly visual fixture rejected unknown endpoint');
      }
      return http.Response(
        jsonEncode({'code': 0, 'data': data}),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }),
  )..restoreSession({'token': 'synthetic-visual-session'});
  final scope = AdminSettingsScope(
    client,
    const AdminPrincipal(memberId: 41, account: 'visual-admin', role: 0),
  );
  final english = Uri.base.queryParameters['lang'] == 'en';
  final scale = double.tryParse(Uri.base.queryParameters['scale'] ?? '') ?? 1;
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: bookstarkTheme(),
      locale: Locale(english ? 'en' : 'zh'),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('zh'), Locale('en')],
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: AdminSettingsFeature(
        scope: scope,
        english: english,
        onReturn: () {},
      ),
    ),
  );
}
