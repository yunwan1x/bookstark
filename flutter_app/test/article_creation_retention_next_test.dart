import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/draft_vault.dart';
import 'package:bookstark_flutter/core/notes_repository.dart';
import 'package:bookstark_flutter/core/owned_article_review_export.dart';
import 'package:bookstark_flutter/core/remote_markdown_creation_vault.dart';
import 'package:bookstark_flutter/features/notes/article_creation_retained_record.dart';

void main() {
  test(
    'legacy oversized source retains complete BOM/Unicode JSON with zero HTTP or mutation',
    () async {
      var requests = 0, flushes = 0;
      final client = BookstarkClient(
        'https://demo.example',
        transport: MockClient((_) async {
          requests++;
          throw StateError('No HTTP allowed');
        }),
      )..restoreSession({'token': 'fixture-token'});
      addTearDown(client.close);
      final values = <String, String>{};
      final draft = DraftVault(
        namespace: 'legacy-article',
        readValue: (key) async => values[key],
        writeValue: (key, value) async {
          values[key] = value;
        },
        deleteValue: (key) async {
          values.remove(key);
        },
      );
      final body = '\ufeff${'x' * (4 * 1024 * 1024)}😀\r\n';
      await draft.write(
        Note(title: 'Original', content: body, labels: const ['tag']),
      );
      final before = Map<String, String>.from(values),
          raw = await draft.readRecord(null);
      final retained = await inspectArticleCreationRetention(
        client: client,
        memberId: 7,
        namespace: 'account',
        isCurrent: () => true,
        readValue: (key) async => values[key],
        flush: () async {
          flushes++;
        },
        legacyDrafts: [draft],
      );
      expect(retained, isNotNull);
      expect(retained!.source, raw);
      expect(utf8.decode(retained.export.bytes, allowMalformed: false), raw);
      expect(jsonDecode(retained.source)['content'], body);
      await retained.verifyFresh();
      expect(values, before);
      expect(requests, 0);
      expect(flushes, 1);
      values[draft.metadataKey(null)] = 'changed';
      await expectLater(retained.verifyFresh(), throwsStateError);
      expect(requests, 0);
    },
  );
  test(
    'malformed existing creation record blocks without replacing its key',
    () async {
      var requests = 0;
      final client = BookstarkClient(
        'https://demo.example',
        transport: MockClient((_) async {
          requests++;
          throw StateError('No HTTP');
        }),
      )..restoreSession({'token': 'fixture-token'});
      addTearDown(client.close);
      final values = <String, String>{};
      final scope = MarkdownCreationScope(
        server: client.baseUri,
        memberId: 7,
        collection: 'article',
      );
      final vault = RemoteMarkdownCreationVault(
        scope: scope,
        readValue: (k) async => values[jsonEncode(['account', k])],
        writeValue: (k, v) async {
          values[jsonEncode(['account', k])] = v;
        },
        deleteValue: (k) async {
          values.remove(jsonEncode(['account', k]));
        },
        flush: () async {},
      );
      const raw = '{"version":1,"content":"incomplete';
      await vault.writeRecord('new', raw);
      final before = Map<String, String>.from(values);
      final retained = await inspectArticleCreationRetention(
        client: client,
        memberId: 7,
        namespace: 'account',
        isCurrent: () => true,
        readValue: (key) async => values[key],
        flush: () async {},
        legacyDrafts: const [],
      );
      expect(retained!.source, raw);
      expect(retained.reason, 'creation-record');
      expect(values, before);
      expect(requests, 0);
    },
  );
  test(
    'same-token same-cookie restore during flush rejects before record reads',
    () async {
      var requests = 0, reads = 0;
      final client = BookstarkClient(
        'https://demo.example',
        transport: MockClient((_) async {
          requests++;
          throw StateError('No HTTP');
        }),
      )..restoreSession({'token': 'fixture-token'});
      addTearDown(client.close);
      final entered = Completer<void>(), release = Completer<void>();
      final operation = inspectArticleCreationRetention(
        client: client,
        memberId: 7,
        namespace: 'account',
        isCurrent: () => true,
        readValue: (key) async {
          reads++;
          return null;
        },
        flush: () async {
          entered.complete();
          await release.future;
        },
        legacyDrafts: const [],
      );
      final assertion = expectLater(operation, throwsStateError);
      await entered.future;
      client.restoreSession(client.exportSession());
      release.complete();
      await assertion;
      expect(reads, 0);
      expect(requests, 0);
    },
  );
  test(
    'valid empty preflight leaves absence unchanged and performs no HTTP',
    () async {
      var requests = 0, flushes = 0;
      final client = BookstarkClient(
        'https://demo.example',
        transport: MockClient((_) async {
          requests++;
          throw StateError('No HTTP');
        }),
      )..restoreSession({'token': 'fixture-token'});
      addTearDown(client.close);
      final retained = await inspectArticleCreationRetention(
        client: client,
        memberId: 7,
        namespace: 'account',
        isCurrent: () => true,
        readValue: (_) async => null,
        flush: () async {
          flushes++;
        },
        legacyDrafts: const [],
      );
      expect(retained, isNull);
      expect(flushes, 1);
      expect(requests, 0);
    },
  );
  test(
    'exact exported bytes preserve BOM and cannot be mutated by a caller',
    () {
      const source = '\ufeff# 雪😀\r\n';
      final record = OwnedArticleReviewExport(
        source: source,
        mime: 'text/markdown',
        name: 'draft.md',
      );
      expect(record.bytes, utf8.encode(source));
      expect(() => record.bytes[0] = 0, throwsUnsupportedError);
      expect(record.bytes, utf8.encode(source));
    },
  );
}
