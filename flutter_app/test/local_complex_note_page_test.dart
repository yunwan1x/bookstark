import 'package:bookstark_flutter/features/complex_editors/complex_editor_browser.dart';
import 'dart:async';
import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:bookstark_flutter/core/local_attachments.dart';
import 'package:bookstark_flutter/core/attachments.dart';
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

const _scope =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _initialSource = '{"elements":[],"future":"baseline"}';
const _editedSource = '{"elements":[],"future":"edited"}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'save is disabled until host ready and after surface retirement',
    (tester) async {
      final rig = _Rig();
      final bridge = _Bridge(tester, rig);
      await bridge.mount(hostReady: false);
      IconButton saveButton() => tester.widget<IconButton>(
        find.byWidgetPredicate(
          (widget) => widget is IconButton && widget.tooltip == 'Save',
        ),
      );
      expect(saveButton().onPressed, isNull);
      expect(rig.repository.saveCount, 0);
      await bridge.ready(bridge.editors.values.last);
      expect(saveButton().onPressed, isNotNull);
      await HtmlBrowserSession.closeActive();
      await tester.pumpAndSettle();
      expect(saveButton().onPressed, isNull);
      expect(rig.repository.saveCount, 0);
      expect(tester.takeException(), isNull);
      await bridge.close();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'durable local checkpoint remains unsaved and leave can be cancelled',
    (tester) async {
      final rig = _Rig();
      await rig.controller.checkpoint(rig.edit);
      final bridge = _Bridge(tester, rig);
      await bridge.mount();

      expect(find.text('Local · Unsaved'), findsOneWidget);
      expect(rig.controller.draftDurable, isTrue);
      expect(rig.repository.saveCount, 0);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Save before leaving?'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(find.byType(LocalComplexNotePage), findsOneWidget);
      expect(find.text('Local · Unsaved'), findsOneWidget);
      expect(rig.repository.saveCount, 0);
      expect(tester.takeException(), isNull);

      await bridge.close();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets('unknown save result stays open and departure never resubmits', (
    tester,
  ) async {
    final rig = _Rig()..repository.loseReceiptAfterCommit = true;
    final bridge = _Bridge(tester, rig);
    await bridge.mount();
    await bridge.edit(_editedSource);

    await tester.tap(find.byTooltip('Save'));
    await _pumpUntil(tester, () => rig.controller.requiresReview);
    await _pumpUntil(
      tester,
      () => find.text('Save needs verification').evaluate().isNotEmpty,
    );
    expect(find.text('Review'), findsOneWidget);
    expect(rig.repository.saveCount, 1);
    expect(rig.vaultStore.removeCount, 0);
    expect(find.byType(LocalComplexNotePage), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(LocalComplexNotePage), findsOneWidget);
    expect(
      find.text('Review the save or finish recovery cleanup first.'),
      findsOneWidget,
    );
    expect(rig.repository.saveCount, 1);
    expect(rig.vaultStore.removeCount, 0);
    expect(tester.takeException(), isNull);

    await bridge.close();
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets(
    'background retirement waits for frozen save durability before destroying the editor',
    (tester) async {
      final rig = _Rig()..repository.blockSave = true;
      final bridge = _Bridge(tester, rig);
      await bridge.mount();

      // Simulate an engine edit whose asynchronous dirty callback has not arrived.
      bridge.editors.values.last.source = _editedSource;
      await tester.tap(find.byTooltip('Save'));
      await _pumpUntil(tester, () => rig.repository.saveEntered.isCompleted);
      expect(rig.repository.saveCount, 1);

      try {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await _pumpUntil(
          tester,
          () => bridge.sessionCalls.any((call) => call.method == 'close'),
        );
        final pending = await rig.controller.vault.read(rig.baseline.id);
        expect(pending, isNotNull);
        expect(pending!.pending, isTrue);
        expect(pending.edit.document.source, _editedSource);
        expect(rig.repository.saveCount, 1);
      } finally {
        if (!rig.repository.releaseSave.isCompleted) {
          rig.repository.releaseSave.complete();
        }
      }

      await _pumpUntil(
        tester,
        () => rig.repository.current.document.source == _editedSource,
      );
      expect(rig.repository.saveCount, 1);
      expect(tester.takeException(), isNull);
      await bridge.close();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets('confirmed commit cleanup retry removes recovery only', (
    tester,
  ) async {
    final rig = _Rig()..vaultStore.removeFailures = 1;
    await rig.controller.checkpoint(rig.edit);
    expect(await rig.controller.save(rig.edit), isNotNull);
    expect(rig.controller.phase, ComplexSavePhase.committedCleanupFailed);
    expect(rig.repository.saveCount, 1);
    expect(rig.vaultStore.removeCount, 1);

    final bridge = _Bridge(tester, rig);
    await bridge.mount();
    expect(find.text('Retry cleanup'), findsOneWidget);

    await tester.tap(find.text('Retry cleanup'));
    await _pumpUntil(
      tester,
      () => rig.controller.phase == ComplexSavePhase.ready,
    );
    expect(rig.repository.saveCount, 1);
    expect(rig.vaultStore.removeCount, 2);
    expect(rig.vaultStore.values, isEmpty);
    expect(find.byType(LocalComplexNotePage), findsOneWidget);
    expect(find.text('Local · Saved'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await bridge.close();
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets(
    'ordinary local complex note information checkpoints exact source and metadata then explicitly saves',
    (tester) async {
      final rig = _Rig();
      final bridge = _Bridge(tester, rig);
      await bridge.mount();
      final engine = bridge.editors.values.last;
      engine.source = _editedSource;
      await tester.tap(find.byTooltip('Note information'));
      await tester.pumpAndSettle();
      expect(find.text('Note title'), findsOneWidget);
      expect(rig.controller.edit.document.source, _editedSource);
      await tester.enterText(
        find.byType(TextField).at(0),
        'Updated drawing note',
      );
      await tester.enterText(find.byType(TextField).at(1), 'comma,label');
      await tester.tap(find.text('Add'));
      await tester.pump();
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(rig.controller.edit.title, 'Updated drawing note');
      expect(rig.controller.edit.labels, ['baseline', 'comma,label']);
      expect(rig.controller.edit.document.source, _editedSource);
      expect(rig.controller.draftDurable, isTrue);
      expect(rig.repository.saveCount, 0);
      expect(identical(bridge.editors.values.last, engine), isTrue);
      await tester.tap(find.byTooltip('Save'));
      await _pumpUntil(
        tester,
        () =>
            rig.repository.saveCount == 1 &&
            rig.controller.phase == ComplexSavePhase.ready,
      );
      expect(rig.repository.current.title, 'Updated drawing note');
      expect(rig.repository.current.labels, ['baseline', 'comma,label']);
      expect(rig.repository.current.document.source, _editedSource);
      expect(tester.takeException(), isNull);
      await bridge.close();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'article metadata checkpoints the latest body without SQL or WebView reload, then saves all fields',
    (tester) async {
      final rig = _Rig(markdown: true);
      final bridge = _Bridge(tester, rig);
      await bridge.mount();
      const source = '\ufeff# latest body\r\ncomma,label survives\r\n';
      final engine = bridge.editors.values.last;
      engine.source = source; // Input callback is deliberately still in flight.
      await tester.tap(find.byTooltip('Article information'));
      await tester.pumpAndSettle();
      expect(find.text('Article title'), findsOneWidget);
      expect(rig.controller.edit.document.source, source);
      await tester.enterText(find.byType(TextField).at(0), 'Updated article');
      await tester.enterText(find.byType(TextField).at(1), 'comma,label');
      await tester.tap(find.text('Add'));
      await tester.pump();
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(rig.controller.edit.title, 'Updated article');
      expect(rig.controller.edit.labels, ['baseline', 'comma,label']);
      expect(rig.controller.edit.document.source, source);
      expect(rig.controller.draftDurable, isTrue);
      expect(rig.repository.saveCount, 0);
      expect(bridge.editors.length, 1);
      expect(identical(bridge.editors.values.last, engine), isTrue);
      expect(engine.source, source);
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await _pumpUntil(
        tester,
        () =>
            rig.repository.saveCount == 1 &&
            rig.controller.phase == ComplexSavePhase.ready,
      );
      expect(rig.repository.current.title, 'Updated article');
      expect(rig.repository.current.labels, ['baseline', 'comma,label']);
      expect(rig.repository.current.document.source, source);
      expect(tester.takeException(), isNull);
      await bridge.close();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'article metadata cancellation and immediate disposal keep metadata and do not leave controllers active',
    (tester) async {
      final rig = _Rig(markdown: true);
      final bridge = _Bridge(tester, rig);
      await bridge.mount();
      await tester.tap(find.byTooltip('Article information'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Do not apply');
      await tester.tap(find.text('Cancel'));
      // Dispose during the dialog closing animation, before draining timers.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(rig.repository.current.title, 'Local article');
      expect(rig.repository.saveCount, 0);
      expect(tester.takeException(), isNull);
      await bridge.close();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'failed body checkpoint blocks metadata dialog and retains the unsaved source',
    (tester) async {
      final rig = _Rig(markdown: true)..vaultStore.writeFailures = 1;
      final bridge = _Bridge(tester, rig);
      await bridge.mount();
      const source = '# retain this unconfirmed body';
      bridge.editors.values.last.source = source;
      await tester.tap(find.byTooltip('Article information'));
      await tester.pumpAndSettle();
      expect(find.text('Article title'), findsNothing);
      expect(
        find.text('Draft durability is unconfirmed. Keep this page open.'),
        findsOneWidget,
      );
      expect(rig.controller.phase, ComplexSavePhase.draftFailed);
      expect(rig.repository.saveCount, 0);
      expect(bridge.editors.values.last.source, source);
      expect(tester.takeException(), isNull);
      await bridge.close();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
  testWidgets(
    'retired article surface ignores a still-open metadata dialog result',
    (tester) async {
      final rig = _Rig(markdown: true);
      final bridge = _Bridge(tester, rig);
      await bridge.mount();
      const source = '# body before retirement';
      bridge.editors.values.last.source = source;
      await tester.tap(find.byTooltip('Article information'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).first,
        'Obsolete dialog title',
      );
      await HtmlBrowserSession.closeActive();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(rig.controller.edit.title, 'Local article');
      expect(rig.controller.edit.document.source, source);
      expect(rig.controller.draftDurable, isTrue);
      expect(rig.repository.saveCount, 0);
      expect(tester.takeException(), isNull);
      await bridge.close();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
  testWidgets(
    'attachment picker cancellation retires first and never saves SQL',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final rig = _Rig(markdown: true);
      final files = _FakeImports();
      final entered = Completer<void>(), finish = Completer<XFile?>();
      late _Bridge bridge;
      bridge = _Bridge(
        tester,
        rig,
        attachments: files,
        pickAttachment: () {
          expect(bridge.editors.values.last.retired, isTrue);
          entered.complete();
          return finish.future;
        },
      );
      await bridge.mount();
      await tester.tap(find.byTooltip('Insert attachment'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Import from device'));
      await _pumpUntil(tester, () => entered.isCompleted);
      expect(rig.repository.saveCount, 0);
      expect(files.imports, 0);
      finish.complete(null);
      await _pumpUntil(tester, () => bridge.editors.length == 2);
      await bridge.ready(bridge.editors.values.last);
      expect(rig.controller.edit.document.same(rig.baseline.document), isTrue);
      expect(files.imports, 0);
      expect(rig.repository.saveCount, 0);
      expect(tester.takeException(), isNull);
      await bridge.close();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'import restores exact selected source into a fresh runtime without SQL save',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final rig = _Rig(markdown: true);
      final files = _FakeImports();
      final entered = Completer<void>(), finish = Completer<XFile?>();
      late _Bridge bridge;
      bridge = _Bridge(
        tester,
        rig,
        attachments: files,
        pickAttachment: () {
          expect(bridge.editors.values.last.retired, isTrue);
          entered.complete();
          return finish.future;
        },
      );
      await bridge.mount();
      bridge.editors.values.last.selection = 5;
      await tester.tap(find.byTooltip('Insert attachment'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Import from device'));
      await _pumpUntil(tester, () => entered.isCompleted);
      finish.complete(
        XFile.fromData(
          Uint8List.fromList([1, 2, 3]),
          name: 'fixture.png',
          path: 'fixture.png',
        ),
      );
      await _pumpUntil(tester, () => bridge.editors.length == 2);
      await bridge.ready(bridge.editors.values.last);
      final markup = markdownAttachment(
        'fixture.png',
        files.importedURI,
        image: true,
      );
      final expected =
          _initialSource.substring(0, 5) + markup + _initialSource.substring(5);
      expect(rig.controller.edit.document.source, expected);
      expect(bridge.editors.values.last.source, expected);
      expect(rig.controller.draftDurable, isTrue);
      expect(rig.repository.saveCount, 0);
      expect(files.imports, 1);
      expect(tester.takeException(), isNull);
      await bridge.close();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'late picker result retains the file and link instead of replacing changed source',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final rig = _Rig(markdown: true);
      final files = _FakeImports();
      final entered = Completer<void>(), finish = Completer<XFile?>();
      final bridge = _Bridge(
        tester,
        rig,
        attachments: files,
        pickAttachment: () {
          entered.complete();
          return finish.future;
        },
      );
      await bridge.mount();
      await tester.tap(find.byTooltip('Insert attachment'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Import from device'));
      await _pumpUntil(tester, () => entered.isCompleted);
      await rig.controller.checkpoint(rig.edit);
      finish.complete(
        XFile.fromData(
          Uint8List.fromList([1]),
          name: 'fixture.png',
          path: 'fixture.png',
        ),
      );
      await _pumpUntil(tester, () => bridge.editors.length == 2);
      await bridge.ready(bridge.editors.values.last);
      expect(rig.controller.edit.document.source, _editedSource);
      expect(files.imports, 1);
      expect(rig.repository.saveCount, 0);
      expect(find.text('Copy attachment link'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await bridge.close();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'unconfirmed draft prevents opening the system attachment picker',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final rig = _Rig(markdown: true);
      final files = _FakeImports();
      var pickerCalls = 0;
      final bridge = _Bridge(
        tester,
        rig,
        attachments: files,
        pickAttachment: () async {
          pickerCalls++;
          return null;
        },
      );
      await bridge.mount();
      await bridge.edit(_editedSource);
      rig.vaultStore.writeFailures = 1;
      await tester.tap(find.byTooltip('Insert attachment'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Import from device'));
      await _pumpUntil(
        tester,
        () => find
            .textContaining('Attachment handling is incomplete.')
            .evaluate()
            .isNotEmpty,
      );
      expect(pickerCalls, 0);
      expect(files.imports, 0);
      expect(rig.repository.saveCount, 0);
      expect(rig.controller.edit.document.source, _editedSource);
      expect(bridge.editors.values.last.retired, isFalse);
      expect(tester.takeException(), isNull);
      await bridge.close();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
  testWidgets(
    'picker return while backgrounded waits for visible lifecycle before recreating the runtime',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final rig = _Rig(markdown: true);
      final files = _FakeImports();
      final entered = Completer<void>(), finish = Completer<XFile?>();
      final bridge = _Bridge(
        tester,
        rig,
        attachments: files,
        pickAttachment: () {
          entered.complete();
          return finish.future;
        },
      );
      await bridge.mount();
      await tester.tap(find.byTooltip('Insert attachment'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Import from device'));
      await _pumpUntil(tester, () => entered.isCompleted);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      finish.complete(
        XFile.fromData(Uint8List.fromList([1]), path: 'fixture.png'),
      );
      await _pumpUntil(
        tester,
        () => files.imports == 1 && rig.controller.draftDurable,
      );
      await tester.pump();
      expect(bridge.editors.length, 1);
      expect(bridge.editors.values.single.retired, isTrue);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _pumpUntil(tester, () => bridge.editors.length == 2);
      await bridge.ready(bridge.editors.values.last);
      expect(rig.repository.saveCount, 0);
      expect(tester.takeException(), isNull);
      await bridge.close();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'disposed article ignores a late picker result before importing bytes',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final rig = _Rig(markdown: true);
      final files = _FakeImports();
      final entered = Completer<void>(), finish = Completer<XFile?>();
      final bridge = _Bridge(
        tester,
        rig,
        attachments: files,
        pickAttachment: () {
          entered.complete();
          return finish.future;
        },
      );
      await bridge.mount();
      await tester.tap(find.byTooltip('Insert attachment'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Import from device'));
      await _pumpUntil(tester, () => entered.isCompleted);
      await bridge.close();
      finish.complete(
        XFile.fromData(Uint8List.fromList([1]), path: 'fixture.png'),
      );
      await tester.pump();
      await tester.pump();
      expect(files.imports, 0);
      expect(rig.repository.saveCount, 0);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
  testWidgets(
    'local article attachment shell supports 320dp large text and keyboard without recreating the view',
    (tester) async {
      tester.view.devicePixelRatio = 2;
      tester.view.physicalSize = const Size(640, 1280);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetViewInsets);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final rig = _Rig(markdown: true);
      final bridge = _Bridge(tester, rig, attachments: _FakeImports());
      await bridge.mount();
      expect(tester.takeException(), isNull);
      final original = bridge.editors.values.single;
      tester.view.viewInsets = const FakeViewPadding(bottom: 500);
      await tester.pump();
      expect(identical(bridge.editors.values.single, original), isTrue);
      expect(tester.takeException(), isNull);
      await bridge.close();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
  testWidgets(
    '320dp 200 percent attachment error retains a usable editor and reachable retry',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      tester.view.devicePixelRatio = 2;
      tester.view.physicalSize = const Size(640, 1280);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final rig = _Rig(markdown: true);
      final bridge = _Bridge(
        tester,
        rig,
        attachments: _FakeImports(),
        pickAttachment: () async =>
            throw StateError('Synthetic provider failure'),
      );
      await bridge.mount();
      try {
        await tester.tap(find.byTooltip('Insert attachment'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Import from device'));
        await _pumpUntil(tester, () => bridge.editors.length == 2);
        await bridge.ready(bridge.editors.values.last);
        await bridge._incoming(
          bridge.editors.values.last,
          'localImageFailure',
          {'lease': bridge.editors.values.last.lease},
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(
          tester.getSize(find.byType(ComplexEditorBrowser)).height,
          greaterThanOrEqualTo(140),
        );
        await tester.ensureVisible(find.text('Retry'));
        expect(tester.takeException(), isNull);
      } finally {
        await bridge.close();
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
  testWidgets(
    '320dp 200 percent existing attachment keeps filename and subtitle inside its card',
    (tester) async {
      tester.view.devicePixelRatio = 2;
      tester.view.physicalSize = const Size(640, 1280);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final id = List.filled(32, 'e').join();
      final rig = _Rig(
        markdown: true,
        source:
            '# Reading\n\n![Missing](<bookstark-attachment:///ID/missing.png>)'
                .replaceFirst('ID', id),
      );
      final bridge = _Bridge(tester, rig, attachments: _FakeImports());
      await bridge.mount();
      try {
        final subtitle = find.text('Local attachment');
        expect(subtitle, findsOneWidget);
        final card = find
            .ancestor(of: subtitle, matching: find.byType(Card))
            .first;
        final cardRect = tester.getRect(card);
        final textRect = tester.getRect(subtitle);
        expect(textRect.top, greaterThanOrEqualTo(cardRect.top));
        expect(
          textRect.bottom,
          lessThanOrEqualTo(cardRect.bottom),
          reason:
              'Large-text attachment metadata must remain within the visible card',
        );
        expect(tester.takeException(), isNull);
      } finally {
        await bridge.close();
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
  _Bridge(this.tester, this.rig, {this.attachments, this.pickAttachment});
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

class _FakeImports extends LocalAttachments {
  _FakeImports() : super(Directory('/unused-bookstark-test-attachments'));
  int imports = 0;
  final importedURI = Uri.parse(
    'bookstark-attachment:///${List.filled(32, 'b').join()}/fixture.png',
  );
  @override
  Future<Attachment> add(
    XFile file, {
    bool protected = false,
    AttachmentCancellation? cancellation,
  }) async {
    cancellation?.check();
    imports++;
    return Attachment(uri: importedURI, name: file.name, image: true, size: 3);
  }
}
