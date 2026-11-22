import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'package:bookstark_flutter/core/native_complex_source_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/local_drawing_retained_export.dart';

void main() {
  test(
    'readonly fallback retains exact original bytes and has no save callback',
    () async {
      const source =
          ' { "elements": [], "files": {}, "appState": {}, '
          '"unknown": "原始文档\\\\n", "trailing": 1 } ';
      final document = ComplexEditorDocument.parse(
        ComplexEditorKind.drawing,
        source,
      );
      var current = true, checks = 0;
      final retained = LocalDrawingRetainedExport(
        document: document,
        verifyFresh: () async {
          checks++;
          if (!current) throw StateError('Owner retired');
        },
      );
      expect(retained.source, source);
      expect(retained.export.bytes, utf8.encode(source));
      expect(
        retained.export.digest,
        sha256.convert(utf8.encode(source)).toString(),
      );
      expect(retained.export.mime, 'application/json');
      await retained.verifyFresh();
      expect(checks, 1);
      current = false;
      await expectLater(retained.verifyFresh(), throwsStateError);
      expect(retained.export.bytes, utf8.encode(source));
    },
  );
  test('another editor kind cannot acquire drawing fallback identity', () {
    final markdown = ComplexEditorDocument.parse(
      ComplexEditorKind.markdown,
      'unchanged',
    );
    expect(
      () => LocalDrawingRetainedExport(
        document: markdown,
        verifyFresh: () async {},
      ),
      throwsArgumentError,
    );
    expect(markdown.source, 'unchanged');
  });
  test(
    'drawing export sends exact old bytes only after fresh owner recheck',
    () async {
      final document = ComplexEditorDocument.parse(
        ComplexEditorKind.drawing,
        '{"elements":[],"files":{},"appState":{},"unknown":"雪😀"}',
      );
      var verified = 0, writes = 0;
      final received = BytesBuilder(copy: false);
      final record = LocalDrawingRetainedExport(
        document: document,
        verifyFresh: () async {
          verified++;
        },
      );
      Future<Map<Object?, Object?>?> invoke(
        String method,
        Map<String, Object?> args,
      ) async {
        switch (method) {
          case 'scopeState':
            return {'epoch': 0};
          case 'activateScope':
            return {'epoch': 1};
          case 'retireScope':
            return {'retired': true};
          case 'beginExport':
            expect(args['sha256'], record.export.digest);
            expect(args['bytes'], record.export.bytes.length);
            expect(args['mime'], 'application/json');
            return {'ready': true};
          case 'writeExport':
            expect(verified, 1);
            writes++;
            received.add(base64Decode(args['data']! as String));
            return {'index': args['index'], 'bytes': received.length};
          case 'finishExport':
            return {
              'saved': true,
              'bytes': received.length,
              'sha256': sha256.convert(received.toBytes()).toString(),
            };
          case 'cancel':
            return {};
          default:
            throw StateError('Unexpected native method');
        }
      }

      final owner = await ComplexSourceIoScope.activate(
        scope: 'a' * 64,
        isCurrent: () => true,
        invoke: invoke,
      );
      final native = NativeComplexSourceIo(
        owner: owner,
        lease: 'drawing-export',
        generation: 1,
        invoke: invoke,
      );
      try {
        expect(
          await native.exportOwnedReview(
            record.export,
            beforeWrite: record.verifyFresh,
          ),
          isTrue,
        );
        expect(writes, 1);
        expect(received.toBytes(), utf8.encode(document.source));
        expect(document.source, record.source);
      } finally {
        native.retire();
        await owner.retire();
      }
    },
  );
  test(
    'owner retired during drawing export picker sends zero body chunks',
    () async {
      final document = ComplexEditorDocument.parse(
        ComplexEditorKind.drawing,
        '{"elements":[],"files":{},"appState":{}}',
      );
      var current = true, writes = 0;
      final entered = Completer<void>(), release = Completer<void>();
      final record = LocalDrawingRetainedExport(
        document: document,
        verifyFresh: () async {
          if (!current) throw StateError('Owner retired');
        },
      );
      Future<Map<Object?, Object?>?> invoke(
        String method,
        Map<String, Object?> args,
      ) async {
        switch (method) {
          case 'scopeState':
            return {'epoch': 0};
          case 'activateScope':
            return {'epoch': 1};
          case 'retireScope':
            return {'retired': true};
          case 'beginExport':
            entered.complete();
            await release.future;
            return {'ready': true};
          case 'writeExport':
            writes++;
            throw StateError('Must not write');
          case 'cancel':
            return {};
          default:
            throw StateError('Unexpected native method');
        }
      }

      final owner = await ComplexSourceIoScope.activate(
        scope: 'a' * 64,
        isCurrent: () => current,
        invoke: invoke,
      );
      final native = NativeComplexSourceIo(
        owner: owner,
        lease: 'drawing-export',
        generation: 1,
        invoke: invoke,
      );
      final operation = native.exportOwnedReview(
        record.export,
        beforeWrite: record.verifyFresh,
      );
      final rejected = expectLater(operation, throwsStateError);
      try {
        await entered.future;
        current = false;
        release.complete();
        await rejected;
        expect(writes, 0);
        expect(record.source, document.source);
      } finally {
        if (!release.isCompleted) release.complete();
        native.retire();
        await owner.retire();
      }
    },
  );
}
