import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/api_client.dart';
import 'admin_settings_repository.dart';

enum AdminRegistrationPhase {
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
class AdminRegistrationController extends ChangeNotifier {
  AdminRegistrationController(this.repository, this.owner);

  final AdminSettingsRepository repository;
  final AdminPrincipal owner;
  AdminRegistrationPhase phase = AdminRegistrationPhase.loading;
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

  static const fields = {'invite_code_enabled', 'invite_code'};
  bool get editable =>
      !_disposed &&
      {
        AdminRegistrationPhase.editing,
        AdminRegistrationPhase.saved,
      }.contains(phase);
  bool get dirty =>
      _base != null &&
      fields.any(
        (key) => (_draft[key] ?? '') != (_base!.records[key]?.value ?? ''),
      );
  bool get clearingCode =>
      (_base?.records['invite_code']?.value.isNotEmpty ?? false) &&
      (_draft['invite_code'] ?? '').isEmpty;

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

  void _failure(Object error, AdminRegistrationPhase fallback) {
    if ((error is ApiFailure && {401, 403}.contains(error.status)) ||
        error is StateError) {
      _draft.clear();
      _base = null;
      current = null;
      phase = AdminRegistrationPhase.permissionLost;
      message = '管理员身份或会话已变化，请重新进入。';
    } else {
      phase = fallback;
      message = fallback == AdminRegistrationPhase.unknown
          ? '保存结果未知，请读取当前配置核对；不会自动重新保存。'
          : '操作未完成，请检查连接后重试。';
    }
  }

  Future<void> load() async {
    if (_disposed ||
        dirty ||
        phase == AdminRegistrationPhase.saving ||
        phase == AdminRegistrationPhase.unknown ||
        phase == AdminRegistrationPhase.committedNeedsRead) {
      return;
    }
    final ticket = _begin();
    phase = AdminRegistrationPhase.loading;
    message = null;
    _emit();
    try {
      final value = await repository.read(owner, abortTrigger: _abort!.future);
      if (!_alive(ticket)) return;
      _adopt(value);
      phase = AdminRegistrationPhase.editing;
    } catch (error) {
      if (!_alive(ticket)) return;
      _failure(error, AdminRegistrationPhase.failed);
    }
    _emit();
  }

  void edit(String key, String value) {
    if (!editable || !fields.contains(key) || _draft[key] == value) return;
    _draft[key] = value;
    revision++;
    message = null;
    phase = AdminRegistrationPhase.editing;
    _emit();
  }

  AdminRegistrationChanges _changes() {
    final enabled = _draft['invite_code_enabled'] ?? '';
    final code = _draft['invite_code'] ?? '';
    if (enabled.isNotEmpty && !{'0', '1'}.contains(enabled)) {
      throw const FormatException('请选择有效的邀请码开关。');
    }
    if (enabled == '1' && code.isEmpty) {
      throw const FormatException('启用邀请码时请填写非空邀请码，否则所有新注册都会失败。');
    }
    return AdminRegistrationChanges(
      enabled: enabled == (_base!.records['invite_code_enabled']?.value ?? '')
          ? const AdminChange.unchanged()
          : AdminChange.set(enabled == '1'),
      code: code == (_base!.records['invite_code']?.value ?? '')
          ? const AdminChange.unchanged()
          : AdminChange.set(code),
    );
  }

  Future<void> save({int? confirmedClearRevision}) async {
    if (!editable || !dirty || _base == null) return;
    if (clearingCode && confirmedClearRevision != revision) {
      message = '清空邀请码会删除服务器保存的邀请码，请先确认。';
      _emit();
      return;
    }
    late final AdminRegistrationChanges changes;
    try {
      changes = _changes();
    } on FormatException catch (error) {
      message = error.message;
      _emit();
      return;
    }
    final ticket = _begin();
    phase = AdminRegistrationPhase.saving;
    message = null;
    _emit();
    try {
      await repository.saveRegistration(
        owner,
        _base!,
        changes,
        abortTrigger: _abort!.future,
      );
      if (!_alive(ticket)) return;
    } catch (error) {
      if (!_alive(ticket)) return;
      _failure(error, AdminRegistrationPhase.unknown);
      _emit();
      return;
    }
    phase = AdminRegistrationPhase.committedNeedsRead;
    await _readAfterWrite(ticket, knownReceipt: true);
  }

  Future<void> _readAfterWrite(int ticket, {required bool knownReceipt}) async {
    try {
      final value = await repository.read(owner, abortTrigger: _abort!.future);
      if (!_alive(ticket)) return;
      if (knownReceipt) {
        _adopt(value);
        phase = AdminRegistrationPhase.saved;
        message = '服务器已确认保存，并已读取当前配置。';
      } else {
        current = value;
        phase = AdminRegistrationPhase.reviewingCurrent;
        message = '已读取当前配置。请核对后采用；当前值不能证明上次请求的结果。';
      }
    } catch (error) {
      if (!_alive(ticket)) return;
      _failure(
        error,
        knownReceipt
            ? AdminRegistrationPhase.committedNeedsRead
            : AdminRegistrationPhase.unknown,
      );
      if (phase == AdminRegistrationPhase.committedNeedsRead) {
        message = '服务器已确认保存，回读未完成。重试只会读取配置。';
      }
    }
    _emit();
  }

  Future<void> readCurrent() async {
    if (_disposed ||
        !{
          AdminRegistrationPhase.unknown,
          AdminRegistrationPhase.committedNeedsRead,
          AdminRegistrationPhase.reviewingCurrent,
        }.contains(phase)) {
      return;
    }
    final knownReceipt = phase == AdminRegistrationPhase.committedNeedsRead;
    final ticket = _begin();
    await _readAfterWrite(ticket, knownReceipt: knownReceipt);
  }

  void adoptReviewedCurrent() {
    if (phase != AdminRegistrationPhase.reviewingCurrent || current == null) {
      return;
    }
    _adopt(current!);
    phase = AdminRegistrationPhase.editing;
    message = '已采用核对后的服务器配置。';
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
