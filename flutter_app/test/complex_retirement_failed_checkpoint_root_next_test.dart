import 'dart:async';
import 'dart:convert';
import 'dart:ffi' show DynamicLibrary;
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/local_store.dart';
import 'package:bookstark_flutter/core/local_data_paths.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/complex_editor_transport.dart';
import 'package:bookstark_flutter/core/complex_recovery_store.dart';
import 'package:bookstark_flutter/core/complex_recovery_vault.dart';
import 'package:bookstark_flutter/core/local_complex_editor_controller.dart';
import 'package:bookstark_flutter/core/local_complex_notes_repository.dart';
import 'package:bookstark_flutter/features/complex_editors/local_complex_note_page.dart';
import 'package:bookstark_flutter/features/html/html_browser_session.dart';
import 'package:bookstark_flutter/features/profile/profile_feature.dart';
import 'package:bookstark_flutter/features/profile/profile_page.dart';
import 'package:bookstark_flutter/features/auth/connection_page.dart';
import 'package:bookstark_flutter/main.dart';
import 'profile_root_test.dart' as root;

const _initialSource =
    '{"schema":"bookstark-richdoc","schema_version":1,"data":{"main":[{"value":"Original"}]}}';
const _changedSource =
    '{"schema":"bookstark-richdoc","schema_version":1,"data":{"main":[{"value":"Unsaved exact source"}]}}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  if (Platform.isLinux) {
    open.overrideFor(
      OperatingSystem.linux,
      () => DynamicLibrary.open('libsqlite3.so.0'),
    );
  }
  for (final heldClose in [false, true]) {
    testWidgets(
      'actual Root logout preserves failed checkpoint and retries storage only heldClose=$heldClose',
      (tester) async {
        root.seed();
        final server = root.Server();
        BookstarkClient? currentClient;
        final rig = _Rig();
        await tester.runAsync(rig.open);
        final bridge = _Bridge(tester, rig);
        bridge.install();
        final closeGate = heldClose ? Completer<void>() : null;
        try {
          await tester.pumpWidget(
            BookstarkApp(
              clientFactory: (base) {
                final client = server.client(base);
                currentClient = client;
                return client;
              },
            ),
          );
          await _pumpUntil(
            tester,
            () => find
                .byIcon(Icons.account_circle_outlined)
                .evaluate()
                .isNotEmpty,
          );
          await tester.tap(find.byIcon(Icons.account_circle_outlined));
          await _pumpUntil(
            tester,
            () => find.byType(ProfilePage).evaluate().isNotEmpty,
          );
          final feature = tester.widget<ProfileFeature>(
            find.byType(ProfileFeature),
          );
          final logout = feature.onLogout; // Actual Root._leaveServer.
          final originalCookies = Map<String, String>.from(
            currentClient!.exportSession(),
          );
          final context = tester.element(find.byType(ProfilePage));
          unawaited(
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => LocalComplexNotePage(
                  controller: rig.controller,
                  english: true,
                ),
              ),
            ),
          );
          await _pumpUntil(tester, () => bridge.editors.isNotEmpty);
          await bridge.ready(bridge.editors.values.single);
          final peer = bridge.editors.values.single;
          // No dirty callback: retirement must inspect the actual runtime.
          peer.source = _changedSource;
          peer.revision++;
          rig.bytes.failWrites = true;
          bridge.closeGate = closeGate;
          Object? failure;
          var finished = false;
          final first = logout().then<void>(
            (_) {
              finished = true;
            },
            onError: (Object error, StackTrace _) {
              failure = error;
              finished = true;
            },
          );
          await _pumpUntil(tester, () => bridge.closeAttempts == 1);
          expect(peer.retired, isTrue);
          expect(rig.bytes.writeAttempts, 1);
          expect(rig.controller.edit.document.source, _changedSource);
          expect(rig.controller.draftDurable, isFalse);
          expect(rig.controller.phase, ComplexSavePhase.draftFailed);
          expect(currentClient!.exportSession(), originalCookies);
          expect(find.byType(ConnectionPage), findsNothing);
          expect(await tester.runAsync(rig.updates), 0);
          expect(
            (await tester.runAsync(
              () => rig.repository.read(rig.baseline.id),
            ))!.document.source,
            _initialSource,
          );
          if (closeGate != null) {
            expect(finished, isFalse);
            expect(bridge.closeAcknowledged, isFalse);
            closeGate.complete();
          }
          await _pumpUntil(tester, () => finished);
          await first;
          expect(failure, isStateError);
          expect(bridge.closeAcknowledged, isTrue);
          expect(find.byType(LocalComplexNotePage), findsOneWidget);
          expect(currentClient!.exportSession(), originalCookies);
          final snapshots = peer.commandCounts['beginSnapshot'];
          final views = bridge.editors.length;
          expect(await rig.controller.vault.read(rig.baseline.id), isNull);
          rig.bytes.failWrites = false;
          var retried = false;
          final retry = logout().then<void>((_) {
            retried = true;
          });
          await _pumpUntil(tester, () => retried);
          await retry;
          expect(bridge.closeAttempts, 1);
          expect(bridge.editors.length, views);
          expect(peer.commandCounts['beginSnapshot'], snapshots);
          expect(rig.bytes.writeAttempts, 2);
          final retained = await rig.controller.vault.read(rig.baseline.id);
          expect(retained!.edit.document.source, _changedSource);
          expect(retained.pending, isFalse);
          expect(await tester.runAsync(rig.updates), 0);
          expect(find.byType(ConnectionPage), findsOneWidget);
          expect(currentClient!.exportSession(), isEmpty);
          expect(tester.takeException(), isNull);
        } finally {
          rig.bytes.failWrites = false;
          if (closeGate != null && !closeGate.isCompleted) closeGate.complete();
          await _settleOwned(tester, HtmlBrowserSession.closeActive());
          await tester.pumpWidget(const SizedBox.shrink());
          await _pumpTurns(tester);
          bridge.uninstall();
          await tester.runAsync(rig.close);
        }
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  }
}

