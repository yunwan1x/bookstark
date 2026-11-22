import 'dart:async';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'attachments.dart';
import 'complex_editor_document.dart';
import 'drive_models.dart';
import 'drive_source.dart';
import 'image_dimensions.dart';
import 'local_drive_repository.dart';
import 'local_drawing_image_owner.dart';
import 'local_markdown_resources.dart';
import 'local_drawing_image_resources.dart';

class _NamedRasterBytes extends XFile {
  _NamedRasterBytes(super.bytes, this._name)
    : super.fromData(lastModified: DateTime.now().toUtc());
  final String _name;
  @override
  String get name => _name;
}

final class LocalDrawingSelectedImage {
  LocalDrawingSelectedImage._(
    this._files,
    this.attachment,
    this.sha256Hex,
    this.width,
    this.height,
    Uint8List bytes,
  ) : preview = Uint8List.fromList(bytes).asUnmodifiableView();
  final LocalDrawingLocalFiles _files;
  final Attachment attachment;
  final String sha256Hex;
  final int width, height;
  final Uint8List preview;
}

/// Real ordinary-local asset publication. Import only publishes library/UUID
/// assets; editor SQL is solely the existing controller's explicit Save.
final class LocalDrawingLocalFiles {
  LocalDrawingLocalFiles(this.owner)
    : drive = LocalDriveRepository(
        owner.store,
        owner.store.dataPaths!.driveBlobs,
      ) {
    owner.sourceOwner.guard();
    _scopeDrain = retireAndDrain;
    owner.sourceOwner.addRetirementDrain(_scopeDrain);
  }
  final LocalDrawingImageOwner owner;
  final LocalDriveRepository drive;
  late final Future<void> Function() _scopeDrain;
  final _cancel = AttachmentCancellation();
  final Set<Future<void>> _pending = {};
  bool _retired = false;
  Future<void>? _retirement;
  static const maxBytes = 5 * 1024 * 1024;
  void guard() {
    owner.guard();
    if (_retired || owner.controller.busy) {
      throw StateError('Local drawing files retired or busy');
    }
  }

  Future<T> _work<T>(Future<T> Function() operation) {
    guard();
    final result = Future<T>.sync(operation);
    late final Future<void> tracked;
    tracked = result
        .then<void>((_) {}, onError: (Object _, StackTrace _) {})
        .whenComplete(() {
          _pending.remove(tracked);
        });
    _pending.add(tracked);
    return result;
  }

