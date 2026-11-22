import 'dart:convert';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/attachments.dart';
import 'package:bookstark_flutter/core/drive_models.dart';
import 'package:bookstark_flutter/core/drive_source.dart';
import 'package:bookstark_flutter/core/drive_upload_controller.dart';
import '../tool/fixtures/drive.dart';

XFile source(String name, String body) => XFile.fromData(
  utf8.encode(body),
  path: name,
  lastModified: DateTime.utc(2026),
);

class InterruptedDrive extends DriveFixture {
  InterruptedDrive() : super(seed: false);
  bool interrupt = false;
  @override
  Future<DriveUploadResult> upload(
    DriveSourceSnapshot source, {
    required String target,
    DriveNode? expected,
    AttachmentCancellation? cancellation,
    void Function(int, int)? onSent,
  }) async {
    final result = await super.upload(
      source,
      target: target,
      expected: expected,
      cancellation: cancellation,
      onSent: onSent,
    );
    if (interrupt) throw StateError('connection lost after write');
    return result;
  }
}

void main() {
  test(
    'selection never writes; duplicate queued names need explicit consent',
    () async {
      final repo = InterruptedDrive();
      final controller = DriveUploadController(repo, directory: '');
      controller.addFiles([source('a.md', 'one'), source('a.md', 'two')]);
      expect(repo.uploads, 0);
      expect(controller.entries.map((e) => e.id).toSet().length, 2);
      var collisions = 0;
      await controller.start(
        onCollision: (entry, node) async {
          collisions++;
          return const DriveCollisionChoice(
            DriveCollisionAction.rename,
            name: 'b.md',
          );
        },
      );
      expect(collisions, 1);
      expect(repo.uploads, 2);
      expect(utf8.decode(repo.data['a.md']!), 'one');
      expect(utf8.decode(repo.data['b.md']!), 'two');
      controller.dispose();
    },
  );
  test(
    'changed overwrite baseline requires fresh consent and no write',
    () async {
      final repo = InterruptedDrive();
      repo.addFile('a.md', utf8.encode('old'), 'text/markdown');
      final controller = DriveUploadController(repo, directory: '');
      controller.addFiles([source('a.md', 'mine')]);
      await controller.start(
        onCollision: (entry, node) async {
          repo.addFile(
            'a.md',
            utf8.encode('changed elsewhere'),
            'text/markdown',
          );
          return const DriveCollisionChoice(DriveCollisionAction.overwrite);
        },
      );
      expect(controller.entries.single.state, DriveUploadState.conflict);
      expect(repo.uploads, 0);
      expect(utf8.decode(repo.data['a.md']!), 'changed elsewhere');
      controller.dispose();
    },
  );
  test(
    'unknown result verifies by read without automatic resubmission',
    () async {
      final repo = InterruptedDrive()..interrupt = true;
      final controller = DriveUploadController(repo, directory: '');
      controller.addFiles([source('a.md', 'mine')]);
      await controller.start(
        onCollision: (_, _) async =>
            const DriveCollisionChoice(DriveCollisionAction.skip),
      );
      final entry = controller.entries.single;
      expect(entry.state, DriveUploadState.uncertain);
      expect(repo.uploads, 1);
      await controller.start(
        onCollision: (_, _) async =>
            const DriveCollisionChoice(DriveCollisionAction.overwrite),
      );
      expect(repo.uploads, 1);
      expect(await controller.verify(entry), isTrue);
      expect(entry.completed, isTrue);
      expect(repo.uploads, 1);
      controller.dispose();
    },
  );
  test(
    'stopping at conflict sends nothing and leaves subsequent rows pending',
    () async {
      final repo = InterruptedDrive();
      repo.addFile('a.md', utf8.encode('old'), 'text/markdown');
      final controller = DriveUploadController(repo, directory: '');
      controller.addFiles([source('a.md', 'mine'), source('b.md', 'next')]);
      await controller.start(
        onCollision: (_, _) async =>
            const DriveCollisionChoice(DriveCollisionAction.pause),
      );
      expect(repo.uploads, 0);
      expect(controller.entries.last.state, DriveUploadState.pending);
      controller.dispose();
    },
  );
  test(
    'uncertain first upload pauses subsequent writes until read verification',
    () async {
      final repo = InterruptedDrive()..interrupt = true;
      final controller = DriveUploadController(repo, directory: '');
      controller.addFiles([source('a.md', 'first'), source('b.md', 'second')]);
      await controller.start(
        onCollision: (_, _) async =>
            const DriveCollisionChoice(DriveCollisionAction.skip),
      );
      expect(repo.uploads, 1);
      expect(controller.entries.last.state, DriveUploadState.pending);
      await controller.start(
        onCollision: (_, _) async =>
            const DriveCollisionChoice(DriveCollisionAction.skip),
      );
      expect(repo.uploads, 1);
      expect(await controller.verify(controller.entries.first), isTrue);
      repo.interrupt = false;
      await controller.start(
        onCollision: (_, _) async =>
            const DriveCollisionChoice(DriveCollisionAction.skip),
      );
      expect(repo.uploads, 2);
      expect(controller.entries.last.completed, isTrue);
      controller.dispose();
    },
  );
}
