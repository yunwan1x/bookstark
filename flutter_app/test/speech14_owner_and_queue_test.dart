import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/scoped_speech_repository.dart';
import 'package:bookstark_flutter/core/speech_controller.dart';
import 'package:bookstark_flutter/core/speech_runtime.dart';
import '../tool/fixtures/speech.dart';

void main() {
  test(
    'retired owner cancels real repository trigger and rejects late audio',
    () async {
      final inner = SpeechFixtureRepository();
      var current = true;
      final owner = SpeechOwner(isCurrent: () => current);
      final repository = ScopedSpeechRepository(inner, owner);
      final abort = Completer<void>();
      final values = <List<int>>[];
      final errors = <Object>[];
      final subscription = repository
          .audio('owned', 'zh-CN-YunxiNeural', abortTrigger: abort.future)
          .listen(values.add, onError: (Object error) => errors.add(error));
      await Future<void>.delayed(Duration.zero);
      inner.audioStreams.single.add([1, 2]);
      await Future<void>.delayed(Duration.zero);
      expect(values, [
        [1, 2],
      ]);
      current = false;
      owner.retire();
      await inner.aborts.single;
      inner.audioStreams.single.add([3]);
      await inner.audioStreams.single.close();
      await Future<void>.delayed(Duration.zero);
      expect(values, [
        [1, 2],
      ]);
      expect(errors, isNotEmpty);
      await subscription.cancel();
    },
  );
  test('retired owner suppresses late voices and never starts audio', () async {
    final inner = SpeechFixtureRepository()..voiceGate = Completer();
    final owner = SpeechOwner(isCurrent: () => true);
    final result = ScopedSpeechRepository(inner, owner).voices();
    owner.retire();
    inner.voiceGate!.complete([]);
    await expectLater(result, throwsStateError);
    expect(inner.audioStreams, isEmpty);
  });
  test(
    'media queue uses actual paragraph items and queue control shares controller',
    () async {
      final repo = SpeechFixtureRepository();
      final player = SpeechFixturePlayback();
      final engine = SpeechController(repository: repo, player: player);
      final handler = BookstarkAudioHandler()..attach(engine);
      addTearDown(() async {
        handler.attach(null);
        await engine.close();
      });
      await engine.prepare(
        'First paragraph.\n\nSecond paragraph.',
        title: 'Owned',
      );
      expect(handler.queue.value.length, 2);
      expect(handler.queue.value.first.id, isNot(handler.queue.value.last.id));
      await handler.skipToQueueItem(1);
      expect(engine.index, 1);
      expect(repo.audioStreams.length, 1);
      await handler.stop();
      await repo.aborts.single;
      expect(engine.active, isFalse);
    },
  );
}
