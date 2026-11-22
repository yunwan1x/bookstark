import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/owned15_creation_journal.dart';

void main() {
  late Map<String, String> values;
  late Owned15CreationJournal journal;
  var failFlush = false;
  var flushes = 0;
  const marker = Owned15CreationMarker(
    owner: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    operation: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    collection: 'article',
    kind: 'html',
    inputHash:
        'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
  );
  setUp(() {
    values = {};
    failFlush = false;
    flushes = 0;
    journal = Owned15CreationJournal(
      owner: marker.owner,
      isCurrent: () => true,
      readValue: (key) async => values[key],
      writeValue: (key, value) async {
        values[key] = value;
      },
      deleteValue: (key) async {
        values.remove(key);
      },
      flush: () async {
        flushes++;
        if (failFlush) throw StateError('durability failed');
      },
    );
  });
  tearDown(() async {
    await journal.retire();
  });
  test(
    'strict claim authorizes at most one submission and metadata has no body',
    () async {
      await journal.claim(marker);
      expect(() => journal.claim(marker), throwsStateError);
      expect((await journal.load())!.operation, marker.operation);
      expect(values.values.single, marker.encode());
      expect(values.values.single, isNot(contains('<html>')));
      expect(
        () => Owned15CreationJournal(
          owner: marker.owner,
          isCurrent: () => true,
          readValue: (key) async => null,
          writeValue: (key, value) async {},
          deleteValue: (key) async {},
          flush: () async {},
        ),
        throwsStateError,
      );
    },
  );
  test(
    'failed durable claim is consumed and retained, never replayed',
    () async {
      failFlush = true;
      await expectLater(journal.claim(marker), throwsStateError);
      expect(() => journal.claim(marker), throwsStateError);
      expect((await journal.load())!.knownId, isNull);
    },
  );
  test(
    'cold loaded unknown cannot claim and false fresh evidence preserves record',
    () async {
      await journal.claim(marker);
      await journal.retire();
      journal = Owned15CreationJournal(
        owner: marker.owner,
        isCurrent: () => true,
        readValue: (key) async => values[key],
        writeValue: (key, value) async {
          values[key] = value;
        },
        deleteValue: (key) async {
          values.remove(key);
        },
        flush: () async {},
      );
      await expectLater(journal.claim(marker), throwsStateError);
      await expectLater(
        journal.clearReviewed(marker, revalidate: () async => false),
        throwsStateError,
      );
      expect(values.length, 1);
    },
  );
  test(
    'known acknowledgement storage retry never calls SQL; deletion flush retry is storage only',
    () async {
      await journal.claim(marker);
      failFlush = true;
      await expectLater(journal.acknowledge(marker, 91), throwsStateError);
      failFlush = false;
      await journal.acknowledge(marker, 91);
      final known = (await journal.load())!;
      expect(known.knownId, 91);
      failFlush = true;
      await expectLater(
        journal.clearReviewed(known, revalidate: () async => true),
        throwsStateError,
      );
      expect(values, isEmpty);
      failFlush = false;
      await journal.clearReviewed(known, revalidate: () async => true);
      expect(values, isEmpty);
      expect(flushes, greaterThan(3));
    },
  );
  test('corrupt retained record is not absence and is never deleted', () async {
    await journal.claim(marker);
    values[values.keys.single] = '{}';
    await expectLater(journal.load(), throwsFormatException);
    await expectLater(
      journal.clearReviewed(marker, revalidate: () async => true),
      throwsStateError,
    );
    expect(values.values.single, '{}');
  });
}
