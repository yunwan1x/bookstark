import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/prepared_owned_image_upload.dart';

void main() {
  test(
    'concurrent submissions call durable boundary once and send exactly once',
    () async {
      final gate = Completer<void>();
      var boundaries = 0, sends = 0, aborts = 0;
      final request = PreparedOwnedImageUpload(
        uri: Uri.parse('https://owned.test/api/uploads'),
        inputSHA256: 'a' * 64,
        beforeSubmit: () {},
        abort: () {
          aborts++;
        },
        send: () async {
          sends++;
          return {
            'code': 0,
            'data': {'id': 7, 'url': '/upload-files/a.png'},
          };
        },
      );
      final first = request.sendAfter(
        onSubmit: () async {
          boundaries++;
          await gate.future;
        },
      );
      await expectLater(
        request.sendAfter(
          onSubmit: () async {
            boundaries++;
          },
        ),
        throwsStateError,
      );
      expect(boundaries, 1);
      expect(sends, 0);
      gate.complete();
      await first;
      expect(boundaries, 1);
      expect(sends, 1);
      expect(aborts, 1);
    },
  );
  test(
    'retire during durable callback forbids send without repeating callback',
    () async {
      final gate = Completer<void>();
      var boundaries = 0, sends = 0;
      final request = PreparedOwnedImageUpload(
        uri: Uri.parse('https://owned.test/api/uploads'),
        inputSHA256: 'b' * 64,
        beforeSubmit: () {},
        abort: () {},
        send: () async {
          sends++;
          return {};
        },
      );
      final result = request.sendAfter(
        onSubmit: () async {
          boundaries++;
          await gate.future;
        },
      );
      final failure = expectLater(result, throwsStateError);
      request.retire();
      gate.complete();
      await failure;
      expect(boundaries, 1);
      expect(sends, 0);
      await expectLater(
        request.sendAfter(
          onSubmit: () async {
            boundaries++;
          },
        ),
        throwsStateError,
      );
      expect(boundaries, 1);
    },
  );
  test(
    'durability failure forbids the one HTTP request and aborts prepared state',
    () async {
      var sends = 0, aborts = 0;
      final request = PreparedOwnedImageUpload(
        uri: Uri.parse('https://owned.test/api/uploads'),
        inputSHA256: 'c' * 64,
        beforeSubmit: () {},
        abort: () {
          aborts++;
        },
        send: () async {
          sends++;
          return {};
        },
      );
      await expectLater(
        request.sendAfter(
          onSubmit: () async {
            throw StateError('Storage unconfirmed');
          },
        ),
        throwsStateError,
      );
      expect(sends, 0);
      expect(aborts, 1);
    },
  );
}
