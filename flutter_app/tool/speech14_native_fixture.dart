// Owned alternate entry. PREPARED/UNRUN. Never replace production entry implicitly.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/speech_repository.dart';
import 'package:bookstark_flutter/core/speech_runtime.dart';
import 'package:bookstark_flutter/core/speech_playback.dart';
import 'package:bookstark_flutter/core/scoped_speech_repository.dart';
import 'package:bookstark_flutter/features/speech/speech_player_page.dart';

void main() => runApp(const MaterialApp(home: OwnedSpeechFixture()));

class OwnedSpeechFixture extends StatefulWidget {
  const OwnedSpeechFixture({super.key});
  @override
  State<OwnedSpeechFixture> createState() => _State();
}

class _State extends State<OwnedSpeechFixture> {
  SpeechRuntime? runtime;
  SpeechOwner? owner;
  BookstarkClient? client;
  StreamSubscription<Duration>? position;
  int milliseconds = 0, epoch = 0, lastReported = -1000;
  String status = 'idle';
  bool current = true;
  static const run = String.fromEnvironment('OWNED_SPEECH_RUN');
  Future<void> start({String? text}) async {
    final request = ++epoch;
    owner?.retire();
    await runtime?.close();
    await position?.cancel();
    client?.close();
    current = true;
    milliseconds = 0;
    lastReported = -1000;
    final captured = SpeechOwner(
      isCurrent: () => mounted && current && request == epoch,
    );
    owner = captured;
    try {
      const port = int.fromEnvironment('OWNED_MP3_PORT');
      if (port < 1024 || !RegExp(r'^[a-f0-9]{64}$').hasMatch(run)) {
        throw StateError(
          'Owned loopback provider and unique run binding required',
        );
      }
      final transport = BookstarkClient('http://127.0.0.1:$port');
      client = transport;
      final next = await SpeechRuntime.create(
        RemoteSpeechRepository(transport),
        owner: captured,
      );
      if (!mounted || !captured.current) {
        await next.close();
        transport.close();
        return;
      }
      runtime = next;
      final player = next.controller.player as JustAudioSpeechPlayback;
      position = player.positionStream.listen((_) {
        if (!mounted || !captured.current) return;
        final c = next.controller, actual = player.position.inMilliseconds;
        setState(() => milliseconds = actual);
        if (c.playing &&
            c.phase == SpeechPlaybackPhase.ready &&
            player.currentSourceTag > 0 &&
            (actual - lastReported >= 200 || actual < lastReported)) {
          lastReported = actual;
          // Actual ExoPlayer-backed position getter, not a timer or invented offset.
          debugPrint(
            'OWNED_SPEECH14 run=$run epoch=$request index=${c.index} tag=${player.currentSourceTag} pos=$actual buffered=${player.bufferedPosition.inMilliseconds}',
          );
        }
      });
      await next.controller.prepare(
        text ?? 'Owned legal sine first passage.\n\nSecond owned passage.',
        title: 'Owned real MP3',
        context: 'Native fixture only',
        autoPlay: true,
      );
      if (mounted && captured.current) setState(() => status = 'ready');
    } catch (_) {
      if (mounted) setState(() => status = 'failed');
    }
  }

  Future<void> retire() async {
    current = false;
    ++epoch;
    owner?.retire();
    await runtime?.close();
    await position?.cancel();
    client?.close();
    if (mounted) setState(() => status = 'retired');
  }

  @override
  void dispose() {
    current = false;
    owner?.retire();
    client?.close();
    unawaited(runtime?.close());
    unawaited(position?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Owned MP3 Native fixture')),
    body: Column(
      children: [
        Text('native_position_ms=$milliseconds; owner=$status; epoch=$epoch'),
        Wrap(
          children: [
            TextButton(
              onPressed: () => start(),
              child: const Text('Start actual MP3'),
            ),
            TextButton(
              onPressed: () => start(
                text:
                    'Alternate owned source first passage.\n\nAlternate second passage.',
              ),
              child: const Text('Start alternate actual MP3'),
            ),
            TextButton(
              onPressed: () => start(
                text: List.generate(
                  55,
                  (i) => 'Owned long paragraph $i exact.',
                ).join('\n\n'),
              ),
              child: const Text('Start long actual queue'),
            ),
            TextButton(
              onPressed: () => runtime?.handler.skipToQueueItem(1),
              child: const Text('Queue second actual MP3'),
            ),
            TextButton(
              onPressed: () => runtime?.handler.skipToQueueItem(49),
              child: const Text('Jump visible queue last'),
            ),
            TextButton(onPressed: retire, child: const Text('Retire owner')),
            TextButton(
              onPressed: () => runtime?.controller.stop(),
              child: const Text('Stop actual MP3'),
            ),
          ],
        ),
        if (runtime != null)
          Expanded(
            child: SpeechPlayerPage(
              controller: runtime!.controller,
              english: true,
            ),
          ),
      ],
    ),
  );
}
