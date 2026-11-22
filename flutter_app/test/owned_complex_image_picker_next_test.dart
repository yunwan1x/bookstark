import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/native_local_article_attachment_picker.dart';
import 'package:bookstark_flutter/core/owned_complex_resource_lease.dart';
import 'package:bookstark_flutter/core/owned_complex_image_upload_journal.dart';
import 'package:bookstark_flutter/core/owned_complex_image_upload_controller.dart';
import 'package:bookstark_flutter/core/owned_complex_image_picker_action.dart';
import 'package:bookstark_flutter/core/secure_record_store.dart';

void main() {
  final bytes = Uint8List.fromList(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aN3sAAAAASUVORK5CYII=',
    ),
  );
  for (final mode in [
    'cancel',
    'decline',
    'confirm',
    'retire-during-confirm',
  ]) {
    test(
      'real SAF inbox image action $mode retains source without implicit insertion or Save',
      () async {
        final temporary = await Directory.systemTemp.createTemp(
          'owned-image-action-',
        );
        final id = ''.padLeft(32, 'a'),
            hash = crypto.sha256.convert(bytes).toString();
        final inbox = Directory(
          '${temporary.path}/local-article-attachment-inbox-v1',
        );
        await inbox.create();
        final copied = File('${inbox.path}/$id.attachment');
        await copied.writeAsBytes(bytes, flush: true);
        final records = <String, String>{};
        var current = true,
            requests = 0,
            posts = 0,
            releases = 0,
            handoffs = 0,
            resumes = 0;
        final native = NativeLocalArticleAttachmentPicker(
          imagesOnly: true,
          identity: () => id,
          cacheDirectory: () async => temporary,
          invoke: (method, args) async {
            expect(args['id'], id);
            if (method == 'pick') {
              expect(args, {'id': id, 'imagesOnly': true});
              if (mode == 'cancel') return {'format': 1, 'cancelled': true};
              return {
                'format': 1,
                'cancelled': false,
                'id': id,
                'bytes': bytes.length,
                'sha256': hash,
                'name': 'actual.png',
              };
            }
            if (method == 'cancel') return {'format': 1, 'cancelled': true};
            if (method == 'release') {
              releases++;
              if (await copied.exists()) await copied.delete();
              return {'format': 1, 'released': id};
            }
            throw StateError('Unexpected native picker operation');
          },
        );
        late OwnedComplexImageUploadJournal journal;
        final client =
            BookstarkClient(
              'https://owned.test/prefix',
              transport: MockClient((request) async {
                requests++;
                if (request.url.path == '/prefix/api/profile') {
                  return http.Response(
                    jsonEncode({
                      'code': 0,
                      'data': {'member_id': 7},
                    }),
                    200,
                    headers: {'content-type': 'application/json'},
                  );
                }
                expect(request.method, 'POST');
                expect(request.url.path, '/prefix/api/uploads');
                expect(
                  (await journal.read())!.phase,
                  OwnedImageUploadPhase.unknown,
                );
                posts++;
                return http.Response(
                  jsonEncode({
                    'code': 0,
                    'data': {'id': 27, 'url': '/upload-files/a.png'},
                  }),
                  200,
                  headers: {'content-type': 'application/json'},
                );
              }),
            )..restoreSession({
              'token': 'fixture-only',
              'csrf_token': 'fixture-csrf',
            });
        final lease = OwnedComplexResourceLease(
          client: client,
          memberId: 7,
          resourceId: 9,
          bookId: 0,
          note: true,
          kind: ComplexEditorKind.richdoc,
          namespace: 'space',
          isCurrentScope: () => current,
        );
        final store = SecureRecordStore(
          prefix: OwnedComplexImageUploadJournal.prefix,
          namespace: ''.padLeft(64, 'b'),
          readValue: (k) async => records[k],
          writeValue: (k, v) async {
            records[k] = v;
          },
          deleteValue: (k) async {
            records.remove(k);
          },
        );
        journal = OwnedComplexImageUploadJournal(
          store: store,
          bindingId: lease.identity,
          flush: () async {},
        );
        final controller = OwnedComplexImageUploadController(
          journal: journal,
          lease: lease,
          validateReceipt: (_) => (
            id: 27,
            url: Uri.parse('https://owned.test/prefix/upload-files/a.png'),
          ),
        );
        await controller.open();
        final action = OwnedComplexImagePickerAction(
          controller: controller,
          lease: lease,
          picker: native,
        );
        final entered = Completer<void>(), choice = Completer<bool>();
        try {
          final work = action.pickAndUpload(
            preparePickerHandoff: () async {
              handoffs++;
              expect(requests, 0);
            },
            resumeEditor: () async {
              resumes++;
            },
            verifyFreshBinding: () async => current,
            confirm: (selected) async {
              expect(selected.name, 'actual.png');
              expect(selected.width, 1);
              expect(selected.height, 1);
              if (mode == 'retire-during-confirm') {
                entered.complete();
                return choice.future;
              }
              return mode == 'confirm';
            },
          );
          if (mode == 'retire-during-confirm') {
            final failure = expectLater(
              work,
              throwsA(isA<OwnedComplexResourceRetired>()),
            );
            await entered.future;
            current = false;
            await action.retireAndDrain();
            choice.complete(true);
            await failure;
            expect(requests, 0);
            expect(resumes, 0);
            expect(await journal.read(), isNull);
          } else {
            final result = await work;
            expect(
              result,
              mode == 'confirm'
                  ? OwnedImagePickResult.confirmedUrl
                  : OwnedImagePickResult.cancelled,
            );
            expect(resumes, 1);
            expect(posts, mode == 'confirm' ? 1 : 0);
            expect(requests, mode == 'confirm' ? 2 : 0);
            expect(
              (await journal.read())?.phase,
              mode == 'confirm' ? OwnedImageUploadPhase.confirmedUrl : null,
            );
          }
          expect(handoffs, 1);
          expect(releases, mode == 'cancel' ? 0 : 1);
          // No insertion callback exists in this action: new runtime insertion stays explicit.
        } finally {
          await action.retireAndDrain();
          client.close();
          if (await temporary.exists()) await temporary.delete(recursive: true);
        }
      },
    );
  }
}
