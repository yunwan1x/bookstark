import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/open.dart';
import 'package:bookstark_flutter/core/attachments.dart';
import 'package:bookstark_flutter/core/bounded_note_text_reader.dart';
import 'package:bookstark_flutter/core/local_data_paths.dart';
import 'package:bookstark_flutter/core/local_generation_content_repository.dart';
import 'package:bookstark_flutter/core/local_legacy_candidate_schema.dart';
import 'package:bookstark_flutter/core/native_local_content_crypto.dart';
import 'package:bookstark_flutter/core/owned_generation15_schema.dart';

class _CommitBoundaryDatabase implements Database {
  _CommitBoundaryDatabase(this.inner);
  final Database inner;
  void Function()? afterWriteCommit;
  @override
  String get path => inner.path;
  @override
  Future<T> transaction<T>(
    Future<T> Function(Transaction txn) action, {
    bool? exclusive,
  }) async {
    final result = await inner.transaction(action, exclusive: exclusive);
    if (exclusive != false) {
      afterWriteCommit?.call();
    }
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('bookstark/generation-content-unit');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Map<String, dynamic> vector;
  late Directory root;
  late LocalDataPaths generation;
  late Database db;
  late LocalGenerationContentRepository repo;
  late bool current;
  late List<String> methods;
  late Map<String, String> decrypted;
  Completer<void>? unlockStarted, unlockRelease;
  const fakeCipher =
      'ENC:v1:AAAAAAAAAAAAAAAAAAAAAA==:AAAAAAAAAAAAAAAA:AAAAAAAAAAAAAAAAAAAAAA==';
  const plain = '\ufeff# full public needle\r\n';
  Future<void> insert(
    int id,
    String title,
    String body, {
    String hash = '',
    String format = 'markdown',
    String collection = 'note',
  }) async {
    await db.rawInsert(
      'INSERT INTO notes (id,title,content,labels,updated_at,collection,editor_type,password_hash,legacy_version,is_pinned,pin_order,visibility) '
      'VALUES (?,CAST(? AS TEXT),CAST(? AS TEXT),?, ?,?,?,?, ?,1,7,3)',
      [
        id,
        Uint8List.fromList(utf8.encode(title)),
        Uint8List.fromList(utf8.encode(body)),
        jsonEncode(['comma,label', '标签🙂']),
        -1,
        collection,
        format,
        hash,
        9223372036854775807,
      ],
    );
  }

  setUpAll(() async {
    sqfliteFfiInit();
    if (Platform.isLinux) {
      open.overrideFor(
        OperatingSystem.linux,
        () => DynamicLibrary.open('libsqlite3.so.0'),
      );
    }
    vector =
        (jsonDecode(
                  await File(
                    'tool/legacy_crypto_test/go-vectors.json',
                  ).readAsString(),
                )
                as List)
            .first
            .cast<String, dynamic>();
  });
  setUp(() async {
    final parent = Directory(
      Platform.environment['BOOKSTARK_APK_TEST_ROOT'] ??
          '/vol1/1000/wy/photos-apk-test/bookstark-flutter/unit-files',
    );
    await parent.create(recursive: true);
    root = await parent.createTemp('generation-content-');
    generation = LocalDataPaths.generation(id: 'e' * 32, privateSupport: root);
    await File(generation.databasePath).parent.create(recursive: true);
    db = await databaseFactoryFfiNoIsolate.openDatabase(
      generation.databasePath,
      options: OpenDatabaseOptions(
        version: 15,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys=ON'),
        onCreate: (db, v) => createLegacyCandidateSchema15(db),
      ),
    );
    await insert(
      1,
      '\ufefflocked',
      vector['body'] as String,
      hash: vector['hash'] as String,
    );
    await insert(
      2,
      'legacy protected',
      'private needle original',
      hash: vector['hash'] as String,
    );
    await insert(3, '\ufeffpublic', plain + 'x' * 2000);
    await insert(4, 'HTML', '\ufeff<p>html</p>\r\n', format: 'html');
    await insert(5, 'article', 'article original', collection: 'article');
    await insert(6, 'other article', 'peer', collection: 'article');
    current = true;
    methods = [];
    decrypted = {vector['body'] as String: vector['plain'] as String};
    unlockStarted = null;
    unlockRelease = null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      methods.add(call.method);
      if (call.method == 'cancel') {
        return null;
      }
      final args = call.arguments as Map;
      if (args['password'] != vector['password']) {
        throw PlatformException(code: 'WRONG_PASSWORD');
      }
      expect(args['hash'], vector['hash']);
      if (call.method == 'unlock') {
        unlockStarted?.complete();
        await unlockRelease?.future;
        final body = BoundedNoteTextReader.decodeUtf8PreservingBom(
          args['body'] as Uint8List,
        );
        final result = body.startsWith('ENC:') ? decrypted[body]! : body;
        return {
          'format': 1,
          'id': args['id'],
          'body': Uint8List.fromList(utf8.encode(result)),
        };
      }
      if (call.method == 'encryptExisting') {
        decrypted[fakeCipher] = BoundedNoteTextReader.decodeUtf8PreservingBom(
          args['body'] as Uint8List,
        );
        return {
          'format': 1,
          'id': args['id'],
          'body': Uint8List.fromList(utf8.encode(fakeCipher)),
        };
      }
      throw PlatformException(code: 'UNSUPPORTED');
    });
    repo = LocalGenerationContentRepository(
      database: db,
      generation: generation,
      isCurrent: () => current,
      crypto: NativeLocalContentCrypto(channel: channel),
      clock: () => DateTime.utc(2026, 11, 8),
    );
  });
  tearDown(() async {
    repo.dispose();
    if (unlockRelease != null && !unlockRelease!.isCompleted) {
      unlockRelease!.complete();
      await Future<void>.delayed(Duration.zero);
    }
    messenger.setMockMethodCallHandler(channel, null);
    if (db.isOpen) {
      await db.close();
    }
    await root.delete(recursive: true);
  });
  Matcher reason(GenerationContentReason value) =>
      isA<GenerationContentFailure>().having((e) => e.reason, 'reason', value);
  Future<GenerationContentHandle> unlock([int id = 1]) =>
      repo.open(id, password: vector['password'] as String);
  Future<Uint8List> bodyBytes(int id) async =>
      (await db.rawQuery(
            'SELECT CAST(content AS BLOB) AS b FROM notes WHERE id=?',
            [id],
          )).single['b']
          as Uint8List;

  test(
    'opaque body degrades only its preview; actual other resources stay openable',
    () async {
      await db.rawInsert(
        "INSERT INTO notes(id,title,content,labels,updated_at) VALUES(20,'Retained raw',?,'[]',1)",
        [
          Uint8List.fromList([0xff, 0, 0xef, 0xbb, 0xbf]),
        ],
      );
      final before = await OwnedGeneration15SchemaGate().rowDigests(db);
      final all = await repo.list(collection: 'all');
      expect(all.map((entry) => entry.metadata.id).toSet(), {
        1,
        2,
        3,
        4,
        5,
        6,
        20,
      });
      final raw = all.singleWhere((entry) => entry.metadata.id == 20);
      expect(raw.metadata.title, 'Retained raw');
      expect(raw.previewUnavailable, isTrue);
      expect(
        raw.preview,
        isEmpty,
        reason: 'Only a flagged list preview, never a body',
      );
      expect(
        all.singleWhere((entry) => entry.metadata.id == 3).previewUnavailable,
        isFalse,
      );
      await expectLater(
        repo.open(20),
        throwsA(reason(GenerationContentReason.invalidRecord)),
      );
      final actual = await repo.open(3);
      try {
        expect(actual.metadata.id, 3);
        expect(actual.source, plain + 'x' * 2000);
      } finally {
        actual.close();
      }
      expect(await OwnedGeneration15SchemaGate().rowDigests(db), before);
      expect(
        methods,
        isEmpty,
        reason: 'Listing cannot unlock, normalize or save',
      );
    },
  );
  test(
    'opaque metadata allowance never accepts malformed title or labels',
    () async {
      await db.rawInsert(
        "INSERT INTO notes(id,title,content,labels,updated_at) VALUES(20,?,?,'[]',1)",
        [
          Uint8List.fromList([0xff]),
          Uint8List.fromList([0xff]),
        ],
      );
      await expectLater(
        repo.list(collection: 'all'),
        throwsA(reason(GenerationContentReason.invalidRecord)),
      );
      expect((await bodyBytes(20)).toList(), [0xff]);
    },
  );
  test(
    'review counts and combined pages include articles without protected body previews',
    () async {
      final counts = await repo.counts();
      expect(counts.notes, 4);
      expect(counts.articles, 2);
      expect(counts.protectedItems, 2);
      expect(counts.total, 6);
      final all = await repo.list(collection: 'all');
      expect(all.map((e) => e.metadata.id), [6, 5, 4, 3, 2, 1]);
      expect(
        all.where((e) => e.metadata.collection == 'article'),
        hasLength(2),
      );
      expect(
        all
            .where((e) => e.metadata.isProtected)
            .every((e) => e.preview.isEmpty),
        isTrue,
      );
      await db.update('notes', {'deleted': 1}, where: 'id=1');
      final after = await repo.counts();
      expect(after.total, 5);
      expect(after.protectedItems, 1);
      current = false;
      await expectLater(
        repo.counts(),
        throwsA(reason(GenerationContentReason.retired)),
      );
    },
  );
  test(
    '20MiB imported Markdown is readable but does not enlarge the save boundary',
    () async {
      final source = '\ufeff${'x' * (20 * 1024 * 1024 - 3)}';
      await insert(101, 'large imported markdown', source);
      final handle = await repo.open(101);
      expect(utf8.encode(handle.source).length, 20 * 1024 * 1024);
      expect(handle.source, source);
      expect(
        () => repo.save(
          handle,
          title: 'large imported markdown',
          source: '${source}a',
          labels: handle.metadata.labels,
        ),
        throwsA(isA<GenerationContentFailure>()),
      );
      expect(await bodyBytes(101), utf8.encode(source));
      handle.close();
    },
  );
  test(
    'protected open without password returns metadata only and does not invoke native crypto',
    () async {
      await expectLater(
        repo.open(1),
        throwsA(
          isA<GenerationContentLocked>().having(
            (e) => e.metadata.isProtected,
            'protected',
            true,
          ),
        ),
      );
      expect(methods, isEmpty);
      expect(await bodyBytes(1), utf8.encode(vector['body'] as String));
    },
  );
  test(
    'protected plaintext and ciphertext never appear in preview or body search',
    () async {
      final all = await repo.list();
      expect(all.length, 4);
      expect(
        all
            .where((r) => r.metadata.isProtected)
            .every((r) => r.preview.isEmpty),
        true,
      );
      expect(all.singleWhere((r) => r.metadata.id == 4).preview, '');
      expect(
        all.singleWhere((r) => r.metadata.id == 3).preview.runes.length,
        512,
      );
      expect(
        (await repo.list(keyword: 'needle')).map((r) => r.metadata.id).toList(),
        [3],
      );
      expect((await repo.list(label: 'comma,label', pinned: '1')).length, 4);
      expect(await repo.list(pinned: '0'), isEmpty);
      expect(await repo.list(page: 2), isEmpty);
      expect(methods, isEmpty);
    },
  );
  test(
    'native unlock keeps exact BOM CRLF and exposes no stored password/hash field',
    () async {
      final opened = await unlock();
      expect(opened.source, vector['plain']);
      expect(opened.metadata.title, '\ufefflocked');
      expect(opened.metadata.revision, 1);
      expect(opened.metadata.isProtected, true);
      expect(methods, ['unlock']);
      expect(opened.isCurrent, true);
      opened.close();
      expect(opened.isCurrent, false);
      expect(
        () => opened.source,
        throwsA(reason(GenerationContentReason.retired)),
      );
      expect(db.isOpen, true);
    },
  );
  test('incorrect password leaves SQL and handles unchanged', () async {
    final before = await bodyBytes(1);
    await expectLater(
      repo.open(1, password: 'incorrect synthetic'),
      throwsA(
        isA<LocalContentCryptoFailure>().having(
          (e) => e.reason,
          'reason',
          LocalContentCryptoReason.wrongPassword,
        ),
      ),
    );
    expect(await bodyBytes(1), before);
    expect(
      (await db.query(
        'notes',
        columns: ['revision'],
        where: 'id=1',
      )).single['revision'],
      1,
    );
  });
  test(
    'public open returns complete source, not its bounded list preview',
    () async {
      final preview = (await repo.list())
          .singleWhere((r) => r.metadata.id == 3)
          .preview;
      final opened = await repo.open(3);
      expect(opened.source, plain + 'x' * 2000);
      expect(opened.source.length, greaterThan(preview.length));
      expect(opened.metadata.title, '\ufeffpublic');
      expect(methods, isEmpty);
    },
  );
  test(
    'repository retirement closes every plaintext handle and cannot resume',
    () async {
      final a = await unlock(), b = await repo.open(3);
      repo.dispose();
      expect(a.isCurrent, false);
      expect(b.isCurrent, false);
      expect(() => a.source, throwsA(reason(GenerationContentReason.retired)));
      current = true;
      await expectLater(
        repo.open(3),
        throwsA(reason(GenerationContentReason.retired)),
      );
      expect(db.isOpen, true);
    },
  );
  test(
    'stored row changed while native unlock waits never publishes stale plaintext',
    () async {
      unlockStarted = Completer<void>();
      unlockRelease = Completer<void>();
      final pending = unlock();
      await unlockStarted!.future;
      await db.update('notes', {
        'revision': 2,
        'title': 'changed during unlock',
      }, where: 'id=1');
      unlockRelease!.complete();
      await expectLater(
        pending,
        throwsA(reason(GenerationContentReason.conflict)),
      );
    },
  );
  test(
    'external cancellation aborts native work without publishing a handle',
    () async {
      unlockStarted = Completer<void>();
      unlockRelease = Completer<void>();
      final cancellation = AttachmentCancellation(),
          pending = repo.open(
            1,
            password: vector['password'] as String,
            cancellation: cancellation,
          );
      await unlockStarted!.future;
      cancellation.cancel();
      await expectLater(
        pending,
        throwsA(
          isA<LocalContentCryptoFailure>().having(
            (e) => e.reason,
            'reason',
            LocalContentCryptoReason.cancelled,
          ),
        ),
      );
      unlockRelease!.complete();
      await Future<void>.delayed(Duration.zero);
      expect(methods, contains('cancel'));
      expect(
        (await repo.list()).singleWhere((r) => r.metadata.id == 1).preview,
        '',
      );
    },
  );
  test(
    'protected save encrypts before SQL and advances independent revision, preserving legacy max64 and flags',
    () async {
      final opened = await unlock();
      const source = '\ufeff\ufeff# edited🙂\r\nA\u0000B\n';
      final saved = await repo.save(
        opened,
        title: '\ufeffnew title',
        source: source,
        labels: ['new,label', '标签🙂'],
      );
      expect(saved.source, source);
      expect(saved.metadata.revision, 2);
      expect(saved.metadata.title, '\ufeffnew title');
      expect(opened.isCurrent, false);
      expect(methods, ['unlock', 'encryptExisting']);
      expect(await bodyBytes(1), utf8.encode(fakeCipher));
      final row = (await db.query(
        'notes',
        columns: [
          'password_hash',
          'legacy_version',
          'is_pinned',
          'pin_order',
          'visibility',
          'revision',
          'updated_at',
        ],
        where: 'id=1',
      )).single;
      expect(row['password_hash'], vector['hash']);
      expect(row['legacy_version'], 9223372036854775807);
      expect(row['is_pinned'], 1);
      expect(row['pin_order'], 7);
      expect(row['visibility'], 3);
      expect(row['revision'], 2);
      expect(
        row['updated_at'],
        DateTime.utc(2026, 11, 8).millisecondsSinceEpoch,
      );
      expect((await unlock()).source, source);
    },
  );
  test(
    'public save retains repeated BOM CRLF NUL and preserves unrelated protected rows',
    () async {
      final protectedBefore = await bodyBytes(1), opened = await repo.open(3);
      const source = '\ufeff\ufeff# public🧩\r\nA\u0000B\r';
      final saved = await repo.save(
        opened,
        title: '\ufeffpublic edited',
        source: source,
        labels: ['comma,label'],
      );
      expect(saved.source, source);
      expect(saved.metadata.revision, 2);
      expect(await bodyBytes(3), utf8.encode(source));
      expect(await bodyBytes(1), protectedBefore);
      expect(methods, isEmpty);
    },
  );
  test(
    'same revision but changed stored body fails full baseline comparison before write',
    () async {
      final opened = await repo.open(3);
      await db.update('notes', {
        'content': 'external new source',
      }, where: 'id=3');
      await expectLater(
        repo.save(
          opened,
          title: 'unsaved',
          source: 'my edit',
          labels: opened.metadata.labels,
        ),
        throwsA(reason(GenerationContentReason.conflict)),
      );
      expect(await bodyBytes(3), utf8.encode('external new source'));
      expect(opened.isCurrent, false);
    },
  );
  test(
    'uncertain SQL abort retires baseline and preserves actual database rows after rollback',
    () async {
      final opened = await unlock(), before = await bodyBytes(1);
      await db.execute(
        "CREATE TRIGGER abort_content BEFORE UPDATE ON notes BEGIN SELECT RAISE(ABORT,'synthetic'); END",
      );
      await expectLater(
        repo.save(opened, title: 'attempt', source: '# changed', labels: []),
        throwsA(
          isA<GenerationContentWriteUncertain>().having(
            (e) => e.knownCommitted,
            'knownCommitted',
            false,
          ),
        ),
      );
      expect(await bodyBytes(1), before);
      expect(opened.isCurrent, false);
      expect(
        (await db.query(
          'notes',
          columns: ['revision'],
          where: 'id=1',
        )).single['revision'],
        1,
      );
    },
  );
  test(
    'late trigger changing legacy metadata is detected and rolled back',
    () async {
      final opened = await repo.open(3), before = await bodyBytes(3);
      await db.execute(
        "CREATE TRIGGER tamper_content AFTER UPDATE ON notes BEGIN UPDATE notes SET legacy_version=0,pin_order=0 WHERE id=NEW.id; END",
      );
      await expectLater(
        repo.save(opened, title: 'changed', source: 'new source', labels: []),
        throwsA(isA<GenerationContentWriteUncertain>()),
      );
      expect(await bodyBytes(3), before);
      expect(
        (await db.query(
          'notes',
          columns: ['legacy_version', 'pin_order'],
          where: 'id=3',
        )).single,
        {'legacy_version': 9223372036854775807, 'pin_order': 7},
      );
    },
  );
  test('unchanged save performs no encryption or revision write', () async {
    final opened = await unlock(), before = await bodyBytes(1);
    final result = await repo.save(
      opened,
      title: opened.metadata.title,
      source: opened.source,
      labels: opened.metadata.labels,
    );
    expect(identical(result, opened), true);
    expect(methods, ['unlock']);
    expect(await bodyBytes(1), before);
    expect(result.metadata.revision, 1);
  });
  test(
    'revision overflow and duplicate article title block before writes',
    () async {
      await db.update('notes', {
        'revision': 9223372036854775807,
      }, where: 'id=3');
      final opened = await repo.open(3);
      await expectLater(
        repo.save(opened, title: 'new', source: 'new', labels: []),
        throwsA(reason(GenerationContentReason.invalidRecord)),
      );
      final article = await repo.open(5, collection: 'article');
      await expectLater(
        repo.save(
          article,
          title: 'other article',
          source: 'changed',
          labels: [],
        ),
        throwsA(reason(GenerationContentReason.invalidEdit)),
      );
      expect(await bodyBytes(5), utf8.encode('article original'));
    },
  );
  test(
    'HTML source remains exact and invalid structured editor input cannot replace it',
    () async {
      final opened = await repo.open(4);
      const source = '\ufeff\ufeff<!doctype html>\r\n<p>🧩</p>\n';
      final saved = await repo.save(
        opened,
        title: 'HTML edit',
        source: source,
        labels: [],
      );
      expect(saved.source, source);
      expect(await bodyBytes(4), utf8.encode(source));
      await db.update('notes', {
        'editor_type': 'drawing',
        'content': '{"elements":[]}',
      }, where: 'id=4');
      final drawing = await repo.open(4);
      await expectLater(
        repo.save(drawing, title: 'broken', source: 'not JSON', labels: []),
        throwsA(reason(GenerationContentReason.invalidEdit)),
      );
      expect(await bodyBytes(4), utf8.encode('{"elements":[]}'));
    },
  );
  test(
    'legacy or mismatched database path cannot construct the repository',
    () {
      final legacy = LocalDataPaths.legacy(
        databasePath: db.path,
        privateSupport: root,
      );
      expect(
        () => LocalGenerationContentRepository(
          database: db,
          generation: legacy,
          isCurrent: () => true,
        ),
        throwsArgumentError,
      );
      final other = LocalDataPaths.generation(
        id: 'f' * 32,
        privateSupport: root,
      );
      expect(
        () => LocalGenerationContentRepository(
          database: db,
          generation: other,
          isCurrent: () => true,
        ),
        throwsArgumentError,
      );
    },
  );
  test(
    'unchanged stale save retires the old handle instead of silently adopting metadata',
    () async {
      final opened = await repo.open(3), source = opened.source;
      await db.update('notes', {'revision': 2}, where: 'id=3');
      await expectLater(
        repo.save(
          opened,
          title: opened.metadata.title,
          source: source,
          labels: opened.metadata.labels,
        ),
        throwsA(reason(GenerationContentReason.conflict)),
      );
      expect(opened.isCurrent, false);
    },
  );
  test(
    'already committed write followed by retirement returns committed reconciliation facts only',
    () async {
      repo.dispose();
      final boundary = _CommitBoundaryDatabase(db);
      repo = LocalGenerationContentRepository(
        database: boundary,
        generation: generation,
        isCurrent: () => current,
        crypto: NativeLocalContentCrypto(channel: channel),
      );
      final opened = await repo.open(3);
      boundary.afterWriteCommit = repo.dispose;
      await expectLater(
        repo.save(
          opened,
          title: 'committed',
          source: 'committed source',
          labels: [],
        ),
        throwsA(
          isA<GenerationContentWriteUncertain>()
              .having((e) => e.knownCommitted, 'knownCommitted', true)
              .having((e) => e.expectedRevision, 'revision', 2),
        ),
      );
      expect(opened.isCurrent, false);
      expect(await bodyBytes(3), utf8.encode('committed source'));
      expect(
        (await db.query(
          'notes',
          columns: ['revision'],
          where: 'id=3',
        )).single['revision'],
        2,
      );
    },
  );
  test(
    'pre-cancelled open does not invoke native crypto or alter SQL',
    () async {
      final cancellation = AttachmentCancellation()..cancel(),
          before = await bodyBytes(1);
      await expectLater(
        repo.open(
          1,
          password: vector['password'] as String,
          cancellation: cancellation,
        ),
        throwsA(reason(GenerationContentReason.cancelled)),
      );
      expect(methods, isEmpty);
      expect(await bodyBytes(1), before);
    },
  );
  test(
    'non-TEXT password hash is rejected before any native invocation',
    () async {
      await db.update('notes', {
        'password_hash': Uint8List.fromList(
          utf8.encode(vector['hash'] as String),
        ),
      }, where: 'id=1');
      await expectLater(
        unlock(),
        throwsA(reason(GenerationContentReason.invalidRecord)),
      );
      expect(methods, isEmpty);
    },
  );
}
