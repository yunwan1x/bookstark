import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'speech_controller.dart';
import 'speech_playback.dart';
import 'speech_repository.dart';
import 'dart:async';
import 'scoped_speech_repository.dart';

/// Root sets its transition gate before calling this and awaits the actual
/// player/HTTP teardown before activating the replacement principal.
Future<void> retireSpeechBeforeTransition({
  SpeechOwner? owner,
  SpeechOwner? localOwner,
  required Future<void> Function() close,
}) async {
  owner?.retire();
  localOwner?.retire();
  await close();
}

class BookstarkAudioHandler extends BaseAudioHandler {
  SpeechController? _engine;
  StreamSubscription<Duration>? _positionSubscription;
  int _queueOffset = 0;
  List<String>? _queueSegments;
  int _queueWindow = -1;
  List<MediaItem> _queueItems = const [];
  SpeechController? get engine => _engine;
  Future<void> Function()? _afterStop;
  void attach(SpeechController? engine, {Future<void> Function()? afterStop}) {
    _afterStop = afterStop;
    unawaited(_positionSubscription?.cancel());
    _positionSubscription = null;
    _engine?.removeListener(_publish);
    _engine = engine;
    engine?.addListener(_publish);
    final player = engine?.player;
    if (player is SpeechPlaybackProgress) {
      _positionSubscription = (player as SpeechPlaybackProgress).positionStream
          .listen(
            (_) => _publish(),
            onError: (Object _, StackTrace _) => _publish(),
          );
    }
    _publish();
  }

  String _mediaLabel(String value) =>
      String.fromCharCodes(value.runes.take(200));
  void _publish() {
    final engine = _engine;
    if (engine == null || engine.segments.isEmpty) {
      _queueSegments = null;
      _queueWindow = -1;
      _queueOffset = 0;
      _queueItems = const [];

      mediaItem.add(null);
      queue.add(const []);
      playbackState.add(
        PlaybackState(processingState: AudioProcessingState.idle),
      );
      return;
    }
    final player = engine.player;
    final progress = player is SpeechPlaybackProgress
        ? player as SpeechPlaybackProgress
        : null;
    final controls = [
      if (engine.index > 0) MediaControl.skipToPrevious,
      engine.wantsPlayback ? MediaControl.pause : MediaControl.play,
      MediaControl.stop,
      if (engine.index + 1 < engine.segments.length) MediaControl.skipToNext,
    ];
    // Binder/notification queue is bounded; controller retains ALL paragraphs.
    // Stable windows preserve absolute paragraph IDs without huge OS payloads.
    final window = engine.index ~/ 50;
    if (!identical(_queueSegments, engine.segments) || window != _queueWindow) {
      _queueSegments = engine.segments;
      _queueWindow = window;
      _queueOffset = window * 50;
      _queueItems = List<MediaItem>.unmodifiable([
        for (
          var i = _queueOffset;
          i < engine.segments.length && i < _queueOffset + 50;
          i++
        )
          MediaItem(
            id: 'bookstark:speech:${identityHashCode(engine)}:$i',
            title: _mediaLabel(engine.title),
            album: _mediaLabel(engine.context),
            displaySubtitle: '${i + 1}/${engine.segments.length}',
          ),
      ]);
      queue.add(_queueItems);
    }
    final items = _queueItems;
    final item = MediaItem(
      id: items[engine.index - _queueOffset].id,
      title: _mediaLabel(engine.title),
      album: _mediaLabel(engine.context),
      displaySubtitle: '${engine.index + 1}/${engine.segments.length}',
    );
    mediaItem.add(item);
    playbackState.add(
      PlaybackState(
        controls: controls,
        androidCompactActionIndices: [
          for (var i = 0; i < controls.length; i++)
            if (controls[i] != MediaControl.stop) i,
        ].take(3).toList(),
        processingState: switch (engine.phase) {
          SpeechPlaybackPhase.idle =>
            engine.preparing
                ? AudioProcessingState.loading
                : AudioProcessingState.idle,
          SpeechPlaybackPhase.loading => AudioProcessingState.loading,
          SpeechPlaybackPhase.buffering => AudioProcessingState.buffering,
          SpeechPlaybackPhase.ready => AudioProcessingState.ready,
          SpeechPlaybackPhase.completed => AudioProcessingState.completed,
          SpeechPlaybackPhase.error => AudioProcessingState.error,
        },
        queueIndex: engine.index - _queueOffset,
        updatePosition: progress?.position ?? Duration.zero,
        bufferedPosition: progress?.bufferedPosition ?? Duration.zero,
        playing: engine.wantsPlayback,
        speed: engine.speed,
        errorCode: engine.error == null ? null : 1,
        errorMessage: engine.error,
      ),
    );
  }

