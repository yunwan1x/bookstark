import 'dart:async';
import 'package:flutter/foundation.dart';
import 'speech_repository.dart';
import 'speech_text.dart';
import 'speech_playback.dart';
import 'stream_audio_source.dart';

/// One owner for paragraph playback, HTTP cancellation and notification state.
/// Advances only after both the backend receipt and the decoder complete.
class SpeechController extends ChangeNotifier {
  SpeechController({required this.repository, required this.player}) {
    _events = player.events.listen(_event);
  }
  final SpeechRepository repository;
  final SpeechPlayback player;
  late final StreamSubscription<SpeechPlaybackEvent> _events;
  List<String> segments = const [];
  List<SpeechVoice> voices = const [];
  String title = '', context = '', voice = '';
  String? error;
  int index = 0, _generation = 0;
  double speed = 1;
  bool playing = false,
      preparing = false,
      _desired = false,
      _validated = false,
      _decoded = false,
      _closed = false;
  SpeechPlaybackPhase phase = SpeechPlaybackPhase.idle;
  MemorySpeechSource? _source;
  Completer<void>? _abort;
  bool _english = false;
  bool _starting = false;
  bool get closed => _closed;
  bool get active => _source != null || preparing;
  bool get wantsPlayback => _desired;
  String get paragraph => segments.isEmpty ? '' : segments[index];
  void _notify() {
    if (!_closed) notifyListeners();
  }

  Future<void> prepare(
    String markdown, {
    required String title,
    String context = '',
    bool english = false,
    bool autoPlay = false,
  }) async {
    final parts = speechSegments(markdown);
    final intent = _generation + 1;
    await stop();
    if (_closed || intent != _generation) return;
    final generation = ++_generation;
    segments = List.unmodifiable(parts);
    this.title = title;
    this.context = context;
    _english = english;
    index = 0;
    preparing = true;
    error = null;
    _desired = autoPlay;
    _notify();
    try {
      if (!await _loadVoices(generation)) return;
      if (autoPlay && _desired && generation == _generation) await play();
    } catch (failure) {
      if (!_closed && generation == _generation) {
        preparing = false;
        _desired = false;
        error = failure.toString();
        phase = SpeechPlaybackPhase.error;
        _notify();
      }
    }
  }

  Future<bool> _loadVoices(int generation) async {
    await player.configure();
    final options = await repository.voices();
    if (_closed || generation != _generation) return false;
    if (options.isEmpty) {
      throw StateError('服务器没有可用音色 / No speech voices available');
    }
    voices = List.unmodifiable(options);
    final previous = voices.where((item) => item.id == voice);
    final preferred = voices.where(
      (item) => item.locale.startsWith(_english ? 'en' : 'zh'),
    );
    voice = previous.isNotEmpty
        ? previous.first.id
        : preferred.isNotEmpty
        ? preferred.first.id
        : voices.first.id;
    preparing = false;
    _notify();
    return true;
  }

  void _event(SpeechPlaybackEvent event) {
    if (_closed) return;
    if (event.interrupted) {
      _desired = false;
      playing = false;
      _notify();
      return;
    }
    if (_closed || _source == null || event.tag != _generation) return;
    if (event.phase == SpeechPlaybackPhase.error) {
      unawaited(
        _fail(_generation, event.error ?? StateError('Audio playback failed')),
      );
      return;
    }
    phase = event.phase;
    playing = event.playing;
    if (!_starting && event.phase == SpeechPlaybackPhase.ready) {
      _desired = event.playing;
    }
    if (event.phase == SpeechPlaybackPhase.completed) {
      _decoded = true;
      _advanceIfComplete();
    }
    _notify();
  }

  void _advanceIfComplete() {
    if (!_validated || !_decoded || !_desired || _source == null) return;
    _desired = false; // Consume this completion once, before scheduling work.
    if (index + 1 < segments.length) {
      unawaited(_begin(index + 1));
    } else {
      unawaited(_finishReading());
    }
  }

  Future<void> _finishReading() async {
    final intent = _generation + 1;
    await stop();
    if (_closed || intent != _generation) return;
    phase = SpeechPlaybackPhase.completed;
    _notify();
  }

  Future<void> _cancelCurrent() async {
    final abort = _abort;
    _abort = null;
    if (abort != null && !abort.isCompleted) abort.complete();
    final source = _source;
    _source = null;
    try {
      await player.stop();
    } finally {
      await source?.disposeSource();
    }
  }

