import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/anonymous_shared_capability.dart';
import 'package:bookstark_flutter/core/protected_shared_identity.dart';
import 'package:bookstark_flutter/core/protected_shared_journal.dart';
import 'package:bookstark_flutter/core/protected_shared_lifetime.dart';
import 'package:bookstark_flutter/core/protected_shared_markdown_controller.dart';
import 'package:bookstark_flutter/core/protected_shared_markdown_repository.dart';
import 'package:bookstark_flutter/core/public_edit_controller.dart';
import 'package:bookstark_flutter/core/public_edit_link.dart';
import 'support/shared_capability_http_fixture.dart';

class Fixture {
  final wire = SharedCapabilityHttpFixture(
    server: Uri.parse('https://share.test'),
    identify: 'protected',
    source: '# original',
  )..protected = true;
  final values = <String, String>{}, written = <String>[];
  bool failKnownFlush = false;
  int _pendingFlushFailures = 0;
  late final link = PublicEditLink.parse(
    wire.server,
    'https://share.test/shares/protected?token=${wire.token}',
  );
  late final transport = AnonymousSharedCapability(
    link,
    isCurrent: () => true,
    anonymousTestClient: () => MockClient((request) async {
      // Password is permitted only in the typed POST/PUT JSON body.
      expect(request.url.queryParameters.keys, isNot(contains('password')));
      expect(request.url.toString(), isNot(contains('correct')));
      expect(request.headers['authorization'], isNull);
      return wire.handle(request);
    }),
  );
  late final owner = ProtectedSharedLifetime(
    transport: transport,
    isCurrentScope: () => true,
    onDrained: (_) {},
  );
  late ProtectedSharedJournal journal;
  late ProtectedSharedMarkdownController controller;
  Future<void> open() async {
    final source = await transport.read(password: ' correct ');
    journal = ProtectedSharedJournal(
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
        written.add(value);
        if (failKnownFlush && (jsonDecode(value) as Map)['phase'] == 'known') {
          _pendingFlushFailures = 1;
        }
      },
      deleteValue: (key) async {
        values.remove(key);
      },
      flush: () async {
        if (_pendingFlushFailures > 0) {
          _pendingFlushFailures--;
          throw StateError('flush ACK lost');
        }
      },
    );
    owner.bindJournal(journal);
    controller = ProtectedSharedMarkdownController(
      ProtectedSharedMarkdownRepository(
        owner: owner,
        journal: journal,
        initial: source,
        password: ' correct ',
      ),
      link,
      journal: journal,
    );
    await controller.initialize(password: ' correct ');
  }

  Future<void> close() async {
    controller.close();
    await owner.retire();
  }
}

void main() {
  test(
    'unknown protected Markdown never replays and requires explicit metadata end',
    () async {
      final f = Fixture();
      await f.open();
      addTearDown(f.close);
      f.wire.loseReply = true;
      await expectLater(
        f.controller.save('# edited secret'),
        throwsA(anything),
      );
      expect(f.wire.puts, 1);
      expect(f.controller.phase, PublicEditPhase.unknown);
      expect(f.values.length, 1);
      for (final raw in f.written) {
        expect(raw, isNot(contains('edited secret')));
        expect(raw, isNot(contains(' correct ')));
        expect(raw, isNot(contains(f.wire.token)));
      }
      await f.controller
          .verify(); // Real read proves matching body, not execution history.
      expect(f.controller.phase, PublicEditPhase.acknowledged);
      expect(f.values.length, 1);
      await expectLater(f.controller.save('# another body'), throwsA(anything));
      expect(f.wire.puts, 1);
      final record = (await f.journal.loadGroup()).single;
      final actual = await f.transport.read(password: ' correct ');
      await f.journal.endReviewed(
        record,
        reviewedFingerprint: actual.fingerprint,
        allowUnverifiable: false,
        fresh: () async => protectedSharedObservation(
          await f.transport.read(password: ' correct '),
        ),
      );
      f.wire.loseReply = false;
      // Explicit record ending does not itself send anything.
      expect(f.wire.puts, 1);
      // Controller kept its prior pending state; fresh explicit verify resolves it.
      await f.controller.verify();
      expect(f.controller.remoteStillBaseline, isTrue);
      f.controller
          .acknowledgeRetry(); // Explicit new authorization after ending.
      await f.controller.save('# explicit new edit');
      expect(f.wire.puts, 2);
      expect(f.values, isEmpty);
    },
  );
  test(
    'known receipt storage failure retries only metadata and exact read',
    () async {
      final f = Fixture();
      await f.open();
      addTearDown(f.close);
      f.failKnownFlush = true;
      await expectLater(
        f.controller.save('# receipt applied'),
        throwsA(anything),
      );
      expect(f.wire.puts, 1);
      expect(f.journal.hasKnown, isTrue);
      f.failKnownFlush = false;
      await f.journal.persistKnown();
      expect(f.wire.puts, 1);
      await f.controller.verify();
      expect(f.controller.phase, PublicEditPhase.acknowledged);
      expect(f.wire.puts, 1);
      expect(f.values, isEmpty);
    },
  );
}
