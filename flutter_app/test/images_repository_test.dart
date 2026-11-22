import 'dart:convert';
import 'dart:typed_data';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/images_repository.dart';
import 'package:bookstark_flutter/core/attachments.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response reply(Object value, {int status = 200}) => http.Response(
  jsonEncode({
    'code': status == 200 ? 0 : status,
    'data': value,
    'message': 'fixture',
  }),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
Map<String, Object?> row({String url = '/upload-files/note/photo.webp'}) => {
  'id': 7,
  'file_name': 'photo.png',
  'url': url,
  'thumb_url': '',
  'category': 'note',
  'mime_type': 'image/png',
  'file_size': 12,
  'width': 128,
  'height': 64,
  'create_time': '2026-11-04 10:20',
};
BookstarkClient client(Future<http.Response> Function(http.Request) handler) {
  final value = BookstarkClient(
    'https://example.test/base',
    transport: MockClient(handler),
  );
  value.restoreSession({'csrf_token': 'fixture'});
  addTearDown(value.close);
  return value;
}

void main() {
  test(
    'list keeps global byte statistic and original MIME despite WebP storage',
    () async {
      final auth = client((request) async {
        expect(request.url.queryParameters['category'], 'note');
        expect(request.url.queryParameters.containsKey('member_id'), isFalse);
        return http.Response(
          jsonEncode({
            'code': 0,
            'data': [row()],
            'total': 1,
            'page': 1,
            'page_size': 20,
            'total_size': 99999,
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final repo = RemoteImagesRepository(auth);
      addTearDown(repo.dispose);
      final result = await repo.list(
        const ImagesQuery(category: ImageCategory.note),
      );
      expect(repo.publicLinks, isTrue);
      expect(result.totalImageBytes, 99999);
      expect(result.items.single.mime, 'image/png');
      expect(
        result.items.single.uri.path,
        '/base/upload-files/note/photo.webp',
      );
      expect(result.items.single.name, 'photo.png');
    },
  );
  test(
    'cross-host and private references never become trusted public images',
    () async {
      for (final url in [
        'https://other.test/upload-files/a.webp',
        '//other.test/upload-files/a.webp',
        '/api/webdav/files/download',
        '/upload-files/a/../secret.webp',
        '/upload-files/%2e%2e/secret.webp',
        '/upload-files/a.webp?redirect=1',
      ]) {
        final auth = client(
          (_) async => http.Response(
            jsonEncode({
              'code': 0,
              'data': [row(url: url)],
              'total': 1,
              'page': 1,
              'page_size': 20,
              'total_size': 12,
            }),
            200,
          ),
        );
        final repo = RemoteImagesRepository(auth);
        addTearDown(repo.dispose);
        await expectLater(
          repo.list(const ImagesQuery()),
          throwsFormatException,
          reason: url,
        );
      }
    },
  );
  test('hash miss is distinct from access denial', () async {
    var status = 404;
    final auth = client((_) async => reply({}, status: status));
    final repo = RemoteImagesRepository(auth);
    addTearDown(repo.dispose);
    final hash = List.filled(64, 'a').join();
    expect(await repo.byHash(hash), isNull);
    status = 403;
    await expectLater(repo.byHash(hash), throwsA(isA<ApiFailure>()));
  });
  test(
    'upload snapshot and streamed progress preserve selected bytes and actual reply ID',
    () async {
      final source = Uint8List.fromList([1, 2, 3]);
      final payload = ImageUploadPayload.fromBytes(
        name: 'photo.png',
        bytes: source,
        category: ImageCategory.note,
      );
      source[0] = 9;
      var calls = 0;
      final auth = client((request) async {
        calls++;
        expect(request.url.path, '/base/api/uploads');
        expect(request.method, 'POST');
        expect(
          utf8.decode(request.bodyBytes, allowMalformed: true),
          contains('name="category"'),
        );
        return reply(row());
      });
      final repo = RemoteImagesRepository(auth);
      addTearDown(repo.dispose);
      var sent = 0;
      final result = await repo.upload(
        payload,
        onSent: (value, total) {
          sent = value;
          expect(total, 3);
        },
      );
      expect(result.id, 7);
      expect(result.name, 'photo.png');
      expect(payload.bytes, [1, 2, 3]);
      expect(sent, 3);
      expect(calls, 1);
      final cancel = AttachmentCancellation()..cancel();
      await expectLater(
        repo.upload(payload, cancellation: cancel),
        throwsA(isA<AttachmentCancelled>()),
      );
      expect(calls, 1);
    },
  );
  test(
    '403 deletion leaves selection state to caller and makes no public probe',
    () async {
      var probes = 0;
      final repo = RemoteImagesRepository(
        client((_) async => reply({}, status: 403)),
        publicTransport: MockClient((_) async {
          probes++;
          return http.Response('', 200);
        }),
      );
      addTearDown(repo.dispose);
      await expectLater(
        repo.remove(
          ManagedImage(
            id: 7,
            name: 'photo.png',
            uri: Uri.parse(
              'https://example.test/base/upload-files/note/photo.webp',
            ),
          ),
        ),
        throwsA(isA<ApiFailure>()),
      );
      expect(probes, 0);
    },
  );
  test(
    'API deletion confirmation cannot imply the public file is inaccessible',
    () async {
      final repo = RemoteImagesRepository(
        client((_) async => reply({})),
        publicTransport: MockClient((request) async {
          expect(request.followRedirects, isFalse);
          expect(request.headers['cookie'], isNull);
          expect(
            request.url.queryParameters.containsKey('_bookstark_verify'),
            isTrue,
          );
          return http.Response.bytes([1, 2, 3], 200);
        }),
      );
      addTearDown(repo.dispose);
      final result = await repo.remove(
        ManagedImage(
          id: 7,
          name: 'photo.png',
          uri: Uri.parse(
            'https://example.test/base/upload-files/note/photo.webp',
          ),
        ),
      );
      expect(result.recordRemoved, isTrue);
      expect(result.linkAvailable, isTrue);
    },
  );
  test(
    'public reads are bounded, immutable, cached and never follow redirects',
    () async {
      var reads = 0;
      final repo = RemoteImagesRepository(
        client((_) async => reply({})),
        publicTransport: MockClient((request) async {
          reads++;
          expect(request.headers['cookie'], isNull);
          expect(request.followRedirects, isFalse);
          return http.Response.bytes([1, 2, 3], 200);
        }),
      );
      addTearDown(repo.dispose);
      final uri = Uri.parse(
        'https://example.test/base/upload-files/note/photo.webp',
      );
      await expectLater(
        repo.bytes(uri, maxBytes: 2),
        throwsA(isA<ApiFailure>()),
      );
      final bytes = await repo.bytes(uri, maxBytes: 3);
      expect(bytes, [1, 2, 3]);
      expect(() => bytes[0] = 9, throwsUnsupportedError);
      await expectLater(
        repo.bytes(uri, maxBytes: 2),
        throwsA(isA<ApiFailure>()),
      );
      expect(reads, 2);
      final redirected = RemoteImagesRepository(
        client((_) async => reply({})),
        publicTransport: MockClient(
          (_) async => http.Response(
            '',
            302,
            headers: {'location': 'https://other.test/image'},
          ),
        ),
      );
      addTearDown(redirected.dispose);
      await expectLater(redirected.bytes(uri), throwsA(isA<ApiFailure>()));
    },
  );
}
