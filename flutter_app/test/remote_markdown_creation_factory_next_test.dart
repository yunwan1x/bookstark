import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/notes_repository.dart';
import 'package:http/testing.dart';
import 'package:bookstark_flutter/features/notes/remote_markdown_creation_factory.dart';
import 'remote_markdown_creation_controller_next_test.dart' as fixture;
import 'remote_markdown_creation_editor_next_test.dart' show ExistingRepository;

void main() {
  test('article cannot enter the native Markdown creation factory', () async {
    var requests = 0, writes = 0;
    final client = BookstarkClient(
      'https://demo.example',
      transport: MockClient((_) async {
        requests++;
        throw StateError('Unexpected HTTP');
      }),
    );
    client.restoreSession({'token': 'fixture-token'});
    addTearDown(client.close);
    final f = fixture.Fixture();
    await expectLater(
      createRemoteMarkdownCreationEditor(
        client: client,
        memberId: 7,
        namespace: 'article-scope',
        collection: NoteCollection.article,
        repository: ExistingRepository(f),
        readValue: (_) async => null,
        writeValue: (_, _) async {
          writes++;
        },
        deleteValue: (_) async {},
        flush: () async {},
        isCurrent: () => true,
      ),
      throwsUnsupportedError,
    );
    expect(requests, 0);
    expect(writes, 0);
  });
  test(
    'factory opens offline with real API methods and mandatory durable empty barrier',
    () async {
      var requests = 0, flushes = 0;
      final client = BookstarkClient(
        'https://demo.example',
        transport: MockClient((_) async {
          requests++;
          throw StateError('Offline');
        }),
      );
      client.restoreSession({'token': 'fixture-token'});
      addTearDown(client.close);
      final f = fixture.Fixture();
      final page = await createRemoteMarkdownCreationEditor(
        client: client,
        memberId: 7,
        namespace: 'account-generation-1',
        collection: NoteCollection.note,
        repository: ExistingRepository(f),
        readValue: (k) async => f.values[k],
        writeValue: (k, v) async {
          f.values[k] = v;
        },
        deleteValue: (k) async {
          f.values.remove(k);
        },
        flush: () async {
          flushes++;
        },
        isCurrent: () => f.current,
      );
      addTearDown(page.controller.retire);
      expect(requests, 0);
      expect(flushes, 1);
      await page.controller.edit(f.input);
      expect(requests, 0);
      expect(flushes, 2);
      expect(f.values.keys.single, startsWith('["account-generation-1",'));
      expect(f.values.keys.single.contains('fixture-token'), isFalse);
      client.restoreSession(client.exportSession());
      expect(page.isCurrent(), isFalse);
      await expectLater(page.controller.save(), throwsStateError);
      expect(requests, 0);
    },
  );
  test(
    'failed absence durability barrier blocks opening and sends no HTTP',
    () async {
      var requests = 0;
      final client = BookstarkClient(
        'https://demo.example',
        transport: MockClient((_) async {
          requests++;
          throw StateError('Offline');
        }),
      );
      client.restoreSession({'token': 'fixture-token'});
      addTearDown(client.close);
      final f = fixture.Fixture();
      await expectLater(
        createRemoteMarkdownCreationEditor(
          client: client,
          memberId: 7,
          namespace: 'account-generation-2',
          collection: NoteCollection.note,
          repository: ExistingRepository(f),
          readValue: (_) async => null,
          writeValue: (_, _) async {},
          deleteValue: (_) async {},
          flush: () async => throw StateError('Native barrier failed'),
          isCurrent: () => true,
        ),
        throwsStateError,
      );
      expect(requests, 0);
    },
  );
}
