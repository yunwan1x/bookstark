import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/complex_recovery_vault.dart';
import 'package:bookstark_flutter/core/complex_recovery_store.dart';
import 'package:bookstark_flutter/core/local_complex_notes_repository.dart';

const _scopeA =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _scopeB =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

void main() {
  group('ComplexRecoveryRecord', () {
    test(
      'round-trips exact source for seven explicit WebView kinds and validates UTF-8 byte length',
      () {
        final samples = <ComplexEditorKind, String>{
          ComplexEditorKind.markdown: '\ufeff# 本地文章\r\n**草稿😀**\r\n',
          ComplexEditorKind.html:
              '\ufeff<!doctype html>\r\n<p>\u539f\u6587\u{1F600}</p>\r\n',
          ComplexEditorKind.spreadsheet:
              '{"id":"w","name":"","appVersion":"0.25.1","locale":"enUS","styles":{},"sheetOrder":["s"],"sheets":{"s":{"id":"s","name":"Sheet1","rowCount":1000,"columnCount":26,"defaultColumnWidth":100,"defaultRowHeight":24,"freeze":{"startRow":-1,"startColumn":-1,"ySplit":0,"xSplit":0},"rowData":{},"columnData":{},"mergeData":[],"cellData":{}}},"future":{"opaque":true}}',
          ComplexEditorKind.drawing:
              ' {"elements":[],"future":{"opaque":true}} ',
          ComplexEditorKind.mindmap:
              '{"nodeData":{"id":"r","topic":"\\u9605\\u8bfb"},"future":true}',
          ComplexEditorKind.richdoc:
              '{"schema":"bookstark-richdoc","schema_version":1,"data":{"main":[{"value":"\\ud83d\\ude00"}]},"future":true}',
          ComplexEditorKind.presentation:
              '{"width":1000,"height":562.5,"slides":[{"id":"s","elements":[]}],"future":true}',
        };
        for (final entry in samples.entries) {
          final doc = ComplexEditorDocument.parse(entry.key, entry.value);
          final baseline = _note(
            document: doc,
            collection: entry.key == ComplexEditorKind.markdown
                ? 'article'
                : 'note',
          );
          final record = ComplexRecoveryRecord.capture(
            baseline,
            ComplexNoteEdit(
              title: baseline.title,
              document: doc,
              labels: baseline.labels,
            ),
            pending: false,
          );
          final bytes = record.encode();
          final metaLength = ByteData.sublistView(
            bytes,
            0,
            4,
          ).getUint32(0, Endian.big);
          final metadata = jsonDecode(
            utf8.decode(Uint8List.sublistView(bytes, 4, 4 + metaLength)),
          );
          expect(metadata['sourceBytes'], utf8.encode(entry.value).length);
          final decoded = ComplexRecoveryRecord.decode(bytes);
          expect(decoded.kind, entry.key);
          expect(decoded.edit.document.source, entry.value);
          expect(
            decoded.edit.document.byteLength,
            utf8.encode(entry.value).length,
          );
          expect(decoded.edit.document.digest, doc.digest);
        }
        final html = samples[ComplexEditorKind.html]!;
        final doc = ComplexEditorDocument.parse(ComplexEditorKind.html, html);
        expect(doc.byteLength, greaterThan(doc.source.length));
        expect(doc.source, startsWith('\ufeff'));
        expect(doc.source, contains('\r\n'));
      },
    );

    test('Markdown recovery cannot cross into ordinary native notes', () {
      final doc = ComplexEditorDocument.parse(
        ComplexEditorKind.markdown,
        '# article',
      );
      final baseline = _note(document: doc, collection: 'article');
      final record = ComplexRecoveryRecord.capture(
        baseline,
        ComplexNoteEdit(
          title: baseline.title,
          document: doc,
          labels: baseline.labels,
        ),
        pending: true,
      );
      expect(
        ComplexRecoveryRecord.decode(record.encode()).collection,
        'article',
      );
      expect(
        () => ComplexRecoveryRecord.capture(
          _note(document: doc),
          record.edit,
          pending: true,
        ),
        throwsFormatException,
      );
      final bytes = record.encode();
      final count = ByteData.sublistView(bytes, 0, 4).getUint32(0, Endian.big);
      final metadata =
          jsonDecode(utf8.decode(Uint8List.sublistView(bytes, 4, 4 + count)))
              as Map<String, dynamic>;
      metadata['collection'] = 'note';
      final changed = _envelope(
        utf8.encode(jsonEncode(metadata)),
        Uint8List.sublistView(bytes, 4 + count),
      );
      expect(
        () => ComplexRecoveryRecord.decode(changed),
        throwsFormatException,
      );
    });

    test(
      'round-trips near-20 MiB presentation and rejects source over limit',
      () {
        const prefix =
            '{"width":1,"height":1,"slides":[{"id":"s","elements":[]}],"future":"';
        const suffix = '"}';
        final max = ComplexEditorKind.presentation.maxBytes;
        final pad = max - utf8.encode(prefix + suffix).length;
        final source = prefix + ('x' * pad) + suffix;
        final document = ComplexEditorDocument.parse(
          ComplexEditorKind.presentation,
          source,
        );
        expect(document.byteLength, max);
        final baseline = _note(document: document);
        final record = ComplexRecoveryRecord.capture(
          baseline,
          ComplexNoteEdit(
            title: baseline.title,
            document: document,
            labels: baseline.labels,
          ),
          pending: true,
        );
        final decoded = ComplexRecoveryRecord.decode(record.encode());
        expect(decoded.edit.document.source, source);
        expect(decoded.pending, isTrue);
        expect(
          () => ComplexEditorDocument.parse(
            ComplexEditorKind.presentation,
            prefix + ('x' * (pad + 1)) + suffix,
          ),
          throwsFormatException,
        );
      },
    );

    test('rejects malformed envelopes without deleting stored bytes', () async {
      final baseline = _note();
      final record = _record(baseline);
      final valid = record.encode();
      final metaLength = ByteData.sublistView(
        valid,
        0,
        4,
      ).getUint32(0, Endian.big);
      final metadataBytes = Uint8List.sublistView(valid, 4, 4 + metaLength);
      final metadata =
          jsonDecode(utf8.decode(metadataBytes)) as Map<String, Object?>;
      final body = Uint8List.sublistView(valid, 4 + metaLength);
      final changedBody = Uint8List.fromList(body);
      final numberAt = changedBody.indexOf(49);
      changedBody[numberAt] = 50;
      final broken = <String, Uint8List>{
        'header length': Uint8List.fromList([
          255,
          255,
          255,
          255,
          ...valid.sublist(4),
        ]),
        'metadata UTF-8': _envelope([255], const []),
        'metadata JSON': _envelope(utf8.encode('{'), const []),
        'version': _envelope(
          utf8.encode(jsonEncode({...metadata, 'version': 2})),
          body,
        ),
        'type': _envelope(
          utf8.encode(jsonEncode({...metadata, 'kind': 'unknown'})),
          body,
        ),
        'source digest': _envelope(metadataBytes, changedBody),
      };
      for (final entry in broken.entries) {
        final memory = _MemoryStore();
        final vault = _vault(memory);
        await vault.write(record);
        final key = memory.values.keys.single;
        memory.values[key] = Uint8List.fromList(entry.value);
        await expectLater(
          vault.read(baseline.id),
          throwsFormatException,
          reason: entry.key,
        );
        expect(memory.values.containsKey(key), isTrue, reason: entry.key);
        expect(
          memory.values[key],
          orderedEquals(entry.value),
          reason: entry.key,
        );
      }
    });

    test(
      'pending state round-trips and baseline versus observed checks differ',
      () {
        final baseline = _note();
        final edit = ComplexNoteEdit(
          title: 'Changed title',
          document: ComplexEditorDocument.parse(
            ComplexEditorKind.drawing,
            '{"elements":[],"future":"changed"}',
          ),
          labels: const ['new-label'],
        );
        final record = ComplexRecoveryRecord.decode(
          ComplexRecoveryRecord.capture(baseline, edit, pending: true).encode(),
        );
        expect(record.pending, isTrue);
        expect(record.baselineMatches(baseline), isTrue);
        expect(record.observedMatches(baseline), isFalse);
        final observed = ComplexNote(
          scope: baseline.scope,
          id: baseline.id,
          collection: baseline.collection,
          title: edit.title,
          document: edit.document,
          version: baseline.version + 1,
          labels: edit.labels,
        );
        expect(record.owns(observed), isTrue);
        expect(record.baselineMatches(observed), isFalse);
        expect(record.observedMatches(observed), isTrue);
      },
    );

    test(
      'baseline fingerprint changes with content, title, labels, version, or scope',
      () {
        final baseline = _note();
        final fingerprint = complexNoteFingerprint(baseline);
        final changed = [
          _note(
            document: ComplexEditorDocument.parse(
              ComplexEditorKind.drawing,
              '{"elements":[],"future":2}',
            ),
          ),
          _note(title: 'other'),
          _note(labels: const ['other']),
          _note(version: baseline.version + 1),
          _note(scope: _scopeB),
        ];
        for (final note in changed) {
          expect(complexNoteFingerprint(note), isNot(fingerprint));
        }
      },
    );
  });

  group('ComplexRecoveryVault', () {
    test(
      'scope, id, kind, and collection mismatches cannot be adopted',
      () async {
        final cases =
            <({String name, ComplexNote foreign, ComplexNote target})>[
              (name: 'scope', foreign: _note(), target: _note(scope: _scopeB)),
              (name: 'id', foreign: _note(), target: _note(id: 19)),
              (
                name: 'kind',
                foreign: _note(),
                target: _note(
                  kind: ComplexEditorKind.mindmap,
                  source: '{"nodeData":{"id":"root","topic":"target"}}',
                ),
              ),
              (
                name: 'collection',
                foreign: _note(),
                target: _note(collection: 'article'),
              ),
            ];
        for (final item in cases) {
          final memory = _MemoryStore();
          final foreignVault = _vault(
            memory,
            scope: item.foreign.scope,
            collection: item.foreign.collection,
            kind: item.foreign.document.kind,
          );
          final targetVault = _vault(
            memory,
            scope: item.target.scope,
            collection: item.target.collection,
            kind: item.target.document.kind,
          );
          final foreign = _record(item.foreign);
          await foreignVault.write(foreign);
          await targetVault.write(_record(item.target));
          final targetKey = memory.values.keys.last;
          memory.values[targetKey] = foreign.encode();
          await expectLater(
            targetVault.read(item.target.id),
            throwsFormatException,
            reason: item.name,
          );
          expect(
            memory.values.containsKey(targetKey),
            isTrue,
            reason: item.name,
          );
        }
      },
    );

    test('delayed write followed by remove cannot resurrect record', () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      final memory = _MemoryStore()
        ..writeEntered = entered
        ..finishWrite = release;
      final vault = _vault(memory);
      final note = _note();
      final write = vault.write(_record(note));
      await entered.future;
      final remove = vault.remove(note.id);
      release.complete();
      await write;
      await remove;
      expect(await vault.read(note.id), isNull);
      expect(memory.values, isEmpty);
    });

    test(
      'removing one recovery namespace leaves other scopes untouched',
      () async {
        final memory = _MemoryStore();
        final first = _vault(memory);
        final second = _vault(
          memory,
          scope: _scopeB,
          collection: 'article',
          kind: ComplexEditorKind.mindmap,
        );
        final firstRecord = _record(_note());
        final secondNote = _note(
          scope: _scopeB,
          collection: 'article',
          kind: ComplexEditorKind.mindmap,
          source: '{"nodeData":{"id":"root","topic":"second"}}',
        );
        final secondRecord = _record(secondNote);
        await first.write(firstRecord);
        await second.write(secondRecord);
        expect(memory.values, hasLength(2));
        await first.remove(firstRecord.id);
        expect(await first.read(firstRecord.id), isNull);
        expect(
          (await second.read(secondRecord.id))!.edit.document.source,
          secondRecord.edit.document.source,
        );
        expect(memory.values, hasLength(1));
      },
    );
  });
}

