import 'dart:async';
import 'package:crypto/crypto.dart';
import 'local_attachments.dart';
import 'local_markdown_resources.dart';
import 'local_mindmap_image_references.dart';

/// One ordinary-local mind-map source and native runtime body. It has no
/// account client, network fallback, caller filesystem path or generic file API.
final class LocalMindmapImageResources {
  LocalMindmapImageResources({
    required LocalAttachments attachments,
    required this.references,
    required this.identity,
    required this.isCurrentScope,
    this.onRetired,
    this.referencesUnavailable = false,
  }) : _reader = LocalMarkdownResources(attachments) {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(identity)) {
      throw const FormatException('Bound local mind-map identity required');
    }
  }
  final LocalMindmapImageReferences references;
  final String identity;
  final bool referencesUnavailable;
  final bool Function() isCurrentScope;
  final void Function()? onRetired;
  final LocalMarkdownResources _reader;
  final Set<Future<void>> _pending = {};
  final Map<Uri, String> _selected = {};
  bool _retired = false;
  Future<void>? _retirement;
  bool get current {
    try {
      return !_retired && isCurrentScope();
    } catch (_) {
      return false;
    }
  }

  void guard() {
    if (!current) throw StateError('Local mind-map image scope retired');
  }

  /// Trusted local selection controller only, after a fresh file hash read.
  /// Native/JS resource requests never call or expand this approval.
  void approveSelected(Uri uri, {required String selectedSha256}) {
    guard();
    LocalMarkdownResources.identity(uri);
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(selectedSha256) ||
        {...references.references, ..._selected.keys, uri}.length > 32) {
      throw const FormatException('Bound selected image approval required');
    }
    final old = _selected[uri];
    if (old != null && old != selectedSha256) {
      throw StateError('Selected local image identity changed');
    }
    _selected[uri] = selectedSha256;
  }

  Future<LocalMarkdownImage> read(Uri uri) {
    guard();
    LocalMarkdownResources.identity(uri);
    if (!references.references.contains(uri) && !_selected.containsKey(uri)) {
      throw const FormatException('Image not referenced by this source');
    }
    final result = Future<LocalMarkdownImage>.sync(() async {
      guard();
      final image = await _reader.read(uri);
      guard();
      final expected = _selected[uri];
      if (expected != null &&
          sha256.convert(image.bytes).toString() != expected) {
        throw StateError('Selected local image bytes changed');
      }
      return image;
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
      onRetired?.call();
    });
  }
}
