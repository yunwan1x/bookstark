import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/complex_editor_transport.dart';
import 'package:bookstark_flutter/core/complex_reading_protocol.dart';
import 'package:bookstark_flutter/core/complex_reading_position_vault.dart';
import 'package:bookstark_flutter/core/reading_position_vault.dart';

ComplexReadingIdentity identity({String? fp, int doc = 9}) =>
    ComplexReadingIdentity(
      bookId: 4,
      documentId: doc,
      kind: ComplexEditorKind.html,
      fullFingerprint: fp ?? 'a' * 64,
      sourceDigest: ComplexEditorDocument.parse(
        ComplexEditorKind.html,
        '<p>Original</p>',
      ).digest,
    );
ComplexReadingAnchor anchor() =>
    ComplexReadingAnchor.parse(ComplexEditorKind.html, {
      'type': 'htmlDomScroll',
      'scrolls': [
        {
          'path': [0, 1],
          'top': 123,
          'left': 0,
        },
      ],
    });

class Host {
  int received = 0, generation = 0;
  bool readOnly = true;
  Map<String, Object?>? binding;
  Completer<Object?>? held;
  String? corrupt;
  final calls = <String>[];
  Future<Object?> call(String name, List<Object?> args) async {
    calls.add(name);
    switch (name) {
      case 'beginLoad':
        readOnly = (args[3] as Map)['readOnly'] == true;
        received = 0;
        return {'id': 'load', 'bytes': args[1], 'chunkBytes': 262144};
      case 'appendLoad':
        received += base64Decode(args[2] as String).length;
        return {'id': args[0], 'index': args[1], 'received': received};
      case 'commitLoad':
        generation++;
        return {
          'ready': true,
          'kind': 'html',
          'readOnly': readOnly,
          'generation': generation,
        };
      case 'bindReading':
        binding = Map<String, Object?>.from(args[0] as Map);
        return {'binding': binding};
      case 'captureReading':
        if (held != null) return held!.future;
        return {
          'binding': {...binding!, if (corrupt == 'doc') 'documentId': 10},
          'text': 'Selected plain <tag>',
          'supported': true,
          'selectionKind': 'text',
          'anchor': anchor().value,
        };
      case 'restoreReading':
        return {'binding': binding, 'restored': true};
      case 'retire':
        return null;
    }
    throw StateError('Unexpected command');
  }
}

