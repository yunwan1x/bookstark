import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as paths;
import 'package:path_provider/path_provider.dart';
import 'attachments.dart';
import 'complex_editor_document.dart';
import 'complex_editor_transport.dart';
import 'drive_models.dart';
import 'drive_source.dart';
import 'html_editor_controller.dart';
import 'html_recovery_vault.dart';
import 'image_dimensions.dart';
import 'local_attachments.dart';
import 'local_drive_repository.dart';
import 'local_html_attachment_reference.dart';
import 'local_html_resources_repository.dart';
import 'local_store.dart';
import 'native_complex_source_io.dart';

/// A file actually copied into this local space by an explicit user selection.
class LocalHtmlSelectedAttachment {
  LocalHtmlSelectedAttachment._(this._owner, this.attachment, this.sha256Hex,
      this.width, this.height, Uint8List? raster)
    : previewBytes = raster == null ? null :
        Uint8List.fromList(raster).asUnmodifiableView();
  final LocalHtmlNoteAttachments _owner;
  final Attachment attachment;
  final String sha256Hex;
  final int? width, height;
  final Uint8List? previewBytes;
  bool get image => width != null && height != null;
}

/// cross_file IO ignores XFile.fromData(name:). Keep this bounded in-memory
/// copy's real selected display name; no caller filesystem path is introduced.
class _NamedLocalHtmlBytes extends XFile {
  _NamedLocalHtmlBytes(super.bytes, this._name, {super.lastModified})
    : super.fromData();
  final String _name;
  @override
  String get name => _name;
}

/// Ordinary local HTML only. It never uploads or saves a note body.
class LocalHtmlNoteAttachments {
  LocalHtmlNoteAttachments._(this.store, this.editor, this.sourceOwner,
      this.isCurrentScope, this.attachments, this.drive, this.library);
  final LocalStore store;
  final HtmlEditorController editor;
  final ComplexSourceIoScope sourceOwner;
  final bool Function() isCurrentScope;
  final LocalAttachments attachments;
  final LocalDriveRepository drive;
  final LocalHtmlResourcesRepository library;
  late final Future<void> Function() _drainRegistration;
  final _cancellation = AttachmentCancellation();
  final Set<Future<void>> _pending = {};
  bool _retired = false;
  Future<void>? _retirement;
  static const maxFileBytes = 20 * 1024 * 1024;

  static Future<LocalHtmlNoteAttachments> open({
    required LocalStore store,
    required HtmlEditorController editor,
    required ComplexSourceIoScope sourceOwner,
    required bool Function() isCurrentScope,
  }) async {
    void guard() {
      sourceOwner.guard();
      final meta = editor.baseline.metadata;
      if (!isCurrentScope() || store.maintenance.retired ||
          meta.id <= 0 || !{'note','article'}.contains(meta.collection) ||
          meta.protected) {
        throw StateError('Ordinary local HTML owner required');
      }
    }
    guard();
    var attachmentsDirectory = store.dataPaths?.attachments;
    var driveDirectory = store.dataPaths?.driveBlobs;
    if (attachmentsDirectory == null || driveDirectory == null) {
      final support = await getApplicationSupportDirectory();
      guard();
      final root = await support.resolveSymbolicLinks();
      guard();
      attachmentsDirectory ??= Directory(paths.join(root, 'attachments'));
      driveDirectory ??= Directory(paths.join(root, 'drive-blobs'));
    }
    final attachments = LocalAttachments(attachmentsDirectory,
      maintenance: store.maintenance);
    final drive = LocalDriveRepository(store, driveDirectory);
    final owner = LocalHtmlNoteAttachments._(store, editor, sourceOwner, isCurrentScope,
      attachments, drive, LocalHtmlResourcesRepository(store, drive,
        collection: editor.baseline.metadata.collection));
    owner._drainRegistration = owner.retireAndDrain;
    sourceOwner.addRetirementDrain(owner._drainRegistration);
    return owner;
  }

  void guard() {
    sourceOwner.guard();
    if (_retired || !isCurrentScope() || store.maintenance.retired ||
        !editor.canEdit || editor.hasPendingOperation ||
        editor.baseline.metadata.protected) {
      throw StateError('Local HTML attachment owner retired or readonly');
    }
  }

  Future<T> _work<T>(Future<T> Function() operation) {
    guard();
    final result = Future<T>.sync(operation);
    late final Future<void> tracked;
    tracked = result.then<void>((_) {}, onError: (Object _, StackTrace _) {})
      .whenComplete(() { _pending.remove(tracked); });
    _pending.add(tracked);
    return result;
  }

  Future<List<DriveNode>> available({String keyword = '', int page = 1}) =>
      _work(() async {
        final result = await library.available(keyword: keyword, page: page);
        guard();
        return result;
      });

