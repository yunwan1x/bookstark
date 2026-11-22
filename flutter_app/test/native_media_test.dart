import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:bookstark_flutter/widgets/native_media.dart';

class MediaPlatform extends VideoPlayerPlatform {
  int played = 0, paused = 0, disposed = 0;
  final seeks = <Duration>[];
  Duration position = Duration.zero;
  Size videoSize = const Size(160, 90);
  DataSource? source;
  @override
  Future<void> init() async {}
  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    source = options.dataSource;
    return 1;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => Stream.value(
    VideoEvent(
      eventType: VideoEventType.initialized,
      duration: const Duration(seconds: 30),
      size: videoSize,
    ),
  );
  @override
  Future<void> dispose(int playerId) async {
    disposed++;
  }

  @override
  Future<void> setLooping(int playerId, bool looping) async {}
  @override
  Future<void> play(int playerId) async {
    played++;
  }

  @override
  Future<void> pause(int playerId) async {
    paused++;
  }

  @override
  Future<void> setVolume(int playerId, double volume) async {}
  @override
  Future<void> seekTo(int playerId, Duration value) async {
    seeks.add(value);
    position = value;
  }

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}
  @override
  Future<Duration> getPosition(int playerId) async => position;
  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}
  @override
  Future<void> setAllowBackgroundPlayback(bool allowBackgroundPlayback) async {}
  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      const ColoredBox(color: Colors.black);
}

Future<void> drainMedia(WidgetTester tester) async {
  await tester.pump();
  for (var n = 0; n < 4; n++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
  }
}

void main() {
  late VideoPlayerPlatform original;
  late MediaPlatform platform;
  setUp(() {
    original = VideoPlayerPlatform.instance;
    platform = MediaPlatform();
    VideoPlayerPlatform.instance = platform;
  });
  tearDown(() => VideoPlayerPlatform.instance = original);
  testWidgets(
    'media playback waits for audio coordination and uses actual platform seek/pause/dispose commands',
    (tester) async {
      var focus = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NativeMedia(
              path: '/private/cache/audio.mp3',
              audioOnly: true,
              english: true,
              beforePlay: () async {
                focus++;
              },
            ),
          ),
        ),
      );
      await drainMedia(tester);
      expect(platform.source!.sourceType, DataSourceType.file);
      expect(platform.played, 0);
      expect(find.text('0:00 / 0:30'), findsOneWidget);
      await tester.tap(find.text('Play'));
      await drainMedia(tester);
      expect(focus, 1);
      expect(platform.played, 1);
      expect(find.text('Pause'), findsOneWidget);
      await tester.tap(find.byTooltip('Forward 10 seconds'));
      await drainMedia(tester);
      expect(platform.seeks.last, const Duration(seconds: 10));
      final pauses = platform.paused;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await drainMedia(tester);
      expect(platform.paused, greaterThan(pauses));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(const SizedBox());
      await drainMedia(tester);
      expect(platform.disposed, 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'leaving while playback coordination is pending does not start a disposed player',
    (tester) async {
      final ready = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NativeMedia(
              path: '/private/cache/audio.mp3',
              audioOnly: true,
              english: true,
              beforePlay: () => ready.future,
            ),
          ),
        ),
      );
      await drainMedia(tester);
      await tester.tap(find.text('Play'));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      ready.complete();
      await drainMedia(tester);
      expect(platform.played, 0);
      expect(platform.disposed, 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'portrait video and real controls remain scrollable at 320dp and double text',
    (tester) async {
      platform.videoSize = const Size(90, 300);
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: const Scaffold(
            body: SingleChildScrollView(
              child: NativeMedia(
                path: '/private/cache/video.mp4',
                audioOnly: false,
                english: true,
              ),
            ),
          ),
        ),
      );
      await drainMedia(tester);
      expect(find.text('Play'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await drainMedia(tester);
    },
  );
}