void main() {
  test('binding requires all fields but ignores map insertion order', () {
    final b = ComplexReadingBinding(
      identity(),
      runtimeLease: 'runtime-lease-123456789',
      generation: 2,
    );
    b.verify(Map.fromEntries(b.toJson().entries.toList().reversed));
    for (final key in [
      'bookId',
      'documentId',
      'kind',
      'fullFingerprint',
      'sourceDigest',
      'runtimeLease',
      'generation',
    ]) {
      final bad = {...b.toJson(), key: key == 'generation' ? 3 : 'other'};
      expect(() => b.verify(bad), throwsFormatException);
    }
  });
  test(
    'typed anchors reject crosskind, negative coordinates, CSS/URL extras',
    () {
      expect(
        () => ComplexReadingAnchor.parse(
          ComplexEditorKind.richdoc,
          anchor().value,
        ),
        throwsFormatException,
      );
      expect(
        () => ComplexReadingAnchor.parse(ComplexEditorKind.html, {
          'type': 'htmlDomScroll',
          'scrolls': [
            {
              'path': [-1],
              'top': 0,
              'left': 0,
            },
          ],
        }),
        throwsFormatException,
      );
      expect(
        () => ComplexReadingAnchor.parse(ComplexEditorKind.html, {
          'type': 'htmlDomScroll',
          'scrolls': [],
          'script': 'alert(1)',
        }),
        throwsFormatException,
      );
    },
  );
  test(
    'plain selected text strictly bounded and unsupported cannot return data',
    () {
      final b = ComplexReadingBinding(
        identity(),
        runtimeLease: 'runtime-lease-123456789',
        generation: 1,
      );
      Map<String, Object?> payload(String text) => {
        'binding': b.toJson(),
        'text': text,
        'supported': true,
        'selectionKind': 'text',
        'anchor': anchor().value,
      };
      expect(
        ComplexReadingCapture.parse(b, payload('😀 plain <b>')).text,
        '😀 plain <b>',
      );
      expect(
        () => ComplexReadingCapture.parse(b, payload('😀' * 9000)),
        throwsFormatException,
      );
      expect(
        () => ComplexReadingCapture.parse(b, {
          ...payload('not selected'),
          'supported': false,
          'selectionKind': 'none',
        }),
        throwsFormatException,
      );
    },
  );
  test(
    'transport uses actual load generation, lease and fullfp without mutation command',
    () async {
      final h = Host(), t = ComplexEditorTransport((n, a) => h.call(n, a));
      await t.load(
        ComplexEditorDocument.parse(ComplexEditorKind.html, '<p>Original</p>'),
      );
      await t.bindReading(identity(), runtimeLease: 'runtime-lease-123456789');
      final selection = await t.captureReading();
      expect(selection.text, 'Selected plain <tag>');
      await t.restoreReading(selection.anchor!);
      expect(
        h.calls,
        containsAllInOrder([
          'commitLoad',
          'bindReading',
          'captureReading',
          'restoreReading',
        ]),
      );
      expect(
        h.calls.any(
          (n) => [
            'acknowledgeSnapshot',
            'beginSnapshot',
            'insertMarkdownSnapshot',
          ].contains(n),
        ),
        false,
      );
    },
  );
  test(
    'editable runtime cannot bind reading and wrong document reply is rejected',
    () async {
      final h = Host(), t = ComplexEditorTransport((n, a) => h.call(n, a));
      final doc = ComplexEditorDocument.parse(
        ComplexEditorKind.html,
        '<p>Original</p>',
      );
      await t.load(doc, readOnly: false);
      await expectLater(
        t.bindReading(identity(), runtimeLease: 'runtime-lease-123456789'),
        throwsStateError,
      );
      await t.load(doc);
      await t.bindReading(identity(), runtimeLease: 'runtime-lease-123456789');
      h.corrupt = 'doc';
      await expectLater(t.captureReading(), throwsFormatException);
    },
  );
  test(
    'late capture after retirement cannot return selected content',
    () async {
      final h = Host(), t = ComplexEditorTransport((n, a) => h.call(n, a));
      await t.load(
        ComplexEditorDocument.parse(ComplexEditorKind.html, '<p>Original</p>'),
      );
      await t.bindReading(identity(), runtimeLease: 'runtime-lease-123456789');
      h.held = Completer<Object?>();
      final f = t.captureReading();
      await Future<void>.delayed(Duration.zero);
      await t.retire();
      final expected = expectLater(f, throwsStateError);
      h.held!.complete({
        'binding': h.binding,
        'text': 'late',
        'supported': true,
        'selectionKind': 'text',
        'anchor': anchor().value,
      });
      await expected;
    },
  );
  test(
    'cold anchor needs same book doc kind source fullfp; never alters MD record',
    () async {
      final values = <String, String>{};
      var current = true;
      ReadingPositionVault base() => ReadingPositionVault(
        namespace: 'owned-space',
        readValue: (k) async => values[k],
        writeValue: (k, v) async {
          values[k] = v;
        },
        deleteValue: (k) async {
          values.remove(k);
        },
      );
      final md = base();
      await md.write(9, const ReadingPosition(.5, 'old-md'));
      final v = ComplexReadingPositionVault(md, isCurrent: () => current);
      await v.write(identity(), anchor());
      final cold = ComplexReadingPositionVault(
        base(),
        isCurrent: () => current,
      );
      expect((await cold.read(identity()))!.value, anchor().value);
      expect(await cold.read(identity(fp: 'b' * 64)), isNull);
      expect(await cold.read(identity(doc: 10)), isNull);
      expect((await md.read(9))!.fraction, .5);
      current = false;
      await expectLater(cold.write(identity(), anchor()), throwsStateError);
      expect((await md.read(9))!.fraction, .5);
    },
  );
  test(
    'corrupt typed record remains until explicit typed-only clear',
    () async {
      final values = <String, String>{};
      final md = ReadingPositionVault(
        namespace: 'owned-space',
        readValue: (k) async => values[k],
        writeValue: (k, v) async {
          values[k] = v;
        },
        deleteValue: (k) async {
          values.remove(k);
        },
      );
      await md.write(9, const ReadingPosition(.2, 'md'));
      final v = ComplexReadingPositionVault(md, isCurrent: () => true);
      await v.write(identity(), anchor());
      final key = values.keys.singleWhere(
        (k) => k.startsWith('bookstark.complex-reading-position'),
      );
      values[key] = 'corrupt';
      await expectLater(v.read(identity()), throwsFormatException);
      expect(values[key], 'corrupt');
      await v.remove(identity());
      expect(values.containsKey(key), false);
      expect((await md.read(9))!.fraction, .2);
    },
  );
  test(
    'drawing, mindmap and slide anchors use genuine typed IDs and signed viewport, never percent',
    () {
      final drawing = ComplexReadingAnchor.parse(ComplexEditorKind.drawing, {
        'type': 'drawingViewport',
        'x': -12.5,
        'y': 42,
        'zoom': 1.2,
        'elementIds': ['actual-element'],
      });
      expect(drawing.value['x'], -12.5);
      final mind = ComplexReadingAnchor.parse(ComplexEditorKind.mindmap, {
        'type': 'mindmapViewport',
        'x': -60,
        'y': 15,
        'scale': .8,
        'nodeIds': ['actual-node'],
      });
      expect(mind.value['nodeIds'], ['actual-node']);
      expect(
        ComplexReadingAnchor.parse(ComplexEditorKind.presentation, {
          'type': 'presentationSlide',
          'slideId': 'actual-slide',
        }).value['slideId'],
        'actual-slide',
      );
      expect(
        () => ComplexReadingAnchor.parse(ComplexEditorKind.presentation, {
          'type': 'presentationSlide',
          'slideId': 'actual-slide',
          'percent': .2,
        }),
        throwsFormatException,
      );
      expect(
        () => ComplexReadingAnchor.parse(ComplexEditorKind.drawing, {
          'type': 'drawingViewport',
          'x': 0,
          'y': 0,
          'zoom': double.nan,
          'elementIds': [],
        }),
        throwsFormatException,
      );
      expect(
        () => ComplexReadingAnchor.parse(ComplexEditorKind.mindmap, {
          'type': 'mindmapViewport',
          'x': 0,
          'y': 0,
          'scale': 1,
          'nodeIds': ['dup', 'dup'],
        }),
        throwsFormatException,
      );
    },
  );
}
