import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'admin_terminal_protocol.dart';
import 'admin_terminal_transport.dart';

enum TerminalPhase {
  review,
  verifying,
  connecting,
  ready,
  disconnected,
  background,
  revoked,
}

/// No disk state and no pending command queue. A generation is one connection.
class AdminTerminalController extends ChangeNotifier {
  AdminTerminalController({
    required this.endpoint,
    required this.token,
    required this.ownerActive,
    required this.prepare,
    required this.verifyOwner,
    TerminalTransport Function()? transportFactory,
    this.onRetire,
    this.ownerPollInterval = const Duration(seconds: 15),
    this.readyTimeout = const Duration(seconds: 25),
  }) : _factory = transportFactory ?? newTerminalTransport;
  final Uri endpoint;
  String? token;
  final bool Function() ownerActive;
  final Future<void> Function() prepare, verifyOwner;
  final TerminalTransport Function() _factory;
  final Duration ownerPollInterval, readyTimeout;
  final VoidCallback? onRetire;
  final output = TerminalOutputQueue();
  TerminalPhase phase = TerminalPhase.review;
  TerminalFailure? failure;
  int generation = 0;
  bool _disposed = false;
  int? _checkingGeneration;
  TerminalTransport? _transport;
  StreamSubscription<Object?>? _subscription;
  Timer? _ownerTimer, _readyTimer;
  bool get disposed => _disposed;

  /// A disconnected foreground view may finish its old output. It must never
  /// consume a new generation's queue or retain output after background/revoke.
  bool presentationOwnsOutput(int held) =>
      !_disposed &&
      ownerActive() &&
      ((generation == held &&
              {
                TerminalPhase.connecting,
                TerminalPhase.ready,
              }.contains(phase)) ||
          (generation == held + 1 && phase == TerminalPhase.disconnected));
  void presentationFailed(int held) {
    if (!_guard(held) || !hasSession) return;
    _retire(clear: true);
    phase = TerminalPhase.disconnected;
    failure = TerminalFailure.protocol;
    _notify();
  }

  bool get canInput =>
      !_disposed && phase == TerminalPhase.ready && ownerActive();
  bool get connecting =>
      {TerminalPhase.verifying, TerminalPhase.connecting}.contains(phase);
  bool get hasSession => connecting || phase == TerminalPhase.ready;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  bool _current(int held) =>
      !_disposed && held == generation && phase != TerminalPhase.revoked;
  bool _guard(int held) {
    if (!_current(held)) return false;
    if (!ownerActive()) {
      revoke();
      return false;
    }
    return true;
  }

  Future<void> connect() async {
    if (_disposed || phase == TerminalPhase.revoked || hasSession) return;
    _retire(clear: true);
    final held = generation;
    if (!_guard(held)) return;
    phase = TerminalPhase.verifying;
    failure = null;
    _notify();
    try {
      await prepare();
      if (!_guard(held)) return;
      final heldToken = token;
      if (heldToken == null || heldToken.isEmpty) {
        revoke();
        return;
      }
      final transport = _factory();
      _transport = transport;
      phase = TerminalPhase.connecting;
      _notify();
      final stream = await transport.connect(endpoint, heldToken);
      if (!_guard(held)) {
        transport.abort();
        return;
      }
      // HTTP101 is only the WebSocket, not an SSH-ready receipt.
      _readyTimer = Timer(readyTimeout, () {
        if (_guard(held) && phase == TerminalPhase.connecting) {
          _disconnect(TerminalFailure.network);
        }
      });
      _subscription = stream.listen(
        (frame) => _frame(held, frame),
        onError: (Object _) {
          if (_guard(held)) _disconnect(TerminalFailure.network);
        },
        onDone: () {
          if (_guard(held)) _disconnect(null);
        },
        cancelOnError: true,
      );
      _ownerTimer = Timer.periodic(
        ownerPollInterval,
        (_) => unawaited(checkOwner()),
      );
    } catch (error) {
      if (!_guard(held)) return;
      if (error is TerminalException &&
          error.kind == TerminalFailure.unauthorized) {
        revoke();
      } else {
        _disconnect(
          error is TerminalException ? error.kind : TerminalFailure.network,
        );
      }
    }
  }

