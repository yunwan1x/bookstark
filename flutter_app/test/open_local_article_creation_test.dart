import 'dart:convert';
import 'dart:ffi' show DynamicLibrary;
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:bookstark_flutter/features/html/html_browser_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/open.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/draft_vault.dart';
import 'package:bookstark_flutter/core/local_article_creation_legacy_metadata.dart';
import 'package:bookstark_flutter/core/local_article_creation_record.dart';
import 'package:bookstark_flutter/core/local_complex_notes_repository.dart';
import 'package:bookstark_flutter/core/local_data_paths.dart';
import 'package:bookstark_flutter/core/local_store.dart';
import 'package:bookstark_flutter/core/notes_repository.dart';
import 'package:bookstark_flutter/features/complex_editors/article_draft_archive_view.dart';
import 'package:bookstark_flutter/features/complex_editors/local_article_create_page.dart';
import 'package:bookstark_flutter/features/complex_editors/local_complex_note_page.dart';
import 'package:bookstark_flutter/features/complex_editors/local_article_creation_services.dart';
import 'package:bookstark_flutter/features/complex_editors/open_local_article_creation.dart';
import 'support/article_creation_storage.dart';
import 'support/article_creation_views.dart';

void androidTestWidgets(String name, Future<void> Function(WidgetTester) body) {
  testWidgets(
    name,
    body,
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    sqfliteFfiInit();
    if (Platform.isLinux) {
      open.overrideFor(
        OperatingSystem.linux,
        () => DynamicLibrary.open('libsqlite3.so.0'),
      );
    }
  });
  late Directory root;
  late LocalStore store;
  late DraftVault legacy;
  late OwnedBytes bytes;
  late OwnedArticleCreationViews views;
  final prefs = <String, String>{};
  bool? result;
  Object? failure;
  int? openedId;
  var nativeLeaseOpens = 0;
  const body = '\ufeff\ufeff# 原旧稿\r\n- 保留字节\r\n';
  String oldKey() => legacy.metadataKey(null);
  String markerKey() =>
      LocalArticleCreationLegacyScope.fromLegacyKey(oldKey()).markerKey;
  LocalArticleCreationServices services() =>
      LocalArticleCreationServices.forStore(
        store,
        legacy: legacy,
        byteStore: bytes,
        fingerprint: (key) async {
          final raw = prefs[key];
          return raw == null
              ? null
              : sha256.convert(utf8.encode('owned-seal:$raw')).toString();
        },
        flush: () async {},
      );
  Future<int> count() async =>
      (await (await store.database).query('notes')).length;
  setUp(() async {
    nativeLeaseOpens = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(HtmlBrowserSession.channel, (call) async {
          if (call.method == 'openLocal') nativeLeaseOpens++;
          // Real route/body/SQL assertions remain. This host has no Android
          // WebView implementation, so fail explicitly rather than fake ready.
          throw MissingPluginException(
            'Native complex engine unsupported in host test',
          );
        });

    root = await Directory.systemTemp.createTemp('article-create-entry-');
    final layout = LocalDataPaths.legacy(
      databasePath: '${root.path}/content.db',
      privateSupport: root,
    );
    store = LocalStore(
      path: layout.databasePath,
      dataPaths: layout,
      factory: databaseFactoryFfiNoIsolate,
    );
    await store.database;
    prefs.clear();
    bytes = OwnedBytes();
    views = OwnedArticleCreationViews(bytes.events);
    legacy = DraftVault(
      namespace: jsonEncode([layout.draftNamespace, 'article']),
      maintenance: store.maintenance,
      readValue: (key) async => prefs[key],
      writeValue: (key, value) async {
        prefs[key] = value;
      },
      deleteValue: (key) async {
        prefs.remove(key);
      },
    );
    result = null;
    failure = null;
    openedId = null;
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(HtmlBrowserSession.channel, null);

    await store.close();
    await root.delete(recursive: true);
  });
  Future<void> until(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 150 && !done(); i++) {
      if (failure != null) fail('Owned entry failure: ${failure.runtimeType}');
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(failure, isNull);
    expect(done(), isTrue);
  }

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Column(
              children: [
                for (final forced in [false, true])
                  TextButton(
                    onPressed: () async {
                      result = null;
                      final env = services();
                      try {
                        result = await openLocalArticleCreation(
                          context,
                          store: store,
                          legacyDrafts: legacy,
                          forceLegacyReview: forced,
                          services: env,
                          sourceBuilder: views.editor,
                          reviewBuilder: views.review,
                        );
                      } catch (error) {
                        failure = error;
                      } finally {
                        env.dispose();
                      }
                    },
                    child: Text(forced ? '核对旧原稿' : '打开新建'),
                  ),
                TextButton(
                  onPressed: () async {
                    result = null;
                    final env = services();
                    try {
                      result = await openLocalArticleCreationArchive(
                        context,
                        store: store,
                        namespace: legacy.namespace,
                        services: env,
                        archiveBuilder: views.archive,
                        sourceBuilder: views.editor,
                        reviewBuilder: views.review,
                        existingArticleOpener: (id) async {
                          openedId = id;
                          return true;
                        },
                      );
                    } catch (error) {
                      failure = error;
                    } finally {
                      env.dispose();
                    }
                  },
                  child: const Text('查看已处理旧稿'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }

  Future<void> ready(WidgetTester tester) async => until(
    tester,
    () =>
        find.byType(LocalArticleCreatePage).evaluate().isNotEmpty &&
        views.states.isNotEmpty &&
        views.states.last.mounted &&
        views.states.last.ready &&
        !views.states.last.widget.lease.retired,
  );
  Future<void> finishKnownHandoff(WidgetTester tester) async {
    await until(
      tester,
      () => find.byType(LocalComplexNotePage).evaluate().isNotEmpty,
    );
    final page = tester.widget<LocalComplexNotePage>(
      find.byType(LocalComplexNotePage),
    );
    final actual = page.controller.baseline;
    expect(actual.id, greaterThan(0));
    expect(actual.collection, 'article');
    expect(actual.document.kind, ComplexEditorKind.markdown);
    expect(actual.document.source, body);
    expect(page.controller.dirty, false);
    final rows = await tester.runAsync(
      () async => (await store.database).query('notes'),
    );
    expect(rows!.length, 1);
    expect(rows.single['id'], actual.id);
    final exact = await tester.runAsync(
      () async => (await store.database).rawQuery(
        'SELECT CAST(content AS BLOB) bytes FROM notes WHERE id=?',
        [actual.id],
      ),
    );
    expect(exact!.single['bytes'], utf8.encode(body));
    // This is the actual existing-ID page, not an injected open callback.
    // No native engine execution is claimed by this host route test.
    await until(
      tester,
      () => find.text('编辑器已关闭或暂不可用，原始内容已保留。').evaluate().isNotEmpty,
    );
    expect(nativeLeaseOpens, 1);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back').first);
    await tester.pump();
  }

  Future<void> home(WidgetTester tester) async => until(
    tester,
    () =>
        result != null &&
        find.byType(LocalArticleCreatePage).evaluate().isEmpty &&
        find.byType(ArticleDraftArchiveView).evaluate().isEmpty &&
        find.byType(AlertDialog).evaluate().isEmpty,
  );
  Future<void> tap(
    WidgetTester tester,
    String label, {
    bool filled = false,
  }) async {
    await tester.pumpAndSettle();
    final target = filled
        ? find.widgetWithText(FilledButton, label)
        : find.text(label);
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target.hitTestable());
    await tester.pump();
  }

  Future<String> seed() async {
    await legacy.write(
      const Note(
        title: 'Legacy article',
        content: body,
        labels: ['z', 'old,label'],
      ),
    );
    return prefs[oldKey()]!;
  }

  androidTestWidgets(
    'legacy restore needs explicit Create and archived completed input opens the same resource',
    (tester) async {
      final original = await seed();
      await mount(tester);
      await tap(tester, '打开新建');
      await until(tester, () => find.text('发现原有新建草稿').evaluate().isNotEmpty);
      expect(await tester.runAsync(count), 0);
      await tap(tester, '恢复草稿');
      await ready(tester);
      expect(views.states.last.widget.readOnly, isFalse);
      final debugEnv = services();
      final durable = await debugEnv.vault.read();
      debugEnv.dispose();
      expect(
        durable!.edit.document.source,
        body,
        reason: 'durable transfer must preserve BOM',
      );
      expect(
        views.states.last.widget.document.source,
        body,
        reason: 'surface seed must preserve BOM',
      );
      expect(
        views.states.last.host.source,
        body,
        reason: 'owned protocol load must preserve BOM',
      );
      expect(await tester.runAsync(count), 0);
      expect(prefs[oldKey()], original);
      final marker = LocalArticleCreationLegacyReceipt.parse(
        prefs[markerKey()]!,
      );
      await tap(tester, '创建');
      await finishKnownHandoff(tester);
      await home(tester);
      expect(result, isTrue);
      expect(await tester.runAsync(count), 1);
      expect(bytes.values, isEmpty);
      expect(prefs[oldKey()], original);
      final rows = await tester.runAsync(
        () async => (await store.database).query('notes'),
      );
      final id = rows!.single['id'] as int;
      expect(rows.single['title'], 'Legacy article');
      final exact = await tester.runAsync(
        () async => (await store.database).rawQuery(
          'SELECT CAST(content AS BLOB) bytes FROM notes WHERE id = ?',
          [id],
        ),
      );
      expect(exact!.single['bytes'], utf8.encode(body));
      final typedReader = services();
      final saved = await tester.runAsync(
        () => typedReader.repository.read(id),
      );
      typedReader.dispose();
      expect(saved!.document.source, body);
      expect(jsonDecode(rows.single['labels'] as String), ['z', 'old,label']);
      final ledger = await tester.runAsync(
        () async => (await store.database).query('html_creation_receipts'),
      );
      expect(ledger!.single['creation_key'], marker.creationKey);
      await tap(tester, '查看已处理旧稿');
      await until(
        tester,
        () =>
            find.text('打开已创建文章').evaluate().isNotEmpty &&
            views.states.last.ready,
      );
      expect(views.states.last.widget.readOnly, isTrue);
      expect(views.states.last.host.source, body);
      await tap(tester, '打开已创建文章');
      await until(tester, () => find.text('打开已创建文章？').evaluate().isNotEmpty);
      await tap(tester, '打开已创建文章', filled: true);
      await until(tester, () => openedId == id);
      expect(await tester.runAsync(count), 1);
      expect(bytes.values, isEmpty);
      expect(prefs[oldKey()], original);
      expect(tester.takeException(), isNull);
    },
  );
  androidTestWidgets(
    'skip keeps the exact old draft and opens an empty Markdown creation without SQL',
    (tester) async {
      final original = await seed();
      await mount(tester);
      await tap(tester, '打开新建');
      await until(tester, () => find.text('发现原有新建草稿').evaluate().isNotEmpty);
      await tap(tester, '暂不恢复');
      await ready(tester);
      expect(views.states.last.host.source, isEmpty);
      expect(
        LocalArticleCreationLegacyReceipt.parse(
          prefs[markerKey()]!,
        ).disposition,
        LocalArticleCreationLegacyDisposition.skipped,
      );
      expect(bytes.values, isEmpty);
      expect(await tester.runAsync(count), 0);
      await tester.tap(find.byTooltip('Back'));
      await tester.pump();
      await home(tester);
      expect(result, isFalse);
      expect(bytes.values, isEmpty);
      expect(prefs[oldKey()], original);
      expect(tester.takeException(), isNull);
    },
  );
  androidTestWidgets(
    'kept transferred draft resumes its existing key from readonly archive before one create',
    (tester) async {
      final original = await seed();
      await mount(tester);
      await tap(tester, '打开新建');
      await until(tester, () => find.text('发现原有新建草稿').evaluate().isNotEmpty);
      await tap(tester, '恢复草稿');
      await ready(tester);
      final env = services();
      final before = await env.vault.read();
      env.dispose();
      await tester.tap(find.byTooltip('Back'));
      await tester.pump();
      await until(tester, () => find.text('保留新建草稿？').evaluate().isNotEmpty);
      await tester.pumpAndSettle();
      expect(find.byType(LinearProgressIndicator), findsNothing);
      await tap(tester, '保留并返回');
      await home(tester);
      expect(await tester.runAsync(count), 0);
      await tap(tester, '查看已处理旧稿');
      await until(
        tester,
        () =>
            find.text('继续处理').evaluate().isNotEmpty && views.states.last.ready,
      );
      await tap(tester, '继续处理');
      await until(tester, () => find.text('继续处理新建草稿？').evaluate().isNotEmpty);
      await tap(tester, '继续处理', filled: true);
      await ready(tester);
      final fresh = services();
      final resumed = await fresh.vault.read();
      fresh.dispose();
      expect(resumed!.key, before!.key);
      expect(resumed.edit.document.source, body);
      expect(await tester.runAsync(count), 0);
      await tap(tester, '创建');
      await finishKnownHandoff(tester);
      await home(tester);
      expect(await tester.runAsync(count), 1);
      expect(prefs[oldKey()], original);
      expect(
        LocalArticleCreationLegacyReceipt.parse(
          prefs[markerKey()]!,
        ).creationKey,
        before.key,
      );
      expect(tester.takeException(), isNull);
    },
  );
  androidTestWidgets(
    'cancelling original-draft offer creates neither a binary copy nor a receipt',
    (tester) async {
      final original = await seed();
      await mount(tester);
      await tap(tester, '打开新建');
      await until(tester, () => find.text('发现原有新建草稿').evaluate().isNotEmpty);
      await tap(tester, '返回');
      await home(tester);
      expect(result, isFalse);
      expect(bytes.values, isEmpty);
      expect(prefs.containsKey(markerKey()), isFalse);
      expect(prefs[oldKey()], original);
      expect(await tester.runAsync(count), 0);
    },
  );
  androidTestWidgets(
    'explicit old-draft skip never overwrites an unrelated pending creation',
    (tester) async {
      final original = await seed();
      final env = services();
      final other = LocalArticleCreationRecord(
        scope: env.repository.scope,
        key: newComplexCreationKey(),
        edit: ComplexNoteEdit(
          title: 'other pending',
          document: ComplexEditorDocument.parse(
            ComplexEditorKind.markdown,
            'other source',
          ),
          labels: const [],
        ),
        pending: true,
      );
      await env.vault.write(other);
      env.dispose();
      await mount(tester);
      await tap(tester, '核对旧原稿');
      await until(tester, () => find.text('已有新建草稿').evaluate().isNotEmpty);
      await tap(tester, '暂不恢复');
      await ready(tester);
      expect(views.states.last.widget.readOnly, isTrue);
      expect(views.states.last.host.source, 'other source');
      final check = services();
      final after = await check.vault.read();
      check.dispose();
      expect(after!.sameInput(other), isTrue);
      expect(after.pending, isTrue);
      expect(prefs[oldKey()], original);
      expect(await tester.runAsync(count), 0);
      await tap(tester, '保留并返回');
      await home(tester);
      expect(tester.takeException(), isNull);
    },
  );
  androidTestWidgets(
    'old source change while offer is open invalidates restoration and preserves the new original',
    (tester) async {
      await seed();
      await mount(tester);
      await tap(tester, '打开新建');
      await until(tester, () => find.text('发现原有新建草稿').evaluate().isNotEmpty);
      await legacy.write(
        const Note(
          title: 'changed old input',
          content: 'changed body',
          labels: [],
        ),
      );
      final expected = prefs[oldKey()];
      await tap(tester, '恢复草稿');
      await until(tester, () => find.text('新建草稿无法核对').evaluate().isNotEmpty);
      expect(bytes.values, isEmpty);
      expect(prefs[oldKey()], expected);
      expect(prefs.containsKey(markerKey()), isFalse);
      expect(await tester.runAsync(count), 0);
      await tap(tester, '返回');
      await home(tester);
      expect(tester.takeException(), isNull);
    },
  );
}
