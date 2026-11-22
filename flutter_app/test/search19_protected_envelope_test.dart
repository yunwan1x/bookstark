import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:sqlite3/open.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:bookstark_flutter/core/local_store.dart';
import 'package:bookstark_flutter/core/local_search_repository.dart';
import 'package:bookstark_flutter/core/search_repository.dart';
import 'package:bookstark_flutter/core/local_protected_content.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    if (Platform.isLinux) {
      open.overrideFor(
        OperatingSystem.linux,
        () => DynamicLibrary.open('libsqlite3.so.0'),
      );
    }
  });
  for (final content in [
    'ENC:v1: CipherNeedle',
    'ENC:v2: CipherNeedle',
    'ENC:future: CipherNeedle',
    'ENC: CipherNeedle',
    '\ufeffENC:v1: CipherNeedle',
    '\ufeffENC:v2: CipherNeedle',
    '\ufeffENC:future: CipherNeedle',
    ' ENC:v2: CipherNeedle',
    'text ENC:v2: CipherNeedle',
    'enc:v2: CipherNeedle',
    '\ufeff\ufeffENC:v2: CipherNeedle',
  ]) {
    test('SQLite title/prose protocol exact ${jsonEncode(content)}', () async {
      final store = LocalStore(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfiNoIsolate,
      );
      try {
        final id = await store.createNote('Visible title', content);
        final db = await store.database;
        final book = await db.insert('books', {
          'book_name': 'Container',
          'identify': 'envelope-container',
          'create_time': '2026-11-11',
          'modify_time': '2026-11-11',
        });
        final document = await db.insert('documents', {
          'book_id': book,
          'document_name': 'DocVisible',
          'identify': 'envelope-document',
          'doc_type': 'markdown',
          'markdown': content,
          'create_time': '2026-11-11',
          'modify_time': '2026-11-11',
        });
        final docBefore = (await db.rawQuery(
          'SELECT CAST(markdown AS BLOB) AS body FROM documents WHERE document_id=?',
          [document],
        )).single['body'];
        final before = (await db.rawQuery(
          'SELECT id,CAST(title AS BLOB) AS title,CAST(content AS BLOB) AS body,labels,updated_at FROM notes WHERE id=?',
          [id],
        )).single;
        expect(before['body'], utf8.encode(content));
        final repo = LocalSearchRepository(store);
        final bodyHits = (await repo.search(
          'CipherNeedle',
        )).groups[SearchKind.blog]!;
        final protected = isLocalProtectedEnvelopePrefix(content);
        expect(bodyHits, hasLength(protected ? 0 : 1));
        if (!protected) {
          expect(bodyHits.single.snippet, contains('CipherNeedle'));
        }
        final docBody = (await repo.search(
          'CipherNeedle',
        )).groups[SearchKind.document]!;
        expect(docBody, hasLength(protected ? 0 : 1));
        final docTitle = (await repo.search(
          'DocVisible',
        )).groups[SearchKind.document]!;
        expect(docTitle, hasLength(1));
        if (protected) expect(docTitle.single.snippet, isEmpty);
        expect(
          (await db.rawQuery(
            'SELECT CAST(markdown AS BLOB) AS body FROM documents WHERE document_id=?',
            [document],
          )).single['body'],
          docBefore,
        );

        final titleHits = (await repo.search(
          'Visible',
        )).groups[SearchKind.blog]!;
        expect(titleHits, hasLength(1));
        if (protected) expect(titleHits.single.snippet, isEmpty);
        final after = (await db.rawQuery(
          'SELECT id,CAST(title AS BLOB) AS title,CAST(content AS BLOB) AS body,labels,updated_at FROM notes WHERE id=?',
          [id],
        )).single;
        expect(after, before);
      } finally {
        await store.close();
      }
    });
    test(
      'typed legacy remote snippets never render an actual protection envelope ${jsonEncode(content)}',
      () {
        final hit = SearchHit.fromJson(SearchKind.blog, {
          'id': 1,
          'title': 'Visible',
          'blog_type': 'note',
          'snippet': content,
        });
        expect(
          hit.snippet,
          isLocalProtectedEnvelopePrefix(content) ? '' : content,
        );
        final document = SearchHit.fromJson(SearchKind.document, {
          'id': 1,
          'name': 'Visible',
          'snippet': content,
        });
        expect(
          document.snippet,
          isLocalProtectedEnvelopePrefix(content) ? '' : content,
        );
      },
    );
  }
}
