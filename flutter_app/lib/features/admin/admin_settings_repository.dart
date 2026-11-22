import 'dart:async';
import 'dart:convert';

import 'package:bookstark_flutter/core/api_client.dart';
import 'package:http/http.dart' as http;

import 'admin_public_tags.dart';
import '../../core/label_management_repository.dart';

/// Identity that owns an administrator screen. Callers must obtain this from
/// their current profile; the repository independently verifies it before I/O.
class AdminPrincipal {
  const AdminPrincipal({
    required this.memberId,
    required this.account,
    required this.role,
  });

  final int memberId;
  final String account;
  final int role;

  bool sameAs(AdminPrincipal other) =>
      memberId == other.memberId &&
      account == other.account &&
      role == other.role;

  @override
  String toString() => 'AdminPrincipal(memberId: $memberId, role: $role)';
}

class AdminSettingRecord {
  const AdminSettingRecord({
    required this.key,
    required this.value,
    required this.description,
    required this.updateTime,
  });

  final String key;
  final String value;
  final String description;
  final String updateTime;

  @override
  String toString() => 'AdminSettingRecord(key: $key, value: [redacted])';
}

enum AdminAiTextField {
  markdown('ai_system_prompt_md'),
  html('ai_system_prompt_html'),
  drawing('ai_system_prompt_drawing'),
  selection('ai_actions_selection'),
  htmlActions('ai_actions_html'),
  book('ai_actions_book'),
  article('ai_actions_article'),
  note('ai_actions_note'),
  task('ai_actions_task'),
  empty('ai_actions_empty');

  const AdminAiTextField(this.key);
  final String key;
  bool get systemPrompt => const {markdown, html, drawing}.contains(this);
}

class AdminTextChanges {
  AdminTextChanges(Map<AdminAiTextField, AdminChange<String>> fields)
    : fields = Map.unmodifiable(fields);
  final Map<AdminAiTextField, AdminChange<String>> fields;
  Map<String, String> patch(AdminSettingsSnapshot base) => _changed({
    for (final field in fields.entries) field.key.key: field.value,
  }, base);
  @override
  String toString() => 'AdminTextChanges(values: [redacted])';
}

class AdminResetOutcome {
  const AdminResetOutcome(this.field, this.value);
  final AdminAiTextField field;
  final String value;
  @override
  String toString() => 'AdminResetOutcome(value: [redacted])';
}

class AdminAiUsage {
  const AdminAiUsage({this.promptTokens, this.completionTokens, this.requests});
  final int? promptTokens;
  final int? completionTokens;
  final int? requests;
}

class AdminAiSettings {
  const AdminAiSettings({
    this.enabled,
    this.provider,
    this.baseUrl,
    this.apiKey,
    this.model,
    this.temperature,
    this.maxTokens,
    required this.usage,
  });

  final bool? enabled;
  final String? provider;
  final String? baseUrl;
  final String? apiKey;
  final String? model;
  final double? temperature;
  final int? maxTokens;
  final AdminAiUsage usage;

  @override
  String toString() =>
      'AdminAiSettings(provider: $provider, model: $model, apiKey: [redacted])';
}

class AdminSmtpSettings {
  const AdminSmtpSettings({
    this.host,
    this.port,
    this.encryption,
    this.username,
    this.timeoutSeconds,
    this.fromName,
    this.fromAddress,
  });

  final String? host;
  final int? port;
  final String? encryption;
  final String? username;
  final int? timeoutSeconds;
  final String? fromName;
  final String? fromAddress;

  @override
  String toString() => 'AdminSmtpSettings([redacted])';
}

class AdminMailSettings {
  const AdminMailSettings({
    this.enabled,
    this.taskReminderEnabled,
    this.passwordResetEnabled,
    this.publicUrl,
    this.passwordResetExpiryMinutes,
  });

  final bool? enabled;
  final bool? taskReminderEnabled;
  final bool? passwordResetEnabled;
  final String? publicUrl;
  final int? passwordResetExpiryMinutes;
}

class AdminSettingsSnapshot {
  AdminSettingsSnapshot._(Map<String, AdminSettingRecord> records)
    : records = Map.unmodifiable(records),
      unknownSettings = Map.unmodifiable({
        for (final entry in records.entries)
          if (!_editableKeys.contains(entry.key) &&
              !_usageKeys.contains(entry.key))
            entry.key: entry.value,
      }),
      ai = AdminAiSettings(
        enabled: _optionalFlag(records, 'ai_enabled'),
        provider: records['ai_provider']?.value,
        baseUrl: records['ai_base_url']?.value,
        apiKey: records['ai_api_key']?.value,
        model: records['ai_model']?.value,
        temperature: _optionalDouble(records, 'ai_temperature'),
        maxTokens: _optionalInt(records, 'ai_max_tokens'),
        usage: AdminAiUsage(
          promptTokens: _optionalNonNegativeInt(
            records,
            'ai_total_prompt_tokens',
          ),
          completionTokens: _optionalNonNegativeInt(
            records,
            'ai_total_completion_tokens',
          ),
          requests: _optionalNonNegativeInt(records, 'ai_total_requests'),
        ),
      ),
      smtp = AdminSmtpSettings(
        host: records['smtp_host']?.value,
        port: _optionalInt(records, 'smtp_port'),
        encryption: records['smtp_encryption']?.value,
        username: records['smtp_username']?.value,
        timeoutSeconds: _optionalInt(records, 'mail_timeout_seconds'),
        fromName: records['mail_from_name']?.value,
        fromAddress: records['mail_from_address']?.value,
      ),
      mail = AdminMailSettings(
        enabled: _optionalFlag(records, 'mail_enabled'),
        taskReminderEnabled: _optionalFlag(
          records,
          'task_email_reminder_enabled',
        ),
        passwordResetEnabled: _optionalFlag(records, 'password_reset_enabled'),
        publicUrl: records['mail_public_url']?.value,
        passwordResetExpiryMinutes: _optionalInt(
          records,
          'password_reset_expiry_minutes',
        ),
      );

