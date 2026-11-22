import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/background_repository.dart';
import 'profile_repository_test.dart' as fixture;
import 'image_dimensions_test.dart' as dimensions;

Map<String, Object?> preference({String hash = '', String mode = 'dynamic'}) =>
    {'mode': mode, 'animated': true, 'fade': 65, 'image_hash': hash};
void main() {
  test(
    'multipart owner background PUT has only four actual fields and optional bounded image',
    () async {
      var writes = 0;
      final upload = BackgroundUpload(dimensions.png(1, 1));
      final client = BookstarkClient(
        'https://example.test/base',
        transport: MockClient((r) async {
          expect(r.followRedirects, false);
          expect(r.headers['cache-control'], 'no-store');
          if (r.url.path == '/base/api/profile') {
            return fixture.data(fixture.profile());
          }
          expect(r.url.path, '/base/api/profile/background');
          if (r.method == 'PUT') {
            writes++;
            expect(r.headers['x-csrf-token'], 'csrf');
            expect(
              r.headers['content-type'],
              startsWith('multipart/form-data; boundary='),
            );
            for (final key in ['mode', 'animated', 'fade', 'remove', 'file']) {
              expect(latin1.decode(r.bodyBytes), contains('name="$key"'));
            }
            expect(
              latin1.decode(r.bodyBytes),
              contains('filename="background-image"'),
            );
            expect(latin1.decode(r.bodyBytes), contains('image'));
            return fixture.data(preference(hash: 'a' * 64, mode: 'image'));
          }
          return fixture.data(preference());
        }),
      )..restoreSession({'token': 'fixture', 'csrf_token': 'csrf'});
      final repo = RemoteBackgroundRepository(client, memberId: 7);
      final draft = BackgroundDraft(
        mode: 'image',
        animated: true,
        fade: 65,
        image: upload,
      );
      await expectLater(
        repo.update(draft),
        throwsA(isA<BackgroundPreflightFailure>()),
      );
      await repo.read();
      expect((await repo.update(draft)).imageHash, 'a' * 64);
      expect(writes, 1);
      client.close();
    },
  );
  test(
    'private JPEG requires actual ETag/hash, bounded same origin and verified session',
    () async {
      final jpeg = Uint8List.fromList([
        255,
        216,
        255,
        192,
        0,
        11,
        8,
        0,
        1,
        0,
        1,
        1,
        1,
        17,
        0,
        255,
        217,
      ]);
      final hash = crypto.sha256.convert(jpeg).toString();
      var reads = 0, bad = false;
      final client = BookstarkClient(
        'https://example.test',
        transport: MockClient((r) async {
          if (r.url.path == '/api/profile') {
            return fixture.data(fixture.profile());
          }
          if (r.url.path.endsWith('/image')) {
            reads++;
            expect(r.headers['cookie'], contains('token=fixture'));
            expect(r.followRedirects, false);
            expect(r.headers['cache-control'], 'no-store');
            return http.Response.bytes(
              jpeg,
              200,
              headers: {
                'content-type': 'image/jpeg',
                'etag': '"${bad ? 'a' * 64 : hash}"',
              },
            );
          }
          return fixture.data(preference(hash: hash, mode: 'image'));
        }),
      )..restoreSession({'token': 'fixture', 'csrf_token': 'csrf'});
      final repo = RemoteBackgroundRepository(client, memberId: 7);
      await repo.read();
      expect(await repo.image(hash), jpeg);
      bad = true;
      await expectLater(repo.image(hash), throwsFormatException);
      client.restoreSession({'token': 'other'});
      await expectLater(
        repo.image(hash),
        throwsA(isA<BackgroundPreflightFailure>()),
      );
      expect(reads, 2);
      client.close();
    },
  );
  test('preference types, range, mode and image-hash are strict', () {
    for (final row in [
      preference()..['mode'] = 'url',
      preference()..['fade'] = 101,
      preference()..['animated'] = 1,
      preference(hash: 'external'),
      preference(mode: 'image'),
    ]) {
      expect(() => BackgroundPreference.fromJson(row), throwsFormatException);
    }
  });
}
