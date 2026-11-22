import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/complex_editor_transport.dart';
import 'package:bookstark_flutter/core/html_editor_controller.dart';
import 'package:bookstark_flutter/core/html_notes_repository.dart';
import 'package:bookstark_flutter/core/html_recovery_vault.dart';
import 'package:bookstark_flutter/core/labels_repository.dart';
import 'package:bookstark_flutter/core/owned_html_note_images.dart';
import 'package:bookstark_flutter/core/owned_complex_image_upload_journal.dart';
import 'package:bookstark_flutter/core/secure_record_store.dart';
import 'package:bookstark_flutter/features/html/html_note_page.dart';
import 'package:bookstark_flutter/features/html/html_browser_session.dart';
import 'package:bookstark_flutter/features/complex_editors/complex_editor_browser.dart';

const opaque =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const initial = '<p>Original HTML exact</p>';

class Labels implements LabelsRepository {
  @override
  Future<List<String>> search(String keyword, {int page = 1}) async => [];
}

class Repository implements HtmlNotesRepository {
  HtmlNote actual = HtmlNote(
    metadata: const HtmlNoteMetadata(
      id: 41,
      memberId: 7,
      collection: 'note',
      title: 'Actual HTML',
      version: 2,
      modifiedAt: 100,
      protected: false,
    ),
    source: initial,
    labels: const ['real'],
  );
  int saves = 0;
  @override
  bool get labelsUseCsv => true;
  @override
  Future<HtmlNote> read(int id, {String? password}) async {
    if (id != 41) throw StateError('Unexpected owned HTML ID');
    return actual;
  }

  @override
  Future<HtmlSaveOutcome> save(HtmlNote baseline, HtmlNoteEdit edit) async {
    if (htmlNoteFingerprint(baseline) != htmlNoteFingerprint(actual)) {
      throw StateError('Owned HTML baseline changed');
    }
    saves++;
    actual = HtmlNote(
      metadata: HtmlNoteMetadata(
        id: 41,
        memberId: 7,
        collection: 'note',
        title: edit.title,
        version: 3,
        modifiedAt: 101,
        protected: false,
      ),
      source: edit.source,
      labels: edit.labels,
    );
    return HtmlSaveOutcome(
      actual,
      HtmlSaveAttempt(
        baseline: baseline,
        edit: edit,
        contentReceipt: true,
        labelsReceipt: true,
      ),
    );
  }

  @override
  Future<HtmlSaveOutcome> finishLabels(HtmlSaveAttempt attempt) async =>
      throw StateError('No extra labels');
  @override
  void dispose() {}
}

Future<void> progress(WidgetTester tester, bool Function() done) async {
  for (var n = 0; n < 100 && !done(); n++) {
    await tester.pump(const Duration(milliseconds: 10));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1)),
    );
  }
  expect(
    done(),
    true,
    reason: 'Actual HTML operation must finish within bounded host fixture',
  );
}

