import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/document_creation.dart';
import 'package:bookstark_flutter/core/documents_repository.dart';
import '../tool/fixtures/books.dart';

class CreationDocuments extends DocumentsFixture {
  int creates = 0;
  Object? failure;
  @override
  Future<DocumentItem> create(
    int bookId,
    String name, {
    int parentId = 0,
  }) async {
    creates++;
    if (failure != null) throw failure!;
    return super.create(bookId, name, parentId: parentId);
  }
}

void main() {
  test(
    'unknown POST persists across restart and cannot create again or silently clear',
    () async {
      final values = <String, String>{};
      final docs = CreationDocuments()
        ..failure = TimeoutException('connection lost');
      DocumentCreationController controller() => DocumentCreationController(
        books: BooksFixture(),
        documents: docs,
        vault: DocumentCreationVault(
          namespace: 'server/member',
          readValue: (key) async => values[key],
          writeValue: (key, value) async {
            values[key] = value;
          },
          deleteValue: (key) async {
            values.remove(key);
          },
        ),
      );
      final first = controller();
      await first.initialize(
        initial: DocumentCreationDraft(bookId: 1, parentId: 1, name: ' 原名📚 '),
      );
      await expectLater(first.create(), throwsA(isA<TimeoutException>()));
      expect(docs.creates, 1);
      expect(first.draft?.phase, DocumentCreationPhase.unknown);
      final restored = controller();
      await restored.initialize();
      expect(restored.draft?.name, ' 原名📚 ');
      await expectLater(restored.create(), throwsStateError);
      await expectLater(restored.clear(), throwsStateError);
      expect(docs.creates, 1);
      expect(values, isNotEmpty);
    },
  );
  test(
    'secure intent write failure prevents POST and invalid name fails before persistence',
    () async {
      final docs = CreationDocuments();
      var writes = 0;
      final controller = DocumentCreationController(
        books: BooksFixture(),
        documents: docs,
        vault: DocumentCreationVault(
          namespace: 'local',
          readValue: (_) async => null,
          writeValue: (_, value) async {
            writes++;
            throw StateError('secure store unavailable');
          },
          deleteValue: (_) async {},
        ),
      );
      await controller.initialize(
        initial: DocumentCreationDraft(bookId: 1, parentId: 0, name: 'Valid'),
      );
      await expectLater(controller.create(), throwsStateError);
      expect(docs.creates, 0);
      expect(writes, 1);
      final invalid = DocumentCreationController(
        books: BooksFixture(),
        documents: docs,
        vault: controller.vault,
      );
      await invalid.initialize(
        initial: DocumentCreationDraft(bookId: 1, parentId: 0, name: ' '),
      );
      await expectLater(invalid.create(), throwsFormatException);
      expect(writes, 1);
      expect(docs.creates, 0);
    },
  );
  test(
    'acknowledged ID survives local receipt write failure without another POST',
    () async {
      final values = <String, String>{};
      final docs = CreationDocuments();
      var failReceipt = true;
      final vault = DocumentCreationVault(
        namespace: 'server/member',
        readValue: (key) async => values[key],
        writeValue: (key, value) async {
          if (DocumentCreationDraft.decode(value).phase ==
                  DocumentCreationPhase.acknowledged &&
              failReceipt) {
            throw StateError('receipt storage failed');
          }
          values[key] = value;
        },
        deleteValue: (key) async {
          values.remove(key);
        },
      );
      final controller = DocumentCreationController(
        books: BooksFixture(),
        documents: docs,
        vault: vault,
      );
      await controller.initialize(
        initial: DocumentCreationDraft(
          bookId: 1,
          parentId: 1,
          name: 'Actual name',
        ),
      );
      final actual = await controller.create();
      expect(controller.acknowledged.id, actual.id);
      expect(controller.storageError, isNotNull);
      await expectLater(controller.create(), throwsStateError);
      expect(docs.creates, 1);
      failReceipt = false;
      await controller.persistAcknowledged();
      final restored = DocumentCreationController(
        books: BooksFixture(),
        documents: docs,
        vault: vault,
      );
      await restored.initialize();
      expect(restored.acknowledged.id, actual.id);
      expect(restored.acknowledged.parentId, 1);
      expect(docs.creates, 1);
    },
  );
  test(
    'interrupted submitting record is unknown; explicit rejection allows deliberate corrected retry',
    () async {
      String? value = DocumentCreationDraft(
        bookId: 1,
        parentId: 0,
        name: 'Pending',
        phase: DocumentCreationPhase.submitting,
      ).encode();
      final docs = CreationDocuments()
        ..failure = const ApiFailure(403, 'denied');
      final vault = DocumentCreationVault(
        namespace: 'account',
        readValue: (_) async => value,
        writeValue: (_, text) async {
          value = text;
        },
        deleteValue: (_) async {
          value = null;
        },
      );
      final interrupted = DocumentCreationController(
        books: BooksFixture(),
        documents: docs,
        vault: vault,
      );
      await interrupted.initialize();
      expect(interrupted.draft?.phase, DocumentCreationPhase.unknown);
      await expectLater(interrupted.create(), throwsStateError);
      expect(docs.creates, 0);
      await interrupted.clear(explicitlyAbandonUnknown: true);
      await interrupted.edit(
        DocumentCreationDraft(bookId: 1, parentId: 0, name: 'Corrected'),
      );
      await expectLater(interrupted.create(), throwsA(isA<ApiFailure>()));
      expect(interrupted.draft?.phase, DocumentCreationPhase.editing);
      docs.failure = null;
      await interrupted.create();
      expect(docs.creates, 2);
    },
  );
}
