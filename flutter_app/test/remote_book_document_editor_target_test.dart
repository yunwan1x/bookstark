// NOT RUN. URL tests do not prove server-Web ready identity or CAS.
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/remote_book_document_editor_target.dart';

void main() {
  test(
    'actual Go editor uses book identify and doc query under fixed prefix',
    () {
      final target = VerifiedRemoteBookDocument(
        server: 'https://example.test/mount',
        bookId: 5,
        documentId: 81,
        bookIdentify: 'real-book',
        kind: ComplexEditorKind.richdoc,
        ownerBinding: 'scope-1',
        documentFingerprint: 'a' * 64,
      );
      expect(
        target.editorUri.toString(),
        'https://example.test/mount/books/real-book/edit?doc=81',
      );
      expect(target.editorUri.path, isNot(contains('blogs')));
    },
  );
  test(
    'no arbitrary URL, markdown or path injection becomes a complex edit target',
    () {
      for (final identify in ['../other', 'a/b', 'a%2fb', '?doc=7']) {
        expect(
          () => VerifiedRemoteBookDocument(
            server: 'https://example.test',
            bookId: 5,
            documentId: 81,
            bookIdentify: identify,
            kind: ComplexEditorKind.html,
            ownerBinding: 'scope-1',
            documentFingerprint: 'a' * 64,
          ),
          throwsFormatException,
        );
      }
    },
  );
}
