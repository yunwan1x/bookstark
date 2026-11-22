// Independent resource-read verification of the owned Android settings fixture.
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/content_password_repository.dart';
import 'package:bookstark_flutter/core/notes_repository.dart';
import 'package:bookstark_flutter/core/public_edit_link.dart';
import 'package:bookstark_flutter/core/public_edit_repository.dart';
import 'package:bookstark_flutter/core/public_share_models.dart';
import 'package:bookstark_flutter/core/public_shares_repository.dart';
import 'package:bookstark_flutter/core/public_notes_repository.dart';
import 'package:bookstark_flutter/core/share_settings_repository.dart';

void main() {
  test(
    'verify actual Android settings results without modifying resources',
    () async {
      final path = Platform.environment['BOOKSTARK_ANDROID_FIXTURE_CONFIG'];
      final phase = Platform.environment['BOOKSTARK_ANDROID_VERIFY_PHASE'];
      if (path == null ||
          !path.startsWith(
            '/vol1/1000/wy/photos-apk-test/bookstark-flutter/android-live-fixture/',
          ) ||
          !{'changed', 'withdrawn'}.contains(phase)) {
        throw StateError(
          'Owned Android fixture and an explicit verification phase required',
        );
      }
      final cfg = Map<String, Object?>.from(
        jsonDecode(await File(path).readAsString()) as Map,
      );
      final base = Uri.parse(cfg['local_base'] as String);
      if (cfg['fixture'] != true ||
          cfg['seeded'] != true ||
          base.scheme != 'http' ||
          base.host != '127.0.0.1') {
        throw StateError('Verification restricted to owned loopback fixture');
      }
      final owner = BookstarkClient(base.toString()),
          anonymous = BookstarkClient(base.toString());
      try {
        await owner.login(cfg['account'] as String, cfg['password'] as String);
        final id = cfg['protected_id'] as int,
            bodyPassword = '${cfg['share_password']}-updated';
        final passwords = RemoteContentPasswordRepository(owner),
            settings = RemoteShareSettingsRepository(owner);
        expect((await passwords.read(id)).protected, isTrue);
        await passwords.verify(id, bodyPassword);
        final actual = await RemoteNotesRepository(
          owner,
        ).unlock(id, bodyPassword);
        expect(
          actual.content,
          '# Native protected reader\n\nPassword verified content.',
        );
        final reference = PublicShareReference(
          base,
          cfg['protected_identify'] as String,
        );
        final timeline = await RemotePublicNotesRepository(anonymous).load(1);
        final proof = <String, Object?>{
          'phase': phase,
          'noResourceWrites': true,
          'actualProtectedId': id,
          'newPasswordActuallyVerified': true,
          'bodySHA256': sha256.convert(utf8.encode(actual.content)).toString(),
        };
        final target = OwnerShareTarget(
          kind: PublicShareKind.blog,
          id: id,
          title: 'fixture',
        );
        if (phase == 'changed') {
          expect(await settings.status(target), isTrue);
          final locked = timeline.items.singleWhere((item) => item.id == id);
          expect(locked.locked, isTrue);
          expect(locked.preview, isEmpty);
          expect(locked.labels, isEmpty);
          final original = Uri.parse(cfg['protected_edit_url'] as String);
          final link = PublicEditLink.parse(
            base,
            reference.canonicalUri.replace(query: original.query).toString(),
          );
          var forbidden = false;
          try {
            await RemotePublicEditRepository(anonymous).read(link);
          } on ApiFailure catch (e) {
            forbidden = e.status == 403;
          }
          expect(forbidden, isTrue);
          proof.addAll({
            'published': true,
            'oldEditingTokenForbidden': true,
            'timelineBodyAndLabelsMasked': true,
          });
        } else {
          expect(await settings.status(target), isFalse);
          expect(timeline.items, isEmpty);
          var missing = false;
          try {
            await RemotePublicSharesRepository(anonymous).load(reference);
          } on ApiFailure catch (e) {
            missing = e.status == 404;
          }
          expect(missing, isTrue);
          final child = cfg['child_id'] as int, book = cfg['book_id'] as int;
          expect(
            await settings.status(
              OwnerShareTarget(
                kind: PublicShareKind.document,
                id: child,
                title: 'fixture',
              ),
            ),
            isTrue,
          );
          expect(
            await settings.status(
              OwnerShareTarget(
                kind: PublicShareKind.book,
                id: book,
                title: 'fixture',
              ),
            ),
            isTrue,
          );
          proof.addAll({
            'protectedShareWithdrawn': true,
            'oldPublicLink404': true,
            'timelineEmpty': true,
            'childDocumentActualId': child,
            'childDocumentPublished': true,
            'wholeBookActualId': book,
            'wholeBookPublished': true,
          });
        }
        final file = File(
          '/vol1/1000/wy/bookstark/docs/flutter-rewrite/validation/2026-11-05-settings-android-$phase-proof.json',
        );
        await file.writeAsString(
          '${const JsonEncoder.withIndent('  ').convert(proof)}\n',
        );
      } finally {
        owner.close();
        anonymous.close();
      }
    },
  );
}
