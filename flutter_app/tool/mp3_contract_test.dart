// Real FFmpeg MP3 decoding through production HTTP/NDJSON/memory source.
// No audio files, external service or speaker are used. This is not an Android
// AudioTrack/Media3/foreground-service device test.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/speech_repository.dart';
import 'package:bookstark_flutter/core/stream_audio_source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('real MP3 produces decoded PCM before server done and HTTP EOF', () async {
    const ffmpeg = '/usr/bin/ffmpeg';
    final encoder = await Process.start(ffmpeg, [
      '-hide_banner',
      '-loglevel',
      'error',
      '-f',
      'lavfi',
      '-i',
      'sine=frequency=440:sample_rate=24000',
      '-t',
      '8',
      '-ac',
      '1',
      '-c:a',
      'libmp3lame',
      '-b:a',
      '64k',
      '-write_xing',
      '0',
      '-id3v2_version',
      '0',
      '-f',
      'mp3',
      'pipe:1',
    ]);
    final encoderError = encoder.stderr.transform(utf8.decoder).join();
    final encoded = BytesBuilder(copy: false);
    await for (final part in encoder.stdout) {
      encoded.add(part);
      if (encoded.length > 1024 * 1024) throw StateError('Unexpected MP3 size');
    }
    expect(await encoder.exitCode, 0, reason: await encoderError);
    final mp3 = encoded.takeBytes();
    expect(mp3.length, greaterThan(8192));
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final allowFinish = Completer<void>();
    var sentDone = false, pcmBytes = 0;
    final serverError = Completer<Object>();
    final requests = server.listen((request) async {
      try {
        if (request.uri.path == '/api/csrf-token') {
          request.response.cookies.add(Cookie('csrf_token', 'mp3-fixture'));
          request.response.write('{}');
          await request.response.close();
          return;
        }
        expect(request.uri.path, '/api/ai/tts/stream');
        expect(request.headers.value('x-csrf-token'), 'mp3-fixture');
        await request.drain<void>();
        request.response.headers.contentType = ContentType(
          'application',
          'x-ndjson',
          charset: 'utf-8',
        );
        request.response.bufferOutput = false;
        Future<void> send(int start, int end) async {
          for (var offset = start; offset < end; offset += 1024) {
            final last = (offset + 1024).clamp(0, end);
            request.response.writeln(
              jsonEncode({
                'event': 'audio',
                'data': base64Encode(mp3.sublist(offset, last)),
              }),
            );
            await request.response.flush();
          }
        }

        final half = mp3.length ~/ 2;
        await send(0, half);
        await allowFinish.future;
        await send(half, mp3.length);
        sentDone = true;
        request.response.writeln(
          jsonEncode({'event': 'done', 'bytes': mp3.length}),
        );
        await request.response.close();
      } catch (error) {
        if (!serverError.isCompleted) serverError.complete(error);
      }
    });
    final client = BookstarkClient('http://127.0.0.1:${server.port}');
    final abort = Completer<void>();
    final source = MemorySpeechSource(
      RemoteSpeechRepository(
        client,
      ).audio('MP3 contract', 'zh-CN-YunxiNeural', abortTrigger: abort.future),
    );
    final decoder = await Process.start(ffmpeg, [
      '-hide_banner',
      '-loglevel',
      'error',
      '-probesize',
      '32',
      '-analyzeduration',
      '1',
      '-f',
      'mp3',
      '-i',
      'pipe:0',
      '-f',
      's16le',
      '-ac',
      '1',
      '-ar',
      '16000',
      'pipe:1',
    ]);
    final decoderError = decoder.stderr.transform(utf8.decoder).join();
    final firstPcm = Completer<void>(), outputDone = Completer<void>();
    final pcm = decoder.stdout.listen(
      (part) {
        pcmBytes += part.length;
        if (pcmBytes > 1024 * 1024) throw StateError('Unexpected PCM size');
        if (part.isNotEmpty && !firstPcm.isCompleted) firstPcm.complete();
      },
      onDone: outputDone.complete,
      onError: outputDone.completeError,
    );
    Future<void>? feeding;
    try {
      final response = await source.request();
      feeding = () async {
        await for (final part in response.stream) {
          decoder.stdin.add(part);
          await decoder.stdin.flush();
        }
        await decoder.stdin.close();
      }();
      unawaited(
        feeding.then<void>(
          (_) {},
          onError: (Object error, StackTrace stack) {
            if (!firstPcm.isCompleted) firstPcm.completeError(error, stack);
          },
        ),
      );
      await Future.any([
        firstPcm.future,
        serverError.future.then<void>((error) => throw error),
      ]).timeout(const Duration(seconds: 8));
      expect(
        sentDone,
        isFalse,
        reason: 'Decoder must emit actual PCM while synthesis remains open',
      );
      expect(source.bufferedBytes, lessThan(mp3.length));
      allowFinish.complete();
      await feeding.timeout(const Duration(seconds: 8));
      await source.completed;
      expect(
        await decoder.exitCode.timeout(const Duration(seconds: 8)),
        0,
        reason: await decoderError,
      );
      await outputDone.future;
      expect(pcmBytes, greaterThan(16000));
      expect(sentDone, isTrue);
      // One line records the measured property without dumping binary data.
      stdout.writeln(
        'PASS real MP3 -> production authenticated HTTP/NDJSON/memory source -> decoded PCM before done; audio never written to disk',
      );
    } finally {
      if (!allowFinish.isCompleted) allowFinish.complete();
      if (!abort.isCompleted) abort.complete();
      decoder.kill();
      await pcm.cancel();
      await source.disposeSource();
      client.close();
      await requests.cancel();
      await server.close(force: true);
      if (feeding != null) {
        try {
          await feeding;
        } catch (_) {}
      }
    }
  }, timeout: const Timeout(Duration(seconds: 40)));
}
