import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/speech_controller.dart';
import '../tool/fixtures/speech.dart';

class _Delayed extends SpeechFixturePlayback {
  Completer<void>? gate;
  int closes = 0;
  @override
  Future<void> stop() async {
    await gate?.future;
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
    'concurrent controller close waits for same actual player teardown',
    () async {
      final player = _Delayed(), repo = SpeechFixtureRepository();
      final controller = SpeechController(repository: repo, player: player);
      await controller.prepare('Owned text', title: 'Owned');
      player.gate = Completer<void>();
      final first = controller.close(), second = controller.close();
      expect(identical(first, second), isTrue);
      expect(controller.closed, isTrue);
      expect(player.closes, 0);
      player.gate!.complete();
      await Future.wait([first, second]);
      expect(player.closes, 1);
    },
  );
}