  final Map<String, AdminSettingRecord> records;
  final Map<String, AdminSettingRecord> unknownSettings;
  final AdminAiSettings ai;
  final AdminSmtpSettings smtp;
  final AdminMailSettings mail;

  static const Set<String> _editableKeys = {
    'asset_terminal_idle_timeout_seconds',
    'asset_terminal_scrollback_lines',
    'tag_recommend_strategy',
    'tag_recommend_manual_labels',
    'tag_recommend_page_size',
    'webdav_file_max_bytes',
    'webdav_user_quota_bytes',
    'webdav_public_file_max_bytes',
    'webdav_max_concurrent_transfers',
    'webdav_public_asset_separate_url_enabled',
    'webdav_public_asset_base_url',
    'webrtc_signaling_enabled',
    'webrtc_signaling_default_url',
    'webrtc_signaling_max_peers',
    'webrtc_signaling_max_message_kb',
    'webrtc_signaling_allow_local_file',
    'webrtc_signaling_allowed_origins',
    'webrtc_signaling_stun_urls',
    'webrtc_signaling_turn_url',
    'webrtc_signaling_turn_username',
    'webrtc_signaling_turn_credential',
    'invite_code_enabled',
    'invite_code',
    'public_feed_tags_article',
    'public_feed_tags_note',
    'public_feed_tags_book',
    'public_feed_tags_bookmark',
    'upload_max_size',
    'upload_allowed_types',
    'upload_max_width',
    'upload_thumb_width',
    'page_size_uploads',
    'share_comments_enabled',
    'share_comment_max_length',
    'login_session_days',
    'save_interval',
    'nav_max_items',
    'favicon_cache_days',
    'page_size_books',
    'page_size_blogs',
    'page_size_shares',
    'page_size_bookmarks',
    'page_size_labels',
    'page_size_notes',
    'label_list_limit',
    'ai_system_prompt_md',
    'ai_system_prompt_html',
    'ai_system_prompt_drawing',
    'ai_actions_selection',
    'ai_actions_html',
    'ai_actions_book',
    'ai_actions_article',
    'ai_actions_note',
    'ai_actions_task',
    'ai_actions_empty',
    'ai_enabled',
    'ai_provider',
    'ai_base_url',
    'ai_api_key',
    'ai_model',
    'ai_temperature',
    'ai_max_tokens',
    'smtp_host',
    'smtp_port',
    'smtp_encryption',
    'smtp_username',
    'smtp_password',
    'mail_timeout_seconds',
    'mail_from_name',
    'mail_from_address',
    'mail_enabled',
    'task_email_reminder_enabled',
    'password_reset_enabled',
    'mail_public_url',
    'password_reset_expiry_minutes',
  };
  static const Set<String> _usageKeys = {
    'ai_total_prompt_tokens',
    'ai_total_completion_tokens',
    'ai_total_requests',
  };

  static bool? _optionalFlag(
    Map<String, AdminSettingRecord> records,
    String key,
  ) {
    final raw = records[key]?.value;
    if (raw == null) return null;
    if (raw == '0') return false;
    if (raw == '1') return true;
    throw FormatException('Invalid boolean setting: $key');
  }

  static int? _optionalInt(
    Map<String, AdminSettingRecord> records,
    String key,
  ) {
    final raw = records[key]?.value;
    if (raw == null) return null;
    final value = int.tryParse(raw);
    if (value == null) throw FormatException('Invalid integer setting: $key');
    return value;
  }

  static double? _optionalDouble(
    Map<String, AdminSettingRecord> records,
    String key,
  ) {
    final raw = records[key]?.value;
    if (raw == null) return null;
    final value = double.tryParse(raw);
    if (value == null || !value.isFinite) {
      throw FormatException('Invalid decimal setting: $key');
    }
    return value;
  }

  static int? _optionalNonNegativeInt(
    Map<String, AdminSettingRecord> records,
    String key,
  ) {
    final raw = records[key]?.value;
    if (raw == null) return null;
    final value = int.tryParse(raw);
    if (value == null || value < 0) {
      throw FormatException('Invalid read-only AI usage field: $key');
    }
    return value;
  }