  @override
  Future<void> play() => _engine?.play() ?? Future.value();
  @override
  Future<void> pause() => _engine?.pause() ?? Future.value();
  @override
  Future<void> stop() async {
    final engine = _engine, after = _afterStop;
    await engine?.stop();
    await after?.call();
  }

  @override
  Future<void> skipToNext() => _engine?.next() ?? Future.value();
  @override
  Future<void> skipToPrevious() => _engine?.previous() ?? Future.value();
  @override
  Future<void> skipToQueueItem(int index) =>
      index >= 0 && index < _queueItems.length
      ? (_engine?.jumpTo(_queueOffset + index) ?? Future.value())
      : Future.value();
  @override
  Future<void> setSpeed(double speed) =>
      _engine?.setSpeed(speed) ?? Future.value();
  @override
  Future<void> onTaskRemoved() => stop();
}

class SpeechRuntime {
  SpeechRuntime._(this.controller, this.handler, this.owner);
  static Future<BookstarkAudioHandler>? _handler;
  static Future<void> _creationTail = Future<void>.value();
  final SpeechOwner? owner;
  static Stream<bool> get notificationClicks =>
      AudioService.notificationClicked;
  final SpeechController controller;
  final BookstarkAudioHandler handler;
  static Future<SpeechRuntime> create(
    SpeechRepository repository, {
    SpeechOwner? owner,
    bool retireOwnerOnStop = false,
  }) {
    final result = Completer<SpeechRuntime>();
    _creationTail = _creationTail.then((_) async {
      try {
        result.complete(await _create(repository, owner, retireOwnerOnStop));
      } catch (error, stack) {
        result.completeError(error, stack);
      }
    });
    return result.future;
  }

  static Future<SpeechRuntime> _create(
    SpeechRepository repository,
    SpeechOwner? owner,
    bool retireOwnerOnStop,
  ) async {
    owner?.check();
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      throw UnsupportedError(
        '请在Android应用中使用原生流式朗读 / Use native streaming speech in the Android app',
      );
    }
    final future = _handler ??= AudioService.init(
      builder: BookstarkAudioHandler.new,
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.bookstark.bookstark_flutter.reading',
        androidNotificationChannelName: 'BookStark reading',
        androidStopForegroundOnPause: false,
      ),
    );
    final BookstarkAudioHandler handler;
    try {
      handler = await future;
    } catch (_) {
      if (identical(_handler, future)) _handler = null;
      rethrow;
    }
    owner?.check();
    final previous = handler.engine;
    if (previous != null) await previous.close();
    owner?.check();
    final controller = SpeechController(
      repository: owner == null
          ? repository
          : ScopedSpeechRepository(repository, owner),
      player: JustAudioSpeechPlayback(),
    );
    final runtime = SpeechRuntime._(controller, handler, owner);
    handler.attach(
      controller,
      afterStop: retireOwnerOnStop ? runtime.close : null,
    );
    owner?.retired.then((_) => runtime.close());
    return runtime;
  }

  Future<void>? _closeFuture;
  Future<void> close() => _closeFuture ??= _close();
  Future<void> _close() async {
    owner?.retire();
    try {
      await controller.close();
    } finally {
      if (identical(handler.engine, controller)) handler.attach(null);
    }
  }
}
