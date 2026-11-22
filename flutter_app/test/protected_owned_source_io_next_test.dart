import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/complex_recovery_vault.dart';
import 'package:bookstark_flutter/core/local_complex_editor_controller.dart';
import 'package:bookstark_flutter/core/local_complex_notes_repository.dart';
import 'package:bookstark_flutter/core/protected_complex_memory_store.dart';
import 'package:bookstark_flutter/core/protected_owned_complex_journal.dart';
import 'package:bookstark_flutter/core/complex_source_io_controller.dart';
import 'complex_source_io_test.dart' as support;

class Drawing extends support.Repository {
  @override
  ComplexEditorKind get kind => ComplexEditorKind.drawing;
  @override
  ComplexNote get baseline => _baseline;
  late final _baseline = ComplexNote(
    scope: scope,
    id: 9,
    collection: collection,
    title: 'Protected drawing',
    version: 7,
    labels: ['exact'],
    document: ComplexEditorDocument.parse(kind, '{"elements":[]}'),
  );
}

void main() {
  for (final allowed in [false, true]) {
    test(
      'protected sourceIO memory handoff consent $allowed never persists body or SQL',
      () async {
        final nativeMetadata = <String, String>{};
        final journal = ProtectedOwnedComplexJournal(
          scope: List.filled(64, 'a').join(),
          ownerTag: List.filled(64, 'e').join(),
          isCurrent: () => true,
          readValue: (k) async => nativeMetadata[k],
          writeValue: (k, v) async {
            nativeMetadata[k] = v;
          },
          deleteValue: (k) async {
            nativeMetadata.remove(k);
          },
          flush: () async {},
        );
        final memory = ProtectedComplexMemoryStore(journal), repo = Drawing();
        final editor = LocalComplexEditorController(
          repository: repo,
          ephemeralDrafts: true,
          vault: ComplexRecoveryVault(
            scope: repo.scope,
            collection: repo.collection,
            kind: repo.kind,
            store: memory,
          ),
          baseline: repo.baseline,
        );
        final bridge = support.Bridge()
          ..source = utf8.encode('{"elements":[],"appState":{}}');
        final scope = await bridge.owner();
        var grants = 0;
        final io = ComplexSourceIoController(
          editor: editor,
          owner: scope,
          allowMemoryOnlyHandoff: allowed,
          capture: () async => repo.baseline.document,
          prepareNative: () async {
            grants++;
            return bridge.client(scope);
          },
          replaceSurface: () async {},
          isCurrent: () => true,
          onDurableHandoff: (_) {},
        );
        try {
          if (!allowed) {
            await expectLater(
              io.importSource(confirm: (_) async => true),
              throwsStateError,
            );
            expect(grants, 0);
            expect(bridge.calls, isNot(contains('pickImport')));
          } else {
            await io.importSource(confirm: (_) async => true);
            expect(io.phase, ComplexSourceIoPhase.completed);
            expect(editor.edit.document.source, utf8.decode(bridge.source));
            expect(editor.draftDurable, isFalse);
            expect(grants, 1);
          }
          expect(repo.saves, 0);
          expect(nativeMetadata, isEmpty);
          expect(editor.baseline.id, 9);
        } finally {
          io.dispose();
          editor.dispose();
          memory.close();
          journal.retire();
          await journal.drain();
          await scope.retire();
        }
      },
    );
  }
}
