import 'dart:async';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'image_dimensions.dart';
import 'native_local_article_attachment_picker.dart';
import 'owned_complex_image_upload_controller.dart';
import 'owned_complex_resource_lease.dart';

enum OwnedImagePickResult { cancelled, confirmedUrl }

class OwnedImageConfirmation {
  const OwnedImageConfirmation({
    required this.name,
    required this.bytes,
    required this.width,
    required this.height,
  });
  final String name;
  final int bytes, width, height;
}

/// Uses the real opaque Android SAF inbox. Only its owned copy is released.
class OwnedComplexImagePickerAction {
  OwnedComplexImagePickerAction({
    required this.controller,
    required this.lease,
    NativeLocalArticleAttachmentPicker? picker,
  }) : _picker = picker ?? NativeLocalArticleAttachmentPicker(imagesOnly: true);
  final OwnedComplexImageUploadController controller;
  final OwnedComplexResourceLease lease;
  final NativeLocalArticleAttachmentPicker _picker;
  bool _busy = false, _retired = false;
  bool get busy => _busy || controller.busy;
  void _guard() {
    lease.guard();
    if (_retired) throw StateError('Image picker ended');
  }

  Future<OwnedImagePickResult> pickAndUpload({
    required Future<bool> Function(OwnedImageConfirmation selection) confirm,
    required Future<bool> Function() verifyFreshBinding,
    required Future<void> Function() preparePickerHandoff,
    required Future<void> Function() resumeEditor,
  }) async {
    _guard();
    if (busy || !controller.canUpload) {
      throw StateError('Resolve retained upload first');
    }
    _busy = true;
    PickedLocalArticleAttachment? picked;
    var handoff = false;
    try {
      handoff = true;
      // This includes closing the old WebView; it must not be a lease job
      // which its own retirement callback could wait on. The editor checkpoints
      // and native-close barrier own their actual storage/runtime work.
      await preparePickerHandoff();
      _guard();
      picked = await lease.use(_picker.pick);
      _guard();
      final selected = picked;
      if (selected == null) return OwnedImagePickResult.cancelled;
      if (selected.bytes <= 0 || selected.bytes > 5 * 1024 * 1024) {
        throw const FormatException('Image size unsupported');
      }
      final file = await lease.use(() => _picker.open(selected));
      _guard();
      final bytes = await lease.use(() async {
        final builder = BytesBuilder(copy: false);
        var total = 0;
        await for (final part in file.openRead()) {
          _guard();
          total += part.length;
          if (total > selected.bytes || total > 5 * 1024 * 1024) {
            throw const FormatException('Image copy exceeded receipt');
          }
          builder.add(part);
        }
        return builder.takeBytes();
      });
      _guard();
      if (bytes.length != selected.bytes ||
          crypto.sha256.convert(bytes).toString() != selected.sha256) {
        throw const FormatException('Image copy changed');
      }
      final (width, height) = encodedImageDimensions(bytes);
      if (width <= 0 ||
          height <= 0 ||
          width > 8192 ||
          height > 8192 ||
          width * height > 16 * 1024 * 1024) {
        throw const FormatException('Image dimensions unsupported');
      }
      // A human dialog is deliberately not registered as repository work.
      if (!await confirm(
        OwnedImageConfirmation(
          name: selected.name,
          bytes: bytes.length,
          width: width,
          height: height,
        ),
      )) {
        return OwnedImagePickResult.cancelled;
      }
      _guard();
      if (!await lease.use(verifyFreshBinding)) {
        throw StateError('Document source changed');
      }
      _guard();
      final prepared = await lease.use(
        () => lease.client.prepareOwnedImageUpload(
          imageBytes: bytes,
          fileName: selected.name,
          inputSHA256: selected.sha256,
          expectedMemberId: lease.memberId,
          expectedSessionRevision: lease.revision,
          ownerGuard: _guard,
          abortTrigger: lease.abortTrigger,
        ),
      );
      try {
        _guard();
        await controller.upload(prepared);
        _guard();
        // The SAF activity retired the previous WebView. Retain the URL, then let
        // the user explicitly insert into a fresh runtime's current selection.
        return OwnedImagePickResult.confirmedUrl;
      } finally {
        prepared.retire();
      }
    } finally {
      try {
        if (picked != null) await _picker.release(picked);
      } finally {
        _busy = false;
        if (handoff && !_retired && lease.current) await resumeEditor();
      }
    }
  }

  Future<void> retireAndDrain() async {
    _retired = true;
    lease.retire();
    await _picker.dispose();
    await controller.retireAndDrain();
  }
}
