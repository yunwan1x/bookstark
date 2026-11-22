import 'dart:async';
import 'dart:convert';
import 'dart:ffi' show DynamicLibrary;
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:bookstark_flutter/core/local_store.dart';
import 'package:bookstark_flutter/core/local_data_paths.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/complex_editor_transport.dart';
import 'package:bookstark_flutter/core/complex_recovery_store.dart';
import 'package:bookstark_flutter/core/complex_recovery_vault.dart';
import 'package:bookstark_flutter/core/local_complex_editor_controller.dart';
import 'package:bookstark_flutter/core/local_complex_notes_repository.dart';
import 'package:bookstark_flutter/core/native_complex_source_io.dart';
import 'package:bookstark_flutter/core/local_drawing_image_owner.dart';
import 'package:bookstark_flutter/core/local_drawing_local_files.dart';
import 'package:bookstark_flutter/features/complex_editors/local_complex_note_page.dart';
import 'package:bookstark_flutter/features/html/html_browser_session.dart';

const _initialSource =
    '{"elements":[{"id":"original","type":"rectangle","x":0,"y":0,"width":20,"height":20}],"files":{},"appState":{},"unknown":"keep"}';
const _png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aN3sAAAAASUVORK5CYII=';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  if (Platform.isLinux) {
    open.overrideFor(
      OperatingSystem.linux,
      () => DynamicLibrary.open('libsqlite3.so.0'),
    );
  }
  for (final collection in ['note', 'article']) {
    testWidgets(
      'real local drawing $collection library selection and actual transport checkpoint before one SQL Save',
      (tester) async {
        if (collection == 'article') {
          tester.view.physicalSize = const Size(320, 640);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
        }
        final rig = _Rig(collection);
        await tester.runAsync(rig.open);
        final bridge = _Bridge(tester, rig);
        try {
          await bridge.mount();
          final add = find.byWidgetPredicate(
            (widget) =>
                widget is IconButton && widget.tooltip == 'Add local image',
          );
          expect(add, findsOneWidget);
          await tester.tap(add);
          await _pumpUntil(
            tester,
            () => find
                .text('Choose from local file library')
                .evaluate()
                .isNotEmpty,
          );
          final choice = find.text('Choose from local file library');
          await tester.ensureVisible(choice);
          await tester.pumpAndSettle();
          expect(choice.hitTestable(), findsOneWidget);
          await tester.tap(choice.hitTestable());
          await _pumpUntil(
            tester,
            () => find.textContaining('-actual.png').evaluate().isNotEmpty,
          );
          final row = find.textContaining('-actual.png').first;
          await tester.ensureVisible(row);
          // ensureVisible updates scroll position; the next frame must lay out
          // the actual sheet before its hit-test region can move onscreen.
          await tester.pumpAndSettle();
          expect(row.hitTestable(), findsOneWidget);
          await tester.tap(row.hitTestable());
          await _pumpUntil(
            tester,
            () => find.text('Insert image').evaluate().isNotEmpty,
          );
          final insert = find.text('Insert image');
          expect(
            find.byKey(const ValueKey('local-drawing-information-scroll')),
            findsOneWidget,
          );
          expect(
            tester
                .getSize(
                  find.byKey(const ValueKey('local-article-editor-area')),
                )
                .height,
            greaterThanOrEqualTo(120),
          );
          expect(tester.takeException(), isNull);
          final insertButton = find.widgetWithText(
            FilledButton,
            'Insert image',
          );
          // Selection is shown before the old runtime's unlock RPC/finally
          // clears busy. Wait for the actual control, not merely its label.
          await _pumpUntil(
            tester,
            () => tester.widget<FilledButton>(insertButton).onPressed != null,
          );
          await tester.ensureVisible(insert);
          await tester.pumpAndSettle();
          final imageScroll = find.ancestor(
            of: insert,
            matching: find.byType(Scrollable),
          );
          expect(imageScroll, findsOneWidget);
          for (
            var attempt = 0;
            attempt < 12 && insert.hitTestable().evaluate().isEmpty;
            attempt++
          ) {
            // A large wrapped control can be above the clipped viewport after
            // ensureVisible clamps to max extent. Drag in the real direction
            // indicated by its geometry, never farther into the same boundary.
            final targetRect = tester.getRect(insertButton);
            final viewportRect = tester.getRect(imageScroll);
            await tester.drag(
              imageScroll,
              Offset(0, targetRect.center.dy < viewportRect.top ? 48 : -48),
            );
            await tester.pumpAndSettle();
          }
          expect(insert.hitTestable(), findsOneWidget);
          await tester.tap(insert.hitTestable());
          await _pumpUntil(
            tester,
            () =>
                rig.controller.draftDurable &&
                rig.controller.edit.document.source.contains(
                  'bookstark-attachment:',
                ),
          );
          final peer = bridge.editors.values.last;
          expect(peer.commandCounts['insertLocalDrawingImageSnapshot'], 1);
          expect(
            (await tester.runAsync(
              () => rig.repository.read(rig.baseline.id),
            ))!.document.source,
            _initialSource,
          );
          expect(await tester.runAsync(rig.updates), 0);
          final save = find.byWidgetPredicate(
            (widget) => widget is IconButton && widget.tooltip == 'Save',
          );
          await _pumpUntil(
            tester,
            () => tester.widget<IconButton>(save).onPressed != null,
          );
          await tester.ensureVisible(save);
          await tester.tap(save.hitTestable());
          await _pumpUntil(
            tester,
            () =>
                rig.controller.phase == ComplexSavePhase.ready &&
                !rig.controller.dirty &&
                !rig.controller.busy,
          );
          expect(await tester.runAsync(rig.updates), 1);
          final actual = (await tester.runAsync(
            () => rig.repository.read(rig.baseline.id),
          ))!;
          expect(actual.id, rig.baseline.id);
          expect(actual.document.kind, ComplexEditorKind.drawing);
          expect(actual.document.source, peer.source);
          expect(actual.labels, rig.baseline.labels);
          expect(rig.vaultStore.values, isEmpty);
          expect(peer.commandCounts['insertLocalDrawingImageSnapshot'], 1);
          expect(tester.takeException(), isNull);
        } finally {
          await bridge.close();
          await tester.runAsync(rig.close);
        }
      },
    );
  }
  testWidgets(
    'real SAF handoff closes old body; Root retires without human wait and late file is inert',
    (tester) async {
      final rig = _Rig('note');
      await tester.runAsync(rig.open);
      final picked = Completer<XFile?>();
      var entered = false;
      final bridge = _Bridge(
        tester,
        rig,
        pickAttachment: () {
          entered = true;
          return picked.future;
        },
      );
      try {
        await bridge.mount();
        final peer = bridge.editors.values.last;
        final add = find.byWidgetPredicate(
          (widget) =>
              widget is IconButton && widget.tooltip == 'Add local image',
        );
        await tester.tap(add);
        await _pumpUntil(
          tester,
          () => find.text('Import from device').evaluate().isNotEmpty,
        );
        final choice = find.text('Import from device');
        await tester.ensureVisible(choice);
        await tester.pumpAndSettle();
        await tester.tap(choice.hitTestable());
        await _pumpUntil(tester, () => entered);
        expect(peer.retired, isTrue);
        expect(await tester.runAsync(rig.updates), 0);
        var retired = false;
        unawaited(
          rig.sourceScope.retire().then((_) {
            retired = true;
          }),
        );
        await _pumpUntil(tester, () => retired);
        expect(picked.isCompleted, isFalse);
        picked.complete(
          XFile.fromData(
            Uint8List.fromList(base64Decode(_png)),
            name: 'late.png',
            path: 'late.png',
          ),
        );
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump();
        final db = (await tester.runAsync(() => rig.store.database))!;
        expect(
          await tester.runAsync(
            () => db.rawQuery(
              "SELECT node_id FROM local_drive_nodes WHERE instr(name,'late.png')>0",
            ),
          ),
          isEmpty,
        );
        expect(await tester.runAsync(rig.updates), 0);
        expect(
          (await tester.runAsync(
            () => rig.repository.read(rig.baseline.id),
          ))!.document.source,
          _initialSource,
        );
        expect(peer.commandCounts['insertLocalDrawingImageSnapshot'], isNull);
      } finally {
        if (!picked.isCompleted) picked.complete(null);
        await bridge.close();
        await tester.runAsync(rig.close);
      }
    },
  );
  testWidgets(
    'real Page refuses Save when initial actual engine receipt reports lost raster',
    (tester) async {
      final rig = _Rig('note');
      await tester.runAsync(rig.open);
      final bridge = _Bridge(tester, rig);
      try {
        await bridge.mount(hostReady: false);
        final peer = bridge.editors.values.last;
        peer.resourceFailed = true;
        await bridge.ready(peer);
        await _pumpUntil(
          tester,
          () => find
              .byWidgetPredicate(
                (widget) => widget is IconButton && widget.tooltip == 'Save',
              )
              .evaluate()
              .isNotEmpty,
        );
        final save = find.byWidgetPredicate(
          (widget) => widget is IconButton && widget.tooltip == 'Save',
        );
        expect(tester.widget<IconButton>(save).onPressed, isNull);
        expect(await tester.runAsync(rig.updates), 0);
        expect(
          (await tester.runAsync(
            () => rig.repository.read(rig.baseline.id),
          ))!.document.source,
          _initialSource,
        );
        expect(peer.commandCounts['insertLocalDrawingImageSnapshot'], isNull);
        expect(tester.takeException(), isNull);
      } finally {
        await bridge.close();
        await tester.runAsync(rig.close);
      }
    },
  );
  testWidgets(
    'initial-only SDK failure closes lease without losing unchanged original or granting Save',
    (tester) async {
      final rig = _Rig('note');
      await tester.runAsync(rig.open);
      final bridge = _Bridge(tester, rig);
      try {
        await bridge.mount(hostReady: false);
        final peer = bridge.editors.values.last;
        peer.failInitialization = true;
        await bridge.ready(peer, expectLoaded: false);
        await _pumpUntil(
          tester,
          () =>
              peer.retired &&
              find
                  .byTooltip('Export retained drawing source')
                  .evaluate()
                  .isNotEmpty,
        );
        final save = find.byWidgetPredicate(
          (widget) => widget is IconButton && widget.tooltip == 'Save',
        );
        expect(tester.widget<IconButton>(save).onPressed, isNull);
        expect(await tester.runAsync(rig.updates), 0);
        expect(rig.controller.edit.document.source, _initialSource);
        expect(
          (await tester.runAsync(
            () => rig.repository.read(rig.baseline.id),
          ))!.document.source,
          _initialSource,
        );
        expect(peer.commandCounts['insertLocalDrawingImageSnapshot'], isNull);
        expect(tester.takeException(), isNull);
      } finally {
        await bridge.close();
        await tester.runAsync(rig.close);
      }
    },
  );
}

