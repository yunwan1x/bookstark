import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/api_client.dart';
import 'admin_settings_repository.dart';

enum AdminTextPhase {
  loading,
  editing,
  saving,
  resetting,
  unknown,
  receiptNeedsRead,
  reviewingCurrent,
  permissionLost,
  failed,
}

class AdminTextSettingsController extends ChangeNotifier {
  AdminTextSettingsController(
    this.repository,
    this.owner, {
    required this.prompts,
  }) : fields = List.unmodifiable(
         AdminAiTextField.values.where(
           (field) => field.systemPrompt == prompts,
         ),
       );
  final AdminSettingsRepository repository;
  final AdminPrincipal owner;
  final bool prompts;
  final List<AdminAiTextField> fields;
  late AdminAiTextField selected = fields.first;
  final Map<AdminAiTextField, String> _draft = {};
  AdminSettingsSnapshot? _base;
  AdminSettingsSnapshot? current;
  AdminAiTextField? _resetField;
  Map<AdminAiTextField, String>? _pending;
  bool _knownReceipt = false;
  AdminTextPhase phase = AdminTextPhase.loading;
  String? message;
  int revision = 0;
  int _ticket = 0;
  bool _disposed = false;
  Completer<void>? _abort;
  String get text => _draft[selected] ?? '';
  bool get editable => !_disposed && phase == AdminTextPhase.editing;
  bool get dirty => fields.any(
    (field) =>
        (_draft[field] ?? '') != (_base?.records[field.key]?.value ?? ''),
  );
  Map<AdminAiTextField, String> get drafts => Map.unmodifiable(_draft);
  bool _alive(int ticket) => !_disposed && ticket == _ticket;
  void _emit() {
    if (!_disposed) notifyListeners();
  }

  void _cancel() {
    if (!(_abort?.isCompleted ?? true)) _abort!.complete();
  }

  int _begin() {
    _cancel();
    _abort = Completer<void>();
    return ++_ticket;
  }

  void _adopt(AdminSettingsSnapshot value) {
    _base = value;
    _draft
      ..clear()
      ..addEntries(
        fields.map(
          (field) => MapEntry(field, value.records[field.key]?.value ?? ''),
        ),
      );
    current = null;
    _pending = null;
    _resetField = null;
    revision++;
  }

  void _fail(Object error, AdminTextPhase fallback) {
    if ((error is ApiFailure && {401, 403}.contains(error.status)) ||
        error is StateError) {
      _base = null;
      current = null;
      _draft.clear();
      _pending = null;
      phase = AdminTextPhase.permissionLost;
      message = '管理员身份或会话已变化，请重新进入。';
    } else {
      phase = fallback;
      message = fallback == AdminTextPhase.unknown
          ? '结果未知，请读取服务器当前文本核对，不会自动重发。'
          : '读取未完成，请重试读取。';
    }
  }

  Future<void> load() async {
    if (_disposed ||
        dirty ||
        !{AdminTextPhase.loading, AdminTextPhase.failed}.contains(phase)) {
      return;
    }
    final ticket = _begin();
    phase = AdminTextPhase.loading;
    _emit();
    try {
      final value = await repository.read(owner, abortTrigger: _abort!.future);
      if (!_alive(ticket)) return;
      _adopt(value);
      phase = AdminTextPhase.editing;
      message = null;
    } catch (error) {
      if (!_alive(ticket)) return;
      _fail(error, AdminTextPhase.failed);
    }
    _emit();
  }

  void select(AdminAiTextField field) {
    if (!editable || !fields.contains(field) || selected == field) return;
    selected = field;
    revision++;
    _emit();
  }

  void edit(String value) {
    if (!editable || text == value) return;
    _draft[selected] = value;
    revision++;
    message = null;
    _emit();
  }

