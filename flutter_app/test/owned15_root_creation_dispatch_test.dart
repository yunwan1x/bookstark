import 'package:bookstark_flutter/features/local_backup/owned15_creation_target_dialog.dart';
import 'dart:ffi';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' as sql;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/open.dart';
import 'package:bookstark_flutter/core/local_data_paths.dart';
import 'package:bookstark_flutter/core/local_generation_state.dart';
import 'package:bookstark_flutter/core/local_legacy_candidate_schema.dart';
import 'package:bookstark_flutter/core/owned_generation15_schema.dart';
import 'package:bookstark_flutter/core/root_local_creation_dispatch.dart';
import 'package:bookstark_flutter/features/home_page.dart';
import 'package:bookstark_flutter/features/local_backup/owned15_feature.dart';
import 'package:bookstark_flutter/features/notes/notes_page.dart';
import 'package:bookstark_flutter/main.dart';

class _Factory extends Fake implements sql.DatabaseFactory {
  _Factory(this.support, this.active);
  final String support, active;
  int legacyWrites = 0;
  int unexpectedOtherWrites = 0;
  final activeVersions = <int?>[];
  @override
  Future<String> getDatabasesPath() async => support;
  @override
  Future<sql.Database> openDatabase(
    String path, {
    sql.OpenDatabaseOptions? options,
  }) async {
    if (path != active &&
        options?.readOnly != true &&
        (!path.startsWith('$support/') ||
            !path.split('/').last.startsWith('owned15-template-') ||
            options?.version != 15 ||
            options?.onCreate == null)) {
      unexpectedOtherWrites++;
    }
    if (path == active && options?.readOnly != true) {
      activeVersions.add(options?.version);
    }
    if (path == '$support/bookstark-flutter.db' && options?.readOnly != true) {
      legacyWrites++;
    }
    return databaseFactoryFfiNoIsolate.openDatabase(path, options: options);
  }