class _Rig {
  _Rig(this.collection);
  final String collection;
  late Directory root;
  late LocalStore store;
  late LocalComplexNotesRepository repository;
  late ComplexNote baseline;
  late LocalComplexEditorController controller;
  late ComplexSourceIoScope sourceScope;
  late LocalDrawingImageOwner owner;
  late LocalDrawingLocalFiles files;
  final vaultStore = _MemoryBytesStore();
  Future<void> open() async {
    root = await Directory.systemTemp.createTemp('local-drawing-images-');
    final paths = LocalDataPaths.legacy(
      databasePath: '${root.path}/data.db',
      privateSupport: root,
    );
    store = LocalStore(
      path: paths.databasePath,
      dataPaths: paths,
      factory: databaseFactoryFfiNoIsolate,
    );
    repository = LocalComplexNotesRepository(
      store,
      kind: ComplexEditorKind.drawing,
      collection: collection,
    );
    baseline = (await repository.createOnce(
      ComplexNoteEdit(
        title: 'Actual rich document',
        document: ComplexEditorDocument.parse(
          ComplexEditorKind.drawing,
          _initialSource,
        ),
        labels: ['literal,label'],
      ),
      creationKey: 'a' * 32,
    )).note;
    controller = LocalComplexEditorController(
      repository: repository,
      vault: ComplexRecoveryVault(
        scope: repository.scope,
        collection: collection,
        kind: ComplexEditorKind.drawing,
        store: vaultStore,
      ),
      baseline: baseline,
    );
    sourceScope = await ComplexSourceIoScope.activate(
      scope: 'c' * 64,
      isCurrent: () => true,
      invoke: (method, args) async {
        if (method == 'scopeState') return {'epoch': 0};
        if (method == 'activateScope') return {'epoch': 1};
        if (method == 'retireScope') return {'retired': true};
        throw StateError('Unexpected Root scope method');
      },
    );
    owner = LocalDrawingImageOwner.open(
      store: store,
      controller: controller,
      sourceOwner: sourceScope,
      isCurrentScope: () => true,
    );
    files = LocalDrawingLocalFiles(owner);
    await files.importDeviceFile(
      XFile.fromData(
        Uint8List.fromList(base64Decode(_png)),
        name: 'actual.png',
        path: 'actual.png',
      ),
    );
    final db = await store.database;
    await db.execute('CREATE TABLE drawing_test_updates(id INTEGER)');
    await db.execute(
      'CREATE TRIGGER drawing_test_update AFTER UPDATE ON notes '
      'BEGIN INSERT INTO drawing_test_updates(id) VALUES(NEW.id); END',
    );
  }

