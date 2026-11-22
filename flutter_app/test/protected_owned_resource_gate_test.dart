import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/protected_owned_resource_gate.dart';
import 'package:bookstark_flutter/core/protected_owned_complex_journal.dart';

void main() {
  String hex(String c) => List.filled(64, c).join();
  const server = 'https://owned.test/prefix', namespace = 'stable-member-7';
  final values = <String, String>{};
  bool current = true, failRead = false;
  Future<String?> read(String key) async {
    if (failRead) throw StateError('IO');
    return values[key];
  }

  ProtectedOwnedResourceGate gate(int member) => ProtectedOwnedResourceGate(
    server: server,
    memberId: member,
    namespace: namespace,
    readValue: read,
    writeValue: (k, v) async {
      values[k] = v;
    },
    deleteValue: (k) async {
      values.remove(k);
    },
    flush: () async {},
    isCurrent: () => current,
  );
  setUp(() {
    values.clear();
    current = true;
    failRead = false;
  });
  test(
    'same resource slot survives five-kind/protection changes; owner/id isolated',
    () async {
      String scope(String kind) => ProtectedOwnedComplexJournal.scopeFor(
        server: server,
        memberId: 7,
        namespace: namespace,
        resourceId: 91,
        kind: kind,
      );
      expect(scope('drawing'), scope('presentation'));
      final journal = ProtectedOwnedComplexJournal(
        scope: scope('drawing'),
        ownerTag: ProtectedOwnedComplexJournal.ownerTagFor(
          server: server,
          memberId: 7,
          namespace: namespace,
        ),
        isCurrent: () => current,
        readValue: read,
        writeValue: (k, v) async {
          values[k] = v;
        },
        deleteValue: (k) async {
          values.remove(k);
        },
        flush: () async {},
      );
      await journal.claimUnknown(
        baselineFingerprint: hex('a'),
        inputDigest: hex('b'),
      );
      journal.retire();
      expect(await gate(7).hasRetainedMarker(91), isTrue);
      expect(await gate(7).hasRetainedMarker(92), isFalse);
      expect(await gate(8).hasRetainedMarker(91), isFalse);
      expect(values.length, 1);
    },
  );
  test('I/O and retired scope never become marker absence', () async {
    failRead = true;
    await expectLater(gate(7).hasRetainedMarker(91), throwsStateError);
    failRead = false;
    current = false;
    await expectLater(gate(7).hasRetainedMarker(91), throwsStateError);
  });
}
