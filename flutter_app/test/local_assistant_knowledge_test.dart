import 'package:bookstark_flutter/core/local_assistant_draft_ledger.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/local_assistant_repository.dart';
import 'package:bookstark_flutter/core/local_model_config.dart';
import 'package:bookstark_flutter/core/local_model_stream.dart';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:bookstark_flutter/core/local_assistant_knowledge.dart';
import 'package:bookstark_flutter/core/local_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/open.dart';

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
  late Directory directory;
  late LocalStore store;
  late LocalAssistantKnowledge knowledge;
  var permitted = true, current = true;
  late int note, article, protected, book, document, topic;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('bookstark-ai-read-');
    store = LocalStore(
      path: '${directory.path}/local.db',
      factory: databaseFactoryFfiNoIsolate,
    );
    permitted = current = true;
    knowledge = LocalAssistantKnowledge(
      store,
      permitted: () => permitted,
      isCurrent: () => current,
    );
    note = await store.createNote('needle note', 'literal 100%_ and 中文内容');
    article = await store.createNote(
      'needle article',
      '<p>original</p>',
      collection: 'article',
    );
    protected = await store.createNote(
      'needle protected',
      'ENC:v1:never-forward-this',
    );
    final db = await store.database;
    book = await db.insert('books', {
      'book_name': 'needle book',
      'identify': 'b',
      'create_time': 'now',
      'modify_time': 'now',
    });
    document = await db.insert('documents', {
      'book_id': book,
      'document_name': 'needle document',
      'identify': 'd',
      'markdown': 'document body',
      'create_time': 'now',
      'modify_time': 'now',
    });
    topic = await db.insert('topics', {
      'title': 'needle topic',
      'question': 'question',
      'create_time': 'now',
      'modify_time': 'now',
    });
    await db.insert('topic_summaries', {
      'topic_id': topic,
      'content': 'summary',
      'create_time': 'now',
      'modify_time': 'now',
    });
    for (final id in [note, article, 999999]) {
      await db.insert('topic_resources', {
        'topic_id': topic,
        'resource_type': 'blog',
        'target_id': id,
        'title_snapshot': 'stale private snapshot',
        'create_time': 'now',
      });
    }
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });
  Future<String> state() async {
    final db = await store.database;
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name",
    );
    return jsonEncode({
      for (final table in tables)
        table['name'] as String: await db.query(table['name'] as String),
    });
  }

  Matcher issue(LocalKnowledgeIssue issue) =>
      isA<LocalKnowledgeFailure>().having((e) => e.issue, 'issue', issue);
  test(
    'all search/read operations leave every original table unchanged',
    () async {
      final before = await state();
      final found = await knowledge.search('needle', limit: 20);
      expect(found.results.length, 6);
      expect(
        found.results.firstWhere(
          (r) => r['id'] == protected && r['kind'] == 'note',
        )['snippet'],
        '',
      );
      for (final ref in found.results.where((r) => r['protected'] != true)) {
        await knowledge.readSource(ref);
      }
      expect(await state(), before);
    },
  );
  test('permission and retired owner reject search and model reads', () async {
    permitted = false;
    await expectLater(
      knowledge.search('needle'),
      throwsA(issue(LocalKnowledgeIssue.permission)),
    );
    await expectLater(
      knowledge.readSource({'kind': 'note', 'id': note}),
      throwsA(issue(LocalKnowledgeIssue.permission)),
    );
    expect(
      (await knowledge.readSource({
        'kind': 'note',
        'id': note,
      }, forModel: false)).title,
      'needle note',
    );
    current = false;
    await expectLater(
      knowledge.readSource({'kind': 'note', 'id': note}, forModel: false),
      throwsA(issue(LocalKnowledgeIssue.retired)),
    );
  });
  test('protected bodies cannot be searched or returned', () async {
    expect((await knowledge.search('never-forward')).results, isEmpty);
    await expectLater(
      knowledge.readSource({'kind': 'note', 'id': protected}),
      throwsA(issue(LocalKnowledgeIssue.protected)),
    );
  });
  test('wildcards are literal and article IDs require correct kind', () async {
    expect((await knowledge.search('100%_')).results.single['id'], note);
    await expectLater(
      knowledge.readSource({'kind': 'note', 'id': article}),
      throwsA(issue(LocalKnowledgeIssue.notFound)),
    );
  });
  test(
    'deleted parent hides documents and live topic links ignore stale snapshots',
    () async {
      final db = await store.database;
      await db.update(
        'books',
        {'deleted': 1},
        where: 'book_id=?',
        whereArgs: [book],
      );
      await db.update(
        'notes',
        {'deleted': 1},
        where: 'id=?',
        whereArgs: [article],
      );
      expect(
        (await knowledge.search('needle', kind: 'document')).results,
        isEmpty,
      );
      await expectLater(
        knowledge.readSource({'kind': 'document', 'id': document}),
        throwsA(issue(LocalKnowledgeIssue.notFound)),
      );
      final detail = await knowledge.readSource({'kind': 'topic', 'id': topic});
      expect(detail.content, 'question\n\nsummary');
      expect(detail.metadata['resource_references'], [
        {
          'kind': 'note',
          'id': note,
          'title': 'needle note',
          'format': 'markdown',
        },
      ]);
      expect(jsonEncode(detail.metadata), isNot(contains('stale')));
    },
  );
  test(
    'large multibyte bodies are bounded at valid UTF8 without any write',
    () async {
      final body = List.filled(10000, '😀中').join();
      final db = await store.database;
      await db.update(
        'notes',
        {'content': body},
        where: 'id=?',
        whereArgs: [note],
      );
      final before = await state();
      final detail = await knowledge.readSource({'kind': 'note', 'id': note});
      expect(utf8.encode(detail.content).length, lessThanOrEqualTo(24000));
      expect(body.startsWith(detail.content), isTrue);
      expect(detail.metadata['truncated'], isTrue);
      expect(await state(), before);
    },
  );
  test('UTF8 BOM source bytes survive read without false truncation', () async {
    final db = await store.database;
    for (final content in ['\ufeffliteral body', '\ufeff', '\ufeff\ufeff中文']) {
      await db.update(
        'notes',
        {'content': content},
        where: 'id=?',
        whereArgs: [note],
      );
      final detail = await knowledge.readSource({'kind': 'note', 'id': note});
      expect(detail.content, content);
      expect(detail.metadata['body_bytes'], utf8.encode(content).length);
      expect(detail.metadata['truncated'], isFalse);
    }
  });
  test('bookmark metadata strips credentials query and fragments', () async {
    final db = await store.database;
    final id = await db.insert('bookmarks', {
      'title': 'link',
      'url': 'https://user:private@example.invalid/path?token=secret#fragment',
      'create_time': 1,
      'modify_time': 1,
    });
    final detail = await knowledge.readSource({'kind': 'bookmark', 'id': id});
    expect(detail.metadata['url'], 'https://example.invalid/path');
    expect(detail.metadata['url_redacted'], isTrue);
    expect(jsonEncode(detail.metadata), isNot(contains('secret')));
  });
  const session = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  String sse(Map<String, Object?> delta, String finish) =>
      'data: ${jsonEncode({
        'choices': [
          {'index': 0, 'delta': delta, 'finish_reason': finish},
        ],
      })}\n\ndata: [DONE]\n\n';
  LocalAssistantRepository assistant(
    MockClient client, {
    bool allow = true,
    LocalAssistantDraftLedger? ledger,
  }) => LocalAssistantRepository(
    sessionId: session,
    draftLedger: ledger,
    knowledge: knowledge,
    allowKnowledge: allow,
    transport: LocalModelStreamTransport(
      LocalModelConfig(
        endpoint: 'https://model.invalid/v1',
        model: 'test',
        allowKnowledge: allow,
      ),
      createClient: () => client,
    ),
  );
  test(
    'actual transport tool loop reads existing resource and returns cited Markdown',
    () async {
      final requests = <Map>[];
      final before = await state();
      final repo = assistant(
        MockClient((request) async {
          final data = jsonDecode(request.body) as Map;
          requests.add(data);
          if (requests.length == 1) {
            return http.Response(
              sse({
                'tool_calls': [
                  {
                    'index': 0,
                    'id': 'read1',
                    'type': 'function',
                    'function': {
                      'name': 'read_local',
                      'arguments': jsonEncode({'kind': 'note', 'id': note}),
                    },
                  },
                ],
              }, 'tool_calls'),
              200,
              headers: {'content-type': 'text/event-stream'},
            );
          }
          final messages = data['messages'] as List;
          final tool =
              jsonDecode((messages.last as Map)['content'] as String) as Map;
          expect(tool['content'], 'literal 100%_ and 中文内容');
          return http.Response(
            sse({'content': '## Answer\n中文 **reply**'}, 'stop'),
            200,
            headers: {'content-type': 'text/event-stream; charset=utf-8'},
          );
        }),
      );
      try {
        final updates = await repo
            .chat(session: session, message: 'read note', history: [])
            .toList();
        final done = updates.singleWhere((u) => u.type == 'done');
        expect(done.messages.last.content, '## Answer\n中文 **reply**');
        expect(done.messages.last.sources.single['id'], note);
        expect(requests.length, 2);
        expect(await state(), before);
      } finally {
        repo.close();
      }
    },
  );
  test(
    'disabled knowledge exposes no tools and starts no local reads',
    () async {
      permitted = false;
      final repo = assistant(
        MockClient((request) async {
          final data = jsonDecode(request.body) as Map;
          expect(data.containsKey('tools'), isFalse);
          return http.Response(
            sse({'content': 'General answer'}, 'stop'),
            200,
            headers: {'content-type': 'text/event-stream'},
          );
        }),
        allow: false,
      );
      try {
        expect(
          (await repo
                  .chat(session: session, message: 'hello', history: [])
                  .toList())
              .last
              .type,
          'done',
        );
      } finally {
        repo.close();
      }
    },
  );
  test(
    'missing stream terminal never produces a completed conversation',
    () async {
      final repo = assistant(
        MockClient(
          (request) async => http.Response(
            'data: ${jsonEncode({
              'choices': [
                {
                  'index': 0,
                  'delta': {'content': 'partial'},
                  'finish_reason': null,
                },
              ],
            })}\n\n',
            200,
            headers: {'content-type': 'text/event-stream'},
          ),
        ),
      );
      final types = <String>[];
      try {
        await expectLater(
          repo.chat(session: session, message: 'hello', history: []).map((u) {
            types.add(u.type);
            return u;
          }).drain<void>(),
          throwsA(isA<LocalModelStreamFailure>()),
        );
        expect(types, contains('delta'));
        expect(types, isNot(contains('done')));
      } finally {
        repo.close();
      }
    },
  );
  test(
    'real SSE proposal loop persists a pending draft without SQL or confirmation authority',
    () async {
      final encrypted = <String, String>{};
      final ledger = LocalAssistantDraftLedger(
        namespace: store.path,
        readValue: (key) async => encrypted[key],
        writeValue: (key, value) async {
          encrypted[key] = value;
        },
      );
      final before = await state();
      var calls = 0;
      final repo = assistant(
        MockClient((request) async {
          final data = jsonDecode(request.body) as Map;
          calls++;
          final tools = (data['tools'] as List)
              .map((tool) => (tool as Map)['function']['name'])
              .toSet();
          expect(tools, {'propose_note', 'propose_task'});
          if (calls == 1) {
            return http.Response(
              sse({
                'tool_calls': [
                  {
                    'index': 0,
                    'id': 'proposal1',
                    'type': 'function',
                    'function': {
                      'name': 'propose_note',
                      'arguments': jsonEncode({
                        'title': '阅读草稿',
                        'content': '# 待编辑',
                      }),
                    },
                  },
                ],
              }, 'tool_calls'),
              200,
              headers: {'content-type': 'text/event-stream; charset=utf-8'},
            );
          }
          final result =
              jsonDecode(
                    ((data['messages'] as List).last as Map)['content']
                        as String,
                  )
                  as Map;
          expect(result['saved'], false);
          expect(result['status'], 'pending');
          expect(result.containsKey('resource_id'), false);
          return http.Response(
            sse({'content': '草稿已准备，请在编辑器保存。'}, 'stop'),
            200,
            headers: {'content-type': 'text/event-stream; charset=utf-8'},
          );
        }),
        allow: false,
        ledger: ledger,
      );
      try {
        final updates = await repo
            .chat(session: session, message: '请创建笔记', history: [])
            .toList();
        final draft = updates
            .singleWhere((value) => value.type == 'done')
            .drafts
            .single;
        expect(draft.status, 'pending');
        expect(draft.url, isEmpty);
        await expectLater(
          repo.resolve(session, draft.id, confirm: true),
          throwsFormatException,
        );
        expect(await state(), before);
        expect((await repo.open()).drafts.single.id, draft.id);
        expect(
          (await repo.resolve(session, draft.id, confirm: false)).status,
          'cancelled',
        );
        expect(await state(), before);
        expect(calls, 2);
      } finally {
        repo.close();
      }
    },
  );
  test(
    'all reserved envelope versions and BOM are excluded from model body reads and search snippets',
    () async {
      final ids = <int>[];
      for (final content in [
        'ENC:v1:payload',
        'ENC:v2:payload',
        'ENC:unknown:payload',
        '﻿ENC:v2:payload',
      ]) {
        ids.add(await store.createNote('Envelope ${ids.length}', content));
      }
      final before = await state();
      expect(
        (await knowledge.search('payload', kind: 'note')).results,
        isEmpty,
      );
      final metadata = (await knowledge.search(
        'Envelope',
        kind: 'note',
      )).results;
      expect(metadata.length, ids.length);
      expect(
        metadata.every(
          (row) => row['protected'] == true && row['snippet'] == '',
        ),
        true,
      );
      for (final id in ids) {
        await expectLater(
          knowledge.readSource({'kind': 'note', 'id': id}),
          throwsA(issue(LocalKnowledgeIssue.protected)),
        );
      }
      expect(await state(), before);
    },
  );
  test(
    'secondary topic summary envelopes are not exposed through a plain parent',
    () async {
      final db = await store.database;
      await db.update(
        'topic_summaries',
        {'content': '﻿ENC:v2:private'},
        where: 'topic_id=?',
        whereArgs: [topic],
      );
      final before = await state();
      await expectLater(
        knowledge.readSource({'kind': 'topic', 'id': topic}),
        throwsA(issue(LocalKnowledgeIssue.protected)),
      );
      expect(await state(), before);
    },
  );
}
