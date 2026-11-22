import 'dart:async';
import 'package:flutter/services.dart';
import '../../core/api_client.dart';

/// One active browser document per process. Retire the old document before
/// installing another account's cookies. A delayed close cannot clear its heir.
class HtmlBrowserSession {
  HtmlBrowserSession._(this.lease, this.retire);
  static const channel = MethodChannel('bookstark/html_preview_session');
  static Future<void>? _tail;
  static HtmlBrowserSession? _active;
  static int _sequence = 0;
  final String lease;
  final Future<void> Function() retire;
  bool _closed = false;
  bool _nativeClosed = false;
  Completer<void>? _closeSignal;
  Completer<void> _signal() {
    final previous = _closeSignal;
    if (previous != null) return previous;
    final signal = Completer<void>();
    // Consumers may subscribe only after retirement has started.
    signal.future.ignore();
    return _closeSignal = signal;
  }

  /// Completes after this lease's native close, never after an heir's close.
  Future<void> get closed => _closed ? Future<void>.value() : _signal().future;

  static Future<T> _ordered<T>(Future<T> Function() work) {
    final previous = _tail;
    final result = previous == null
        ? Future<T>.sync(work)
        : previous.then((_) => work());
    final tail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _tail = tail;
    tail.then((_) {
      if (identical(_tail, tail)) _tail = null;
    });
    return result;
  }

  static Future<HtmlBrowserSession> open(
    BookstarkClient client, {
    required Future<void> Function() retire,
  }) => _ordered(() async {
    final cookies = client.exportSession();
    if ((cookies['token'] ?? '').isEmpty) {
      throw StateError('Authenticated preview required');
    }
    final previous = _active;
    if (previous != null) {
      await previous._close();
    }
    final session = HtmlBrowserSession._(
      '${DateTime.now().microsecondsSinceEpoch}-${++_sequence}',
      retire,
    );
    await channel.invokeMethod<void>('open', {
      'lease': session.lease,
      'server': client.baseUri.toString(),
      'cookies': cookies,
    });
    // A logout/account replacement during the native callback must fail closed.
    if (client.exportSession()['token'] != cookies['token']) {
      await channel.invokeMethod<void>('close', {'lease': session.lease});
      throw StateError('Preview session ended');
    }
    _active = session;
    return session;
  });

  /// Shares the same exclusive queue as authenticated previews, with no cookies.
  static Future<HtmlBrowserSession> openLocal({
    required Future<void> Function() retire,
  }) => _ordered(() async {
    final previous = _active;
    if (previous != null) {
      await previous._close();
    }
    final session = HtmlBrowserSession._(
      '${DateTime.now().microsecondsSinceEpoch}-${++_sequence}',
      retire,
    );
    await channel.invokeMethod<void>('openLocal', {'lease': session.lease});
    _active = session;
    return session;
  });

  /// An isolated public browser has no authenticated cookie installation.
  static Future<HtmlBrowserSession> openPublic({
    required Future<void> Function() retire,
  }) => _ordered(() async {
    final previous = _active;
    if (previous != null) {
      await previous._close();
    }
    final session = HtmlBrowserSession._(
      '${DateTime.now().microsecondsSinceEpoch}-${++_sequence}',
      retire,
    );
    await channel.invokeMethod<void>('openPublic', {'lease': session.lease});
    _active = session;
    return session;
  });

  /// Queue this barrier even while an opening lease has not become active yet.
  static Future<void> closeActive() => _ordered(() async {
    final active = _active;
    if (active != null) await active._close();
  });

  Future<void> _close() async {
    if (_closed) return;
    final signal = _signal();
    try {
      Object? retirementError;
      StackTrace? retirementStack;
      try {
        await retire();
      } catch (error, stack) {
        retirementError = error;
        retirementStack = stack;
      }
      // Storage failure blocks identity replacement, but must not leave a live
      // WebView/cookie capability while the owner waits for a storage retry.
      if (!_nativeClosed) {
        await channel.invokeMethod<void>('close', {'lease': lease});
        _nativeClosed = true;
      }
      if (retirementError != null) {
        Error.throwWithStackTrace(retirementError, retirementStack!);
      }
      _closed = true;
      if (identical(_active, this)) _active = null;
      if (!signal.isCompleted) signal.complete();
    } catch (error, stack) {
      if (!signal.isCompleted) signal.completeError(error, stack);
      if (identical(_closeSignal, signal)) _closeSignal = null;
      rethrow;
    }
  }

  Future<void> close() => _ordered(_close);
}