Future<void> drain(WidgetTester tester, Future<void> work) async {
  var done = false;
  Object? error;
  StackTrace? trace;
  unawaited(
    work.then<void>(
      (_) {
        done = true;
      },
      onError: (Object e, StackTrace s) {
        error = e;
        trace = s;
        done = true;
      },
    ),
  );
  await progress(tester, () => done);
  if (error != null) Error.throwWithStackTrace(error!, trace!);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final unknown in [false, true]) {
    testWidgets(
      unknown
          ? 'actual dedicated HTML cold unknown disables another upload'
          : 'actual dedicated HTML inserts with real transport and old vault before one explicit Save',
      (tester) async {
        final repository = Repository(),
            records = <String, String>{},
            markers = <String, String>{};
        final vault = HtmlRecoveryVault(
          server: Uri.parse('https://owned.test/prefix'),
          memberId: 7,
          collection: 'note',
          readValue: (k) async => records[k],
          writeValue: (k, v) async {
            records[k] = v;
          },
          deleteValue: (k) async {
            records.remove(k);
          },
        );
        final editor = HtmlEditorController(
          repository,
          repository.actual,
          recovery: vault,
        );
        var accountRequests = 0, mediaRequests = 0;
        final client = BookstarkClient(
          'https://owned.test/prefix',
          transport: MockClient((_) async {
            accountRequests++;
            throw StateError(
              'No mutation HTTP permitted in retained URL fixture',
            );
          }),
        )..restoreSession({'token': 'account-only'});
        final media = MockClient((request) async {
          mediaRequests++;
          if (request.headers.containsKey('cookie')) {
            throw StateError('Anonymous media sent an account cookie');
          }
          return http.Response.bytes(
            base64Decode(
              'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aN3sAAAAASUVORK5CYII=',
            ),
            200,
            headers: {'content-type': 'image/png'},
          );
        });
        final images = OwnedHtmlNoteImages(
          client: client,
          memberId: 7,
          resourceId: 41,
          namespace: 'remote-html-v1',
          isCurrent: () => true,
          editor: editor,
          resourceTransport: media,
          imageValidator: (_, _) async {},
          journalStore: SecureRecordStore(
            prefix: OwnedComplexImageUploadJournal.prefix,
            namespace: opaque,
            readValue: (k) async => markers[k],
            writeValue: (k, v) async {
              markers[k] = v;
            },
            deleteValue: (k) async {
              markers.remove(k);
            },
          ),
          flush: () async {},
        );
        final retained = OwnedImageUploadRecord(
          bindingId: images.lease.identity,
          inputSHA256: opaque,
          phase: unknown
              ? OwnedImageUploadPhase.unknown
              : OwnedImageUploadPhase.confirmedUrl,
          uploadId: unknown ? null : 27,
          url: unknown
              ? null
              : Uri.parse('https://owned.test/prefix/upload-files/a.png'),
        );
        await images.journal.write(retained);
        await images.open();
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        final peers = <_EditorProtocol>[];
        messenger.setMockMethodCallHandler(
          HtmlBrowserSession.channel,
          (_) async => null,
        );
        messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
          call,
        ) async {
          if (call.method != 'create') return null;
          final args = call.arguments as Map;
          final params =
              const StandardMessageCodec().decodeMessage(
                    ByteData.sublistView(args['params'] as Uint8List),
                  )
                  as Map;
          if (args['viewType'] != 'bookstark/owned_complex_view') {
            throw StateError('Unexpected owned HTML factory');
          }
          final peer = _EditorProtocol(
            args['id'] as int,
            params['lease'] as String,
            viewType: args['viewType'] as String,
          );
          peers.add(peer);
          messenger.setMockMethodCallHandler(peer.channel, (call) async {
            if (call.method != 'command') {
              throw StateError('Unexpected owned HTML RPC method');
            }
            final p = call.arguments as Map;
            return await peer.command(
              p['name'] as String,
              (p['arguments'] as List).cast<Object?>(),
            );
          });
          return 99;
        });
        Widget surface(
          BuildContext context, {
          required Key key,
          required ComplexEditorDocument document,
          required String title,
          required bool english,
          required bool readOnly,
          required Future<void> Function(ComplexEditorTransport) onReady,
          required void Function(ComplexEditorState) onState,
          required Future<void> Function() onSaveRequested,
          required Future<void> Function(ComplexEditorTransport) beforeRetire,
          required Future<void> Function() onReloadRequested,
          required Future<void> Function(Uri) onExternalLink,
        }) => ComplexEditorBrowser(
          key: key,
          document: document,
          title: title,
          english: english,
          readOnly: readOnly,
          ownedResourceFactory: images.resourceFactory,
          onReady: onReady,
          onState: onState,
          onSaveRequested: onSaveRequested,
          beforeRetire: beforeRetire,
          onReloadRequested: onReloadRequested,
          onExternalLink: onExternalLink,
        );
        try {
          await tester.pumpWidget(
            MaterialApp(
              home: HtmlNotePage(
                controller: editor,
                labels: Labels(),
                english: true,
                ownedImages: images,
                sourceSurfaceBuilder: surface,
                fullPreviewBuilder: (_, _) => const Text('Preview fixture'),
              ),
            ),
          );
          await tester.tap(find.text('Source'));
          await progress(tester, () => peers.isNotEmpty);
          final peer = peers.last;
          await drain(
            tester,
            messenger.handlePlatformMessage(
              peer.channel.name,
              const StandardMethodCodec().encodeMethodCall(
                MethodCall('hostReady', {'lease': peer.lease}),
              ),
              (_) {},
            ),
          );
          await progress(tester, () => peer.source == initial);
          await tester.pumpAndSettle();
          final upload = find.byWidgetPredicate(
            (w) => w is IconButton && w.tooltip == 'Upload image',
          );
          expect(upload, findsOneWidget);
          expect(tester.widget<IconButton>(upload).onPressed, isNull);
          if (unknown) {
            expect(
              find.textContaining('Upload result unknown.'),
              findsOneWidget,
            );
            expect((await images.journal.read())!.encode(), retained.encode());
            expect(editor.draft.source, initial);
            expect(repository.saves, 0);
            expect(mediaRequests, 0);
          } else {
            final insert = find.text('Insert confirmed image');
            await tester.ensureVisible(insert);
            await tester.tap(insert);
            await progress(
              tester,
              () =>
                  editor.draft.source.contains('/upload-files/a.png') &&
                  images.upload.record == null,
            );
            expect(repository.saves, 0);
            expect(editor.baseline.source, initial);
            expect((await vault.read(41))!.edit!.source, editor.draft.source);
            expect(mediaRequests, 1);
            expect(accountRequests, 0);
            final save = find.widgetWithText(FilledButton, 'Save');
            await progress(
              tester,
              () => tester.widget<FilledButton>(save).onPressed != null,
            );
            await tester.tap(save.hitTestable());
            await progress(
              tester,
              () =>
                  repository.saves == 1 &&
                  editor.baseline.source.contains('/upload-files/a.png'),
            );
            expect(editor.baseline.metadata.id, 41);
            expect(editor.baseline.metadata.collection, 'note');
            expect(editor.baseline.labels, ['real']);
            expect(await vault.read(41), isNull);
          }
          expect(accountRequests, 0);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox());
          await tester.pump();
          await drain(tester, HtmlBrowserSession.closeActive());
          await drain(tester, images.retireAndDrain());
          messenger.setMockMethodCallHandler(HtmlBrowserSession.channel, null);
          messenger.setMockMethodCallHandler(
            SystemChannels.platform_views,
            null,
          );
          for (final p in peers) {
            messenger.setMockMethodCallHandler(p.channel, null);
          }
          client.close();
          media.close();
        }
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  }
}

