import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/attachments.dart';
import 'package:bookstark_flutter/core/images_repository.dart';
import 'package:bookstark_flutter/core/native_owned_image_picker.dart';
import 'package:bookstark_flutter/features/images/image_library_owner.dart';

void main() {
  test(
    'failed native cleanup can retry only cleanup while identity remains permanently revoked',
    () async {
      var calls = 0;
      final second = Completer<Object?>();
      final entered = Completer<void>();
      final picker = NativeOwnedImagePicker(
        identity: () => 'a' * 32,
        isCurrent: () => true,
        invoke: (method, args) async {
          expect(method, 'retireOwner');
          expect(args, {'owner': 'a' * 32});
          calls++;
          if (calls == 1) {
            throw PlatformException(code: 'image_retire_cleanup_failed');
          }
          entered.complete();
          return second.future;
        },
      );
      final owner = ImageLibraryOwner();
      owner.addRetirementBarrier(picker.retire);
      await expectLater(
        owner.retireAndDrain(),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'image_retire_cleanup_failed',
          ),
        ),
      );
      expect(owner.isCurrent, false);
      await expectLater(owner.run(() async => 1), throwsStateError);
      await expectLater(picker.pick(), throwsA(isA<AttachmentCancelled>()));
      var activated = false;
      final retry = owner.retireAndDrain().then((_) => activated = true);
      await entered.future;
      expect(activated, false);
      expect(calls, 2);
      second.complete({'format': 1, 'owner': 'a' * 32, 'retired': true});
      await retry;
      expect(activated, true);
      expect(owner.isCurrent, false);
      await owner.retireAndDrain();
      await picker.retire();
      expect(calls, 2);
      await expectLater(picker.pick(), throwsA(isA<AttachmentCancelled>()));
    },
  );
  test(
    'long normalized Unicode suffix including real extension survives payload bytes exactly',
    () async {
      final cache = await Directory.systemTemp.createTemp('image20-long-name-');
      try {
        final inbox = await Directory(
          '${cache.path}/owned-image-inbox-v1',
        ).create();
        final raw = '${'head' * 100}😀${'a' * 172}📚.jpeg';
        // attachmentName takes last180 UTF16 units. The native safe-boundary
        // adjustment drops only a cut leading low surrogate, yielding179 units.
        final suffix = attachmentName(raw);
        expect(suffix.codeUnitAt(0), inInclusiveRange(0xDC00, 0xDFFF));
        final expected = suffix.substring(1);
        expect(expected, 'a' * 172 + '📚.jpeg');
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
            ]),
            id = 'e' * 32;
        await File('${inbox.path}/$id.image').writeAsBytes(bytes);
        var sequence = 0;
        final picker = NativeOwnedImagePicker(
          isCurrent: () => true,
          cacheDirectory: () async => cache,
          identity: () => ((++sequence).toRadixString(16)).padLeft(32, '0'),
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
                    'name': expected,
                    'mime': 'image/png',
                    'bytes': bytes.length,
                    'sha256': sha256.convert(bytes).toString(),
                  },
                ],
              };
            }
            if (method == 'retireOwner') {
              await File('${inbox.path}/$id.image').delete();
              return {'format': 1, 'owner': args['owner'], 'retired': true};
            }
            throw StateError('unexpected');
          },
        );
        final files = await picker.pick();
        final payload = await ImageUploadPayload.readFile(
          files.single,
          ImageCategory.note,
        );
        expect(files.single.name, expected);
        expect(payload.name, expected);
        expect(payload.bytes, bytes);
        expect(payload.name.endsWith('.jpeg'), true);
        expect(payload.name.runes.contains(0xFFFD), false);
        await picker.retire();
      } finally {
        await cache.delete(recursive: true);
      }
    },
  );
}
