import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/owned_complex_resource_lease.dart';
import 'package:bookstark_flutter/core/owned_complex_image_upload_journal.dart';
import 'package:bookstark_flutter/core/owned_complex_image_upload_controller.dart';
import 'package:bookstark_flutter/core/prepared_owned_image_upload.dart';
import 'package:bookstark_flutter/core/secure_record_store.dart';

void main() {
  const binding =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const hash =
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
  final url = Uri.parse(
    'https://owned.test/prefix/upload-files/editor/example.png',
  );
  var index = 0;
  ({
    OwnedComplexImageUploadController controller,
    OwnedComplexImageUploadJournal journal,
    BookstarkClient client,
  })
  fixture(
    Map<String, String> values, {
    Future<void> Function()? flush,
    String? namespace,
  }) {
    final client = BookstarkClient('https://owned.test/prefix');
    client.restoreSession({'token': 'fixture-only'});
    final lease = OwnedComplexResourceLease(
      client: client,
      memberId: 1,
      resourceId: 8,
      bookId: 0,
      note: true,
      kind: ComplexEditorKind.richdoc,
      namespace: 'space',
      isCurrentScope: () => true,
    );
    final store = SecureRecordStore(
      prefix: OwnedComplexImageUploadJournal.prefix,
      namespace: crypto.sha256
          .convert(utf8.encode(namespace ?? 'case-${index++}'))
          .toString(),
      readValue: (k) async => values[k],
      writeValue: (k, v) async {
        values[k] = v;
      },
      deleteValue: (k) async {
        values.remove(k);
      },
    );
    final journal = OwnedComplexImageUploadJournal(
      store: store,
      bindingId: binding,
      flush: flush ?? () async {},
    );
    final controller = OwnedComplexImageUploadController(
      journal: journal,
      lease: lease,
      validateReceipt: (_) => (id: 27, url: url),
    );
    addTearDown(() async {
      await controller.retireAndDrain();
      client.close();
    });
    return (controller: controller, journal: journal, client: client);
  }

  test(
    'unknown is durable before one send and cold open cannot replay',
    () async {
      final data = <String, String>{};
      final f = fixture(data, namespace: 'cold');
      await f.controller.open();
      var sends = 0;
      final p = PreparedOwnedImageUpload(
        uri: Uri.parse('https://owned.test/prefix/api/uploads'),
        inputSHA256: hash,
        beforeSubmit: () {},
        abort: () {},
        send: () async {
          sends++;
          expect(
            (await f.journal.read())!.phase,
            OwnedImageUploadPhase.unknown,
          );
          throw StateError('Response lost');
        },
      );
      await expectLater(f.controller.upload(p), throwsStateError);
      expect(sends, 1);
      await f.controller.retireAndDrain();
      final cold = fixture(data, namespace: 'cold');
      await cold.controller.open();
      expect(cold.controller.record!.phase, OwnedImageUploadPhase.unknown);
      expect(cold.controller.canUpload, false);
      var second = 0;
      await expectLater(
        cold.controller.upload(
          PreparedOwnedImageUpload(
            uri: p.uri,
            inputSHA256: hash,
            beforeSubmit: () {},
            abort: () {},
            send: () async {
              second++;
              return {};
            },
          ),
        ),
        throwsStateError,
      );
      expect(second, 0);
    },
  );
  test(
    'known receipt storage failure retries only storage then explicit insertion',
    () async {
      final data = <String, String>{};
      var flushes = 0;
      final f = fixture(
        data,
        flush: () async {
          if (++flushes == 2) throw StateError('Flush failed');
        },
      );
      await f.controller.open();
      var sends = 0, inserts = 0, checks = 0;
      await expectLater(
        f.controller.upload(
          PreparedOwnedImageUpload(
            uri: Uri.parse('https://owned.test/prefix/api/uploads'),
            inputSHA256: hash,
            beforeSubmit: () {},
            abort: () {},
            send: () async {
              sends++;
              return {};
            },
          ),
        ),
        throwsStateError,
      );
      expect(f.controller.record!.phase, OwnedImageUploadPhase.confirmedUrl);
      await f.controller.retryKnownStorage();
      expect(sends, 1);
      await f.controller.insert(
        verifyFreshBinding: () async {
          checks++;
          return true;
        },
        insertIntoActualEngine: (u) async {
          expect(u, url);
          inserts++;
        },
      );
      expect(checks, 1);
      expect(inserts, 1);
      expect(sends, 1);
      expect((await f.journal.read())!.phase, OwnedImageUploadPhase.inserted);
      await f.controller.dismissInserted();
      expect(await f.journal.read(), isNull);
    },
  );
  test(
    'retirement during marker flush prevents POST and retains unknown',
    () async {
      final data = <String, String>{};
      final entered = Completer<void>(), release = Completer<void>();
      final f = fixture(
        data,
        flush: () async {
          entered.complete();
          await release.future;
        },
      );
      await f.controller.open();
      var sends = 0;
      final work = f.controller.upload(
        PreparedOwnedImageUpload(
          uri: Uri.parse('https://owned.test/prefix/api/uploads'),
          inputSHA256: hash,
          beforeSubmit: () {},
          abort: () {},
          send: () async {
            sends++;
            return {};
          },
        ),
      );
      final assertion = expectLater(work, throwsStateError);
      await entered.future;
      f.controller.retire();
      release.complete();
      await assertion;
      expect(sends, 0);
      expect((await f.journal.read())!.phase, OwnedImageUploadPhase.unknown);
    },
  );
  test(
    'fresh source rejection inserts nothing and keeps confirmed URL',
    () async {
      final f = fixture(<String, String>{});
      await f.controller.open();
      await f.controller.upload(
        PreparedOwnedImageUpload(
          uri: Uri.parse('https://owned.test/prefix/api/uploads'),
          inputSHA256: hash,
          beforeSubmit: () {},
          abort: () {},
          send: () async => {},
        ),
      );
      var inserts = 0;
      await expectLater(
        f.controller.insert(
          verifyFreshBinding: () async => false,
          insertIntoActualEngine: (_) async {
            inserts++;
          },
        ),
        throwsStateError,
      );
      expect(inserts, 0);
      expect(f.controller.record!.phase, OwnedImageUploadPhase.confirmedUrl);
    },
  );
  test(
    'explicit existing choice does not reconcile or clear an unknown POST',
    () async {
      final f = fixture(<String, String>{});
      final unknown = OwnedImageUploadRecord(
        bindingId: binding,
        inputSHA256: hash,
        phase: OwnedImageUploadPhase.unknown,
      );
      await f.journal.write(unknown);
      await f.controller.open();
      var inserts = 0, choiceChecks = 0, sourceChecks = 0;
      await f.controller.insertExisting(
        url: url,
        verifyFreshChoice: () async {
          choiceChecks++;
          return true;
        },
        verifyFreshBinding: () async {
          sourceChecks++;
          return true;
        },
        insertIntoActualEngine: (u) async {
          expect(u, url);
          inserts++;
        },
      );
      expect(inserts, 1);
      expect(choiceChecks, 1);
      expect(sourceChecks, 1);
      expect((await f.journal.read())!.encode(), unknown.encode());
      expect(f.controller.canUpload, false);
    },
  );
}
