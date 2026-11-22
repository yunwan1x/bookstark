import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:bookstark_flutter/core/attachments.dart';
import 'package:bookstark_flutter/core/local_applied_backup_review.dart';
import 'package:bookstark_flutter/core/local_backup_exporter.dart';
import 'package:bookstark_flutter/core/local_data_paths.dart';
import 'package:bookstark_flutter/core/local_generation_state.dart';
import 'package:bookstark_flutter/core/local_legacy_format_selection.dart';
import 'package:bookstark_flutter/core/local_legacy_go_export.dart';
import 'package:bookstark_flutter/core/local_legacy_zip_stage.dart';
import 'package:bookstark_flutter/core/local_restore_coordinator.dart';
import 'package:bookstark_flutter/core/local_retained_backup.dart';
import 'package:bookstark_flutter/core/local_storage_session.dart';
import 'package:bookstark_flutter/core/local_store.dart';
import 'package:bookstark_flutter/core/native_local_content_crypto.dart';
import 'package:bookstark_flutter/core/native_local_data_control.dart';
import 'package:bookstark_flutter/core/owned_generation15_activation_preparation.dart';
import 'package:bookstark_flutter/core/resolved_local_storage.dart';

// Host integration only: native durable-control/file-review ACKs are simulated.
// ZIP inspection, conversion, SQLite, retention, review and writable open are real.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  if (Platform.isLinux) {
    open.overrideFor(
      OperatingSystem.linux,
      () => DynamicLibrary.open('libsqlite3.so.0'),
    );
  }
  test(
    'normal legacy ZIP activates and reopens the exact selected note body',
    () async {
      final base = Directory(
        Platform.environment['BOOKSTARK_APK_TEST_ROOT'] ??
            '${Directory.systemTemp.path}/bookstark-unit',
      );
      await base.create(recursive: true);
      final temp = await base.createTemp('legacy44-normal-');
      final root = Directory(await temp.resolveSymbolicLinks());
      final support = await Directory('${root.path}/support').create();
      final cache = await Directory('${root.path}/cache').create();
      final work = await Directory('${root.path}/work').create();
      const channel = MethodChannel('bookstark/legacy44-normal-core-test');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'drain') return {'format': 1, 'drained': true};
        throw StateError(
          'Unprotected normal ZIP must not invoke content crypto',
        );
      });
      LocalStore? sourceStore;
      OwnedGeneration15ActivationPreparation? preparation;
      ResolvedLocalStorage? live;
      try {
        final layout = LocalDataPaths.legacy(
          databasePath: '${support.path}/legacy.db',
          privateSupport: support,
        );
        final source = LocalStore(
          path: layout.databasePath,
          factory: databaseFactoryFfiNoIsolate,
          dataPaths: layout,
        );
        sourceStore = source;
        await source.database;
        await source.createNote('Pre-activation source', 'Retain this source');
        await layout.attachments.create(recursive: true);
        await layout.driveBlobs.create(recursive: true);
        String? pointerRaw, intentRaw, retentionRaw;
        final mutations = <String>[];
        Map<String, Object?> state() => {
          'format': 1,
          'pointerRaw': pointerRaw,
          'intentRaw': intentRaw,
          'currentRetentionRaw': pointerRaw == null ? retentionRaw : null,
          'sourceRetentionRaw': intentRaw == null ? null : retentionRaw,
          'metadataOnly': true,
        };
        final control = NativeLocalDataControl(
          invoke: (method, args) async {
            if (method == 'space')
              return {'format': 1, 'availableBytes': 1 << 40};
            if (method == 'readState') return state();
            if (method == 'reviewApplied') {
              final intent = LocalRestoreIntent.parse(intentRaw!);
              final target = LocalGenerationPointer.parse(
                intent.targetPointerRaw,
              );
              final targetLayout = LocalDataPaths.generation(
                id: target.generation,
                privateSupport: support,
              );
              return {
                'format': 1,
                'operationId': intent.operationId,
                'pointerSHA256': localPointerSHA256(intent.targetPointerRaw),
                'intentSHA256': localPointerSHA256(intent.encode()),
                'manifestRaw': await File(
                  '${targetLayout.controlRoot.path}/generations/${target.generation}/_manifest.json',
                ).readAsString(),
                'metadataOnly': true,
              };
            }
            mutations.add(method);
            late String action;
            late LocalRestoreIntent intent;
            if (method == 'prepareRestore') {
              intentRaw = args!['intentRaw'] as String;
              intent = LocalRestoreIntent.parse(intentRaw!);
              retentionRaw = LocalRetention(
                id: intent.retainedId,
                sourcePointerSHA256: intent.sourcePointerSHA256,
                sourceGeneration: 'legacy',
                manifestSHA256: intent.retainedManifestSHA256,
              ).encode();
              action = 'prepared';
            } else if (method == 'commitRestore') {
              intent = LocalRestoreIntent.parse(intentRaw!);
              pointerRaw = intent.targetPointerRaw;
              action = 'switched';
            } else if (method == 'acknowledgeApplied') {
              intent = LocalRestoreIntent.parse(intentRaw!);
              intentRaw = null;
              action = 'acknowledged';
            } else {
              throw StateError('Unexpected native boundary method');
            }
            return {
              'format': 1,
              'action': action,
              'id': intent.operationId,
              'durable': true,
              'state': state(),
            };
          },
        );
        final session = LocalStorageSession(
          control: control,
          privateSupport: support,
          legacyDatabasePath: layout.databasePath,
          factory: databaseFactoryFfiNoIsolate,
        );
        final input = File(
          'test/fixtures/legacy_zip/identity-upload-shared-thumb.zip',
        );
        final zip = await LegacyZipStage.inspect(
          input,
          privateParent: root,
          expectedSha256: (await sha256.bind(input.openRead()).first)
              .toString(),
          availableBytes: () async => 1 << 40,
        );
        final inspected = await LegacyGoExport.inspect(zip);
        final formats = LegacyFormatSource.fromInspection(
          inspected,
          scopeKey: 'b' * 32,
        );
        final selected = formats.items.firstWhere(
          (item) => item.collection == 'note' && !item.isProtected,
        );
        final selection = LegacyFormatSelection(
          formats,
          choices: {
            for (final item in formats.items)
              item.id: item.collection == 'article'
                  ? LegacyContentFormat.html
                  : LegacyContentFormat.markdown,
          },
        );
        final prepare = OwnedGeneration15ActivationPreparation(
          zip: zip,
          selection: selection,
          session: session,
          privateCache: cache,
          workspace: work,
          isCurrentScope: () => true,
        );
        preparation = prepare;
        final candidate = await prepare.prepare(AttachmentCancellation());
        expect(candidate.manifest.databaseSchema, 15);
        expect(mutations, isEmpty);
        final coordinator = LocalRestoreCoordinator(
          retainedBuilder: LocalRetainedBackupBuilder(
            exporter: LocalBackupExporter(
              store: source,
              attachments: layout.attachments,
              driveBlobs: layout.driveBlobs,
              workspace: Directory('${root.path}/retention-exports'),
              checkPendingRecovery: () async {},
            ),
            control: control,
            identity: () => 'c' * 32,
          ),
          identity: () => 'd' * 32,
        );
        final switched = await coordinator.apply(candidate);
        expect(switched.action, 'switched');
        expect(source.maintenance.retired, isTrue);
        expect(candidate.preservedForActivation, isTrue);
        final review = await LocalAppliedBackupReviewer(
          control: control,
          privateSupport: support,
          privateCache: cache,
          factory: databaseFactoryFfiNoIsolate,
        ).read(switched.state);
        expect(review.manifest.databaseSchema, 15);
        await control.acknowledgeApplied(review.intent);
        expect(mutations, [
          'prepareRestore',
          'commitRestore',
          'acknowledgeApplied',
        ]);
        int? openedId;
        for (var pass = 0; pass < 2; pass++) {
          final resolved = await ResolvedLocalStorage.open(
            session: session,
            verificationWorkspace: await Directory(
              '${support.path}/verify-$pass',
            ).create(),
            isCurrentScope: () => true,
            crypto: NativeLocalContentCrypto(channel: channel),
          );
          live = resolved;
          expect(resolved, isA<Owned15ResolvedLocalStorage>());
          final owner = (resolved as Owned15ResolvedLocalStorage).owner;
          expect(owner.current, isTrue);
          final rows = await owner.exclusiveSnapshot(
            (db) => db.rawQuery(
              'SELECT id, CAST(content AS BLOB) AS content_bytes FROM notes '
              'WHERE title=? AND collection=? AND deleted=0',
              [selected.title, selected.collection],
            ),
          );
          expect(rows, hasLength(1));
          final id = rows.single['id'] as int;
          openedId ??= id;
          expect(id, openedId);
          // SQLite TEXT decoding in the host FFI driver consumes a leading
          // UTF-8 BOM. Assert the stored bytes, then the production reader below.
          expect(
            rows.single['content_bytes'],
            utf8.encode(selected.originalBody),
          );
          final handle = await owner.content.open(
            id,
            collection: selected.collection,
          );
          expect(handle.source, selected.originalBody);
          expect(handle.metadata.format, LegacyContentFormat.markdown);
          await resolved.retire();
          live = null;
        }
      } finally {
        await live?.retire();
        await preparation?.retire();
        if (sourceStore != null && !sourceStore.maintenance.retired) {
          await sourceStore.close();
        }
        messenger.setMockMethodCallHandler(channel, null);
        await root.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
