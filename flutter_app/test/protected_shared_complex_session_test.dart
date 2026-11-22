import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/complex_recovery_store.dart';
import 'package:bookstark_flutter/core/local_complex_editor_controller.dart';
import 'package:bookstark_flutter/core/local_complex_notes_repository.dart';
import 'package:bookstark_flutter/core/protected_shared_complex_session.dart';
import 'package:bookstark_flutter/core/protected_shared_identity.dart';
import 'package:bookstark_flutter/core/protected_shared_journal.dart';
import 'package:bookstark_flutter/core/protected_shared_lifetime.dart';
import 'package:bookstark_flutter/core/public_edit_link.dart';
import 'support/shared_capability_http_fixture.dart';

class HtmlWire extends SharedCapabilityHttpFixture {
  HtmlWire()
    : super(
        server: Uri.parse('https://complex-share.test'),
        identify: 'protected-html',
        source: '\ufeff<p>original🙂</p>\r\n',
      ) {
    protected = true;
  }
  bool renameOnPut = false;
  @override
  Map<String, Object?> get identity => {...super.identity, 'format': 'html'};
  @override
  Future<http.Response> handle(http.Request request) async {
    if (renameOnPut && request.method == 'PUT') {
      title = 'Concurrent server rename';
    }
    return super.handle(request);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'protected complex checkpoints use only RAM and never native recovery storage',
    () async {
      var nativeCalls = 0;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(NativeComplexRecoveryStore.channel, (
        _,
      ) async {
        nativeCalls++;
        throw StateError('Protected plaintext must not enter native recovery');
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          NativeComplexRecoveryStore.channel,
          null,
        ),
      );
      final wire = HtmlWire(), values = <String, String>{};
      final link = PublicEditLink.parse(
        wire.server,
        '${wire.server}/shares/protected-html?token=${wire.token}',
      );
      final transport = wire.capability(link, () => true);
      final source = await transport.read(password: ' correct ');
      final owner = ProtectedSharedLifetime(
        transport: transport,
        isCurrentScope: () => true,
        onDrained: (_) {},
      );
      final journal = ProtectedSharedJournal(
        capabilityPrincipal: ProtectedSharedJournal.capabilityFor(
          server: wire.server.toString(),
          shareId: source.identity.shareId,
          capabilityHash: sha256
              .convert(utf8.encode(link.requestPath))
              .toString(),
        ),
        identity: protectedSharedIdentity(source.identity),
        isCurrent: () => owner.current,
        listKeys: () async => values.keys.toList(),
        readValue: (key) async => values[key],
        writeValue: (key, value) async {
          values[key] = value;
        },
        deleteValue: (key) async {
          values.remove(key);
        },
        flush: () async {},
      );
      owner.bindJournal(journal);
      final session = await ProtectedSharedComplexSession.open(
        owner: owner,
        journal: journal,
        initial: source,
        password: ' correct ',
      );
      addTearDown(() async {
        session.controller.dispose();
        await session.retire();
      });
      final edit = ComplexNoteEdit(
        title: source.title,
        labels: const [],
        document: ComplexEditorDocument.parse(
          ComplexEditorKind.html,
          '\ufeff<p>draft secret🙂</p>\r\n',
        ),
      );
      final draftBytes = utf8.encode(edit.document.source);
      expect(draftBytes.take(3), orderedEquals([0xef, 0xbb, 0xbf]));
      expect(
        draftBytes.sublist(draftBytes.length - 2),
        orderedEquals([13, 10]),
      );
      await session.controller.checkpoint(edit);
      expect(session.controller.draftDurable, isFalse);
      expect(values, isEmpty);
      expect(nativeCalls, 0);
      final recovery = await session.controller.vault.read(
        source.identity.targetId,
      );
      expect(recovery!.edit.document.source, edit.document.source);
      final actual = await session.controller.save(edit);
      expect(actual!.document.source, edit.document.source);
      expect(wire.puts, 1);
      expect(values, isEmpty);
      expect(nativeCalls, 0);
      expect(session.controller.draftDurable, isFalse);
      await session.retire();
      await expectLater(session.memory.read('a' * 64), throwsStateError);
    },
  );
  test(
    'unknown complex save retains only hashes on disk and cannot overwrite on retry',
    () async {
      final wire = HtmlWire()..loseReply = true, values = <String, String>{};
      final link = PublicEditLink.parse(
        wire.server,
        '${wire.server}/shares/protected-html?token=${wire.token}',
      );
      final transport = wire.capability(link, () => true);
      final source = await transport.read(password: ' correct ');
      final owner = ProtectedSharedLifetime(
        transport: transport,
        isCurrentScope: () => true,
        onDrained: (_) {},
      );
      final journal = ProtectedSharedJournal(
        capabilityPrincipal: ProtectedSharedJournal.capabilityFor(
          server: wire.server.toString(),
          shareId: source.identity.shareId,
          capabilityHash: sha256
              .convert(utf8.encode(link.requestPath))
              .toString(),
        ),
        identity: protectedSharedIdentity(source.identity),
        isCurrent: () => owner.current,
        listKeys: () async => values.keys.toList(),
        readValue: (key) async => values[key],
        writeValue: (key, value) async {
          values[key] = value;
        },
        deleteValue: (key) async {
          values.remove(key);
        },
        flush: () async {},
      );
      owner.bindJournal(journal);
      final session = await ProtectedSharedComplexSession.open(
        owner: owner,
        journal: journal,
        initial: source,
        password: ' correct ',
      );
      addTearDown(() async {
        session.controller.dispose();
        await session.retire();
      });
      final edit = ComplexNoteEdit(
        title: source.title,
        labels: const [],
        document: ComplexEditorDocument.parse(
          ComplexEditorKind.html,
          '<p>unknown private draft</p>',
        ),
      );
      expect(await session.controller.save(edit), isNull);
      expect(session.controller.phase, ComplexSavePhase.unknown);
      expect(wire.puts, 1);
      expect(values.length, 1);
      expect(values.values.single, isNot(contains('unknown private draft')));
      expect(values.values.single, isNot(contains(' correct ')));
      expect(values.values.single, isNot(contains(wire.token)));
      await expectLater(session.controller.save(edit), throwsStateError);
      expect(wire.puts, 1);
    },
  );
  test(
    'concurrent rename preserves metadata and reports review instead of false save/replay',
    () async {
      final wire = HtmlWire()..renameOnPut = true, values = <String, String>{};
      final link = PublicEditLink.parse(
        wire.server,
        '${wire.server}/shares/protected-html?token=${wire.token}',
      );
      final transport = wire.capability(link, () => true);
      final source = await transport.read(password: ' correct ');
      final owner = ProtectedSharedLifetime(
        transport: transport,
        isCurrentScope: () => true,
        onDrained: (_) {},
      );
      final journal = ProtectedSharedJournal(
        capabilityPrincipal: ProtectedSharedJournal.capabilityFor(
          server: wire.server.toString(),
          shareId: source.identity.shareId,
          capabilityHash: sha256
              .convert(utf8.encode(link.requestPath))
              .toString(),
        ),
        identity: protectedSharedIdentity(source.identity),
        isCurrent: () => owner.current,
        listKeys: () async => values.keys.toList(),
        readValue: (key) async => values[key],
        writeValue: (key, value) async {
          values[key] = value;
        },
        deleteValue: (key) async {
          values.remove(key);
        },
        flush: () async {},
      );
      owner.bindJournal(journal);
      final session = await ProtectedSharedComplexSession.open(
        owner: owner,
        journal: journal,
        initial: source,
        password: ' correct ',
      );
      addTearDown(() async {
        session.controller.dispose();
        await session.retire();
      });
      final edit = ComplexNoteEdit(
        title: source.title,
        labels: const [],
        document: ComplexEditorDocument.parse(
          ComplexEditorKind.html,
          '<p>draft body</p>',
        ),
      );
      expect(await session.controller.save(edit), isNull);
      expect(session.controller.phase, ComplexSavePhase.unknown);
      expect(wire.puts, 1);
      expect(wire.title, 'Concurrent server rename');
      expect(journal.hasKnown, isTrue);
      expect(values.length, 1);
      final observed = await session.controller.observe();
      expect(observed.title, 'Concurrent server rename');
      expect(wire.puts, 1);
      // Review alone is not consent to erase the durable submission marker.
      await expectLater(
        session.controller.adoptReviewed(observed, keepDraft: true),
        throwsStateError,
      );
      expect(wire.puts, 1);
      final record = (await journal.loadGroup()).single;
      final fresh = await transport.read(password: ' correct ');
      await journal.endReviewed(
        record,
        reviewedFingerprint: fresh.fingerprint,
        allowUnverifiable: false,
        fresh: () async => protectedSharedObservation(
          await transport.read(password: ' correct '),
        ),
      );
      await session.controller.adoptReviewed(observed, keepDraft: true);
      expect(session.controller.edit.title, 'Concurrent server rename');
      expect(session.controller.edit.document.source, edit.document.source);
      expect(wire.puts, 1);
      expect(values, isEmpty);
    },
  );
}
