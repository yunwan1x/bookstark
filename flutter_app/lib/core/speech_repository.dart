import 'dart:async';
import 'api_client.dart';
import 'speech_stream.dart';

class SpeechVoice {
  const SpeechVoice({
    required this.id,
    required this.name,
    required this.locale,
  });
  final String id, name, locale;
}

abstract interface class SpeechRepository {
  Future<List<SpeechVoice>> voices();
  Stream<List<int>> audio(
    String text,
    String voice, {
    required Future<void> abortTrigger,
  });
}

abstract interface class CancellableSpeechVoices {
  Future<List<SpeechVoice>> voicesUntil(Future<void> abortTrigger);
}

class RemoteSpeechRepository
    implements SpeechRepository, CancellableSpeechVoices {
  RemoteSpeechRepository(this.client);
  final BookstarkClient client;
  static bool _validVoice(String value) =>
      RegExp(r'^[a-zA-Z0-9_-]{1,80}$').hasMatch(value);
  @override
  Future<List<SpeechVoice>> voices() => voicesUntil(Completer<void>().future);
  @override
  Future<List<SpeechVoice>> voicesUntil(Future<void> abortTrigger) async {
    final result = await client.speechVoicesJson(abortTrigger: abortTrigger);
    final raw = result['voices'];
    if (raw is! List || raw.isEmpty || raw.length > 16) {
      throw const FormatException('Invalid speech voice catalogue');
    }
    final rows = raw;
    final seen = <String>{};
    return rows.map((value) {
      final row = value as Map;
      final id = row['id'] as String;
      if (row['name'] is! String ||
          (row['name'] as String).length > 160 ||
          row['locale'] is! String ||
          !RegExp(
            r'^[a-zA-Z]{2,3}(?:-[a-zA-Z0-9]{2,8}){0,3}$',
          ).hasMatch(row['locale'] as String)) {
        throw const FormatException('Invalid speech voice metadata');
      }
      if (!_validVoice(id) || !seen.add(id)) {
        throw const FormatException('Invalid speech voice');
      }
      return SpeechVoice(
        id: id,
        name: row['name'] as String,
        locale: row['locale'] as String,
      );
    }).toList();
  }

  @override
  Stream<List<int>> audio(
    String text,
    String voice, {
    required Future<void> abortTrigger,
  }) {
    final readable = text.trim();
    if (readable.isEmpty ||
        readable.runes.length > 800 ||
        !_validVoice(voice)) {
      throw const FormatException(
        '每段朗读需1—800字和有效音色 / Each passage requires 1–800 characters and a valid voice',
      );
    }
    return decodeSpeechAudio(
      client.postStream(
        '/api/ai/tts/stream',
        {'text': readable, 'voice': voice},
        accept: 'application/x-ndjson',
        abortTrigger: abortTrigger,
      ),
    );
  }
}
