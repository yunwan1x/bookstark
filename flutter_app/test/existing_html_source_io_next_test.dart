import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/html_editor_controller.dart';
import 'package:bookstark_flutter/core/html_notes_repository.dart';
import 'package:bookstark_flutter/core/html_recovery_vault.dart';
import 'package:bookstark_flutter/core/native_complex_source_io.dart';
import 'package:bookstark_flutter/features/html/html_source_coordinator.dart';
import 'package:bookstark_flutter/features/html/html_source_io_controller.dart';

class NoSql implements HtmlNotesRepository {
  int calls = 0, disposals = 0;
  @override
  void dispose() {
    disposals++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls++;
    throw StateError('Source IO must not call SQL repository');
  }
}

// Capture peer only; actual engine serialization stays covered by the existing
// HtmlSourceCoordinator tests. These tests are not SAF/Native evidence.
class CapturedSource extends HtmlSourceCoordinator {
  CapturedSource(super.c)
    : super(
        freezeEdit: (text) => HtmlNoteEdit(
          title: c.draft.title,
          source: text,
          labels: c.draft.labels,
        ),
      );
  bool fail = false;
  int captures = 0;
  @override
  bool get ready => true;
  @override
  bool get busy => false;
  @override
  Future<bool> checkpoint({bool keepLocked = false}) async {
    captures++;
    return !fail && await controller.flushRecovery();
  }

  @override
  Future<void> unlock() async {}
}

class Picker extends NativeComplexSourceIo {
  Picker(ComplexSourceIoScope owner, this.value)
    : super(owner: owner, lease: 'actual-owner-peer', generation: 3);
  final ComplexSourceFile? value;
  int picks = 0;
  @override
  Future<ComplexSourceFile?> pick(ComplexEditorKind kind) async {
    picks++;
    return value;
  }
}

void main() {
  for (final approve in [false, true]) {
    test(
      'legacy HTML confirm $approve retains metadata and changes only original vault draft',
      () async {
        final repo = NoSql(), values = <String, String>{};
        final baseline = HtmlNote(
          metadata: HtmlNoteMetadata(
            id: 42,
            memberId: 7,
            collection: 'note',
            title: 'Original',
            version: 3,
            modifiedAt: 100,
            protected: false,
          ),
          source: '<p>Original</p>',
          labels: ['unchanged'],
        );
        final vault = HtmlRecoveryVault(
          server: Uri.parse('https://fixture.example'),
          memberId: 7,
          collection: 'note',
          readValue: (k) async => values[k],
          writeValue: (k, v) async {
            values[k] = v;
          },
          deleteValue: (k) async {
            values.remove(k);
          },
        );
        final editor = HtmlEditorController(repo, baseline, recovery: vault);
        editor.edit(
          HtmlNoteEdit(
            title: 'Original',
            source: '<p>Unsaved original</p>',
            labels: ['unchanged'],
          ),
        );
        final source = CapturedSource(editor);
        var current = true, retired = false, remounts = 0, grants = 0;
        final scope = await ComplexSourceIoScope.activate(
          scope: List.filled(64, 'e').join(),
          isCurrent: () => current,
          invoke: (name, args) async => name == 'scopeState'
              ? {'epoch': 0}
              : name == 'activateScope'
              ? {'epoch': 1}
              : {'retired': true},
        );
        final incoming = ComplexSourceFile(
          name: 'a.html',
          document: ComplexEditorDocument.parse(
            ComplexEditorKind.html,
            '\ufeff<p>Incoming</p>\r\n',
          ),
        );
        final picker = Picker(scope, incoming);
        final io = HtmlSourceIoController(
          editor: editor,
          source: source,
          scope: scope,
          isCurrent: () => current,
          prepareNative: () async {
            grants++;
            expect(values, isNotEmpty);
            return picker;
          },
          retireSurface: () async {
            retired = true;
          },
          remount: () async {
            remounts++;
          },
        );
        try {
          await io.run(
            importing: true,
            confirm: (_) async {
              expect(retired, isTrue);
              expect(editor.draft.source, '<p>Unsaved original</p>');
              return approve;
            },
          );
          expect(grants, 1);
          expect(repo.calls, 0);
          expect(remounts, 1);
          expect(editor.baseline, same(baseline));
          expect(editor.draft.title, 'Original');
          expect(editor.draft.labels, ['unchanged']);
          expect(
            editor.draft.source,
            approve ? incoming.document.source : '<p>Unsaved original</p>',
          );
          expect(io.completed, approve);
        } finally {
          io.retire();
          editor.dispose();
          await source.dispose();
          await scope.retire();
        }
      },
    );
  }
  test('failed checkpoint opens no grant or mutation', () async {
    final repo = NoSql();
    final baseline = HtmlNote(
      metadata: HtmlNoteMetadata(
        id: 42,
        memberId: 7,
        collection: 'note',
        title: 'Original',
        version: 3,
        modifiedAt: 100,
        protected: false,
      ),
      source: '<p>Original</p>',
      labels: [],
    );
    final editor = HtmlEditorController(repo, baseline);
    final source = CapturedSource(editor)..fail = true;
    final scope = await ComplexSourceIoScope.activate(
      scope: List.filled(64, 'f').join(),
      isCurrent: () => true,
      invoke: (n, a) async => n == 'scopeState'
          ? {'epoch': 0}
          : n == 'activateScope'
          ? {'epoch': 1}
          : {'retired': true},
    );
    var grants = 0;
    final io = HtmlSourceIoController(
      editor: editor,
      source: source,
      scope: scope,
      isCurrent: () => true,
      prepareNative: () async {
        grants++;
        throw StateError('must not open');
      },
      retireSurface: () async {},
      remount: () async {},
    );
    try {
      await io.run(importing: true, confirm: (_) async => true);
      expect(grants, 0);
      expect(repo.calls, 0);
      expect(editor.draft.source, baseline.source);
    } finally {
      io.retire();
      editor.dispose();
      await source.dispose();
      await scope.retire();
    }
  });
}
