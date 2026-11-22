import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/owned15_creation_journal.dart';

void main() {
  const marker = Owned15CreationMarker(
    owner: 'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
    operation: 'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
    collection: 'note',
    kind: 'markdown',
    inputHash:
        'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
  );
  test(
    'retirement during final fresh read preserves recovery marker',
    () async {
      String? raw;
      var reads = 0, deletes = 0;
      Completer<void>? entered, release;
      final journal = Owned15CreationJournal(
        owner: marker.owner,
        isCurrent: () => true,
        readValue: (key) async {
          reads++;
          if (entered != null && reads == 2) {
            entered.complete();
            await release!.future;
          }
          return raw;
        },
        writeValue: (key, value) async {
          raw = value;
        },
        deleteValue: (key) async {
          deletes++;
          raw = null;
        },
        flush: () async {},
      );
      try {
        await journal.claim(marker);
        reads = 0;
        entered = Completer<void>();
        release = Completer<void>();
        final clearing = journal.clearReviewed(
          marker,
          revalidate: () async => true,
        );
        final rejected = expectLater(clearing, throwsStateError);
        await entered.future;
        final retired = journal.retire();
        release.complete();
        await rejected;
        await retired;
        expect(raw, marker.encode());
        expect(deletes, 0);
      } finally {
        release?.completeIfNeeded();
        await journal.retire();
      }
    },
  );
  test('known receipt cannot be retargeted on storage retry', () async {
    String? raw;
    final journal = Owned15CreationJournal(
      owner: marker.owner,
      isCurrent: () => true,
      readValue: (key) async => raw,
      writeValue: (key, value) async {
        raw = value;
      },
      deleteValue: (key) async {
        raw = null;
      },
      flush: () async {},
    );
    try {
      await journal.claim(marker);
      await journal.acknowledge(marker, 42);
      final known = (await journal.load())!, before = raw;
      await expectLater(journal.acknowledge(known, 43), throwsArgumentError);
      expect(raw, before);
    } finally {
      await journal.retire();
    }
  });
  test('duplicate JSON keys never become valid recoverable metadata', () {
    final raw = marker.encode();
    expect(
      () => Owned15CreationMarker.decode(
        raw.replaceFirst('{', '{"v":1,'),
        marker.owner,
      ),
      throwsFormatException,
    );
  });
}

extension on Completer<void> {
  void completeIfNeeded() {
    if (!isCompleted) complete();
  }
}
