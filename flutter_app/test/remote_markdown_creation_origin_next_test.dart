import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/remote_markdown_creation_controller.dart';
import 'package:bookstark_flutter/core/remote_markdown_creation_vault.dart';
import 'remote_markdown_creation_controller_next_test.dart' as fixture;

void main() {
  test(
    'actual POST origin survives storage-only failure and cold roundtrip',
    () async {
      final f = fixture.Fixture()..deleteFails = true;
      final first = await f.open();
      await first.save();
      expect(first.phase, MarkdownCreationPhase.cleanup);
      expect(first.record.knownIDOrigin, MarkdownKnownIDOrigin.postReceipt);
      first.retire();
      final cold = await f.open();
      addTearDown(cold.retire);
      expect(cold.record.knownIDOrigin, MarkdownKnownIDOrigin.postReceipt);
      expect(cold.record.knownId, 318);
      expect(f.transport.posts, 1);
      expect(
        cold.record.copy().knownIDOrigin,
        MarkdownKnownIDOrigin.postReceipt,
      );
    },
  );
  test('explicit adopt is manualExisting and never another POST', () async {
    final f = fixture.Fixture()..transport.drop = true;
    final c = await f.open();
    addTearDown(c.retire);
    await c.save();
    expect(c.phase, MarkdownCreationPhase.unknown);
    await c.inspect(318);
    c.markReviewed(c.observed!);
    f.deleteFails = true;
    await c.adopt();
    expect(c.record.knownIDOrigin, MarkdownKnownIDOrigin.manualExisting);
    expect(
      (await f.vault.read())!.knownIDOrigin,
      MarkdownKnownIDOrigin.manualExisting,
    );
    expect(f.transport.posts, 1);
    f.deleteFails = false;
    await c.retryCleanup();
    expect(c.phase, MarkdownCreationPhase.finished);
    expect(c.record.knownIDOrigin, MarkdownKnownIDOrigin.manualExisting);
    expect(f.transport.posts, 1);
  });
  test('legacy missing origin is unknownLegacy without ID inference', () {
    final f = fixture.Fixture();
    final known = MarkdownCreationRecord.fresh(
      f.scope,
      f.input,
    ).copy(pending: true, knownId: 318);
    final legacy = Map<String, Object?>.of(known.toJson())
      ..remove('known_id_origin');
    final parsed = MarkdownCreationRecord.parse(legacy, f.scope);
    expect(parsed.knownIDOrigin, MarkdownKnownIDOrigin.unknownLegacy);
    expect(parsed.knownId, 318);
    expect(
      MarkdownCreationRecord.parse(parsed.toJson(), f.scope).knownIDOrigin,
      MarkdownKnownIDOrigin.unknownLegacy,
    );
  });
  test(
    'pending cannot claim post receipt provenance; unknown names fail closed',
    () {
      final f = fixture.Fixture();
      final pending = MarkdownCreationRecord.fresh(f.scope, f.input);
      expect(
        () => pending.copy(knownIDOrigin: MarkdownKnownIDOrigin.postReceipt),
        throwsFormatException,
      );
      final invalid = Map<String, Object?>.of(pending.toJson())
        ..['known_id_origin'] = 'inferredFromName';
      expect(
        () => MarkdownCreationRecord.parse(invalid, f.scope),
        throwsFormatException,
      );
    },
  );
}
