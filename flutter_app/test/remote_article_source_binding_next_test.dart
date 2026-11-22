import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/complex_editor_transport.dart';
import 'package:bookstark_flutter/core/remote_markdown_creation_controller.dart';
import 'package:bookstark_flutter/core/remote_markdown_creation_vault.dart';
import 'package:bookstark_flutter/features/complex_editors/remote_article_creation_source_binding.dart';
import 'support/markdown_creation_host.dart';
import 'remote_markdown_creation_controller_next_test.dart' show FakeTransport;

class _Fixture {
  final scope = MarkdownCreationScope(
    server: Uri.parse('https://demo.example'),
    memberId: 7,
    collection: 'article',
  );
  final values = <String, String>{};
  bool current = true, failFlush = false;
  final initial = MarkdownCreationInput(
    title: 'Article',
    content: 'Original',
    labels: const ['tag'],
  );
  late final wire = FakeTransport(
    scope,
    MarkdownCreationObserved(
      scope: scope,
      id: 208,
      version: 1,
      modifiedAt: 100,
      input: initial,
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
      values.remove(k);
    },
    flush: () async {
      if (failFlush) throw StateError('Native flush failed');
    },
  );
  Future<RemoteMarkdownCreationController> open() =>
      RemoteMarkdownCreationController.open(
        transport: wire,
        vault: vault,
        isCurrent: () => current,
        initial: initial,
      );
}

void main() {
  test(
    'real captured complete article is durable before one actual controller POST',
    () async {
      final f = _Fixture(), host = MarkdownCreationHost();
      final c = await f.open();
      addTearDown(c.retire);
      final binding = RemoteArticleCreationSourceBinding(
        controller: c,
        isCurrent: () => f.current,
      );
      const source = '\ufeff# Article edited😀\r\n';
      binding.source.beginGeneration(source);
      final transport = ComplexEditorTransport(host.call);
      await transport.load(
        ComplexEditorDocument.parse(ComplexEditorKind.markdown, source),
        readOnly: false,
      );
      await binding.source.bind(transport, generation: transport.generation!);
      expect(await binding.source.checkpoint(), isTrue);
      expect((await f.vault.read())!.input.content, source);
      expect(f.wire.posts, 0);
      f.wire.current = MarkdownCreationObserved(
        scope: f.scope,
        id: 208,
        version: 1,
        modifiedAt: 100,
        input: c.record.input,
        editorType: 'markdown',
        isProtected: false,
      );
      expect(await binding.source.submit(), isTrue);
      expect(c.phase, MarkdownCreationPhase.finished);
      expect(await f.vault.read(), isNull);
      expect(f.wire.posts, 1);
      expect(f.wire.sent!.content, source);
      expect(c.record.knownIDOrigin, MarkdownKnownIDOrigin.postReceipt);
      expect(c.record.knownId, 208);
      expect(await binding.source.submit(), isFalse);
      expect(f.wire.posts, 1);
      await binding.retireAndDrain();
      await transport.retire();
    },
  );
  test(
    'flush failure retains record and becomes readonly without a POST',
    () async {
      final f = _Fixture(), host = MarkdownCreationHost();
      final c = await f.open();
      addTearDown(c.retire);
      final binding = RemoteArticleCreationSourceBinding(
        controller: c,
        isCurrent: () => f.current,
      );
      const source = '# Full unsaved source';
      binding.source.beginGeneration(source);
      final transport = ComplexEditorTransport(host.call);
      await transport.load(
        ComplexEditorDocument.parse(ComplexEditorKind.markdown, source),
        readOnly: false,
      );
      await binding.source.bind(transport, generation: transport.generation!);
      f.failFlush = true;
      expect(await binding.source.checkpoint(), isFalse);
      expect(c.phase, MarkdownCreationPhase.unknown);
      expect(c.canEdit, isFalse);
      expect(f.values, isNotEmpty);
      expect(host.source, source);
      expect(f.wire.posts, 0);
      expect(await binding.source.submit(), isFalse);
      expect(f.wire.posts, 0);
      await binding.retireAndDrain();
      await transport.retire();
    },
  );
  test(
    'oversized captured source is not truncated or put into the 4MiB record',
    () async {
      final f = _Fixture(), host = MarkdownCreationHost();
      final c = await f.open();
      addTearDown(c.retire);
      final binding = RemoteArticleCreationSourceBinding(
        controller: c,
        isCurrent: () => f.current,
      );
      binding.source.beginGeneration('Original');
      final transport = ComplexEditorTransport(host.call);
      await transport.load(
        ComplexEditorDocument.parse(ComplexEditorKind.markdown, 'Original'),
        readOnly: false,
      );
      await binding.source.bind(transport, generation: transport.generation!);
      final oversized = '\ufeff${'x' * (4 * 1024 * 1024)}😀';
      host.source = oversized;
      host.revision++;
      expect(await binding.source.submit(), isFalse);
      expect(host.source, oversized);
      expect(host.locked, isFalse);
      expect(f.values, isEmpty);
      expect(f.wire.posts, 0);
      expect(c.record.input.content, 'Original');
      await binding.retireAndDrain();
      await transport.retire();
    },
  );
  test(
    'retirement while capture is held cannot commit or submit late source',
    () async {
      final f = _Fixture(), host = MarkdownCreationHost();
      final c = await f.open();
      addTearDown(c.retire);
      final binding = RemoteArticleCreationSourceBinding(
        controller: c,
        isCurrent: () => f.current,
      );
      binding.source.beginGeneration('Original');
      final transport = ComplexEditorTransport(host.call);
      await transport.load(
        ComplexEditorDocument.parse(ComplexEditorKind.markdown, 'Original'),
        readOnly: false,
      );
      await binding.source.bind(transport, generation: transport.generation!);
      host.snapshotStarted = Completer<void>();
      host.snapshotGate = Completer<void>();
      final capture = binding.source.submit();
      await host.snapshotStarted!.future;
      f.current = false;
      host.snapshotGate!.complete();
      expect(await capture, isFalse);
      expect(f.values, isEmpty);
      expect(f.wire.posts, 0);
      await binding.retireAndDrain();
      await transport.retire();
    },
  );
}
