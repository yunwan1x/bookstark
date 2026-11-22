import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'package:bookstark_flutter/core/background_repository.dart';

// Synthetic2x2 test-only PNG. Actual JPEG conversion has a separate real-Go contract.
final backgroundFixturePixels = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAE0lEQVR4nGPYcuUXEDE8u/MLiABHKAp9dFYAzwAAAABJRU5ErkJggg==',
);

class BackgroundFixture implements BackgroundRepository {
  BackgroundFixture({this.loseReceipt = false});
  final bool loseReceipt;
  BackgroundPreference current = const BackgroundPreference();
  Uint8List? _bytes;
  @override
  Future<BackgroundPreference> read() async => current;
  @override
  Future<BackgroundPreference> update(BackgroundDraft draft) async {
    if (draft.remove) {
      _bytes = null;
    }
    if (draft.image != null) {
      _bytes = draft.image!.bytes;
    }
    current = BackgroundPreference(
      mode: draft.mode,
      animated: draft.animated,
      fade: draft.fade,
      imageHash: _bytes == null
          ? ''
          : crypto.sha256.convert(_bytes!).toString(),
    );
    if (loseReceipt) {
      throw StateError('Fixture lost receipt');
    }
    return current;
  }

  @override
  Future<Uint8List> image(String hash) async {
    if (_bytes == null || hash != current.imageHash) {
      throw StateError('Fixture image unavailable');
    }
    return _bytes!;
  }
}
