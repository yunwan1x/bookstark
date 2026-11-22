// Prepared tests only. NOT RUN; Fake flush is not Native durability evidence.
import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/books_repository.dart';
import 'package:bookstark_flutter/core/book_creation_attempt.dart';
import 'package:bookstark_flutter/core/book_creation_attempt_store.dart';
import 'package:bookstark_flutter/core/book_creation_controller.dart';
import 'package:bookstark_flutter/core/book_creation_transport.dart';

class Env {
  static int _next = 0;
  final scope = BookCreationScope(
    server: 'https://example.test/mount',
    memberId: 7,
    binding: (++_next).toRadixString(16).padLeft(32, '0'),
  );
  final values = <String, String>{}, events = <String>[];
  bool current = true,
      failPrepare = false,
      failUnknownFlush = false,
      failKnownWrite = false,
      drop = false;
  int posts = 0, reads = 0, writes = 0, flushes = 0;
  BookItem actual = const BookItem(
    id: 208,
    name: 'existing',
    description: 'actual book',
    identify: 'book-existing',
    documentCount: 3,
    labels: ['legacy,value'],
  );
  Future<BookCreateReceipt> Function()? sendHook;
  late final BookCreationAttemptStore store = BookCreationAttemptStore(
    scope: scope,
    attemptKey: 'b' * 32,
    isCurrent: () => current,
    readValue: (key) async => values[key],
    writeValue: (key, value) async {
      writes++;
      final record = BookCreationAttempt.decode(value);
      events.add('write-${record.state.name}');
      if (failKnownWrite && record.state == BookAttemptState.knownID) {
        failKnownWrite = false;
        throw StateError('private storage fault');
      }
      values[key] = value;
    },
    deleteValue: (key) async {
      values.remove(key);
    },
    flush: () async {
      flushes++;
      events.add('flush');
      final raw = values[store.metadataKey];
      if (failUnknownFlush &&
          raw != null &&
          BookCreationAttempt.decode(raw).state ==
              BookAttemptState.submittedUnknown) {
        failUnknownFlush = false;
        throw StateError('private flush fault');
      }
    },
  );
  late final transport = ExactBookCreationTransport(
    scope: scope,
    isCurrent: () => current,
    prepare: (input) async {
      events.add('auth-csrf-ready');
      if (failPrepare) throw const BookCreateNotSubmitted();
      return PreparedBookCreationPost(
        uri: Uri.parse('${scope.server}/api/books'),
        ownerIdentity: scope.identity,
        inputDigest: input.digest,
        send: () async {
          posts++;
          events.add('post');
          if (sendHook != null) return sendHook!();
          if (drop) throw StateError('applied, response dropped');
          return BookCreateReceipt(208);
        },
      );
    },
    read: (id) async {
      reads++;
      return actual;
    },
  );
  BookCreationController controller() =>
      BookCreationController(store: store, transport: transport);
}

BookCreationInput input() => BookCreationInput(
  name: ' exact book ',
  description: '',
  labels: [' team ', '指南'],
);

