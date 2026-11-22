import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../core/api_client.dart';

enum ConnectionCheckState {
  local,
  unverified,
  checking,
  verified,
  unavailable,
  loginExpired,
  accessDenied,
}

/// User-initiated read-only checks, bound to the current workspace.
/// Server responses, account values and exception messages are never UI state.
class SettingsConnectionController extends ChangeNotifier {
  SettingsConnectionController({
    required this.local,
    required this.server,
    required this.isCurrent,
    required this.checkConnection,
    this.timeout = const Duration(seconds: 15),
  }) : state = local
           ? ConnectionCheckState.local
           : ConnectionCheckState.unverified;

  final bool local;
  final String? server;
  final bool Function() isCurrent;
  final Future<void> Function(Future<void> abort) checkConnection;
  final Duration timeout;
  ConnectionCheckState state;
  DateTime? checkedAt;
  Completer<void>? _abort;
  int _epoch = 0;
  bool _disposed = false, switching = false;
  bool get busy => switching || state == ConnectionCheckState.checking;

  String? get displayAddress {
    final value = Uri.tryParse(server ?? '');
    if (value == null ||
        !{'http', 'https'}.contains(value.scheme) ||
        value.host.isEmpty) {
      return null;
    }
    return Uri(
      scheme: value.scheme,
      host: value.host,
      port: value.hasPort ? value.port : null,
      pathSegments: value.pathSegments,
    ).toString();
  }

  void _cancel() {
    final abort = _abort;
    _abort = null;
    if (abort != null && !abort.isCompleted) abort.complete();
  }

  bool _current(int epoch) => !_disposed && epoch == _epoch && isCurrent();

  Future<void> check() async {
    if (local || busy || _disposed || !isCurrent()) return;
    final epoch = ++_epoch;
    _cancel();
    final abort = Completer<void>();
    _abort = abort;
    state = ConnectionCheckState.checking;
    checkedAt = null;
    notifyListeners();
    try {
      await checkConnection(abort.future).timeout(
        timeout,
        onTimeout: () {
          if (!abort.isCompleted) abort.complete();
          throw TimeoutException('Connection check deadline');
        },
      );
      if (!_current(epoch)) return;
      state = ConnectionCheckState.verified;
      checkedAt = DateTime.now();
    } catch (error) {
      if (!_current(epoch)) return;
      state = error is ApiFailure && error.status == 401
          ? ConnectionCheckState.loginExpired
          : error is ApiFailure && error.status == 403
          ? ConnectionCheckState.accessDenied
          : ConnectionCheckState.unavailable;
    } finally {
      if (identical(_abort, abort)) _abort = null;
      if (_current(epoch)) notifyListeners();
    }
  }

  /// The route provides the actual draft barrier and retire-before-switch.
  /// An error propagates to the route; this controller never discards content.
  Future<void> switchSpace({
    required Future<void> Function() prepare,
    required Future<void> Function() enter,
  }) async {
    if (_disposed || switching || !isCurrent()) return;
    final epoch = ++_epoch;
    _cancel();
    if (state == ConnectionCheckState.checking) {
      state = ConnectionCheckState.unverified;
    }
    switching = true;
    notifyListeners();
    try {
      await prepare();
      if (!_current(epoch)) return;
      await enter();
    } finally {
      switching = false;
      if (_current(epoch)) notifyListeners();
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    ++_epoch;
    _cancel();
    super.dispose();
  }
}