  factory AdminSettingsSnapshot.parse(Object? raw) {
    if (raw is! List || raw.length > 200) {
      throw const FormatException('Invalid admin settings response');
    }
    final result = <String, AdminSettingRecord>{};
    for (final item in raw) {
      if (item is! Map<String, Object?>) {
        throw const FormatException('Invalid setting record');
      }
      final key = item['key'];
      final value = item['value'];
      final description = item['description'];
      final updateTime = item['update_time'];
      if (key is! String ||
          key.isEmpty ||
          key.length > 256 ||
          value is! String ||
          utf8.encode(value).length > 32768 ||
          description is! String ||
          description.length > 4096 ||
          updateTime is! String ||
          updateTime.length > 64 ||
          result.containsKey(key)) {
        throw const FormatException('Invalid or duplicate setting record');
      }
      if (key == 'smtp_password' && value.isNotEmpty) {
        throw const FormatException('SMTP password must remain redacted');
      }
      result[key] = AdminSettingRecord(
        key: key,
        value: value,
        description: description,
        updateTime: updateTime,
      );
    }
    return AdminSettingsSnapshot._(result);
  }

  @override
  String toString() =>
      'AdminSettingsSnapshot(records: ${records.length}, secrets: [redacted])';
}

/// A change is explicit, so `set('')` differs from leaving a field untouched.
class AdminChange<T> {
  const AdminChange.unchanged() : changed = false, value = null;
  const AdminChange.set(T this.value) : changed = true;

  final bool changed;
  final T? value;
}

enum AdminWebDavField {
  fileMax('webdav_file_max_bytes', '单文件上限（字节）', 1048576, 2147483648),
  userQuota('webdav_user_quota_bytes', '用户容量（字节）', 10485760, 1099511627776),
  publicFileMax(
    'webdav_public_file_max_bytes',
    '公开文件上限（字节）',
    1048576,
    1073741824,
  ),
  concurrent('webdav_max_concurrent_transfers', '最大并发传输', 1, 32),
  separateUrl('webdav_public_asset_separate_url_enabled', '使用独立资源地址'),
  baseUrl('webdav_public_asset_base_url', '基础地址');

  const AdminWebDavField(this.key, this.label, [this.minimum, this.maximum]);
  final String key, label;
  final int? minimum, maximum;
}

class AdminWebDavChanges {
  AdminWebDavChanges(Map<AdminWebDavField, String> fields)
    : fields = Map.unmodifiable(fields);
  final Map<AdminWebDavField, String> fields;
  Map<String, String> patch(AdminSettingsSnapshot base) {
    final result = <String, String>{};
    for (final entry in fields.entries) {
      if (base.records[entry.key.key]?.value == entry.value) continue;
      final value = entry.value.trim();
      final minimum = entry.key.minimum;
      if (minimum != null) {
        final parsed = int.tryParse(value);
        if (!RegExp(r'^[+-]?[0-9]+$').hasMatch(value) ||
            parsed == null ||
            parsed < minimum ||
            parsed > entry.key.maximum!) {
          throw FormatException('${entry.key.label}超出有效整数范围。');
        }
      } else if (entry.key == AdminWebDavField.separateUrl) {
        if (!{'0', '1'}.contains(value)) {
          throw const FormatException('独立资源地址开关无效。');
        }
      } else if (value.isNotEmpty) {
        final uri = Uri.tryParse(value);
        if (uri == null ||
            !{'http', 'https'}.contains(uri.scheme) ||
            uri.host.isEmpty ||
            uri.userInfo.isNotEmpty ||
            uri.hasQuery ||
            uri.hasFragment) {
          throw const FormatException('资源地址需为 HTTP(S)，不能包含账号、查询参数或片段。');
        }
      }
      result[entry.key.key] = entry.value;
    }
    final enabled =
        (result['webdav_public_asset_separate_url_enabled'] ??
                base
                    .records['webdav_public_asset_separate_url_enabled']
                    ?.value ??
                '')
            .trim();
    final url =
        result['webdav_public_asset_base_url'] ??
        base.records['webdav_public_asset_base_url']?.value ??
        '';
    if (enabled == '1' && url.trim().isEmpty) {
      throw const FormatException('启用独立资源地址前，请填写基础地址。');
    }
    return Map.unmodifiable(result);
  }

  @override
  String toString() => 'AdminWebDavChanges(values: [redacted])';
}

enum AdminSignalingField {
  enabled('webrtc_signaling_enabled', '启用信令'),
  url('webrtc_signaling_default_url', '默认信令地址'),
  peers('webrtc_signaling_max_peers', '单房间连接数'),
  messageSize('webrtc_signaling_max_message_kb', '信令消息上限（KB）'),
  localFile('webrtc_signaling_allow_local_file', '允许本地文件调试'),
  origins('webrtc_signaling_allowed_origins', '允许的来源'),
  stun('webrtc_signaling_stun_urls', 'STUN 地址'),
  turn('webrtc_signaling_turn_url', 'TURN 地址'),
  turnUsername('webrtc_signaling_turn_username', 'TURN 账号'),
  turnCredential('webrtc_signaling_turn_credential', 'TURN 凭据');

  const AdminSignalingField(this.key, this.label);
  final String key, label;
}