class _EditorProtocol {
  _EditorProtocol(
    this.id,
    this.lease, {
    String viewType = 'bookstark/complex_editor_view',
  }) : channel = MethodChannel('$viewType/$id');
  final int id;
  final String lease;
  final MethodChannel channel;
  ComplexEditorKind kind = ComplexEditorKind.html;
  String source = '';
  int generation = 1, revision = 1, transferNumber = 0;
  bool readOnly = true, localImages = false, retired = false;
  int? selection;
  final loads = <String, BytesBuilder>{};
  final snapshots = <String, Uint8List>{};

  final commandCounts = <String, int>{};
  Future<Object?> command(String name, List<Object?> args) async {
    commandCounts.update(name, (value) => value + 1, ifAbsent: () => 1);
    switch (name) {
      case 'beginLoad':
        kind = ComplexEditorKind.parse(args[0]! as String);
        readOnly = (args[3]! as Map)['readOnly']! as bool;
        localImages = (args[3]! as Map)['localMarkdownImages'] == true;
        final id = 'load-${++transferNumber}';
        loads[id] = BytesBuilder(copy: false);
        return {
          'id': id,
          'bytes': args[1],
          'chunkBytes': ComplexEditorTransport.chunkBytes,
        };
      case 'appendLoad':
        final id = args[0]! as String;
        final bytes = base64Decode(args[2]! as String);
        final builder = loads[id]!;
        builder.add(bytes);
        return {'id': id, 'index': args[1], 'received': builder.length};
      case 'commitLoad':
        final id = args[0]! as String;
        source = utf8.decode(loads.remove(id)!.takeBytes());
        return {
          'ready': true,
          'kind': kind.name,
          'readOnly': readOnly,
          'generation': generation,
        };
      case 'setInputLocked':
        return {
          'generation': args[1],
          'ready': true,
          'kind': kind.name,
          'inputLocked': args[0],
        };
      case 'beginSnapshot':
        final bytes = Uint8List.fromList(utf8.encode(source));
        final id = 'snapshot-${++transferNumber}';
        snapshots[id] = bytes;
        return {
          'id': id,
          'bytes': bytes.length,
          'chunks':
              (bytes.length + ComplexEditorTransport.chunkBytes - 1) ~/
              ComplexEditorTransport.chunkBytes,
          'generation': generation,
          'revision': revision,
          'sha256': sha256.convert(bytes).toString(),
          if (localImages)
            'markdownSelection': {
              'anchor': selection ?? source.length,
              'head': selection ?? source.length,
            },
        };
      case 'readSnapshot':
        final id = args[0]! as String;
        final index = args[1]! as int;
        final bytes = snapshots[id]!;
        final start = index * ComplexEditorTransport.chunkBytes;
        final end = (start + ComplexEditorTransport.chunkBytes).clamp(
          0,
          bytes.length,
        );
        return {
          'id': id,
          'generation': generation,
          'index': index,
          'base64': base64Encode(bytes.sublist(start, end)),
        };
      case 'insertImageSnapshot':
        final id = args[0] as String;
        if (!snapshots.containsKey(id)) {
          throw StateError('Missing frozen input');
        }
        source +=
            '<img src="${args[1] as String}" width="${args[2]}" height="${args[3]}">';
        snapshots.remove(id);
        revision++;
        return {
          'generation': generation,
          'kind': kind.name,
          'ready': true,
          'inputLocked': true,
          'dirty': true,
        };
      case 'endSnapshot':
        snapshots.remove(args[0]! as String);
        return true;
      case 'acknowledgeSnapshot':
        return {'generation': generation, 'ready': true, 'kind': kind.name};
      case 'abortLoad':
        loads.remove(args[0]! as String);
        return true;
      case 'retire':
        retired = true;
        return true;
      default:
        throw StateError('Unexpected editor command $name');
    }
  }
}
