// Draft only; no toolchain execution during shared Native.
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/complex_editor_transport.dart';

void main() {
  test(
    'new typed readonly boot contains no token/password/account and no write capability',
    () async {
      final doc = ComplexEditorDocument.parse(
        ComplexEditorKind.drawing,
        '{"elements":[],"appState":{}}',
      );
      Map<String, Object?>? options;
      var received = 0;
      final commands = <String>[];
      final transport = ComplexEditorTransport((name, args) async {
        commands.add(name);
        if (name == 'beginLoad') {
          options = Map<String, Object?>.from(args[3] as Map);
          return {
            'id': 'load-fixture',
            'bytes': doc.byteLength,
            'chunkBytes': 262144,
          };
        }
        if (name == 'appendLoad') {
          received += base64Decode(args[2] as String).length;
          return {'id': args[0], 'index': args[1], 'received': received};
        }
        if (name == 'commitLoad') {
          return {
            'ready': true,
            'kind': 'drawing',
            'readOnly': true,
            'sourceReadOnly': false,
            'generation': 1,
          };
        }
        throw StateError('Unexpected command');
      });
      await transport.load(
        doc,
        publicResourceRoot: Uri.parse('https://demo.invalid/mount'),
        publicComplexReadOnly: true,
        readOnly: true,
        title: 'Public drawing',
      );
      expect(options!['publicComplexReadOnly'], true);
      expect(options!['readOnly'], true);
      expect(
        options!.keys.any(
          (key) => [
            'token',
            'password',
            'cookie',
            'account',
            'authorization',
            'sharedMarkdownEditing',
          ].contains(key),
        ),
        false,
      );
      expect(commands, ['beginLoad', 'appendLoad', 'commitLoad']);
    },
  );
  test(
    'new mode rejects editable/source/shared/local or missing public root before dispatch',
    () async {
      final doc = ComplexEditorDocument.parse(
        ComplexEditorKind.drawing,
        '{"elements":[]}',
      );
      var commands = 0;
      Future<Object?> command(String name, List<Object?> args) async {
        commands++;
        throw StateError('Must not dispatch');
      }

      for (final setup in <Future<void> Function(ComplexEditorTransport)>[
        (t) => t.load(doc, publicComplexReadOnly: true),
        (t) => t.load(
          doc,
          publicComplexReadOnly: true,
          publicResourceRoot: Uri.parse('https://demo.invalid'),
          readOnly: false,
        ),
        (t) => t.load(
          doc,
          publicComplexReadOnly: true,
          publicResourceRoot: Uri.parse('https://demo.invalid'),
          sharedMarkdownEditing: true,
        ),
        (t) => t.load(
          doc,
          publicComplexReadOnly: true,
          publicResourceRoot: Uri.parse('https://demo.invalid'),
          localMarkdownImages: true,
        ),
      ]) {
        await expectLater(
          setup(ComplexEditorTransport(command)),
          throwsArgumentError,
        );
      }
      expect(commands, 0);
    },
  );
  test(
    'legacy public Markdown and shared Markdown keep their original option protocol',
    () async {
      for (final shared in [false, true]) {
        final doc = ComplexEditorDocument.parse(
          ComplexEditorKind.markdown,
          '# Existing MD',
        );
        var received = 0;
        Map? options;
        final transport = ComplexEditorTransport((name, args) async {
          if (name == 'beginLoad') {
            options = args[3] as Map;
            return {
              'id': 'load-fixture',
              'bytes': doc.byteLength,
              'chunkBytes': 262144,
            };
          }
          if (name == 'appendLoad') {
            received += base64Decode(args[2] as String).length;
            return {'id': args[0], 'index': args[1], 'received': received};
          }
          if (name == 'commitLoad') {
            return {
              'ready': true,
              'kind': 'markdown',
              'readOnly': !shared,
              'sourceReadOnly': false,
              'generation': 1,
            };
          }
          throw StateError('Unexpected');
        });
        await transport.load(
          doc,
          publicResourceRoot: Uri.parse('https://demo.invalid'),
          sharedMarkdownEditing: shared,
          readOnly: !shared,
        );
        expect(options!.containsKey('publicComplexReadOnly'), false);
        expect(options!['sharedMarkdownEditing'], shared ? true : null);
      }
    },
  );
  test(
    'Native new factory command list cannot call save upload AI export input-unlock',
    () async {
      final native = await File(
        'android/app/src/main/kotlin/com/bookstark/bookstark_flutter/ComplexEditorView.kt',
      ).readAsString();
      final start = native.indexOf('if(publicComplexReadOnly) {');
      final end = native.indexOf('if(localMarkdownImages &&', start);
      expect(start, greaterThan(0));
      expect(end, greaterThan(start));
      final policy = native.substring(start, end);
      for (final denied in [
        '"insertMarkdownSnapshot"',
        '"acknowledgeSnapshot"',
        '"setInputLocked"',
        '"upload"',
        '"save"',
        '"export"',
        '"ai"',
      ]) {
        expect(policy.contains(denied), false);
      }
      expect(policy.contains('options["readOnly"] == true'), true);
      expect(policy.contains('sharedEditing || localMarkdownImages'), true);
      expect(native.contains('publicMode = true, sharedEditing = true'), true);
    },
  );
}
