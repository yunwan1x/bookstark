import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/complex_recovery_vault.dart';
import 'package:bookstark_flutter/core/local_complex_editor_controller.dart';
import 'package:bookstark_flutter/core/native_complex_source_io.dart';
import 'package:bookstark_flutter/core/complex_source_io_controller.dart';
import 'complex_source_io_test.dart' as support;

class ArticleRepository extends support.Repository {
  @override
  String get collection => 'article';
  @override
  ComplexEditorKind get kind => ComplexEditorKind.markdown;
}

void main() {
  for (final approved in [false, true]) {
    test(
      'existing MD article import confirmation $approved checkpoints only same draft',
      () async {
        const incoming =
            '\ufeff# Incoming\r\n![image](attachment://unchanged)\r\n';
        final bridge = support.Bridge()..source = utf8.encode(incoming);
        final scope = await bridge.owner(),
            repo = ArticleRepository(),
            bytes = support.BytesStore();
        final editor = LocalComplexEditorController(
          repository: repo,
          vault: ComplexRecoveryVault(
            scope: repo.scope,
            collection: repo.collection,
            kind: repo.kind,
            store: bytes,
          ),
          baseline: repo.baseline,
        );
        var replacements = 0, grants = 0;
        final original = ComplexEditorDocument.parse(
          ComplexEditorKind.markdown,
          '# Unsaved original\r\n',
        );
        final io = ComplexSourceIoController(
          editor: editor,
          owner: scope,
          capture: () async => original,
          prepareNative: () async {
            grants++;
            return NativeComplexSourceIo(
              owner: scope,
              lease: 'owned-md-live',
              generation: 7,
              allowMarkdown: true,
              invoke: bridge.invoke,
            );
          },
          replaceSurface: () async {
            replacements++;
          },
          isCurrent: () => bridge.current,
          onDurableHandoff: (_) {},
        );
        try {
          await io.importSource(
            confirm: (file) async {
              expect(file.document.source, incoming);
              expect(editor.edit.document.source, original.source);
              expect(editor.draftDurable, isTrue);
              return approved;
            },
          );
          expect(grants, 1);
          expect(repo.saves, 0);
          expect(editor.baseline.id, 9);
          expect(editor.baseline.labels, ['exact']);
          expect(
            editor.edit.document.source,
            approved ? incoming : original.source,
          );
          expect(editor.draftDurable, isTrue);
          expect(replacements, 1);
        } finally {
          io.dispose();
          editor.dispose();
          await scope.retire();
        }
      },
    );
  }
  test(
    'existing MD failed checkpoint opens zero native grants or pickers',
    () async {
      final bridge = support.Bridge(),
          scope = await bridge.owner(),
          repo = ArticleRepository();
      final bytes = support.BytesStore()..fail = true;
      final editor = LocalComplexEditorController(
        repository: repo,
        vault: ComplexRecoveryVault(
          scope: repo.scope,
          collection: repo.collection,
          kind: repo.kind,
          store: bytes,
        ),
        baseline: repo.baseline,
      );
      var grants = 0;
      final io = ComplexSourceIoController(
        editor: editor,
        owner: scope,
        capture: () async => ComplexEditorDocument.parse(repo.kind, 'Original'),
        prepareNative: () async {
          grants++;
          throw StateError('must not open');
        },
        replaceSurface: () async {},
        isCurrent: () => true,
        onDurableHandoff: (_) {},
      );
      try {
        await io.importSource(confirm: (_) async => true);
        expect(grants, 0);
        expect(repo.saves, 0);
        expect(bridge.calls, isNot(contains('pickImport')));
        expect(io.phase, ComplexSourceIoPhase.failed);
      } finally {
        io.dispose();
        editor.dispose();
        await scope.retire();
      }
    },
  );
  test(
    'existing MD scope retired during actual chunk reads rejects imported source',
    () async {
      final bridge = support.Bridge()..source = utf8.encode('# Incoming');
      final scope = await bridge.owner(),
          repo = ArticleRepository(),
          bytes = support.BytesStore();
      final editor = LocalComplexEditorController(
        repository: repo,
        vault: ComplexRecoveryVault(
          scope: repo.scope,
          collection: repo.collection,
          kind: repo.kind,
          store: bytes,
        ),
        baseline: repo.baseline,
      );
      bridge.beforeRead = () async {
        bridge.current = false;
        await scope.retire();
      };
      final original = ComplexEditorDocument.parse(repo.kind, '# Original');
      var confirmations = 0;
      final io = ComplexSourceIoController(
        editor: editor,
        owner: scope,
        capture: () async => original,
        prepareNative: () async => NativeComplexSourceIo(
          owner: scope,
          lease: 'owned-md-live',
          generation: 7,
          allowMarkdown: true,
          invoke: bridge.invoke,
        ),
        replaceSurface: () async {},
        isCurrent: () => bridge.current,
        onDurableHandoff: (_) {},
      );
      try {
        await io.importSource(
          confirm: (_) async {
            confirmations++;
            return true;
          },
        );
        expect(confirmations, 0);
        expect(editor.edit.document.source, original.source);
        expect(repo.saves, 0);
      } finally {
        io.dispose();
        editor.dispose();
        await scope.retire();
      }
    },
  );
}
