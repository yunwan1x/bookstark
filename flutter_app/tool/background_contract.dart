import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/background_repository.dart';
import 'package:bookstark_flutter/core/background_controller.dart';

void check(bool value, String message) {
  if (!value) {
    throw StateError(message);
  }
}

Future<void> runBackgroundContract(BookstarkClient client, int memberId) async {
  final repo = RemoteBackgroundRepository(client, memberId: memberId);
  final initial = await repo.read();
  check(
    initial.mode == 'dynamic' &&
        initial.animated &&
        initial.fade == 65 &&
        initial.imageHash.isEmpty,
    'Actual empty-account background defaults',
  );
  final source = await File(
    '../docs/flutter-rewrite/pages/08-editor.png',
  ).readAsBytes();
  final upload = BackgroundUpload(Uint8List.fromList(source));
  final controller = BackgroundController(repo, initial);
  try {
    await controller.save(
      BackgroundDraft(mode: 'image', animated: false, fade: 80, image: upload),
    );
    check(
      controller.phase == BackgroundPhase.confirmed &&
          controller.receipt != null &&
          controller.verifiedImage != null,
      'Actual multipart image save receipt and fresh private JPEG verified',
    );
    final actual = controller.baseline, bytes = controller.verifiedImage!;
    check(
      bytes[0] == 255 &&
          bytes[1] == 216 &&
          crypto.sha256.convert(bytes).toString() == actual.imageHash,
      'Stored hash belongs to actual JPEG transformation',
    );
    check(
      crypto.sha256.convert(source).toString() != actual.imageHash,
      'Source PNG hash is not mistaken for stored JPEG hash',
    );
    final anonymous = BookstarkClient(client.baseUri.toString());
    var denied = false;
    try {
      await anonymous.backgroundImageBytes(actual.imageHash);
    } on ApiFailure catch (e) {
      denied = {401, 403}.contains(e.status);
    } finally {
      anonymous.close();
    }
    check(denied, 'Private background cannot be fetched anonymously');
    await controller.save(
      const BackgroundDraft(mode: 'solid', animated: false, fade: 0),
    );
    check(
      controller.phase == BackgroundPhase.confirmed &&
          controller.baseline.imageHash == actual.imageHash,
      'Switching mode preserves account private image',
    );
    final external = RemoteBackgroundRepository(client, memberId: memberId);
    await external.read();
    await external.update(
      const BackgroundDraft(mode: 'dynamic', animated: true, fade: 25),
    );
    await controller.save(
      const BackgroundDraft(mode: 'solid', animated: false, fade: 100),
    );
    check(
      controller.phase == BackgroundPhase.conflict &&
          (await repo.read()).fade == 25,
      'Observed server change blocks overwrite',
    );
    controller.useObserved();
    await controller.save(
      const BackgroundDraft(
        mode: 'dynamic',
        animated: true,
        fade: 65,
        remove: true,
      ),
    );
    check(
      controller.phase == BackgroundPhase.confirmed &&
          controller.baseline.imageHash.isEmpty,
      'Explicit restore removes private image and verifies default settings',
    );
    var gone = false;
    try {
      await client.backgroundImageBytes(actual.imageHash);
    } on ApiFailure catch (e) {
      gone = e.status == 404;
    }
    check(gone, 'Actual private image endpoint404 after confirmed removal');
    stdout.writeln(
      'PASS actual private background: empty-account defaults, owner multipart PNG upload converted to JPEG, real ETag and SHA256 bytes, anonymous denial, preserved image while switching mode, concurrent baseline conflict and explicit default reset/removal404; disposable fixture only',
    );
  } finally {
    controller.dispose();
    await repo.read();
    await repo.update(
      const BackgroundDraft(
        mode: 'dynamic',
        animated: true,
        fade: 65,
        remove: true,
      ),
    );
  }
}
