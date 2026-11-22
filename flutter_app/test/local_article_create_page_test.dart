import 'dart:async';
import 'dart:ffi' show DynamicLibrary;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/open.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/local_article_creation_controller.dart';
import 'package:bookstark_flutter/core/local_article_creation_record.dart';
import 'package:bookstark_flutter/core/local_complex_notes_repository.dart';
import 'package:bookstark_flutter/core/local_store.dart';
import 'package:bookstark_flutter/features/complex_editors/article_metadata_dialog.dart';
import 'package:bookstark_flutter/features/complex_editors/local_article_create_page.dart';
import 'support/article_creation_storage.dart';
import 'support/article_creation_views.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    if (Platform.isLinux) {
      open.overrideFor(
        OperatingSystem.linux,
        () => DynamicLibrary.open('libsqlite3.so.0'),
      );
    }
  });
  late Directory directory;
  late LocalStore store;
  late LocalComplexNotesRepository actual;
  late LostReplySQL sql;
  late OwnedBytes bytes;
  late LocalArticleCreationVault vault;
  late OwnedArticleCreationViews views;
  LocalArticleCreationController? owner;
  var disposed = false;
  const source = '\ufeff\ufeff# 原稿\r\n- 原字节\r\n';
  ComplexNoteEdit input({String title = 'Draft title'}) => ComplexNoteEdit(
    title: title,
    document: ComplexEditorDocument.parse(ComplexEditorKind.markdown, source),
    labels: const ['old,label'],
  );
  LocalArticleCreationController create({LocalArticleCreationRecord? record}) {
    disposed = false;
    return owner = LocalArticleCreationController(
      repository: sql,
      vault: vault,
      record: record,
    );
  }

  Future<int> count() async =>
      (await (await store.database).query('notes')).length;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('article-create-ui-');
    store = LocalStore(
      path: '${directory.path}/notes.db',
      factory: databaseFactoryFfiNoIsolate,
    );
    await store.database;
    actual = LocalComplexNotesRepository(
      store,
      kind: ComplexEditorKind.markdown,
      collection: 'article',
    );
    sql = LostReplySQL(actual);
    bytes = OwnedBytes();
    views = OwnedArticleCreationViews(bytes.events);
    vault = LocalArticleCreationVault(
      scope: actual.scope,
      store: bytes,
      maintenance: store.maintenance,
    );
    owner = null;
    disposed = false;
  });
  tearDown(() async {
    if (owner != null && !disposed) owner!.dispose();
    actual.dispose();
    await store.close();
    await directory.delete(recursive: true);
  });
  Future<void> until(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 120 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(done(), isTrue);
  }

  Future<void> mount(
    WidgetTester tester,
    LocalArticleCreationController value, {
    Size? size,
    double scale = 1,
  }) async {
    if (size != null) {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
    }
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: TextButton(
                onPressed: () {
                  Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (_) {
                        return MediaQuery(
                          data: MediaQuery.of(
                            context,
                          ).copyWith(textScaler: TextScaler.linear(scale)),
                          child: LocalArticleCreatePage(
                            controller: value,
                            sourceBuilder: views.editor,
                            reviewBuilder: views.review,
                            onDisposed: () => disposed = true,
                          ),
                        );
                      },
                    ),
                  );
                },
                child: const Text('入口'),
              ),
            );
          },
        ),
      ),
    );

    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
    await tester.tap(find.text('入口'));
    await tester.pumpAndSettle();
    await until(
      tester,
      () => views.states.isNotEmpty && views.states.last.ready,
    );
  }

  Future<void> tapVisible(WidgetTester tester, String label) async {
    final target = find.text(label);
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target.hitTestable());
    await tester.pump();
  }

  testWidgets(
    'latest WebView body is checkpointed before metadata and one explicit create saves all fields',
    (tester) async {
      final value = create();
      await mount(tester, value);
      expect(await tester.runAsync(count), 0);
      final body = views.states.last;
      body.enter(source);
      await tester.pump();
      await tapVisible(tester, '点击填写标题');
      expect(find.byType(ArticleMetadataDialog), findsOneWidget);
      expect((await vault.read())!.edit.document.source, source);
      expect(await tester.runAsync(count), 0);
      await tester.enterText(
        find.byType(TextField).first,
        'Created UI article',
      );
      await tester.enterText(find.byType(TextField).at(1), 'android,label');
      await tester.tap(find.text('添加'));
      await tester.pump();
      await tester.tap(find.text('应用'));
      await tester.pumpAndSettle();
      expect(views.states, hasLength(1));
      expect(body.host.source, source);
      expect(find.text('android,label'), findsOneWidget);
      expect(await tester.runAsync(count), 0);
      await tapVisible(tester, '创建');
      await until(tester, () => disposed);
      expect(
        views.states,
        hasLength(1),
        reason:
            'A successful create retires its existing browser without mounting another editor',
      );
      expect(sql.creates, 1);
      expect(await tester.runAsync(count), 1);
      final rows = await tester.runAsync(
        () async => (await store.database).query('notes'),
      );
      final saved = await tester.runAsync(
        () => actual.read(rows!.single['id'] as int),
      );
      expect(saved!.title, 'Created UI article');
      expect(saved.document.source, source);
      expect(saved.labels, ['android,label']);
      expect(bytes.values, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'actual committed lost reply needs a checked readonly snapshot and closes its lease before adoption cleanup',
    (tester) async {
      final value = create()..edit(input());
      sql.dropAfterCommit = true;
      await value.save();
      sql.dropAfterCommit = false;
      await mount(tester, value);
      await tapVisible(tester, '核对结果');
      await until(
        tester,
        () =>
            value.phase == LocalArticleCreationPhase.review &&
            views.states.last.ready,
      );
      final adopt = find.widgetWithText(FilledButton, '采用此结果');
      expect(tester.widget<FilledButton>(adopt).onPressed, isNull);
      await until(
        tester,
        () =>
            find.byType(CheckboxListTile).evaluate().isNotEmpty &&
            tester
                    .widget<CheckboxListTile>(find.byType(CheckboxListTile))
                    .onChanged !=
                null &&
            views.states.last.ready &&
            !views.states.last.widget.lease.retired,
      );
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CheckboxListTile).hitTestable());
      await tester.pump();
      expect(value.reviewed, isTrue);
      final gate = Completer<void>();
      views.states.last.closeGate = gate;
      final eventStart = bytes.events.length;
      await tapVisible(tester, '采用此结果');
      await tester.pump();
      expect(bytes.values, hasLength(1));
      expect(value.phase, LocalArticleCreationPhase.review);
      gate.complete();
      await until(tester, () => disposed);
      expect(sql.creates, 1);
      expect(await tester.runAsync(count), 1);
      expect(
        bytes.events.indexOf('view-closed', eventStart),
        lessThan(bytes.events.indexOf('draft-delete', eventStart)),
      );
      expect(bytes.values, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'confirmed absence leaves retry and editing disabled until explicit review',
    (tester) async {
      final record = LocalArticleCreationRecord(
        scope: actual.scope,
        key: newComplexCreationKey(),
        edit: input(),
        pending: true,
      );
      await vault.write(record);
      final value = create(record: record);
      await mount(tester, value);
      await tapVisible(tester, '核对结果');
      await until(
        tester,
        () => value.confirmedAbsent && views.states.last.ready,
      );
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '重试创建'))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '返回编辑'))
            .onPressed,
        isNull,
      );
      await until(
        tester,
        () =>
            find.byType(CheckboxListTile).evaluate().isNotEmpty &&
            tester
                    .widget<CheckboxListTile>(find.byType(CheckboxListTile))
                    .onChanged !=
                null &&
            views.states.last.ready &&
            !views.states.last.widget.lease.retired,
      );
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CheckboxListTile).hitTestable());
      await tester.pump();
      await tapVisible(tester, '返回编辑');
      await until(
        tester,
        () =>
            value.canEdit &&
            views.states.last.ready &&
            find.text('创建').evaluate().isNotEmpty,
      );
      expect(sql.creates, 0);
      expect(await tester.runAsync(count), 0);
      expect((await vault.read())!.pending, isFalse);
      expect(views.states.last.host.source, source);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'known cleanup failure offers storage retry and never another create',
    (tester) async {
      bytes.failRemove = true;
      final value = create()..edit(input());
      await value.save();
      await mount(tester, value);
      expect(find.text('已创建，草稿清理待重试'), findsOneWidget);
      expect(find.text('创建'), findsNothing);
      bytes.failRemove = false;
      await tapVisible(tester, '重试清理');
      await until(tester, () => disposed);
      expect(sql.creates, 1);
      expect(await tester.runAsync(count), 1);
      expect(bytes.values, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'source capture failure blocks metadata dialog and SQL until explicit retry',
    (tester) async {
      final value = create();
      await mount(tester, value);
      final body = views.states.last;
      body.enter(source);
      body.host.failSnapshot = true;
      await tester.pump();
      await tapVisible(tester, '点击填写标题');
      expect(find.byType(ArticleMetadataDialog), findsNothing);
      expect(await tester.runAsync(count), 0);
      expect(sql.creates, 0);
      expect(body.host.source, source);
      body.host.failSnapshot = false;
      await tapVisible(tester, '点击填写标题');
      expect(find.byType(ArticleMetadataDialog), findsOneWidget);
      expect((await vault.read())!.edit.document.source, source);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  for (final phase in ['editing', 'absent', 'unavailable']) {
    testWidgets(
      '320dp 200 percent $phase layout keeps actions reachable without overflow',
      (tester) async {
        late LocalArticleCreationController value;
        if (phase == 'editing') {
          value = create()..edit(input());
        } else if (phase == 'absent') {
          final record = LocalArticleCreationRecord(
            scope: actual.scope,
            key: newComplexCreationKey(),
            edit: input(),
            pending: true,
          );
          await vault.write(record);
          value = create(record: record);
          await value.inspect();
        } else {
          value = create()..edit(input());
          sql.dropAfterCommit = true;
          await value.save();
          sql.dropAfterCommit = false;
          final found = await actual.findCreation(value.record.key);
          await (await store.database).delete(
            'notes',
            where: 'id = ?',
            whereArgs: [found!.noteId],
          );
          await value.inspect();
        }
        await mount(tester, value, size: const Size(320, 640), scale: 2);
        expect(tester.takeException(), isNull);
        if (phase != 'editing') {
          await tester.ensureVisible(find.text('保留并返回'));
          await tester.pumpAndSettle();
          expect(find.text('保留并返回').hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
      },
    );
  }
}
