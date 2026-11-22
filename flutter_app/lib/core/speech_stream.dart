import 'dart:convert';

/// Emits each MP3 part immediately. A successful EOF requires an exact done
/// receipt; receiving some audio never implies a complete synthesis.
Stream<List<int>> decodeSpeechAudio(Stream<List<int>> bytes) async* {
  var received = 0, wireBytes = 0;
  var complete = false;
  Stream<List<int>> bounded() async* {
    await for (final part in bytes) {
      wireBytes += part.length;
      if (wireBytes > 2 * 1024 * 1024) {
        throw const FormatException('Speech response exceeds wire limit');
      }
      yield part;
    }
  }

  await for (final raw
      in bounded().transform(utf8.decoder).transform(const LineSplitter())) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (complete || utf8.encode(line).length > 24000) {
      throw const FormatException('Invalid speech frame');
    }
    final frame = jsonDecode(line) as Map;
    switch (frame['event']) {
      case 'audio':
        final data = frame['data'];
        if (data is! String || data.length > 22000) {
          throw const FormatException('Invalid speech audio frame');
        }
        final audio = base64Decode(data);
        if (audio.isEmpty || audio.length > 16 * 1024) {
          throw const FormatException('Invalid audio chunk size');
        }
        received += audio.length;
        if (received > 1024 * 1024) {
          throw const FormatException('Speech audio exceeds limit');
        }
        yield audio;
      case 'done':
        if (received == 0 ||
            frame['bytes'] is! int ||
            frame['bytes'] != received) {
          throw const FormatException('Incomplete speech audio');
        }
        complete = true;
      case 'error':
        throw StateError('语音连接中断，请重试 / Speech connection interrupted; retry');
      default:
        throw const FormatException('Unknown speech frame');
    }
  }
  if (!complete) {
    throw const FormatException('Speech stream ended without completion');
  }
}
