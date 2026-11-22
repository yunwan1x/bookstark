import 'package:bookstark_flutter/core/app_theme.dart';
import 'package:bookstark_flutter/core/speech_controller.dart';
import 'package:bookstark_flutter/core/speech_runtime.dart';
import 'package:bookstark_flutter/features/speech/speech_player_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../tool/fixtures/speech.dart';

const speech =
    '阅读不必从最难的书开始。先找到一个你真正想解决的问题，再挑选能帮助你理解它的书。\n\n选择与当前问题有关的内容。\n\n能读懂，也有一点挑战。\n\n愿意读完后付诸实践。';
void main() {
  testWidgets(
    'player page uses real controller actions for pause next speed and stop',
    (tester) async {
      final repo = SpeechFixtureRepository(), player = SpeechFixturePlayback();
      final engine = SpeechController(repository: repo, player: player);
      addTearDown(engine.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: bookstarkTheme(),
          home: SpeechPlayerPage(
            controller: engine,
            request: const SpeechRequest(
              speech,
              title: '选择适合自己的书',
              context: '阅读的方法',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(engine.segments.length, 4);
      expect(find.text('第1段 / 共4段'), findsOneWidget);
      final scroll = find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.byTooltip('暂停'),
        200,
        scrollable: scroll,
      );
      await tester.ensureVisible(find.byTooltip('暂停'));
      await tester.pump();
      await tester.tap(find.byTooltip('暂停'));
      await tester.pumpAndSettle();
      expect(engine.wantsPlayback, isFalse);
      await tester.ensureVisible(find.byTooltip('下一段'));
      await tester.pump();
      await tester.tap(find.byTooltip('下一段'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        engine.phase.name,
        'ready',
        reason:
            'phase=${engine.phase}, error=${engine.error}, wants=${engine.wantsPlayback}, requests=${repo.audioStreams.length}, stops=${player.stopsStarted}/${player.stopsFinished}',
      );
      await tester.pumpAndSettle();
      expect(engine.index, 1);
      await tester.scrollUntilVisible(
        find.text('停止朗读'),
        160,
        scrollable: scroll,
      );
      await tester.tap(find.text('停止朗读'));
      await tester.pumpAndSettle();
      expect(engine.active, isFalse);
      expect(engine.wantsPlayback, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'English player supports 320dp twofold text and notification state follows controller',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final engine = SpeechController(
        repository: SpeechFixtureRepository(),
        player: SpeechFixturePlayback(),
      );
      final handler = BookstarkAudioHandler()..attach(engine);
      addTearDown(() async {
        handler.attach(null);
        await engine.close();
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: bookstarkTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: SpeechPlayerPage(
            controller: engine,
            english: true,
            request: const SpeechRequest(speech, title: 'Book reading'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(handler.mediaItem.value!.title, 'Book reading');
      expect(handler.playbackState.value.playing, isTrue);
      final scroll = find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.byTooltip('Pause'),
        200,
        scrollable: scroll,
      );
      await tester.ensureVisible(find.byTooltip('Pause'));
      await tester.pump();
      await tester.tap(find.byTooltip('Pause'));
      await tester.pumpAndSettle();
      expect(handler.playbackState.value.playing, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
}
