import 'dart:async';
import 'speech_repository.dart';

/// The owner must retire synchronously BEFORE replacing account/space/client.
/// App background/lock is not retirement: media playback continues there.
class SpeechOwner {
  SpeechOwner({required this._isCurrent});
  final bool Function() _isCurrent;
  final _retired = Completer<void>();
  bool get current => !_retired.isCompleted && _isCurrent();
  Future<void> get retired => _retired.future;
  void retire() {
    if (!_retired.isCompleted) _retired.complete();
  }

  void check() {
    if (!current) throw StateError('Speech owner retired');
  }
}

class ScopedSpeechRepository implements SpeechRepository {
  ScopedSpeechRepository(this.inner, this.owner);
  final SpeechRepository inner;
  final SpeechOwner owner;
  @override
  Future<List<SpeechVoice>> voices() async {
    owner.check();
    final source = inner;
    final result = await (source is CancellableSpeechVoices
        ? (source as CancellableSpeechVoices).voicesUntil(owner.retired)
        : source.voices());
    owner.check();
    return result;
  }

  @override
  Stream<List<int>> audio(
    String text,
    String voice, {
    required Future<void> abortTrigger,
  }) async* {
    owner.check();
    final abort = Completer<void>();
    void cancel() {
      if (!abort.isCompleted) abort.complete();
    }

    owner.retired.then((_) => cancel());
    abortTrigger.then(
      (_) => cancel(),
      onError: (Object _, StackTrace _) => cancel(),
    );
    try {
      owner.check();
      if (abort.isCompleted) throw StateError('Speech cancelled');
      await for (final bytes in inner.audio(
        text,
        voice,
        abortTrigger: abort.future,
      )) {
        owner.check();
        if (abort.isCompleted) throw StateError('Speech cancelled');
        yield bytes;
      }
      owner.check();
    } finally {
      cancel();
    }
  }
}