class AdminSignalingChanges {
  AdminSignalingChanges(Map<AdminSignalingField, String> fields)
    : fields = Map.unmodifiable(fields);
  final Map<AdminSignalingField, String> fields;
  Map<String, String> patch(AdminSettingsSnapshot base) {
    final result = <String, String>{};
    bool url(String value, Set<String> schemes) {
      final uri = Uri.tryParse(value);
      return uri != null && uri.host.isNotEmpty && schemes.contains(uri.scheme);
    }

    for (final entry in fields.entries) {
      final raw = entry.value;
      if (base.records[entry.key.key]?.value == raw) continue;
      final value = raw.trim();
      var valid = true;
      switch (entry.key) {
        case AdminSignalingField.enabled:
        case AdminSignalingField.localFile:
          valid = {'0', '1'}.contains(raw);
        case AdminSignalingField.peers:
        case AdminSignalingField.messageSize:
          final parsed = int.tryParse(raw);
          final peers = entry.key == AdminSignalingField.peers;
          valid =
              RegExp(r'^[+-]?[0-9]+$').hasMatch(raw) &&
              parsed != null &&
              parsed >= (peers ? 2 : 8) &&
              parsed <= (peers ? 64 : 512);
        case AdminSignalingField.url:
          valid = value.isEmpty || url(value, {'ws', 'wss'});
        case AdminSignalingField.origins:
        case AdminSignalingField.stun:
          final items = raw
              .split(RegExp(r'[\n\r,]'))
              .map((item) => item.trim())
              .where((item) => item.isNotEmpty);
          valid = items.every(
            (item) => entry.key == AdminSignalingField.stun
                ? item.startsWith('stun:')
                : url(item, {'http', 'https'}),
          );
        case AdminSignalingField.turn:
          valid =
              value.isEmpty ||
              value.startsWith('turn:') ||
              value.startsWith('turns:');
        case AdminSignalingField.turnUsername:
        case AdminSignalingField.turnCredential:
          valid = utf8.encode(raw).length <= 256;
      }
      if (!valid) throw FormatException('${entry.key.label}格式或范围无效。');
      result[entry.key.key] = raw;
    }
    return Map.unmodifiable(result);
  }

  @override
  String toString() => 'AdminSignalingChanges(values: [redacted])';
}

class AdminRegistrationChanges {
  const AdminRegistrationChanges({
    this.enabled = const AdminChange.unchanged(),
    this.code = const AdminChange.unchanged(),
  });
  final AdminChange<bool> enabled;
  final AdminChange<String> code;
  Map<String, String> patch(AdminSettingsSnapshot base) => _changed({
    'invite_code_enabled': _stringChange(enabled, (value) => value ? '1' : '0'),
    'invite_code': code,
  }, base);
  @override
  String toString() => 'AdminRegistrationChanges(values: [redacted])';
}

class AdminPublicTagChanges {
  AdminPublicTagChanges(Map<AdminPublicTagKind, String> fields)
    : fields = Map.unmodifiable(fields);
  final Map<AdminPublicTagKind, String> fields;
  Map<String, String> patch(AdminSettingsSnapshot base) {
    final result = <String, String>{};
    for (final entry in fields.entries) {
      if (base.records[entry.key.key]?.value == entry.value) continue;
      AdminPublicTagConfig.parse(entry.value);
      result[entry.key.key] = entry.value;
    }
    return Map.unmodifiable(result);
  }

  @override
  String toString() => 'AdminPublicTagChanges(values: [redacted])';
}

enum AdminContentField {
  maxSize('upload_max_size', '文件上限（字节）', 1024, 1073741824),
  allowedTypes('upload_allowed_types', '允许的 MIME 类型'),
  maxWidth('upload_max_width', '原图最大宽度（px）', 100, 16384),
  thumbWidth('upload_thumb_width', '缩略图宽度（px）', 50, 2000),
  pageSize('page_size_uploads', '上传列表每页条数', 1, 200),
  comments('share_comments_enabled', '公开分享评论', 0, 1),
  commentLength('share_comment_max_length', '评论字符上限', 100, 5000);

  const AdminContentField(this.key, this.label, [this.minimum, this.maximum]);
  final String key, label;
  final int? minimum, maximum;
}

class AdminContentChanges {
  AdminContentChanges(Map<AdminContentField, String> fields)
    : fields = Map.unmodifiable(fields);
  final Map<AdminContentField, String> fields;
  Map<String, String> patch(AdminSettingsSnapshot base) {
    final result = <String, String>{};
    for (final entry in fields.entries) {
      if (base.records[entry.key.key]?.value == entry.value) continue;
      final minimum = entry.key.minimum;
      if (entry.key == AdminContentField.comments) {
        if (!{'0', '1'}.contains(entry.value)) {
          throw const FormatException('请选择有效的评论开关。');
        }
      } else if (minimum != null) {
        final value = int.tryParse(entry.value);
        if (!RegExp(r'^[+-]?[0-9]+$').hasMatch(entry.value) ||
            value == null ||
            value < minimum ||
            value > entry.key.maximum!) {
          throw FormatException('${entry.key.label}超出有效整数范围。');
        }
      }
      result[entry.key.key] = entry.value;
    }
    return Map.unmodifiable(result);
  }

  @override
  String toString() => 'AdminContentChanges(values: [redacted])';
}

enum AdminNumericField {
  loginSessionDays('login_session_days', '登录有效期（天）', 1, 365, true),
  saveInterval('save_interval', '自动保存间隔（秒）', 5, 300, true),
  navMaxItems('nav_max_items', '导航书签上限', 1, 100000, true),
  faviconCacheDays('favicon_cache_days', '图标缓存（天）', 1, 365, true),
  books('page_size_books', '书籍', 1, 200, false),
  blogs('page_size_blogs', '文章', 1, 200, false),
  shares('page_size_shares', '分享', 1, 200, false),
  bookmarks('page_size_bookmarks', '书签', 1, 200, false),
  labels('page_size_labels', '标签', 1, 200, false),
  notes('page_size_notes', '笔记', 1, 200, false),
  labelListLimit('label_list_limit', '标签列表上限', 1, 10000, false),
  terminalIdle(
    'asset_terminal_idle_timeout_seconds',
    '无操作断开时间（秒）',
    1,
    86400,
    false,
    terminal: true,
  ),
  terminalScrollback(
    'asset_terminal_scrollback_lines',
    '历史保留行数',
    500,
    50000,
    false,
    terminal: true,
  );

