// In-memory UI fixture and test doubles. No MP3 decoder or platform audio.
import 'dart:async';
import 'package:bookstark_flutter/core/speech_playback.dart';
import 'package:bookstark_flutter/core/speech_repository.dart';
import 'package:bookstark_flutter/core/stream_audio_source.dart';

class SpeechFixtureRepository implements SpeechRepository {
  final audioStreams = <StreamController<List<int>>>[];
  final aborts = <Future<void>>[];
  final requestedVoices = <String>[];
  Completer<List<SpeechVoice>>? voiceGate;
  @override
  Future<List<SpeechVoice>> voices() async =>
      voiceGate?.future ??
      Future.value(const [
        SpeechVoice(
          id: 'zh-CN-YunxiNeural',
          name: '云希 · 普通话男声',
          locale: 'zh-CN',
        ),
        SpeechVoice(
          id: 'zh-CN-XiaoxiaoNeural',
          name: '晓晓 · 普通话女声',
          locale: 'zh-CN',
        ),
        SpeechVoice(id: 'en-US-AriaNeural', name: 'Aria', locale: 'en-US'),
        SpeechVoice(id: 'en-US-GuyNeural', name: 'Guy', locale: 'en-US'),
      ]);
  @override
  Stream<List<int>> audio(
    String text,
    String voice, {
    required Future<void> abortTrigger,
  }) {
    final controller = StreamController<List<int>>(onCancel: () async {});
    audioStreams.add(controller);
    aborts.add(abortTrigger);
    requestedVoices.add(voice);
    return controller.stream;
  }
}

class SpeechFixturePlayback implements SpeechPlayback {
  final bus = StreamController<SpeechPlaybackEvent>.broadcast(sync: true);
  StreamSubscription<List<int>>? subscription;
  int tag = 0, plays = 0;
  int stopsStarted = 0, stopsFinished = 0;
  bool playing = false;
  @override
  Stream<SpeechPlaybackEvent> get events => bus.stream;
  void emit(SpeechPlaybackPhase phase, {int? sourceTag}) =>
      bus.add(SpeechPlaybackEvent(sourceTag ?? tag, phase, playing));
  @override
  Future<void> configure() async {}
  @override
  Future<void> setSource(MemorySpeechSource source) async {
    tag = source.tag as int;
    final sourceTag = tag;
    final response = await source.request();
    subscription = response.stream.listen(
      (_) => emit(SpeechPlaybackPhase.ready, sourceTag: sourceTag),
      onError: (Object error, StackTrace stack) => bus.add(
        SpeechPlaybackEvent(
          sourceTag,
          SpeechPlaybackPhase.error,
          false,
          error: error,
        ),
      ),
      onDone: () => emit(SpeechPlaybackPhase.completed, sourceTag: sourceTag),
    );
  }

  @override
  Future<void> play() async {
    plays++;
    playing = true;
    emit(SpeechPlaybackPhase.ready);
  }

  @override
  Future<void> pause() async {
    playing = false;
    emit(SpeechPlaybackPhase.ready);
  }

  @override
  Future<void> stop() async {
    stopsStarted++;
    playing = false;
    await subscription?.cancel();
    subscription = null;
    stopsFinished++;
  }

  @override
  Future<void> setSpeed(double speed) async {}
  @override
  Future<void> close() async {
    await stop();
    await bus.close();
  }
}
