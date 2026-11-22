import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:bookstark_flutter/features/admin/admin_files_controller.dart';
import 'package:bookstark_flutter/features/admin/admin_files_models.dart';
import 'support/admin_files_harness.dart';

void main() {
  late AdminFilesHarness h;
  late AdminFilesController c;
  setUp(() {
    h = AdminFilesHarness();
    c = h.scope.own(AdminFilesController(h.repository));
  });
  tearDown(() => h.close());
  Future<void> confirmPriorWrite() async {
    expect(await c.load(), true);
    expect(
      await c.submit(
        AdminFileWritePlan(
          action: AdminFileAction.chmod,
          path: h.entry.path,
          baseline: h.entry,
          mode: '0640',
        ),
      ),
      true,
    );
    expect(c.receipt, AdminFileAction.chmod);
    expect(h.mutations, 1);
  }

  for (final dropped in [true, false]) {
    test(
      'Prior receipt cannot identify a new pending or ${dropped ? 'unknown' : 'refused'} operation as successful',
      () async {
        await confirmPriorWrite();
        final reached = Completer<void>(), release = Completer<void>();
        h.dropped = dropped;
        h.intercept = (request) async {
          if (request.method == 'POST' && request.url.path.endsWith('/copy')) {
            reached.complete();
            await release.future;
            if (!dropped) {
              return http.Response(
                '{"code":1,"message":"owned refused"}',
                409,
                headers: {'content-type': 'application/json'},
              );
            }
          }
          return null;
        };
        final task = c.submit(
          AdminFileWritePlan(
            action: AdminFileAction.copy,
            path: h.entry.path,
            baseline: h.entry,
            target: '/work/owned-second-copy.txt',
          ),
        );
        await reached.future;
        final pendingBusy = c.busy;
        final pendingReceipt = c.receipt;
        release.complete();
        expect(await task, false);
        expect(pendingBusy, true);
        expect(pendingReceipt, isNull);
        expect(c.receipt, isNull);
        expect(
          c.failure,
          dropped ? AdminFilesFailure.unknown : AdminFilesFailure.refused,
        );
        expect(
          h.requests.where(
            (r) => r.method == 'POST' && r.url.path.endsWith('/copy'),
          ),
          hasLength(1),
        );
      },
    );
  }
  test(
    'All bytes sent in a new upload cannot retain the prior confirmed receipt',
    () async {
      await confirmPriorWrite();
      final reached = Completer<void>(), release = Completer<void>();
      h.dropped = true;
      h.intercept = (request) async {
        if (request.method == 'POST' && request.url.path.endsWith('/upload')) {
          reached.complete();
          await release.future;
        }
        return null;
      };
      final task = c.upload('owned-new-upload.bin', 3, Stream.value([1, 2, 3]));
      await reached.future;
      final pendingBusy = c.busy;
      final pendingReceipt = c.receipt;
      final sent = c.transferred;
      release.complete();
      expect(await task, false);
      expect(pendingBusy, true);
      expect(sent, 3);
      expect(pendingReceipt, isNull);
      expect(c.receipt, isNull);
      expect(c.failure, AdminFilesFailure.unknown);
    },
  );
}
