import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_selector/file_selector.dart';
import 'package:http/http.dart' as http;
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/drive_repository.dart';
import 'package:bookstark_flutter/core/drive_models.dart';
import 'package:bookstark_flutter/core/drive_source.dart';

void requireDrive(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> runDriveContract(BookstarkClient client) async {
  final repo = RemoteDriveRepository(client), anonymous = http.Client();
  final base = Directory(
    Platform.environment['BOOKSTARK_APK_TEST_ROOT'] ??
        '/vol1/1000/wy/photos-apk-test/bookstark-flutter/unit-files',
  );
  await base.create(recursive: true);
  final directory = await base.createTemp('drive-contract-');
  DriveNode? root;
  try {
    final initial = await repo.profile();
    requireDrive(
      initial.fileMaxBytes > 0 && initial.endpoint != null,
      'Drive returns actual limits and endpoint',
    );
    root = await repo.mkdir('', 'Flutter网盘契约');
    final folder = await repo.mkdir(root.path, '阅读资料');
    final bytes = Uint8List.fromList([
      239,
      187,
      191,
      ...utf8.encode('# 阅读\r\n\r\n100%_?.txt\r\n'),
    ]);
    final source = await File(
      '${directory.path}/actual.txt',
    ).writeAsBytes(bytes);
    final snapshot = await DriveSourceSnapshot.prepare(
      XFile(source.path),
      maxBytes: initial.fileMaxBytes,
    );
    final target = driveChild(folder.path, 'a%2Fb?.txt');
    final uploaded = await repo.upload(snapshot, target: target);
    requireDrive(
      uploaded.node.path == target && uploaded.node.size == bytes.length,
      'Actual file path preserves literal percent and query punctuation',
    );
    requireDrive(
      base64Encode(await repo.bytes(uploaded.node)) == base64Encode(bytes),
      'Authenticated download preserves BOM and CRLF bytes',
    );
    final document = await repo.readText(uploaded.node);
    requireDrive(
      document.hasBom && document.content == '# 阅读\r\n\r\n100%_?.txt\r\n',
      'Strict text decoder preserves actual content',
    );
    final range = await repo.open(
      uploaded.node,
      range: 'bytes=3-8',
      ifRange: '"${uploaded.node.etag}"',
    );
    final partial = BytesBuilder(copy: false);
    await for (final chunk in range.stream) {
      partial.add(chunk);
    }
    requireDrive(
      range.status == 206 &&
          range.headers['content-range'] == 'bytes 3-8/${bytes.length}' &&
          base64Encode(partial.takeBytes()) ==
              base64Encode(bytes.sublist(3, 9)),
      'Real Go Range and If-Range expose original binary offsets',
    );
    final alias = await repo.upload(
      snapshot,
      target: driveChild(folder.path, 'alias.txt'),
    );
    requireDrive(
      alias.deduplicated &&
          alias.node.id != uploaded.node.id &&
          alias.node.etag == uploaded.node.etag,
      'Owned hash check writes canonical linked target with a distinct node ID',
    );
    var rejected = false;
    try {
      await repo.upload(snapshot, target: target);
    } on DriveConflict {
      rejected = true;
    }
    requireDrive(
      rejected,
      'Existing target cannot be silently overwritten without expected snapshot',
    );
    final beforeCopy = await repo.profile();
    final copiedPath = driveChild(folder.path, 'copy.txt');
    await repo.copy(uploaded.node, copiedPath);
    final copied = (await repo.lookup(copiedPath))!;
    final afterCopy = await repo.profile();
    requireDrive(
      copied.id != uploaded.node.id &&
          afterCopy.usage.storedBytes == beforeCopy.usage.storedBytes &&
          afterCopy.usage.logicalBytes ==
              beforeCopy.usage.logicalBytes + bytes.length,
      'Copy counts logical bytes but not a second unique stored blob',
    );
    final movedPath = driveChild(root.path, 'moved.txt');
    await repo.rename(copied, movedPath);
    final moved = (await repo.lookup(movedPath))!;
    requireDrive(
      moved.id == copied.id && await repo.lookup(copiedPath) == null,
      'Move preserves actual node ID and removes old path',
    );
    final saved = await repo.saveText(document, '');
    requireDrive(
      (await repo.bytes(saved)).toList().join(',') == '239,187,191',
      'Clearing BOM text preserves only its original BOM',
    );
    final empty = DriveText.decode(saved, await repo.bytes(saved));
    final updated = await repo.saveText(empty, '公开文本');
    rejected = false;
    try {
      await repo.saveText(document, '不能覆盖新版本');
    } on DriveConflict {
      rejected = true;
    }
    requireDrive(
      rejected,
      'Stale text baseline does not overwrite current content',
    );
    final privateDraft = await repo.readText(updated);
    const publicPath = 'flutter-drive-contract/阅读资料.txt';
    final public = await repo.publish(updated, publicPath);
    final response = await anonymous.get(public);
    requireDrive(
      response.statusCode == 200 &&
          base64Encode(response.bodyBytes) ==
              base64Encode(await repo.bytes(updated)),
      'Explicit public file is readable anonymously with actual bytes',
    );
    final published = (await repo.lookup(target))!;
    requireDrive(
      published.isPublic && published.publicPath == publicPath,
      'Canonical listing confirms public path',
    );
    rejected = false;
    try {
      await repo.saveText(privateDraft, '不能把私人草稿悄悄写进公开文件');
    } on DriveConflict {
      rejected = true;
    }
    requireDrive(
      rejected,
      'Publication context changes prevent silently publishing a private draft',
    );
    final publicDocument = await repo.readText(published);
    final publicSaved = await repo.saveText(publicDocument, '公开修改后的正文');
    requireDrive(
      publicSaved.isPublic && publicSaved.publicPath == publicPath,
      'Save response is refreshed from real listing and never invents a private state',
    );
    final sharedAgain = await repo.upload(
      snapshot,
      target: target,
      expected: publicSaved,
    );
    requireDrive(
      sharedAgain.node.isPublic && sharedAgain.node.publicPath == publicPath,
      'Overwriting a public target preserves canonical public state after hash linking',
    );
    await repo.unpublish(sharedAgain.node);
    requireDrive(
      !(await repo.lookup(target))!.isPublic,
      'Unpublish refreshes actual private state',
    );
    requireDrive(
      (await anonymous.get(
            public.replace(queryParameters: {'verify': 'fresh'}),
          )).statusCode ==
          404,
      'Fresh anonymous request no longer exposes unpublished file',
    );
    await repo.remove(moved);
    requireDrive(
      await repo.lookup(movedPath) == null,
      'Deletion checks actual original node',
    );
    stdout.writeln(
      'PASS production drive: private CRUD, literal paths, streamed upload, owned hash linking, explicit overwrite protection, deduplicated quota, stable-ID move/copy, UTF8 BOM/CRLF and empty edits, stale baseline rejection, Range/ETag and explicit public/unpublish',
    );
  } finally {
    if (root != null) {
      final current = await repo.lookup(root.path);
      if (current != null) await repo.remove(current);
    }
    repo.dispose();
    anonymous.close();
    await directory.delete(recursive: true);
  }
}
