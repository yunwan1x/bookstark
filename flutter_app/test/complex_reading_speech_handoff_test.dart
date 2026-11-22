import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/complex_reading_selection.dart';
import 'package:bookstark_flutter/core/selected_speech_repository.dart';
import 'package:bookstark_flutter/core/speech_repository.dart';

class FakeSpeech implements SpeechRepository {
  int audioCalls = 0;
  @override
  Future<List<SpeechVoice>> voices() async => [];
  @override
  Stream<List<int>> audio(
    String text,
    String voice, {
    required Future<void> abortTrigger,
  }) async* {
    audioCalls++;
    yield [1];
  }
}

void main() {
  test('HTML actual UTF16 coordinates roundtrip independently of viewport', () {
    final range = {
      'type': 'htmlDomRange',
      'startPath': [0, 1],
      'startOffset': 0,
      'endPath': [0, 1],
      'endOffset': 4,
    };
    final a = ComplexReadingSelection.parse(ComplexEditorKind.html, range);
    expect(
      a.same(ComplexReadingSelection.parse(ComplexEditorKind.html, range)),
      isTrue,
    );
    expect(
      () => ComplexReadingSelection.parse(ComplexEditorKind.html, {
        ...range,
        'rawSourceOffset': 0,
      }),
      throwsFormatException,
    );
  });
  test('engine and coordinates cannot be substituted', () {
    expect(
      () => ComplexReadingSelection.parse(ComplexEditorKind.richdoc, {
        'type': 'presentationSlide',
        'slideId': 'x',
      }),
      throwsFormatException,
    );
    expect(
      () => ComplexReadingSelection.parse(ComplexEditorKind.spreadsheet, {
        'type': 'sheetRange',
        'sheetId': 's',
        'startRow': 0,
        'endRow': 4096,
        'startColumn': 0,
        'endColumn': 0,
      }),
      throwsFormatException,
    );
  });
  test('slide is actual page identity, not fabricated range', () {
    final a = ComplexReadingSelection.parse(ComplexEditorKind.presentation, {
      'type': 'presentationSlide',
      'slideId': 'one',
    });
    expect(
      a.same(
        ComplexReadingSelection.parse(ComplexEditorKind.presentation, {
          'type': 'presentationSlide',
          'slideId': 'two',
        }),
      ),
      isFalse,
    );
  });
  test(
    'each segment performs fresh verification before real synthesis',
    () async {
      final inner = FakeSpeech();
      var verifies = 0;
      final repo = SelectedSpeechRepository(
        inner,
        isCurrent: () => true,
        verifyFresh: () async {
          verifies++;
          return true;
        },
      );
      await repo
          .audio('selected', 'voice', abortTrigger: Completer<void>().future)
          .drain<void>();
      await repo
          .audio('next', 'voice', abortTrigger: Completer<void>().future)
          .drain<void>();
      expect(verifies, 2);
      expect(inner.audioCalls, 2);
    },
  );
  test('source drift results in zero synthesis requests', () async {
    final inner = FakeSpeech(), abort = Completer<void>();
    final repo = SelectedSpeechRepository(
      inner,
      isCurrent: () => true,
      verifyFresh: () async => false,
    );
    await expectLater(
      repo.audio('selected', 'voice', abortTrigger: abort.future).drain<void>(),
      throwsStateError,
    );
    expect(inner.audioCalls, 0);
  });
  test('retirement while fresh read awaits prevents synthesis', () async {
    final inner = FakeSpeech(), verify = Completer<bool>();
    var current = true;
    final repo = SelectedSpeechRepository(
      inner,
      isCurrent: () => current,
      verifyFresh: () => verify.future,
    );
    final result = repo
        .audio('selected', 'voice', abortTrigger: Completer<void>().future)
        .drain<void>();
    final assertion = expectLater(result, throwsStateError);
    await Future<void>.delayed(Duration.zero);
    current = false;
    verify.complete(true);
    await assertion;
    expect(inner.audioCalls, 0);
  });
  test('abort during verifier prevents synthesis', () async {
    final inner = FakeSpeech(),
        verify = Completer<bool>(),
        abort = Completer<void>();
    final repo = SelectedSpeechRepository(
      inner,
      isCurrent: () => true,
      verifyFresh: () => verify.future,
    );
    final result = repo
        .audio('selected', 'voice', abortTrigger: abort.future)
        .drain<void>();
    final assertion = expectLater(result, throwsStateError);
    await Future<void>.delayed(Duration.zero);
    abort.complete();
    await Future<void>.delayed(Duration.zero);
    verify.complete(true);
    await assertion;
    expect(inner.audioCalls, 0);
  });
}