  Future<List<DriveNode>> available({String keyword = '', int page = 1}) =>
      _work(() async {
        if (keyword.length > 200 || page < 1 || page > 1000) {
          throw const FormatException('Invalid local image query');
        }
        final db = await owner.store.database;
        guard();
        final rows = await db.query(
          'local_drive_nodes',
          where: 'directory=0 AND instr(lower(path),lower(?))>0',
          whereArgs: [keyword],
          orderBy: 'path',
          limit: 50,
          offset: (page - 1) * 50,
        );
        guard();
        return rows
            .map(
              (row) => DriveNode(
                id: row['node_id'] as int,
                name: row['name'] as String,
                path: row['path'] as String,
                directory: false,
                size: row['file_size'] as int,
                etag: row['file_hash'] as String,
                mime: row['mime_type'] as String,
                modified: row['modify_time'] as String,
                created: row['create_time'] as String,
              ),
            )
            .toList();
      });
  (int, int) _validate(Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > maxBytes) {
      throw const FormatException('Local raster exceeds 5 MiB');
    }
    final raster =
        bytes.length >= 12 &&
        (bytes[0] == 137 &&
                bytes[1] == 80 &&
                bytes[2] == 78 &&
                bytes[3] == 71 ||
            bytes[0] == 255 && bytes[1] == 216 && bytes[2] == 255 ||
            bytes[0] == 71 && bytes[1] == 73 && bytes[2] == 70 ||
            bytes[0] == 82 &&
                bytes[1] == 73 &&
                bytes[2] == 70 &&
                bytes[3] == 70 &&
                bytes[8] == 87 &&
                bytes[9] == 69 &&
                bytes[10] == 66 &&
                bytes[11] == 80);
    if (!raster) {
      throw const FormatException('PNG/JPEG/GIF/WebP image required');
    }
    final size = encodedImageDimensions(bytes);
    if (size.$1 < 1 ||
        size.$2 < 1 ||
        size.$1 > 16384 ||
        size.$2 > 16384 ||
        size.$1 * size.$2 > 32 * 1024 * 1024) {
      throw const FormatException('Local raster dimensions exceed bound');
    }
    return size;
  }

  String _name(String value) {
    final name = attachmentName(value);
    ComplexEditorDocument.validateText(name);
    return name;
  }

  Future<LocalDrawingSelectedImage> importDeviceFile(XFile selected) =>
      _work(() async {
        final builder = BytesBuilder(copy: false);
        await for (final chunk in selected.openRead()) {
          guard();
          if (builder.length + chunk.length > maxBytes) {
            throw const FormatException('Local image exceeds 5 MiB');
          }
          builder.add(chunk);
        }
        guard();
        final bytes = builder.takeBytes();
        _validate(bytes);
        final name = _name(selected.name);
        final source = await DriveSourceSnapshot.prepare(
          _NamedRasterBytes(bytes, name),
          maxBytes: maxBytes,
          cancellation: _cancel,
        );
        guard();
        const folder = '画板图片';
        final existing = await drive.lookup(folder);
        guard();
        if (existing == null) {
          await drive.mkdir('', folder, cancellation: _cancel);
        } else if (!existing.directory) {
          throw StateError('Local image folder unavailable');
        }
        guard();
        await drive.upload(
          source,
          target: driveChild(folder, '${attachmentId()}-$name'),
          cancellation: _cancel,
        );
        guard();
        return _copy(bytes, name);
      });
  Future<LocalDrawingSelectedImage> selectLibraryFile(DriveNode selected) =>
      _work(() async {
        final bytes = await drive.bytes(
          selected,
          maxBytes: maxBytes,
          cancellation: _cancel,
        );
        guard();
        if (sha256.convert(bytes).toString() != selected.etag) {
          throw StateError('Selected local image changed');
        }
        return _copy(bytes, _name(selected.name));
      });
  Future<LocalDrawingSelectedImage> _copy(Uint8List bytes, String name) async {
    final size = _validate(bytes);
    guard();
    final attachment = await owner.attachments.add(
      _NamedRasterBytes(bytes, name),
      cancellation: _cancel,
    );
    guard();
    return LocalDrawingSelectedImage._(
      this,
      attachment,
      sha256.convert(bytes).toString(),
      size.$1,
      size.$2,
      bytes,
    );
  }

  /// Re-read through the nofollow bounded raster reader before any insertion.
  Future<void> verifySelected(LocalDrawingSelectedImage selected) =>
      _work(() async {
        if (!identical(selected._files, this)) {
          throw StateError('Selected local image belongs to another scope');
        }
        // Read owns only UUID paths in this owner's exact attachment directory.
        final temporary = LocalMarkdownResources(owner.attachments);
        try {
          final image = await temporary.read(selected.attachment.uri);
          final bytes = image.bytes;
          guard();
          if (sha256.convert(bytes).toString() != selected.sha256Hex) {
            throw StateError('Selected local image changed before insertion');
          }
        } finally {
          temporary.close();
        }
      });
  Future<String> prepareExplicitInsertion(
    LocalDrawingImageResources resources,
    LocalDrawingSelectedImage selected,
    ComplexEditorDocument capturedSource,
  ) async {
    guard();
    if (!owner.ownsBody(resources) ||
        capturedSource.kind != ComplexEditorKind.drawing ||
        !capturedSource.same(owner.controller.edit.document)) {
      throw StateError(
        'Actual current locked source and resource body required',
      );
    }
    await verifySelected(selected);
    guard();
    if (!owner.ownsBody(resources) ||
        !capturedSource.same(owner.controller.edit.document)) {
      throw StateError('Source changed during local image approval');
    }
    return resources.approveSelected(
      selected.attachment.uri,
      selectedSha256: selected.sha256Hex,
    );
  }

  Future<void> retireAndDrain() {
    _retired = true;
    _cancel.cancel();
    return _retirement ??= Future.wait<void>(List.of(_pending)).then((_) {
      drive.dispose();
      owner.sourceOwner.removeRetirementDrain(_scopeDrain);
    });
  }
}
