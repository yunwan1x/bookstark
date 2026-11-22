import 'dart:async';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart' as audio;
import 'stream_audio_source.dart';

enum SpeechPlaybackPhase { idle, loading, buffering, ready, completed, error }

class SpeechPlaybackEvent {
  const SpeechPlaybackEvent(
    this.tag,
    this.phase,
    this.playing, {
    this.error,
    this.interrupted = false,
  });
  final int tag;
  final SpeechPlaybackPhase phase;
  final bool playing;
  final Object? error;
  final bool interrupted;
}

abstract interface class SpeechPlayback {
  Stream<SpeechPlaybackEvent> get events;
  Future<void> configure();
  Future<void> setSource(MemorySpeechSource source);
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> setSpeed(double speed);
  Future<void> close();
}

/// Optional capability: old playback fakes need not invent progress.
abstract interface class SpeechPlaybackProgress {
  Stream<Duration> get positionStream;
  Duration get position;
  Duration get bufferedPosition;
}

class JustAudioSpeechPlayback
    implements SpeechPlayback, SpeechPlaybackProgress {
  JustAudioSpeechPlayback() {
    _state = _player.playerStateStream.listen(
      (state) => _events.add(
        SpeechPlaybackEvent(
          _tag,
          SpeechPlaybackPhase.values[state.processingState.index],
          state.playing,
        ),
      ),
    );
    _errors = _player.errorStream.listen(
      (error) => _events.add(
        SpeechPlaybackEvent(
          _tag,
          SpeechPlaybackPhase.error,
          false,
          error: error,
        ),
      ),
    );
  }
  final _player = audio.AudioPlayer();
  @override
  Stream<Duration> get positionStream => _player.positionStream;
  @override
  Duration get position => _player.position;
  @override
  Duration get bufferedPosition => _player.bufferedPosition;
  int get currentSourceTag => _tag;
  final _events = StreamController<SpeechPlaybackEvent>.broadcast(sync: true);
  late final StreamSubscription _state, _errors;
  StreamSubscription? _noisy, _interruptions;
  int get _tag {
    final tag = _player.sequenceState.currentSource?.tag;
    return tag is int ? tag : 0;
  }

  @override
  Stream<SpeechPlaybackEvent> get events => _events.stream;
  @override
  Future<void> configure() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.speech());
    // just_audio performs the platform pause/resume. Report interruption intent
    // as well so a pending voice/HTTP load cannot start on unplugged speakers.
    _noisy ??= session.becomingNoisyEventStream.listen(
      (_) => _events.add(
        SpeechPlaybackEvent(
          _tag,
          SpeechPlaybackPhase.ready,
          false,
          interrupted: true,
        ),
      ),
    );
    _interruptions ??= session.interruptionEventStream.listen((event) {
      if (event.begin) {
        _events.add(
          SpeechPlaybackEvent(
            _tag,
            SpeechPlaybackPhase.ready,
            false,
            interrupted: true,
          ),
        );
      }
    });
  }

  @override
  Future<void> setSource(MemorySpeechSource source) async {
    await _player.setAudioSource(source);
  }

  @override
  Future<void> play() => _player.play();
  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> stop() => _player.stop();
  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);
  @override
  Future<void> close() async {
    await _noisy?.cancel();
    await _interruptions?.cancel();
    await _state.cancel();
    await _errors.cancel();
    await _player.dispose();
    await _events.close();
  }
}
