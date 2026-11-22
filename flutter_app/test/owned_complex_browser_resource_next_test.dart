import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/owned_complex_resource_lease.dart';
import 'package:bookstark_flutter/core/owned_complex_resources.dart';
import 'package:bookstark_flutter/core/owned_complex_document_references.dart';
import 'package:bookstark_flutter/features/complex_editors/complex_editor_browser.dart';
import 'package:bookstark_flutter/features/html/html_browser_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const ref = '/upload-files/a.png';
  final sources = <ComplexEditorKind, String>{
    ComplexEditorKind.html: '<img src="$ref">',
    ComplexEditorKind.drawing: jsonEncode({'elements': [], 'image': ref}),
    ComplexEditorKind.mindmap: jsonEncode({
      'nodeData': {'id': 'root', 'topic': 'R', 'image': ref},
    }),
    ComplexEditorKind.richdoc: jsonEncode({
      'schema': 'bookstark-richdoc',
      'schema_version': 1,
      'data': {
        'main': [
          {'type': 'image', 'value': ref},
        ],
      },
    }),
    ComplexEditorKind.presentation: jsonEncode({
      'width': 960,
      'height': 540,
      'slides': [
        {
          'id': 's',
          'elements': [
            {'type': 'image', 'src': ref},
          ],
        },
      ],
    }),
    ComplexEditorKind.spreadsheet: jsonEncode({
      'id': 'w',
      'name': 'W',
      'sheetOrder': ['s'],
      'sheets': {
        's': {
          'id': 's',
          'name': 'S',
          'rowCount': 2,
          'columnCount': 2,
          'cellData': {},
        },
      },
      'resources': [
        {'name': 'future', 'data': ref},
      ],
    }),
  };
  for (final entry in sources.entries) {
    testWidgets(
      'real owned Browser ${entry.key.name} binds only exact anonymous current-source refs',
      (tester) async {
        final document = ComplexEditorDocument.parse(entry.key, entry.value);
        final client = BookstarkClient('https://owned.test/prefix');
        client.restoreSession({
          'token': 'fixture-only',
          'csrf_token': 'fixture-only',
        });
        final lease = OwnedComplexResourceLease(
          client: client,
          memberId: 7,
          resourceId: 9,
          bookId: 0,
          note: true,
          kind: entry.key,
          namespace: 'space',
          isCurrentScope: () => true,
        );
        var gets = 0;
        final png = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]);
        final httpClient = MockClient((request) async {
          gets++;
          expect(
            request.url.toString(),
            'https://owned.test/prefix/upload-files/a.png',
          );
          for (final h in [
            'cookie',
            'authorization',
            'x-csrf-token',
            'referer',
            'accept-language',
          ]) {
            expect(request.headers.containsKey(h), false);
          }
          return http.Response.bytes(
            png,
            200,
            headers: {'content-type': 'image/png'},
          );
        });
        final refs = OwnedComplexDocumentReferences.capture(
          document,
          fullFingerprint: ''.padLeft(64, 'a'),
        );
        final resources = OwnedComplexResources(
          lease: lease,
          sourceDigest: document.digest,
          documentReferences: refs.references,
          transport: httpClient,
          validateImage: (_, _) async {},
        );
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        MethodChannel? channel;
        Map? parameters;
        messenger.setMockMethodCallHandler(
          HtmlBrowserSession.channel,
          (_) async => null,
        );
        messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
          call,
        ) async {
          final args = call.arguments as Map;
          if (call.method == 'create') {
            expect(args['viewType'], 'bookstark/owned_complex_view');
            parameters =
                const StandardMessageCodec().decodeMessage(
                      ByteData.sublistView(args['params'] as Uint8List),
                    )
                    as Map;
            expect(parameters!.keys.toSet(), {
              'lease',
              'server',
              'resourceScope',
            });
            expect(parameters!['server'], 'https://owned.test/prefix');
            channel = MethodChannel(
              'bookstark/owned_complex_view/${args['id']}',
            );
            messenger.setMockMethodCallHandler(channel!, (_) async => null);
            return 99;
          }
          if (call.method == 'resize') {
            return {'width': args['width'], 'height': args['height']};
          }
          return null;
        });
        Future<Object?> request(
          String url, {
          String? scope,
          String? runtime,
        }) async {
          Object? reply;
          var done = false;
          // Native resource callbacks carry real streamed HTTP I/O. Deliver just
          // this RPC on the real event loop; widget lifecycle/guards stay outside.
          await tester.runAsync(() async {
            await messenger.handlePlatformMessage(
              channel!.name,
              const StandardMethodCodec().encodeMethodCall(
                MethodCall('ownedResource', {
                  'lease': runtime ?? parameters!['lease'],
                  'resourceScope': scope ?? resources.identity,
                  'url': url,
                }),
              ),
              (bytes) {
                if (bytes != null) {
                  reply = const StandardMethodCodec().decodeEnvelope(bytes);
                }
                done = true;
              },
            );
          });
          for (var n = 0; n < 20 && !done; n++) {
            await tester.pump();
          }
          expect(done, true);
          return reply;
        }

        try {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: ComplexEditorBrowser(
                  document: document,
                  ownedResourceFactory: (_) => resources,
                ),
              ),
            ),
          );
          for (var n = 0; n < 20 && channel == null; n++) {
            await tester.pump();
          }
          expect(channel, isNotNull);
          expect(
            await request(
              'https://owned.test/prefix/upload-files/a.png',
              scope: ''.padLeft(64, 'b'),
            ),
            isNull,
          );
          expect(
            await request(
              'https://owned.test/prefix/upload-files/a.png',
              runtime: 'wrong-lease',
            ),
            isNull,
          );
          expect(gets, 0);
          final response = await request(
            'https://owned.test/prefix/upload-files/a.png',
          );
          expect(response, isA<Map>());
          expect((response as Map)['bytes'], png);
          expect(response['resourceScope'], resources.identity);
          expect(gets, 1);
          expect(
            await request('https://owned.test/prefix/api/profile'),
            isNull,
          );
          expect(gets, 1);
          lease.retire();
          expect(
            await request('https://owned.test/prefix/upload-files/a.png'),
            isNull,
          );
          expect(gets, 1);
        } finally {
          await tester.pumpWidget(const SizedBox());
          await tester.pump();
          await HtmlBrowserSession.closeActive();
          await lease.retireAndDrain();
          resources.close();
          httpClient.close();
          client.close();
          messenger.setMockMethodCallHandler(HtmlBrowserSession.channel, null);
          messenger.setMockMethodCallHandler(
            SystemChannels.platform_views,
            null,
          );
          if (channel != null) {
            messenger.setMockMethodCallHandler(channel!, null);
          }
        }
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  }
}
