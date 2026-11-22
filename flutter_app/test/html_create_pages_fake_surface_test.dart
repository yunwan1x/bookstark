import 'dart:ffi' show DynamicLibrary;
import 'dart:io';

import 'package:bookstark_flutter/core/html_creation_vault.dart';
import 'package:bookstark_flutter/core/local_store.dart';
import 'package:bookstark_flutter/core/local_html_creation_controller.dart';
import 'package:bookstark_flutter/core/local_html_notes_repository.dart';
import 'package:bookstark_flutter/core/labels_repository.dart';
import 'package:bookstark_flutter/core/remote_html_creation_controller.dart';
import 'package:bookstark_flutter/core/remote_html_creation_repository.dart';
import 'package:bookstark_flutter/core/html_notes_repository.dart';
import 'package:bookstark_flutter/features/html/html_create_page.dart';
import 'package:bookstark_flutter/features/html/remote_html_create_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'html_note_page_fake_surface_test_support.dart';
import 'local_html_creation_controller_test.dart' show CreationMemory;
import 'remote_html_creation_controller_test.dart' show CreationServer;

class _EmptyLabels implements LabelsRepository {
  @override
  Future<List<String>> search(String keyword, {int page = 1}) async => [];
}

void main() {
  setUpAll(() {
    installFakeHtmlSessionChannel();
    sqfliteFfiInit();
    if (Platform.isLinux) {
      open.overrideFor(
        OperatingSystem.linux,
        () => DynamicLibrary.open('libsqlite3.so.0'),
      );
    }
  });

  testWidgets('local create Save waits for a validated source generation', (
    tester,
  ) async {
    final directory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('html-create-ready-test-'),
    ))!;
    final store = LocalStore(
      path: '${directory.path}/local.db',
      factory: databaseFactoryFfiNoIsolate,
    );
    await tester.runAsync(() => store.database);
    final memory = CreationMemory();
    final controller = LocalHtmlCreationController(
      LocalHtmlNotesRepository(store),
      memory.vault(),
    );
    final control = FakeHtmlSurfaceControl(autoReady: false);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push<int>(
                MaterialPageRoute(
                  builder: (_) => HtmlCreatePage(
                    controller: controller,
                    labels: LocalLabelsRepository(store),
                    english: true,
                    sourceSurfaceBuilder: fakeHtmlSourceSurface(control),
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Save'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('Complete fake load'));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Save'))
          .onPressed,
      isNotNull,
    );
    expect(
      await tester.runAsync(() async => (await store.database).query('notes')),
      isEmpty,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(store.close);
    await tester.runAsync(() => directory.delete(recursive: true));
  });

  testWidgets(
    'local create captures source before durable insert and retires before pop',
    (tester) async {
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('html-create-webview-test-'),
      ))!;
      final store = LocalStore(
        path: '${directory.path}/local.db',
        factory: databaseFactoryFfiNoIsolate,
      );
      await tester.runAsync(() => store.database);
      final memory = CreationMemory();
      final controller = LocalHtmlCreationController(
        LocalHtmlNotesRepository(store),
        memory.vault(),
      );
      final control = FakeHtmlSurfaceControl();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.of(context).push<int>(
                  MaterialPageRoute(
                    builder: (_) => HtmlCreatePage(
                      controller: controller,
                      labels: LocalLabelsRepository(store),
                      english: true,
                      sourceSurfaceBuilder: fakeHtmlSourceSurface(control),
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      for (var i = 0; i < 40 && control.inputLocked; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(find.text('Fake HTML source surface'), findsOneWidget);
      await tester.tap(find.text('Preview'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Source'));
      await tester.pumpAndSettle();
      for (var i = 0; i < 40 && control.sessionOpens < 2; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(find.text('Fake HTML source surface'), findsOneWidget);
      expect(control.sessionOpens, 2);
      expect(control.retireCalls, 1);
      await tester.tap(find.text('Reload fake source'));
      await tester.pumpAndSettle();
      for (var i = 0; i < 40 && control.sessionOpens < 3; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(find.text('Fake HTML source surface'), findsOneWidget);
      expect(control.sessionOpens, 3);
      expect(control.retireCalls, 2);
      await tester.enterText(
        find.byKey(const ValueKey('html-create-title')),
        'Captured local title',
      );
      await tester.ensureVisible(find.text('Change fake HTML source'));
      await tester.tap(find.text('Change fake HTML source'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump();
      expect(
        controller.draft.source,
        '<!doctype html><p>changed through fake transport</p>\r\n',
      );
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      for (
        var i = 0;
        i < 80 && controller.phase != HtmlCreationPhase.finished;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(controller.phase, HtmlCreationPhase.finished);
      final row = (await tester.runAsync(
        () async => (await store.database).query('notes'),
      ))!.single;
      expect(row['content'], controller.created!.source);
      expect(row['content'], contains('changed through fake transport'));
      expect(
        await tester.runAsync(
          () async => (await store.database).query('html_creation_receipts'),
        ),
        isNotEmpty,
      );
      await tester.pumpAndSettle();
      expect(find.text('Fake HTML source surface'), findsNothing);
      expect(control.sessionOpens, 3);
      expect(control.retireCalls, 3);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(store.close);
      await tester.runAsync(() => directory.delete(recursive: true));
    },
  );

  testWidgets(
    'remote create submits one captured draft and never uses existing-note save',
    (tester) async {
      final server = CreationServer();
      final vaultData = <String, String>{};
      final vault = HtmlCreationVault(
        server: Uri.parse('https://books.example'),
        memberId: 3,
        collection: 'note',
        readValue: (key) async => vaultData[key],
        writeValue: (key, value) async {
          vaultData[key] = value;
        },
        deleteValue: (key) async {
          vaultData.remove(key);
        },
      );
      final controller = RemoteHtmlCreationController(
        RemoteHtmlCreationRepository(
          server.client,
          memberId: 3,
          collection: 'note',
        ),
        vault,
      );
      controller.edit(
        HtmlNoteEdit(
          title: 'Draft title',
          source: controller.draft!.source,
          labels: const ['fixture-label'],
        ),
      );
      final control = FakeHtmlSurfaceControl();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.of(context).push<int>(
                  MaterialPageRoute(
                    builder: (_) => RemoteHtmlCreatePage(
                      controller: controller,
                      labels: _EmptyLabels(),
                      serverLabel: 'fixture',
                      english: true,
                      sourceSurfaceBuilder: fakeHtmlSourceSurface(control),
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Change fake HTML source'));
      await tester.tap(find.text('Change fake HTML source'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('remote-html-create-title')),
        'Captured create',
      );
      await tester.pump();
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      for (
        var i = 0;
        i < 100 && controller.phase != RemoteHtmlCreationPhase.finished;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(controller.phase, RemoteHtmlCreationPhase.finished);
      expect(server.posts, 1);
      expect(server.source, contains('changed through fake transport'));
      expect(server.row['blog_title'], 'Captured create');
      expect(server.contentWrites, 0);
      expect(server.labelWrites, 0);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      server.client.close();
      server.repo.dispose();
    },
  );
  testWidgets(
    'forced page destruction captures the immediate source before retiring',
    (tester) async {
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('html-create-forced-close-'),
      ))!;
      final store = LocalStore(
        path: '${directory.path}/local.db',
        factory: databaseFactoryFfiNoIsolate,
      );
      await tester.runAsync(() => store.database);
      final memory = CreationMemory();
      final controller = LocalHtmlCreationController(
        LocalHtmlNotesRepository(store),
        memory.vault(),
      );
      final control = FakeHtmlSurfaceControl();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => HtmlCreatePage(
                      controller: controller,
                      labels: LocalLabelsRepository(store),
                      english: true,
                      sourceSurfaceBuilder: fakeHtmlSourceSurface(control),
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      for (var i = 0; i < 40 && control.inputLocked; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.tap(find.text('Change fake HTML source'));
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      for (var i = 0; i < 40 && control.retireCalls == 0; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 10));
      }
      for (var i = 0; i < 40 && memory.values.isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(control.retireCalls, 1);
      final draft = await tester.runAsync(() => memory.vault().read());
      expect(draft!.edit.source, contains('changed through fake transport'));
      expect(
        (await tester.runAsync(
          () async => (await store.database).query('notes'),
        )),
        isEmpty,
      );
      await tester.runAsync(store.close);
      await tester.runAsync(() => directory.delete(recursive: true));
    },
  );
}
