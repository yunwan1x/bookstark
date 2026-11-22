import 'dart:ffi';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/open.dart';
import 'package:bookstark_flutter/core/attachments.dart';
import 'package:bookstark_flutter/core/local_legacy_format_selection.dart';
import 'package:bookstark_flutter/core/local_legacy_go_export.dart';
import 'package:bookstark_flutter/core/local_legacy_zip_stage.dart';
import 'package:bookstark_flutter/core/local_storage_session.dart';
import 'package:bookstark_flutter/core/native_local_data_control.dart';
import 'package:bookstark_flutter/core/owned_generation15_activation_preparation.dart';

void main() {
  late Directory root, support, cache, work;
  late OwnedGeneration15ActivationPreparation preparation;
  final calls = <String>[];
  bool current = true, failDiscard = false;
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
    root = await parent.createTemp('owned15-prepare-');
    support = await Directory('${root.path}/support').create();
    cache = await Directory('${root.path}/cache').create();
    work = await Directory('${root.path}/work').create();
    calls.clear();
    current = true;
    failDiscard = false;
    final file = File(
      'test/fixtures/legacy_zip/identity-upload-shared-thumb.zip',
    );
    final zip = await LegacyZipStage.inspect(
      file,
      privateParent: root,
      expectedSha256: (await sha256.bind(file.openRead()).first).toString(),
      availableBytes: () async => 4 * 1024 * 1024 * 1024,
    );
    final source = await LegacyGoExport.inspect(zip);
    final formats = LegacyFormatSource.fromInspection(
      source,
      scopeKey: 'b' * 32,
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
    final control = NativeLocalDataControl(
      invoke: (name, args) async {
        calls.add(name);
        if (name == 'space') {
          return {'format': 1, 'availableBytes': 4 * 1024 * 1024 * 1024};
        }
        if (name == 'discardCandidate') {
          if (failDiscard) throw StateError('Temporary discard failure');
          final id = args!['generation'] as String;
          expect(RegExp(r'^[a-f0-9]{32}$').hasMatch(id), isTrue);
          await Directory(
            '${support.path}/local-data-v1/generations/$id',
          ).delete(recursive: true);
          return {
            'format': 1,
            'action': 'discarded',
            'id': id,
            'durable': true,
            'state': {
              'format': 1,
              'pointerRaw': null,
              'intentRaw': null,
              'currentRetentionRaw': null,
              'sourceRetentionRaw': null,
              'metadataOnly': true,
            },
          };
        }
        throw StateError(
          'Preparation cannot prepare/commit/acknowledge active data',
        );
      },
    );
    preparation = OwnedGeneration15ActivationPreparation(
      zip: zip,
      selection: selection,
      session: LocalStorageSession(
        control: control,
        privateSupport: support,
        legacyDatabasePath: '${support.path}/legacy.db',
        factory: databaseFactoryFfiNoIsolate,
      ),
      privateCache: cache,
      workspace: work,
      isCurrentScope: () => current,
    );
  });
  tearDown(() async {
    failDiscard = false;
    await preparation.retire();
    await root.delete(recursive: true);
  });
  test(
    'one source selection produces one actual candidate and clears owned temporary copies',
    () async {
      final first = preparation.prepare(AttachmentCancellation());
      final duplicate = preparation.prepare(AttachmentCancellation());
      expect(identical(first, duplicate), isTrue);
      final candidate = await first;
      expect(candidate.manifest.databaseSchema, 15);
      expect(candidate.preservedForActivation, isFalse);
      expect(calls.where((name) => name != 'space'), isEmpty);
      expect(
        await Directory('${cache.path}/local-backup-inbox-v1').list().toList(),
        isEmpty,
      );
      expect(
        (await work.list().toList()).where(
          (entry) => entry.uri.pathSegments
              .where((s) => s.isNotEmpty)
              .last
              .startsWith('owned15-stage-'),
        ),
        isEmpty,
      );
      await preparation.retire();
      expect(calls.where((name) => name == 'discardCandidate').length, 1);
      expect(
        await Directory(
          '${candidate.layout.privateSupport.path}/local-data-v1/generations/${candidate.id}',
        ).exists(),
        isFalse,
      );
    },
  );
  test(
    'native-boundary preservation flag retains candidate rather than claiming commit',
    () async {
      final candidate = await preparation.prepare(AttachmentCancellation());
      candidate.preserveForActivation();
      current = false;
      await preparation.retire();
      expect(candidate.preservedForActivation, isTrue);
      expect(calls.where((name) => name != 'space'), isEmpty);
      expect(await File(candidate.layout.databasePath).exists(), isTrue);
    },
  );
  test(
    'initial cancellation has no space/native mutation and no candidate',
    () async {
      final cancellation = AttachmentCancellation()..cancel();
      await expectLater(
        preparation.prepare(cancellation),
        throwsA(isA<AttachmentCancelled>()),
      );
      expect(calls, isEmpty);
      await preparation.retire();
      expect(calls, isEmpty);
    },
  );
  test(
    'failed cleanup retains lease and explicit retry discards only the same candidate',
    () async {
      final candidate = await preparation.prepare(AttachmentCancellation());
      failDiscard = true;
      await expectLater(
        preparation.retire(),
        throwsA(isA<LocalControlUnconfirmed>()),
      );
      expect(await File(candidate.layout.databasePath).exists(), isTrue);
      failDiscard = false;
      await preparation.retire();
      expect(calls.where((name) => name == 'discardCandidate').length, 2);
      expect(await File(candidate.layout.databasePath).exists(), isFalse);
      expect(
        calls.where((name) => !{'space', 'discardCandidate'}.contains(name)),
        isEmpty,
      );
    },
  );
}
