import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/complex_editor_transport.dart';
import 'package:bookstark_flutter/core/notes_repository.dart';
import 'package:bookstark_flutter/core/owned_preview_controller.dart';
import 'package:bookstark_flutter/core/remote_markdown_creation_controller.dart';
import 'package:bookstark_flutter/core/remote_markdown_creation_vault.dart';
import 'package:bookstark_flutter/features/complex_editors/complex_editor_browser.dart';
import 'package:bookstark_flutter/features/complex_editors/remote_article_creation_page.dart';
import 'package:bookstark_flutter/features/notes/notes_page.dart';
import 'package:bookstark_flutter/features/notes/remote_markdown_creation_factory.dart';
import 'remote_markdown_creation_controller_next_test.dart' show FakeTransport;
import 'support/markdown_creation_host.dart';

class _Repository extends NotesRepository {
  int saves = 0;
  @override
  Future<Note> read(int id) async =>
      Note(id: id, title: 'Actual', content: 'Actual');
  @override
  Future<int> save(Note value) async {
    saves++;
    throw StateError('Legacy save forbidden');
  }

  @override
  Future<List<Note>> list({String keyword = '', int page = 1}) async => [];
  @override
  Future<void> remove(int id) async => throw StateError('Delete forbidden');
}

class _ArticleWire extends FakeTransport {
  _ArticleWire(super.scope, super.current);
  @override
  Future<int> submit(
    MarkdownCreationInput input, {
    required void Function() onSubmit,
  }) async {
    final before = posts;
    try {
      return await super.submit(input, onSubmit: onSubmit);
    } finally {
      if (posts > before) {
        current = MarkdownCreationObserved(
          scope: scope,
          id: 208,
          version: 1,
          modifiedAt: 100,
          input: input,
          editorType: 'markdown',
          isProtected: false,
        );
      }
    }
  }
}

class ArticleCreationPageFixture {
  ArticleCreationPageFixture({int memberId = 7})
    : scope = MarkdownCreationScope(
        server: Uri.parse('https://demo.example'),
        memberId: memberId,
        collection: 'article',
      );
  final MarkdownCreationScope scope;
  final input = MarkdownCreationInput(
    title: 'Article',
    content: 'Original',
    labels: const ['tag'],
  );
  final values = <String, String>{};
  final repo = _Repository();
  bool current = true, deleteFails = false;
  late final wire = _ArticleWire(
    scope,
    MarkdownCreationObserved(
      scope: scope,
      id: 208,
      version: 1,
      modifiedAt: 100,
      input: input,
      editorType: 'markdown',
      isProtected: false,
    ),
  );
  late final vault = RemoteMarkdownCreationVault(
    scope: scope,
    readValue: (k) async => values[k],
    writeValue: (k, v) async {
      values[k] = v;
    },
    deleteValue: (k) async {
      if (deleteFails) throw StateError('Cleanup held');
      values.remove(k);
    },
    flush: () async {},
  );
  Future<RemoteMarkdownCreationController> open() =>
      RemoteMarkdownCreationController.open(
        transport: wire,
        vault: vault,
        isCurrent: () => current,
        initial: input,
      );
  RemoteMarkdownCreationBinding binding(RemoteMarkdownCreationController c) =>
      RemoteMarkdownCreationBinding(
        controller: c,
        repository: repo,
        isCurrent: () => current,
        collection: NoteCollection.article,
        english: true,
      );
}

Widget articleCreationSurface(
  BuildContext context, {
  required Key key,
  required ComplexEditorDocument document,
  required String title,
  required bool english,
  required OwnedPreviewController retirementController,
  required Future<void> Function(ComplexEditorTransport) onReady,
  required void Function(ComplexEditorState) onState,
  required Future<void> Function() onSaveRequested,
  required Future<void> Function(ComplexEditorTransport) beforeRetire,
  required Future<void> Function() onReloadRequested,
}) => ArticleCreationEngine(
  key: key,
  document: document,
  owner: retirementController,
  onReady: onReady,
  onState: onState,
  beforeRetire: beforeRetire,
);

