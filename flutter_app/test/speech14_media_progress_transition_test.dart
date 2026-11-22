import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/scoped_speech_repository.dart';
import 'package:bookstark_flutter/core/speech_controller.dart';
import 'package:bookstark_flutter/core/speech_playback.dart';
import 'package:bookstark_flutter/core/speech_runtime.dart';
import '../tool/fixtures/speech.dart';

class ProgressPlayer extends SpeechFixturePlayback
    implements SpeechPlaybackProgress {
  final progress = StreamController<Duration>.broadcast(sync: true);
  @override
  Duration position = Duration.zero;
  @override
  Duration bufferedPosition = Duration.zero;
  @override
  Stream<Duration> get positionStream => progress.stream;
  void advance(int positionMs, int bufferedMs) {
    position = Duration(milliseconds: positionMs);
    bufferedPosition = Duration(milliseconds: bufferedMs);
    progress.add(position);
  }

  @override
  Future<void> close() async {
    await super.close();
    await progress.close();
  }
}

class HeldStopPlayer extends SpeechFixturePlayback {
  Completer<void>? gate;
  final entered = Completer<void>();
  int closes = 0;
  @override
  Future<void> stop() async {
    if (gate != null) {
      if (!entered.isCompleted) entered.complete();
      await gate!.future;
    }
    await super.stop();
  }

  @override
  Future<void> close() async {
    closes++;
    await super.close();
  }
}

void main() {
  test(
    'MediaSession publishes actual optional position/buffered values and releases prior subscription',
    () async {
      final player = ProgressPlayer(), nextPlayer = ProgressPlayer();
      final first = SpeechController(
        repository: SpeechFixtureRepository(),
        player: player,
      );
      final second = SpeechController(
        repository: SpeechFixtureRepository(),
        player: nextPlayer,
      );
      final handler = BookstarkAudioHandler();
      addTearDown(() async {
        handler.attach(null);
        await first.close();
        await second.close();
      });
      await first.prepare('First actual paragraph.', title: 'First');
      await second.prepare('Second actual paragraph.', title: 'Second');
      handler.attach(first);
      expect(player.progress.hasListener, isTrue);
      player.advance(750, 2100);
      expect(
        handler.playbackState.value.updatePosition,
        const Duration(milliseconds: 750),
      );
      expect(
        handler.playbackState.value.bufferedPosition,
        const Duration(milliseconds: 2100),
      );
      // No duration is invented for a finite but not-yet-finished MP3 stream.
      expect(handler.mediaItem.value!.duration, isNull);
      handler.attach(second);
      expect(player.progress.hasListener, isFalse);
      nextPlayer.advance(125, 500);
      player.advance(9999, 10000);
      expect(
        handler.playbackState.value.updatePosition,
        const Duration(milliseconds: 125),
      );
      expect(
        handler.playbackState.value.bufferedPosition,
        const Duration(milliseconds: 500),
      );
      nextPlayer.progress.addError(
        StateError('Progress telemetry unavailable'),
      );
      handler.attach(null);
      expect(nextPlayer.progress.hasListener, isFalse);
      expect(handler.mediaItem.value, isNull);
      expect(handler.queue.value, isEmpty);
      expect(handler.playbackState.value.updatePosition, Duration.zero);
    },
  );
  test(
    'legacy playback without progress capability remains supported',
    () async {
      final engine = SpeechController(
        repository: SpeechFixtureRepository(),
        player: SpeechFixturePlayback(),
      );
      final handler = BookstarkAudioHandler();
      addTearDown(() async {
        handler.attach(null);
        await engine.close();
      });
      await engine.prepare('Legacy fixture.', title: 'Legacy');
      handler.attach(engine);
      expect(handler.playbackState.value.updatePosition, Duration.zero);
      expect(handler.playbackState.value.bufferedPosition, Duration.zero);
    },
  );
  test(
    'Root transition contract revokes both owners immediately but waits for actual controller native stop before activation',
    () async {
      final player = HeldStopPlayer();
      final engine = SpeechController(
        repository: SpeechFixtureRepository(),
        player: player,
      );
      await engine.prepare('Old account paragraph.', title: 'Old account');
      final owner = SpeechOwner(isCurrent: () => true),
          localOwner = SpeechOwner(isCurrent: () => true);
      player.gate = Completer<void>();
      var activated = false;
      final transition =
          retireSpeechBeforeTransition(
            owner: owner,
            localOwner: localOwner,
            close: engine.close,
          ).then((_) {
            activated = true;
          });
      expect(owner.current, isFalse);
      expect(localOwner.current, isFalse);
      await player.entered.future;
      expect(activated, isFalse);
      expect(player.closes, 0);
      expect(engine.closed, isTrue);
      player.gate!.complete();
      await transition;
      expect(activated, isTrue);
      expect(player.closes, 1);
    },
  );
}
