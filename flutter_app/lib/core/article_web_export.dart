import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;

enum ArticleExportReason { receipt, missing, changed, retired }

final class ArticleExportFailure implements Exception {
  const ArticleExportFailure(this.reason);
  final ArticleExportReason reason;
}

final class ArticleWebExport {
  ArticleWebExport._(
    this.id,
    this.file,
    this.name,
    this.mime,
    this.bytes,
    this.sha256Hex,
  );
  final String id, name, mime, sha256Hex;
  final XFile file;
  final int bytes;
  static const maxBytes = 32 * 1024 * 1024;

  /// Only a bounded, completed native export under this app's trusted cache root.
  static Future<ArticleWebExport> verify({
    required Directory privateCache,
    required String lease,
    required Map<Object?, Object?> receipt,
    required bool Function() isCurrent,
  }) async {
    void current() {
      var valid = false;
      try {
        valid = isCurrent();
      } catch (_) {}
      if (!valid) throw const ArticleExportFailure(ArticleExportReason.retired);
    }

    current();
    final id = receipt['id'],
        size = receipt['bytes'],
        hash = receipt['sha256'],
        name = receipt['name'],
        mime = receipt['mime'];
    if (receipt.length != 6 ||
        receipt['format'] != 1 ||
        id is! String ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(id) ||
        size is! int ||
        size < 0 ||
        size > maxBytes ||
        hash is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash) ||
        name is! String ||
        name.isEmpty ||
        utf8.encode(name).length > 512 ||
        name == '.' ||
        name == '..' ||
        name.runes.any((r) => r < 32 || r == 127 || r == 47 || r == 92) ||
        mime is! String ||
        mime.length > 128 ||
        !RegExp(r'^[A-Za-z0-9.+-]+/[A-Za-z0-9.+-]+$').hasMatch(mime)) {
      throw const ArticleExportFailure(ArticleExportReason.receipt);
    }
    if (!p.isAbsolute(privateCache.path) ||
        await FileSystemEntity.type(privateCache.path, followLinks: false) !=
            FileSystemEntityType.directory) {
      throw const ArticleExportFailure(ArticleExportReason.missing);
    }
    final canonical = await privateCache.resolveSymbolicLinks();
    final root = Directory(
      p.join(privateCache.path, 'article-web-downloads-v1'),
    );
    final folder = Directory(p.join(root.path, id));
    for (final directory in [root, folder]) {
      if (await FileSystemEntity.type(directory.path, followLinks: false) !=
              FileSystemEntityType.directory ||
          await directory.resolveSymbolicLinks() !=
              p.join(
                canonical,
                p.relative(directory.path, from: privateCache.path),
              )) {
        throw const ArticleExportFailure(ArticleExportReason.missing);
      }
    }
    final marker = File(p.join(folder.path, 'owned.json')),
        ready = File(p.join(folder.path, 'ready.json'));
    for (final metadata in [marker, ready]) {
      if (await FileSystemEntity.type(metadata.path, followLinks: false) !=
              FileSystemEntityType.file ||
          await metadata.length() > 4096 ||
          await metadata.resolveSymbolicLinks() !=
              p.join(
                await folder.resolveSymbolicLinks(),
                p.basename(metadata.path),
              )) {
        throw const ArticleExportFailure(ArticleExportReason.missing);
      }
    }
    final owned = jsonDecode(await marker.readAsString()),
        stored = jsonDecode(await ready.readAsString());
    if (owned is! Map ||
        owned.length != 3 ||
        owned['format'] != 1 ||
        owned['id'] != id ||
        owned['lease'] != lease ||
        stored is! Map ||
        stored.length != 6 ||
        stored['format'] != 1 ||
        stored['id'] != id ||
        stored['bytes'] != size ||
        stored['sha256'] != hash ||
        stored['name'] != name ||
        stored['mime'] != mime) {
      throw const ArticleExportFailure(ArticleExportReason.receipt);
    }
    final source = File(p.join(folder.path, 'content.bin'));
    if (await FileSystemEntity.type(source.path, followLinks: false) !=
            FileSystemEntityType.file ||
        await source.resolveSymbolicLinks() !=
            p.join(await folder.resolveSymbolicLinks(), 'content.bin') ||
        await source.length() != size) {
      throw const ArticleExportFailure(ArticleExportReason.changed);
    }
    var count = 0;
    final digest = await sha256
        .bind(
          source.openRead().map((chunk) {
            current();
            count += chunk.length;
            if (count > size || count > maxBytes) {
              throw const ArticleExportFailure(ArticleExportReason.changed);
            }
            return chunk;
          }),
        )
        .first;
    current();
    if (count != size ||
        digest.toString() != hash ||
        await source.length() != size) {
      throw const ArticleExportFailure(ArticleExportReason.changed);
    }
    return ArticleWebExport._(id, XFile(source.path), name, mime, size, hash);
  }
}
