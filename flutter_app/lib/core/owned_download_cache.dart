import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:path/path.dart' as paths;

/// Deliberately separate from historical unmarked download and picker caches.
/// A cache entry is never eligible while its lease is alive.
class OwnedDownloadCache {
  OwnedDownloadCache(this.temporaryDirectory);
  final Directory temporaryDirectory;
  static final Map<String, _CacheGate> _gates = {};
  static final Random _random = Random.secure();
  static String _identity() => List.generate(
    16,
    (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  static final String _process = _identity();
  static const _marker = '.bookstark-cache-owner-v1.json';
  static final _id = RegExp(r'^[a-f0-9]{32}$');
  static final _payload = RegExp(r'^(partial|file\.[A-Za-z0-9]{1,12})$');

  Future<Directory> _root() async {
    final canonical = await temporaryDirectory.resolveSymbolicLinks();
    final root = Directory(
      paths.join(canonical, 'bookstark-download-cache-v1'),
    );
    final type = await FileSystemEntity.type(root.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) await root.create();
    if (await FileSystemEntity.type(root.path, followLinks: false) !=
            FileSystemEntityType.directory ||
        await root.resolveSymbolicLinks() != root.path) {
      throw const FileSystemException('Owned cache root is unavailable');
    }
    return root;
  }

  Future<T> _exclusive<T>(
    Future<T> Function(Directory, _CacheGate) work,
  ) async {
    final root = await _root();
    final gate = _gates.putIfAbsent(root.path, _CacheGate.new);
    final result = gate.tail.then((_) => work(root, gate));
    gate.tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<OwnedDownloadLease> create(String kind) => _exclusive((
    root,
    gate,
  ) async {
    if (!{'drive', 'remote', 'dav'}.contains(kind)) {
      throw ArgumentError.value(kind, 'kind');
    }
    String id;
    Directory directory;
    do {
      id = _identity();
      directory = Directory(paths.join(root.path, id));
    } while (await FileSystemEntity.type(directory.path, followLinks: false) !=
        FileSystemEntityType.notFound);
    gate.active.add(id);
    try {
      await directory.create();
      await File(paths.join(directory.path, _marker)).writeAsString(
        jsonEncode({'format': 1, 'id': id, 'kind': kind, 'process': _process}),
        flush: true,
      );
      return OwnedDownloadLease._(this, directory, id);
    } catch (_) {
      // A failed unmarked creation is retained rather than recursively deleting
      // an unexpected path. It is not advertised as clearable cache.
      gate.active.remove(id);
      rethrow;
    }
  });

  Future<_OwnedEntry?> _inspect(Directory root, Directory directory) async {
    final id = paths.basename(directory.path);
    if (!_id.hasMatch(id) ||
        paths.dirname(directory.path) != root.path ||
        await FileSystemEntity.type(directory.path, followLinks: false) !=
            FileSystemEntityType.directory ||
        await directory.resolveSymbolicLinks() != directory.path) {
      return null;
    }
    final files = <File>[];
    var bytes = 0;
    Map<String, Object?>? marker;
    await for (final entity in directory.list(followLinks: false)) {
      if (files.length >= 3 ||
          await FileSystemEntity.type(entity.path, followLinks: false) !=
              FileSystemEntityType.file) {
        return null;
      }
      final name = paths.basename(entity.path);
      final file = File(entity.path);
      final stat = await file.stat();
      if (name == _marker) {
        if (stat.size > 512) return null;
        final reader = await file.open();
        late List<int> markerBytes;
        try {
          markerBytes = await reader.read(513);
        } finally {
          await reader.close();
        }
        if (markerBytes.length > 512) return null;
        final value = jsonDecode(utf8.decode(markerBytes));
        if (value is! Map<String, dynamic> ||
            value.keys.toSet().difference({
              'format',
              'id',
              'kind',
              'process',
            }).isNotEmpty ||
            value.length != 4 ||
            value['format'] != 1 ||
            value['id'] != id ||
            !{'drive', 'remote', 'dav'}.contains(value['kind']) ||
            value['process'] is! String ||
            !_id.hasMatch(value['process'] as String)) {
          return null;
        }
        marker = value;
      } else {
        if (!_payload.hasMatch(name)) return null;
        bytes += stat.size;
      }
      files.add(file);
    }
    if (marker == null) return null;
    return _OwnedEntry(directory, files, bytes);
  }

  Future<OwnedCacheResult> inspect() => _visit(clear: false);
  Future<OwnedCacheResult> clear() => _visit(clear: true);

  Future<OwnedCacheResult> _visit({required bool clear}) =>
      _exclusive((root, gate) async {
        var eligibleBytes = 0, removedBytes = 0, eligible = 0;
        var active = 0, skipped = 0, failed = 0, visited = 0;
        await for (final entity in root.list(followLinks: false)) {
          if (++visited > 4096) {
            skipped++;
            break;
          }
          final id = paths.basename(entity.path);
          if (gate.active.contains(id)) {
            active++;
            continue;
          }
          try {
            final entry = await _inspect(root, Directory(entity.path));
            if (entry == null) {
              skipped++;
              continue;
            }
            eligible++;
            eligibleBytes += entry.bytes;
            if (!clear) continue;
            // Recheck the marker/shape immediately before deleting only known
            // regular files; never call recursive delete on scanned entries.
            final current = await _inspect(root, entry.directory);
            if (current == null ||
                current.bytes != entry.bytes ||
                current.files
                    .map((f) => f.path)
                    .toSet()
                    .difference(entry.files.map((f) => f.path).toSet())
                    .isNotEmpty ||
                current.files.length != entry.files.length) {
              failed++;
              continue;
            }
            // Keep the ownership marker until every payload deletion succeeds.
            for (final file in current.files.where(
              (file) => paths.basename(file.path) != _marker,
            )) {
              final size = await file.length();
              await file.delete();
              removedBytes += size;
            }
            await File(paths.join(entry.directory.path, _marker)).delete();
            await entry.directory.delete();
          } catch (_) {
            failed++;
          }
        }
        return OwnedCacheResult(
          eligibleBytes: eligibleBytes,
          removedBytes: removedBytes,
          eligibleEntries: eligible,
          activeEntries: active,
          skippedEntries: skipped,
          failedEntries: failed,
        );
      });

  Future<void> _close(OwnedDownloadLease lease) => _exclusive((
    root,
    gate,
  ) async {
    if (!gate.active.contains(lease.id)) return;
    // Only this creator can close the lease. A failure leaves an inactive
    // marked entry for a later explicit cleanup, without touching other files.
    try {
      final entry = await _inspect(root, lease.directory);
      if (entry == null) {
        throw const FileSystemException('Owned cache entry changed');
      }
      for (final file in entry.files.where(
        (file) => paths.basename(file.path) != _marker,
      )) {
        await file.delete();
      }
      await File(paths.join(lease.directory.path, _marker)).delete();
      await lease.directory.delete();
    } finally {
      gate.active.remove(lease.id);
    }
  });
}

class OwnedDownloadLease {
  OwnedDownloadLease._(this._owner, this.directory, this.id);
  final OwnedDownloadCache _owner;
  final Directory directory;
  final String id;
  Future<void>? _closing;
  Future<void> close() => _closing ??= _owner._close(this);
}

class OwnedCacheResult {
  const OwnedCacheResult({
    required this.eligibleBytes,
    required this.removedBytes,
    required this.eligibleEntries,
    required this.activeEntries,
    required this.skippedEntries,
    required this.failedEntries,
  });
  final int eligibleBytes, removedBytes, eligibleEntries;
  final int activeEntries, skippedEntries, failedEntries;
}

class _CacheGate {
  Future<void> tail = Future<void>.value();
  final Set<String> active = {};
}

class _OwnedEntry {
  _OwnedEntry(this.directory, this.files, this.bytes);
  final Directory directory;
  final List<File> files;
  final int bytes;
}
