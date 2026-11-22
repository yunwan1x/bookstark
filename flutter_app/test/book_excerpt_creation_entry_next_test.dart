import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/document_excerpt_origin.dart';
import 'package:bookstark_flutter/core/document_excerpt_request.dart';
import 'package:bookstark_flutter/core/documents_repository.dart';
import 'package:bookstark_flutter/core/notes_repository.dart';
import 'package:bookstark_flutter/core/draft_vault.dart';
import 'package:bookstark_flutter/core/remote_markdown_creation_vault.dart';
import 'package:bookstark_flutter/features/notes/remote_markdown_creation_factory.dart';
import 'package:bookstark_flutter/features/notes/remote_markdown_creation_editor_page.dart';
import 'package:bookstark_flutter/features/notes/remote_markdown_creation_review_page.dart';
import 'package:bookstark_flutter/features/books/remote_book_excerpt_entry.dart';

class NoLegacyCreates implements NotesRepository {
  int creates = 0;
  @override
  Future<int> save(Note n) async {
    if (n.id == null) creates++;
    throw StateError('No legacy create permitted');
  }

  @override
  Future<Note> read(int id) async =>
      throw StateError('Unexpected existing read');
  @override
  Future<void> remove(int id) async => throw StateError('Unexpected delete');
  @override
  Future<List<Note>> list({String keyword = '', int page = 1}) async => [];
}

