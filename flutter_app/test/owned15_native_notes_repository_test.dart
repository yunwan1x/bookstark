import 'dart:async';
import 'dart:ffi' show DynamicLibrary;
import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:bookstark_flutter/features/notes/notes_page.dart';
import 'package:bookstark_flutter/features/local_backup/owned15_native_memory_editor.dart';
import 'package:bookstark_flutter/features/local_backup/owned15_feature.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/open.dart';
import 'package:bookstark_flutter/core/attachments.dart';
import 'package:bookstark_flutter/core/notes_repository.dart';
import 'package:bookstark_flutter/core/local_data_paths.dart';
import 'package:bookstark_flutter/core/local_generation_state.dart';
import 'package:bookstark_flutter/core/local_legacy_candidate_schema.dart';
import 'package:bookstark_flutter/core/native_local_content_crypto.dart';
import 'package:bookstark_flutter/core/native_local_data_control.dart';
import 'package:bookstark_flutter/core/owned15_native_notes_repository.dart';
import 'package:bookstark_flutter/core/owned15_save_journal.dart';
import 'package:bookstark_flutter/core/owned_generation15_schema.dart';
import 'package:bookstark_flutter/core/owned_writable_generation15.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('bookstark/owned15-adapter-unit');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory root;
  late LocalDataPaths layout;
  late OwnedWritableGeneration15 owner;
  late LocalGenerationPointer pointer;
  late String pointerRaw;
  final values = <String, String>{};
  bool failFlush = false,
      failKnown = false,
      retargetOnClaim = false,
      holdNextRead = false;
  Completer<void>? readEntered, releaseRead;
  Owned15SaveJournal? journal;
  Owned15NativeNotesRepository? repository;
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
    final parent = Directory(
      Platform.environment['BOOKSTARK_APK_TEST_ROOT'] ??
          '/vol1/1000/wy/photos-apk-test/bookstark-flutter/current-run/test-tmp',
    );
    await parent.create(recursive: true);
    root = await parent.createTemp('owned15-adapter-');
    pointer = LocalGenerationPointer(
      generation: 'a' * 32,
      epoch: 7,
      activationId: 'b' * 32,
      sourceSHA256: 'c' * 64,
    );
    pointerRaw = pointer.encode();
    values.clear();
    failFlush = false;
    failKnown = false;
    retargetOnClaim = false;
    journal = null;
    repository = null;
    holdNextRead = false;
    readEntered = null;
    releaseRead = null;
    layout = LocalDataPaths.generation(
      id: pointer.generation,
      privateSupport: root,
    );
    await File(layout.databasePath).parent.create(recursive: true);
    await layout.attachments.create();
    await layout.driveBlobs.create();
    final db = await databaseFactoryFfiNoIsolate.openDatabase(
      layout.databasePath,
      options: OpenDatabaseOptions(
        version: 15,
        singleInstance: false,
        onCreate: (db, _) => createLegacyCandidateSchema15(db),
      ),
    );
    await db.insert('notes', {
      'id': 9,
      'title': 'Original',
      'content': '\ufeff# Original\r\n',
      'labels': '["original"]',
      'updated_at': 11,
      'collection': 'note',
      'editor_type': 'markdown',
      'visibility': 3,
      'is_pinned': 1,
      'pin_order': -2,
      'legacy_version': 9223372036854775807,
    });
    await db.close();
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'drain') return {'format': 1, 'drained': true};
      throw StateError('Unprotected adapter must not transform source');
    });
    owner = await OwnedWritableGeneration15.openActive(
      privateSupport: root,
      workspace: await Directory('${root.path}/verify').create(),
      expectedPointer: pointer,
      isCurrentScope: () => true,
      factory: databaseFactoryFfiNoIsolate,
      crypto: NativeLocalContentCrypto(channel: channel),
      control: NativeLocalDataControl(
        invoke: (name, args) async {
          if (name != 'readState') {
            throw StateError('No native mutation for existing-ID save');
          }
          if (holdNextRead) {
            holdNextRead = false;
            readEntered!.complete();
            await releaseRead!.future;
          }
          return {
            'format': 1,
            'pointerRaw': pointerRaw,
            'intentRaw': null,
            'currentRetentionRaw': null,
            'sourceRetentionRaw': null,
            'metadataOnly': true,
          };
        },
      ),
    );
  });
  tearDown(() async {
    repository?.dispose();
    await repository?.drain();
    await journal?.drain();
    journal?.retire();
    await owner.retire();
    messenger.setMockMethodCallHandler(channel, null);
    await root.delete(recursive: true);
  });
  Future<Map<String, String>> rows() async {
    final db = await databaseFactoryFfiNoIsolate.openDatabase(
      layout.databasePath,
      options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
    );
    try {
      return await OwnedGeneration15SchemaGate().rowDigests(db);
    } finally {
      await db.close();
    }
  }

  Future<void> openRepository() async {
    journal = Owned15SaveJournal(
      draftNamespace: layout.draftNamespace,
      collection: 'note',
      resourceId: 9,
      isCurrent: () => owner.current,
      readValue: (key) async => values[key],
      writeValue: (key, value) async {
        values[key] = value;
        final state = (jsonDecode(value) as Map)['state'];
        if (state == 'known' && failKnown) failFlush = true;
        if (state == 'unknown' && retargetOnClaim) {
          pointerRaw = LocalGenerationPointer(
            generation: pointer.generation,
            epoch: 8,
            activationId: 'd' * 32,
            sourceSHA256: 'c' * 64,
          ).encode();
        }
      },
      deleteValue: (key) async {
        values.remove(key);
      },
      flush: () async {
        if (failFlush) throw StateError('Storage barrier failed');
      },
    );
    repository = await Owned15NativeNotesRepository.open(
      owner: owner,
      journal: journal!,
      resourceId: 9,
      isCurrentScope: () => owner.current,
      cancellation: AttachmentCancellation(),
    );
  }

  Note edit() => repository!.baseline.copyWith(content: '\ufeff# Changed\r\n');
  test(
    'known native note cleanup retries only storage with all SQL rows and seq unchanged',
    () async {
      await openRepository();
      failKnown = true;
      final desired = edit();
      await expectLater(
        repository!.save(desired),
        throwsA(isA<NoteSaveFailure>()),
      );
      final committed = await rows();
      expect(repository!.reviewRequired.value, isFalse);
      expect(values.values.join(), isNot(contains('# Changed')));
      expect(values.values.join(), isNot(contains('# Original')));
      failKnown = false;
      failFlush = false;
      expect(await repository!.save(desired), 9);
      expect(await rows(), committed);
      expect(values, isEmpty);
      expect((await repository!.read(9)).content, '\ufeff# Changed\r\n');
    },
  );
  test(
    'unknown save is latched and a second Save cannot replay the UPDATE',
    () async {
      await openRepository();
      final before = await rows();
      final desired = edit();
      failFlush = true;
      await expectLater(
        repository!.save(desired),
        throwsA(isA<Owned15NativeSaveNeedsReview>()),
      );
      expect(repository!.reviewRequired.value, isTrue);
      failFlush = false;
      await expectLater(
        repository!.save(desired),
        throwsA(isA<Owned15NativeSaveNeedsReview>()),
      );
      expect(await rows(), before);
    },
  );
  test('changed input cannot be sent as a known cleanup retry', () async {
    await openRepository();
    failKnown = true;
    final desired = edit();
    await expectLater(
      repository!.save(desired),
      throwsA(isA<NoteSaveFailure>()),
    );
    final committed = await rows();
    failKnown = false;
    failFlush = false;
    await expectLater(
      repository!.save(desired.copyWith(content: 'Different input')),
      throwsStateError,
    );
    expect(await rows(), committed);
    expect(await repository!.save(desired), 9);
    expect(await rows(), committed);
  });
  test(
    'null or another ID cannot become ordinary INSERT and creates no marker',
    () async {
      await openRepository();
      final before = await rows();
      await expectLater(
        repository!.save(const Note(title: 'New', content: 'Body')),
        throwsArgumentError,
      );
      await expectLater(
        repository!.save(edit().copyWith(id: 10)),
        throwsArgumentError,
      );
      expect(values, isEmpty);
      expect(await rows(), before);
    },
  );
  test(
    'actual pre-SQL pointer await is cancelled and joined before plaintext owner retires',
    () async {
      await openRepository();
      final before = await rows();
      readEntered = Completer<void>();
      releaseRead = Completer<void>();
      holdNextRead = true;
      final saving = repository!.save(edit());
      final failure = expectLater(saving, throwsA(anything));
      await readEntered!.future;
      repository!.dispose();
      var drained = false;
      final closing = repository!.drain().then((_) => drained = true);
      await Future<void>.delayed(Duration.zero);
      expect(drained, isFalse);
      releaseRead!.complete();
      await failure;
      await closing;
      expect(drained, isTrue);
      expect(await rows(), before);
      expect(values, isNotEmpty);
    },
  );

  testWidgets(
    'unknown replaces actual native editor with explicit read-only review and retains record on back',
    (tester) async {
      try {
        await tester.runAsync(openRepository);
        final desired = edit();
        var reviewed = 0, acknowledged = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Owned15NativeMemoryEditor(
              repository: repository!,
              isCurrent: () => owner.current,
              onReviewed: () async {
                reviewed++;
              },
              editorBuilder: (_) => NoteEditorPage(
                repository: repository!,
                note: repository!.baseline,
                drafts: null,
                onSaveAcknowledged: (_, _, _) {
                  acknowledged++;
                },
              ),
            ),
          ),
        );
        expect(find.byType(NoteEditorPage), findsOneWidget);
        final beforeUnknown = await tester.runAsync(rows);
        // A real SQLite rejection AFTER the durable claim exercises unknown
        // recovery while keeping this same owner available for readonly review.
        await tester.runAsync(
          () => owner.exclusiveSnapshot(
            (db) => db.execute(
              "CREATE TRIGGER owned15_fail_update BEFORE UPDATE ON notes "
              "BEGIN SELECT RAISE(FAIL,'fixture SQL rejection'); END",
            ),
          ),
        );
        await tester.runAsync(() async {
          await expectLater(
            repository!.save(desired),
            throwsA(isA<Owned15NativeSaveNeedsReview>()),
          );
        });
        await tester.pump();
        expect(find.byType(NoteEditorPage), findsNothing);
        expect(find.byType(TextField), findsNothing);
        expect(find.text('重新读取核对'), findsOneWidget);
        expect(find.text('确认已核对并移除记录'), findsNothing);
        expect(reviewed, 0);
        expect(acknowledged, 0);
        expect(values, isNotEmpty);
        expect(await tester.runAsync(rows), beforeUnknown);
        await tester.runAsync(
          () => owner.exclusiveSnapshot(
            (db) => db.execute('DROP TRIGGER owned15_fail_update'),
          ),
        );
        await tester.runAsync(() => repository!.read(9));
        expect(repository!.reviewRequired.value, isTrue);
        await tester.pumpWidget(const SizedBox.shrink());
        expect(values, isNotEmpty);
        expect(reviewed, 0);
        expect(acknowledged, 0);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        repository?.dispose();
        await tester.runAsync(() async {
          await repository?.drain();
          await journal?.drain();
          await owner.retire();
        });
      }
    },
  );

  Future<void> reveal(WidgetTester tester, Finder target) async {
    final scroll = find
        .descendant(
          of: find.byType(Owned15Feature),
          matching: find.byType(Scrollable),
        )
        .first;
    expect(scroll, findsOneWidget);
    for (
      var step = 0;
      step < 100 && target.hitTestable().evaluate().isEmpty;
      step++
    ) {
      final box = tester.getRect(scroll);
      await tester.dragFrom(
        Offset(box.left + 8, box.center.dy),
        const Offset(0, -100),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(target.hitTestable(), findsOneWidget);
  }

  testWidgets(
    'owned catalog loads actual metadata and keeps seven formats and collection IDs typed',
    (tester) async {
      try {
        await tester.runAsync(() async {
          final db = await databaseFactoryFfiNoIsolate.openDatabase(
            layout.databasePath,
            options: OpenDatabaseOptions(singleInstance: false),
          );
          try {
            for (var index = 0; index < 7; index++) {
              final kind = [
                'markdown',
                'html',
                'spreadsheet',
                'drawing',
                'mindmap',
                'richdoc',
                'presentation',
              ][index];
              await db.insert('notes', {
                'id': 20 + index,
                'title': 'Actual $kind',
                'content': 'fixture source',
                'labels': '[]',
                'updated_at': 12,
                'collection': index == 0 ? 'article' : 'note',
                'editor_type': kind,
                'visibility': 0,
                'is_pinned': 0,
                'pin_order': 0,
                'legacy_version': 1,
              });
            }
            await db.rawInsert(
              "INSERT INTO notes(id,title,content,labels,updated_at) VALUES(27,'Retained opaque note',?,'[]',13)",
              [
                Uint8List.fromList([0xff, 0, 0xef, 0xbb, 0xbf]),
              ],
            );
          } finally {
            await db.close();
          }
        });
        final metadata = await tester.runAsync(
          () => owner.content.list(collection: 'all'),
        );
        final entries = metadata!;
        expect(
          entries
              .singleWhere((entry) => entry.metadata.id == 27)
              .previewUnavailable,
          isTrue,
        );
        expect(entries.map((entry) => entry.metadata.format.name).toSet(), {
          'markdown',
          'html',
          'spreadsheet',
          'drawing',
          'mindmap',
          'richdoc',
          'presentation',
        });
        expect(
          entries
              .where((entry) => entry.metadata.id == 20)
              .single
              .metadata
              .collection,
          'article',
        );
        final opened = <String>[];
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(2),
                viewInsets: const EdgeInsets.only(bottom: 180),
              ),
              child: child!,
            ),
            home: Owned15Feature(
              owner: owner,
              english: true,
              isCurrent: () => owner.current,
              openResource: (actual) async {
                opened.add(
                  '${actual.collection}:${actual.id}:${actual.format.name}',
                );
              },
              openBackup: () async {},
              openMigration: () async {},
              onConnection: () async {},
            ),
          ),
        );
        for (
          var attempt = 0;
          attempt < 400 &&
              tester
                      .widget<IconButton>(
                        find.byWidgetPredicate(
                          (widget) =>
                              widget is IconButton &&
                              widget.tooltip == 'Complete backup and recovery',
                        ),
                      )
                      .onPressed ==
                  null;
          attempt++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
          await tester.pump(const Duration(milliseconds: 1));
        }
        expect(
          tester
              .widget<IconButton>(
                find.byWidgetPredicate(
                  (widget) =>
                      widget is IconButton &&
                      widget.tooltip == 'Complete backup and recovery',
                ),
              )
              .onPressed,
          isNotNull,
          reason:
              'Actual fixed toolbar action enables only after real loading finishes',
        );
        expect(find.text('Content could not be read. Retry.'), findsNothing);
        expect(find.byType(LinearProgressIndicator), findsNothing);
        await reveal(
          tester,
          find.textContaining('Original retained; preview unavailable'),
        );
        expect(
          find.textContaining('Original retained; preview unavailable'),
          findsOneWidget,
        );
        await reveal(tester, find.text('Actual markdown'));
        await tester.pump();
        expect(find.text('Actual markdown'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Actual markdown'));
        for (var attempt = 0; attempt < 400 && opened.isEmpty; attempt++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
          await tester.pump();
        }
        expect(opened, ['article:20:markdown']);
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        repository?.dispose();
        await tester.runAsync(() async {
          await repository?.drain();
          await journal?.drain();
          await owner.retire();
        });
      }
    },
  );
}
