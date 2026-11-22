import 'dart:io';
import 'dart:typed_data';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/attachments.dart';
import 'package:bookstark_flutter/core/local_attachments.dart';
import 'package:bookstark_flutter/core/local_article_attachment_import.dart';

void main() {
  late Directory root;
  late LocalAttachments repository;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('bookstark-article-import-');
    repository = LocalAttachments(Directory('${root.path}/attachments'));
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });

  test(
    'native file name, bytes and private URI survive bounded import',
    () async {
      final source = Uint8List.fromList([3, 1, 4, 1, 5]);
      final result = await importLocalArticleAttachment(
        repository,
        XFile.fromData(
          source,
          name: 'provider-name.txt',
          path: 'provider-name.txt',
        ),
      );
      expect(result.name, 'provider-name.txt');
      expect(result.uri.scheme, 'bookstark-attachment');
      expect(result.uri.pathSegments.last, 'provider-name.txt');
      expect(result.size, source.length);
      expect(await repository.read(result.uri), source);
    },
  );

  test(
    'oversized receipt never opens stream or creates private storage',
    () async {
      final source = _ProviderFile(
        64 * 1024 * 1024 + 1,
        () => Stream.value(Uint8List(0)),
      );
      await expectLater(
        importLocalArticleAttachment(repository, source),
        throwsFormatException,
      );
      expect(source.opened, isFalse);
      expect(await repository.directory.exists(), isFalse);
    },
  );

  test(
    'lying provider stream cannot exceed 64 MiB and partial private file is removed',
    () async {
      final source = _ProviderFile(
        1,
        () => Stream.value(Uint8List(64 * 1024 * 1024 + 1)),
      );
      await expectLater(
        importLocalArticleAttachment(repository, source),
        throwsFormatException,
      );
      expect(source.opened, isTrue);
      expect(await repository.directory.list().toList(), isEmpty);
    },
  );

  test(
    'cancellation during copy removes partial target without returning a reference',
    () async {
      final cancellation = AttachmentCancellation();
      Stream<Uint8List> chunks() async* {
        yield Uint8List.fromList([1, 2, 3]);
        cancellation.cancel();
        yield Uint8List.fromList([4, 5]);
      }

      await expectLater(
        importLocalArticleAttachment(
          repository,
          _ProviderFile(5, chunks),
          cancellation: cancellation,
        ),
        throwsA(isA<AttachmentCancelled>()),
      );
      expect(await repository.directory.list().toList(), isEmpty);
    },
  );

  test(
    'provider failure removes partial target and cannot look like a completed import',
    () async {
      Stream<Uint8List> chunks() async* {
        yield Uint8List.fromList([1, 2, 3]);
        throw StateError('Synthetic provider failure');
      }

      await expectLater(
        importLocalArticleAttachment(repository, _ProviderFile(5, chunks)),
        throwsStateError,
      );
      expect(await repository.directory.list().toList(), isEmpty);
    },
  );
}

class _ProviderFile extends XFile {
  _ProviderFile(this.reportedLength, this.chunks) : super('provider.txt');
  final int reportedLength;
  final Stream<Uint8List> Function() chunks;
  bool opened = false;
  @override
  Future<int> length() async => reportedLength;
  @override
  Stream<Uint8List> openRead([int? start, int? end]) {
    opened = true;
    return chunks();
  }
}
