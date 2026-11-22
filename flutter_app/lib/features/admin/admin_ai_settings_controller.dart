import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/api_client.dart';
import 'admin_settings_repository.dart';

enum AdminAiPhase {
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
class AdminAiSettingsController extends ChangeNotifier {
  AdminAiSettingsController(this.repository, this.owner);

  final AdminSettingsRepository repository;
  final AdminPrincipal owner;
  AdminAiPhase phase = AdminAiPhase.loading;
  AdminSettingsSnapshot? _base;
  AdminSettingsSnapshot? current;
  final Map<String, String> _draft = {};
  Map<String, String> get draft => Map.unmodifiable(_draft);
  AdminSettingsSnapshot? get baseline => _base;
  AdminAiTestOutcome? testOutcome;
  bool testRunning = false;
  bool testStale = false;
  String? message;
  int revision = 0;
  int _ticket = 0;
  bool _disposed = false;
  Completer<void>? _abort;

  static const fields = {
    'ai_enabled',
    'ai_provider',
    'ai_base_url',
    'ai_api_key',
    'ai_model',
    'ai_temperature',
    'ai_max_tokens',
  };

  bool get editable =>
      !_disposed &&
      !testRunning &&
      {AdminAiPhase.editing, AdminAiPhase.saved}.contains(phase);
  bool get dirty =>
      _base != null &&
      fields.any(
        (key) => (_draft[key] ?? '') != (_base!.records[key]?.value ?? ''),
      );
  bool get clearingKey =>
      (_base?.ai.apiKey?.isNotEmpty ?? false) &&
      (_draft['ai_api_key'] ?? '').isEmpty;
  bool get testUsesSavedFallback => const [
    'ai_provider',
    'ai_base_url',
    'ai_api_key',
    'ai_model',
  ].any((key) => (_draft[key] ?? '').isEmpty);

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
    testOutcome = null;
    testStale = false;
  }

  void _failure(Object error, AdminAiPhase fallback) {
    if ((error is ApiFailure && {401, 403}.contains(error.status)) ||
        error is StateError) {
      _draft.clear();
      _base = null;
      current = null;
      testOutcome = null;
      phase = AdminAiPhase.permissionLost;
      message = '管理员身份或会话已变化，请重新进入。';
    } else {
      phase = fallback;
      message = fallback == AdminAiPhase.unknown
          ? '保存结果未知，请读取当前配置核对；不会自动重新保存。'
          : '操作未完成，请检查连接后重试。';
    }
  }

  Future<void> load() async {
    if (_disposed ||
        dirty ||
        phase == AdminAiPhase.saving ||
        phase == AdminAiPhase.unknown ||
        phase == AdminAiPhase.committedNeedsRead) {
      return;
    }
    final ticket = _begin();
    phase = AdminAiPhase.loading;
    message = null;
    _emit();
    try {
      final value = await repository.read(owner, abortTrigger: _abort!.future);
      if (!_alive(ticket)) return;
      _adopt(value);
      phase = AdminAiPhase.editing;
    } catch (error) {
      if (!_alive(ticket)) return;
      _failure(error, AdminAiPhase.failed);
    }
    _emit();
  }

  void edit(String key, String value) {
    if (!editable || !fields.contains(key) || _draft[key] == value) return;
    _draft[key] = value;
    revision++;
    testStale = testOutcome != null || testStale;
    message = null;
    phase = AdminAiPhase.editing;
    _emit();
  }

  AdminAiChanges _changes() {
    AdminChange<String> text(String key) =>
        _draft[key] == (_base!.records[key]?.value ?? '')
        ? const AdminChange.unchanged()
        : AdminChange.set(_draft[key] ?? '');
    final enabled = text('ai_enabled');
    final temperature = text('ai_temperature');
    final maxTokens = text('ai_max_tokens');
    if (enabled.changed && !{'0', '1'}.contains(enabled.value)) {
      throw const FormatException('请选择有效的启用状态。');
    }
    final url = _draft['ai_base_url'] ?? '';
    if (url.isNotEmpty) {
      final uri = Uri.tryParse(url);
      if (uri == null ||
          !{'http', 'https'}.contains(uri.scheme) ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty) {
        throw const FormatException('请输入有效的 HTTP/HTTPS 接口地址。');
      }
    }
    final t = temperature.changed
        ? double.tryParse(temperature.value ?? '')
        : null;
    final m = maxTokens.changed ? int.tryParse(maxTokens.value ?? '') : null;
    if (temperature.changed && (t == null || !t.isFinite)) {
      throw const FormatException('温度必须为有限数字。');
    }
    if (maxTokens.changed && m == null) {
      throw const FormatException('最大输出必须为整数。');
    }
    return AdminAiChanges(
      enabled: enabled.changed
          ? AdminChange.set(enabled.value == '1')
          : const AdminChange.unchanged(),
      provider: text('ai_provider'),
      baseUrl: text('ai_base_url'),
      apiKey: text('ai_api_key'),
      model: text('ai_model'),
      temperature: temperature.changed
          ? AdminChange.set(t!)
          : const AdminChange.unchanged(),
      maxTokens: maxTokens.changed
          ? AdminChange.set(m!)
          : const AdminChange.unchanged(),
    );
  }

