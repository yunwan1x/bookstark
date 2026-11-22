import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/complex_recovery_vault.dart';
import 'package:bookstark_flutter/core/local_complex_editor_controller.dart';
import 'package:bookstark_flutter/core/complex_source_io_controller.dart';
import 'complex_source_io_test.dart' as fixture;

void main() {
  test(
    'cancel then fresh explicit import and export can succeed with real controller',
    () async {
      final bridge = fixture.Bridge(), owner = await bridge.owner();
      final repository = fixture.Repository(), bytes = fixture.BytesStore();
      final editor = LocalComplexEditorController(
        repository: repository,
        vault: ComplexRecoveryVault(
          scope: repository.scope,
          collection: 'note',
          kind: repository.kind,
          store: bytes,
        ),
        baseline: repository.baseline,
      );
      addTearDown(editor.dispose);
      final io = ComplexSourceIoController(
        editor: editor,
        owner: owner,
        capture: () async => editor.edit.document,
        prepareNative: () async => bridge.client(owner),
        replaceSurface: () async {},
        isCurrent: () => true,
        onDurableHandoff: (_) {},
      );
      addTearDown(io.dispose);
      await io.cancel();
      await io.importSource(confirm: (_) async => true);
      expect(io.phase, ComplexSourceIoPhase.completed);
      expect(editor.edit.document.source, '<p>incoming 😀</p>');
      await io.cancel();
      await io.exportSource(name: 'source.html');
      expect(io.phase, ComplexSourceIoPhase.completed);
      expect(repository.saves, 0);
    },
  );
  test(
    'a busy second explicit entry cannot clear cancellation of the active operation',
    () async {
      final bridge = fixture.Bridge(), owner = await bridge.owner();
      final repository = fixture.Repository(), bytes = fixture.BytesStore();
      final editor = LocalComplexEditorController(
        repository: repository,
        vault: ComplexRecoveryVault(
          scope: repository.scope,
          collection: 'note',
          kind: repository.kind,
          store: bytes,
        ),
        baseline: repository.baseline,
      );
      addTearDown(editor.dispose);
      final capture = Completer<ComplexEditorDocument>();
      final io = ComplexSourceIoController(
        editor: editor,
        owner: owner,
        capture: () => capture.future,
        prepareNative: () async => bridge.client(owner),
        replaceSurface: () async {},
        isCurrent: () => true,
        onDurableHandoff: (_) {},
      );
      addTearDown(io.dispose);
      final first = io.importSource(confirm: (_) async => true);
      await io.cancel();
      await io.exportSource(name: 'second.html');
      capture.complete(repository.baseline.document);
      await first;
      expect(io.phase, ComplexSourceIoPhase.cancelled);
      expect(bridge.calls, isNot(contains('pickImport')));
      expect(bridge.calls, isNot(contains('beginExport')));
      expect(editor.edit.document.source, repository.baseline.document.source);
      expect(repository.saves, 0);
    },
  );
}
