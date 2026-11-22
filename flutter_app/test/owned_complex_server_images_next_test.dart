import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/owned_complex_resource_lease.dart';
import 'package:bookstark_flutter/core/owned_complex_resources.dart';
import 'package:bookstark_flutter/core/owned_complex_server_images.dart';

void main() {
  Map<String, Object?> row({int width = 640, String mime = 'image/png'}) => {
    'id': 27,
    'url': '/upload-files/a.png',
    'file_name': 'actual.png',
    'file_size': 84000,
    'width': width,
    'height': 480,
    'mime_type': mime,
  };
  http.Response response(List<Object?> rows) => http.Response(
    jsonEncode({
      'code': 0,
      'data': rows,
      'page': 1,
      'page_size': 20,
      'total': rows.length,
      'total_pages': 1,
    }),
    200,
    headers: {'content-type': 'application/json'},
  );
  ({
    BookstarkClient client,
    OwnedComplexResourceLease lease,
    OwnedComplexResources resources,
    OwnedComplexServerImages library,
  })
  fixture(http.Client transport) {
    final client = BookstarkClient(
      'https://owned.test/prefix',
      transport: transport,
    );
    client.restoreSession({'token': 'fixture-only'});
    final lease = OwnedComplexResourceLease(
      client: client,
      memberId: 7,
      resourceId: 9,
      bookId: 0,
      note: true,
      kind: ComplexEditorKind.richdoc,
      namespace: 'space',
      isCurrentScope: () => true,
    );
    final resources = OwnedComplexResources(
      lease: lease,
      documentReferences: [],
    );
    final library = OwnedComplexServerImages(
      lease: lease,
      resources: resources,
    );
    addTearDown(() async {
      resources.close();
      await lease.retireAndDrain();
      client.close();
    });
    return (
      client: client,
      lease: lease,
      resources: resources,
      library: library,
    );
  }

  test(
    'real authenticated visible library is fixed bounded page, not false per-member filtering',
    () async {
      final requests = <http.Request>[];
      final f = fixture(
        MockClient((request) async {
          requests.add(request);
          return response([row()]);
        }),
      );
      final page = await f.library.read(1);
      expect(
        page.items.single.url.toString(),
        'https://owned.test/prefix/upload-files/a.png',
      );
      expect(page.items.single.id, 27);
      expect(page.hasNext, false);
      expect(requests.single.method, 'GET');
      expect(requests.single.bodyBytes, isEmpty);
      expect(requests.single.url.path, '/prefix/api/uploads');
      expect(requests.single.url.queryParameters, {
        'page': '1',
        'page_size': '20',
      });
      expect(requests.single.headers['cookie'], contains('token=fixture-only'));
      // No fabricated member_id request/response constraint: Go returns global media.
      expect(
        requests.single.url.queryParameters.containsKey('member_id'),
        false,
      );
    },
  );
  test(
    'explicit choice fresh verification rejects changed metadata without upload',
    () async {
      var reads = 0, mutations = 0;
      final f = fixture(
        MockClient((request) async {
          if (request.method != 'GET') mutations++;
          return response([row(width: ++reads == 1 ? 640 : 641)]);
        }),
      );
      final picked = (await f.library.read(1)).items.single;
      expect(await f.library.verify(picked), false);
      expect(reads, 2);
      expect(mutations, 0);
    },
  );
  test(
    'unsupported media stays unavailable and server-path escape rejects',
    () async {
      var bad = false;
      final f = fixture(
        MockClient(
          (_) async => response(
            bad
                ? [
                    {...row(), 'url': 'https://other.test/upload-files/a.png'},
                  ]
                : [row(mime: 'image/svg+xml')],
          ),
        ),
      );
      expect((await f.library.read(1)).items, isEmpty);
      bad = true;
      await expectLater(f.library.read(1), throwsFormatException);
    },
  );
  test(
    'same-token restored session retires held list before late result',
    () async {
      final entered = Completer<void>(), release = Completer<http.Response>();
      var calls = 0;
      final f = fixture(
        MockClient((_) async {
          calls++;
          entered.complete();
          return release.future;
        }),
      );
      final work = f.library.read(1);
      final assertion = expectLater(
        work,
        throwsA(
          anyOf(
            isA<ApiFailure>().having((e) => e.status, 'retired status', 499),
            isA<OwnedComplexResourceRetired>(),
          ),
        ),
      );
      await entered.future;
      f.client.restoreSession({'token': 'fixture-only'});
      release.complete(response([row()]));
      await assertion;
      expect(calls, 1);
    },
  );
}