class ArticleCreationEngine extends StatefulWidget {
  const ArticleCreationEngine({
    super.key,
    required this.document,
    required this.owner,
    required this.onReady,
    required this.onState,
    required this.beforeRetire,
  });
  final ComplexEditorDocument document;
  final OwnedPreviewController owner;
  final Future<void> Function(ComplexEditorTransport) onReady, beforeRetire;
  final void Function(ComplexEditorState) onState;
  @override
  State<ArticleCreationEngine> createState() => ArticleCreationEngineState();
}

class ArticleCreationEngineState extends State<ArticleCreationEngine> {
  final host = MarkdownCreationHost();
  late final transport = ComplexEditorTransport((name, args) async {
    if (name == 'setMarkdownByteLimit') {
      expect(host.locked, isTrue);
      expect(args, [4 * 1024 * 1024, host.generation]);
      return {
        'generation': host.generation,
        'kind': 'markdown',
        'limit': args[0],
      };
    }
    return host.call(name, args);
  });
  late Future<void> loading;
  bool ready = false;
  @override
  void initState() {
    super.initState();
    widget.owner.bind(this, () async {
      await loading;
      await widget.beforeRetire(transport);
      await transport.retire();
    });
    loading = () async {
      await transport.load(widget.document, readOnly: false);
      if (!mounted || widget.owner.retired) return;
      await widget.onReady(transport);
      if (mounted) setState(() => ready = true);
    }();
  }

  void enter(String source) {
    host.source = source;
    host.revision++;
    widget.onState(
      ComplexEditorState.parse(host.state(), ComplexEditorKind.markdown)!,
    );
  }

  @override
  Widget build(BuildContext context) => const ColoredBox(color: Colors.white);
  @override
  void dispose() {
    widget.owner.unbind(this);
    super.dispose();
  }
}

Future<void> _pump(WidgetTester tester, [int frames = 30]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await _pump(tester);
}

