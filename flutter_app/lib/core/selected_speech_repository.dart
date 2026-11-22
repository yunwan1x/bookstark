import 'speech_repository.dart';

/// Verify real source and engine selection at each synthesis subscription.
/// No transport callbacks, session changes, or permissions are introduced.
class SelectedSpeechRepository implements SpeechRepository {
  SelectedSpeechRepository(
    this.inner, {
    required this.isCurrent,
    required this.verifyFresh,
  });
  final SpeechRepository inner;
  final bool Function() isCurrent;
  final Future<bool> Function() verifyFresh;
  @override
  Future<List<SpeechVoice>> voices() async {
    if (!isCurrent()) throw StateError('Selected reading retired');
    final voices = await inner.voices();
    if (!isCurrent()) throw StateError('Selected reading retired');
    return voices;
  }

  @override
  Stream<List<int>> audio(
    String text,
    String voice, {
    required Future<void> abortTrigger,
  }) async* {
    var aborted = false;
    final observedAbort = abortTrigger.then(
      (_) {
        aborted = true;
      },
      onError: (Object _, StackTrace _) {
        aborted = true;
      },
    );
    if (!isCurrent() ||
        aborted ||
        !await verifyFresh() ||
        !isCurrent() ||
        aborted) {
      throw StateError('Selection or source changed');
    }
    await for (final bytes in inner.audio(
      text,
      voice,
      abortTrigger: observedAbort,
    )) {
      if (!isCurrent() || aborted) throw StateError('Selected reading retired');
      yield bytes;
    }
  }
}