  const AdminNumericField(
    this.key,
    this.label,
    this.minimum,
    this.maximum,
    this.general, {
    this.terminal = false,
  });
  final String key, label;
  final int minimum, maximum;
  final bool general, terminal;
}

class AdminNumericChanges {
  AdminNumericChanges(Map<AdminNumericField, String> fields)
    : fields = Map.unmodifiable(fields);
  final Map<AdminNumericField, String> fields;
  Map<String, String> patch(AdminSettingsSnapshot base) {
    final result = <String, String>{};
    for (final entry in fields.entries) {
      if (base.records[entry.key.key]?.value == entry.value) continue;
      final value = int.tryParse(entry.value);
      if (!RegExp(r'^[+-]?[0-9]+$').hasMatch(entry.value) ||
          value == null ||
          value < entry.key.minimum ||
          value > entry.key.maximum) {
        throw FormatException('${entry.key.label}超出有效整数范围。');
      }
      result[entry.key.key] = entry.value;
    }
    return Map.unmodifiable(result);
  }

  @override
  String toString() => 'AdminNumericChanges(values: [redacted])';
}

class AdminAiChanges {
  const AdminAiChanges({
    this.enabled = const AdminChange.unchanged(),
    this.provider = const AdminChange.unchanged(),
    this.baseUrl = const AdminChange.unchanged(),
    this.apiKey = const AdminChange.unchanged(),
    this.model = const AdminChange.unchanged(),
    this.temperature = const AdminChange.unchanged(),
    this.maxTokens = const AdminChange.unchanged(),
  });

  final AdminChange<bool> enabled;
  final AdminChange<String> provider, baseUrl, apiKey, model;
  final AdminChange<double> temperature;
  final AdminChange<int> maxTokens;

  Map<String, String> patch(AdminSettingsSnapshot base) {
    final fields = <String, AdminChange<String>>{
      'ai_enabled': _stringChange(enabled, (value) => value ? '1' : '0'),
      'ai_provider': provider,
      'ai_base_url': baseUrl,
      'ai_api_key': apiKey,
      'ai_model': model,
      'ai_temperature': _stringChange(temperature, (value) => value.toString()),
      'ai_max_tokens': _stringChange(maxTokens, (value) => value.toString()),
    };
    return _changed(fields, base);
  }

  @override
  String toString() => 'AdminAiChanges(fields: [redacted])';
}

class AdminSmtpChanges {
  const AdminSmtpChanges({
    this.host = const AdminChange.unchanged(),
    this.port = const AdminChange.unchanged(),
    this.encryption = const AdminChange.unchanged(),
    this.username = const AdminChange.unchanged(),
    this.password = const AdminChange.unchanged(),
    this.timeoutSeconds = const AdminChange.unchanged(),
    this.fromName = const AdminChange.unchanged(),
    this.fromAddress = const AdminChange.unchanged(),
  });

  final AdminChange<String> host, encryption, username, password;
  final AdminChange<int> port, timeoutSeconds;
  final AdminChange<String> fromName, fromAddress;

  Map<String, String> patch(AdminSettingsSnapshot base) {
    final fields = <String, AdminChange<String>>{
      'smtp_host': host,
      'smtp_port': _stringChange(port, (value) => value.toString()),
      'smtp_encryption': encryption,
      'smtp_username': username,
      'smtp_password': password,
      'mail_timeout_seconds': _stringChange(
        timeoutSeconds,
        (value) => value.toString(),
      ),
      'mail_from_name': fromName,
      'mail_from_address': fromAddress,
    };
    // Go discards empty smtp_password values. Omit it to represent retain;
    // unlike AI, this page has no endpoint semantic for clearing the secret.
    return _changed(fields, base, omitEmpty: const {'smtp_password'});
  }

  @override
  String toString() => 'AdminSmtpChanges(fields: [redacted])';
}

class AdminMailChanges {
  const AdminMailChanges({
    this.enabled = const AdminChange.unchanged(),
    this.taskReminderEnabled = const AdminChange.unchanged(),
    this.passwordResetEnabled = const AdminChange.unchanged(),
    this.publicUrl = const AdminChange.unchanged(),
    this.passwordResetExpiryMinutes = const AdminChange.unchanged(),
  });

  final AdminChange<bool> enabled, taskReminderEnabled, passwordResetEnabled;
  final AdminChange<String> publicUrl;
  final AdminChange<int> passwordResetExpiryMinutes;

  Map<String, String> patch(AdminSettingsSnapshot base) => _changed({
    'mail_enabled': _stringChange(enabled, (value) => value ? '1' : '0'),
    'task_email_reminder_enabled': _stringChange(
      taskReminderEnabled,
      (value) => value ? '1' : '0',
    ),
    'password_reset_enabled': _stringChange(
      passwordResetEnabled,
      (value) => value ? '1' : '0',
    ),
    'mail_public_url': publicUrl,
    'password_reset_expiry_minutes': _stringChange(
      passwordResetExpiryMinutes,
      (value) => value.toString(),
    ),
  }, base);