void main() {
  testWidgets(
    'actual article page durable capture then one Save never uses NoteEditor',
    (tester) async {
      final f = ArticleCreationPageFixture();
      final c = await f.open();
      await tester.pumpWidget(
        MaterialApp(
          home: RemoteArticleCreationPage(
            binding: f.binding(c),
            surfaceBuilder: articleCreationSurface,
            openKnown: (_, _) async {},
          ),
        ),
      );
      await _pump(tester);
      expect(find.byType(NoteEditorPage), findsNothing);
      final engine = tester.state<ArticleCreationEngineState>(
        find.byType(ArticleCreationEngine),
      );
      expect(engine.ready, isTrue);
      const edited = '\ufeff# Actual WebView port edited😀\r\n';
      engine.enter(edited);
      await tester.pump();
      expect(find.text('Draft retention pending'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 650));
      await _pump(tester);
      expect((await f.vault.read())!.input.content, edited);
      expect(find.text('Draft retained on this device'), findsOneWidget);
      expect(f.wire.posts, 0);
      expect(f.repo.saves, 0);
      await tester.tap(
        find.widgetWithText(FilledButton, 'Save article').hitTestable(),
      );
      await _pump(tester);
      expect(f.wire.posts, 1);
      expect(f.wire.sent!.content, edited);
      expect(c.record.knownId, 208);
      expect(c.record.knownIDOrigin, MarkdownKnownIDOrigin.postReceipt);
      expect(find.byType(ComplexEditorBrowser), findsOneWidget);
      expect(find.byType(NoteEditorPage), findsNothing);
      expect(f.repo.saves, 0);
      await _close(tester);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'lost POST response shows readonly real Browser and cannot adopt without full runtime review',
    (tester) async {
      final f = ArticleCreationPageFixture();
      f.wire.drop = true;
      final c = await f.open();
      await tester.pumpWidget(
        MaterialApp(
          home: RemoteArticleCreationPage(
            binding: f.binding(c),
            surfaceBuilder: articleCreationSurface,
            openKnown: (_, _) async {},
          ),
        ),
      );
      await _pump(tester);
      await tester.tap(
        find.widgetWithText(FilledButton, 'Save article').hitTestable(),
      );
      await _pump(tester);
      expect(c.phase, MarkdownCreationPhase.unknown);
      expect(f.wire.posts, 1);
      expect(find.byType(ComplexEditorBrowser), findsOneWidget);
      expect(find.byType(NoteEditorPage), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Save article'), findsNothing);
      await tester.enterText(find.byType(TextField), '208');
      await tester.ensureVisible(
        find.widgetWithText(OutlinedButton, 'Read server version'),
      );
      await tester.tap(
        find
            .widgetWithText(OutlinedButton, 'Read server version')
            .hitTestable(),
      );
      await _pump(tester);
      final adopt = find.widgetWithText(
        FilledButton,
        'Reviewed: associate this article',
      );
      expect(tester.widget<FilledButton>(adopt).onPressed, isNull);
      expect(f.wire.posts, 1);
      expect(f.repo.saves, 0);
      expect(await f.vault.read(), isNotNull);
      await _close(tester);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'EN 320dp font2 keyboard keeps unknown controls scrollable without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final f = ArticleCreationPageFixture();
      f.wire.drop = true;
      final c = await f.open();
      await c.save();
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
              viewInsets: const EdgeInsets.only(bottom: 280),
            ),
            child: child!,
          ),
          home: RemoteArticleCreationPage(
            binding: f.binding(c),
            surfaceBuilder: articleCreationSurface,
            openKnown: (_, _) async {},
          ),
        ),
      );
      await _pump(tester);
      final keep = find.widgetWithText(OutlinedButton, 'Keep and return');
      await tester.ensureVisible(keep);
      await _pump(tester, 2);
      expect(keep.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(f.wire.posts, 1);
      expect(f.repo.saves, 0);
      await _close(tester);
    },
  );
  testWidgets(
    'owner replacement during held real source capture blanks old body and cannot send for either owner',
    (tester) async {
      final old = ArticleCreationPageFixture(),
          next = ArticleCreationPageFixture(memberId: 8);
      final c1 = await old.open();
      final binding1 = old.binding(c1);
      await tester.pumpWidget(
        MaterialApp(
          home: RemoteArticleCreationPage(
            key: const ValueKey('same-route'),
            binding: binding1,
            surfaceBuilder: articleCreationSurface,
            openKnown: (_, _) async {},
          ),
        ),
      );
      await _pump(tester);
      final engine = tester.state<ArticleCreationEngineState>(
        find.byType(ArticleCreationEngine),
      );
      engine.host.snapshotStarted = Completer<void>();
      engine.host.snapshotGate = Completer<void>();
      engine.enter('# Owner one pending');
      await tester.tap(
        find.widgetWithText(FilledButton, 'Save article').hitTestable(),
      );
      await tester.pump();
      expect(engine.host.snapshotStarted!.isCompleted, isTrue);
      old.current = false;
      final c2 = await next.open();
      await tester.pumpWidget(
        MaterialApp(
          home: RemoteArticleCreationPage(
            key: const ValueKey('same-route'),
            binding: next.binding(c2),
            surfaceBuilder: articleCreationSurface,
            openKnown: (_, _) async {},
          ),
        ),
      );
      engine.host.snapshotGate!.complete();
      await _pump(tester);
      expect(find.byType(ArticleCreationEngine), findsNothing);
      expect(
        find.text('Editing scope changed. Reopen the article.'),
        findsOneWidget,
      );
      expect(old.wire.posts, 0);
      expect(next.wire.posts, 0);
      expect(old.repo.saves, 0);
      expect(next.repo.saves, 0);
      expect(c2.canEdit, isFalse);
      await _close(tester);
      expect(tester.takeException(), isNull);
    },
  );
}
