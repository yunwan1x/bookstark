import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/api_client.dart';
import 'admin_settings_repository.dart';

enum AdminSmtpPhase {
  loading,
  editing,
  saving,
  saved,
  unknown,
  committedNeedsRead,
  reviewingCurrent,
  permissionLost,
  failed,
}

/// Owns one administrator form. No credentials are persisted or logged here.
class AdminSmtpSettingsController extends ChangeNotifier {
  AdminSmtpSettingsController(this.repository, this.owner);

  final AdminSettingsRepository repository;
  final AdminPrincipal owner;
  AdminSmtpPhase phase = AdminSmtpPhase.loading;
  AdminSettingsSnapshot? _base;
  AdminSettingsSnapshot? current;
  final Map<String, String> _draft = {};
  Map<String, String> get draft => Map.unmodifiable(_draft);
  AdminSettingsSnapshot? get baseline => _base;
  String? message;
  int revision = 0;
  int _ticket = 0;
  bool _disposed = false;
  Completer<void>? _abort;

  static const fields = {
    'smtp_host',
    'smtp_port',
    'smtp_encryption',
    'smtp_username',
    'smtp_password',
    'mail_timeout_seconds',
    'mail_from_name',
    'mail_from_address',
  };
  bool get editable =>
      !_disposed &&
      {AdminSmtpPhase.editing, AdminSmtpPhase.saved}.contains(phase);
  bool get dirty =>
      _base != null &&
      fields.any(
        (key) => (_draft[key] ?? '') != (_base!.records[key]?.value ?? ''),
      );
  void _emit() {
    if (!_disposed) notifyListeners();
  }

  bool _alive(int ticket) => !_disposed && ticket == _ticket;
  void _cancel() {
    if (!(_abort?.isCompleted ?? true)) _abort!.complete();
    _abort = null;
  }

  int _begin() {
    _cancel();
    _abort = Completer<void>();
    return ++_ticket;
  }

  void _adopt(AdminSettingsSnapshot snapshot) {
    _base = snapshot;
    current = null;
    _draft
      ..clear()
      ..addEntries(
        fields.map(
          (key) => MapEntry(
            key,
            key == 'smtp_password' ? '' : snapshot.records[key]?.value ?? '',
          ),
        ),
      );
    revision++;
  }

  void _failure(Object error, AdminSmtpPhase fallback) {
    if ((error is ApiFailure && {401, 403}.contains(error.status)) ||
        error is StateError) {
      _draft.clear();
      _base = null;
      current = null;
      phase = AdminSmtpPhase.permissionLost;
      message = '管理员身份或会话已变化，请重新进入。';
    } else {
      phase = fallback;
      message = fallback == AdminSmtpPhase.unknown
          ? '保存结果未知，请读取当前配置核对；不会自动重新保存。'
          : '操作未完成，请检查连接后重试。';
    }
  }

  Future<void> load() async {
    if (_disposed ||
        dirty ||
        phase == AdminSmtpPhase.saving ||
        phase == AdminSmtpPhase.unknown ||
        phase == AdminSmtpPhase.committedNeedsRead) {
      return;
    }
    final ticket = _begin();
    phase = AdminSmtpPhase.loading;
    message = null;
    _emit();
    try {
      final value = await repository.read(owner, abortTrigger: _abort!.future);
      if (!_alive(ticket)) return;
      _adopt(value);
      phase = AdminSmtpPhase.editing;
    } catch (error) {
      if (!_alive(ticket)) return;
      _failure(error, AdminSmtpPhase.failed);
    }
    _emit();
  }

  void edit(String key, String value) {
    if (!editable || !fields.contains(key) || _draft[key] == value) return;
    _draft[key] = value;
    revision++;
    message = null;
    phase = AdminSmtpPhase.editing;
    _emit();
  }