class Env {
  final values = <String, String>{};
  int requests = 0, posts = 0, flushes = 0;
  bool current = true, dropPost = false;
  late final client = BookstarkClient(
    'https://book.example/prefix',
    transport: MockClient((request) async {
      requests++;
      if (dropPost &&
          request.method == 'GET' &&
          request.url.path.endsWith('/api/profile')) {
        return http.Response(
          jsonEncode({
            'code': 0,
            'data': {'member_id': 7},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (dropPost &&
          request.method == 'POST' &&
          request.url.path.endsWith('/api/blogs')) {
        posts++;
        throw StateError('Dropped creation response');
      }
      throw StateError('Unexpected HTTP');
    }),
  )..restoreSession({'token': 'fixture-token', 'csrf_token': 'fixture-csrf'});
  final repository = NoLegacyCreates();
  DraftVault drafts(String ns) => DraftVault(
    namespace: ns,
    readValue: (k) async => values[k],
    writeValue: (k, v) async {
      values[k] = v;
    },
    deleteValue: (k) async {
      values.remove(k);
    },
  );
  Future<void> flush() async {
    flushes++;
  }

  DocumentExcerptRequest request({
    String quote = 'Selected **plain** <b>',
    Future<bool> Function()? verify,
  }) => DocumentExcerptRequest.snapshot(
    bookId: 4,
    item: const DocumentItem(
      id: 9,
      bookId: 4,
      name: 'Owned chapter',
      markdown: '# Original',
      modifiedAt: 'source-v1',
    ),
    source: '# Original',
    selected: quote,
    path: 'Book / Chapter',
    bookIdentify: 'book',
    server: client.baseUri,
    isCurrentSource: () => current,
    verifyCurrentSource: verify ?? () async => current,
    english: true,
  );
  Future<RemoteMarkdownCreationEditorPage> openFactory(
    DocumentExcerptRequest request,
  ) => createRemoteMarkdownCreationEditor(
    client: client,
    memberId: 7,
    namespace: 'account-space',
    collection: NoteCollection.note,
    repository: repository,
    initial: MarkdownCreationInput(
      title: request.note.title,
      content: request.note.content,
      labels: request.note.labels,
    ),
    initialExcerptOrigin: request.origin,
    drafts: drafts('account-space'),
    readValue: (k) async => values[k],
    writeValue: (k, v) async {
      values[k] = v;
    },
    deleteValue: (k) async {
      values.remove(k);
    },
    flush: flush,
    isCurrent: () => current,
    english: true,
  );
  Future<void> entry(BuildContext c, DocumentExcerptRequest request) =>
      openRemoteBookExcerpt(
        c,
        client: client,
        memberId: 7,
        namespace: 'account-space',
        request: request,
        repository: repository,
        drafts: drafts('account-space'),
        additionalLegacyDrafts: [drafts('excerpt-old')],
        readValue: (k) async => values[k],
        writeValue: (k, v) async {
          values[k] = v;
        },
        deleteValue: (k) async {
          values.remove(k);
        },
        flush: flush,
        isCurrent: () => current,
        english: true,
      );
}

void main() {
  test(
    'origin cold roundtrip preserves exact selected/source identity; legacy omits field',
    () async {
      final e = Env();
      addTearDown(e.client.close);
      final request = e.request();
      final page = await e.openFactory(request);
      await page.controller.edit(page.controller.record.input);
      final record = page.controller.record;
      final parsed = MarkdownCreationRecord.parse(
        record.toJson(),
        record.scope,
      );
      expect(parsed.excerptOrigin!.same(request.origin), true);
      expect(
        parsed.excerptOrigin!.selectionDigest,
        DocumentExcerptOrigin.digest('Selected **plain** <b>'),
      );
      expect(parsed.input.content, contains(r'\<b\>'));
      final known = parsed.copy(
        pending: true,
        knownId: 99,
        knownIDOrigin: MarkdownKnownIDOrigin.postReceipt,
      );
      expect(known.excerptOrigin!.same(request.origin), true);
      final legacy = {...record.toJson()}
        ..remove('excerpt_origin')
        ..remove('known_id_origin');
      expect(
        MarkdownCreationRecord.parse(legacy, record.scope).excerptOrigin,
        isNull,
      );
      page.controller.retire();
      expect(e.requests, 0);
      expect(e.repository.creates, 0);
    },
  );
  test(
    'fresh initial excerpt cannot replace retained different creation or its origin',
    () async {
      final e = Env();
      addTearDown(e.client.close);
      final first = e.request(quote: 'first');
      var page = await e.openFactory(first);
      await page.controller.edit(page.controller.record.input);
      final key = page.controller.record.key;
      page.controller.retire();
      final second = e.request(quote: 'second');
      page = await e.openFactory(second);
      expect(page.controller.record.key, key);
      expect(page.controller.record.excerptOrigin!.same(first.origin), true);
      expect(page.controller.record.input.content, contains('first'));
      expect(page.controller.record.input.content, isNot(contains('second')));
      page.controller.retire();
      expect(e.requests, 0);
      expect(e.repository.creates, 0);
    },
  );
  test(
    'unrelated normal/excerpt legacy drafts fail closed; both remain and zero HTTP',
    () async {
      final e = Env();
      addTearDown(e.client.close);
      final normal = e.drafts('account-space'),
          excerpt = e.drafts('excerpt-old');
      await normal.write(
        const Note(title: 'normal', content: 'retained normal'),
      );
      await excerpt.write(
        const Note(title: 'excerpt', content: 'retained excerpt'),
      );
      final request = e.request();
      await expectLater(
        createRemoteMarkdownCreationEditor(
          client: e.client,
          memberId: 7,
          namespace: 'account-space',
          collection: NoteCollection.note,
          repository: e.repository,
          initial: MarkdownCreationInput(
            title: request.note.title,
            content: request.note.content,
            labels: [],
          ),
          initialExcerptOrigin: request.origin,
          drafts: normal,
          additionalLegacyDrafts: [excerpt],
          readValue: (k) async => e.values[k],
          writeValue: (k, v) async {
            e.values[k] = v;
          },
          deleteValue: (k) async {
            e.values.remove(k);
          },
          flush: e.flush,
          isCurrent: () => true,
        ),
        throwsStateError,
      );
      expect((await normal.read(null))!.content, 'retained normal');
      expect((await excerpt.read(null))!.content, 'retained excerpt');
      expect(e.requests, 0);
      expect(e.repository.creates, 0);
    },
  );
  testWidgets(
    'actual pending excerpt opens08 review; opening never sends legacy or HTTP create',
    (tester) async {
      final e = Env();
      addTearDown(e.client.close);
      final request = e.request();
      final page = await e.openFactory(request);
      await page.controller.edit(page.controller.record.input);
      final saved = page.controller.record;
      await page.controller.vault.compareAndWrite(
        saved,
        saved.copy(pending: true),
        guard: () {},
      );
      page.controller.retire();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => e.entry(context, request),
                child: const Text('Excerpt'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Excerpt'));
      await tester.pumpAndSettle();
      expect(find.byType(RemoteMarkdownCreationReviewPage), findsOneWidget);
      expect(e.requests, 0);
      expect(e.repository.creates, 0);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );
  testWidgets(
    'retained different excerpt Back keeps old record and sends zero create',
    (tester) async {
      final e = Env();
      addTearDown(e.client.close);
      var page = await e.openFactory(e.request(quote: 'first'));
      await page.controller.edit(page.controller.record.input);
      final before = Map<String, String>.from(e.values);
      page.controller.retire();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => e.entry(context, e.request(quote: 'second')),
                child: const Text('Excerpt'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Excerpt'));
      await tester.pumpAndSettle();
      expect(find.text('Retained note draft'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Back'));
      await tester.pumpAndSettle();
      expect(e.values, before);
      expect(e.requests, 0);
      expect(e.repository.creates, 0);
    },
  );
  testWidgets(
    'owner retired during fresh-source check does not open or write new excerpt',
    (tester) async {
      final e = Env();
      addTearDown(e.client.close);
      final gate = Completer<bool>();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () =>
                    e.entry(context, e.request(verify: () => gate.future)),
                child: const Text('Excerpt'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Excerpt'));
      await tester.pump();
      e.current = false;
      gate.complete(true);
      await tester.pumpAndSettle();
      expect(find.byType(RemoteMarkdownCreationReviewPage), findsNothing);
      expect(e.values, isEmpty);
      expect(e.requests, 0);
      expect(e.repository.creates, 0);
    },
  );
  testWidgets(
    'real excerpt Restore+Save drops one POST then cold reopens unknown with no replay',
    (tester) async {
      final e = Env()..dropPost = true;
      addTearDown(e.client.close);
      final request = e.request();
      Future<void> mount() async {
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => e.entry(context, request),
                  child: const Text('Excerpt'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await mount();
      await tester.tap(find.text('Excerpt'));
      await tester.pumpAndSettle();
      expect(find.text('Restore draft'), findsOneWidget);
      await tester.tap(find.text('Restore draft'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(e.posts, 1);
      expect(e.repository.creates, 0);
      expect(find.byType(RemoteMarkdownCreationReviewPage), findsOneWidget);
      final afterFailure = Map<String, String>.from(e.values);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Excerpt'));
      await tester.pumpAndSettle();
      expect(find.byType(RemoteMarkdownCreationReviewPage), findsOneWidget);
      expect(e.posts, 1);
      expect(e.repository.creates, 0);
      expect(e.values, afterFailure);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  test(
    'two matching legacy drafts cleanup retries storage only after partial failure',
    () async {
      final e = Env();
      addTearDown(e.client.close);
      final request = e.request();
      final first = e.drafts('account-space');
      await first.write(request.note);
      var fail = true;
      final second = DraftVault(
        namespace: 'excerpt-old',
        readValue: (k) async => e.values[k],
        writeValue: (k, v) async {
          e.values[k] = v;
        },
        deleteValue: (k) async {
          if (fail) throw StateError('Storage unavailable');
          e.values.remove(k);
        },
      );
      await second.write(request.note);
      final page = await createRemoteMarkdownCreationEditor(
        client: e.client,
        memberId: 7,
        namespace: 'account-space',
        collection: NoteCollection.note,
        repository: e.repository,
        initial: MarkdownCreationInput(
          title: request.note.title,
          content: request.note.content,
          labels: [],
        ),
        initialExcerptOrigin: request.origin,
        drafts: first,
        additionalLegacyDrafts: [second],
        readValue: (k) async => e.values[k],
        writeValue: (k, v) async {
          e.values[k] = v;
        },
        deleteValue: (k) async {
          e.values.remove(k);
        },
        flush: e.flush,
        isCurrent: () => true,
      );
      // The actual page invokes this only from its verified known-ID gate; here
      // isolate the additional legacy storage cleanup's partial failure contract.
      await expectLater(page.beforeOpenSaved!(), throwsStateError);
      expect(await first.read(null), isNull);
      expect(await second.read(null), isNotNull);
      fail = false;
      await page.beforeOpenSaved!();
      expect(await second.read(null), isNull);
      expect(e.posts, 0);
      expect(e.repository.creates, 0);
      expect(
        page.controller.record.pending,
        true,
      ); // never reset a pending POST record.
      page.controller.retire();
    },
  );
}
