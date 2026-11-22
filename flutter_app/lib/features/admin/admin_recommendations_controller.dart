import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/api_client.dart';
import 'admin_settings_repository.dart';
import '../../core/label_management_repository.dart';

enum AdminRecommendationsPhase {
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
class AdminRecommendationsController extends ChangeNotifier {
  AdminRecommendationsController(this.repository, this.owner);
  final AdminSettingsRepository repository;
  final AdminPrincipal owner;
  AdminRecommendationsPhase phase = AdminRecommendationsPhase.loading;
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
    'tag_recommend_strategy',
    'tag_recommend_manual_labels',
    'tag_recommend_page_size',
  };
  bool get editable =>
      !_disposed &&
      {
        AdminRecommendationsPhase.editing,
        AdminRecommendationsPhase.saved,
      }.contains(phase);
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

  void _failure(Object error, AdminRecommendationsPhase fallback) {
    if ((error is ApiFailure && {401, 403}.contains(error.status)) ||
        error is StateError) {
      _draft.clear();
      _base = null;
      current = null;
      phase = AdminRecommendationsPhase.permissionLost;
      message = '管理员身份或会话已变化，请重新进入。';
    } else {
      phase = fallback;
      message = fallback == AdminRecommendationsPhase.unknown
          ? '保存结果未知，请读取当前配置核对；不会自动重新保存。'
          : '操作未完成，请检查连接后重试。';
    }
  }

  Future<void> load() async {
    if (_disposed ||
        dirty ||
        phase == AdminRecommendationsPhase.saving ||
        phase == AdminRecommendationsPhase.unknown ||
        phase == AdminRecommendationsPhase.committedNeedsRead) {
      return;
    }
    final ticket = _begin();
    phase = AdminRecommendationsPhase.loading;
    message = null;
    _emit();
    try {
      final value = await _readConfiguration();
      if (!_alive(ticket)) return;
      _adopt(value);
      phase = AdminRecommendationsPhase.editing;
    } catch (error) {
      if (!_alive(ticket)) return;
      _failure(error, AdminRecommendationsPhase.failed);
    }
    _emit();
  }

  void edit(String key, String value) {
    if (!editable || !fields.contains(key) || _draft[key] == value) return;
    _draft[key] = value;
    revision++;
    message = null;
    phase = AdminRecommendationsPhase.editing;
    _emit();
  }

  LabelRecommendationSettings _changes() {
    final strategy = _draft['tag_recommend_strategy'];
    if (!LabelRecommendationStrategy.values.any(
      (value) => value.name == strategy,
    )) {
      throw const FormatException('请选择有效推荐策略。');
    }
    final pageSize = int.tryParse(_draft['tag_recommend_page_size'] ?? '');
    if (pageSize == null) throw const FormatException('推荐数量必须为整数。');
    final manual = _draft['tag_recommend_manual_labels'] ?? '';
    final lines = manual.split(RegExp(r'\r\n|\n|\r'));
    if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
    return LabelRecommendationSettings(
      strategy: LabelRecommendationStrategy.values.byName(strategy!),
      pageSize: pageSize,
      manualLabels: manual.isEmpty ? [] : lines,
    );
  }

  Future<AdminSettingsSnapshot> _readConfiguration() async {
    await repository.read(owner, abortTrigger: _abort!.future);
    final value = await repository.readRecommendations(
      owner,
      abortTrigger: _abort!.future,
    );
    return AdminSettingsSnapshot.parse([
      for (final entry in {
        'tag_recommend_strategy': value.strategy.name,
        'tag_recommend_page_size': value.pageSize.toString(),
        'tag_recommend_manual_labels': value.manualLabels.join('\n'),
      }.entries)
        {
          'key': entry.key,
          'value': entry.value,
          'description': '',
          'update_time': '',
        },
    ]);
  }

  Future<void> save() async {
    if (!editable || !dirty || _base == null) return;
    late final LabelRecommendationSettings changes;
    try {
      changes = _changes();
      changes.writeBody();
    } on FormatException catch (error) {
      message = error.message;
      _emit();
      return;
    }
    final ticket = _begin();
    phase = AdminRecommendationsPhase.saving;
    message = null;
    _emit();
    try {
      await repository.saveRecommendations(
        owner,
        changes,
        abortTrigger: _abort!.future,
      );
      if (!_alive(ticket)) return;
    } catch (error) {
      if (!_alive(ticket)) return;
      _failure(error, AdminRecommendationsPhase.unknown);
      _emit();
      return;
    }
    phase = AdminRecommendationsPhase.committedNeedsRead;
    await _readAfterWrite(ticket, knownReceipt: true);
  }

  Future<void> _readAfterWrite(int ticket, {required bool knownReceipt}) async {
    try {
      final value = await _readConfiguration();
      if (!_alive(ticket)) return;
      if (knownReceipt) {
        _adopt(value);
        phase = AdminRecommendationsPhase.saved;
        message = '服务器已确认保存，并已读取当前配置。';
      } else {
        current = value;
        phase = AdminRecommendationsPhase.reviewingCurrent;
        message = '请核对当前可读取配置。当前值不能证明上次请求结果。';
      }
    } catch (error) {
      if (!_alive(ticket)) return;
      _failure(
        error,
        knownReceipt
            ? AdminRecommendationsPhase.committedNeedsRead
            : AdminRecommendationsPhase.unknown,
      );
      if (phase == AdminRecommendationsPhase.committedNeedsRead) {
        message = '服务器已确认保存，回读未完成。重试只会读取配置。';
      }
    }
    _emit();
  }

  Future<void> readCurrent() async {
    if (_disposed ||
        !{
          AdminRecommendationsPhase.unknown,
          AdminRecommendationsPhase.committedNeedsRead,
          AdminRecommendationsPhase.reviewingCurrent,
        }.contains(phase)) {
      return;
    }
    final knownReceipt = phase == AdminRecommendationsPhase.committedNeedsRead;
    final ticket = _begin();
    await _readAfterWrite(ticket, knownReceipt: knownReceipt);
  }

  void adoptReviewedCurrent() {
    if (phase != AdminRecommendationsPhase.reviewingCurrent ||
        current == null) {
      return;
    }
    _adopt(current!);
    phase = AdminRecommendationsPhase.editing;
    message = '已采用当前可读取配置。此操作不会重发保存请求。';
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
