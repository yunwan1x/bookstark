import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/background_repository.dart';
import 'package:bookstark_flutter/core/background_controller.dart';
import 'image_dimensions_test.dart' as dimensions;

const imageHash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

class Repo implements BackgroundRepository {
  BackgroundPreference current = const BackgroundPreference();
  bool lose = false, readFails = false, imageFails = false;
  int writes = 0, reads = 0;
  @override
  Future<BackgroundPreference> read() async {
    reads++;
    if (readFails) {
      throw StateError('fixture read failure');
    }
    return current;
  }

  @override
  Future<BackgroundPreference> update(BackgroundDraft draft) async {
    writes++;
    current = BackgroundPreference(
      mode: draft.mode,
      animated: draft.animated,
      fade: draft.fade,
      imageHash: draft.image != null
          ? imageHash
          : draft.remove
          ? ''
          : current.imageHash,
    );
    if (lose) {
      throw StateError('fixture lost receipt');
    }
    return current;
  }

  @override
  Future<Uint8List> image(String hash) async {
    if (imageFails) {
      throw StateError('fixture private image unavailable');
    }
    return dimensions.png(1, 1);
  }
}

BackgroundDraft draft({
  String mode = 'solid',
  bool remove = false,
  BackgroundUpload? image,
}) => BackgroundDraft(
  mode: mode,
  animated: false,
  fade: 80,
  remove: remove,
  image: image,
);
void main() {
  test(
    'known metadata receipt and exact reread confirm; reset removes only on explicit save',
    () async {
      final r = Repo()
        ..current = const BackgroundPreference(
          mode: 'image',
          imageHash: imageHash,
        );
      final c = BackgroundController(r, r.current);
      final reset = draft(remove: true);
      expect(r.writes, 0);
      expect(r.current.imageHash, imageHash);
      await c.save(reset);
      expect(c.phase, BackgroundPhase.confirmed);
      expect(c.receipt, isNotNull);
      expect(c.baseline.imageHash, isEmpty);
      expect(r.writes, 1);
      c.dispose();
    },
  );
  test(
    'known upload uses server converted hash and verifies actual private bytes',
    () async {
      final r = Repo();
      final c = BackgroundController(r, r.current);
      final image = BackgroundUpload(dimensions.png(1, 1));
      await c.save(draft(mode: 'image', image: image));
      expect(c.phase, BackgroundPhase.confirmed);
      expect(c.baseline.imageHash, imageHash);
      expect(c.verifiedImage, isNotNull);
      expect(r.writes, 1);
      c.dispose();
    },
  );
  test(
    'unknown upload never resends; read shows observed state instead of falsely claiming our file',
    () async {
      final r = Repo()..lose = true;
      final c = BackgroundController(r, r.current);
      await c.save(
        draft(mode: 'image', image: BackgroundUpload(dimensions.png(1, 1))),
      );
      expect(c.phase, BackgroundPhase.unknown);
      await c.save(draft());
      expect(r.writes, 1);
      await c.inspect();
      expect(c.phase, BackgroundPhase.conflict);
      expect(c.receipt, isNull);
      expect(c.verifiedImage, isNull);
      expect(c.useObserved().imageHash, imageHash);
      expect(r.writes, 1);
      c.dispose();
    },
  );
  test(
    'unknown ordinary settings may verify with no image replacement and no second PUT',
    () async {
      final r = Repo()..lose = true;
      final c = BackgroundController(r, r.current);
      await c.save(draft());
      await c.inspect();
      expect(c.phase, BackgroundPhase.confirmed);
      expect(c.receipt, isNull);
      expect(r.writes, 1);
      c.dispose();
    },
  );
  test(
    'changed baseline prevents overwrite; failed image read retains real receipt for later read-only retry',
    () async {
      final r = Repo();
      final c = BackgroundController(r, r.current);
      r.current = const BackgroundPreference(fade: 20);
      await c.save(draft());
      expect(c.phase, BackgroundPhase.conflict);
      expect(r.writes, 0);
      c.useObserved();
      r.imageFails = true;
      await c.save(
        draft(mode: 'image', image: BackgroundUpload(dimensions.png(1, 1))),
      );
      expect(c.phase, BackgroundPhase.unverified);
      expect(c.receipt, isNotNull);
      expect(r.writes, 1);
      r.imageFails = false;
      await c.inspect();
      expect(c.phase, BackgroundPhase.confirmed);
      expect(r.writes, 1);
      c.dispose();
    },
  );
  test(
    'background upload validates immutable bounded format and metadata before any raster allocation',
    () {
      final bytes = dimensions.png(10, 10);
      final upload = BackgroundUpload(bytes);
      bytes[0] = 0;
      expect(upload.bytes.first, 137);
      expect(() => upload.bytes[0] = 0, throwsUnsupportedError);
      for (final bad in [
        Uint8List(0),
        Uint8List(5 * 1024 * 1024 + 1),
        dimensions.png(100000, 100000),
        Uint8List.fromList('GIF89a000000'.codeUnits),
      ]) {
        expect(() => BackgroundUpload(bad), throwsFormatException);
      }
    },
  );
}