  Future<LocalHtmlSelectedAttachment> importDeviceFile(XFile selected) =>
      _work(() async {
        final builder = BytesBuilder(copy: false);
        await for (final chunk in selected.openRead()) {
          guard();
          if (builder.length + chunk.length > maxFileBytes) {
            throw const FormatException('Local attachment exceeds 20 MiB');
          }
          builder.add(chunk);
        }
        guard();
        final bytes = builder.takeBytes();
        final source = await DriveSourceSnapshot.prepare(
          _NamedLocalHtmlBytes(bytes, attachmentName(selected.name),
            lastModified: DateTime.now().toUtc()),
          maxBytes: maxFileBytes, cancellation: _cancellation);
        guard();
        const folder = 'HTML附件';
        final existing = await drive.lookup(folder);
        guard();
        if (existing == null) {
          await drive.mkdir('', folder, cancellation: _cancellation);
          guard();
        } else if (!existing.directory) {
          throw StateError('Local attachment library folder unavailable');
        }
        final target = driveChild(folder,
          '${attachmentId()}-${attachmentName(selected.name)}');
        await drive.upload(source, target: target, cancellation: _cancellation);
        guard();
        // The durable original stays discoverable in the local file library
        // even when the user later chooses Keep file instead of inserting.
        return _copySelected(bytes, selected.name);
      });

  Future<LocalHtmlSelectedAttachment> selectLibraryFile(DriveNode selected) =>
      _work(() async {
        final bytes = await drive.bytes(selected, maxBytes: maxFileBytes,
          cancellation: _cancellation);
        guard();
        if (sha256.convert(bytes).toString() != selected.etag) {
          throw StateError('Selected local library file changed');
        }
        return _copySelected(bytes, selected.name);
      });

  Future<LocalHtmlSelectedAttachment> _copySelected(Uint8List bytes, String name) async {
    guard();
    int? width, height;
    final raster = bytes.length >= 12 &&
      (bytes[0] == 137 && bytes[1] == 80 && bytes[2] == 78 && bytes[3] == 71 ||
       bytes[0] == 255 && bytes[1] == 216 && bytes[2] == 255 ||
       bytes[0] == 71 && bytes[1] == 73 && bytes[2] == 70 ||
       bytes[0] == 82 && bytes[1] == 73 && bytes[2] == 70 && bytes[3] == 70 &&
       bytes[8] == 87 && bytes[9] == 69 && bytes[10] == 66 && bytes[11] == 80);
    if (raster) {
      final dimensions = encodedImageDimensions(bytes);
      if (dimensions.$1 < 1 || dimensions.$2 < 1 ||
          dimensions.$1 > 16384 || dimensions.$2 > 16384 ||
          dimensions.$1 * dimensions.$2 > 32 * 1024 * 1024 ||
          bytes.length > 5 * 1024 * 1024) {
        throw const FormatException('Local raster exceeds image limits');
      }
      width = dimensions.$1;
      height = dimensions.$2;
    }
    guard();
    final attachment = await attachments.add(
      _NamedLocalHtmlBytes(bytes, attachmentName(name)),
      cancellation: _cancellation,
    );
    guard();
    // Published user assets are retained; never delete an existing source file.
    return LocalHtmlSelectedAttachment._(
      this, attachment, sha256.convert(bytes).toString(), width, height,
      width == null ? null : bytes);
  }

  Future<Uint8List> _readSelected(LocalHtmlSelectedAttachment selected) async {
    if (!identical(selected._owner, this)) throw StateError('Wrong local file owner');
    final uri = selected.attachment.uri;
    localHtmlAttachmentName(uri);
    var directory = paths.normalize(attachments.directory.absolute.path);
    while (true) {
      if (await FileSystemEntity.type(directory, followLinks: false) ==
          FileSystemEntityType.link) {
        throw const FormatException('Local attachment directory link rejected');
      }
      guard();
      final parent = paths.dirname(directory);
      if (parent == directory) break;
      directory = parent;
    }
    final file = File(paths.join(attachments.directory.path, uri.pathSegments.first));
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw const FormatException('Local attachment unavailable');
    }
    guard();
    final bytes = await attachments.read(uri, maxBytes: maxFileBytes);
    guard();
    if (sha256.convert(bytes).toString() != selected.sha256Hex) {
      throw StateError('Local attachment changed before insertion');
    }
    return bytes;
  }

  /// Caller keeps the real editor input locked, then checkpoints its actual
  /// post-insertion source through HtmlSourceCoordinator. This does no SQL save.
  Future<void> insert(ComplexEditorTransport transport,
      ComplexEditorSnapshot snapshot, LocalHtmlSelectedAttachment selected) =>
      _work(() async {
        await _readSelected(selected);
        guard();
        if (snapshot.document.kind != ComplexEditorKind.html ||
            snapshot.document.source != editor.draft.source) {
          throw StateError('Current durable HTML source snapshot required');
        }
        final meta = editor.baseline.metadata;
        final identity = sha256.convert(utf8.encode(jsonEncode([
          store.path, meta.collection, meta.id, 'html',
          htmlNoteFingerprint(editor.baseline), snapshot.document.digest,
          sourceOwner.scope, sourceOwner.epoch,
        ]))).toString();
        await transport.authorizeLocalHtmlAttachments(snapshot: snapshot,
          scope: sourceOwner.scope,
          scopeEpoch: sourceOwner.epoch, identityDigest: identity);
        guard();
        await transport.insertLocalHtmlAttachment(snapshot,
          uri: selected.attachment.uri, image: selected.image,
          width: selected.width, height: selected.height);
        guard();
      });

  Future<void> retireAndDrain() {
    final existing = _retirement;
    if (existing != null) return existing;
    _retired = true;
    _cancellation.cancel();
    return _retirement = Future.wait<void>(List.of(_pending))
      .whenComplete(() {
        drive.dispose();
        sourceOwner.removeRetirementDrain(_drainRegistration);
      });
  }
}
