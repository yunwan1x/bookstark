// NOT RUN; guards exact legacy wire bytes when shared changes are integrated.
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/local_complex_notes_repository.dart';
import 'package:bookstark_flutter/core/complex_recovery_vault.dart';

void main() {
  for (final collection in ['note', 'article']) {
    test(
      'null resource fingerprint preserves legacy $collection fingerprint and exact record bytes',
      () {
        final baseline = ComplexNote(
          scope: 'a' * 64,
          id: 71,
          collection: collection,
          title: 'old title',
          document: ComplexEditorDocument.parse(
            ComplexEditorKind.html,
            '<p>old</p>',
          ),
          version: 7,
          labels: ['x', 'y'],
        );
        final edit = ComplexNoteEdit(
          title: 'new title',
          document: ComplexEditorDocument.parse(
            ComplexEditorKind.html,
            '\ufeff<p>😀</p>\r\n',
          ),
          labels: ['keep'],
        );
        final oldFingerprint = sha256
            .convert(
              utf8.encode(
                jsonEncode([
                  baseline.scope,
                  baseline.id,
                  baseline.collection,
                  baseline.document.kind.name,
                  baseline.version,
                  baseline.title,
                  baseline.labels,
                  baseline.document.digest,
                ]),
              ),
            )
            .toString();
        expect(complexNoteFingerprint(baseline), oldFingerprint);
        final metadata = utf8.encode(
          jsonEncode({
            'version': 1,
            'scope': baseline.scope,
            'id': 71,
            'collection': collection,
            'kind': 'html',
            'baseline': oldFingerprint,
            'baselineVersion': 7,
            'pending': true,
            'title': edit.title,
            'labels': edit.labels,
            'sourceBytes': edit.document.byteLength,
            'sourceSHA256': edit.document.digest,
          }),
        );
        final header = ByteData(4)..setUint32(0, metadata.length, Endian.big);
        final oldBytes =
            (BytesBuilder(copy: false)
                  ..add(header.buffer.asUint8List())
                  ..add(metadata)
                  ..add(utf8.encode(edit.document.source)))
                .takeBytes();
        final record = ComplexRecoveryRecord.capture(
          baseline,
          edit,
          pending: true,
        );
        expect(record.encode(), oldBytes);
        expect(
          ComplexRecoveryRecord.decode(oldBytes).baselineMatches(baseline),
          true,
        );
      },
    );
  }
  test(
    'book-document full fingerprint survives cold record and detects metadata-only identity drift',
    () {
      ComplexNote note(String resource) => ComplexNote(
        scope: 'b' * 64,
        id: 71,
        collection: 'book-document',
        title: 'title',
        document: ComplexEditorDocument.parse(
          ComplexEditorKind.html,
          '<p>unchanged</p>',
        ),
        version: 0,
        labels: [],
        resourceFingerprint: resource,
      );
      final before = note('c' * 64), after = note('d' * 64);
      final edit = ComplexNoteEdit(
        title: before.title,
        document: ComplexEditorDocument.parse(
          ComplexEditorKind.html,
          '<p>draft</p>',
        ),
        labels: [],
      );
      final cold = ComplexRecoveryRecord.decode(
        ComplexRecoveryRecord.capture(before, edit, pending: false).encode(),
      );
      expect(cold.baselineMatches(before), true);
      expect(cold.baselineMatches(after), false);
      expect(cold.owns(after), true);
      expect(cold.baselineResourceFingerprint, 'c' * 64);
    },
  );
  test(
    'book-document cannot create Markdown recovery or omit full resource identity',
    () {
      final baseline = ComplexNote(
        scope: 'b' * 64,
        id: 71,
        collection: 'book-document',
        title: 'title',
        document: ComplexEditorDocument.parse(
          ComplexEditorKind.html,
          '<p>old</p>',
        ),
        version: 0,
        labels: [],
      );
      final edit = ComplexNoteEdit(
        title: 'title',
        document: baseline.document,
        labels: [],
      );
      expect(
        () => ComplexRecoveryRecord.capture(baseline, edit, pending: false),
        throwsFormatException,
      );
      final markdown = ComplexNote(
        scope: 'b' * 64,
        id: 71,
        collection: 'book-document',
        title: 'title',
        document: ComplexEditorDocument.parse(
          ComplexEditorKind.markdown,
          '# old',
        ),
        version: 0,
        labels: [],
        resourceFingerprint: 'c' * 64,
      );
      expect(
        () => ComplexRecoveryRecord.capture(
          markdown,
          ComplexNoteEdit(
            title: 'title',
            document: markdown.document,
            labels: [],
          ),
          pending: false,
        ),
        throwsFormatException,
      );
    },
  );
}
