import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/notes_repository.dart';
import 'package:bookstark_flutter/features/notes/notes_page.dart';

class _Remote extends RemoteNotesRepository {
  _Remote(this.kind, {this.actualId = 47, super.collection})
    : super(
        BookstarkClient(
          'https://fixture.invalid',
          transport: MockClient((_) async => http.Response('', 500)),
        ),
      );
  final String kind;
  final int actualId;
  int reads = 0;
  Completer<void>? delay;
  @override
  Future<Note> read(int id) async {
    reads++;
    if (delay != null) await delay!.future;
    throw DedicatedEditorRequired(actualId, kind);
  }
}

void main() {
  for (final kind in [
    'spreadsheet',
    'drawing',
    'mindmap',
    'richdoc',
    'presentation',
  ]) {
    testWidgets('actual owned $kind dispatch keeps identity', (tester) async {
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) {
              context = c;
              return const SizedBox();
            },
          ),
        ),
      );
      final repo = _Remote(kind);
      var calls = 0;
      final opened = await openNativeNoteEditor(
        context,
        repository: repo,
        id: 47,
        onOpenOwnedComplex:
            (
              c, {
              required id,
              required collection,
              required kind,
              required isCurrentScope,
            }) async {
              calls++;
              expect(id, 47);
              expect(collection, NoteCollection.note);
              expect(kind.name, repo.kind);
              expect(isCurrentScope(), isTrue);
              return true;
            },
      );
      expect(opened, isTrue);
      expect(calls, 1);
      expect(repo.reads, 1);
    });
  }
  testWidgets('retired before read and during await never opens engine', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );
    var current = false, calls = 0;
    final repo = _Remote('drawing');
    Future<bool> open() => openNativeNoteEditor(
      context,
      repository: repo,
      id: 47,
      isCurrentScope: () => current,
      onOpenOwnedComplex:
          (
            c, {
            required id,
            required collection,
            required kind,
            required isCurrentScope,
          }) async {
            calls++;
            return true;
          },
    );
    expect(await open(), isFalse);
    expect(repo.reads, 0);
    current = true;
    repo.delay = Completer<void>();
    final future = open();
    await tester.pump();
    expect(repo.reads, 1);
    current = false;
    repo.delay!.complete();
    expect(await future, isFalse);
    expect(calls, 0);
  });
  testWidgets(
    'wrong actual ID, article and missing callback cannot fake native note',
    (tester) async {
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) {
              context = c;
              return const SizedBox();
            },
          ),
        ),
      );
      var calls = 0;
      Future<bool> writer(
        BuildContext c, {
        required int id,
        required NoteCollection collection,
        required ComplexEditorKind kind,
        required bool Function() isCurrentScope,
      }) async {
        calls++;
        return true;
      }

      await expectLater(
        openNativeNoteEditor(
          context,
          repository: _Remote('drawing', actualId: 48),
          id: 47,
          onOpenOwnedComplex: writer,
        ),
        throwsA(isA<DedicatedEditorRequired>()),
      );
      await expectLater(
        openNativeNoteEditor(
          context,
          repository: _Remote('drawing', collection: NoteCollection.article),
          collection: NoteCollection.article,
          id: 47,
          onOpenOwnedComplex: writer,
        ),
        throwsA(isA<DedicatedEditorRequired>()),
      );
      await expectLater(
        openNativeNoteEditor(context, repository: _Remote('drawing'), id: 47),
        throwsA(isA<DedicatedEditorRequired>()),
      );
      expect(calls, 0);
    },
  );
}
