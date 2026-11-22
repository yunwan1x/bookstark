// Pinned just_audio 0.10.6 streaming API is isolated and covered by source tests.
// ignore_for_file: experimental_member_use
import 'dart:async';
import 'dart:typed_data';
import 'package:just_audio/just_audio.dart';

/// A single finite MP3 segment, replayable in bounded memory for decoder probes.
/// No file or disk-cache API is used. Android consumes its local HTTP stream;
/// just_audio's web implementation buffers data URLs and is not used for TTS.
class MemorySpeechSource extends StreamAudioSource {
  MemorySpeechSource(this.input, {super.tag}) {
    // Keep disposal/errors safe even if a decoder never starts listening.
    unawaited(
      _complete.future.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    );
  }
  final Stream<List<int>> input;
  final _history = <Uint8List>[];
  final _listeners = <StreamController<List<int>>>{};
  final _complete = Completer<void>();
  StreamSubscription<List<int>>? _subscription;
  bool _started = false, _finished = false, _disposed = false, _paused = false;
  int _bytes = 0;
  Object? _failure;
  StackTrace? _stack;
  Future<void> get completed => _complete.future;
  int get bufferedBytes => _bytes;

  void _start() {
    if (_started || _disposed) return;
    _started = true;
    _subscription = input.listen(
      (part) {
        if (_finished || _disposed) return;
        if (part.isEmpty) return;
        if (_bytes + part.length > 1024 * 1024) {
          _finish(
            const FormatException('Speech segment exceeds memory limit'),
            StackTrace.current,
          );
          unawaited(_subscription?.cancel());
          return;
        }
        final owned = Uint8List.fromList(part);
        _bytes += owned.length;
        _history.add(owned);
        for (final listener in List.of(_listeners)) {
          listener.add(owned);
        }
      },
      onError: (Object error, StackTrace stack) => _finish(error, stack),
      onDone: () => _finish(),
    );
  }

  void _finish([Object? error, StackTrace? stack]) {
    if (_finished) return;
    if (error == null && _bytes == 0) {
      error = const FormatException('Empty speech audio');
    }
    _finished = true;
    _failure = error;
    _stack = stack;
    for (final listener in List.of(_listeners)) {
      if (error != null) listener.addError(error, stack);
      unawaited(listener.close());
    }
    if (!_complete.isCompleted) {
      if (error == null) {
        _complete.complete();
      } else {
        _complete.completeError(error, stack);
      }
    }
  }

  void _backpressure() {
    final shouldPause =
        _listeners.isNotEmpty &&
        _listeners.every((listener) => listener.isPaused);
    if (shouldPause && !_paused) {
      _subscription?.pause();
      _paused = true;
    } else if (!shouldPause && _paused) {
      _subscription?.resume();
      _paused = false;
    }
  }

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    if (_disposed || (start != null && start != 0)) {
      throw StateError('Speech source cannot seek or is stopped');
    }
    if (_listeners.length >= 2) {
      throw StateError('Too many concurrent decoder requests');
    }
    late StreamController<List<int>> controller;
    controller = StreamController<List<int>>(
      onListen: () {
        if (_listeners.length >= 2) {
          controller.addError(
            StateError('Too many concurrent decoder requests'),
          );
          unawaited(controller.close());
          return;
        }
        _listeners.add(controller);
        for (final part in _history) {
          controller.add(part);
        }
        if (_finished) {
          if (_failure != null) controller.addError(_failure!, _stack);
          unawaited(controller.close());
        } else {
          _start();
        }
      },
      onPause: _backpressure,
      onResume: _backpressure,
      onCancel: () async {
        _listeners.remove(controller);
        _backpressure();
      },
    );
    return StreamAudioResponse(
      rangeRequestsSupported: false,
      sourceLength: null,
      contentLength: null,
      offset: null,
      stream: controller.stream,
      contentType: 'audio/mpeg',
    );
  }

  Future<void> disposeSource() async {
    if (_disposed) return;
    _disposed = true;
    await _subscription?.cancel();
    _finish(StateError('Speech source stopped'), StackTrace.current);
    _listeners.clear();
    _history.clear();
    _bytes = 0;
  }
}