  AdminSmtpChanges _changes() {
    AdminChange<String> text(String key) =>
        _draft[key] == (_base!.records[key]?.value ?? '')
        ? const AdminChange.unchanged()
        : AdminChange.set(_draft[key] ?? '');
    int? parsed(String key, int minimum, int maximum) {
      if (!text(key).changed) return null;
      final value = int.tryParse((_draft[key] ?? '').trim());
      if (value == null || value < minimum || value > maximum) {
        throw FormatException(
          key == 'smtp_port' ? '端口应在 1–65535 之间。' : '连接超时应在 3–60 秒之间。',
        );
      }
      return value;
    }

    void limit(String key, int maximum) {
      if (text(key).changed &&
          utf8.encode((_draft[key] ?? '').trim()).length > maximum) {
        throw const FormatException('字段内容过长，请检查。');
      }
    }

    limit('smtp_host', 255);
    limit('smtp_username', 500);
    limit('smtp_password', 500);
    limit('mail_from_name', 100);
    if (text('smtp_host').changed &&
        (_draft['smtp_host'] ?? '').contains('://')) {
      throw const FormatException('SMTP 主机不包含协议。');
    }
    if (text('smtp_encryption').changed &&
        !{
          'starttls',
          'tls',
          'none',
        }.contains((_draft['smtp_encryption'] ?? '').trim())) {
      throw const FormatException('请选择有效加密方式。');
    }
    final name = (_draft['mail_from_name'] ?? '').trim();
    if (text('mail_from_name').changed &&
        (name.isEmpty || name.contains('\r') || name.contains('\n'))) {
      throw const FormatException('发件人名称不能为空或包含换行。');
    }
    // Mail address grammar is authoritatively checked by Go mail.ParseAddress.
    final address = (_draft['mail_from_address'] ?? '').trim();
    if (text('mail_from_address').changed &&
        (address.contains('\r') || address.contains('\n'))) {
      throw const FormatException('发件邮箱不能包含换行。');
    }
    final port = parsed('smtp_port', 1, 65535);
    final timeout = parsed('mail_timeout_seconds', 3, 60);
    return AdminSmtpChanges(
      host: text('smtp_host'),
      encryption: text('smtp_encryption'),
      username: text('smtp_username'),
      password: text('smtp_password'),
      fromName: text('mail_from_name'),
      fromAddress: text('mail_from_address'),
      port: port == null
          ? const AdminChange.unchanged()
          : AdminChange.set(port),
      timeoutSeconds: timeout == null
          ? const AdminChange.unchanged()
          : AdminChange.set(timeout),
    );
  }

  Future<void> save() async {
    if (!editable || !dirty || _base == null) return;
    late final AdminSmtpChanges changes;
    try {
      changes = _changes();
    } on FormatException catch (error) {
      message = error.message;
      _emit();
      return;
    }
    final ticket = _begin();
    phase = AdminSmtpPhase.saving;
    message = null;
    _emit();
    try {
      await repository.saveSmtp(
        owner,
        _base!,
        changes,
        abortTrigger: _abort!.future,
      );
      if (!_alive(ticket)) return;
    } catch (error) {
      if (!_alive(ticket)) return;
      _failure(error, AdminSmtpPhase.unknown);
      _emit();
      return;
    }
    _draft['smtp_password'] = '';
    phase = AdminSmtpPhase.committedNeedsRead;
    await _readAfterWrite(ticket, knownReceipt: true);
  }

  Future<void> _readAfterWrite(int ticket, {required bool knownReceipt}) async {
    try {
      final value = await repository.read(owner, abortTrigger: _abort!.future);
      if (!_alive(ticket)) return;
      if (knownReceipt) {
        _adopt(value);
        phase = AdminSmtpPhase.saved;
        message = '服务器已确认保存，并已读取当前配置。';
      } else {
        current = value;
        phase = AdminSmtpPhase.reviewingCurrent;
        message = '请核对当前可读取配置。SMTP 密码无法回读；当前值不能证明上次请求结果。';
      }
    } catch (error) {
      if (!_alive(ticket)) return;
      _failure(
        error,
        knownReceipt
            ? AdminSmtpPhase.committedNeedsRead
            : AdminSmtpPhase.unknown,
      );
      if (phase == AdminSmtpPhase.committedNeedsRead) {
        message = '服务器已确认保存，回读未完成。重试只会读取配置。';
      }
    }
    _emit();
  }

  Future<void> readCurrent() async {
    if (_disposed ||
        !{
          AdminSmtpPhase.unknown,
          AdminSmtpPhase.committedNeedsRead,
          AdminSmtpPhase.reviewingCurrent,
        }.contains(phase)) {
      return;
    }
    final knownReceipt = phase == AdminSmtpPhase.committedNeedsRead;
    final ticket = _begin();
    await _readAfterWrite(ticket, knownReceipt: knownReceipt);
  }

  void adoptReviewedCurrent() {
    if (phase != AdminSmtpPhase.reviewingCurrent || current == null) return;
    _adopt(current!);
    phase = AdminSmtpPhase.editing;
    message = '已采用当前可读取配置。SMTP 密码无法回读，不能据此确认未知请求是否设置了密码。';
    _emit();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _ticket++;
    _cancel();
    _draft.clear();
    _base = null;
    current = null;
    repository.dispose();
    super.dispose();
  }
}