  Future<void> save() async {
    if (!editable || !dirty || _base == null) return;
    final changes = AdminTextChanges({
      for (final field in fields) field: AdminChange.set(_draft[field] ?? ''),
    });
    _pending = Map.of(_draft);
    _resetField = null;
    _knownReceipt = false;
    final ticket = _begin();
    phase = AdminTextPhase.saving;
    message = null;
    _emit();
    try {
      await repository.saveText(
        owner,
        _base!,
        changes,
        abortTrigger: _abort!.future,
      );
      if (!_alive(ticket)) return;
      _knownReceipt = true;
      phase = AdminTextPhase.receiptNeedsRead;
    } catch (error) {
      if (!_alive(ticket)) return;
      _fail(error, AdminTextPhase.unknown);
      _emit();
      return;
    }
    await _read(ticket);
  }

  /// Confirmation belongs to the exact selected field and draft revision.
  Future<void> resetToDefault({
    required AdminAiTextField confirmedField,
    required int confirmedRevision,
  }) async {
    if (!editable ||
        confirmedField != selected ||
        confirmedRevision != revision ||
        _base == null) {
      return;
    }
    _pending = Map.of(_draft);
    _resetField = selected;
    _knownReceipt = false;
    final ticket = _begin();
    phase = AdminTextPhase.resetting;
    message = null;
    _emit();
    try {
      final receipt = await repository.resetTextToDefault(
        owner,
        confirmedField,
        abortTrigger: _abort!.future,
      );
      if (!_alive(ticket)) return;
      _pending![confirmedField] = receipt.value;
      _knownReceipt = true;
      phase = AdminTextPhase.receiptNeedsRead;
    } catch (error) {
      if (!_alive(ticket)) return;
      _fail(error, AdminTextPhase.unknown);
      _emit();
      return;
    }
    await _read(ticket);
  }

  Future<void> _read(int ticket) async {
    try {
      final value = await repository.read(owner, abortTrigger: _abort!.future);
      if (!_alive(ticket)) return;
      if (!_knownReceipt) {
        current = value;
        phase = AdminTextPhase.reviewingCurrent;
        message = '请核对服务器当前文本；当前内容不能证明上次请求的结果。';
      } else {
        final pending = _pending;
        final reset = _resetField;
        _adopt(value);
        // Reset writes one field immediately; preserve every other scene draft.
        if (reset != null && pending != null) {
          for (final field in fields) {
            if (field != reset) _draft[field] = pending[field] ?? '';
          }
        }
        phase = AdminTextPhase.editing;
        message = '服务器已确认操作，并已读取当前文本。';
      }
    } catch (error) {
      if (!_alive(ticket)) return;
      _fail(
        error,
        _knownReceipt
            ? AdminTextPhase.receiptNeedsRead
            : AdminTextPhase.unknown,
      );
      if (phase == AdminTextPhase.receiptNeedsRead) {
        message = '服务器已确认操作，回读未完成；重试只会读取。';
      }
    }
    _emit();
  }

  Future<void> readCurrent() async {
    if (_disposed ||
        !{
          AdminTextPhase.unknown,
          AdminTextPhase.receiptNeedsRead,
          AdminTextPhase.reviewingCurrent,
        }.contains(phase)) {
      return;
    }
    await _read(_begin());
  }

  void adoptReviewedCurrent() {
    if (phase != AdminTextPhase.reviewingCurrent || current == null) return;
    // Unknown reset must not discard drafts in unrelated scenes.
    final pending = _pending;
    final reset = _resetField;
    final value = current!;
    _adopt(value);
    if (reset != null && pending != null) {
      for (final field in fields) {
        if (field != reset) _draft[field] = pending[field] ?? '';
      }
    }
    phase = AdminTextPhase.editing;
    message = '已采用核对后的服务器文本。';
    _emit();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _ticket++;
    _cancel();
    _draft.clear();
    _pending = null;
    _base = null;
    current = null;
    repository.dispose();
    super.dispose();
  }
}
