import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/attachments.dart';
import 'package:bookstark_flutter/core/images_repository.dart';
import 'package:bookstark_flutter/core/native_owned_image_picker.dart';
import 'package:bookstark_flutter/features/images/image_library_owner.dart';

void main() {
  test(
    'real private file exact original Unicode displayName MIME and bytes survive queue payload',
    () async {
      final cache = await Directory.systemTemp.createTemp('owned-images20-');
      try {
        final inbox = await Directory(
          '${cache.path}/owned-image-inbox-v1',
        ).create();
        final bytes = Uint8List.fromList([
          137,
          80,
          78,
          71,
          13,
          10,
          26,
          10,
          1,
          2,
          3,
        ]);
        final id = 'c' * 32, hash = sha256.convert(bytes).toString();
        await File('${inbox.path}/$id.image').writeAsBytes(bytes);
        var counter = 0;
        final calls = <String>[];
        final picker = NativeOwnedImagePicker(
          cacheDirectory: () async => cache,
          isCurrent: () => true,
          identity: () => ((++counter).toRadixString(16)).padLeft(32, '0'),
          invoke: (method, args) async {
            calls.add(method);
            if (method == 'registerOwner') {
              return {'format': 1, 'owner': args['owner'], 'registered': true};
            }
            if (method == 'pick') {
              return {
                'format': 1,
                'cancelled': false,
                'owner': args['owner'],
                'id': args['id'],
                'files': [
                  {
                    'id': id,
                    'name': '原图😀.jpeg',
                    'mime': 'image/png',
                    'bytes': bytes.length,
                    'sha256': hash,
                  },
                ],
              };
            }
            if (method == 'release') {
              await File('${inbox.path}/$id.image').delete();
              return {'format': 1, 'released': id};
            }
            if (method == 'retireOwner') {
              return {'format': 1, 'owner': args['owner'], 'retired': true};
            }
            throw StateError('unexpected');
          },
        );
        final selected = await picker.pick();
        expect(selected, hasLength(1));
        expect(selected.single.name, '原图😀.jpeg');
        expect(selected.single.mimeType, 'image/png');
        final payload = await ImageUploadPayload.readFile(
          selected.single,
          ImageCategory.note,
        );
        expect(payload.name, '原图😀.jpeg');
        expect(payload.bytes, bytes);
        expect(payload.hash, hash);
        await picker.release(selected.single);
        expect(await File('${inbox.path}/$id.image').exists(), false);
        await expectLater(
          ImageUploadPayload.readFile(selected.single, ImageCategory.note),
          throwsA(isA<AttachmentCancelled>()),
        );
        await picker.retire();
        expect(calls, ['registerOwner', 'pick', 'release', 'retireOwner']);
      } finally {
        await cache.delete(recursive: true);
      }
    },
  );
  test(
    'Root image owner drain cannot activate next scope until actual native retirement acknowledgement',
    () async {
      final held = Completer<Object?>();
      final entered = Completer<void>();
      var activates = false;
      final picker = NativeOwnedImagePicker(
        isCurrent: () => true,
        identity: () => 'a' * 32,
        invoke: (method, args) {
          expect(method, 'retireOwner');
          entered.complete();
          return held.future;
        },
      );
      final owner = ImageLibraryOwner();
      owner.addRetirementBarrier(picker.retire);
      final draining = owner.retireAndDrain().then((_) => activates = true);
      await entered.future;
      expect(owner.isCurrent, false);
      expect(activates, false);
      held.complete({'format': 1, 'owner': 'a' * 32, 'retired': true});
      await draining;
      expect(activates, true);
    },
  );
  test(
    'held SAF result cannot return files after owner retirement or authorize a new scope',
    () async {
      final choose = Completer<Object?>();
      final choosing = Completer<void>();
      var next = 0;
      final calls = <String>[];
      final picker = NativeOwnedImagePicker(
        isCurrent: () => true,
        identity: () => ((++next).toRadixString(16)).padLeft(32, '0'),
        invoke: (method, args) async {
          calls.add(method);
          if (method == 'registerOwner') {
            return {'format': 1, 'owner': args['owner'], 'registered': true};
          }
          if (method == 'pick') {
            choosing.complete();
            return choose.future;
          }
          if (method == 'retireOwner') {
            return {'format': 1, 'owner': args['owner'], 'retired': true};
          }
          throw StateError('unexpected');
        },
      );
      final result = picker.pick();
      final expectation = expectLater(
        result,
        throwsA(isA<AttachmentCancelled>()),
      );
      await choosing.future;
      await picker.retire();
      await expectation;
      choose.complete({'format': 1, 'cancelled': true});
      await Future<void>.delayed(Duration.zero);
      await expectLater(picker.pick(), throwsA(isA<AttachmentCancelled>()));
      expect(calls, ['registerOwner', 'pick', 'retireOwner']);
    },
  );
  test(
    'inbox tampering fails integrity before upload and retire cleanup stays awaited',
    () async {
      final cache = await Directory.systemTemp.createTemp('owned-images20-');
      try {
        final inbox = await Directory(
          '${cache.path}/owned-image-inbox-v1',
        ).create();
        final id = 'd' * 32;
        final bytes = Uint8List.fromList([1, 2, 3]);
        final file = File('${inbox.path}/$id.image');
        await file.writeAsBytes(bytes);
        var next = 0;
        final picker = NativeOwnedImagePicker(
          cacheDirectory: () async => cache,
          isCurrent: () => true,
          identity: () => ((++next).toRadixString(16)).padLeft(32, '0'),
          invoke: (method, args) async {
            if (method == 'registerOwner') {
              return {'format': 1, 'owner': args['owner'], 'registered': true};
            }
            if (method == 'pick') {
              return {
                'format': 1,
                'cancelled': false,
                'owner': args['owner'],
                'id': args['id'],
                'files': [
                  {
                    'id': id,
                    'name': '原图.png',
                    'mime': 'image/png',
                    'bytes': 3,
                    'sha256': sha256.convert(bytes).toString(),
                  },
                ],
              };
            }
            if (method == 'retireOwner') {
              await file.delete();
              return {'format': 1, 'owner': args['owner'], 'retired': true};
            }
            throw StateError('unexpected');
          },
        );
        final selected = await picker.pick();
        await file.writeAsBytes([3, 2, 1]);
        await expectLater(
          ImageUploadPayload.readFile(selected.single, ImageCategory.note),
          throwsFormatException,
        );
        await picker.retire();
        expect(await file.exists(), false);
      } finally {
        await cache.delete(recursive: true);
      }
    },
  );
}
