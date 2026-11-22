import 'package:bookstark_flutter/core/public_selection_protocol.dart';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/complex_editor_transport.dart';
import 'package:bookstark_flutter/core/public_complex_source.dart';
import 'package:bookstark_flutter/core/public_share_models.dart';
import 'package:bookstark_flutter/features/speech/public_reading_speech_capture.dart';

void main() {
  test(
    'actual public selection binds real range/tuple; fresh retarget or changed text revokes speech',
    () async {
      final ref = PublicShareReference(
        Uri.parse('https://example.test'),
        'public-drawing',
      );
      final document = ComplexEditorDocument.parse(
        ComplexEditorKind.drawing,
        '{"elements":[],"appState":{}}',
      );
      var target = 9, text = '选中真实文字😀', reads = 0;
      var current = true;
      Map<String, Object?>? bound;
      PublicComplexContent content() => PublicComplexContent(
        reference: ref,
        title: 'Actual drawing',
        document: document,
        protected: false,
        identity: PublicShareDetail.fromJson(ref, {
          'share_id': 8,
          'target_id': target,
          'share_identify': ref.identify,
          'share_type': 'blog',
          'blog_type': 'note',
          'doc_type': 'drawing',
          'has_password': false,
          'title': 'Actual drawing',
          'content': '',
        }),
      );
      var received = 0;
      final transport = ComplexEditorTransport((name, args) async {
        switch (name) {
          case 'beginLoad':
            return {
              'id': 'load',
              'bytes': document.byteLength,
              'chunkBytes': 262144,
            };
          case 'appendLoad':
            received += base64Decode(args[2] as String).length;
            return {'id': 'load', 'index': args[1], 'received': received};
          case 'commitLoad':
            return {
              'ready': true,
              'readOnly': true,
              'kind': 'drawing',
              'generation': 1,
            };
          case 'bindPublicSelection':
            bound = Map<String, Object?>.from(args[0] as Map);
            return {'binding': bound};
          case 'capturePublicSelection':
            return {
              'binding': bound,
              'text': text,
              'supported': true,
              'selectionKind': 'elements',
              'selection': {
                'type': 'drawingElements',
                'ids': ['real-engine-id'],
              },
              'anchor': null,
            };
          default:
            throw StateError('Unexpected public command');
        }
      });
      final actual = content(), identity = publicSpeechIdentity(actual);
      await transport.load(
        document,
        publicResourceRoot: ref.server,
        publicComplexReadOnly: true,
      );
      await transport.bindPublicSelection(
        identity,
        runtimeLease: 'public-native-runtime-lease',
      );
      final selection = await capturePublicReadingSpeech(
        transport: transport,
        identity: identity,
        isCurrent: () => current,
        freshSource: () async {
          reads++;
          return content();
        },
      );
      expect(selection.text, '选中真实文字😀');
      expect(selection.selectionKind, 'elements');
      expect(selection.bindingId, contains('engineRange'));
      expect(selection.bindingId, contains('"resource":"public-share"'));
      expect(selection.bindingId, contains('"start":0'));
      expect(selection.bindingId, contains('"end":${text.length}'));
      expect(bound!.containsKey('bookId'), isFalse);
      expect(bound!.containsKey('documentId'), isFalse);
      expect(await selection.verifyFreshBinding(), isTrue);
      expect(reads, 2);
      text = '另一个选区';
      expect(await selection.verifyFreshBinding(), isFalse);
      text = selection.text;
      target = 10;
      expect(await selection.verifyFreshBinding(), isFalse);
      target = 9;
      current = false;
      expect(selection.current, isFalse);
      expect(await selection.verifyFreshBinding(), isFalse);
    },
  );
  test(
    'public selected speech rejects missing real engine range and byte overflow',
    () {
      final identity = PublicSelectionIdentity(
        tuple: 'actual-share-identity',
        kind: ComplexEditorKind.drawing,
        sourceDigest: 'a' * 64,
      );
      final binding = PublicSelectionBinding(
        identity,
        runtimeLease: 'public-native-runtime-lease',
        generation: 1,
      );
      final row = <String, Object?>{
        'binding': binding.toJson(),
        'text': 'actual text',
        'supported': true,
        'selectionKind': 'elements',
        'selection': null,
        'anchor': null,
      };
      expect(
        () => PublicSelectionCapture.parse(binding, row),
        throwsFormatException,
      );
      row['selection'] = {
        'type': 'drawingElements',
        'ids': ['real-id'],
      };
      row['text'] = '😀' * 8193;
      expect(
        () => PublicSelectionCapture.parse(binding, row),
        throwsFormatException,
      );
    },
  );
}