class _Rig {
  late Directory directory;
  late LocalStore store;
  late LocalComplexNotesRepository repository;
  late ComplexNote baseline;
  late LocalComplexEditorController controller;
  final bytes = _FailingBytes();
  Future<void> open() async {
    directory = await Directory.systemTemp.createTemp(
      'retirement-store-failure-',
    );
    final paths = LocalDataPaths.legacy(
      databasePath: '${directory.path}/data.db',
      privateSupport: directory,
    );
    store = LocalStore(
      path: paths.databasePath,
      dataPaths: paths,
      factory: databaseFactoryFfiNoIsolate,
    );
    repository = LocalComplexNotesRepository(
      store,
      kind: ComplexEditorKind.richdoc,
      collection: 'note',
    );
    baseline = (await repository.createOnce(
      ComplexNoteEdit(
        title: 'Original',
        document: ComplexEditorDocument.parse(
          ComplexEditorKind.richdoc,
          _initialSource,
        ),
        labels: ['kept'],
      ),
      creationKey: 'd' * 32,
    )).note;
    controller = LocalComplexEditorController(
      repository: repository,
      vault: ComplexRecoveryVault(
        scope: repository.scope,
        collection: 'note',
        kind: ComplexEditorKind.richdoc,
        store: bytes,
      ),
      baseline: baseline,
    );
    final db = await store.database;
    await db.execute('CREATE TABLE retirement_updates(id INTEGER)');
    await db.execute(
      'CREATE TRIGGER retirement_update AFTER UPDATE ON notes '
      'BEGIN INSERT INTO retirement_updates(id) VALUES(NEW.id); END',
    );
  }

  Future<int> updates() async =>
      (await (await store.database).query('retirement_updates')).length;
  Future<void> close() async {
    controller.dispose();
    repository.dispose();
    await store.close();
    await directory.delete(recursive: true);
  }
}

class _FailingBytes implements ComplexRecoveryBytesStore {
  final values = <String, Uint8List>{};
  bool failWrites = false;
  int writeAttempts = 0;
  @override
  Future<Uint8List?> read(String key) async {
    final value = values[key];
    return value == null ? null : Uint8List.fromList(value);
  }

  @override
  Future<void> write(String key, Uint8List value) async {
    writeAttempts++;
    if (failWrites) throw StateError('Injected checkpoint failure');
    values[key] = Uint8List.fromList(value);
  }

  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }
}

Future<void> _pumpTurns(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 10));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1)),
    );
  }
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var i = 0; i < 200 && !condition(); i++) {
    await tester.pump(const Duration(milliseconds: 10));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1)),
    );
  }
  expect(
    condition(),
    isTrue,
    reason: 'Actual operation did not reach bounded condition',
  );
}

Future<void> _settleOwned(WidgetTester tester, Future<void> work) async {
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
  await _pumpUntil(tester, () => done);
  if (failure != null) Error.throwWithStackTrace(failure!, trace!);
}

class _Bridge {
  _Bridge(this.tester, this.rig);
  final WidgetTester tester;
  final _Rig rig;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final editors = <int, _EditorProtocol>{};
  Completer<void>? closeGate;
  int closeAttempts = 0;
  bool closeAcknowledged = false;
  void install() {
    messenger.setMockMethodCallHandler(HtmlBrowserSession.channel, (
      call,
    ) async {
      if (call.method == 'close') {
        closeAttempts++;
        await closeGate?.future;
        closeAcknowledged = true;
      } else if (call.method != 'openLocal') {
        throw StateError('Unexpected browser session command');
      }
      return null;
    });
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
      call,
    ) async {
      final args = call.arguments as Map;
      if (call.method == 'create') {
        if (args['viewType'] != 'bookstark/complex_editor_view') {
          throw StateError('Unexpected platform view type');
        }
        final params =
            const StandardMessageCodec().decodeMessage(
                  ByteData.sublistView(args['params'] as Uint8List),
                )
                as Map;
        final id = args['id'] as int;
        final editor = _EditorProtocol(id, params['lease'] as String);
        editors[id] = editor;
        messenger.setMockMethodCallHandler(editor.channel, (call) async {
          if (call.method != 'command') {
            throw StateError('Expected actual command RPC');
          }
          final payload = call.arguments as Map;
          return editor.command(
            payload['name'] as String,
            (payload['arguments'] as List).cast<Object?>(),
          );
        });
        return 99;
      }
      if (call.method == 'resize') {
        return {'width': args['width'], 'height': args['height']};
      }
      return null;
    });
  }

  Future<void> ready(_EditorProtocol editor) async {
    await tester.runAsync(
      () => messenger.handlePlatformMessage(
        editor.channel.name,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('hostReady', {'lease': editor.lease}),
        ),
        (_) {},
      ),
    );
    await _pumpUntil(tester, () => editor.source == _initialSource);
    await tester.pump();
  }

  void uninstall() {
    messenger.setMockMethodCallHandler(HtmlBrowserSession.channel, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
    for (final editor in editors.values) {
      messenger.setMockMethodCallHandler(editor.channel, null);
    }
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
  final String resourceIdentity = '';
  final MethodChannel channel;
  ComplexEditorKind kind = ComplexEditorKind.drawing;
  String source = '';
  int generation = 1, revision = 1, transferNumber = 0;
  bool readOnly = true, localImages = false, retired = false, locked = false;
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
