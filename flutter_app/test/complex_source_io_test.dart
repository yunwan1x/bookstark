// NOT RUN. Fake bridge verifies protocol/client/controller semantics, not SAF/Native.
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/complex_recovery_store.dart';
import 'package:bookstark_flutter/core/complex_recovery_vault.dart';
import 'package:bookstark_flutter/core/local_complex_editor_controller.dart';
import 'package:bookstark_flutter/core/local_complex_notes_repository.dart';
import 'package:bookstark_flutter/core/native_complex_source_io.dart';
import 'package:bookstark_flutter/core/complex_source_io_controller.dart';

class Bridge {
  int epoch = 0, reads = 0, offset = 0, index = 0;
  bool current = true, cancelPicker = false, failFinish = false;
  String? scope;
  List<int> source = utf8.encode('<p>incoming 😀</p>');
  final exported = BytesBuilder(copy: false), calls = <String>[];
  Future<void> Function()? beforeRead;
  Future<Map<Object?, Object?>?> invoke(
    String method,
    Map<String, Object?> a,
  ) async {
    calls.add(method);
    final id = a['id'];
    switch (method) {
      case 'scopeState':
        return {'epoch': epoch};
      case 'activateScope':
        if (a['expectedEpoch'] != epoch) throw StateError('stale activation');
        scope = a['scope'] as String;
        return {'epoch': ++epoch};
      case 'retireScope':
        if (a['epoch'] == epoch) {
          scope = null;
          epoch++;
        }
        return {'retired': true};
      case 'pickImport':
        offset = 0;
        index = 0;
        return {
          'id': id,
          'cancelled': cancelPicker,
          'name': 'source.json',
          'mime': 'application/octet-stream',
        };
      case 'readImport':
        await beforeRead?.call();
        reads++;
        if (offset == source.length) {
          return {
            'id': id,
            'index': a['index'],
            'bytes': offset,
            'data': '',
            'done': true,
            'sha256': sha256.convert(source).toString(),
          };
        }
        final end = (offset + 7).clamp(0, source.length),
            bytes = source.sublist(offset, end);
        offset = end;
        return {
          'id': id,
          'index': a['index'],
          'bytes': offset,
          'data': base64Encode(bytes),
          'done': false,
        };
      case 'beginExport':
        return {'id': id, 'ready': true};
      case 'writeExport':
        exported.add(base64Decode(a['data'] as String));
        return {'id': id, 'index': a['index'], 'bytes': exported.length};
      case 'finishExport':
        if (failFinish) throw StateError('provider close failed');
        final bytes = exported.toBytes();
        return {
          'id': id,
          'saved': true,
          'bytes': bytes.length,
          'sha256': sha256.convert(bytes).toString(),
        };
      case 'cancel':
        return {'id': id, 'cancelled': true};
    }
    throw StateError('Unknown command');
  }

  Future<ComplexSourceIoScope> owner() => ComplexSourceIoScope.activate(
    scope: 'a' * 64,
    isCurrent: () => current,
    invoke: invoke,
  );
  NativeComplexSourceIo client(ComplexSourceIoScope owner) =>
      NativeComplexSourceIo(
        owner: owner,
        lease: 'fixed-native-lease',
        generation: 7,
        invoke: invoke,
      );
}

class BytesStore implements ComplexRecoveryBytesStore {
  final values = <String, Uint8List>{};
  bool fail = false;
  @override
  Future<Uint8List?> read(String key) async => values[key];
  @override
  Future<void> write(String key, Uint8List bytes) async {
    if (fail) throw StateError('flush');
    values[key] = bytes;
  }

  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }
}

class Repository implements ComplexNotesRepository {
  @override
  String get scope => 'b' * 64;
  @override
  String get collection => 'note';
  @override
  ComplexEditorKind get kind => ComplexEditorKind.html;
  int saves = 0;
  late final baseline = ComplexNote(
    scope: scope,
    id: 9,
    collection: collection,
    title: 'original title',
    document: ComplexEditorDocument.parse(kind, '<p>SQL old</p>'),
    version: 7,
    labels: ['exact'],
  );
  @override
  Future<ComplexNote> read(int id) async => baseline;
  @override
  Future<ComplexNote> save(ComplexNote baseline, ComplexNoteEdit edit) async {
    saves++;
    throw StateError('I/O must not save');
  }

  @override
  void dispose() {}
}