  Future<void> save({int? confirmedClearRevision}) async {
    if (!editable || !dirty || _base == null) return;
    if (clearingKey && confirmedClearRevision != revision) {
      message = '清空 API Key 会删除服务器保存的密钥，请先确认。';
      _emit();
      return;
    }
    late final AdminAiChanges changes;
    try {
      changes = _changes();
    } on FormatException catch (error) {
      message = error.message;
      _emit();
      return;
    }
    final ticket = _begin();
    phase = AdminAiPhase.saving;
    message = null;
    _emit();
    try {
      await repository.saveAi(
        owner,
        _base!,
        changes,
        abortTrigger: _abort!.future,
      );
      if (!_alive(ticket)) return;
    } catch (error) {
      if (!_alive(ticket)) return;
      _failure(error, AdminAiPhase.unknown);
      _emit();
      return;
    }
    phase = AdminAiPhase.committedNeedsRead;
    await _readAfterWrite(ticket, knownReceipt: true);
  }

  Future<void> _readAfterWrite(int ticket, {required bool knownReceipt}) async {
    try {
      final value = await repository.read(owner, abortTrigger: _abort!.future);
      if (!_alive(ticket)) return;
      if (knownReceipt) {
        _adopt(value);
        phase = AdminAiPhase.saved;
        message = '服务器已确认保存，并已读取当前配置。';
      } else {
        current = value;
        phase = AdminAiPhase.reviewingCurrent;
        message = '已读取当前配置。请核对后采用；当前值不能证明上次请求的结果。';
      }
    } catch (error) {
      if (!_alive(ticket)) return;
      _failure(
        error,
        knownReceipt ? AdminAiPhase.committedNeedsRead : AdminAiPhase.unknown,
      );
      if (phase == AdminAiPhase.committedNeedsRead) {
        message = '服务器已确认保存，回读未完成。重试只会读取配置。';
      }
    }
    _emit();
  }

  Future<void> readCurrent() async {
    if (_disposed ||
        !{
          AdminAiPhase.unknown,
          AdminAiPhase.committedNeedsRead,
          AdminAiPhase.reviewingCurrent,
        }.contains(phase)) {
      return;
    }
    final knownReceipt = phase == AdminAiPhase.committedNeedsRead;
    final ticket = _begin();
    await _readAfterWrite(ticket, knownReceipt: knownReceipt);
  }

  void adoptReviewedCurrent() {
    if (phase != AdminAiPhase.reviewingCurrent || current == null) return;
    _adopt(current!);
    phase = AdminAiPhase.editing;
    message = '已采用核对后的服务器配置。';
    _emit();
  }

  Future<void> testConnection() async {
    if (!editable || _base == null) return;
    final ticket = _begin();
    testRunning = true;
    testOutcome = null;
    testStale = false;
    message = null;
    _emit();
    try {
      final result = await repository.testAi(
        owner,
        provider: _draft['ai_provider'] ?? '',
        baseUrl: _draft['ai_base_url'] ?? '',
        apiKey: _draft['ai_api_key'] ?? '',
        model: _draft['ai_model'] ?? '',
        abortTrigger: _abort!.future,
      );
      if (!_alive(ticket)) return;
      testOutcome = result;
    } catch (error) {
      if (!_alive(ticket)) return;
      _failure(error, AdminAiPhase.editing);
    } finally {
      if (_alive(ticket)) {
        testRunning = false;
        _emit();
      }
    }
  }

  void cancelTest() {
    if (!testRunning || _disposed) return;
    _cancel();
    _ticket++;
    testRunning = false;
    testOutcome = null;
    testStale = true;
    message = '已取消测试，迟到结果不会采用。';
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
    testOutcome = null;
    repository.dispose();
    super.dispose();
  }
}
