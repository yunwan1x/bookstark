import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:bookstark_flutter/core/local_data_paths.dart';
import 'package:bookstark_flutter/core/local_generation_state.dart';
import 'package:bookstark_flutter/core/local_store.dart';

LocalGenerationObservation observation({String? pointer, String? retention}) =>
    LocalGenerationObservation.inspect(
      pointerRaw: pointer,
      intentRaw: null,
      currentRetentionRaw: retention,
      sourceRetentionRaw: null,
    );

void main() {
  test(
    'legacy database spelling preserves existing recovery scope identity',
    () {
      const original = '/data/user/0/owned/databases/bookstark-flutter.db';
      final layout = LocalDataPaths.legacy(
        databasePath: original,
        privateSupport: Directory('/data/data/owned/files'),
      );
      expect(layout.databasePath, original);
      expect(layout.draftNamespace, 'local');
      expect(layout.attachments.path, '/data/data/owned/files/attachments');
      expect(layout.driveBlobs.path, '/data/data/owned/files/drive-blobs');
    },
  );

  test(
    'new generation keeps DB, attachments, drive and draft scopes together',
    () {
      final id = 'a' * 32;
      final layout = LocalDataPaths.generation(
        id: id,
        privateSupport: Directory('/private/files'),
      );
      final base = '/private/files/local-data-v1/generations/$id';
      expect(layout.databasePath, '$base/database/content.db');
      expect(layout.attachments.path, '$base/attachments');
      expect(layout.driveBlobs.path, '$base/drive-blobs');
      expect(layout.draftNamespace, 'local-generation:$id');
      expect(layout.controlRoot.path, '/private/files/local-data-v1');
    },
  );

  test('retained but uncommitted data cannot become a writable layout', () {
    final lock = LocalRetention(
      id: 'a' * 32,
      sourcePointerSHA256: localPointerSHA256(null),
      sourceGeneration: 'legacy',
      manifestSHA256: 'b' * 64,
    );
    expect(
      () => LocalDataPaths.fromObservation(
        observation: observation(retention: lock.encode()),
        legacyDatabasePath: '/private/databases/old.db',
        privateSupport: Directory('/private/files'),
      ),
      throwsA(isA<LocalDataNeedsReview>()),
    );
  });

  test(
    'ready active pointer chooses its generation without fallback to legacy',
    () {
      final pointer = LocalGenerationPointer(
        generation: 'a' * 32,
        epoch: 1,
        activationId: 'b' * 32,
        sourceSHA256: 'c' * 64,
      );
      final layout = LocalDataPaths.fromObservation(
        observation: observation(pointer: pointer.encode()),
        legacyDatabasePath: '/private/databases/old.db',
        privateSupport: Directory('/private/files'),
      );
      expect(layout.generationId, 'a' * 32);
      expect(layout.databasePath, contains('/generations/'));
      expect(layout.databasePath, endsWith('/database/content.db'));
    },
  );

  test(
    'mismatched database and blob roots are rejected before opening SQL',
    () {
      final layout = LocalDataPaths.legacy(
        databasePath: '/private/databases/old.db',
        privateSupport: Directory('/private/files'),
      );
      expect(
        () => LocalStore(
          path: '/private/databases/other.db',
          dataPaths: layout,
          factory: databaseFactoryFfiNoIsolate,
        ),
        throwsArgumentError,
      );
      final store = LocalStore(
        path: layout.databasePath,
        dataPaths: layout,
        factory: databaseFactoryFfiNoIsolate,
      );
      expect(identical(store.dataPaths, layout), isTrue);
    },
  );

  test(
    'generation IDs cannot supply paths and private roots must be absolute',
    () {
      for (final id in ['../outside', 'A' * 32, 'a/b', '']) {
        expect(
          () => LocalDataPaths.generation(
            id: id,
            privateSupport: Directory('/private/files'),
          ),
          throwsFormatException,
        );
      }
      expect(
        () => LocalDataPaths.legacy(
          databasePath: 'relative.db',
          privateSupport: Directory('/private/files'),
        ),
        throwsFormatException,
      );
      expect(
        () => LocalDataPaths.generation(
          id: 'a' * 32,
          privateSupport: Directory('relative'),
        ),
        throwsFormatException,
      );
    },
  );
}