void main() {
  test(
    'auth/CSRF failure before exact boundary proves not sent; explicit retry only',
    () async {
      final e = Env()..failPrepare = true, c = e.controller();
      addTearDown(c.dispose);
      await c.start(input());
      await c.submit();
      expect(c.phase, BookCreationPhase.notSent);
      expect(e.posts, 0);
      expect(
        BookCreationAttempt.decode(e.values[e.store.metadataKey]!).state,
        BookAttemptState.pending,
      );
      e.failPrepare = false;
      await c.submit();
      expect(e.posts, 1);
      expect(
        e.events.indexOf('auth-csrf-ready'),
        lessThan(e.events.indexOf('write-submittedUnknown')),
      );
      expect(
        e.events.indexOf('write-submittedUnknown'),
        lessThan(e.events.indexOf('post')),
      );
      expect(c.attempt!.knownID, 208);
    },
  );
  test(
    'onSubmit barrier failure sends zero POST and never rolls unknown back to pending',
    () async {
      final e = Env()..failUnknownFlush = true, c = e.controller();
      addTearDown(c.dispose);
      await c.start(input());
      await c.submit();
      expect(e.posts, 0);
      expect(c.phase, BookCreationPhase.unknown);
      await c.submit();
      await c.retryStorage();
      expect(e.posts, 0);
      expect(c.canSubmit, false);
      final cold = e.controller();
      addTearDown(cold.dispose);
      await cold.load();
      expect(cold.phase, BookCreationPhase.unknown);
      await cold.submit();
      expect(e.posts, 0);
    },
  );
  test(
    'applied POST dropped response freezes unknown across cold controller without resend',
    () async {
      final e = Env()..drop = true, c = e.controller();
      addTearDown(c.dispose);
      await c.start(input());
      await c.submit();
      await c.submit();
      expect(e.posts, 1);
      expect(c.phase, BookCreationPhase.unknown);
      final cold = e.controller();
      addTearDown(cold.dispose);
      await cold.load();
      await cold.submit();
      expect(cold.phase, BookCreationPhase.unknown);
      expect(e.posts, 1);
      final persisted = BookCreationAttempt.decode(
        e.values[e.store.metadataKey]!,
      );
      expect(persisted.submitBoundaryArmed, true);
      expect(persisted.input.description, '');
      expect(persisted.input.labels, [' team ', '指南']);
      expect(persisted.input.toJson().keys.toSet(), {
        'name',
        'description',
        'labels',
      });
    },
  );
  test(
    'known positive ID storage failure never recreates, only storage retries',
    () async {
      final e = Env()..failKnownWrite = true, c = e.controller();
      addTearDown(c.dispose);
      await c.start(input());
      await c.submit();
      expect(c.attempt!.knownID, 208);
      expect(c.phase, BookCreationPhase.storageUnconfirmed);
      await c.submit();
      expect(e.posts, 1);
      await c.retryStorage();
      expect(e.posts, 1);
      expect(c.knownDurable, true);
      final cold = e.controller();
      addTearDown(cold.dispose);
      await cold.load();
      await cold.submit();
      expect(cold.attempt!.knownID, 208);
      expect(e.posts, 1);
    },
  );
  test(
    'unknown manual existing adoption needs explicit checkbox and fresh exact fingerprint',
    () async {
      final e = Env()..drop = true, c = e.controller();
      addTearDown(c.dispose);
      await c.start(input());
      await c.submit();
      await c.inspectExisting(208);
      final first = c.review!;
      final writes = e.writes;
      await c.adoptExisting(first, explicitlyConfirmed: false);
      expect(e.writes, writes);
      e.actual = e.actual.copyWith(name: 'changed existing');
      await c.adoptExisting(first, explicitlyConfirmed: true);
      expect(c.phase, BookCreationPhase.unknown);
      expect(c.attempt!.knownID, isNull);
      expect(c.review!.book.name, 'changed existing');
      await c.adoptExisting(c.review!, explicitlyConfirmed: true);
      expect(c.attempt!.knownID, 208);
      expect(c.attempt!.origin, BookIDOrigin.manualExisting);
      expect(c.attempt!.input.name, ' exact book ');
      expect(c.review!.book.labels, ['legacy,value']);
      expect(
        e.posts,
        1,
      ); // No label PUT or metadata update API exists in this flow.
    },
  );
  test(
    'stale pending journal cannot overwrite durable unknown; malformed record is retained',
    () async {
      final e = Env()..drop = true, c = e.controller();
      addTearDown(c.dispose);
      await c.start(input());
      final pending = c.attempt!;
      await c.submit();
      final raw = e.values[e.store.metadataKey];
      await expectLater(
        e.store.put(pending),
        throwsA(isA<BookCreationStorageUnconfirmed>()),
      );
      expect(e.values[e.store.metadataKey], raw);
      e.values[e.store.metadataKey] = '{malformed';
      final cold = e.controller();
      addTearDown(cold.dispose);
      await cold.load();
      await cold.start(input());
      expect(e.values[e.store.metadataKey], '{malformed');
      expect(e.posts, 1);
    },
  );
  test(
    'logout after submission retains old unknown and never writes a new scope',
    () async {
      final e = Env(),
          receipt = Completer<BookCreateReceipt>(),
          entered = Completer<void>();
      e.sendHook = () {
        entered.complete();
        return receipt.future;
      };
      final c = e.controller();
      addTearDown(c.dispose);
      await c.start(input());
      final operation = c.submit();
      await entered.future;
      final writes = e.writes, key = e.store.metadataKey;
      e.current = false;
      receipt.complete(BookCreateReceipt(208));
      await operation;
      expect(e.writes, writes);
      expect(e.values.keys, [key]);
      expect(
        BookCreationAttempt.decode(e.values[key]!).state,
        BookAttemptState.submittedUnknown,
      );
      await expectLater(
        e.store.put(
          BookCreationAttempt(
            key: 'b' * 32,
            scope: e.scope,
            input: input(),
            state: BookAttemptState.pending,
          ),
        ),
        throwsA(isA<BookCreationOwnerRetired>()),
      );
    },
  );
  test(
    'book schema rejects body/unknown fields; does not silently normalize Unicode/labels',
    () {
      final attempt = BookCreationAttempt(
        key: 'b' * 32,
        scope: BookCreationScope(
          server: 'https://example.test',
          memberId: 7,
          binding: 'a' * 32,
        ),
        input: input(),
        state: BookAttemptState.pending,
      );
      final json = jsonDecode(attempt.encode()) as Map;
      (json['input'] as Map)['markdown'] =
          'must never enter a book creation record';
      expect(
        () => BookCreationAttempt.decode(jsonEncode(json)),
        throwsFormatException,
      );
      expect(
        () => BookCreationInput(
          name: 'book',
          description: '',
          labels: ['one,value'],
        ),
        throwsFormatException,
      );
      expect(
        () => BookCreationInput(name: '\ud800', description: '', labels: []),
        throwsFormatException,
      );
    },
  );
  test(
    'known positive BookSaveFailure retains ID without replaying label/update work',
    () async {
      final e = Env(), c = e.controller();
      addTearDown(c.dispose);
      e.sendHook = () async =>
          throw BookSaveFailure(208, StateError('label confirmation failed'));
      await c.start(input());
      await c.submit();
      await c.submit();
      expect(e.posts, 1);
      expect(c.attempt!.knownID, 208);
      expect(c.attempt!.labelsNeedReview, true);
      expect(c.attempt!.origin, BookIDOrigin.postReceipt);
    },
  );

  test(
    'two controllers loaded pending share exclusive submission lease and claim once',
    () async {
      final e = Env(), a = e.controller(), b = e.controller();
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      await a.start(input());
      await b.load();
      final entered = Completer<void>(),
          receipt = Completer<BookCreateReceipt>();
      e.sendHook = () {
        entered.complete();
        return receipt.future;
      };
      final first = a.submit();
      await entered.future;
      await b.submit();
      expect(e.posts, 1);
      receipt.complete(BookCreateReceipt(208));
      await first;
      await b.submit();
      expect(e.posts, 1);
      expect(
        BookCreationAttempt.decode(e.values[e.store.metadataKey]!).knownID,
        208,
      );
    },
  );
  test(
    'strict claim never grants second send for an already unknown marker',
    () async {
      final e = Env(), c = e.controller();
      addTearDown(c.dispose);
      await c.start(input());
      final pending = c.attempt!, one = Object(), two = Object();
      e.store.acquireSubmission(one);
      await e.store.claimSubmission(pending, one);
      e.store.releaseSubmission(one);
      e.store.acquireSubmission(two);
      await expectLater(
        e.store.claimSubmission(pending, two),
        throwsA(isA<BookCreationStorageUnconfirmed>()),
      );
      e.store.releaseSubmission(two);
      expect(e.posts, 0);
      await expectLater(
        e.store.put(pending, expected: pending.unknown()),
        throwsA(isA<BookCreationStorageUnconfirmed>()),
      );
    },
  );
  test(
    'clear tombstone rejects late expected writer and same-key fresh resurrection',
    () async {
      final e = Env(), c = e.controller();
      addTearDown(c.dispose);
      await c.start(input());
      final pending = c.attempt!;
      await c.submit();
      final known = c.attempt!;
      await c.clearKnownRecord();
      expect(e.values, isEmpty);
      await expectLater(
        e.store.put(known, expected: known),
        throwsA(isA<BookCreationStorageUnconfirmed>()),
      );
      await expectLater(
        e.store.put(pending),
        throwsA(isA<BookCreationStorageUnconfirmed>()),
      );
      expect(e.values, isEmpty);
      expect(e.posts, 1);
    },
  );
}