  @override
  String toString() => 'AdminMailChanges(fields: [redacted])';
}

AdminChange<String> _stringChange<T>(
  AdminChange<T> change,
  String Function(T value) encode,
) {
  if (!change.changed) return const AdminChange<String>.unchanged();
  final value = change.value;
  if (value == null) {
    throw const FormatException('Changed setting has no value');
  }
  return AdminChange<String>.set(encode(value));
}

Map<String, String> _changed(
  Map<String, AdminChange<String>> fields,
  AdminSettingsSnapshot base, {
  Set<String> omitEmpty = const {},
}) {
  final patch = <String, String>{};
  for (final entry in fields.entries) {
    final change = entry.value;
    if (!change.changed) continue;
    final value = change.value;
    if (value == null) {
      throw const FormatException('Changed setting has no value');
    }
    if (omitEmpty.contains(entry.key) && value.isEmpty) continue;
    if (base.records[entry.key]?.value != value ||
        !base.records.containsKey(entry.key)) {
      patch[entry.key] = value;
    }
  }
  return Map.unmodifiable(patch);
}

class AdminAiTestOutcome {
  const AdminAiTestOutcome({required this.connected, required this.latencyMs});
  final bool connected;
  final int? latencyMs;

  @override
  String toString() =>
      'AdminAiTestOutcome(connected: $connected, latencyMs: $latencyMs)';
}

class AdminMailStatus {
  const AdminMailStatus({
    required this.configured,
    required this.enabled,
    required this.taskReminderEnabled,
    required this.passwordResetEnabled,
    required this.passwordResetReady,
    required this.pending,
    required this.failed,
    required this.sent,
    required this.lastSent,
    required this.hasLastError,
  });

  final bool configured, enabled, taskReminderEnabled;
  final bool passwordResetEnabled, passwordResetReady;
  final int pending, failed, sent;
  final DateTime? lastSent;
  final bool hasLastError;

  factory AdminMailStatus.parse(Map<String, Object?> row) {
    bool flag(String name) {
      final value = row[name];
      if (value is! bool) throw FormatException('Invalid mail status: $name');
      return value;
    }

    final summary = row['summary'];
    if (summary is! Map<String, Object?>) {
      throw const FormatException('Invalid mail summary');
    }
    int count(String name) {
      final value = summary[name];
      if (value is! int || value < 0) {
        throw FormatException('Invalid mail summary: $name');
      }
      return value;
    }

    DateTime? lastSent;
    final rawTime = summary['last_sent'];
    if (rawTime != null) {
      if (rawTime is! String ||
          (lastSent = DateTime.tryParse(rawTime)) == null) {
        throw const FormatException('Invalid mail last_sent timestamp');
      }
    }
    final lastError = summary['last_error'];
    if (lastError is! String || utf8.encode(lastError).length > 4096) {
      throw const FormatException('Invalid mail last_error field');
    }
    return AdminMailStatus(
      configured: flag('configured'),
      enabled: flag('enabled'),
      taskReminderEnabled: flag('task_reminder_enabled'),
      passwordResetEnabled: flag('password_reset_enabled'),
      passwordResetReady: flag('password_reset_ready'),
      pending: count('pending'),
      failed: count('failed'),
      sent: count('sent'),
      lastSent: lastSent,
      hasLastError: lastError.isNotEmpty,
    );
  }

  @override
  String toString() =>
      'AdminMailStatus(pending: $pending, failed: $failed, sent: $sent)';
}

enum AdminMailTestState { sent, rateLimited, rejected, unknown }

class AdminMailTestOutcome {
  const AdminMailTestOutcome(
    this.state, {
    this.savedConfigOnly = true,
    this.hadUnsavedChanges = false,
  });
  final AdminMailTestState state;
  final bool savedConfigOnly;
  final bool hadUnsavedChanges;

  @override
  String toString() => 'AdminMailTestOutcome(state: $state)';
}

class AdminSettingsRepository {
  AdminSettingsRepository(this.client);

  final BookstarkClient client;
  int _operation = 0;
  bool _disposed = false;
  _VerifiedAdmin? _verified;

  String? _token() => client.exportSession()['token'];

