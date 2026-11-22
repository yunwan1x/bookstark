import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/open.dart';
import 'package:bookstark_flutter/core/attachments.dart';
import 'package:bookstark_flutter/core/local_backup_importer.dart';
import 'package:bookstark_flutter/core/local_generation_content_repository.dart';
import 'package:bookstark_flutter/core/local_legacy_candidate_review.dart';
import 'package:bookstark_flutter/core/local_legacy_format_selection.dart';
import 'package:bookstark_flutter/core/local_legacy_go_export.dart';
import 'package:bookstark_flutter/core/local_legacy_zip_stage.dart';
import 'package:bookstark_flutter/core/native_local_content_crypto.dart';

class _Factory implements DatabaseFactory {
  _Factory(this.inner);
  final DatabaseFactory inner;
  Database? readOnly;
  @override
  Future<Database> openDatabase(
    String path, {
    OpenDatabaseOptions? options,
  }) async {
    final db = await inner.openDatabase(path, options: options);
    if (options?.readOnly == true) readOnly = db;
    return db;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root, parent;
  late LegacyZipStage stage;
  late LegacyGoExport source;
  late LegacyFormatSelection selection;
  late _Factory factory;
  LegacyCandidateReviewSession? session;
  var current = true;
  const channel = MethodChannel('bookstark/review-unit-crypto');
  setUpAll(() {
    sqfliteFfiInit();
    if (Platform.isLinux) {
      open.overrideFor(
        OperatingSystem.linux,
        () => DynamicLibrary.open('libsqlite3.so.0'),
      );
    }
  });
  setUp(() async {
    final base = Directory(
      Platform.environment['BOOKSTARK_APK_TEST_ROOT'] ??
          '/vol1/1000/wy/photos-apk-test/bookstark-flutter/unit-files',
    );
    await base.create(recursive: true);
    root = await base.createTemp('review-session-');
    parent = await Directory('${root.path}/reviews').create();
    await File(
      '${parent.path}/keep.txt',
    ).writeAsString('unrelated current data');
    current = true;
    factory = _Factory(databaseFactoryFfiNoIsolate);
  });
  tearDown(() async {
    try {
      await session?.close();
    } catch (_) {}
    session = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await root.delete(recursive: true);
  });
  Future<void> prepare([String variant = 'known-formats']) async {
    final input = File('test/fixtures/legacy_zip/identity-$variant.zip');
    final digest = (await sha256.bind(input.openRead()).first).toString();
    stage = await LegacyZipStage.inspect(
      input,
      privateParent: root,
      expectedSha256: digest,
      availableBytes: () async => 4 * 1024 * 1024 * 1024,
    );
    source = await LegacyGoExport.inspect(stage);
    final formats = LegacyFormatSource.fromInspection(
      source,
      scopeKey: 'b' * 32,
    );
    selection = LegacyFormatSelection(
      formats,
      choices: {
        for (final item in formats.items) item.id: LegacyContentFormat.html,
      },
    );
  }

  Future<LegacyCandidateReviewSession> build({
    AttachmentCancellation? cancellation,
    Future<int> Function()? space,
  }) => LegacyCandidateReviewSession.build(
    stage: stage,
    selection: selection,
    privateParent: parent,
    availableBytes: space ?? () async => 4 * 1024 * 1024 * 1024,
    isCurrentScope: () => current,
    factory: factory,
    cancellation: cancellation,
    crypto: NativeLocalContentCrypto(channel: channel),
  );
  Future<List<Directory>> directories() async => [
    await for (final item in parent.list(followLinks: false))
      if (item is Directory) item,
  ];
  Future<void> originalUntouched() async {
    expect(
      await File('${parent.path}/keep.txt').readAsString(),
      'unrelated current data',
    );
    final archive = File('test/fixtures/legacy_zip/identity-known-formats.zip');
    expect(await archive.exists(), isTrue);
    expect(await stage.directory.exists(), isTrue);
  }

  test(
    'session close waits registered views before deleting or closing its readonly copy',
    () async {
      await prepare();
      session = await build();
      final owner = Object(), gate = Completer<void>();
      var done = false;
      session!.attachViewer(owner, () => gate.future);
      expect(() => session!.attachViewer(owner, () async {}), throwsStateError);
      final closing = session!.close()..then((_) => done = true);
      await Future<void>.delayed(Duration.zero);
      expect(done, isFalse);
      expect(factory.readOnly!.isOpen, isTrue);
      expect((await directories()).length, 1);
      gate.complete();
      await closing;
      expect(done, isTrue);
      expect(await directories(), isEmpty);
      await originalUntouched();
    },
  );
  test(
    'failed viewer retirement keeps its copy and can be explicitly retried',
    () async {
      await prepare();
      session = await build();
      var calls = 0;
      session!.attachViewer(Object(), () async {
        if (++calls == 1) throw StateError('owned close failed');
      });
      await expectLater(session!.close(), throwsStateError);
      expect((await directories()).length, 1);
      expect(factory.readOnly!.isOpen, isTrue);
      await session!.close();
      expect(calls, 2);
      expect(await directories(), isEmpty);
      await originalUntouched();
    },
  );
  test(
    'real Go copy publishes only read APIs from a genuinely readonly database',
    () async {
      await prepare();
      session = await build();
      final counts = await session!.counts();
      final blogs = source.sections['blogs.json'] as List;
      expect(counts.total, blogs.length);
      expect(
        counts.articles,
        blogs.where((v) => (v as Map)['blog_type'] == 'article').length,
      );
      final entries = await session!.list();
      expect(entries.length, counts.total);
      final first = entries.first;
      final handle = await session!.open(
        first.metadata.id,
        collection: first.metadata.collection,
      );
      expect(
        handle.source,
        (blogs[first.metadata.id - 1] as Map)['blog_content'],
      );
      expect(factory.readOnly, isNotNull);
      await expectLater(
        factory.readOnly!.execute('UPDATE notes SET title=? WHERE id=1', [
          'forbidden',
        ]),
        throwsA(anything),
      );
      expect(
        (await session!.list()).map((r) => r.metadata.title),
        entries.map((r) => r.metadata.title),
      );
      expect((await directories()).length, 1);
      await session!.close();
      expect(await directories(), isEmpty);
      expect(handle.isCurrent, isFalse);
      await expectLater(
        session!.counts(),
        throwsA(isA<GenerationContentFailure>()),
      );
      await originalUntouched();
    },
  );
  test(
    'HTML view is bounded to its content lifetime and close drains reads',
    () async {
      await prepare();
      session = await build();
      final entry = (await session!.list()).first;
      final handle = await session!.open(
        entry.metadata.id,
        collection: entry.metadata.collection,
      );
      final view = session!.html(handle);
      expect(view.document.scriptsEnabled, isFalse);
      expect(view.document.source, contains(handle.source));
      session!.lockContent();
      expect(view.isCurrent, isFalse);
      expect(await view.load('/upload-files/none.png'), isNull);
      expect(() => handle.source, throwsA(isA<GenerationContentFailure>()));
      expect((await session!.counts()).total, greaterThan(0));
      final reopened = await session!.open(
        entry.metadata.id,
        collection: entry.metadata.collection,
      );
      expect(reopened.isCurrent, isTrue);
      await session!.close();
      expect(reopened.isCurrent, isFalse);
      await originalUntouched();
    },
  );
  test(
    'changed staged bytes are rejected before creating a review directory',
    () async {
      await prepare();
      await stage.files['blogs.json']!.file.writeAsString('[]');
      await expectLater(build(), throwsA(anything));
      expect(await directories(), isEmpty);
      await originalUntouched();
    },
  );
  test(
    'incomplete recipe and wrong source lifetime never create a candidate',
    () async {
      await prepare();
      selection = LegacyFormatSelection(selection.source);
      await expectLater(build(), throwsA(isA<GenerationContentFailure>()));
      expect(await directories(), isEmpty);
      await originalUntouched();
    },
  );
  test(
    'pre-cancel and reserve failures preserve all source/current files',
    () async {
      await prepare();
      final cancelled = AttachmentCancellation()..cancel();
      await expectLater(
        build(cancellation: cancelled),
        throwsA(isA<GenerationContentFailure>()),
      );
      await expectLater(
        build(space: () async => 0),
        throwsA(isA<LocalBackupSpaceUnavailable>()),
      );
      expect(await directories(), isEmpty);
      await originalUntouched();
    },
  );
  test(
    'cancellation inside upload preparation removes only the owned copy',
    () async {
      await prepare('upload-shared-thumb');
      final request = AttachmentCancellation();
      var checks = 0;
      await expectLater(
        build(
          cancellation: request,
          space: () async {
            if (++checks == 2) request.cancel();
            return 4 * 1024 * 1024 * 1024;
          },
        ),
        throwsA(anything),
      );
      expect(await directories(), isEmpty);
      await originalUntouched();
    },
  );
  test(
    'scope retirement is sticky and cannot resurrect plaintext or reads',
    () async {
      await prepare();
      session = await build();
      final entry = (await session!.list()).first;
      final handle = await session!.open(
        entry.metadata.id,
        collection: entry.metadata.collection,
      );
      current = false;
      expect(session!.isCurrent, isFalse);
      current = true;
      expect(session!.isCurrent, isFalse);
      expect(() => handle.source, throwsA(isA<GenerationContentFailure>()));
      await expectLater(
        session!.list(),
        throwsA(isA<GenerationContentFailure>()),
      );
      await session!.close();
      expect(await directories(), isEmpty);
      await originalUntouched();
    },
  );
  test(
    'unknown files prevent blind deletion, then explicit cleanup retry succeeds',
    () async {
      await prepare();
      session = await build();
      final owned = (await directories()).single;
      final foreign = File('${owned.path}/unknown.txt');
      await foreign.writeAsString('keep');
      await expectLater(
        session!.close(),
        throwsA(isA<LegacyReviewCleanupRequired>()),
      );
      expect(await foreign.readAsString(), 'keep');
      await originalUntouched();
      await foreign.delete();
      await session!.close();
      expect(await directories(), isEmpty);
    },
  );
  test(
    'protected items never reveal a body before correct ephemeral unlock',
    () async {
      await prepare('protected-native');
      final vector =
          (jsonDecode(
                        await File(
                          'tool/legacy_crypto_test/go-vectors.json',
                        ).readAsString(),
                      )
                      as List)
                  .first
              as Map;
      var calls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'cancel') return null;
            calls++;
            final args = call.arguments as Map;
            if (args['password'] != vector['password']) {
              throw PlatformException(code: 'WRONG_PASSWORD');
            }
            return {
              'format': 1,
              'id': args['id'],
              'body': Uint8List.fromList(
                utf8.encode(vector['plain'] as String),
              ),
            };
          });
      session = await build();
      final entry = (await session!.list()).firstWhere(
        (e) => e.metadata.isProtected,
      );
      expect(entry.preview, isEmpty);
      expect(calls, 0);
      await expectLater(
        session!.open(entry.metadata.id, collection: entry.metadata.collection),
        throwsA(isA<GenerationContentLocked>()),
      );
      expect(calls, 0);
      await expectLater(
        session!.open(
          entry.metadata.id,
          collection: entry.metadata.collection,
          password: 'wrong',
        ),
        throwsA(isA<LocalContentCryptoFailure>()),
      );
      final handle = await session!.open(
        entry.metadata.id,
        collection: entry.metadata.collection,
        password: vector['password'] as String,
      );
      expect(handle.source, vector['plain']);
      expect(calls, 2);
      session!.lockContent();
      expect(handle.isCurrent, isFalse);
      await session!.close();
      await originalUntouched();
    },
  );
}
