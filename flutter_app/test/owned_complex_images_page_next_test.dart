import 'dart:async';
import 'package:file_selector/file_selector.dart';
import 'package:bookstark_flutter/core/local_attachments.dart';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/complex_editor_transport.dart';
import 'package:bookstark_flutter/core/complex_recovery_store.dart';
import 'package:bookstark_flutter/core/complex_recovery_vault.dart';
import 'package:bookstark_flutter/core/local_complex_editor_controller.dart';
import 'package:bookstark_flutter/core/local_complex_notes_repository.dart';
import 'package:bookstark_flutter/features/complex_editors/local_complex_note_page.dart';
import 'package:bookstark_flutter/features/html/html_browser_session.dart';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/secure_record_store.dart';
import 'package:bookstark_flutter/core/owned_complex_images.dart';
import 'package:bookstark_flutter/core/owned_complex_image_upload_journal.dart';

const _scope =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _initialSource =
    '{"schema":"bookstark-richdoc","schema_version":1,"data":{"main":[{"value":"Original"}]}}';
const _editedSource = _initialSource;
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final unknown in [false, true]) {
    testWidgets(
      unknown
          ? 'cold unknown upload real page disables upload and keeps source'
          : 'known URL inserts into actual editor transport and checkpoints before explicit existing-ID Save',
      (tester) async {
        final rig = _Rig();
        final rows = <String, String>{};
        var ownerRequests = 0, imageGets = 0;
        final client = BookstarkClient(
          'https://owned.test/prefix',
          transport: MockClient((request) async {
            ownerRequests++;
            throw StateError('No owner HTTP allowed by retained URL path');
          }),
        )..restoreSession({'token': 'fixture-only'});
        final png = Uint8List.fromList(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aN3sAAAAASUVORK5CYII=',
          ),
        );
        final media = MockClient((request) async {
          imageGets++;
          expect(request.headers.containsKey('cookie'), false);
          expect(request.headers.containsKey('authorization'), false);
          return http.Response.bytes(
            png,
            200,
            headers: {'content-type': 'image/png'},
          );
        });
        final store = SecureRecordStore(
          prefix: OwnedComplexImageUploadJournal.prefix,
          namespace: _scope,
          readValue: (k) async => rows[k],
          writeValue: (k, v) async {
            rows[k] = v;
          },
          deleteValue: (k) async {
            rows.remove(k);
          },
        );
        final images = OwnedComplexImages(
          client: client,
          memberId: 7,
          resourceId: 41,
          bookId: 0,
          note: true,
          namespace: 'space',
          isCurrent: () => true,
          editor: rig.controller,
          journalStore: store,
          flush: () async {},
          resourceTransport: media,
          imageValidator: (_, _) async {},
        );
        final retained = OwnedImageUploadRecord(
          bindingId: images.lease.identity,
          inputSHA256: _scope,
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
        final bridge = _Bridge(tester, rig, images: images);
        await bridge.mount();
        var failed = false;
        try {
          expect(rig.repository.saveCount, 0);
          final uploadButton = find.byWidgetPredicate(
            (widget) =>
                widget is IconButton && widget.tooltip == 'Upload image',
          );
          expect(uploadButton, findsOneWidget);
          expect(tester.widget<IconButton>(uploadButton).onPressed, isNull);
          if (unknown) {
            expect(
              find.textContaining('Upload result unknown.'),
              findsOneWidget,
            );
            expect((await images.journal.read())!.encode(), retained.encode());
            expect(rig.controller.edit.document.source, _initialSource);
            expect(ownerRequests, 0);
            expect(imageGets, 0);
          } else {
            final insert = find.text('Insert confirmed image');
            await tester.ensureVisible(insert);
            // This action consumes a genuine streamed HTTP mock response. Keep the
            // network event-loop boundary real, not the entire widget test/timers.
            await tester.runAsync(() async {
              await tester.tap(insert);
              for (
                var n = 0;
                n < 100 &&
                    !(rig.controller.edit.document.source.contains(
                          '/upload-files/a.png',
                        ) &&
                        images.upload.record == null);
                n++
              ) {
                await Future<void>.delayed(const Duration(milliseconds: 10));
              }
            });
            await _pumpUntil(
              tester,
              () =>
                  rig.controller.edit.document.source.contains(
                    '/upload-files/a.png',
                  ) &&
                  images.upload.record == null,
            );
            expect(rig.repository.saveCount, 0);
            expect(rig.controller.draftDurable, true);
            expect(rig.controller.baseline.document.source, _initialSource);
            expect(imageGets, 1);
            expect(ownerRequests, 0);
            final saveButton = find.byWidgetPredicate(
              (widget) => widget is IconButton && widget.tooltip == 'Save',
            );
            expect(saveButton, findsOneWidget);
            await _pumpUntil(
              tester,
              () => tester.widget<IconButton>(saveButton).onPressed != null,
            );
            await tester.ensureVisible(saveButton);
            await tester.pump();
            expect(saveButton.hitTestable(), findsOneWidget);
            await tester.tap(saveButton.hitTestable());
            for (
              var n = 0;
              n < 80 &&
                  !(rig.repository.saveCount == 1 &&
                      rig.controller.baseline.document.source.contains(
                        '/upload-files/a.png',
                      ));
              n++
            ) {
              await tester.pump(const Duration(milliseconds: 10));
              await tester.runAsync(
                () => Future<void>.delayed(const Duration(milliseconds: 1)),
              );
            }
            expect(rig.repository.saveCount, 1);
            expect(
              rig.controller.baseline.document.source,
              contains('/upload-files/a.png'),
            );
            expect(rig.repository.current.id, 41);
            expect(rig.repository.current.collection, 'remote-note');
            expect(
              rig.repository.current.document.kind,
              ComplexEditorKind.richdoc,
            );
            expect(ownerRequests, 0);
            expect(await images.journal.read(), isNull);
          }
          expect(tester.takeException(), isNull);
        } catch (error) {
          failed = true;
          rethrow;
        } finally {
          try {
            await bridge.close();
            await _settleOwned(tester, images.retireAndDrain(), 'image drain');
          } catch (error) {
            if (!failed) rethrow;
          } finally {
            client.close();
            media.close();
          }
        }
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  }
}

Future<void> _settleOwned(
  WidgetTester tester,
  Future<void> work,
  String phase,
) async {
  var done = false;
  Object? failure;
  StackTrace? trace;
  unawaited(
    work.then<void>(
      (_) {
        done = true;
      },
      onError: (Object error, StackTrace stack) {
        failure = error;
        trace = stack;
        done = true;
      },
    ),
  );
  for (var n = 0; n < 100 && !done; n++) {
    await tester.pump(const Duration(milliseconds: 10));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1)),
    );
  }
  if (!done) throw StateError('Owned fixture did not drain: $phase');
  if (failure != null) Error.throwWithStackTrace(failure!, trace!);
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var i = 0; i < 80 && !condition(); i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(condition(), isTrue, reason: 'Condition did not settle within 800 ms');
}

