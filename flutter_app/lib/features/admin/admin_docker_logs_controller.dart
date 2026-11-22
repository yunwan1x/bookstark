import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../core/api_client.dart';
import 'admin_assets_repository.dart';
import 'admin_docker_models.dart';
import 'admin_docker_repository.dart';

enum DockerLogsPhase {
  idle,
  checking,
  connecting,
  receiving,
  snapshot,
  stopped,
  failed,
  background,
  revoked,
}

class AdminDockerLogsController extends ChangeNotifier {
  AdminDockerLogsController(
    this.repository,
    this.container, {
    this.ownerPollInterval = const Duration(seconds: 15),
  });
  final AdminDockerRepository repository;
  final DockerInspect container;
  final Duration ownerPollInterval;
  DockerLogsPhase phase = DockerLogsPhase.idle;
  final Queue<(String, int)> _chunks = Queue();
  int _bytes = 0, _generation = 0;
  bool truncated = false, containsReplacement = false, _disposed = false;
  Completer<void>? _abort;
  Timer? _ownerTimer;
  bool _checkingOwner = false;
  static const maxBufferBytes = 1024 * 1024;
  String get text => _chunks.map((v) => v.$1).join();
  bool get following => {
    DockerLogsPhase.checking,
    DockerLogsPhase.connecting,
    DockerLogsPhase.receiving,
  }.contains(phase);
  bool get active => !_disposed && repository.active;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  bool _current(int ticket) => active && ticket == _generation;
  void clear() {
    _chunks.clear();
    _bytes = 0;
    truncated = false;
    containsReplacement = false;
    _notify();
  }

  void _append(String value) {
    dockerText(value, limit: 1024 * 1024);
    containsReplacement |= value.contains('\ufffd');
    for (var at = 0; at < value.length;) {
      var end = (at + 4096).clamp(0, value.length);
      if (end < value.length &&
          value.codeUnitAt(end - 1) >= 0xd800 &&
          value.codeUnitAt(end - 1) <= 0xdbff) {
        end--;
      }
      final part = value.substring(at, end),
          size = utf8.encode(value.substring(at, end)).length;
      _chunks.add((part, size));
      _bytes += size;
      at = end;
      while (_bytes > maxBufferBytes && _chunks.isNotEmpty) {
        _bytes -= _chunks.removeFirst().$2;
        truncated = true;
      }
    }
  }

  void _retire() {
    ++_generation;
    final abort = _abort;
    _abort = null;
    if (abort != null && !abort.isCompleted) abort.complete();
    _ownerTimer?.cancel();
    _ownerTimer = null;
    repository.cancel();
  }

  Future<void> _owner(int ticket) async {
    if (!_current(ticket) || _checkingOwner) return;
    _checkingOwner = true;
    try {
      await repository.verifyOwner(abortTrigger: _abort?.future);
    } catch (error) {
      if (_current(ticket)) _fail(error);
    } finally {
      _checkingOwner = false;
    }
  }

  void _fail(Object error) {
    final revoked =
        !repository.active ||
        error is AdminAssetOwnerLost ||
        (error is ApiFailure && {401, 403}.contains(error.status));
    _retire();
    clear();
    if (revoked) repository.scope.close();
    phase = revoked ? DockerLogsPhase.revoked : DockerLogsPhase.failed;
    _notify();
  }

  Future<void> snapshot(int tail) async {
    if (!active || following || phase == DockerLogsPhase.background) return;
    _retire();
    clear();
    final ticket = _generation;
    phase = DockerLogsPhase.checking;
    _notify();
    try {
      final value = await repository.logs(container, tail);
      if (!_current(ticket)) return;
      _append(value);
      phase = DockerLogsPhase.snapshot;
    } catch (error) {
      if (_current(ticket)) _fail(error);
    } finally {
      if (_current(ticket)) _notify();
    }
  }

  Future<void> follow(int tail) async {
    if (!active ||
        following ||
        phase == DockerLogsPhase.background ||
        tail < 1 ||
        tail > 10000) {
      return;
    }
    _retire();
    clear();
    final ticket = _generation, abort = Completer<void>();
    _abort = abort;
    phase = DockerLogsPhase.checking;
    _notify();
    try {
      await repository.verifyContainer(container, requireRunning: false);
      if (!_current(ticket)) return;
      phase = DockerLogsPhase.connecting;
      _notify();
      _ownerTimer = Timer.periodic(
        ownerPollInterval,
        (_) => unawaited(_owner(ticket)),
      );
      await for (final event in repository.scope.client.adminDockerLogEvents(
        repository.host.id,
        container.id,
        tail: tail,
        abortTrigger: abort.future,
      )) {
        if (!_current(ticket)) return;
        final data = jsonDecode(event.data);
        if (data is! Map<String, dynamic>) {
          throw const FormatException('Invalid Docker log event');
        }
        switch (event.type) {
          case 'status':
            if (data['state'] != 'connecting') {
              throw const FormatException('Invalid log status');
            }
          case 'log':
            final value = dockerText(data['data'], limit: 32 * 1024);
            _append(value);
            if (value.isNotEmpty) phase = DockerLogsPhase.receiving;
          case 'log-error':
            throw const ApiFailure(502, 'Docker logs unavailable');
          default:
            throw const FormatException('Unknown Docker log event');
        }
        _notify();
      }
      if (_current(ticket)) {
        _retire();
        phase = DockerLogsPhase.stopped;
        _notify();
      }
    } catch (error) {
      if (_current(ticket)) _fail(error);
    }
  }

  void stop() {
    if (_disposed) return;
    _retire();
    phase = DockerLogsPhase.stopped;
    _notify();
  }

  void background() {
    if (_disposed) return;
    _retire();
    clear();
    phase = DockerLogsPhase.background;
    _notify();
  }

  void resume() {
    if (!_disposed && phase == DockerLogsPhase.background) {
      phase = DockerLogsPhase.idle;
      _notify();
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _retire();
    _chunks.clear();
    repository.dispose();
    super.dispose();
  }
}
