import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'native_complex_source_io.dart';
import 'complex_source_io_runtime.dart';

/// Root-only native epoch owner. No page/lifecycle-pause observer activates it.
class ComplexSourceIoOwner {
  ComplexSourceIoOwner({bool? nativeSupported, this.invoke})
    : supported = nativeSupported ?? complexSourceIoNativeSupported;
  final bool supported;
  final SourceIoInvoke? invoke;
  ComplexSourceIoScope? _scope;
  String? _identity, _unconfirmedHash;
  Future<Map<Object?, Object?>?> _native(
    String method,
    Map<String, Object?> args,
  ) => invoke != null
      ? invoke!(method, args)
      : const MethodChannel(
          'bookstark/complex_source_io',
        ).invokeMapMethod<Object?, Object?>(method, args);
  bool _blocked = false, _closed = false;
  Future<void> _tail = Future<void>.value();
  ComplexSourceIoScope? get current => _closed || _blocked ? null : _scope;
  bool get transitionAllowed => _scope == null && !_blocked;
  bool get blocked => _blocked;
  void assertTransitionAllowed() {
    if (!transitionAllowed) {
      throw StateError('Retire native source I/O before changing space');
    }
  }

  Future<T> _serial<T>(Future<T> Function() work) {
    final result = _tail.then((_) => work());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> _retire() async {
    final previous = _scope;
    _blocked = true; // failed ACK retains the old owner and blocks publication
    if (previous != null) {
      await previous.retire();
    } else if (_unconfirmedHash != null) {
      // An activation ACK may have been lost. A fresh ordered native epoch read
      // and retirement acknowledgment must precede any Root identity change.
      final state = await _native('scopeState', {});
      final epoch = state?['epoch'];
      if (epoch is! int) throw StateError('Native epoch unavailable');
      final result = await _native('retireScope', {
        'scope': _unconfirmedHash!,
        'epoch': epoch,
      });
      if (result?['retired'] != true) {
        throw StateError('Native retirement unconfirmed');
      }
    }
    _scope = null;
    _identity = null;
    _unconfirmedHash = null;
    _blocked = false;
  }

  Future<void> beforeTransition() => _serial(_retire);
  Future<ComplexSourceIoScope?> ensure({
    required String identity,
    required bool Function() isCurrent,
  }) => _serial(() async {
    if (_closed || !isCurrent()) {
      throw StateError('Root source I/O owner retired');
    }
    if (!supported) {
      return null; // actual non-Android/web/host, never an Android RPC error
    }
    if (_blocked) {
      throw StateError('Retry native retirement before opening another owner');
    }
    if (_scope != null && _identity == identity) {
      _scope!.guard();
      return _scope;
    }
    await _retire();
    if (_closed || !isCurrent()) {
      throw StateError('Root source I/O owner retired');
    }
    _blocked = true;
    final hash = sha256
        .convert(
          utf8.encode(jsonEncode(['complex-source-io-root-v1', identity])),
        )
        .toString();
    _unconfirmedHash = hash;
    try {
      final scope = invoke == null
          ? await ComplexSourceIoScope.activate(
              scope: hash,
              isCurrent: () => !_closed && isCurrent(),
            )
          : await ComplexSourceIoScope.activate(
              scope: hash,
              isCurrent: () => !_closed && isCurrent(),
              invoke: invoke!,
            );
      _scope = scope;
      _identity = identity;
      _unconfirmedHash = null;
      _blocked = false;
      return scope;
    } catch (_) {
      // Unknown Android activation / stale CAS is not unsupported. No auto-retry
      // and no publication. Root must explicitly retire/retry before proceeding.
      _blocked = true;
      rethrow;
    }
  });
  Future<void> close() {
    _closed = true;
    return beforeTransition();
  }
}
