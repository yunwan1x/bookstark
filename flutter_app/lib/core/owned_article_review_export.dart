import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'complex_editor_document.dart';

/// Immutable exact retained record/source. This is export-only authority, not a
/// parsed editable article and not evidence that a POST did or did not happen.
class OwnedArticleReviewExport {
  OwnedArticleReviewExport({
    required String source,
    required this.mime,
    required this.name,
  }) : _bytes = Uint8List.fromList(utf8.encode(source)) {
    ComplexEditorDocument.validateText(source);
    if (_bytes.length > 32 * 1024 * 1024 ||
        !const {
          'application/json',
          'text/plain',
          'text/markdown',
        }.contains(mime)) {
      throw const FormatException('Retained export exceeds bounds');
    }
  }
  final Uint8List _bytes;
  Uint8List get bytes => _bytes.asUnmodifiableView();
  final String mime, name;
  late final String digest = sha256.convert(_bytes).toString();
}
