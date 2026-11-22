import 'dart:async';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/features/admin/admin_files_controller.dart';
import 'package:bookstark_flutter/features/admin/admin_files_models.dart';
import 'package:bookstark_flutter/features/admin/admin_files_repository.dart';
import 'support/admin_files_harness.dart';

void main() {
  late AdminFilesHarness h;
  late AdminFilesController c;
  setUp(() {
    h = AdminFilesHarness();
    c = h.scope.own(AdminFilesController(h.repository));
  });
  tearDown(() {
    h.close();
  });
  test(
    'Read failure does not replace failed directory with empty success',
    () async {
      h.intercept = (request) async {
        if (request.url.path.endsWith('/files')) {
          throw StateError('owned failed listing');
        }
        return null;
      };
      expect(await c.load(), false);
      expect(c.listing, isNull);
      expect(c.failure, AdminFilesFailure.read);
      h.intercept = null;
      h.empty = true;
      expect(await c.load(), true);
      expect(c.listing!.items, isEmpty);
      expect(c.failure, isNull);
    },
  );
  test(
    'Background retires plaintext and never adopts a late content response',
    () async {
      await c.load();
      final reached = Completer<void>(), release = Completer<void>();
      h.intercept = (request) async {
        if (request.url.path.endsWith('/content')) {
          reached.complete();
          await release.future;
        }
        return null;
      };
      final task = c.open(h.entry);
      await reached.future;
      c.suspend();
      release.complete();
      expect(await task, false);
      expect(c.original, isNull);
      expect(c.editing, isNull);
      expect(c.listing, isNull);
      expect(c.suspended, true);
      expect(h.mutations, 0);
    },
  );
  test(
    'Known write receipt remains distinct from later directory read failure',
    () async {
      await c.load();
      await c.open(h.entry);
      final baseline = c.original!;
      expect(
        await c.submit(
          AdminFileWritePlan(
            action: AdminFileAction.save,
            path: baseline.path,
            baseline: c.editing,
            content: 'new',
          ),
          baselineContent: baseline.content,
        ),
        true,
      );
      expect(c.receipt, AdminFileAction.save);
      expect(c.original, isNull);
      expect(h.mutations, 1);
      h.intercept = (request) async {
        if (request.url.path.endsWith('/files')) {
          throw StateError('owned refresh failure');
        }
        return null;
      };
      expect(await c.load(), false);
      expect(c.failure, AdminFilesFailure.read);
      expect(c.receipt, AdminFileAction.save);
      expect(h.mutations, 1);
    },
  );
  test(
    'Unknown operation survives background only as metadata; no automatic replay',
    () async {
      await c.load();
      await c.open(h.entry);
      final baseline = c.original!;
      h.dropped = true;
      expect(
        await c.submit(
          AdminFileWritePlan(
            action: AdminFileAction.save,
            path: baseline.path,
            baseline: c.editing,
            content: 'owned secret draft',
          ),
          baselineContent: baseline.content,
        ),
        false,
      );
      expect(c.failure, AdminFilesFailure.unknown);
      expect(h.mutations, 1);
      c.suspend();
      expect(c.original, isNull);
      expect(c.editing, isNull);
      expect(c.repository.unknown!.path, baseline.path);
      c.resumeForReview();
      expect(await c.observe(), true);
      expect(h.mutations, 1);
      c.finishReview();
      expect(c.repository.unknown, isNull);
    },
  );
  test(
    'Cancellation during final fresh ownership check prevents any mutation',
    () async {
      await c.load();
      await c.open(h.entry);
      final baseline = c.original!;
      final reached = Completer<void>(), release = Completer<void>();
      var profileReads = 0;
      h.intercept = (request) async {
        if (request.url.path.endsWith('/profile') && ++profileReads == 3) {
          reached.complete();
          await release.future;
        }
        return null;
      };
      final task = c.submit(
        AdminFileWritePlan(
          action: AdminFileAction.save,
          path: baseline.path,
          baseline: c.editing,
          content: 'new',
        ),
        baselineContent: baseline.content,
      );
      await reached.future;
      c.suspend();
      release.complete();
      expect(await task, false);
      expect(h.mutations, 0);
      expect(c.original, isNull);
    },
  );
  test(
    'Scope owner revocation disposes controller and clears plaintext',
    () async {
      await c.load();
      await c.open(h.entry);
      expect(c.original, isNotNull);
      h.scope.close();
      expect(c.disposed, true);
      expect(c.original, isNull);
      expect(c.editing, isNull);
    },
  );
  test('Actual fresh profile rejection retires an idle open editor', () async {
    await c.load();
    await c.open(h.entry);
    expect(c.original, isNotNull);
    h.role = -1;
    await c.checkOwner();
    expect(h.scope.closed, true);
    expect(c.disposed, true);
    expect(c.original, isNull);
    expect(c.editing, isNull);
    expect(h.mutations, 0);
  });
  test(
    'Failed current-content observation cannot unlock uncertain save replay',
    () async {
      await c.load();
      await c.open(h.entry);
      final baseline = c.original!;
      h.dropped = true;
      await c.submit(
        AdminFileWritePlan(
          action: AdminFileAction.save,
          path: baseline.path,
          baseline: c.editing,
          content: 'new',
        ),
        baselineContent: baseline.content,
      );
      h.intercept = (request) async {
        if (request.url.path.endsWith('/content')) {
          throw const FormatException('owned invalid current text');
        }
        return null;
      };
      expect(await c.observe(), true);
      expect(c.observationContentUnavailable, true);
      expect(c.observedText, isNull);
      expect(c.repository.unknown!.observationRead, false);
      expect(() => c.finishReview(), throwsA(isA<AdminFileReviewRequired>()));
      expect(h.mutations, 1);
    },
  );
  test(
    'Read503 stays a retryable read failure rather than access refusal',
    () async {
      h.intercept = (request) async {
        if (request.url.path.endsWith('/files')) {
          throw ApiFailure(503, 'owned unavailable');
        }
        return null;
      };
      expect(await c.load(), false);
      expect(c.failure, AdminFilesFailure.read);
      expect(c.repository.unknown, isNull);
      expect(h.mutations, 0);
      h.intercept = null;
      expect(await c.load(), true);
      expect(c.listing!.items, isNotEmpty);
    },
  );
}
