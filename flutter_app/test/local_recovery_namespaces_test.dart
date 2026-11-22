import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/local_data_paths.dart';
import 'package:bookstark_flutter/core/local_recovery_namespaces.dart';

void main() {
  late Directory root;
  setUp(() async {
    final base = Directory(
      Platform.environment['BOOKSTARK_APK_TEST_ROOT'] ??
          '${Directory.systemTemp.path}/bookstark-unit',
    );
    await base.create(recursive: true);
    root = await base.createTemp('recovery-namespaces-');
  });
  tearDown(() async => root.delete(recursive: true));

  test(
    'only owned generation directories enter archive scope; links and files are excluded',
    () async {
      final path = '${root.path}/local-data-v1/generations';
      await Directory(path).create(recursive: true);
      final valid = 'a' * 32, linked = 'b' * 32, file = 'c' * 32;
      await Directory('$path/$valid').create();
      final outside = await Directory('${root.path}/elsewhere').create();
      await Link('$path/$linked').create(outside.path);
      await File('$path/$file').writeAsString('not a directory');
      await Directory('$path/not-a-generation').create();
      final layout = LocalDataPaths.legacy(
        databasePath: '${root.path}/content.db',
        privateSupport: root,
      );
      expect(await localRecoveryNamespaces(layout), {
        'local',
        'local-generation:$valid',
      });
    },
  );

  test(
    'linked generations root is not followed; current scope remains explicit',
    () async {
      final outside = await Directory('${root.path}/elsewhere').create();
      await Directory('${outside.path}/${'d' * 32}').create();
      await Directory('${root.path}/local-data-v1').create();
      await Link('${root.path}/local-data-v1/generations').create(outside.path);
      final layout = LocalDataPaths.generation(
        id: 'e' * 32,
        privateSupport: root,
      );
      expect(await localRecoveryNamespaces(layout), {
        'local',
        'local-generation:${'e' * 32}',
      });
    },
  );
}
