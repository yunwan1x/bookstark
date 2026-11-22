import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:bookstark_flutter/core/local_data_paths.dart';
import 'package:bookstark_flutter/core/local_recovery_resolver.dart';
import 'package:bookstark_flutter/core/local_storage_session.dart';
import 'package:bookstark_flutter/core/local_store.dart';
import 'package:bookstark_flutter/core/native_local_data_control.dart';
import 'package:bookstark_flutter/features/local_backup/local_backup_feature.dart';
import 'package:bookstark_flutter/features/local_backup/local_pending_recovery_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  if (Platform.isLinux) {
    open.overrideFor(
      OperatingSystem.linux,
      () => DynamicLibrary.open('libsqlite3.so.0'),
    );
  }
  late Directory root, cache;
  late LocalStore store;
  late LocalStorageSession session;
  late int noteId;
  var current = true, nativeReads = 0, inventoryReads = 0;
  final opened = <LocalRecoveryDestination>[];
  const prefs = MethodChannel('bookstark/recovery_storage');
  const complex = MethodChannel('bookstark/complex_recovery');
  const save = MethodChannel('bookstark/file_export');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() async {
    final base = Directory(
      Platform.environment['BOOKSTARK_APK_TEST_ROOT'] ??
          '${Directory.systemTemp.path}/bookstark-unit',
    );
    await base.create(recursive: true);
    root = await base.createTemp('backup-feature-');
    root = Directory(await root.resolveSymbolicLinks());
    cache = await Directory('${root.path}/cache').create();
    final layout = LocalDataPaths.legacy(
      databasePath: '${root.path}/content.db',
      privateSupport: root,
    );
    store = LocalStore(
      path: layout.databasePath,
      dataPaths: layout,
      factory: databaseFactoryFfiNoIsolate,
    );
    noteId = await store.createNote('实际恢复标题', '原有正文');
    current = true;
    nativeReads = 0;
    inventoryReads = 0;
    opened.clear();
    final control = NativeLocalDataControl(
      invoke: (method, args) async {
        expect(method, 'readState');
        nativeReads++;
        return {
          'format': 1,
          'pointerRaw': null,
          'intentRaw': null,
          'currentRetentionRaw': null,
          'sourceRetentionRaw': null,
          'metadataOnly': true,
        };
      },
    );
    session = LocalStorageSession(
      control: control,
      privateSupport: root,
      legacyDatabasePath: store.path,
      factory: databaseFactoryFfiNoIsolate,
    );
    messenger.setMockMethodCallHandler(prefs, (call) async {
      expect(call.method, 'localMetadata');
      inventoryReads++;
      final key =
          'bookstark.draft.v1.${base64Url.encode(utf8.encode(jsonEncode(['local', noteId])))}';
      return {
        'format': 1,
        'secureKeys': [key],
        'htmlKeys': [],
        'overflow': false,
        'valuesIncluded': false,
      };
    });
    messenger.setMockMethodCallHandler(
      complex,
      (_) async => {
        'format': 1,
        'keys': [],
        'unknownFiles': 0,
        'activeTransfers': 0,
        'overflow': false,
        'valuesIncluded': false,
      },
    );
    messenger.setMockMethodCallHandler(
      save,
      (_) async => throw StateError('Pending drafts must block save'),
    );
  });
  tearDown(() async {
    messenger.setMockMethodCallHandler(prefs, null);
    messenger.setMockMethodCallHandler(complex, null);
    messenger.setMockMethodCallHandler(save, null);
    await store.close();
    await root.delete(recursive: true);
  });
  Widget app() => MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (_) => LocalBackupFeature(
                session: session,
                privateCache: cache,
                store: store,
                isCurrentScope: () => current,
                onEntered: (_) async =>
                    throw StateError('No restore was confirmed'),
                onConnection: () async {},
                openDraft: (_, destination) async {
                  opened.add(destination);
                },
              ),
            ),
          ),
          child: const Text('打开备份'),
        ),
      ),
    ),
  );
  Future<void> settle(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 100 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(done(), isTrue);
  }

  testWidgets(
    'pending metadata opens exact owned editor and Android back keeps parent workflow',
    (tester) async {
      await tester.pumpWidget(app());
      await tester.tap(find.text('打开备份'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('导出备份'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('创建并导出'), 200);
      await tester.tap(find.text('创建并导出'));
      await tester.pump();
      await settle(tester, () => find.text('实际恢复标题').evaluate().isNotEmpty);
      expect(find.text('本机草稿'), findsOneWidget);
      expect(find.text('待处理'), findsOneWidget);
      expect(find.text('未保存记录已保留，请先处理。'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('打开编辑器'),
        200,
        scrollable: find.descendant(
          of: find.byType(LocalPendingRecoveryPage),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('打开编辑器').hitTestable());
      await tester.pump();
      await settle(
        tester,
        () =>
            opened.length == 1 &&
            find.byType(LinearProgressIndicator).evaluate().isEmpty,
      );
      expect(opened.single.id, noteId);
      expect(opened.single.namespace, 'local');
      expect(inventoryReads, greaterThanOrEqualTo(3));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('备份前核对'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('打开备份'), findsOneWidget);
      expect(
        (await tester.runAsync(() => store.readNote(noteId)))!['content'],
        '原有正文',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'expired app scope prevents export before native inventory or any editor navigation',
    (tester) async {
      await tester.pumpWidget(app());
      await tester.tap(find.text('打开备份'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('导出备份'));
      await tester.pumpAndSettle();
      current = false;
      await tester.scrollUntilVisible(find.text('创建并导出'), 200);
      await tester.tap(find.text('创建并导出'));
      await tester.pumpAndSettle();
      expect(nativeReads, 0);
      expect(inventoryReads, 0);
      expect(opened, isEmpty);
      expect(find.textContaining('操作未完成'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
