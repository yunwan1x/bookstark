import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/attachments.dart';
import 'package:bookstark_flutter/core/local_attachments.dart';

void main() {
  test(
    'local attachment persists independently of picker path; rejects traversal and protected plaintext',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'bookstark-attachments-',
      );
      addTearDown(() => temp.delete(recursive: true));
      final source = File('${temp.path}/report.pdf');
      await source.writeAsString('persistent file');
      final target = Directory('${temp.path}/assets');
      var repository = LocalAttachments(target);
      final attachment = await repository.add(XFile(source.path));
      await source.delete();
      repository.close();
      repository = LocalAttachments(target);
      addTearDown(repository.close);
      expect(
        utf8.decode(await repository.read(attachment.uri)),
        'persistent file',
      );
      await expectLater(
        repository.read(attachment.uri, maxBytes: 2),
        throwsA(isA<ApiFailure>()),
      );
      await expectLater(
        repository.read(Uri.parse('bookstark-attachment:///../etc/passwd')),
        throwsFormatException,
      );
      await expectLater(
        repository.read(Uri.parse('file:///etc/passwd')),
        throwsFormatException,
      );
      await expectLater(
        repository.add(
          XFile.fromData(Uint8List.fromList([1]), name: 'secret.png'),
          protected: true,
        ),
        throwsStateError,
      );
    },
  );
  test(
    'private attachment authentication is never sent to public or foreign URLs',
    () async {
      var privateCalls = 0, publicCalls = 0;
      final auth = BookstarkClient(
        'https://example.test/prefix',
        transport: MockClient((r) async {
          privateCalls++;
          expect(r.url.path, '/prefix/api/webdav/files/download');
          expect(r.headers['cookie'], 'token=session');
          expect(r.followRedirects, isFalse);
          return http.Response.bytes([1, 2, 3], 200);
        }),
      );
      auth.restoreSession({'token': 'session'});
      final repository = RemoteAttachments(
        auth,
        publicTransport: MockClient((r) async {
          publicCalls++;
          expect(r.headers.containsKey('cookie'), isFalse);
          expect(r.headers.containsKey('x-csrf-token'), isFalse);
          expect(r.followRedirects, isFalse);
          return http.Response.bytes([4, 5], 200);
        }),
      );
      addTearDown(repository.close);
      await repository.read(
        Uri.parse('/api/webdav/files/download?path=%2Fprivate.pdf'),
      );
      await repository.read(Uri.parse('/upload-files/image.webp'));
      await repository.read(
        Uri.parse('https://foreign.test/api/webdav/files/download?path=%2Fa'),
      );
      expect(privateCalls, 1);
      expect(publicCalls, 2);
      expect(
        repository.resolve(Uri.parse('/upload-files/a.png')).path,
        '/prefix/upload-files/a.png',
      );
      expect(repository.owns(Uri.parse('file:///etc/passwd')), isFalse);
      await expectLater(
        repository.read(Uri.parse('https://user:password@foreign.test/x')),
        throwsFormatException,
      );
    },
  );
  test(
    'protected images use authenticated private upload; names cannot overwrite existing files',
    () async {
      final uploadNames = <String>[];
      final auth = BookstarkClient(
        'https://example.test',
        transport: MockClient((r) async {
          if (r.url.path.endsWith('/csrf-token')) {
            return http.Response(
              '{"code":0}',
              200,
              headers: {'set-cookie': 'csrf_token=x'},
            );
          }
          expect(r.url.path, '/api/webdav/files/upload');
          uploadNames.add(
            RegExp('filename="([^"]+)"').firstMatch(r.body)!.group(1)!,
          );
          return http.Response(
            '{"code":0,"data":{"file":{"path":"unique.png"}}}',
            200,
          );
        }),
      );
      final repository = RemoteAttachments(auth);
      addTearDown(repository.close);
      for (var i = 0; i < 2; i++) {
        final result = await repository.add(
          XFile.fromData(
            Uint8List.fromList([1, 2, 3]),
            name: 'same.png',
            path: 'same.png',
          ),
          protected: true,
        );
        expect(result.name, 'same.png');
        expect(result.uri.path, '/api/webdav/files/download');
      }
      expect(uploadNames.toSet().length, 2);
      expect(
        uploadNames.every(
          (name) => name.endsWith('.png') && name != 'same.png',
        ),
        isTrue,
      );
    },
  );
  test(
    'Markdown AST round trips escaped labels, query strings and removal without deleting prose',
    () {
      final uri = Uri.parse(
        'https://example.test/api/webdav/files/download?path=%2Freport%20(1).pdf&x=1',
      );
      final text = markdownAttachment('报告[1].pdf', uri, image: false);
      final content = 'Keep bare URL: $uri\n\n$text\n';
      final attachments = noteAttachments(content, (_) => true);
      expect(attachments.last.name, '报告[1].pdf');
      expect(attachments.last.uri, uri);
      final removed = removeAttachmentReference(content, attachments.last);
      expect(removed, contains('Keep bare URL: $uri'));
      expect(removed, isNot(contains(text)));
    },
  );
  test(
    'BMP uses private file upload and malformed DAV paths never become references',
    () async {
      var invalid = false;
      final auth = BookstarkClient(
        'https://example.test',
        transport: MockClient((request) async {
          if (request.url.path.endsWith('/csrf-token')) {
            return http.Response(
              '{}',
              200,
              headers: {'set-cookie': 'csrf_token=x'},
            );
          }
          expect(request.url.path, '/api/webdav/files/upload');
          return http.Response(
            jsonEncode({
              'file': {'path': invalid ? '../outside.bmp' : '/safe.bmp'},
            }),
            200,
          );
        }),
      );
      addTearDown(auth.close);
      final repository = RemoteAttachments(auth);
      addTearDown(repository.close);
      final file = XFile.fromData(
        Uint8List.fromList([66, 77]),
        path: 'scan.bmp',
      );
      final image = await repository.add(file);
      expect(image.image, isTrue);
      expect(image.uri.queryParameters['path'], '/safe.bmp');
      invalid = true;
      await expectLater(repository.add(file), throwsFormatException);
    },
  );
}
