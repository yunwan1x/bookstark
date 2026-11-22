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

import 'package:bookstark_flutter/core/owned_preview_controller.dart';
import 'package:bookstark_flutter/core/protected_complex_lifetime.dart';
import 'package:bookstark_flutter/core/protected_owned_complex_journal.dart';

const _scope =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _initialSource = '{"elements":[],"future":"baseline"}';
const _editedSource = '{"elements":[],"future":"edited"}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final invalid in [false, true]) {
    testWidgets(
      invalid
          ? 'retired owner cannot reopen protected actual browser'
          : 'actual page renews retired preview through real owner before reopening browser',
      (tester) async {
        var current = true, renewals = 0;
        final values = <String, String>{};
        final journal = ProtectedOwnedComplexJournal(
          scope: _scope,
          ownerTag: _scope,
          isCurrent: () => current,
          readValue: (k) async => values[k],
          writeValue: (k, v) async {
            values[k] = v;
          },
          deleteValue: (k) async {
            values.remove(k);
          },
          flush: () async {},
        );
        final owner = ProtectedComplexLifetime(
          journal: journal,
          isCurrentScope: () => current,
          onDrained: (_) {},
        );
        final original = owner.preview;
        final rig = _Rig();
        final bridge = _Bridge(
          tester,
          rig,
          preview: original,
          renew: () async {
            renewals++;
            await owner.nextPreview();
            return owner.preview;
          },
        );
        await bridge.mount();
        try {
          final before = bridge.editors.length;
          await HtmlBrowserSession.closeActive();
          await tester.pumpAndSettle();
          expect(original.retired, true);
          current = !invalid;
          await tester.tap(find.text('Reload'));
          await tester.pump();
          if (invalid) {
            for (var n = 0; n < 12; n++) {
              await tester.pump();
            }
            expect(bridge.editors.length, before);
            expect(renewals, 1);
          } else {
            await _pumpUntil(tester, () => bridge.editors.length == before + 1);
            await bridge.ready(bridge.editors.values.last);
            expect(renewals, 1);
            expect(identical(owner.preview, original), false);
            expect(owner.preview.retired, false);
            expect(
              bridge.editors.values.last.source,
              rig.baseline.document.source,
            );
          }
          expect(rig.repository.saveCount, 0);
          expect(tester.takeException(), isNull);
        } finally {
          await bridge.close();
          await owner.retire();
          owner.preview.dispose();
        }
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  }
  testWidgets(
    'unacknowledged old native close cannot reopen a new actual browser',
    (tester) async {
      final values = <String, String>{};
      final journal = ProtectedOwnedComplexJournal(
        scope: _scope,
        ownerTag: _scope,
        isCurrent: () => true,
        readValue: (k) async => values[k],
        writeValue: (k, v) async {
          values[k] = v;
        },
        deleteValue: (k) async {
          values.remove(k);
        },
        flush: () async {},
      );
      final owner = ProtectedComplexLifetime(
        journal: journal,
        isCurrentScope: () => true,
        onDrained: (_) {},
      );
      var renewals = 0;
      final rig = _Rig();
      final bridge = _Bridge(
        tester,
        rig,
        preview: owner.preview,
        renew: () async {
          renewals++;
          await owner.nextPreview();
          return owner.preview;
        },
      );
      await bridge.mount();
      final gate = Completer<void>();
      var closeEntered = false;
      bridge.messenger.setMockMethodCallHandler(HtmlBrowserSession.channel, (
        call,
      ) async {
        bridge.sessionCalls.add(call);
        if (call.method == 'close') {
          closeEntered = true;
          await gate.future;
        }
        return null;
      });
      final closing = HtmlBrowserSession.closeActive();
      var done = false;
      closing.then((_) => done = true);
      try {
        await _pumpUntil(tester, () => closeEntered);
        for (var n = 0; n < 10; n++) {
          await tester.pump();
        }
        expect(done, false);
        expect(bridge.editors.length, 1);
        expect(renewals, 0);
        expect(find.text('Reload'), findsNothing);
        gate.complete();
        await tester.pump();
        await closing;
        await tester.pumpAndSettle();
        await tester.tap(find.text('Reload'));
        await tester.pump();
        await _pumpUntil(tester, () => bridge.editors.length == 2);
        await bridge.ready(bridge.editors.values.last);
        expect(renewals, 1);
        expect(rig.repository.saveCount, 0);
        expect(tester.takeException(), isNull);
      } finally {
        if (!gate.isCompleted) gate.complete();
        await bridge.close();
        await owner.retire();
        owner.preview.dispose();
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
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
  collection: markdown ? 'article' : 'note',
  title: markdown ? 'Local article' : 'Local drawing',
  document: ComplexEditorDocument.parse(
    markdown ? ComplexEditorKind.markdown : ComplexEditorKind.drawing,
    source,
  ),
  version: 10,
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
  _Bridge(this.tester, this.rig, {required this.preview, required this.renew})
    : pickAttachment = null,
      attachments = null;
  final OwnedPreviewController preview;
  final Future<OwnedPreviewController> Function() renew;
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
                    retirementController: preview,
                    renewRetirementController: renew,
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
    await messenger.handlePlatformMessage(
      editor.channel.name,
      const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)),
      (_) {},
    );
    await tester.pump();
  }

  Future<void> close() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await HtmlBrowserSession.closeActive();
    await tester.pump();
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

  Future<Object?> command(String name, List<Object?> args) async {
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
