// Headless synthetic acceptance entrypoint; never production main.dart.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as paths;
import 'package:path_provider/path_provider.dart';
import 'package:bookstark_flutter/core/local_store.dart';
import 'local_text_bytes_scenario.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SizedBox.shrink());
  Directory? root;
  LocalStore? store;
  var phase = 'startup';
  var owned = false;
  try {
    final support = await getApplicationSupportDirectory();
    root = Directory(paths.join(support.path, 'local-text-bytes-probe'));
    if (await FileSystemEntity.type(root.path, followLinks: false) !=
            FileSystemEntityType.directory ||
        !(await root.resolveSymbolicLinks()).startsWith(
          (await support.resolveSymbolicLinks()) + paths.separator,
        )) {
      throw StateError('Owned test root unavailable');
    }
    owned = true;
    final markerFile = File(paths.join(root.path, 'owned.json'));
    if (await FileSystemEntity.type(markerFile.path, followLinks: false) !=
            FileSystemEntityType.file ||
        await markerFile.length() > 4096) {
      throw StateError('Owned marker invalid');
    }
    final marker = jsonDecode(await markerFile.readAsString());
    if (marker is! Map ||
        marker.length != 4 ||
        marker['format'] != 1 ||
        marker['synthetic_only'] != true ||
        !{'build', 'verify'}.contains(marker['phase']) ||
        marker['nonce'] is! String ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(marker['nonce'] as String)) {
      throw StateError('Owned marker invalid');
    }
    phase = marker['phase'] as String;
    final dbPath = paths.join(root.path, 'runtime.db');
    final type = await FileSystemEntity.type(dbPath, followLinks: false);
    if (phase == 'build' && type != FileSystemEntityType.notFound ||
        phase == 'verify' && type != FileSystemEntityType.file) {
      throw StateError('Owned database phase invalid');
    }
    if (phase == 'verify') {
      final prior = jsonDecode(
        await File(paths.join(root.path, 'build-proof.json')).readAsString(),
      );
      if (prior['passed'] != true || prior['nonce'] != marker['nonce']) {
        throw StateError('Owned prior proof invalid');
      }
    }
    store = LocalStore(path: dbPath);
    final result = await localTextBytesScenario(store, build: phase == 'build');
    await store.close();
    store = null;
    final output = File(
      paths.join(
        root.path,
        phase == 'build' ? 'build-proof.json' : 'cold-proof.json',
      ),
    );
    if (await output.exists()) throw StateError('Owned result already exists');
    await output.writeAsString(
      jsonEncode({
        ...result,
        'phase': phase,
        'nonce': marker['nonce'],
        'coldProcess': phase == 'verify',
      }),
      flush: true,
    );
  } catch (error) {
    if (owned && root != null) {
      await File(paths.join(root.path, 'failure-$phase.json')).writeAsString(
        jsonEncode({
          'passed': false,
          'error_type': error.runtimeType.toString(),
          'source_values_redacted': true,
        }),
        flush: true,
      );
    }
  } finally {
    await store?.close();
  }
}
