import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../../core/complex_editor_transport.dart';
import '../../core/public_selection_protocol.dart';
import '../../core/public_complex_source.dart';
import '../../core/public_share_models.dart';
import 'local_speech_provider_page.dart';

PublicSelectionIdentity publicSpeechIdentity(PublicComplexContent content) {
  final actual = content.identity;
  if (actual == null) throw StateError('Public identity unavailable');
  PublicShareNode? chapter;
  if (content.chapterIdentify != null) {
    PublicShareNode? find(List<PublicShareNode> rows) {
      for (final row in rows) {
        if (row.identify == content.chapterIdentify) return row;
        final child = find(row.children);
        if (child != null) return child;
      }
      return null;
    }

    chapter = find(actual.nodes);
    if (chapter == null) throw StateError('Actual public chapter unavailable');
  }
  return PublicSelectionIdentity(
    kind: content.document.kind,
    sourceDigest: content.document.digest,
    tuple: jsonEncode({
      'reference': content.reference.canonicalUri.toString(),
      'shareId': actual.shareId,
      'targetId': actual.targetId,
      'shareType': actual.kind.name,
      'format': actual.format,
      'protected': actual.protected,
      'title': content.title,
      'chapterId': chapter?.id,
      'chapterIdentify': content.chapterIdentify,
      'chapterFormat': chapter?.format,
    }),
  );
}

Future<LocalSpeechSelection> capturePublicReadingSpeech({
  required ComplexEditorTransport transport,
  required PublicSelectionIdentity identity,
  required bool Function() isCurrent,
  required Future<PublicComplexContent> Function() freshSource,
}) async {
  final binding = transport.publicSelectionBinding;
  bool current() =>
      isCurrent() &&
      binding != null &&
      identical(transport.publicSelectionBinding, binding) &&
      binding.identity.identityDigest == identity.identityDigest &&
      binding.identity.sourceDigest == identity.sourceDigest;
  if (!current()) throw StateError('Public reading runtime changed');
  final captured = await transport.capturePublicSelection();
  if (!current()) throw StateError('Public reading runtime changed');
  final text = captured.text, range = captured.range;
  Future<bool> verify() async {
    if (!current()) return false;
    try {
      final fresh = publicSpeechIdentity(await freshSource());
      if (!current() ||
          fresh.identityDigest != identity.identityDigest ||
          fresh.sourceDigest != identity.sourceDigest) {
        return false;
      }
      final actual = await transport.capturePublicSelection();
      return current() &&
          actual.text == text &&
          actual.kind == captured.kind &&
          actual.range.same(range);
    } catch (_) {
      return false;
    }
  }

  if (!await verify()) throw StateError('Public selection changed');
  return LocalSpeechSelection.captured(
    text: text,
    bindingId: jsonEncode({
      'public': binding!.toJson(),
      'engineRange': range.value,
      'readableDigest': sha256.convert(utf8.encode(text)).toString(),
      'range': {'unit': 'utf16', 'start': 0, 'end': text.length},
      'selectionKind': captured.kind.name,
    }),
    selectionKind: captured.kind.name,
    isCurrentBinding: current,
    verifyFreshBinding: verify,
  );
}
