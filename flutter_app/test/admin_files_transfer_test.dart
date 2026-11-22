import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:bookstark_flutter/features/admin/admin_files_models.dart';
import 'package:bookstark_flutter/features/admin/admin_files_transfer.dart';
import 'admin_files_models_test.dart' as models;

void main() {
  late Directory root;
  late Completer<void> abort;
  AdminFileEntry entry(int size) =>
      AdminFileEntry.parse(models.row(name: 'binary.bin', size: size), '/work');
  Future<void> emptyCache() async {
    for (final name in [
      'bookstark-remote-files',
      'bookstark-download-cache-v1',
    ]) {
      final parent = Directory('${root.path}/$name');
      if (await parent.exists()) expect(await parent.list().toList(), isEmpty);
    }
  }

  setUp(() async {
    final base = Directory(
      '${Platform.environment['BOOKSTARK_APK_TEST_ROOT'] ?? '/vol1/1000/wy/photos-apk-test/bookstark-flutter/unit-files'}/admin41-download-tests',
    );
    await base.create(recursive: true);
    root = await base.createTemp('case-');
    abort = Completer<void>();
  });
  tearDown(() async {
    if (!abort.isCompleted) abort.complete();
    if (await root.exists()) await root.delete(recursive: true);
  });
  test(
    'Exact binary bytes and SHA256 saved privately then deleted idempotently',
    () async {
      final bytes = [0, 255, 13, 10, 228, 184, 173];
      final progress = <int>[];
      final response = http.StreamedResponse(
        Stream.fromIterable([bytes.sublist(0, 3), bytes.sublist(3)]),
        200,
        contentLength: bytes.length,
      );
      final file = await receiveAdminFile(
        response,
        entry(bytes.length),
        abort.future,
        cacheDirectory: () async => root,
        onReceived: (received, total) {
          progress.add(received);
          expect(total, bytes.length);
        },
      );
      expect(await file.file.readAsBytes(), bytes);
      expect(file.hash, sha256.convert(bytes).toString());
      expect(progress, [3, 7]);
      expect(file.file.path, startsWith(root.path));
      await file.close();
      await file.close();
      await emptyCache();
    },
  );
  for (final extra in [false, true]) {
    test(
      extra
          ? 'Reject appended error JSON despite HTTP200'
          : 'Reject short body despite HTTP200',
      () async {
        final bytes = extra ? [1, 2, 3, 4, 123, 125] : [1, 2, 3];
        final response = http.StreamedResponse(Stream.value(bytes), 200);
        await expectLater(
          receiveAdminFile(
            response,
            entry(4),
            abort.future,
            cacheDirectory: () async => root,
          ),
          throwsFormatException,
        );
        await emptyCache();
      },
    );
  }
  test(
    'Metadata mismatch cancels unread stream before creating a partial file',
    () async {
      var cancelled = false;
      final stream = StreamController<List<int>>(
        onCancel: () {
          cancelled = true;
        },
      );
      final response = http.StreamedResponse(
        stream.stream,
        200,
        contentLength: 99,
      );
      await expectLater(
        receiveAdminFile(
          response,
          entry(4),
          abort.future,
          cacheDirectory: () async => root,
        ),
        throwsFormatException,
      );
      expect(cancelled, true);
      await emptyCache();
      await stream.close();
    },
  );
  test('Transport error removes partial bytes', () async {
    Stream<List<int>> broken() async* {
      yield [1, 2];
      throw const HttpException('owned disconnect');
    }

    await expectLater(
      receiveAdminFile(
        http.StreamedResponse(broken(), 200),
        entry(4),
        abort.future,
        cacheDirectory: () async => root,
      ),
      throwsA(isA<HttpException>()),
    );
    await emptyCache();
  });
  test('Cancellation between chunks removes partial bytes', () async {
    Stream<List<int>> chunks() async* {
      yield [1, 2];
      abort.complete();
      await Future<void>.delayed(Duration.zero);
      yield [3, 4];
    }

    await expectLater(
      receiveAdminFile(
        http.StreamedResponse(chunks(), 200),
        entry(4),
        abort.future,
        cacheDirectory: () async => root,
      ),
      throwsStateError,
    );
    await emptyCache();
  });
}
