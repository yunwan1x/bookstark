import 'dart:async';
import 'package:bookstark_flutter/core/speech_controller.dart';
import 'package:bookstark_flutter/core/speech_playback.dart';
import 'package:bookstark_flutter/core/speech_repository.dart';
import 'package:bookstark_flutter/core/stream_audio_source.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/fixtures/speech.dart';

Future<void> settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test(
    'audio focus pause and resume update intended playback; interruption prevents loading autoplay',
    () async {
      final repo = SpeechFixtureRepository(), player = SpeechFixturePlayback();
      final engine = SpeechController(repository: repo, player: player);
      addTearDown(engine.close);
      await engine.prepare('正文', title: '测试', autoPlay: true);
      await settle();
      player.playing = false;
      player.emit(SpeechPlaybackPhase.ready);
      expect(engine.wantsPlayback, isFalse);
      player.playing = true;
      player.emit(SpeechPlaybackPhase.ready);
      expect(engine.wantsPlayback, isTrue);
      await engine.stop();
      repo.voiceGate = Completer<List<SpeechVoice>>();
      final preparing = engine.prepare('新正文', title: '测试', autoPlay: true);
      await settle();
      player.bus.add(
        const SpeechPlaybackEvent(
          0,
          SpeechPlaybackPhase.ready,
          false,
          interrupted: true,
        ),
      );
      repo.voiceGate!.complete(const [
        SpeechVoice(id: 'zh-CN-YunxiNeural', name: '云希', locale: 'zh-CN'),
      ]);
      await preparing;
      await settle();
      expect(repo.audioStreams.length, 1);
      expect(engine.wantsPlayback, isFalse);
    },
  );
  test(
    'voice switching aborts the old segment and speed changes validate allowed values',
    () async {
      final repo = SpeechFixtureRepository(), player = SpeechFixturePlayback();
      final engine = SpeechController(repository: repo, player: player);
      addTearDown(engine.close);
      await engine.prepare('第一段。\n\n第二段。', title: '测试', autoPlay: true);
      await settle();
      await engine.setVoice('en-US-AriaNeural');
      await settle();
      await repo.aborts.first.timeout(const Duration(seconds: 2));
      expect(repo.requestedVoices, ['zh-CN-YunxiNeural', 'en-US-AriaNeural']);
      expect(engine.index, 0);
      await engine.setSpeed(1.25);
      expect(engine.speed, 1.25);
      await expectLater(engine.setSpeed(8), throwsFormatException);
    },
  );
  test(
    'empty or excessive audio is rejected and errors are not successful completion',
    () async {
      final empty = MemorySpeechSource(const Stream.empty());
      final emptyOutput = (await empty.request()).stream.toList();
      await expectLater(emptyOutput, throwsFormatException);
      await expectLater(empty.completed, throwsFormatException);
      await empty.disposeSource();
      final large = MemorySpeechSource(
        Stream.value(List.filled(1024 * 1024 + 1, 0)),
      );
      await expectLater(
        (await large.request()).stream.toList(),
        throwsFormatException,
      );
      await expectLater(large.completed, throwsFormatException);
      await large.disposeSource();
      expect(large.bufferedBytes, 0);
    },
  );
  test(
    'memory source streams before completion, replays in memory and releases on stop',
    () async {
      final input = StreamController<List<int>>();
      final source = MemorySpeechSource(input.stream);
      final response = await source.request();
      expect(response.contentLength, isNull);
      expect(response.rangeRequestsSupported, isFalse);
      final iterator = StreamIterator(response.stream),
          first = iterator.moveNext();
      input.add([1, 2, 3]);
      expect(await first, isTrue);
      expect(iterator.current, [1, 2, 3]);
      expect(source.bufferedBytes, 3);
      final end = iterator.moveNext();
      await input.close();
      expect(await end, isFalse);
      await source.completed;
      final replay = await (await source.request()).stream.toList();
      expect(replay, [
        [1, 2, 3],
      ]);
      await source.disposeSource();
      expect(source.bufferedBytes, 0);
    },
  );
  test(
    'speech controller requires both receipts and decoder completion before advancing',
    () async {
      final repo = SpeechFixtureRepository(), player = SpeechFixturePlayback();
      final engine = SpeechController(repository: repo, player: player);
      addTearDown(engine.close);
      await engine.prepare(List.filled(250, '字').join(), title: '测试');
      expect(engine.segments.length, 2);
      await engine.play();
      await settle();
      repo.audioStreams.first.add([1, 2, 3]);
      await settle();
      expect(engine.playing, isTrue);
      player.emit(SpeechPlaybackPhase.completed);
      await settle();
      expect(engine.index, 0);
      expect(repo.audioStreams.length, 1);
      await repo.audioStreams.first.close();
      await settle();
      expect(engine.index, 1);
      expect(repo.audioStreams.length, 2);
      await engine.stop();
      await repo.aborts.last.timeout(const Duration(seconds: 2));
      expect(engine.active, isFalse);
    },
  );
  test(
    'pause never advances or restarts playback; resume consumes completion only once',
    () async {
      final repo = SpeechFixtureRepository(), player = SpeechFixturePlayback();
      final engine = SpeechController(repository: repo, player: player);
      addTearDown(engine.close);
      await engine.prepare(
        List.filled(250, '字').join(),
        title: '测试',
        autoPlay: true,
      );
      await settle();
      repo.audioStreams.first.add([1, 2, 3]);
      await settle();
      await engine.pause();
      await repo.audioStreams.first.close();
      await settle();
      expect(engine.index, 0);
      expect(engine.playing, isFalse);
      await engine.play();
      await settle();
      expect(engine.index, 1);
      expect(repo.audioStreams.length, 2);
      player.emit(SpeechPlaybackPhase.completed, sourceTag: player.tag - 1);
      await settle();
      expect(repo.audioStreams.length, 2);
    },
  );
  test(
    'stream failure aborts transport and never skips to another paragraph',
    () async {
      final repo = SpeechFixtureRepository(), player = SpeechFixturePlayback();
      final engine = SpeechController(repository: repo, player: player);
      addTearDown(engine.close);
      await engine.prepare(
        List.filled(250, '字').join(),
        title: '测试',
        autoPlay: true,
      );
      await settle();
      repo.audioStreams.first.add([1, 2]);
      repo.audioStreams.first.addError(StateError('missing done'));
      await repo.audioStreams.first.close();
      await settle();
      expect(engine.phase, SpeechPlaybackPhase.error);
      expect(engine.index, 0);
      expect(repo.audioStreams.length, 1);
      await repo.aborts.first.timeout(const Duration(seconds: 2));
    },
  );
  test('stop during voice loading prevents late autoplay', () async {
    final repo = SpeechFixtureRepository()
      ..voiceGate = Completer<List<SpeechVoice>>();
    final player = SpeechFixturePlayback();
    final engine = SpeechController(repository: repo, player: player);
    addTearDown(engine.close);
    final preparing = engine.prepare('正文', title: '测试', autoPlay: true);
    await settle();
    await engine.stop();
    repo.voiceGate!.complete(const [
      SpeechVoice(id: 'zh-CN-YunxiNeural', name: '云希', locale: 'zh-CN'),
    ]);
    await preparing;
    await settle();
    expect(repo.audioStreams, isEmpty);
  });
}
