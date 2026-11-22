// Creates synthetic data for the isolated Android emulator only. Not an APK
// entry point, not imported by lib/, never reads user content or credentials.
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:bookstark_flutter/core/local_drive_repository.dart';
import 'package:bookstark_flutter/core/local_store.dart';
import 'package:bookstark_flutter/core/drive_source.dart';
import '../test/fixtures/native_pdf.dart';

void main() {
  test(
    'prepare real SQLite and private blob files for Android-only native validation',
    () async {
      sqfliteFfiInit();
      if (Platform.isLinux) {
        open.overrideFor(
          OperatingSystem.linux,
          () => DynamicLibrary.open('libsqlite3.so.0'),
        );
      }
      final base = Directory(
        '/vol1/1000/wy/photos-apk-test/bookstark-flutter/android-native-seed',
      );
      if (await base.exists()) {
        throw StateError(
          'Preserve existing emulator seed; inspect before regenerating',
        );
      }
      await Directory('${base.path}/databases').create(recursive: true);
      final store = LocalStore(
        path: '${base.path}/databases/bookstark-flutter.db',
        factory: databaseFactoryFfiNoIsolate,
      );
      final drive = LocalDriveRepository(
        store,
        Directory('${base.path}/files/drive-blobs'),
      );
      final sources = Directory(
        '/vol1/1000/wy/photos-apk-test/bookstark-flutter/android-native-sources',
      );
      final pdf = File('${sources.path}/native-proof.pdf');
      await pdf.writeAsBytes(nativePdfFixture(), flush: true);
      final markdown = File('${sources.path}/native-markdown.md');
      await markdown.writeAsString(
        '# Android 原生验证\n\n**粗体文字**、列表和真实附件。\n\n- PDF：原生页面渲染\n- 音视频：实际设备解码\n- 保存：系统文件选择器\n\n![示意图](native-diagram.svg)\n',
        flush: true,
      );
      final svg = File('${sources.path}/native-diagram.svg');
      await svg.writeAsString(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 320 180"><rect width="320" height="180" fill="#dbeafe"/><rect x="24" y="40" width="100" height="100" rx="8" fill="#2563eb"/><circle cx="240" cy="90" r="48" fill="#22c55e"/></svg>',
        flush: true,
      );
      await drive.mkdir('', 'Android 验收');
      for (final name in [
        'native-proof.pdf',
        'native-markdown.md',
        'native-diagram.svg',
        'native-video.mp4',
        'native-audio.mp3',
      ]) {
        final source = await DriveSourceSnapshot.prepare(
          XFile('${sources.path}/$name'),
          maxBytes: 10 * 1024 * 1024,
        );
        final result = await drive.upload(source, target: 'Android 验收/$name');
        expect(result.node.size, await File('${sources.path}/$name').length());
      }
      await store.createNote(
        'Android Markdown 验证',
        '# 原生 Markdown\n\n这是**真实本地笔记**。\n\n- [x] SQLite 数据\n- [ ] Android 回归',
      );
      expect((await drive.list('Android 验收')).length, 5);
      drive.dispose();
      await store.close();
      await File('${base.path}/seed-manifest.json').writeAsString(
        jsonEncode({
          'purpose': 'isolated Android native validation only',
          'schema': 11,
          'synthetic': true,
          'files': 5,
        }),
      );
    },
  );
}
