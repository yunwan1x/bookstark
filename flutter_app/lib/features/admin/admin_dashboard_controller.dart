import 'dart:async';

import 'package:bookstark_flutter/core/api_client.dart';

import 'admin_dashboard_repository.dart';

enum DashboardLoadState { idle, loading, loaded, failed }

class DashboardSection<T> {
  const DashboardSection({this.state = DashboardLoadState.idle, this.value});

  final DashboardLoadState state;
  final T? value;
  DashboardSection<T> loading({bool clearValue = false}) => DashboardSection<T>(
    state: DashboardLoadState.loading,
    value: clearValue ? null : value,
  );

  DashboardSection<T> loaded(T next) =>
      DashboardSection<T>(state: DashboardLoadState.loaded, value: next);

  DashboardSection<T> failed() =>
      DashboardSection<T>(state: DashboardLoadState.failed);

  DashboardSection<T> cleared() => DashboardSection<T>();
}

/// Presentation state for the three read-only endpoints. Every request is
/// bound to a local request generation and can be aborted on range change,
/// account/session exit, or disposal. Late HTTP completions are discarded even
/// when the underlying transport cannot abort.
class AdminDashboardController {
  AdminDashboardController(this.repository);

  final AdminDashboardRepository repository;
  DashboardRange range = DashboardRange.days7;
  DashboardSection<DashboardStats> stats = const DashboardSection();
  DashboardSection<List<DashboardTrendPoint>> trend = const DashboardSection();
  DashboardSection<DashboardLogPage> logs = const DashboardSection();
  bool sessionRevoked = false;
  bool _disposed = false;
  bool _started = false;
  int _rangeGeneration = 0;
  int _logsGeneration = 0;
  int _requestedLogsPage = 1;
  Completer<void>? _rangeAbort;
  Completer<void>? _logsAbort;
  final _listeners = <void Function()>[];

  void addListener(void Function() listener) => _listeners.add(listener);
  void removeListener(void Function() listener) => _listeners.remove(listener);

  void _notify() {
    if (_disposed) return;
    for (final listener in List<void Function()>.of(_listeners)) {
      listener();
    }
  }

  void initialize() {
    if (_started || _disposed) return;
    _started = true;
    _reloadRange(clear: true);
    _loadLogs(1, clear: true);
  }

  void changeRange(DashboardRange next) {
    if (_disposed || sessionRevoked || range == next) return;
    range = next;
    _reloadRange(clear: true);
  }

  Future<void> retryStats() =>
      _loadStats(range, _rangeGeneration, _rangeAbort?.future, clear: false);

  Future<void> retryTrend() =>
      _loadTrend(range, _rangeGeneration, _rangeAbort?.future, clear: false);

  Future<void> retryLogs() => _loadLogs(_requestedLogsPage, clear: false);

  void refresh() {
    if (_disposed || sessionRevoked) return;
    _reloadRange(clear: true);
    _loadLogs(_requestedLogsPage, clear: true);
  }

  Future<void> loadLogsPage(int page) {
    if (_disposed || sessionRevoked) return Future<void>.value();
    final current = logs.value;
    if (page < 1 || (current != null && page > current.totalPages)) {
      return Future<void>.value();
    }
    return _loadLogs(page, clear: true);
  }

  void _reloadRange({required bool clear}) {
    _cancelRange();
    final generation = ++_rangeGeneration;
    final abort = _rangeAbort = Completer<void>();
    stats = stats.loading(clearValue: clear);
    trend = trend.loading(clearValue: clear);
    _notify();
    unawaited(_loadStats(range, generation, abort.future, clear: clear));
    unawaited(_loadTrend(range, generation, abort.future, clear: clear));
  }

  Future<void> _loadStats(
    DashboardRange requestedRange,
    int generation,
    Future<void>? abort, {
    required bool clear,
  }) async {
    if (_disposed || sessionRevoked) return;
    stats = stats.loading(clearValue: clear);
    _notify();
    try {
      final value = await repository.stats(requestedRange, abortTrigger: abort);
      if (!_disposed && !sessionRevoked && generation == _rangeGeneration) {
        stats = stats.loaded(value);
        _notify();
      }
    } catch (error) {
      if (_disposed || generation != _rangeGeneration || sessionRevoked) return;
      if (_handlePermissionFailure(error)) return;
      stats = stats.failed();
      _notify();
    }
  }

  Future<void> _loadTrend(
    DashboardRange requestedRange,
    int generation,
    Future<void>? abort, {
    required bool clear,
  }) async {
    if (_disposed || sessionRevoked) return;
    trend = trend.loading(clearValue: clear);
    _notify();
    try {
      final value = await repository.trend(requestedRange, abortTrigger: abort);
      if (!_disposed && !sessionRevoked && generation == _rangeGeneration) {
        trend = trend.loaded(value);
        _notify();
      }
    } catch (error) {
      if (_disposed || generation != _rangeGeneration || sessionRevoked) return;
      if (_handlePermissionFailure(error)) return;
      trend = trend.failed();
      _notify();
    }
  }

  Future<void> _loadLogs(int page, {required bool clear}) async {
    if (_disposed || sessionRevoked) return;
    _requestedLogsPage = page;
    _cancelLogs();
    final generation = ++_logsGeneration;
    final abort = _logsAbort = Completer<void>();
    logs = logs.loading(clearValue: clear);
    _notify();
    try {
      final value = await repository.logs(page, abortTrigger: abort.future);
      if (!_disposed && !sessionRevoked && generation == _logsGeneration) {
        logs = logs.loaded(value);
        _notify();
      }
    } catch (error) {
      if (_disposed || generation != _logsGeneration || sessionRevoked) return;
      if (_handlePermissionFailure(error)) return;
      logs = logs.failed();
      _notify();
    }
  }

  bool _handlePermissionFailure(Object error) {
    if (error is! ApiFailure || (error.status != 401 && error.status != 403)) {
      return false;
    }
    sessionRevoked = true;
    _rangeGeneration++;
    _logsGeneration++;
    _cancelRange();
    _cancelLogs();
    stats = stats.cleared();
    trend = trend.cleared();
    logs = logs.cleared();
    _notify();
    return true;
  }

  void clearForSessionExit() {
    if (_disposed) return;
    _rangeGeneration++;
    _logsGeneration++;
    _cancelRange();
    _cancelLogs();
    stats = stats.cleared();
    trend = trend.cleared();
    logs = logs.cleared();
    sessionRevoked = true;
    _notify();
  }

  void _cancelRange() {
    final abort = _rangeAbort;
    _rangeAbort = null;
    if (abort != null && !abort.isCompleted) abort.complete();
  }

  void _cancelLogs() {
    final abort = _logsAbort;
    _logsAbort = null;
    if (abort != null && !abort.isCompleted) abort.complete();
  }

  void dispose() {
    if (_disposed) return;
    _rangeGeneration++;
    _logsGeneration++;
    _cancelRange();
    _cancelLogs();
    stats = stats.cleared();
    trend = trend.cleared();
    logs = logs.cleared();
    sessionRevoked = true;
    _disposed = true;
    _listeners.clear();
  }
}