  void _frame(int held, Object? frame) {
    if (!_guard(held)) return;
    try {
      final event = TerminalEvent.parse(frame);
      switch (event.kind) {
        case TerminalEventKind.ready:
          if (phase != TerminalPhase.connecting) {
            _disconnect(TerminalFailure.protocol);
            return;
          }
          _readyTimer?.cancel();
          phase = TerminalPhase.ready;
        case TerminalEventKind.output:
          // Go may write output immediately before ready on a different goroutine.
          if (phase != TerminalPhase.connecting &&
              phase != TerminalPhase.ready) {
            return;
          }
          output.add(event.output);
        case TerminalEventKind.error:
          _disconnect(TerminalFailure.network);
          return;
        case TerminalEventKind.closed:
          _disconnect(null);
          return;
      }
      _notify();
    } catch (_) {
      _disconnect(TerminalFailure.protocol);
    }
  }

  Future<void> checkOwner() async {
    if (_disposed || !hasSession || _checkingGeneration == generation) return;
    final held = generation;
    if (!_guard(held)) return;
    _checkingGeneration = held;
    try {
      await verifyOwner();
      _guard(held);
    } catch (error) {
      if (!_current(held)) return;
      if (error is TerminalException &&
          error.kind == TerminalFailure.unauthorized) {
        revoke();
      } else {
        // A failed identity check must not leave an unchecked interactive shell.
        _disconnect(TerminalFailure.network);
      }
    } finally {
      if (_checkingGeneration == held) _checkingGeneration = null;
    }
  }

  bool input(int heldGeneration, String text) {
    if (!_guard(heldGeneration) || !canInput || !terminalInputAllowed(text)) {
      return false;
    }
    try {
      _transport!.send(terminalInputFrame(text));
      return true;
    } catch (_) {
      _disconnect(TerminalFailure.network);
      return false;
    }
  }

  bool resize(int heldGeneration, int cols, int rows) {
    if (!_guard(heldGeneration) || !canInput) return false;
    try {
      _transport!.send(terminalResizeFrame(cols, rows));
      return true;
    } catch (_) {
      _disconnect(TerminalFailure.protocol);
      return false;
    }
  }

  void _retire({required bool clear}) {
    onRetire?.call();
    generation++;
    _checkingGeneration = null;
    _ownerTimer?.cancel();
    _ownerTimer = null;
    _readyTimer?.cancel();
    _readyTimer = null;
    unawaited(_subscription?.cancel());
    _subscription = null;
    _transport?.abort();
    _transport = null;
    if (clear) output.clear();
  }

  void _disconnect(TerminalFailure? reason) {
    _retire(clear: false);
    phase = TerminalPhase.disconnected;
    failure = reason;
    _notify();
  }

  void disconnect() {
    if (_disposed || phase == TerminalPhase.revoked) return;
    if (phase == TerminalPhase.ready) {
      try {
        _transport?.send(jsonEncode({'type': 'close'}));
      } catch (_) {}
    }
    _retire(clear: true);
    phase = TerminalPhase.disconnected;
    failure = null;
    _notify();
  }

  void background() {
    if (_disposed || phase == TerminalPhase.revoked) return;
    _retire(clear: true);
    phase = TerminalPhase.background;
    _notify();
  }

  void revoke() {
    if (_disposed || phase == TerminalPhase.revoked) return;
    _retire(clear: true);
    token = null;
    phase = TerminalPhase.revoked;
    failure = TerminalFailure.unauthorized;
    _notify();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _retire(clear: true);
    token = null;
    super.dispose();
  }
}
