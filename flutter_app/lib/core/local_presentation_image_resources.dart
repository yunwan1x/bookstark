import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'image_dimensions.dart';
import 'local_attachments.dart';
import 'local_presentation_image_references.dart';
import 'local_markdown_resources.dart';

/// Native virtual-HTTPS paths contain only these opaque resource IDs. Mapping
/// to a canonical UUID or inline bytes belongs to this exact source owner.
final class LocalPresentationImageResources {
  LocalPresentationImageResources({
    required LocalAttachments attachments,
    required this.references,
    required this.identity,
    required this.isCurrentScope,
    this.onReadFailure,
    this.onRetired,
  }) : _reader = LocalMarkdownResources(attachments) {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(identity)) {
      throw const FormatException('Bound presentation image identity required');
    }
    for (final item in references.files.values) {
      final old = _originalByResource[item.resourceId];
      if (old != null && old.sourceValue != item.sourceValue) {
        throw const FormatException('Ambiguous presentation image authority');
      }
      _originalByResource[item.resourceId] = item;
    }
  }
  final LocalPresentationImageReferences references;
  final String identity;
  final bool Function() isCurrentScope;
  final void Function()? onReadFailure, onRetired;
  final LocalMarkdownResources _reader;
  final _originalByResource = <String, LocalPresentationImageReference>{};
  final _selected = <String, (Uri, String)>{};
  final _pending = <Future<void>>{};
  final _charged = <String>{};
  var _totalBytes = 0, _totalPixels = 0;
  bool _retired = false, _failed = false;
  Future<void>? _retirement;
  bool get complete => references.complete && !_failed;
  bool get referencesUnavailable => !references.complete;
  bool get current {
    try {
      return !_retired && isCurrentScope();
    } catch (_) {
      return false;
    }
  }

  void guard() {
    if (!current) throw StateError('Local presentation image scope retired');
  }

  /// A Dart-owned, freshly verified selection only. Never called by JS or by a
  /// resource-read callback. One resource ID cannot be rebound to other bytes.
  String approveSelected(Uri uri, {required String selectedSha256}) {
    guard();
    LocalMarkdownResources.identity(uri);
    if (!complete || !RegExp(r'^[a-f0-9]{64}$').hasMatch(selectedSha256)) {
      throw StateError('Presentation source cannot approve another image');
    }
    final id = sha256
        .convert(
          utf8.encode(
            jsonEncode([
              'ordinary-local-presentation-selected-v1',
              identity,
              uri.toString(),
              selectedSha256,
            ]),
          ),
        )
        .toString();
    final old = _selected[id];
    if (old != null && (old.$1 != uri || old.$2 != selectedSha256)) {
      throw StateError('Presentation image identity changed');
    }
    if ({..._originalByResource.keys, ..._selected.keys, id}.length > 32) {
      throw const FormatException('Presentation image count bound');
    }
    _selected[id] = (uri, selectedSha256);
    return id;
  }

  Map<String, String> get sourceFileResources => Map.unmodifiable({
    for (final item in references.files.values) item.fileId: item.resourceId,
  });

  Future<LocalMarkdownImage> read(String resourceId) {
    guard();
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(resourceId)) {
      throw const FormatException('Invalid presentation image resource ID');
    }
    final original = _originalByResource[resourceId];
    final selected = _selected[resourceId];
    if (original == null && selected == null) {
      throw const FormatException(
        'Image not referenced or selected for this presentation',
      );
    }
    final result = Future<LocalMarkdownImage>.sync(() async {
      guard();
      try {
        final LocalMarkdownImage image;
        if (original?.inlineBytes != null) {
          final bytes = original!.inlineBytes!;
          final size = encodedImageDimensions(bytes);
          image = LocalMarkdownImage(
            bytes,
            original.inlineMime!,
            size.$1 * size.$2,
          );
        } else {
          image = await _reader.read(selected?.$1 ?? original!.attachment!);
        }
        guard();
        if (selected != null &&
            sha256.convert(image.bytes).toString() != selected.$2) {
          throw StateError('Selected presentation image bytes changed');
        }
        if (!_charged.contains(resourceId)) {
          if (_totalBytes + image.bytes.length > 20 * 1024 * 1024 ||
              _totalPixels + image.pixels > 64 * 1024 * 1024) {
            _reader.close();
            throw const FormatException(
              'Presentation image scope budget exceeded',
            );
          }
          _charged.add(resourceId);
          _totalBytes += image.bytes.length;
          _totalPixels += image.pixels;
        }
        return image;
      } catch (_) {
        if (!_retired) {
          _failed = true;
          onReadFailure?.call();
        }
        rethrow;
      }
    });
    late final Future<void> tracked;
    tracked = result
        .then<void>((_) {}, onError: (Object _, StackTrace _) {})
        .whenComplete(() {
          _pending.remove(tracked);
        });
    _pending.add(tracked);
    return result;
  }

  Future<void> retireAndDrain() {
    _retired = true;
    _reader.close();
    _selected.clear();
    return _retirement ??= Future.wait<void>(List.of(_pending)).then((_) {
      _originalByResource.clear();
      _charged.clear();
      onRetired?.call();
    });
  }
}
