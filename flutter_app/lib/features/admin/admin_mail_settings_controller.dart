import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/api_client.dart';
import 'admin_settings_repository.dart';

enum AdminMailPhase {
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
class AdminMailSettingsController extends ChangeNotifier {
  AdminMailSettingsController(this.repository, this.owner);

  final AdminSettingsRepository repository;
  final AdminPrincipal owner;
  AdminMailPhase phase = AdminMailPhase.loading;
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

  AdminMailStatus? status;
  DateTime? statusReadAt;
  AdminMailTestOutcome? testOutcome;
  bool serviceBusy = false;
  String? serviceMessage;
  static const fields = {
    'mail_enabled',
    'task_email_reminder_enabled',
    'password_reset_enabled',
    'mail_public_url',
    'password_reset_expiry_minutes',
  };
  bool get editable =>
      !_disposed &&
      !serviceBusy &&
      {AdminMailPhase.editing, AdminMailPhase.saved}.contains(phase);
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
        fields.map((key) => MapEntry(key, snapshot.records[key]?.value ?? '')),
      );
    revision++;
  }

  void _failure(Object error, AdminMailPhase fallback) {
    if ((error is ApiFailure && {401, 403}.contains(error.status)) ||
        error is StateError) {
      _draft.clear();
      status = null;
      statusReadAt = null;
      testOutcome = null;
      _base = null;
      current = null;
      phase = AdminMailPhase.permissionLost;
      message = '管理员身份或会话已变化，请重新进入。';
    } else {
      phase = fallback;
      message = fallback == AdminMailPhase.unknown
          ? '保存结果未知，请读取当前配置核对；不会自动重新保存。'
          : '操作未完成，请检查连接后重试。';
    }
  }

  Future<void> load() async {
    if (_disposed ||
        dirty ||
        phase == AdminMailPhase.saving ||
        phase == AdminMailPhase.unknown ||
        phase == AdminMailPhase.committedNeedsRead) {
      return;
    }
    final ticket = _begin();
    phase = AdminMailPhase.loading;
    message = null;
    _emit();
    try {
      final value = await repository.read(owner, abortTrigger: _abort!.future);
      if (!_alive(ticket)) return;
      _adopt(value);
      phase = AdminMailPhase.editing;
    } catch (error) {
      if (!_alive(ticket)) return;
      _failure(error, AdminMailPhase.failed);
    }
    _emit();
  }

  void edit(String key, String value) {
    if (!editable || !fields.contains(key) || _draft[key] == value) return;
    _draft[key] = value;
    revision++;
    message = null;
    phase = AdminMailPhase.editing;
    _emit();
  }

  AdminMailChanges _changes() {
    AdminChange<String> text(String key) =>
        _draft[key] == (_base!.records[key]?.value ?? '')
        ? const AdminChange.unchanged()
        : AdminChange.set(_draft[key] ?? '');
    AdminChange<bool> flag(String key) {
      if (!text(key).changed) return const AdminChange.unchanged();
      if (!{'0', '1'}.contains(_draft[key])) {
        throw const FormatException('请选择有效的开关状态。');
      }
      return AdminChange.set(_draft[key] == '1');
    }

    final enabled = _draft['mail_enabled'] == '1';
    final reminder = _draft['task_email_reminder_enabled'] == '1';
    final reset = _draft['password_reset_enabled'] == '1';
    final url = _draft['mail_public_url'] ?? '';
    final uri = Uri.tryParse(url);
    if (url.isNotEmpty &&
        (uri == null ||
            uri.host.isEmpty ||
            !{'http', 'https'}.contains(uri.scheme) ||
            uri.userInfo.isNotEmpty)) {
      throw const FormatException('请输入有效的 HTTP/HTTPS 公开站点地址。');
    }
    if (reminder && !enabled) {
      throw const FormatException('待办邮件提醒需要先启用邮件服务。');
    }
    if ((reminder || (enabled && reset)) && url.trim().isEmpty) {
      throw const FormatException('提醒和邮件找回密码需要公开站点地址。');
    }
    if (enabled &&
        ((_base!.smtp.host ?? '').trim().isEmpty ||
            (_base!.smtp.fromAddress ?? '').trim().isEmpty)) {
      throw const FormatException('请先保存 SMTP 主机与发件邮箱。');
    }
    int? expiry;
    if (text('password_reset_expiry_minutes').changed) {
      expiry = int.tryParse(
        (_draft['password_reset_expiry_minutes'] ?? '').trim(),
      );
      if (expiry == null || expiry < 5 || expiry > 120) {
        throw const FormatException('重置链接有效期应在 5–120 分钟之间。');
      }
    }
    return AdminMailChanges(
      enabled: flag('mail_enabled'),
      taskReminderEnabled: flag('task_email_reminder_enabled'),
      passwordResetEnabled: flag('password_reset_enabled'),
      publicUrl: text('mail_public_url'),
      passwordResetExpiryMinutes: expiry == null
          ? const AdminChange.unchanged()
          : AdminChange.set(expiry),
    );
  }

  Future<void> save() async {
    if (!editable || !dirty || _base == null) return;
    late final AdminMailChanges changes;
    try {
      changes = _changes();
    } on FormatException catch (error) {
      message = error.message;
      _emit();
      return;
    }
    final ticket = _begin();
    phase = AdminMailPhase.saving;
    message = null;
    _emit();
    try {
      await repository.saveMail(
        owner,
        _base!,
        changes,
        abortTrigger: _abort!.future,
      );
      if (!_alive(ticket)) return;
    } catch (error) {
      if (!_alive(ticket)) return;
      _failure(error, AdminMailPhase.unknown);
      _emit();
      return;
    }
    phase = AdminMailPhase.committedNeedsRead;
    await _readAfterWrite(ticket, knownReceipt: true);
  }

  Future<void> _readAfterWrite(int ticket, {required bool knownReceipt}) async {
    try {
      final value = await repository.read(owner, abortTrigger: _abort!.future);
      if (!_alive(ticket)) return;
      if (knownReceipt) {
        _adopt(value);
        phase = AdminMailPhase.saved;
        message = '服务器已确认保存，并已读取当前配置。';
      } else {
        current = value;
        phase = AdminMailPhase.reviewingCurrent;
        message = '请核对当前可读取配置。当前值不能证明上次请求结果。';
      }
    } catch (error) {
      if (!_alive(ticket)) return;
      _failure(
        error,
        knownReceipt
            ? AdminMailPhase.committedNeedsRead
            : AdminMailPhase.unknown,
      );
      if (phase == AdminMailPhase.committedNeedsRead) {
        message = '服务器已确认保存，回读未完成。重试只会读取配置。';
      }
    }
    _emit();
  }

  Future<void> readCurrent() async {
    if (_disposed ||
        !{
          AdminMailPhase.unknown,
          AdminMailPhase.committedNeedsRead,
          AdminMailPhase.reviewingCurrent,
        }.contains(phase)) {
      return;
    }
    final knownReceipt = phase == AdminMailPhase.committedNeedsRead;
    final ticket = _begin();
    await _readAfterWrite(ticket, knownReceipt: knownReceipt);
  }

  void adoptReviewedCurrent() {
    if (phase != AdminMailPhase.reviewingCurrent || current == null) return;
    _adopt(current!);
    phase = AdminMailPhase.editing;
    message = '已采用当前可读取配置。此操作不会重新发送保存请求。';
    _emit();
  }

  Future<void> refreshStatus() async {
    if (!editable || _base == null) return;
    final ticket = _begin();
    serviceBusy = true;
    serviceMessage = null;
    _emit();
    try {
      final value = await repository.readMailStatus(
        owner,
        abortTrigger: _abort!.future,
      );
      if (!_alive(ticket)) return;
      status = value;
      statusReadAt = DateTime.now();
    } catch (error) {
      if (!_alive(ticket)) return;
      _failure(error, phase);
      serviceMessage = '状态刷新失败；显示的旧状态不会作为当前状态。';
      status = null;
      statusReadAt = null;
    } finally {
      if (_alive(ticket)) {
        serviceBusy = false;
        _emit();
      }
    }
  }

  Future<void> sendTest(String recipient) async {
    if (!editable || _base == null) return;
    if (recipient.trim().isEmpty) {
      serviceMessage = '请输入测试收件邮箱。';
      _emit();
      return;
    }
    final ticket = _begin();
    final unsaved = dirty;
    serviceBusy = true;
    testOutcome = null;
    serviceMessage = null;
    _emit();
    try {
      final value = await repository.sendMailTest(
        owner,
        recipient,
        hasUnsavedSettings: unsaved,
        abortTrigger: _abort!.future,
      );
      if (!_alive(ticket)) return;
      testOutcome = value;
    } catch (error) {
      if (!_alive(ticket)) return;
      _failure(error, phase);
      serviceMessage = '发送操作未完成；请核对结果，不会自动重发。';
    } finally {
      if (_alive(ticket)) {
        serviceBusy = false;
        _emit();
      }
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _ticket++;
    _cancel();
    _draft.clear();
    status = null;
    statusReadAt = null;
    testOutcome = null;
    _base = null;
    current = null;
    repository.dispose();
    super.dispose();
  }
}
