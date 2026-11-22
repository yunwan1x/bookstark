import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/document_editor_repository.dart';
import 'package:bookstark_flutter/core/documents_repository.dart';
import 'package:bookstark_flutter/core/notes_repository.dart';
import '../tool/fixtures/books.dart';

class _Docs extends DocumentsFixture implements BoundedDocumentsReader {
  int oldReads = 0, bodyWrites = 0, renames = 0;
  int? budget;
  void Function()? afterRename;
  @override
  Future<DocumentItem> read(int id) async {
    oldReads++;
    return super.read(id);
  }

  @override
  Future<TypedDocumentRead> readBounded(
    int id, {
    required int bookId,
    int maxMarkdownReadBytes = documentReadMaxBytes,
  }) async {
    budget = maxMarkdownReadBytes;
    final item = await super.read(id);
    return TypedDocumentRead(
      item: item,
      source: item.markdown,
      byteLength: item.markdown.length,
    );
  }

  @override
  Future<void> rename(int id, String name) async {
    renames++;
    await super.rename(id, name);
    afterRename?.call();
  }

  @override
  Future<void> saveMarkdown(int id, String text) async {
    bodyWrites++;
    await super.saveMarkdown(id, text);
  }
}

void main() {
  test(
    'real MD adapter asks bounded reader for edit budget, never old GET',
    () async {
      final docs = _Docs();
      final repo = DocumentEditorRepository(docs, 1, boundedReader: docs);
      final note = await repo.read(2);
      expect(note.id, 2);
      expect(docs.budget, documentMarkdownEditBytes);
      expect(docs.oldReads, 0);
    },
  );
  test(
    'scope retirement after title ACK prevents following body mutation',
    () async {
      var current = true;
      final docs = _Docs()
        ..afterRename = () {
          current = false;
        };
      final repo = DocumentEditorRepository(
        docs,
        1,
        boundedReader: docs,
        isCurrentScope: () => current,
      );
      final note = await repo.read(2);
      await expectLater(
        repo.save(
          note.copyWith(title: 'Explicit rename', content: 'Retained draft'),
        ),
        throwsA(isA<NoteSaveFailure>()),
      );
      expect(docs.renames, 1);
      expect(docs.bodyWrites, 0);
      expect(docs.oldReads, 0);
      expect(docs.records[2]!.markdown, DocumentsFixture.body);
    },
  );
}
