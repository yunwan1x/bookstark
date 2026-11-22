import 'dart:io';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/attachments.dart';
import 'package:bookstark_flutter/core/drive_models.dart';
import 'package:bookstark_flutter/core/drive_repository.dart';
import 'package:bookstark_flutter/core/drive_download.dart';
import 'package:bookstark_flutter/core/file_export.dart';

class DownloadRepository extends DriveRepository {
  DownloadRepository(this.data)
    : node = DriveNode(
        id: 42,
        name: '报告.md',
        path: 'private/报告.md',
        directory: false,
        size: data.length,
        etag: crypto.sha256.convert(data).toString(),
        mime: 'text/markdown',
        modified: '2026-11-04',
      );
  final Uint8List data;
  final DriveNode node;
  List<List<int>>? chunks;
  int status = 200;
  int? length;
  @override
  bool get local => false;
  @override
  Future<List<DriveNode>> list(
    String path, {
    AttachmentCancellation? cancellation,
  }) async => [node];
  @override
  Future<DriveRead> open(
    DriveNode file, {
    String? range,
    String? ifRange,
    AttachmentCancellation? cancellation,
  }) async => DriveRead(
    stream: Stream.fromIterable(chunks ?? [data]),
    status: status,
    headers: const {},
    length: length ?? node.size,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'Unexpected repository operation ${invocation.memberName}',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  setUp(() async {
    final root = Directory(
      Platform.environment['BOOKSTARK_APK_TEST_ROOT'] ??
          '/vol1/1000/wy/photos-apk-test/bookstark-flutter/unit-files',
    );
    await root.create(recursive: true);
    directory = await root.createTemp('drive-download-');
  });
  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('bookstark/file_export'),
          null,
        );
    await directory.delete(recursive: true);
  });
  Future<List<FileSystemEntity>> files() async => await directory
      .list(recursive: true, followLinks: false)
      .where(
        (item) =>
            item is File &&
            !item.path.endsWith('/.bookstark-cache-owner-v1.json'),
      )
      .toList();
  test(
    'download preserves byte hash and original display name in a completed private cache file',
    () async {
      final repo = DownloadRepository(
        Uint8List.fromList([239, 187, 191, 35, 32, 65]),
      );
      var progress = 0;
      final result = await downloadDriveFile(
        repo,
        repo.node,
        cacheDirectory: () async => directory,
        onReceived: (count, total) {
          progress = count;
          expect(total, repo.node.size);
        },
      );
      expect(await result.file.readAsBytes(), repo.data);
      expect(result.hash, repo.node.etag);
      expect(result.node.name, '报告.md');
      expect(result.file.path, endsWith('/file.md'));
      expect(progress, repo.node.size);
      expect(await files(), hasLength(1));
      await result.close();
      expect(await files(), isEmpty);
    },
  );
  test(
    'truncated, oversized and wrong-version responses never leave a completed cache file',
    () async {
      for (final chunks in [
        [
          [1, 2],
        ],
        [
          [1, 2, 3, 4],
        ],
        [
          [9, 2, 3],
        ],
      ]) {
        final repo = DownloadRepository(Uint8List.fromList([1, 2, 3]))
          ..chunks = chunks;
        await expectLater(
          downloadDriveFile(
            repo,
            repo.node,
            cacheDirectory: () async => directory,
          ),
          throwsA(anyOf(isA<FormatException>(), isA<ApiFailure>())),
        );
        expect(await files(), isEmpty);
      }
    },
  );
  test(
    'cancelling a partially received response clears its private partial file',
    () async {
      final cancel = AttachmentCancellation(),
          repo = DownloadRepository(Uint8List.fromList([1, 2, 3]))
            ..chunks = [
              [1],
              [2],
              [3],
            ];
      await expectLater(
        downloadDriveFile(
          repo,
          repo.node,
          cancellation: cancel,
          cacheDirectory: () async => directory,
          onReceived: (count, total) => cancel.cancel(),
        ),
        throwsA(isA<AttachmentCancelled>()),
      );
      expect(await files(), isEmpty);
    },
  );
  test(
    'unexpected partial response and preview limit are rejected without producing a file',
    () async {
      final repo = DownloadRepository(Uint8List.fromList([1, 2, 3]))
        ..status = 206;
      await expectLater(
        downloadDriveFile(
          repo,
          repo.node,
          cacheDirectory: () async => directory,
        ),
        throwsFormatException,
      );
      expect(await files(), isEmpty);
      await expectLater(
        downloadDriveFile(
          repo,
          repo.node,
          maxBytes: 2,
          cacheDirectory: () async => directory,
        ),
        throwsA(isA<ApiFailure>()),
      );
      expect(await files(), isEmpty);
    },
  );
  test(
    'Android save passes a private file path and original name, and validates byte/hash acknowledgement',
    () async {
      final repo = DownloadRepository(Uint8List.fromList([1, 2, 3])),
          file = await downloadDriveFile(
            repo,
            repo.node,
            cacheDirectory: () async => directory,
          );
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('bookstark/file_export'),
            (call) async {
              expect(call.method, 'saveFile');
              final args = call.arguments as Map;
              expect(args['path'], file.file.path);
              expect(args['name'], '报告.md');
              expect(args['size'], 3);
              expect(args['sha256'], repo.node.etag);
              return {'saved': true, 'bytes': 3, 'sha256': repo.node.etag};
            },
          );
      expect(
        await const SystemFileExporter().save(file),
        FileExportOutcome.saved,
      );
      await file.close();
    },
  );
  test(
    'Android picker cancellation and invalid acknowledgements never report a saved file',
    () async {
      final repo = DownloadRepository(Uint8List.fromList([1, 2, 3])),
          file = await downloadDriveFile(
            repo,
            repo.node,
            cacheDirectory: () async => directory,
          );
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('bookstark/file_export'),
            (_) async => {'saved': false},
          );
      expect(
        await const SystemFileExporter().save(file),
        FileExportOutcome.cancelled,
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('bookstark/file_export'),
            (_) async => {'saved': true, 'bytes': 2, 'sha256': 'wrong'},
          );
      await expectLater(
        const SystemFileExporter().save(file),
        throwsFormatException,
      );
      await file.close();
    },
  );
}
