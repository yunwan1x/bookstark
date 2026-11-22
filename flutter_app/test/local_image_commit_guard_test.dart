import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:bookstark_flutter/core/local_store.dart';
import 'package:bookstark_flutter/core/local_attachments.dart';
import 'package:bookstark_flutter/core/local_images_repository.dart';
import 'package:bookstark_flutter/core/images_repository.dart';

void main() {
  sqfliteFfiInit();
  if (Platform.isLinux) {
    open.overrideFor(
      OperatingSystem.linux,
      () => DynamicLibrary.open('libsqlite3.so.0'),
    );
  }
  test(
    'scope retires during dimensions await: no SQL insert, staged file compensated',
    () async {
      final root = await Directory.systemTemp.createTemp('image-owner-commit-');
      final store = LocalStore(
        path: '${root.path}/content.db',
        factory: databaseFactoryFfiNoIsolate,
      );
      final media = LocalAttachments(Directory('${root.path}/attachments'));
      var current = true;
      final entered = Completer<void>(), dimensions = Completer<(int, int)>();
      final repo = LocalImagesRepository(
        store,
        media,
        isCurrentScope: () => current,
        dimensionsReader: (_) async {
          entered.complete();
          return dimensions.future;
        },
      );
      try {
        final payload = ImageUploadPayload.fromBytes(
          name: 'fixture.png',
          category: ImageCategory.note,
          bytes: Uint8List.fromList(
            base64Decode(
              'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/l9sAAAAASUVORK5CYII=',
            ),
          ),
        );
        final save = repo.upload(payload);
        final expectation = expectLater(save, throwsStateError);
        await entered.future;
        current = false;
        dimensions.complete((1, 1));
        await expectation;
        expect(await (await store.database).query('local_images'), isEmpty);
        expect(await media.directory.list().toList(), isEmpty);
      } finally {
        repo.dispose();
        media.close();
        await store.close();
        await root.delete(recursive: true);
      }
    },
  );
}