  Future<void> _begin(int next) async {
    if (_closed || next < 0 || next >= segments.length || voices.isEmpty) {
      return;
    }
    final generation = ++_generation;
    _desired = true;
    _starting = true;
    playing = false;
    phase = SpeechPlaybackPhase.loading;
    error = null;
    _validated = false;
    _decoded = false;
    index = next;
    _notify();
    try {
      await _cancelCurrent();
      if (_closed || generation != _generation) return;
      final abort = Completer<void>();
      _abort = abort;
      final source = MemorySpeechSource(
        repository.audio(segments[index], voice, abortTrigger: abort.future),
        tag: generation,
      );
      _source = source;
      unawaited(
        source.completed.then<void>(
          (_) {
            if (!_closed && generation == _generation) {
              _validated = true;
              _advanceIfComplete();
            }
          },
          onError: (Object failure, StackTrace stack) {
            unawaited(_fail(generation, failure));
          },
        ),
      );
      await player.setSource(source);
      if (_closed || generation != _generation) return;
      await player.setSpeed(speed);
      if (_closed || generation != _generation) return;
      _starting = false;
      if (_desired) {
        unawaited(
          player.play().catchError(
            (Object failure) => _fail(generation, failure),
          ),
        );
      }
    } catch (failure) {
      await _fail(generation, failure);
    }
  }

  Future<void> _fail(int generation, Object failure) async {
    if (_closed || generation != _generation) return;
    ++_generation;
    _desired = false;
    _starting = false;
    playing = false;
    preparing = false;
    error = failure.toString();
    phase = SpeechPlaybackPhase.error;
    _notify();
    await _cancelCurrent();
  }

  Future<void> play() async {
    if (_closed || segments.isEmpty || preparing) return;
    if (voices.isEmpty) {
      final generation = ++_generation;
      preparing = true;
      error = null;
      _notify();
      try {
        if (!await _loadVoices(generation)) return;
      } catch (failure) {
        await _fail(generation, failure);
        return;
      }
    }
    if (_source == null) {
      if (phase == SpeechPlaybackPhase.completed) index = 0;
      await _begin(index);
      return;
    }
    _desired = true;
    _advanceIfComplete();
    final generation = _generation;
    if (_source != null) {
      unawaited(
        player.play().catchError(
          (Object failure) => _fail(generation, failure),
        ),
      );
    }
  }

  Future<void> pause() async {
    if (_closed) return;
    _desired = false;
    playing = false;
    await player.pause();
    _notify();
  }

  Future<void> stop() async {
    if (_closed) return;
    ++_generation;
    _desired = false;
    _starting = false;
    playing = false;
    preparing = false;
    phase = SpeechPlaybackPhase.idle;
    await _cancelCurrent();
    _notify();
  }

  Future<void> jumpTo(int target) async {
    if (!_closed && !preparing && target >= 0 && target < segments.length) {
      await _begin(target);
    }
  }

  Future<void> next() async {
    if (index + 1 < segments.length) await _begin(index + 1);
  }

  Future<void> previous() async {
    if (index > 0) await _begin(index - 1);
  }

  Future<void> setVoice(String id) async {
    if (_closed) return;
    if (!voices.any((item) => item.id == id)) {
      throw const FormatException('Invalid voice');
    }
    if (id == voice) return;
    final resume = _desired, intent = _generation + 1;
    await stop();
    if (_closed || intent != _generation) return;
    voice = id;
    _notify();
    if (resume) await _begin(index);
  }

  Future<void> setSpeed(double value) async {
    if (_closed) return;
    if (!{0.75, 1.0, 1.25, 1.5}.contains(value)) {
      throw const FormatException('Invalid speed');
    }
    await player.setSpeed(value);
    speed = value;
    _notify();
  }

  Future<void>? _closeFuture;
  Future<void> close() => _closeFuture ??= _close();
  Future<void> _close() async {
    if (_closed) return;
    _closed = true;
    ++_generation;
    _desired = false;
    playing = false;
    preparing = false;
    phase = SpeechPlaybackPhase.idle;
    notifyListeners();
    try {
      await _cancelCurrent();
    } finally {
      await _events.cancel();
      await player.close();
      super.dispose();
    }
  }
}
