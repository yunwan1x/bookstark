import 'dart:io';
import 'package:path/path.dart' as path;
import 'local_data_paths.dart';
import 'local_draft_namespace.dart';

/// Directory names only. No database, journal body or account value is read.
Future<Set<String>> localRecoveryNamespaces(LocalDataPaths layout) async {
  final namespaces = <String>{'local', layout.draftNamespace};
  final generations = Directory(
    path.join(layout.privateSupport.path, 'local-data-v1', 'generations'),
  );
  if (await FileSystemEntity.type(generations.path, followLinks: false) ==
      FileSystemEntityType.directory) {
    var count = 0;
    await for (final entry in generations.list(followLinks: false)) {
      if (++count > 32768) {
        throw const FormatException(
          'Local generation inspection limit reached',
        );
      }
      final id = entry.uri.pathSegments.where((part) => part.isNotEmpty).last;
      if (RegExp(r'^[a-f0-9]{32}$').hasMatch(id) &&
          await FileSystemEntity.type(entry.path, followLinks: false) ==
              FileSystemEntityType.directory) {
        namespaces.add(LocalDraftNamespace.generation(id));
      }
    }
  }
  return Set.unmodifiable(namespaces);
}