  @override
  Future<void> deleteDatabase(String path) =>
      databaseFactoryFfiNoIsolate.deleteDatabase(path);
  @override
  Future<bool> databaseExists(String path) =>
      databaseFactoryFfiNoIsolate.databaseExists(path);
}

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
  test(
    'unresolved local target never invokes an ordinary creation factory',
    () {
      var calls = 0;
      expect(
        () => RootLocalCreationDispatch.dispatch<Object?>(
          resolved: null,
          owned: null,
          create: (_) {
            calls++;
            return null;
          },
        ),
        throwsA(isA<LocalCreationUnavailable>()),
      );
      expect(calls, 0);
    },
  );
  testWidgets(
    'real Root dispatches active15 to owned catalog and denies old article INSERT while retaining draft',
    (tester) async {
      final oldPlatform = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      final parent = Directory(
        Platform.environment['BOOKSTARK_APK_TEST_ROOT'] ??
            '/vol1/1000/wy/photos-apk-test/bookstark-flutter/current-run/test-tmp',
      );
      final root = (await tester.runAsync(() async {
        await parent.create(recursive: true);
        return parent.createTemp('owned15-root-dispatch-');
      }))!;
      final pointer = LocalGenerationPointer(
        generation: 'd' * 32,
        epoch: 3,
        activationId: 'e' * 32,
        sourceSHA256: 'f' * 64,
      );
      final layout = LocalDataPaths.generation(
        id: pointer.generation,
        privateSupport: root,
      );
      final factory = _Factory(root.path, layout.databasePath);
      const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
      const control = MethodChannel('bookstark/local_data_control');
      const crypto = MethodChannel('bookstark/local_content_crypto');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final mutations = <String>[];
      Owned15Feature? feature;
      const draftKey = 'bookstark.root-negative-creation-fixture';
      FlutterSecureStorage.setMockInitialValues({
        draftKey: 'retained fixture draft',
      });
      try {
        await tester.runAsync(() async {
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
          try {
            await db.insert('notes', {
              'id': 9,
              'title': 'Existing owned article',
              'content': '# Original',
              'labels': '[]',
              'collection': 'article',
              'editor_type': 'markdown',
              'updated_at': 10,
            });
          } finally {
            await db.close();
          }
        });
        messenger.setMockMethodCallHandler(pathChannel, (_) async {
          return root.path;
        });
        messenger.setMockMethodCallHandler(crypto, (call) async {
          if (call.method == 'drain') return {'format': 1, 'drained': true};
          throw StateError('No password/body crypto in creation dispatch gate');
        });
        messenger.setMockMethodCallHandler(control, (call) async {
          if (call.method != 'readState') {
            mutations.add(call.method);
            throw StateError('No native mutation');
          }
          return {
            'format': 1,
            'pointerRaw': pointer.encode(),
            'intentRaw': null,
            'currentRetentionRaw': null,
            'sourceRetentionRaw': null,
            'metadataOnly': true,
          };
        });
        await tester.pumpWidget(BookstarkApp(localDatabaseFactory: factory));
        await tester.pumpAndSettle();
        await tester.tap(find.text('本地空间'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('进入本地空间'));
        await tester.pump();
        for (
          var i = 0;
          i < 1000 &&
              (find.byType(Owned15Feature).evaluate().isEmpty ||
                  find.byType(LinearProgressIndicator).evaluate().isNotEmpty);
          i++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump(const Duration(milliseconds: 1));
        }
        expect(
          factory.unexpectedOtherWrites,
          0,
          reason:
              'No fallback/ordinary/unknown-path writer during owned15 resolution',
        );
        expect(find.byType(Owned15Feature), findsOneWidget);
        expect(find.byType(HomePage), findsNothing);
        expect(find.byType(NoteEditorPage), findsNothing);
        feature = tester.widget<Owned15Feature>(find.byType(Owned15Feature));
        final owner = feature.owner;
        final before = await tester.runAsync(
          () => owner.exclusiveSnapshot(
            (db) => OwnedGeneration15SchemaGate().rowDigests(db),
          ),
        );
        var oldCreatorCalls = 0;
        // Same production gate called at both Root _resourceCreator and
        // _createOwnedArticle, using the real Root-owned sealed capability.
        expect(
          () => RootLocalCreationDispatch.dispatch<Object?>(
            resolved: null,
            owned: owner,
            create: (_) {
              oldCreatorCalls++;
              return null;
            },
          ),
          throwsA(isA<LocalCreationUnavailable>()),
        );
        expect(oldCreatorCalls, 0);
        expect(feature.openCreation, isNotNull);
        expect(feature.openCreationRecovery, isNotNull);
        const recoveryChannel = MethodChannel('bookstark/recovery_storage');
        const complexChannel = MethodChannel('bookstark/complex_recovery');
        const secureChannel = MethodChannel('bookstark/asset_secure_window');
        messenger.setMockMethodCallHandler(recoveryChannel, (call) async {
          if (call.method == 'localMetadata') {
            return {
              'format': 1,
              'secureKeys': <String>[],
              'htmlKeys': <String>[],
              'overflow': false,
              'valuesIncluded': false,
            };
          }
          if (call.method == 'flush') return true;
          throw StateError('No unlisted recovery operation');
        });
        messenger.setMockMethodCallHandler(complexChannel, (call) async {
          if (call.method == 'metadata') {
            return {
              'format': 1,
              'keys': <String>[],
              'unknownFiles': 0,
              'activeTransfers': 0,
              'overflow': false,
              'valuesIncluded': false,
            };
          }
          throw StateError('No complex mutation');
        });
        messenger.setMockMethodCallHandler(secureChannel, (call) async {
          if (call.method == 'acquire' || call.method == 'release') return true;
          throw StateError('No unlisted secure-window operation');
        });
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        try {
          final opening = feature.openCreation!();
          for (
            var i = 0;
            i < 400 &&
                find.byType(Owned15CreationTargetDialog).evaluate().isEmpty;
            i++
          ) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 2)),
            );
            await tester.pump(const Duration(milliseconds: 1));
          }
          expect(find.byType(Owned15CreationTargetDialog), findsOneWidget);
          expect(find.byType(NoteEditorPage), findsNothing);
          final cancel = find.descendant(
            of: find.byType(Owned15CreationTargetDialog),
            matching: find.text('取消'),
          );
          await tester.ensureVisible(cancel);
          await tester.pumpAndSettle();
          await tester.tap(cancel.hitTestable());
          await tester.pumpAndSettle();
          await tester.runAsync(() => opening);
          // Recovery-only with no actual operation never opens a fresh editor.
          await tester.runAsync(feature.openCreationRecovery!);
          await tester.pump();
          expect(find.byType(Owned15CreationTargetDialog), findsNothing);
          expect(find.byType(NoteEditorPage), findsNothing);
        } finally {
          messenger.setMockMethodCallHandler(recoveryChannel, null);
          messenger.setMockMethodCallHandler(complexChannel, null);
          messenger.setMockMethodCallHandler(secureChannel, null);
          debugDefaultTargetPlatformOverride = TargetPlatform.linux;
        }
        final after = await tester.runAsync(
          () => owner.exclusiveSnapshot(
            (db) => OwnedGeneration15SchemaGate().rowDigests(db),
          ),
        );
        expect(after, before);
        expect(factory.legacyWrites, 0);
        expect(factory.activeVersions, isNotEmpty);
        expect(factory.activeVersions, everyElement(isNull));
        expect(mutations, isEmpty);
        expect(
          await const FlutterSecureStorage().read(key: draftKey),
          'retained fixture draft',
        );
        expect(tester.takeException(), isNull);
      } finally {
        if (feature != null) await tester.runAsync(feature.owner.retire);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        messenger.setMockMethodCallHandler(pathChannel, null);
        messenger.setMockMethodCallHandler(control, null);
        messenger.setMockMethodCallHandler(crypto, null);
        debugDefaultTargetPlatformOverride = oldPlatform;
        await tester.runAsync(() => root.delete(recursive: true));
      }
    },
  );
}
