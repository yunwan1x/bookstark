// Copy to test/ after sourceReadOnly protocol changes land.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/complex_editor_transport.dart';

class _HostCommand {
  _HostCommand({
    this.receiptSourceReadOnly = true,
    this.receiptInputLocked = true,
  });
  final bool receiptSourceReadOnly;
  final bool? receiptInputLocked;
  final calls = <String>[];
  Map<Object?, Object?>? beginOptions;
  int received = 0;

  Future<Object?> call(String name, List<Object?> args) async {
    calls.add(name);
    switch (name) {
      case 'beginLoad':
        beginOptions = (args[3] as Map).cast<Object?, Object?>();
        return {'id': 'owned-load', 'bytes': args[1], 'chunkBytes': 262144};
      case 'appendLoad':
        final data = base64Decode(args[2] as String);
        received += data.length;
        return {'id': args[0], 'index': args[1], 'received': received};
      case 'commitLoad':
        return {
          'version': 1,
          'kind': 'html',
          'ready': true,
          'readOnly': false,
          'sourceReadOnly': receiptSourceReadOnly,
          if (receiptInputLocked != null) 'inputLocked': receiptInputLocked,
          'dirty': false,
          'revision': 0,
          'generation': 4,
        };
      case 'abortLoad':
        return true;
      case 'retire':
        return true;
      default:
        throw StateError('unexpected host command: $name');
    }
  }
}

void main() {
  const exactSource = '\ufeff<!doctype html>\r\n<p>只读 🧭</p>\n';

  test(
    'sourceReadOnly is explicit and validated without changing raw source',
    () async {
      final host = _HostCommand();
      final transport = ComplexEditorTransport(host.call);
      final document = ComplexEditorDocument.parse(
        ComplexEditorKind.html,
        exactSource,
      );
      await transport.load(document, readOnly: false, sourceReadOnly: true);
      expect(host.beginOptions, containsPair('readOnly', false));
      expect(host.beginOptions, containsPair('sourceReadOnly', true));
      expect(transport.generation, 4);
      expect(document.source, exactSource);
      await transport.retire();
    },
  );

  test(
    'default editable mode accepts legacy ready receipt without inputLocked',
    () async {
      final host = _HostCommand(
        receiptSourceReadOnly: false,
        receiptInputLocked: null,
      );
      final transport = ComplexEditorTransport(host.call);
      final document = ComplexEditorDocument.parse(
        ComplexEditorKind.html,
        exactSource,
      );
      await transport.load(document, readOnly: false);
      expect(host.beginOptions, containsPair('sourceReadOnly', false));
      await transport.retire();
    },
  );

  test('mismatched sourceReadOnly ready receipt fails closed', () async {
    final host = _HostCommand(receiptSourceReadOnly: false);
    final transport = ComplexEditorTransport(host.call);
    final document = ComplexEditorDocument.parse(
      ComplexEditorKind.html,
      exactSource,
    );
    await expectLater(
      transport.load(document, readOnly: false, sourceReadOnly: true),
      throwsFormatException,
    );
    expect(host.calls, contains('abortLoad'));
    expect(transport.generation, isNull);
    await transport.retire();
  });

  test('sourceReadOnly is rejected for preview and non-HTML kinds', () async {
    final host = _HostCommand();
    final transport = ComplexEditorTransport(host.call);
    final html = ComplexEditorDocument.parse(
      ComplexEditorKind.html,
      '<p>x</p>',
    );
    await expectLater(
      transport.load(html, readOnly: true, sourceReadOnly: true),
      throwsArgumentError,
    );
    final sheet = ComplexEditorDocument.parse(
      ComplexEditorKind.spreadsheet,
      '{"id":"w","appVersion":"0.25.1","locale":"enUS","styles":{},"sheetOrder":["s"],"sheets":{"s":{"id":"s","name":"Sheet1","rowCount":1000,"columnCount":26,"defaultColumnWidth":100,"defaultRowHeight":24,"freeze":{"startRow":-1,"startColumn":-1,"ySplit":0,"xSplit":0},"rowData":{},"columnData":{},"mergeData":[],"cellData":{}}}}',
    );
    await expectLater(
      transport.load(sheet, readOnly: false, sourceReadOnly: true),
      throwsArgumentError,
    );
    expect(host.calls, isEmpty);
    await transport.retire();
  });
}
