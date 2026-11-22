import 'dart:async';
import 'package:flutter/services.dart';
import 'attachments.dart';
import 'local_backup_codec.dart';

typedef LocalBackupPickerInvoke =
    Future<Object?> Function(String method, Map<String, Object?> arguments);

class PickedLocalBackup {
  PickedLocalBackup._(this.id, this.bytes, this.sha256);
  final String id, sha256;
  final int bytes;
}

/// Only opaque inbox identities cross this port; never content URIs or paths.
class NativeLocalBackupPicker {
  NativeLocalBackupPicker({
    LocalBackupPickerInvoke? invoke,
    String Function()? identity,
    this.timeout = const Duration(minutes: 10),
  }) : _invoke =
           invoke ??
           ((method, arguments) =>
               channel.invokeMethod<Object?>(method, arguments)),
       _identity = identity ?? attachmentId {
    if (timeout <= Duration.zero) {
      throw ArgumentError('Positive timeout required');
    }
  }
  static const channel = MethodChannel('bookstark/local_backup_picker');
  final LocalBackupPickerInvoke _invoke;
  final String Function() _identity;
  final Duration timeout;
  String? _active;
  bool _disposed = false;
  Completer<void>? _abortWait;
  Future<void>? _cancelFuture, _disposeFuture;

  PickedLocalBackup? _receipt(Object? raw, String id) {
    if (raw is! Map ||
        raw['format'] is! int ||
        raw['format'] != 1 ||
        raw['cancelled'] is! bool) {
      throw const FormatException('Invalid backup picker receipt');
    }
    if (raw['cancelled'] == true) {
      if (raw.length != 2) {
        throw const FormatException('Invalid cancellation receipt');
      }
      return null;
    }
    final bytes = raw['bytes'], hash = raw['sha256'];
    if (raw.length != 5 ||
        raw['id'] != id ||
        bytes is! int ||
        bytes <= 0 ||
        bytes > LocalBackupCodec.maxArchiveBytes ||
        hash is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)) {
      throw const FormatException('Unbound backup inbox receipt');
    }
    return PickedLocalBackup._(id, bytes, hash);
  }

  Future<PickedLocalBackup?> pick() async {
    if (_disposed) throw StateError('Backup picker owner was disposed');
    if (_active != null) throw StateError('Backup selection already active');
    final id = _identity();
    _checkId(id);
    _active = id;
    _cancelFuture = null;
    final abort = Completer<void>();
    _abortWait = abort;
    var abandoned = false;
    try {
      final native = _invoke('pick', {'id': id});
      unawaited(
        native.then<void>((raw) async {
          if (!_disposed && !abandoned) return;
          try {
            // Only a bound completed receipt authorizes cleanup of this owner's
            // generated inbox identity. Native refuses any still-active copy.
            if (_receipt(raw, id) != null) await _releaseOwned(id);
          } catch (_) {
            // An unconfirmed private copy stays retained; never delete another ID.
          }
        }, onError: (Object _, StackTrace _) {}),
      );
      final raw =
          await Future.any<Object?>([
            native,
            abort.future.then<Object?>(
              (_) => throw const AttachmentCancelled(),
            ),
          ]).timeout(
            timeout,
            onTimeout: () {
              abandoned = true;
              throw TimeoutException(
                'Backup document selection deadline',
                timeout,
              );
            },
          );
      if (_disposed) throw const AttachmentCancelled();
      return _receipt(raw, id);
    } on TimeoutException {
      try {
        await cancel();
      } catch (_) {
        // Native also cancels on activity destruction and its copy deadline.
      }
      rethrow;
    } finally {
      _active = null;
      if (identical(_abortWait, abort)) _abortWait = null;
    }
  }

  Future<void> cancel() {
    final pending = _cancelFuture;
    if (pending != null) return pending;
    final id = _active;
    if (id == null) return Future<void>.value();
    return _cancelFuture ??= _cancel(id);
  }

  Future<void> _cancel(String id) async {
    final raw = await _invoke('cancel', {
      'id': id,
    }).timeout(const Duration(seconds: 5));
    if (raw is! Map ||
        raw.length != 2 ||
        raw['format'] is! int ||
        raw['format'] != 1 ||
        raw['cancelled'] != true) {
      throw const FormatException('Invalid picker cancellation');
    }
  }

  /// Retires this owner's wait immediately, even if Android's document activity
  /// has not returned. A late bound copy is cleaned through the native owner.
  Future<void> dispose() {
    final previous = _disposeFuture;
    if (previous != null) return previous;
    _disposed = true;
    final cancellation = cancel();
    final abort = _abortWait;
    if (abort != null && !abort.isCompleted) abort.complete();
    return _disposeFuture = cancellation;
  }

  Future<void> release(PickedLocalBackup picked) async {
    _checkId(picked.id);
    if (_active == picked.id) throw StateError('Backup selection is active');
    await _releaseOwned(picked.id);
  }

  Future<void> _releaseOwned(String id) async {
    final raw = await _invoke('release', {
      'id': id,
    }).timeout(const Duration(seconds: 10));
    if (raw is! Map ||
        raw.length != 2 ||
        raw['format'] is! int ||
        raw['format'] != 1 ||
        raw['released'] != id) {
      throw const FormatException('Unbound inbox release receipt');
    }
  }

  void _checkId(String id) {
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(id)) {
      throw const FormatException('Invalid backup inbox identity');
    }
  }
}
