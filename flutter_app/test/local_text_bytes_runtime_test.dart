import 'dart:ffi';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/local_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/open.dart';
import '../tool/local_text_bytes_scenario.dart';

void main() {
  test(
    'production note, HTML, complex and document paths retain exact UTF8 across reopen',
    () async {
      sqfliteFfiInit();
      if (Platform.isLinux) {
        open.overrideFor(
          OperatingSystem.linux,
          () => DynamicLibrary.open('libsqlite3.so.0'),
        );
      }
      final root =
          Platform.environment['BOOKSTARK_APK_TEST_ROOT'] ??
          Directory.systemTemp.path;
      final dir = await Directory(root).createTemp('exact-text-runtime-');
      var store = LocalStore(
        path: '${dir.path}/runtime.db',
        factory: databaseFactoryFfiNoIsolate,
      );
      try {
        final built = await localTextBytesScenario(store, build: true);
        expect(built['schema'], 16);
        expect(built['verifiedExactTextCells'], 6);
        expect(built['staleComplexSaveRejected'], true);
        await store.close();
        store = LocalStore(
          path: '${dir.path}/runtime.db',
          factory: databaseFactoryFfiNoIsolate,
        );
        final cold = await localTextBytesScenario(store, build: false);
        expect(cold['passed'], true);
        expect(cold['schema'], 16);
        expect(cold['bodySha256'], built['bodySha256']);
        expect(cold['htmlSha256'], built['htmlSha256']);
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );
}
