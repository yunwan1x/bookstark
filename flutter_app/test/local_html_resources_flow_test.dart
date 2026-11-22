import 'dart:ffi' show DynamicLibrary;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:file_selector/file_selector.dart';
import 'package:sqlite3/open.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:bookstark_flutter/core/local_store.dart';
import 'package:bookstark_flutter/core/local_drive_repository.dart';
import 'package:bookstark_flutter/core/drive_source.dart';
import 'package:bookstark_flutter/core/drive_models.dart';
import 'package:bookstark_flutter/core/html_notes_repository.dart';
import 'package:bookstark_flutter/core/local_html_notes_repository.dart';
import 'package:bookstark_flutter/core/local_html_resources_repository.dart';
import 'package:bookstark_flutter/features/html/local_html_preview_panel.dart';

void main() {
  sqfliteFfiInit();
  if (Platform.isLinux) {
    open.overrideFor(
      OperatingSystem.linux,
      () => DynamicLibrary.open('libsqlite3.so.0'),
    );
  }
  late Directory space;
  late LocalStore store;
  late LocalDriveRepository drive;
  late LocalHtmlResourcesRepository repo;
  late DriveNode file;
  late int id;
  var sequence = 0;
  const source = '<p>Original HTML</p>';
  setUp(() async {
    final base = Directory(
      Platform.environment['BOOKSTARK_APK_TEST_ROOT'] ??
          Directory.systemTemp.path,
    );
    await base.create(recursive: true);
    space = await base.createTemp('html-resource-flow-');
    store = LocalStore(
      path: '${space.path}/data.db',
      factory: databaseFactoryFfiNoIsolate,
    );
    drive = LocalDriveRepository(store, Directory('${space.path}/drive-blobs'));
    repo = LocalHtmlResourcesRepository(store, drive, collection: 'note');
    final notes = LocalHtmlNotesRepository(store);
    id = (await notes.create(
      HtmlNoteEdit(title: 'HTML', source: source, labels: []),
    )).metadata.id;
    notes.dispose();
    sequence = 0;
    final f = File('${space.path}/theme.css');
    await f.writeAsString('body{color:blue}');
    file = (await drive.upload(
      await DriveSourceSnapshot.prepare(XFile(f.path), maxBytes: 1024),
      target: 'theme.css',
    )).node;
    await repo.replace(id, [
      HtmlResourceChoice(path: 'theme.css', node: file),
    ], baseline: []);
  });
  tearDown(() async {
    drive.dispose();
    await store.close();
    await space.delete(recursive: true);
  });
  Future<void> ready(WidgetTester tester, bool Function() test) async {
    bool complete() =>
        test() &&
        find.byType(LinearProgressIndicator).evaluate().isEmpty &&
        find.byType(CircularProgressIndicator).evaluate().isEmpty;
    for (var i = 0; i < 100 && !complete(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(complete(), isTrue);
    await tester.pumpAndSettle();
  }

  Future<void> mount(
    WidgetTester tester, {
    Future<XFile?> Function()? pick,
    bool small = false,
  }) async {
    if (small) {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(small ? 2 : 1)),
          child: child!,
        ),
        home: Scaffold(
          body: SizedBox(
            height: 520,
            child: LocalHtmlPreviewPanel(
              repository: repo,
              noteId: id,
              source: source,
              pickFile: pick,
              previewBuilder: (doc) => Text(
                'Rendered:${doc.resources.map((r) => r.path).join(',')}',
              ),
            ),
          ),
        ),
      ),
    );
    await ready(
      tester,
      () => find.text('Rendered:theme.css').evaluate().isNotEmpty,
    );
  }

  Future<void> sheet(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('local-html-resources')));
    await tester.pump();
    await ready(
      tester,
      () => find
          .byKey(const ValueKey('html-resource-check-theme.css'))
          .evaluate()
          .isNotEmpty,
    );
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    final f = find.text(text).last;
    await tester.ensureVisible(f);
    await tester.tap(f);
    await tester.pump();
    if (find.byType(LinearProgressIndicator).evaluate().isEmpty) {
      await tester.pumpAndSettle();
    }
  }

  testWidgets(
    'cancel keeps SQLite bindings and the existing rendered document',
    (tester) async {
      await mount(tester);
      await sheet(tester);
      await tester.tap(
        find.byKey(const ValueKey('html-resource-check-theme.css')),
      );
      await tester.pump();
      await tapText(tester, '取消');
      final bindings = await tester.runAsync(() => repo.list(id));
      expect(bindings!.single.binding.path, 'theme.css');
      expect(find.text('Rendered:theme.css'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'apply removes only binding and reloads actual preview input without deleting file or note source',
    (tester) async {
      await mount(tester);
      await sheet(tester);
      await tester.tap(
        find.byKey(const ValueKey('html-resource-check-theme.css')),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('html-resource-apply')));
      await tester.pump();
      await ready(tester, () => find.text('Rendered:').evaluate().isNotEmpty);
      expect(
        await tester.runAsync(
          () async => (await store.readNote(id))['content'],
        ),
        source,
      );
      expect(await tester.runAsync(() => drive.bytes(file)), isNotEmpty);
      expect(await tester.runAsync(() => repo.list(id)), isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'changed file during selection requires reload and explicit new approval',
    (tester) async {
      await mount(tester);
      await sheet(tester);
      await tester.runAsync(() async {
        final f = File('${space.path}/changed-${sequence++}.css');
        await f.writeAsString('body{color:red}');
        await drive.upload(
          await DriveSourceSnapshot.prepare(XFile(f.path), maxBytes: 1024),
          target: 'theme.css',
          expected: file,
        );
      });
      await tester.tap(find.byKey(const ValueKey('html-resource-apply')));
      await tester.pump();
      await ready(tester, () => find.text('重新读取').evaluate().isNotEmpty);
      expect(
        (await tester.runAsync(() => repo.list(id)))!.single.changed,
        isTrue,
      );
      await tapText(tester, '重新读取');
      await ready(
        tester,
        () => find.text('文件已更新，应用后使用新版').evaluate().isNotEmpty,
      );
      await tester.tap(find.byKey(const ValueKey('html-resource-apply')));
      await tester.pump();
      await ready(
        tester,
        () => find.byType(LocalHtmlResourceSheet).evaluate().isEmpty,
      );
      expect(
        (await tester.runAsync(() => repo.list(id)))!.single.changed,
        isFalse,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'cancelled device chooser imports nothing and preserves selected resources',
    (tester) async {
      await mount(tester, pick: () async => null);
      await sheet(tester);
      await tester.tap(find.byKey(const ValueKey('html-resource-add')));
      await tester.pumpAndSettle();
      await tapText(tester, '从本机文件添加');
      expect((await tester.runAsync(() => repo.available()))!, hasLength(1));
      await tapText(tester, '取消');
      expect(find.text('Rendered:theme.css'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'real local file import binds its chosen relative path only on Apply',
    (tester) async {
      final input = File('${space.path}/cover.css');
      await tester.runAsync(() => input.writeAsString('img{max-width:100%}'));
      await mount(tester, pick: () async => XFile(input.path));
      await sheet(tester);
      await tester.tap(find.byKey(const ValueKey('html-resource-add')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('从本机文件添加'));
      await tester.pump();
      await ready(tester, () => find.text('网页内的附件路径').evaluate().isNotEmpty);
      await tapText(tester, '添加');
      expect((await tester.runAsync(() => repo.list(id)))!, hasLength(1));
      await tester.tap(find.byKey(const ValueKey('html-resource-apply')));
      await tester.pump();
      await ready(
        tester,
        () => find.text('Rendered:cover.css,theme.css').evaluate().isNotEmpty,
      );
      expect((await tester.runAsync(() => repo.list(id)))!, hasLength(2));
      expect(
        await tester.runAsync(() => input.readAsString()),
        'img{max-width:100%}',
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    '320dp doubled text keeps resource selection and apply/cancel scrollable',
    (tester) async {
      await mount(tester, small: true);
      await sheet(tester);
      final apply = find.byKey(const ValueKey('html-resource-apply'));
      await tester.ensureVisible(apply);
      expect(tester.takeException(), isNull);
      await tapText(tester, '取消');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