  Future<T> _withAuthExpiry<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on ApiFailure catch (error) {
      if (error.status == 401 || error.status == 403) _verified = null;
      rethrow;
    }
  }

  int _begin() {
    if (_disposed) throw StateError('Admin repository is disposed');
    _verified = null;
    return ++_operation;
  }

  void _checkTicket(int op, AdminPrincipal owner, String token) {
    if (_disposed ||
        op != _operation ||
        _token() != token ||
        owner.role != 0 ||
        owner.memberId <= 0 ||
        owner.account.isEmpty) {
      throw StateError('Administrator owner/session changed during request');
    }
  }

  Future<void> _verifyAdmin(
    int op,
    AdminPrincipal owner,
    String token, {
    Future<void>? abortTrigger,
  }) async {
    if (token.isEmpty) throw StateError('Authenticated session required');
    final profile = await _withAuthExpiry(
      () => client.profileSettingsJson(abortTrigger: abortTrigger),
    );
    _checkTicket(op, owner, token);
    final id = profile['member_id'];
    final account = profile['account'];
    final role = profile['role'];
    if (id != owner.memberId || account != owner.account || role != 0) {
      _verified = null;
      throw StateError('Current account is not the reviewed administrator');
    }
  }

  Future<AdminSettingsSnapshot> read(
    AdminPrincipal owner, {
    Future<void>? abortTrigger,
  }) async {
    final op = _begin();
    final token = _token();
    if (token == null || token.isEmpty) {
      throw StateError('Authenticated session required');
    }
    await _verifyAdmin(op, owner, token, abortTrigger: abortTrigger);
    final response = await _withAuthExpiry(
      () => client.adminSettingsJson(abortTrigger: abortTrigger),
    );
    _checkTicket(op, owner, token);
    final snapshot = AdminSettingsSnapshot.parse(response['data']);
    if (snapshot.records['smtp_password']?.value.isNotEmpty ?? false) {
      throw const FormatException('SMTP secret unexpectedly exposed');
    }
    _verified = _VerifiedAdmin(owner, token);
    return snapshot;
  }

  Future<({int operation, String token})> _preflight(
    AdminPrincipal owner, {
    Future<void>? abortTrigger,
  }) async {
    final verified = _verified;
    final token = _token();
    if (verified == null ||
        !verified.owner.sameAs(owner) ||
        token == null ||
        verified.token != token) {
      throw StateError('Fresh administrator settings read required');
    }
    final op = ++_operation;
    _checkTicket(op, owner, token);
    await _verifyAdmin(op, owner, token, abortTrigger: abortTrigger);
    _checkTicket(op, owner, token);
    _verified = _VerifiedAdmin(owner, token);
    return (operation: op, token: token);
  }

  Future<void> _save(
    AdminPrincipal owner,
    Map<String, String> values, {
    Future<void>? abortTrigger,
  }) async {
    if (values.isEmpty) {
      throw const FormatException('No dirty settings to save');
    }
    final ticket = await _preflight(owner, abortTrigger: abortTrigger);
    final op = ticket.operation;
    final token = ticket.token;
    _checkTicket(op, owner, token);
    final response = await _withAuthExpiry(
      () =>
          client.adminSettingsJson(update: values, abortTrigger: abortTrigger),
    );
    _checkTicket(op, owner, token);
    _requireReceipt(response, 'settings save');
  }

  Future<void> saveText(
    AdminPrincipal owner,
    AdminSettingsSnapshot base,
    AdminTextChanges changes, {
    Future<void>? abortTrigger,
  }) => _save(owner, changes.patch(base), abortTrigger: abortTrigger);

  Future<AdminResetOutcome> resetTextToDefault(
    AdminPrincipal owner,
    AdminAiTextField field, {
    Future<void>? abortTrigger,
  }) async {
    final ticket = await _preflight(owner, abortTrigger: abortTrigger);
    _checkTicket(ticket.operation, owner, ticket.token);
    final response = await _withAuthExpiry(
      () => client.adminAiResetJson(field.key, abortTrigger: abortTrigger),
    );
    _checkTicket(ticket.operation, owner, ticket.token);
    final value = response['value'];
    if (response['key'] != field.key || value is! String) {
      throw const FormatException(
        'AI reset receipt does not match reviewed field',
      );
    }
    return AdminResetOutcome(field, value);
  }

  Future<void> saveWebDav(
    AdminPrincipal owner,
    AdminSettingsSnapshot base,
    AdminWebDavChanges changes, {
    Future<void>? abortTrigger,
  }) => _save(owner, changes.patch(base), abortTrigger: abortTrigger);

  Future<void> saveSignaling(
    AdminPrincipal owner,
    AdminSettingsSnapshot base,
    AdminSignalingChanges changes, {
    Future<void>? abortTrigger,
  }) => _save(owner, changes.patch(base), abortTrigger: abortTrigger);

  Future<void> saveRegistration(
    AdminPrincipal owner,
    AdminSettingsSnapshot base,
    AdminRegistrationChanges changes, {
    Future<void>? abortTrigger,
  }) => _save(owner, changes.patch(base), abortTrigger: abortTrigger);

  Future<LabelRecommendationSettings> readRecommendations(
    AdminPrincipal owner, {
    Future<void>? abortTrigger,
  }) async {
    final ticket = await _preflight(owner, abortTrigger: abortTrigger);
    final response = await _withAuthExpiry(
      () => client.adminRecommendationsJson(abortTrigger: abortTrigger),
    );
    _checkTicket(ticket.operation, owner, ticket.token);
    return LabelRecommendationSettings.fromJson(response);
  }

  Future<void> saveRecommendations(
    AdminPrincipal owner,
    LabelRecommendationSettings value, {
    Future<void>? abortTrigger,
  }) async {
    final body = value.writeBody();
    final ticket = await _preflight(owner, abortTrigger: abortTrigger);
    final response = await _withAuthExpiry(
      () => client.adminRecommendationsJson(
        update: body,
        abortTrigger: abortTrigger,
      ),
    );
    _checkTicket(ticket.operation, owner, ticket.token);
    LabelRecommendationSettings.fromJson(response);
  }

  Future<void> savePublicTags(
    AdminPrincipal owner,
    AdminSettingsSnapshot base,
    AdminPublicTagChanges changes, {
    Future<void>? abortTrigger,
  }) => _save(owner, changes.patch(base), abortTrigger: abortTrigger);

  Future<void> saveContent(
    AdminPrincipal owner,
    AdminSettingsSnapshot base,
    AdminContentChanges changes, {
    Future<void>? abortTrigger,
  }) => _save(owner, changes.patch(base), abortTrigger: abortTrigger);

  Future<void> saveNumeric(
    AdminPrincipal owner,
    AdminSettingsSnapshot base,
    AdminNumericChanges changes, {
    Future<void>? abortTrigger,
  }) => _save(owner, changes.patch(base), abortTrigger: abortTrigger);

  Future<void> saveAi(
    AdminPrincipal owner,
    AdminSettingsSnapshot base,
    AdminAiChanges changes, {
    Future<void>? abortTrigger,
  }) => _save(owner, changes.patch(base), abortTrigger: abortTrigger);

  Future<void> saveSmtp(
    AdminPrincipal owner,
    AdminSettingsSnapshot base,
    AdminSmtpChanges changes, {
    Future<void>? abortTrigger,
  }) => _save(owner, changes.patch(base), abortTrigger: abortTrigger);

  Future<void> saveMail(
    AdminPrincipal owner,
    AdminSettingsSnapshot base,
    AdminMailChanges changes, {
    Future<void>? abortTrigger,
  }) => _save(owner, changes.patch(base), abortTrigger: abortTrigger);

  Future<AdminAiTestOutcome> testAi(
    AdminPrincipal owner, {
    required String provider,
    required String baseUrl,
    required String apiKey,
    required String model,
    Future<void>? abortTrigger,
  }) async {
    final ticket = await _preflight(owner, abortTrigger: abortTrigger);
    final op = ticket.operation;
    final token = ticket.token;
    _checkTicket(op, owner, token);
    final response = await _withAuthExpiry(
      () => client.adminAiTestJson({
        'provider': provider,
        'base_url': baseUrl,
        'api_key': apiKey,
        'model': model,
      }, abortTrigger: abortTrigger),
    );
    _checkTicket(op, owner, token);
    if (response['code'] is! int || !{0, 200}.contains(response['code'])) {
      throw const FormatException('Invalid AI test response code');
    }
    final ok = response['ok'];
    if (ok is! bool) {
      throw const FormatException('AI test response omitted `ok`');
    }
    final latency = response['latency_ms'];
    final latencyMs = latency is int && latency >= 0 ? latency : null;
    // Never pass upstream detail, sample, URL or credential-bearing strings to UI.
    return AdminAiTestOutcome(connected: ok, latencyMs: latencyMs);
  }

  Future<AdminMailStatus> readMailStatus(
    AdminPrincipal owner, {
    Future<void>? abortTrigger,
  }) async {
    final ticket = await _preflight(owner, abortTrigger: abortTrigger);
    final op = ticket.operation;
    final token = ticket.token;
    _checkTicket(op, owner, token);
    final response = await _withAuthExpiry(
      () => client.adminMailStatusJson(abortTrigger: abortTrigger),
    );
    _checkTicket(op, owner, token);
    return AdminMailStatus.parse(response);
  }

  Future<AdminMailTestOutcome> sendMailTest(
    AdminPrincipal owner,
    String recipient, {
    bool hasUnsavedSettings = false,
    Future<void>? abortTrigger,
  }) async {
    if (recipient.trim().isEmpty) {
      throw const FormatException('A test recipient is required');
    }
    final ticket = await _preflight(owner, abortTrigger: abortTrigger);
    final op = ticket.operation;
    final token = ticket.token;
    _checkTicket(op, owner, token);
    try {
      final response = await _withAuthExpiry(
        () => client.adminMailTestJson(recipient, abortTrigger: abortTrigger),
      );
      _checkTicket(op, owner, token);
      _requireReceipt(response, 'mail test');
      return AdminMailTestOutcome(
        AdminMailTestState.sent,
        hadUnsavedChanges: hasUnsavedSettings,
      );
    } on ApiFailure catch (error) {
      if (error.status == 401 || error.status == 403) rethrow;
      _checkTicket(op, owner, token);
      return AdminMailTestOutcome(
        error.status == 429
            ? AdminMailTestState.rateLimited
            : AdminMailTestState.rejected,
        savedConfigOnly: true,
        hadUnsavedChanges: hasUnsavedSettings,
      );
    } on TimeoutException {
      _checkTicket(op, owner, token);
      return AdminMailTestOutcome(
        AdminMailTestState.unknown,
        hadUnsavedChanges: hasUnsavedSettings,
      );
    } on http.ClientException {
      _checkTicket(op, owner, token);
      return AdminMailTestOutcome(
        AdminMailTestState.unknown,
        hadUnsavedChanges: hasUnsavedSettings,
      );
    }
  }

  void _requireReceipt(Map<String, Object?> response, String operation) {
    if (!{0, 200}.contains(response['code']) ||
        response['message'] is! String) {
      throw FormatException('Missing actual $operation receipt');
    }
  }

  void dispose() {
    _disposed = true;
    _operation++;
    _verified = null;
  }
}

class _VerifiedAdmin {
  const _VerifiedAdmin(this.owner, this.token);
  final AdminPrincipal owner;
  final String token;
}
