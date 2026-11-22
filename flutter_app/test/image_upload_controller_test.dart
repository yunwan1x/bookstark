import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/attachments.dart';
import 'package:bookstark_flutter/core/image_upload_controller.dart';
import 'package:bookstark_flutter/core/images_repository.dart';
import '../tool/fixtures/images.dart';

XFile file([String color = 'blue']) => XFile.fromData(
  Uint8List.fromList(
    utf8.encode(
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"><rect width="10" height="10" fill="$color"/></svg>',
    ),
  ),
  name: '同名.svg',
);
void main() {
  test(
    'same-name queue entries retain independent identity and identical content reuses actual ID',
    () async {
      final repo = ImagesFixture();
      final controller = ImageUploadController(repo);
      addTearDown(controller.dispose);
      await controller.addFiles([file(), file()]);
      expect(controller.entries[0].id, isNot(controller.entries[1].id));
      expect(repo.uploadCalls, 0);
      await controller.start();
      expect(repo.uploadCalls, 1);
      expect(controller.confirmedCount, 2);
      expect(
        controller.entries[0].result!.id,
        controller.entries[1].result!.id,
      );
      expect(controller.entries[1].state, ImageUploadState.reused);
    },
  );
  test(
    'invalid image remains failed while later valid queue entries can succeed',
    () async {
      final repo = ImagesFixture();
      final queue = ImageUploadController(repo);
      addTearDown(queue.dispose);
      await queue.addFiles([
        XFile.fromData(Uint8List.fromList([1, 2, 3]), name: 'not-image.png'),
        file(),
      ]);
      await queue.start();
      expect(queue.entries.first.state, ImageUploadState.failed);
      expect(queue.entries.last.state, ImageUploadState.confirmed);
      expect(repo.uploadCalls, 1);
      expect(queue.running, isFalse);
    },
  );
  test(
    'stop after server write is uncertain and hash verification confirms without repost',
    () async {
      final repo = ImagesFixture(), started = Completer<void>();
      repo.uploadOverride = (payload, cancel, onSent) async {
        repo.recordPayload(payload);
        started.complete();
        await cancel!.signal;
        throw const AttachmentCancelled();
      };
      final queue = ImageUploadController(repo);
      addTearDown(queue.dispose);
      await queue.addFiles([file(), file('red')]);
      final running = queue.start();
      await started.future;
      queue.stop();
      await running;
      expect(queue.entries.first.state, ImageUploadState.uncertain);
      expect(queue.entries.last.state, ImageUploadState.pending);
      expect(repo.uploadCalls, 1);
      await queue.verify(queue.entries.first);
      expect(queue.entries.first.state, ImageUploadState.confirmed);
      expect(repo.uploadCalls, 1);
      expect(queue.confirmedCount, 1);
    },
  );
  test(
    'missing verification never automatically retransmits a previously uncertain write',
    () async {
      final repo = ImagesFixture()
        ..uploadOverride = ((_, cancel, onSent) async =>
            throw const ApiFailure(502, 'fixture upstream failure'));
      final queue = ImageUploadController(repo);
      addTearDown(queue.dispose);
      await queue.addFiles([file()]);
      await queue.start();
      expect(queue.uncertainCount, 1);
      await queue.verify(queue.entries.single);
      expect(queue.entries.single.verifiedMissing, isTrue);
      await queue.start();
      expect(repo.uploadCalls, 1);
      queue.allowExplicitRetransmission(queue.entries.single);
      repo.uploadOverride = null;
      await queue.start();
      expect(repo.uploadCalls, 2);
      expect(queue.entries.single.state, ImageUploadState.confirmed);
    },
  );
  test(
    'sending every byte does not mark completion; a known reply wins a late stop',
    () async {
      final repo = ImagesFixture(),
          started = Completer<void>(),
          reply = Completer<UploadedImageReference>();
      ImageUploadPayload? sentPayload;
      repo.uploadOverride = (payload, cancel, onSent) async {
        sentPayload = payload;
        onSent?.call(payload.bytes.length, payload.bytes.length);
        started.complete();
        return reply.future;
      };
      final queue = ImageUploadController(repo);
      addTearDown(queue.dispose);
      await queue.addFiles([file()]);
      final running = queue.start();
      await started.future;
      expect(queue.entries.single.sent, queue.entries.single.sourceSize);
      expect(queue.entries.single.state, ImageUploadState.uploading);
      expect(queue.confirmedCount, 0);
      queue.stop();
      reply.complete(repo.recordPayload(sentPayload!));
      await running;
      expect(queue.entries.single.state, ImageUploadState.confirmed);
      expect(queue.confirmedCount, 1);
    },
  );
}
