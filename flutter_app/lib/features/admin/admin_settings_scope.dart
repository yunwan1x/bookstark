import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/api_client.dart';
import 'admin_settings_repository.dart';

/// Lifetime belongs to the profile/server session, including pushed routes.
class AdminSettingsScope extends ChangeNotifier {
  AdminSettingsScope(this.client, this.owner)
    : _session = client.exportSession()['token'];
  final BookstarkClient client;
  final AdminPrincipal owner;
  final String? _session;
  final Set<ChangeNotifier> _owned = {};
  bool _closed = false;
  bool _disposed = false;
  bool get active =>
      !_closed &&
      _session != null &&
      _session.isNotEmpty &&
      client.exportSession()['token'] == _session;
  bool get closed => _closed;
  bool guard() {
    if (active) return true;
    close();
    return false;
  }

  T own<T extends ChangeNotifier>(T controller) {
    if (!guard()) {
      controller.dispose();
      throw StateError('Administrator settings scope ended');
    }
    _owned.add(controller);
    return controller;
  }

  void release(ChangeNotifier? controller) {
    if (controller != null && _owned.remove(controller)) controller.dispose();
  }

  void close() {
    if (_closed) return;
    _closed = true;
    final controllers = _owned.toList();
    _owned.clear();
    for (final controller in controllers) {
      controller.dispose();
    }
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    close();
    _disposed = true;
    super.dispose();
  }
}

class AdminSettingsHubController extends ChangeNotifier {
  AdminSettingsHubController(this.repository, this.owner);
  final AdminSettingsRepository repository;
  final AdminPrincipal owner;
  bool loading = false;
  bool ready = false;
  bool revoked = false;
  String? message;
  bool _disposed = false;
  int _ticket = 0;
  Completer<void>? _abort;
  Future<bool>? _loading;

  Future<bool> verify() {
    if (_disposed || revoked) return Future.value(false);
    final pending = _loading;
    if (pending != null) return pending;
    final task = _verify();
    _loading = task;
    return task.whenComplete(() {
      if (identical(_loading, task)) _loading = null;
    });
  }

  Future<bool> _verify() async {
    final ticket = ++_ticket;
    _abort = Completer<void>();
    loading = true;
    ready = false;
    message = null;
    notifyListeners();
    try {
      // No setting values are retained by this navigation screen.
      await repository.read(owner, abortTrigger: _abort!.future);
      if (_disposed || ticket != _ticket) return false;
      ready = true;
    } catch (error) {
      if (_disposed || ticket != _ticket) return false;
      revoked =
          error is StateError ||
          (error is ApiFailure && {401, 403}.contains(error.status));
      message = revoked ? '管理员身份或会话已变化，请重新进入。' : '设置读取失败，请重试。';
    } finally {
      if (!_disposed && ticket == _ticket) {
        loading = false;
        notifyListeners();
      }
    }
    return ready;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _ticket++;
    if (!(_abort?.isCompleted ?? true)) _abort!.complete();
    repository.dispose();
    super.dispose();
  }
}