  Future<int> updates() async =>
      (await (await store.database).query('drawing_test_updates')).length;
  Future<void> close() async {
    await files.retireAndDrain();
    await owner.retireAndDrain();
    await sourceScope.retire();
    controller.dispose();
    repository.dispose();
    await store.close();
    await root.delete(recursive: true);
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
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1)),
    );
  }
  expect(condition(), isTrue, reason: 'Condition did not settle within 800 ms');
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
  _Bridge(this.tester, this.rig, {this.pickAttachment});
  final Future<XFile?> Function()? pickAttachment;
  LocalDrawingLocalFiles get files => rig.files;
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
        if (args['viewType'] != 'bookstark/local_drawing_view' ||
            params.keys.toSet().difference({
              'lease',
              'resourceScope',
              'sourceDigest',
            }).isNotEmpty ||
            params.length != 3 ||
            params['sourceDigest'] != rig.controller.edit.document.digest) {
          throw StateError('Wrong actual local drawing factory/source mode');
        }
        final editor = _EditorProtocol(
          id,
          params['lease'] as String,
          viewType: args['viewType'] as String,
          resourceIdentity: params['resourceScope'] as String,
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
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(rig.collection == 'article' ? 2 : 1),
            viewInsets: EdgeInsets.only(
              bottom: rig.collection == 'article' ? 180 : 0,
            ),
          ),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => LocalComplexNotePage(
                    controller: rig.controller,
                    localDrawingFiles: files,
                    sourceIoScope: rig.sourceScope,
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

  Future<void> ready(_EditorProtocol editor, {bool expectLoaded = true}) async {
    await _incoming(editor, 'hostReady', {'lease': editor.lease});
    if (expectLoaded) {
      await _pumpUntil(
        tester,
        () => editor.source == rig.controller.edit.document.source,
      );
    }
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
    required this.resourceIdentity,
  }) : channel = MethodChannel('$viewType/$id');
  final int id;
  final String lease;
  final String resourceIdentity;
  final MethodChannel channel;
  ComplexEditorKind kind = ComplexEditorKind.drawing;
  String source = '';
  int generation = 1, revision = 1, transferNumber = 0;
  bool readOnly = true, localImages = false, retired = false, locked = false;
  bool resourceFailed = false;
  bool failInitialization = false;
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
        if (failInitialization)
          throw StateError('SDK initialization ACK failed');
        final id = args[0]! as String;
        source = utf8.decode(loads.remove(id)!.takeBytes());
        return {
          'ready': true,
          'kind': kind.name,
          'readOnly': readOnly,
          'generation': generation,
          'localDrawingResourceFailed': resourceFailed,
        };
      case 'state':
        return {
          'version': 1,
          'generation': generation,
          'revision': revision,
          'kind': kind.name,
          'ready': true,
          'dirty': revision > 1,
          'inputLocked': locked,
          'localDrawingResourceFailed': resourceFailed,
        };
      case 'setInputLocked':
        locked = args[0] == true;
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
      case 'insertLocalDrawingImageSnapshot':
        final id = args[0] as String;
        final bytes = snapshots[id];
        final options = args[2] as Map;
        if (bytes == null ||
            !locked ||
            readOnly ||
            kind != ComplexEditorKind.drawing ||
            options.length != 7 ||
            options['resourceId'] is! String ||
            !RegExp(
              r'^[a-f0-9]{64}$',
            ).hasMatch(options['resourceId'] as String) ||
            options['identityDigest'] != resourceIdentity ||
            options['scope'] != 'c' * 64 ||
            options['scopeEpoch'] != 1 ||
            options['sourceDigest'] != sha256.convert(bytes).toString()) {
          throw StateError('Invalid actual source-bound local image command');
        }
        final uri = Uri.parse(args[1] as String);
        if (uri.scheme != 'bookstark-attachment') {
          throw StateError('Local URI required');
        }
        final value = jsonDecode(source) as Map<String, dynamic>;
        (value['elements'] as List).add({
          'id': 'actual-image',
          'type': 'image',
          'fileId': 'actual-file',
          'width': options['width'],
          'height': options['height'],
        });
        (value['files'] as Map)['actual-file'] = {
          'id': 'actual-file',
          'dataURL': uri.toString(),
          'mimeType': 'image/png',
        };
        source = jsonEncode(value);
        snapshots.remove(id);
        revision++;
        return {
          'generation': generation,
          'kind': 'drawing',
          'ready': true,
          'inputLocked': true,
          'dirty': true,
          'localDrawingResourceFailed': resourceFailed,
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
