import 'package:flutter_test/flutter_test.dart';

import 'package:bookstark_flutter/core/remote_markdown_creation_vault.dart';
import 'package:bookstark_flutter/core/remote_markdown_creation_controller.dart';

class FakeTransport implements RemoteMarkdownCreationTransport {
  int retireCalls = 0;
  @override
  void retire() {
    retireCalls++;
  }

  FakeTransport(this.scope, this.current);
  @override
  final MarkdownCreationScope scope;
  MarkdownCreationObserved current;
  int posts = 0, reads = 0;
  MarkdownCreationInput? sent;
  bool drop = false, preSubmitFail = false;
  @override
  Future<int> submit(
    MarkdownCreationInput input, {
    required void Function() onSubmit,
  }) async {
    if (preSubmitFail) throw StateError('Before send');
    onSubmit();
    sent = input;
    posts++;
    if (drop) throw StateError('Applied but response lost');
    return current.id;
  }

  @override
  Future<MarkdownCreationObserved> inspect(int id) async {
    reads++;
    return current;
  }
}

class Fixture {
  final scope = MarkdownCreationScope(
    server: Uri.parse('https://demo.example'),
    memberId: 7,
    collection: 'note',
  );
  final input = MarkdownCreationInput(
    title: 'Trip',
    content: '\ufeff# Checklist😀\r\n',
    labels: ['travel'],
  );
  final values = <String, String>{};
  late final transport = FakeTransport(scope, observed());
  late final vault = RemoteMarkdownCreationVault(
    scope: scope,
    readValue: (k) async => values[k],
    writeValue: (k, v) async {
      values[k] = v;
    },
    deleteValue: (k) async {
      if (deleteFails) throw StateError('Delete failed');
      values.remove(k);
    },
    flush: () async {},
  );
  bool current = true, deleteFails = false;
  MarkdownCreationObserved observed({
    int id = 318,
    int version = 1,
    String? content,
  }) => MarkdownCreationObserved(
    scope: scope,
    id: id,
    version: version,
    modifiedAt: 100 + version,
    input: content == null
        ? input
        : MarkdownCreationInput(
            title: 'Trip',
            content: content,
            labels: ['travel'],
          ),
    editorType: 'markdown',
    isProtected: false,
  );
  Future<RemoteMarkdownCreationController> open() =>
      RemoteMarkdownCreationController.open(
        transport: transport,
        vault: vault,
        isCurrent: () => current,
        initial: input,
      );
}

void main() {
  test('owner coordinator retire aborts transport exactly once', () async {
    final f = Fixture();
    final c = await f.open();
    c.retire();
    c.retire();
    expect(f.transport.retireCalls, 1);
    await expectLater(c.save(), throwsStateError);
    expect(f.transport.posts, 0);
  });
  test('one POST uses edited full snapshot and successful cleanup', () async {
    final f = Fixture();
    final editor = await f.open();
    addTearDown(editor.retire);
    final edited = MarkdownCreationInput(
      title: 'Edited title',
      content: '\ufeffEdited😀\r\n',
      labels: ['changed'],
    );
    await editor.edit(edited);
    f.transport.current = MarkdownCreationObserved(
      scope: f.scope,
      id: 318,
      version: 1,
      modifiedAt: 101,
      input: edited,
      editorType: 'markdown',
      isProtected: false,
    );
    await editor.save();
    expect(f.transport.sent!.fingerprint, edited.fingerprint);
    expect(f.transport.posts, 1);
    expect(editor.phase, MarkdownCreationPhase.finished);
    expect(await f.vault.read(), isNull);
    await expectLater(editor.save(), throwsStateError);
    expect(f.transport.posts, 1);
  });
  test(
    'lost response stays unknown across cold controller restart, no second POST',
    () async {
      final f = Fixture();
      f.transport.drop = true;
      final a = await f.open();
      await a.save();
      expect(a.phase, MarkdownCreationPhase.unknown);
      expect((await f.vault.read())!.pending, isTrue);
      a.retire();
      final b = await f.open();
      addTearDown(b.retire);
      expect(b.phase, MarkdownCreationPhase.unknown);
      await expectLater(b.save(), throwsStateError);
      expect(f.transport.posts, 1);
    },
  );
  test('fresh change blocks adoption until complete latest review', () async {
    final f = Fixture();
    f.transport.drop = true;
    final c = await f.open();
    addTearDown(c.retire);
    await c.save();
    await c.inspect(318);
    c.markReviewed(c.observed!);
    f.transport.current = f.observed(version: 2, content: 'Changed remotely');
    await c.adopt();
    expect(c.phase, MarkdownCreationPhase.review);
    expect(await f.vault.read(), isNotNull);
    await expectLater(c.adopt(), throwsStateError);
    c.markReviewed(c.observed!);
    await c.adopt();
    expect(c.phase, MarkdownCreationPhase.finished);
    expect(f.transport.posts, 1);
    expect(f.transport.current.input.content, 'Changed remotely');
  });
  test('known ID cleanup retry never calls transport', () async {
    final f = Fixture();
    f.deleteFails = true;
    final c = await f.open();
    addTearDown(c.retire);
    await c.save();
    expect(c.phase, MarkdownCreationPhase.cleanup);
    expect(c.record.knownId, 318);
    final reads = f.transport.reads;
    f.deleteFails = false;
    await c.retryCleanup();
    expect(c.phase, MarkdownCreationPhase.finished);
    expect(f.transport.posts, 1);
    expect(f.transport.reads, reads);
  });
  test('known ID cannot inspect another ID', () async {
    final f = Fixture();
    f.transport.current = f.observed(content: 'Different');
    final c = await f.open();
    addTearDown(c.retire);
    await c.save();
    expect(c.record.knownId, 318);
    final reads = f.transport.reads;
    await c.inspect(319);
    expect(c.phase, MarkdownCreationPhase.unknown);
    expect(f.transport.reads, reads);
    expect(await f.vault.read(), isNotNull);
  });
  test(
    'proven pre-submit failure may edit and retry only after durable reset',
    () async {
      final f = Fixture();
      f.transport.preSubmitFail = true;
      final c = await f.open();
      addTearDown(c.retire);
      await c.save();
      expect(c.phase, MarkdownCreationPhase.editing);
      expect((await f.vault.read())!.pending, isFalse);
      expect(f.transport.posts, 0);
    },
  );
  test(
    'duplicate lease rejected and old retire cannot unlock new editor',
    () async {
      final f = Fixture();
      final first = await f.open();
      await expectLater(f.open(), throwsStateError);
      first.retire();
      final second = await f.open();
      addTearDown(second.retire);
      first.retire();
      await expectLater(f.open(), throwsStateError);
    },
  );
  test(
    'wrong format and protection cannot construct an observed Markdown body',
    () {
      final f = Fixture();
      expect(
        () => MarkdownCreationObserved(
          scope: f.scope,
          id: 318,
          version: 1,
          modifiedAt: 1,
          input: f.input,
          editorType: 'html',
          isProtected: false,
        ),
        throwsFormatException,
      );
      expect(
        () => MarkdownCreationObserved(
          scope: f.scope,
          id: 318,
          version: 1,
          modifiedAt: 1,
          input: f.input,
          editorType: 'markdown',
          isProtected: true,
        ),
        throwsFormatException,
      );
    },
  );
}