void main() {
  test(
    'strict bounded chunks preserve BOM/emoji/CRLF and verify actual source hash',
    () async {
      final b = Bridge()..source = utf8.encode('\ufeff\ufeff<p>😀</p>\r\n'),
          owner = await b.owner();
      final result = await b.client(owner).pick(ComplexEditorKind.html);
      expect(result!.document.source, '\ufeff\ufeff<p>😀</p>\r\n');
      expect(b.reads, greaterThan(1));
      expect(b.calls.last, 'cancel');
    },
  );
  test(
    'wrong actual format and cipher prefix reject despite accepted filename/MIME',
    () async {
      for (final source in ['not json', 'ENC:v2:opaque']) {
        final b = Bridge()..source = utf8.encode(source),
            owner = await b.owner();
        await expectLater(
          b.client(owner).pick(ComplexEditorKind.drawing),
          throwsA(anything),
        );
        expect(b.calls.last, 'cancel');
      }
    },
  );
  test('cancelled system picker reads zero bytes', () async {
    final b = Bridge()..cancelPicker = true, owner = await b.owner();
    expect(await b.client(owner).pick(ComplexEditorKind.html), isNull);
    expect(b.reads, 0);
  });
  test(
    'scope retirement rejects late selected bytes and cannot retarget a new scope',
    () async {
      final b = Bridge(), owner = await b.owner();
      b.beforeRead = () async {
        b.current = false;
        await owner.retire();
      };
      await expectLater(
        b.client(owner).pick(ComplexEditorKind.html),
        throwsStateError,
      );
      expect(b.scope, isNull);
    },
  );
  test(
    'direct export completion requires close receipt exact bytes/hash; no cache/path',
    () async {
      final b = Bridge(), owner = await b.owner();
      final document = ComplexEditorDocument.parse(
        ComplexEditorKind.html,
        '\ufeff<p>export😀</p>',
      );
      expect(await b.client(owner).export(document, name: 'source.html'), true);
      expect(b.exported.toBytes(), utf8.encode(document.source));
      expect(
        b.calls,
        containsAllInOrder(['beginExport', 'writeExport', 'finishExport']),
      );
      expect(b.calls.any((v) => v.toLowerCase().contains('cache')), false);
    },
  );
  test('provider close failure never produces export success', () async {
    final b = Bridge()..failFinish = true, owner = await b.owner();
    await expectLater(
      b
          .client(owner)
          .export(
            ComplexEditorDocument.parse(ComplexEditorKind.html, '<p>x</p>'),
            name: 'source.html',
          ),
      throwsStateError,
    );
    expect(b.calls.last, 'cancel');
  });
  for (final approved in [false, true]) {
    test(
      'import confirmation $approved changes durable draft only, SQL Save remains zero',
      () async {
        final b = Bridge(),
            owner = await b.owner(),
            repository = Repository(),
            bytes = BytesStore();
        final editor = LocalComplexEditorController(
          repository: repository,
          vault: ComplexRecoveryVault(
            scope: repository.scope,
            collection: 'note',
            kind: repository.kind,
            store: bytes,
          ),
          baseline: repository.baseline,
        );
        addTearDown(editor.dispose);
        var loads = 0;
        final io = ComplexSourceIoController(
          editor: editor,
          owner: owner,
          capture: () async => ComplexEditorDocument.parse(
            ComplexEditorKind.html,
            '<p>unsaved original</p>',
          ),
          prepareNative: () async => b.client(owner),
          replaceSurface: () async {
            loads++;
          },
          isCurrent: () => b.current,
          onDurableHandoff: (_) {},
        );
        addTearDown(io.dispose);
        await io.importSource(confirm: (_) async => approved);
        expect(repository.saves, 0);
        expect(repository.baseline.document.source, '<p>SQL old</p>');
        expect(
          editor.edit.document.source,
          approved ? '<p>incoming 😀</p>' : '<p>unsaved original</p>',
        );
        expect(editor.draftDurable, true);
        expect(loads, 1);
      },
    );
  }
  test(
    'failed durable checkpoint never opens picker or overwrites original SQL',
    () async {
      final b = Bridge(),
          owner = await b.owner(),
          repository = Repository(),
          bytes = BytesStore()..fail = true;
      final editor = LocalComplexEditorController(
        repository: repository,
        vault: ComplexRecoveryVault(
          scope: repository.scope,
          collection: 'note',
          kind: repository.kind,
          store: bytes,
        ),
        baseline: repository.baseline,
      );
      addTearDown(editor.dispose);
      final io = ComplexSourceIoController(
        editor: editor,
        owner: owner,
        capture: () async => ComplexEditorDocument.parse(
          ComplexEditorKind.html,
          '<p>unsaved</p>',
        ),
        prepareNative: () async => b.client(owner),
        replaceSurface: () async {},
        isCurrent: () => b.current,
        onDurableHandoff: (_) {},
      );
      addTearDown(io.dispose);
      await io.importSource(confirm: (_) async => true);
      expect(b.calls, isNot(contains('pickImport')));
      expect(repository.saves, 0);
      expect(io.phase, ComplexSourceIoPhase.failed);
    },
  );
}
