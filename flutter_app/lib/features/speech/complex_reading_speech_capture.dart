import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../../core/complex_editor_transport.dart';
import '../../core/complex_reading_protocol.dart';
import 'local_speech_provider_page.dart';

/// The readable fragment is real selected plain text. It is not complex fulltext.
Future<LocalSpeechSelection> captureComplexReadingSpeech({
  required ComplexEditorTransport transport,
  required ComplexReadingIdentity identity,
  required bool Function() isCurrentSource,
}) async {
  final binding = transport.readingBinding;
  bool current() =>
      isCurrentSource() &&
      binding != null &&
      identical(transport.readingBinding, binding) &&
      binding.identity.same(identity);
  if (!current()) throw StateError('Reading runtime changed');
  final captured = await transport.captureReading(includeSelection: true);
  final range = captured.selection, text = captured.text;
  if (!current() ||
      !captured.supported ||
      text.trim().isEmpty ||
      range == null) {
    throw StateError('No actual readable selection');
  }
  final digest = sha256.convert(utf8.encode(text)).toString();
  final bindingId = jsonEncode({
    'reading': binding!.toJson(),
    'engineRange': range.value,
    'readableDigest': digest,
    'range': {'unit': 'utf16', 'start': 0, 'end': text.length},
    'selectionKind': captured.selectionKind.name,
  });
  return LocalSpeechSelection.captured(
    text: text,
    bindingId: bindingId,
    selectionKind: captured.selectionKind.name,
    isCurrentBinding: current,
    verifyFreshBinding: () async {
      if (!current()) return false;
      try {
        final actual = await transport.captureReading(includeSelection: true);
        return current() &&
            actual.text == text &&
            actual.selection?.same(range) == true &&
            actual.selectionKind == captured.selectionKind;
      } catch (_) {
        return false;
      }
    },
  );
}
