import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/owned_complex_resource_lease.dart';
import 'package:bookstark_flutter/core/owned_complex_resources.dart';
import 'package:bookstark_flutter/core/owned_complex_document_references.dart';

void main() {
  final png = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]);
  OwnedComplexResourceLease owner(
    BookstarkClient client, {
    bool Function()? current,
  }) => OwnedComplexResourceLease(
    client: client,
    memberId: 7,
    resourceId: 19,
    bookId: 0,
    note: true,
    kind: ComplexEditorKind.drawing,
    namespace: 'owned',
    isCurrentScope: current ?? () => true,
  );
  BookstarkClient client() {
    final value = BookstarkClient('https://owned.test/prefix');
    value.restoreSession({
      'token': 'fixture-account-only',
      'csrf_token': 'fixture-csrf',
    });
    addTearDown(value.close);
    return value;
  }

  test(
    'exact source-derived prefixed resource is anonymous and cached once',
    () async {
      final c = client(), lease = owner(c);
      addTearDown(lease.retire);
      var calls = 0, validations = 0;
      final transport = MockClient((request) async {
        calls++;
        expect(request.method, 'GET');
        expect(
          request.url.toString(),
          'https://owned.test/prefix/upload-files/a.png',
        );
        for (final name in [
          'cookie',
          'authorization',
          'x-csrf-token',
          'referer',
          'accept-language',
        ]) {
          expect(request.headers.containsKey(name), false);
        }
        expect(request.headers['accept-encoding'], 'identity');
        return http.Response.bytes(
          png,
          200,
          headers: {'content-type': 'image/png'},
        );
      });
      addTearDown(transport.close);
      final resources = OwnedComplexResources(
        lease: lease,
        transport: transport,
        documentReferences: [Uri.parse('/upload-files/a.png')],
        validateImage: (_, _) async {
          validations++;
        },
      );
      addTearDown(resources.close);
      final first = await resources.read(Uri.parse('/upload-files/a.png'));
      final second = await resources.read(
        Uri.parse('https://owned.test/prefix/upload-files/a.png'),
      );
      expect(identical(first, second), true);
      expect(first.bytes, png);
      expect(calls, 1);
      expect(validations, 1);
      expect(
        () => resources.read(Uri.parse('/upload-files/not-in-document.png')),
        throwsFormatException,
      );
      expect(calls, 1);
    },
  );
  test(
    'credentials traversal encoded aliases and arbitrary API never reach HTTP',
    () async {
      final c = client(), lease = owner(c);
      addTearDown(lease.retire);
      var calls = 0;
      final transport = MockClient((_) async {
        calls++;
        throw StateError('Forbidden request');
      });
      addTearDown(transport.close);
      final resources = OwnedComplexResources(
        lease: lease,
        transport: transport,
        documentReferences: [],
      );
      addTearDown(resources.close);
      for (final value in [
        'https://other.test/upload-files/a.png',
        'https://user:fixture@owned.test/prefix/upload-files/a.png',
        '/upload-files/a/../b.png',
        '/upload-files/a%252fb.png',
        '/api/profile',
        '/upload-files/a.png?token=fixture',
        '/upload-files/a.png#fragment',
      ]) {
        expect(() => resources.read(Uri.parse(value)), throwsFormatException);
      }
      expect(calls, 0);
    },
  );
  test(
    'HTTP redirect gzip and oversized headers are refused without body decode',
    () async {
      for (final mode in ['redirect', 'gzip', 'oversized', 'script']) {
        final c = client(), lease = owner(c);
        addTearDown(lease.retire);
        final transport = MockClient.streaming(
          (_, _) async => http.StreamedResponse(
            Stream<List<int>>.value(png),
            mode == 'redirect' ? 302 : 200,
            contentLength: mode == 'oversized'
                ? OwnedComplexResources.maxObject + 1
                : png.length,
            headers: {
              'content-type': mode == 'script'
                  ? 'application/javascript'
                  : 'image/png',
              if (mode == 'gzip') 'content-encoding': 'gzip',
            },
          ),
        );
        addTearDown(transport.close);
        var validated = 0;
        final resources = OwnedComplexResources(
          lease: lease,
          transport: transport,
          documentReferences: [Uri.parse('/upload-files/a.png')],
          validateImage: (_, _) async {
            validated++;
          },
        );
        addTearDown(resources.close);
        await expectLater(
          resources.read(Uri.parse('/upload-files/a.png')),
          throwsFormatException,
        );
        expect(validated, 0);
      }
    },
  );
  test(
    'same-token restore rejects cache and late body cannot become visible',
    () async {
      final c = client(), lease = owner(c);
      final entered = Completer<void>(), reply = Completer<http.Response>();
      final transport = MockClient((_) async {
        entered.complete();
        return reply.future;
      });
      addTearDown(transport.close);
      final resources = OwnedComplexResources(
        lease: lease,
        transport: transport,
        documentReferences: [Uri.parse('/upload-files/a.png')],
        validateImage: (_, _) async {},
      );
      addTearDown(resources.close);
      addTearDown(lease.retire);
      final work = resources.read(Uri.parse('/upload-files/a.png'));
      final rejected = expectLater(
        work,
        throwsA(
          anyOf(isA<OwnedComplexResourceRetired>(), isA<TimeoutException>()),
        ),
      );
      await entered.future;
      c.restoreSession({
        'token': 'fixture-account-only',
        'csrf_token': 'fixture-csrf',
      });
      reply.complete(
        http.Response.bytes(png, 200, headers: {'content-type': 'image/png'}),
      );
      await rejected;
      expect(
        () => resources.read(Uri.parse('/upload-files/a.png')),
        throwsA(isA<OwnedComplexResourceRetired>()),
      );
    },
  );
  test(
    'retire drain waits for late response body cancellation acknowledgement',
    () async {
      final c = client(), lease = owner(c), entered = Completer<void>();
      final response = Completer<http.StreamedResponse>(),
          cancelEntered = Completer<void>(),
          cancelAck = Completer<void>();
      final body = StreamController<List<int>>(
        onCancel: () async {
          cancelEntered.complete();
          await cancelAck.future;
        },
      );
      final transport = MockClient.streaming((_, _) async {
        entered.complete();
        return response.future;
      });
      addTearDown(transport.close);
      final resources = OwnedComplexResources(
        lease: lease,
        transport: transport,
        documentReferences: [Uri.parse('/upload-files/a.png')],
        validateImage: (_, _) async {},
      );
      addTearDown(resources.close);
      final work = resources.read(Uri.parse('/upload-files/a.png'));
      final rejected = expectLater(
        work,
        throwsA(
          anyOf(isA<OwnedComplexResourceRetired>(), isA<TimeoutException>()),
        ),
      );
      await entered.future;
      var drained = false;
      final drain = lease.retireAndDrain().then((_) => drained = true);
      response.complete(
        http.StreamedResponse(
          body.stream,
          200,
          headers: {'content-type': 'image/png'},
        ),
      );
      await cancelEntered.future;
      await Future<void>.value();
      expect(
        drained,
        false,
        reason: 'HTTP cancellation ACK is part of owned work',
      );
      cancelAck.complete();
      await rejected;
      await drain;
      expect(drained, true);
      await body.close();
    },
  );
  test(
    'reference extraction preserves exact source and unknown fields without second JSON graph',
    () {
      final source = jsonEncode({
        'elements': [],
        'future': {'image': '/upload-files/a.png', 'note': '雪🙂'},
      });
      final document = ComplexEditorDocument.parse(
        ComplexEditorKind.drawing,
        source,
      );
      final refs = OwnedComplexDocumentReferences.capture(
        document,
        fullFingerprint: 'a' * 64,
      );
      expect(refs.sourceDigest, document.digest);
      expect(refs.fullFingerprint, 'a' * 64);
      expect(refs.references, {Uri.parse('/upload-files/a.png')});
      expect(document.source, source);
      final html = ComplexEditorDocument.parse(
        ComplexEditorKind.html,
        '<p>Exact</p><img src="/upload-files/b.png"><style>.x{background:url("/upload-files/c.png")}</style>',
      );
      final hrefs = OwnedComplexDocumentReferences.capture(
        html,
        fullFingerprint: 'b' * 64,
      );
      expect(hrefs.references, {
        Uri.parse('/upload-files/b.png'),
        Uri.parse('/upload-files/c.png'),
      });
    },
  );
  test(
    'retire drains actual registered work, refuses new work and sends no secret to identity',
    () async {
      final c = client(), lease = owner(c), gate = Completer<void>();
      final running = lease.use(() => gate.future);
      var drained = false;
      final draining = lease.retireAndDrain().then((_) => drained = true);
      await Future<void>.value();
      expect(drained, false);
      expect(
        () => lease.use(() async {}),
        throwsA(isA<OwnedComplexResourceRetired>()),
      );
      expect(lease.identity, hasLength(64));
      expect(lease.identity, isNot(contains('fixture')));
      gate.complete();
      await running;
      await draining;
      expect(drained, true);
    },
  );
}
