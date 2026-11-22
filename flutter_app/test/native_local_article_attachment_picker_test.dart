import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'package:bookstark_flutter/core/local_attachments.dart';
import 'package:bookstark_flutter/core/local_article_attachment_import.dart';
import 'package:bookstark_flutter/core/attachments.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/native_local_article_attachment_picker.dart';

void main() {
  final id = 'a' * 32;
  Map<String, Object?> receipt() => {
    'format': 1,
    'cancelled': false,
    'id': id,
    'bytes': 120,
    'sha256': 'b' * 64,
    'name': 'fixture.txt',
  };
  test(
    'successful receipt is bound and release uses only opaque identity',
    () async {
      final calls = <String>[];
      final picker = NativeLocalArticleAttachmentPicker(
        identity: () => id,
        invoke: (method, args) async {
          calls.add(method);
          expect(args, {'id': id});
          return method == 'pick' ? receipt() : {'format': 1, 'released': id};
        },
      );
      final picked = (await picker.pick())!;
      expect(picked.bytes, 120);
      expect(picked.sha256, 'b' * 64);
      await picker.release(picked);
      expect(calls, ['pick', 'release']);
    },
  );
  test('cancelled choice produces no input artifact', () async {
    final picker = NativeLocalArticleAttachmentPicker(
      identity: () => id,
      invoke: (_, _) async => {'format': 1, 'cancelled': true},
    );
    expect(await picker.pick(), isNull);
  });
  test('wrong identity/hash/size/format and extra paths fail closed', () async {
    for (final changes in [
      {'id': 'c' * 32},
      {'sha256': 'invalid'},
      {'bytes': -1},
      {'bytes': 65 * 1024 * 1024},
      {'name': '../bad'},
      {'name': ''},
      {'bytes': 3 * 1024 * 1024 * 1024},
      {'format': 1.0},
      {'path': '/outside'},
      {'bytes': 120.0},
    ]) {
      final picker = NativeLocalArticleAttachmentPicker(
        identity: () => id,
        invoke: (_, _) async => {...receipt(), ...changes},
      );
      await expectLater(picker.pick(), throwsFormatException);
    }
  });
  test(
    'timeout cancels the same request once without releasing or replaying',
    () async {
      final calls = <String>[];
      final picker = NativeLocalArticleAttachmentPicker(
        identity: () => id,
        timeout: const Duration(milliseconds: 10),
        invoke: (method, args) async {
          calls.add(method);
          expect(args, {'id': id});
          if (method == 'pick') return Completer<Object?>().future;
          return {'format': 1, 'cancelled': true};
        },
      );
      await expectLater(picker.pick(), throwsA(isA<TimeoutException>()));
      expect(calls, ['pick', 'cancel']);
    },
  );
  test(
    'overlapping selection rejected; explicit cancel targets active request',
    () async {
      final pending = Completer<Object?>();
      final calls = <String>[];
      final picker = NativeLocalArticleAttachmentPicker(
        identity: () => id,
        invoke: (method, args) async {
          calls.add(method);
          if (method == 'pick') return await pending.future;
          return <String, Object?>{'format': 1, 'cancelled': true};
        },
      );
      final first = picker.pick();
      await expectLater(picker.pick(), throwsStateError);
      await picker.cancel();
      pending.complete({'format': 1, 'cancelled': true});
      expect(await first, isNull);
      expect(calls, ['pick', 'cancel']);
    },
  );
  test('bad generated identity never invokes native code', () async {
    var called = false;
    final picker = NativeLocalArticleAttachmentPicker(
      identity: () => '../bad',
      invoke: (_, _) async {
        called = true;
        return null;
      },
    );
    await expectLater(picker.pick(), throwsFormatException);
    expect(called, isFalse);
  });
  test(
    'dispose releases wait immediately and cleans only a late bound receipt',
    () async {
      final native = Completer<Object?>();
      final released = Completer<void>();
      final calls = <String>[];
      final picker = NativeLocalArticleAttachmentPicker(
        identity: () => id,
        invoke: (method, args) async {
          calls.add(method);
          expect(args, {'id': id});
          if (method == 'pick') return await native.future;
          if (method == 'release') {
            released.complete();
            return {'format': 1, 'released': id};
          }
          return {'format': 1, 'cancelled': true};
        },
      );
      final waiting = picker.pick();
      final rejected = expectLater(
        waiting,
        throwsA(isA<AttachmentCancelled>()),
      );
      await Future.wait([picker.dispose(), picker.dispose(), rejected]);
      expect(calls, ['pick', 'cancel']);
      native.complete(receipt());
      await released.future;
      expect(calls, ['pick', 'cancel', 'release']);
      await expectLater(picker.pick(), throwsStateError);
    },
  );
  test('disposed owner never cleans a mismatched late receipt', () async {
    final native = Completer<Object?>();
    final calls = <String>[];
    final picker = NativeLocalArticleAttachmentPicker(
      identity: () => id,
      invoke: (method, args) async {
        calls.add(method);
        if (method == 'pick') return await native.future;
        return {'format': 1, 'cancelled': true};
      },
    );
    final waiting = picker.pick();
    final rejected = expectLater(waiting, throwsA(isA<AttachmentCancelled>()));
    await picker.dispose();
    await rejected;
    native.complete({...receipt(), 'id': 'f' * 32});
    await Future<void>.delayed(Duration.zero);
    expect(calls, ['pick', 'cancel']);
  });
  test(
    'inbox receipt cannot be released through another picker owner',
    () async {
      NativeLocalArticleAttachmentPicker owner() =>
          NativeLocalArticleAttachmentPicker(
            identity: () => id,
            invoke: (method, args) async =>
                method == 'pick' ? receipt() : {'format': 1, 'released': id},
          );
      final first = owner(), second = owner();
      final picked = (await first.pick())!;
      await expectLater(second.release(picked), throwsStateError);
      await first.release(picked);
      await expectLater(first.open(picked), throwsStateError);
    },
  );

  test(
    'native inbox name and digest are preserved through streaming import and release',
    () async {
      final cache = await Directory.systemTemp.createTemp(
        'bookstark-attachment-picker-',
      );
      try {
        final inbox = await Directory(
          '${cache.path}/local-article-attachment-inbox-v1',
        ).create();
        final bytes = Uint8List.fromList([3, 1, 4, 1, 5]);
        final source = await File(
          '${inbox.path}/$id.attachment',
        ).writeAsBytes(bytes);
        final picker = NativeLocalArticleAttachmentPicker(
          cacheDirectory: () async => cache,
          identity: () => id,
          invoke: (method, args) async {
            expect(args, {'id': id});
            if (method == 'pick') {
              return {
                ...receipt(),
                'bytes': bytes.length,
                'sha256': crypto.sha256.convert(bytes).toString(),
                'name': 'provider-original.txt',
              };
            }
            if (await source.exists()) await source.delete();
            return {'format': 1, 'released': id};
          },
        );
        final picked = (await picker.pick())!;
        final file = await picker.open(picked);
        expect(file.name, 'provider-original.txt');
        final attachments = LocalAttachments(
          Directory('${cache.path}/permanent'),
        );
        final imported = await importLocalArticleAttachment(attachments, file);
        expect(imported.name, 'provider-original.txt');
        expect(await attachments.read(imported.uri), bytes);
        await picker.release(picked);
        expect(await source.exists(), isFalse);
        await expectLater(
          file.openRead().drain<void>(),
          throwsA(isA<AttachmentCancelled>()),
        );
      } finally {
        await cache.delete(recursive: true);
      }
    },
  );

  test(
    'inbox digest mismatch cannot publish a partial permanent attachment',
    () async {
      final cache = await Directory.systemTemp.createTemp(
        'bookstark-attachment-picker-',
      );
      try {
        final inbox = await Directory(
          '${cache.path}/local-article-attachment-inbox-v1',
        ).create();
        await File('${inbox.path}/$id.attachment').writeAsBytes([1, 2, 3]);
        final picker = NativeLocalArticleAttachmentPicker(
          cacheDirectory: () async => cache,
          identity: () => id,
          invoke: (_, _) async => {
            ...receipt(),
            'bytes': 3,
            'name': 'document.txt',
          },
        );
        final file = await picker.open((await picker.pick())!);
        final attachments = LocalAttachments(
          Directory('${cache.path}/permanent'),
        );
        await expectLater(
          importLocalArticleAttachment(attachments, file),
          throwsFormatException,
        );
        expect(await attachments.directory.list().toList(), isEmpty);
      } finally {
        await cache.delete(recursive: true);
      }
    },
  );

  test('inbox directory and file symlinks cannot redirect a receipt', () async {
    final cache = await Directory.systemTemp.createTemp(
      'bookstark-attachment-picker-',
    );
    final outside = await Directory.systemTemp.createTemp(
      'bookstark-attachment-outside-',
    );
    try {
      final picker = NativeLocalArticleAttachmentPicker(
        cacheDirectory: () async => cache,
        identity: () => id,
        invoke: (_, _) async => receipt(),
      );
      final picked = (await picker.pick())!;
      final inbox = '${cache.path}/local-article-attachment-inbox-v1';
      await Link(inbox).create(outside.path);
      await expectLater(picker.open(picked), throwsFormatException);
      await Link(inbox).delete();
      await Directory(inbox).create();
      final source = await File(
        '${outside.path}/source',
      ).writeAsBytes(List.filled(120, 0));
      await Link('$inbox/$id.attachment').create(source.path);
      await expectLater(picker.open(picked), throwsFormatException);
    } finally {
      await cache.delete(recursive: true);
      await outside.delete(recursive: true);
    }
  });
}