class _Rig {
  _Rig({bool markdown = false, String? source})
    : baseline = _note(source ?? _initialSource, markdown: markdown);
  final ComplexNote baseline;
  late final repository = _Repository(baseline);
  final vaultStore = _MemoryBytesStore();
  late final controller = LocalComplexEditorController(
    repository: repository,
    vault: ComplexRecoveryVault(
      scope: _scope,
      collection: baseline.collection,
      kind: baseline.document.kind,
      store: vaultStore,
    ),
    baseline: baseline,
  );
  late final edit = ComplexNoteEdit(
    title: baseline.title,
    document: ComplexEditorDocument.parse(
      baseline.document.kind,
      _editedSource,
    ),
    labels: baseline.labels,
  );
}

ComplexNote _note(String source, {bool markdown = false}) => ComplexNote(
  scope: _scope,
  id: 41,
  collection: 'remote-note',
  title: 'Owned richdoc',
  document: ComplexEditorDocument.parse(ComplexEditorKind.richdoc, source),
  version: 10,
  resourceFingerprint: _scope,
  labels: const ['baseline'],
);

class _Repository implements ComplexNotesRepository {
  _Repository(this.current);
  ComplexNote current;
  int saveCount = 0;
  bool loseReceiptAfterCommit = false, blockSave = false;
  final saveEntered = Completer<void>();
  final releaseSave = Completer<void>();

  @override
  String get scope => _scope;
  @override
  String get collection => current.collection;
  @override
  ComplexEditorKind get kind => current.document.kind;
  @override
  void dispose() {}

  @override
  Future<ComplexNote> read(int id) async {
    if (id != current.id) throw StateError('Unexpected note id');
    return current;
  }

  @override
  Future<ComplexNote> save(ComplexNote baseline, ComplexNoteEdit edit) async {
    saveCount++;
    if (!baseline.same(current)) throw ComplexNoteConflict(current);
    if (blockSave) {
      if (!saveEntered.isCompleted) saveEntered.complete();
      await releaseSave.future;
    }
    current = ComplexNote(
      scope: current.scope,
      id: current.id,
      collection: current.collection,
      title: edit.title,
      document: edit.document,
      version: current.version + 1,
      resourceFingerprint: sha256
          .convert(utf8.encode(edit.document.source))
          .toString(),
      labels: edit.labels,
    );
    if (loseReceiptAfterCommit) {
      throw StateError('Commit applied; response lost');
    }
    return current;
  }
}

class _MemoryBytesStore implements ComplexRecoveryBytesStore {
  final values = <String, Uint8List>{};
  int removeCount = 0, removeFailures = 0, writeFailures = 0;

