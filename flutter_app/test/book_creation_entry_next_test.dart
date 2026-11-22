import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/books_repository.dart';
import 'package:bookstark_flutter/core/book_draft_vault.dart';
import 'package:bookstark_flutter/core/book_creation_attempt.dart';
import 'package:bookstark_flutter/features/book_creation_entry.dart';
import 'package:bookstark_flutter/features/book_creation_recovery_page.dart';
import 'book_editor_existing_retention_next_test.dart' show Books, Labels;

void main() {
  testWidgets('real book editor Save uses typed create and keeps known ID record', (
    tester,
  ) async {
    final values = <String, String>{};
    var posts = 0, profiles = 0;
    final client = BookstarkClient(
      'https://entry.test',
      transport: MockClient((r) async {
        if (r.method == 'POST' && r.url.path == '/api/books') {
          expect(jsonDecode(r.body), containsPair('book_name', 'Exact'));
          posts++;
          return http.Response(
            jsonEncode({
              'code': 0,
              'data': {
                'book_id': 208,
                'member_id': 7,
                'book_name': 'Exact',
                'description': '',
                'identify': 'generated',
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (r.method == 'GET' && r.url.path == '/api/profile') {
          profiles++;
          return http.Response(
            jsonEncode({
              'code': 0,
              'data': {'member_id': 7},
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        fail('Unexpected creation HTTP method/path: ${r.method} ${r.url.path}');
      }),
    );
    client.restoreSession({
      'token': 'fixture-token',
      'csrf_token': 'fixture-csrf',
    });
    addTearDown(client.close);
    final normal = Books();
    final vault = BookDraftVault(
      namespace: 'ordinary',
      readValue: (k) async => values[k],
      writeValue: (k, v) async {
        values[k] = v;
      },
      deleteValue: (k) async {
        values.remove(k);
      },
    );
    final page = await createRemoteBookEntry(
      client: client,
      scope: BookCreationScope(
        server: 'https://entry.test',
        memberId: 7,
        binding: 'c' * 32,
      ),
      repository: normal,
      labelsRepository: Labels(),
      ordinaryDrafts: vault,
      readValue: (k) async => values[k],
      writeValue: (k, v) async {
        values[k] = v;
      },
      deleteValue: (k) async {
        values.remove(k);
      },
      flush: () async {},
      isCurrent: () => true,
      english: true,
    );
    addTearDown(() => retireRemoteBookEntry(page));
    await tester.pumpWidget(MaterialApp(home: page));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Exact');
    // Execute real HTTP stream cancellation outside WidgetTester fake async.
    // Keep the entire Save path real, and wait for durable known-ID evidence.
    await tester.runAsync(() async {
      await tester.tap(find.text('Save'));
      bool knownStored() {
        return values.values.any((raw) {
          try {
            final value = jsonDecode(raw);
            return value is Map &&
                value['kind'] == 'book' &&
                value['state'] == 'knownID' &&
                value['known_id'] == 208;
          } catch (_) {
            return false;
          }
        });
      }

      for (var tick = 0; tick < 200 && !knownStored(); tick++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(
        knownStored(),
        isTrue,
        reason:
            'Real event loop: profileRequests=$profiles, POSTs=$posts, durableRecordCount=${values.length}',
      );
    });
    // Bound the test by the expected terminal UI, not an indefinitely animated
    // busy indicator. Keep actual HTTP/controller/store; no mocked save shortcut.
    for (
      var tick = 0;
      tick < 200 && find.text('Known book ID').evaluate().isEmpty;
      tick++
    ) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(
      find.byType(BookCreationRecoveryPage),
      findsOneWidget,
      reason:
          'Creation did not reach known ID: profileRequests=$profiles, POSTs=$posts, durableRecordCount=${values.length}',
    );
    await tester.pumpAndSettle();
    expect(profiles, 1);
    expect(posts, 1);
    expect(normal.saves, 0);
    final recovery = tester.widget<BookCreationRecoveryPage>(
      find.byType(BookCreationRecoveryPage),
    );
    expect(recovery.controller.knownDurable, isTrue);
    expect(recovery.controller.attempt!.knownID, 208);
    expect(find.text('Known book ID'), findsWidgets);
  });
  testWidgets('legacy null draft is review-only and opening cannot POST', (
    tester,
  ) async {
    final values = <String, String>{};
    var requests = 0;
    final client = BookstarkClient(
      'https://legacy.test',
      transport: MockClient((_) async {
        requests++;
        throw StateError('Offline');
      }),
    );
    client.restoreSession({'token': 'fixture-token'});
    addTearDown(client.close);
    final vault = BookDraftVault(
      namespace: 'ordinary-legacy',
      readValue: (k) async => values[k],
      writeValue: (k, v) async {
        values[k] = v;
      },
      deleteValue: (k) async {
        values.remove(k);
      },
    );
    await vault.write(
      const BookItem(name: 'Legacy', description: 'Exact original'),
    );
    final page = await createRemoteBookEntry(
      client: client,
      scope: BookCreationScope(
        server: 'https://legacy.test',
        memberId: 7,
        binding: 'd' * 32,
      ),
      repository: Books(),
      labelsRepository: Labels(),
      ordinaryDrafts: vault,
      readValue: (k) async => values[k],
      writeValue: (k, v) async {
        values[k] = v;
      },
      deleteValue: (k) async {
        values.remove(k);
      },
      flush: () async {},
      isCurrent: () => true,
      english: true,
    );
    addTearDown(() => retireRemoteBookEntry(page));
    await tester.pumpWidget(MaterialApp(home: page));
    await tester.pumpAndSettle();
    expect(requests, 0);
    expect((await vault.read(null))!.description, 'Exact original');
    expect(find.text('Save'), findsNothing);
  });
}
