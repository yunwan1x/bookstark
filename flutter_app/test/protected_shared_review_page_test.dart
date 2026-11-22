import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/anonymous_shared_capability.dart';
import 'package:bookstark_flutter/core/protected_shared_identity.dart';
import 'package:bookstark_flutter/core/protected_shared_journal.dart';
import 'package:bookstark_flutter/core/protected_shared_lifetime.dart';
import 'package:bookstark_flutter/core/protected_shared_marker_metadata.dart';
import 'package:bookstark_flutter/core/public_edit_link.dart';
import 'package:bookstark_flutter/features/public_shares/protected_shared_review_page.dart';

class ReviewFixture {
  ReviewFixture(this.tag);
  final String tag;
  final values = <String, String>{};
  int deletes = 0;
  late final source = SharedCapabilitySource.parse({
    'identity': {
      'share_id': 1,
      'target_id': 2,
      'owner_member_id': 3,
      'book_id': 0,
      'share_type': 'blog',
      'format': 'html',
      'protected': true,
      'blog_type': 'note',
    },
    'title': 'Actual current title',
    'modify_time': '2026-11-11 12:00:00',
    'source_base64': base64Encode(utf8.encode('<p>actual current body</p>')),
    'source_sha256': sha256
        .convert(utf8.encode('<p>actual current body</p>'))
        .toString(),
    'bytes': utf8.encode('<p>actual current body</p>').length,
  });
  late final owner = ProtectedSharedLifetime(
    transport: AnonymousSharedCapability(
      PublicEditLink.parse(
        Uri.parse('https://review.test'),
        'https://review.test/shares/$tag?token=${'a' * 64}',
      ),
      isCurrent: () => true,
      anonymousTestClient: () =>
          MockClient((_) async => throw StateError('No network expected')),
    ),
    isCurrentScope: () => true,
    onDrained: (_) {},
  );
  late final journal = ProtectedSharedJournal(
    capabilityPrincipal: sha256.convert(utf8.encode(tag)).toString(),
    identity: protectedSharedIdentity(source.identity),
    isCurrent: () => owner.current,
    listKeys: () async => values.keys.toList(),
    readValue: (key) async => values[key],
    writeValue: (key, value) async {
      values[key] = value;
    },
    deleteValue: (key) async {
      deletes++;
      values.remove(key);
    },
    flush: () async {},
  );
  late List<ProtectedSharedMarkerMetadata> records;
  Future<void> prepare() async {
    owner.bindJournal(journal);
    await journal.claimUnknown(
      expectedSource: 'c' * 64,
      submittedSource: 'd' * 64,
    );
    records = await journal.loadGroup();
  }

  Widget page() => ProtectedSharedReviewPage(
    owner: owner,
    journal: journal,
    initial: source,
    records: records,
    readFresh: () async => source,
    server: Uri.parse('https://review.test'),
  );
}

Future<void> drainReviewOwners(
  WidgetTester tester,
  List<ProtectedSharedLifetime> owners,
) async {
  // Retirement may already contain futures created by widget dispose in FakeAsync.
  // Keep pumping that zone rather than await those futures in runAsync.
  Object? error;
  StackTrace? trace;
  var done = false;
  Future.wait(owners.map((owner) => owner.retire())).then<void>(
    (_) {
      done = true;
    },
    onError: (Object e, StackTrace s) {
      error = e;
      trace = s;
      done = true;
    },
  );
  for (var i = 0; i < 100 && !done; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  if (!done) {
    throw StateError(
      'Protected shared fixture retirement did not drain in 100 pumps',
    );
  }
  if (error != null) Error.throwWithStackTrace(error!, trace!);
}

void main() {
  // These tests cover review ownership/metadata actions, not an Android platform view.
  // Flutter widget tests otherwise default to Android even on the Linux host.

  testWidgets(
    'confirmation from old owner cannot end a replacement owner record',
    (tester) async {
      final previousPlatform = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      final a = ReviewFixture('owner-a'), b = ReviewFixture('owner-b');
      try {
        await a.prepare();
        await b.prepare();
        var selected = a;
        late StateSetter rebuild;
        await tester.pumpWidget(
          MaterialApp(
            home: StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return selected.page();
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('结束核对记录'),
          300,
          scrollable: find
              .descendant(
                of: find.byType(ProtectedSharedReviewPage),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(find.text('结束核对记录').hitTestable(), findsOneWidget);
        await tester.tap(find.text('结束核对记录'));
        await tester.pumpAndSettle();
        expect(find.text('结束核对记录？'), findsOneWidget);
        rebuild(() => selected = b);
        await tester.pump();
        await tester.tap(find.text('确认结束'));
        await tester.pumpAndSettle();
        expect(a.deletes, 0);
        expect(b.deletes, 0);
        expect(a.values.length, 1);
        expect(b.values.length, 1);
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        try {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          await drainReviewOwners(tester, [a.owner, b.owner]);
        } finally {
          debugDefaultTargetPlatformOverride = previousPlatform;
        }
      }
    },
  );
  testWidgets(
    'explicit current record ending deletes metadata only, never changes source',
    (tester) async {
      final previousPlatform = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      final f = ReviewFixture('current-owner');
      try {
        await f.prepare();
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(
                    context,
                  ).push(MaterialPageRoute<void>(builder: (_) => f.page())),
                  child: const Text('Open review'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open review'));
        await tester.pumpAndSettle();
        expect(find.text('上次编辑正文未保留。'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('结束核对记录'),
          300,
          scrollable: find
              .descendant(
                of: find.byType(ProtectedSharedReviewPage),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(find.text('结束核对记录').hitTestable(), findsOneWidget);
        await tester.tap(find.text('结束核对记录'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('确认结束'));
        await tester.pumpAndSettle();
        expect(f.deletes, 1);
        expect(f.values, isEmpty);
        expect(f.source.document.source, '<p>actual current body</p>');
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        try {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          await drainReviewOwners(tester, [f.owner]);
        } finally {
          debugDefaultTargetPlatformOverride = previousPlatform;
        }
      }
    },
  );
}