ComplexNote _note({
  String scope = _scopeA,
  int id = 17,
  String collection = 'note',
  int version = 4,
  String title = 'Baseline',
  List<String> labels = const ['base'],
  ComplexEditorKind kind = ComplexEditorKind.drawing,
  String source = '{"elements":[],"future":1}',
  ComplexEditorDocument? document,
}) => ComplexNote(
  scope: scope,
  id: id,
  collection: collection,
  title: title,
  document: document ?? ComplexEditorDocument.parse(kind, source),
  version: version,
  labels: labels,
);

ComplexRecoveryRecord _record(ComplexNote note) =>
    ComplexRecoveryRecord.capture(
      note,
      ComplexNoteEdit(
        title: [note.title, 'draft'].join(' '),
        document: note.document,
        labels: [...note.labels, 'draft'],
      ),
      pending: true,
    );

ComplexRecoveryVault _vault(
  _MemoryStore store, {
  String scope = _scopeA,
  String collection = 'note',
  ComplexEditorKind kind = ComplexEditorKind.drawing,
}) => ComplexRecoveryVault(
  scope: scope,
  collection: collection,
  kind: kind,
  store: store,
);

Uint8List _envelope(List<int> metadata, List<int> body) {
  final header = ByteData(4)..setUint32(0, metadata.length, Endian.big);
  return (BytesBuilder(copy: false)
        ..add(header.buffer.asUint8List())
        ..add(metadata)
        ..add(body))
      .takeBytes();
}

class _MemoryStore implements ComplexRecoveryBytesStore {
  final values = <String, Uint8List>{};
  Completer<void>? writeEntered;
  Completer<void>? finishWrite;

  @override
  Future<Uint8List?> read(String key) async {
    final bytes = values[key];
    return bytes == null ? null : Uint8List.fromList(bytes);
  }

  @override
  Future<void> write(String key, Uint8List bytes) async {
    if (writeEntered != null && !writeEntered!.isCompleted) {
      writeEntered!.complete();
    }
    await finishWrite?.future;
    values[key] = Uint8List.fromList(bytes);
  }

  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }
}