  @override
  Future<Uint8List?> read(String key) async {
    final value = values[key];
    return value == null ? null : Uint8List.fromList(value);
  }

  @override
  Future<void> write(String key, Uint8List bytes) async {
    if (writeFailures > 0) {
      writeFailures--;
      throw StateError('Injected draft write failure');
    }
    values[key] = Uint8List.fromList(bytes);
  }

  @override
  Future<void> remove(String key) async {
    removeCount++;
    if (removeFailures > 0) {
      removeFailures--;
      throw StateError('Injected cleanup failure');
    }
    values.clear();
  }
}

class _Bridge {
  _Bridge(this.tester, this.rig, {required this.images})
    : pickAttachment = null,
      attachments = null;
  final OwnedComplexImages images;
  final LocalAttachments? attachments;
  final Future<XFile?> Function()? pickAttachment;
  final WidgetTester tester;
  final _Rig rig;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final editors = <int, _EditorProtocol>{};
  final sessionCalls = <MethodCall>[];
  Object? lastLease;

  Future<void> mount({bool hostReady = true}) async {
    messenger.setMockMethodCallHandler(HtmlBrowserSession.channel, (
      call,
    ) async {
      sessionCalls.add(call);
      if (call.method == 'openLocal') {
        lastLease = (call.arguments as Map)['lease'];
      }
      return null;
    });
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
      call,
    ) async {
      final args = call.arguments as Map;
      if (call.method == 'create') {
        final id = args['id'] as int;
        final params =
            const StandardMessageCodec().decodeMessage(
                  ByteData.sublistView(args['params'] as Uint8List),
                )
                as Map;
        if (attachments != null) {
          expect(args['viewType'], 'bookstark/local_markdown_view');
          expect(params.keys.toSet(), {'lease'});
        }
        final editor = _EditorProtocol(
          id,
          params['lease'] as String,
          viewType: args['viewType'] as String,
        );
        editors[id] = editor;
        messenger.setMockMethodCallHandler(editor.channel, (call) async {
          if (call.method != 'command') {
            throw MissingPluginException(call.method);
          }
          final payload = call.arguments as Map;
          return editor.command(
            payload['name'] as String,
            (payload['arguments'] as List).cast<Object?>(),
          );
        });
        return 99;
      }
      return null;
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => LocalComplexNotePage(
                    controller: rig.controller,
                    ownedImages: images,
                    attachments: attachments,
                    pickAttachment: pickAttachment,
                    english: true,
                  ),
                ),
              ),
              child: const Text('Open local editor'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open local editor'));
    // Do not settle before hostReady; that advances the virtual clock through
    // the browser fail-closed timeout.
    await tester.pump();
    await _pumpUntil(tester, () => editors.isNotEmpty);
    await tester.pump();
    expect(lastLease, isNotNull);
    if (hostReady) await ready(editors.values.last);
  }

  Future<void> ready(_EditorProtocol editor) async {
    await _incoming(editor, 'hostReady', {'lease': editor.lease});
    await _pumpUntil(
      tester,
      () => editor.source == rig.controller.edit.document.source,
    );
    await tester.pumpAndSettle();
  }

  Future<void> edit(String source) async {
    final editor = editors.values.last;
    editor.source = source;
    editor.revision++;
    await _incoming(editor, 'state', {
      'lease': editor.lease,
      'state': {
        'version': 1,
        'kind': editor.kind.name,
        'generation': 1,
        'revision': editor.revision,
        'ready': true,
        'dirty': true,
        'inputLocked': false,
      },
    });
    await tester.pump(const Duration(milliseconds: 700));
    await _pumpUntil(tester, () => rig.controller.draftDurable);
  }

  Future<void> _incoming(
    _EditorProtocol editor,
    String method,
    Object args,
  ) async {
    await tester.runAsync(() async {
      await messenger.handlePlatformMessage(
        editor.channel.name,
        const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)),
        (_) {},
      );
    });
    await tester.pump();
  }

  Future<void> close() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await _settleOwned(
      tester,
      HtmlBrowserSession.closeActive(),
      'native session close',
    );
    await tester.pumpAndSettle();
    messenger.setMockMethodCallHandler(HtmlBrowserSession.channel, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
    for (final editor in editors.values) {
      messenger.setMockMethodCallHandler(editor.channel, null);
    }
    rig.controller.dispose();
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
  ComplexEditorKind kind = ComplexEditorKind.drawing;
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
        final value = jsonDecode(source) as Map<String, dynamic>;
        final data = value['data'] as Map<String, dynamic>;
        (data['main'] as List).add({
          'type': 'image',
          'value': args[1],
          'width': args[2],
          'height': args[3],
        });
        source = jsonEncode(value);
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
