import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'api_client.dart';
import 'profile_repository.dart';
import 'image_dimensions.dart';

class BackgroundPreference {
  const BackgroundPreference({
    this.mode = 'dynamic',
    this.animated = true,
    this.fade = 65,
    this.imageHash = '',
  });
  final String mode, imageHash;
  final bool animated;
  final int fade;
  factory BackgroundPreference.fromJson(Map<String, Object?> row) {
    final mode = row['mode'],
        animated = row['animated'],
        fade = row['fade'],
        hash = row['image_hash'];
    if (mode is! String ||
        !{'solid', 'dynamic', 'image'}.contains(mode) ||
        animated is! bool ||
        fade is! int ||
        fade < 0 ||
        fade > 100 ||
        hash is! String ||
        hash.isNotEmpty && !RegExp(r'^[0-9a-f]{64}$').hasMatch(hash) ||
        mode == 'image' && hash == '') {
      throw const FormatException('Invalid background preference');
    }
    return BackgroundPreference(
      mode: mode,
      animated: animated,
      fade: fade,
      imageHash: hash,
    );
  }
  bool same(BackgroundPreference other) =>
      mode == other.mode &&
      animated == other.animated &&
      fade == other.fade &&
      imageHash == other.imageHash;
}

class BackgroundUpload {
  BackgroundUpload(Uint8List bytes)
    : bytes = Uint8List.fromList(bytes).asUnmodifiableView() {
    if (bytes.isEmpty || bytes.length > 5 * 1024 * 1024) {
      throw const FormatException('Background exceeds5MiB');
    }
    final png =
        bytes.length >= 8 &&
        bytes[0] == 137 &&
        bytes[1] == 80 &&
        bytes[2] == 78 &&
        bytes[3] == 71;
    final jpeg =
        bytes.length >= 3 &&
        bytes[0] == 255 &&
        bytes[1] == 216 &&
        bytes[2] == 255;
    final webp =
        bytes.length >= 12 &&
        String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
        String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP';
    if (!png && !jpeg && !webp) {
      throw const FormatException('Background must be PNG, JPEG or WebP');
    }
    final (w, h) = encodedImageDimensions(bytes);
    if (w * h > 20000000) {
      throw const FormatException('Background exceeds20 megapixels');
    }
  }
  final Uint8List bytes;
}

class BackgroundDraft {
  const BackgroundDraft({
    required this.mode,
    required this.animated,
    required this.fade,
    this.remove = false,
    this.image,
  });
  final String mode;
  final bool animated, remove;
  final int fade;
  final BackgroundUpload? image;
  void validate(BackgroundPreference baseline) {
    if (!{'solid', 'dynamic', 'image'}.contains(mode) ||
        fade < 0 ||
        fade > 100 ||
        mode == 'image' &&
            image == null &&
            (remove || baseline.imageHash.isEmpty)) {
      throw const FormatException('Invalid background draft');
    }
  }

  bool matches(BackgroundPreference value, {String? uploadedHash}) =>
      mode == value.mode &&
      animated == value.animated &&
      fade == value.fade &&
      (image != null
          ? uploadedHash != null && value.imageHash == uploadedHash
          : !remove || value.imageHash.isEmpty);
  Map<String, String> get fields => {
    'mode': mode,
    'animated': '$animated',
    'fade': '$fade',
    'remove': '$remove',
  };
}

class BackgroundPreflightFailure implements Exception {
  const BackgroundPreflightFailure();
}

abstract interface class BackgroundRepository {
  Future<BackgroundPreference> read();
  Future<BackgroundPreference> update(BackgroundDraft draft);
  Future<Uint8List> image(String hash);
}

class RemoteBackgroundRepository implements BackgroundRepository {
  RemoteBackgroundRepository(this.client, {required this.memberId});
  final BookstarkClient client;
  final int memberId;
  BackgroundPreference? _baseline;
  String? _session;
  @override
  Future<BackgroundPreference> read() async {
    _baseline = null;
    final session = client.exportSession()['token'];
    await RemoteProfileRepository(client, memberId: memberId).read();
    final value = BackgroundPreference.fromJson(
      await client.backgroundSettingsJson(),
    );
    if (client.exportSession()['token'] != session) {
      throw const BackgroundPreflightFailure();
    }
    _session = session;
    _baseline = value;
    return value;
  }

  @override
  Future<BackgroundPreference> update(BackgroundDraft draft) async {
    if (_baseline == null || client.exportSession()['token'] != _session) {
      throw const BackgroundPreflightFailure();
    }
    draft.validate(_baseline!);
    return BackgroundPreference.fromJson(
      await client.updateBackgroundJson(
        draft.fields,
        image: draft.image?.bytes,
      ),
    );
  }

  @override
  Future<Uint8List> image(String hash) async {
    if (_baseline == null ||
        _baseline!.imageHash != hash ||
        client.exportSession()['token'] != _session) {
      throw const BackgroundPreflightFailure();
    }
    final bytes = await client.backgroundImageBytes(hash);
    if (crypto.sha256.convert(bytes).toString() != hash) {
      throw const FormatException(
        'Private image digest differs from actual preference',
      );
    }
    final (w, h) = encodedImageDimensions(bytes);
    if (w > 2560 || h > 2560) {
      throw const FormatException('Unexpected background dimensions');
    }
    return bytes;
  }
}
