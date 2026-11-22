import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/api_client.dart';
import 'admin_settings_repository.dart';
import 'admin_public_tags.dart';

enum AdminPublicTagsPhase {
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
class AdminPublicTagsController extends ChangeNotifier {
  AdminPublicTagsController(this.repository, this.owner);
  final List<AdminPublicTagKind> tagKinds = List.unmodifiable(
    AdminPublicTagKind.values,
  );
  AdminPublicTagKind selected = AdminPublicTagKind.article;
  final AdminSettingsRepository repository;
  final AdminPrincipal owner;
  AdminPublicTagsPhase phase = AdminPublicTagsPhase.loading;
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

  Set<String> get fields => tagKinds.map((field) => field.key).toSet();
  bool get editable =>
      !_disposed &&
      {
        AdminPublicTagsPhase.editing,
        AdminPublicTagsPhase.saved,
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

  void _failure(Object error, AdminPublicTagsPhase fallback) {
    if ((error is ApiFailure && {401, 403}.contains(error.status)) ||
        error is StateError) {
      _draft.clear();
      _base = null;
      current = null;
      phase = AdminPublicTagsPhase.permissionLost;
      message = '管理员身份或会话已变化，请重新进入。';
    } else {
      phase = fallback;
      message = fallback == AdminPublicTagsPhase.unknown
          ? '保存结果未知，请读取当前配置核对；不会自动重新保存。'
          : '操作未完成，请检查连接后重试。';
    }
  }

  Future<void> load() async {
    if (_disposed ||
        dirty ||
        phase == AdminPublicTagsPhase.saving ||
        phase == AdminPublicTagsPhase.unknown ||
        phase == AdminPublicTagsPhase.committedNeedsRead) {
      return;
    }
    final ticket = _begin();
    phase = AdminPublicTagsPhase.loading;
    message = null;
    _emit();
    try {
      final value = await repository.read(owner, abortTrigger: _abort!.future);
      if (!_alive(ticket)) return;
      _adopt(value);
      phase = AdminPublicTagsPhase.editing;
    } catch (error) {
      if (!_alive(ticket)) return;
      _failure(error, AdminPublicTagsPhase.failed);
    }
    _emit();
  }

  void edit(String key, String value) {
    if (!editable || !fields.contains(key) || _draft[key] == value) return;
    _draft[key] = value;
    revision++;
    message = null;
    phase = AdminPublicTagsPhase.editing;
    _emit();
  }

  String get text => _draft[selected.key] ?? '';
  void select(AdminPublicTagKind kind) {
    if (!editable || selected == kind) return;
    selected = kind;
    revision++;
    _emit();
  }

  void editRaw(String value) => edit(selected.key, value);
  void editMode(String mode) {
    if (!editable) return;
    try {
      final config = AdminPublicTagConfig.decodeForEditing(text);
      editRaw(config.changeMode(mode));
    } on FormatException catch (error) {
      message = error.message;
      _emit();
    }
  }

  void editLabels(String value) {
    if (!editable) return;
    try {
      final config = AdminPublicTagConfig.decodeForEditing(text);
      editRaw(config.changeLabels(value));
    } on FormatException catch (error) {
      message = error.message;
      _emit();
    }
  }

  void replaceReviewedInvalid({
    required int confirmedRevision,
    required String mode,
  }) {
    if (!editable || revision != confirmedRevision) return;
    editRaw(AdminPublicTagConfig.create(mode));
  }

  AdminPublicTagChanges _changes() => AdminPublicTagChanges({
    for (final field in tagKinds)
      if ((_draft[field.key] ?? '') != (_base!.records[field.key]?.value ?? ''))
        field: _draft[field.key] ?? '',
  });

  Future<void> save() async {
    if (!editable || !dirty || _base == null) return;
    late final AdminPublicTagChanges changes;
    try {
      changes = _changes();
      changes.patch(_base!);
    } on FormatException catch (error) {
      message = error.message;
      _emit();
      return;
    }
    final ticket = _begin();
    phase = AdminPublicTagsPhase.saving;
    message = null;
    _emit();
    try {
      await repository.savePublicTags(
        owner,
        _base!,
        changes,
        abortTrigger: _abort!.future,
      );
      if (!_alive(ticket)) return;
    } catch (error) {
      if (!_alive(ticket)) return;
      _failure(error, AdminPublicTagsPhase.unknown);
      _emit();
      return;
    }
    phase = AdminPublicTagsPhase.committedNeedsRead;
    await _readAfterWrite(ticket, knownReceipt: true);
  }

  Future<void> _readAfterWrite(int ticket, {required bool knownReceipt}) async {
    try {
      final value = await repository.read(owner, abortTrigger: _abort!.future);
      if (!_alive(ticket)) return;
      if (knownReceipt) {
        _adopt(value);
        phase = AdminPublicTagsPhase.saved;
        message = '服务器已确认保存，并已读取当前配置。';
      } else {
        current = value;
        phase = AdminPublicTagsPhase.reviewingCurrent;
        message = '请核对当前可读取配置。当前值不能证明上次请求结果。';
      }
    } catch (error) {
      if (!_alive(ticket)) return;
      _failure(
        error,
        knownReceipt
            ? AdminPublicTagsPhase.committedNeedsRead
            : AdminPublicTagsPhase.unknown,
      );
      if (phase == AdminPublicTagsPhase.committedNeedsRead) {
        message = '服务器已确认保存，回读未完成。重试只会读取配置。';
      }
    }
    _emit();
  }

  Future<void> readCurrent() async {
    if (_disposed ||
        !{
          AdminPublicTagsPhase.unknown,
          AdminPublicTagsPhase.committedNeedsRead,
          AdminPublicTagsPhase.reviewingCurrent,
        }.contains(phase)) {
      return;
    }
    final knownReceipt = phase == AdminPublicTagsPhase.committedNeedsRead;
    final ticket = _begin();
    await _readAfterWrite(ticket, knownReceipt: knownReceipt);
  }

  void adoptReviewedCurrent() {
    if (phase != AdminPublicTagsPhase.reviewingCurrent || current == null) {
      return;
    }
    _adopt(current!);
    phase = AdminPublicTagsPhase.editing;
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
