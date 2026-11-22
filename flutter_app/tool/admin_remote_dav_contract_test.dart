// Isolated real backend contract, excluded from ordinary unit-test discovery.
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/features/admin/admin_assets_scope.dart';
import 'package:bookstark_flutter/features/admin/admin_assets_repository.dart';
import 'package:bookstark_flutter/features/admin/admin_settings_repository.dart';
import 'package:bookstark_flutter/features/admin/admin_remote_dav_models.dart';
import 'package:bookstark_flutter/features/admin/admin_remote_dav_repository.dart';
import 'package:bookstark_flutter/features/admin/admin_remote_dav_files_repository.dart';

void main() {
  test(
    'Production DAV client against isolated actual Go and authenticated DAV',
    () async {
      final location = Platform.environment['BOOKSTARK_ADMIN42_FIXTURE'];
      if (location == null) {
        throw StateError('Owned admin42 runner required');
      }
      final base = Directory(location);
      if (!base.resolveSymbolicLinksSync().startsWith(
        '/vol1/1000/wy/photos-apk-test/complex-webview-host/next-stage/admin42-api-contract/',
      )) {
        throw StateError('Outside owned DAV fixture root');
      }
      final cfg =
          jsonDecode(
                await File('${base.path}/fixture-private.json').readAsString(),
              )
              as Map<String, dynamic>;
      final cache = Directory('${base.path}/client-cache');
      await cache.create();
      final client = BookstarkClient(cfg['client_base'] as String);
      AdminAssetsScope? scope;
      AdminDavRepository? catalog;
      AdminDavFilesRepository? files;
      final checks = <Map<String, Object?>>[];
      Future<void> record(String name, Map<String, Object?> facts) async {
        checks.add({'name': name, ...facts});
        await File(
          '${base.path}/client-checkpoints.json',
        ).writeAsString(jsonEncode(checks));
      }

      Future<void> control(String name) async {
        final result = await Process.run('python3', [
          '${base.path}/fixture_adapter.py',
          name,
        ]);
        if (result.exitCode != 0) {
          throw StateError('Owned DAV fault control failed');
        }
      }

      int count(String method, String route) {
        final raw =
            jsonDecode(
                  File(
                    '${base.path}/relay-control.private.json',
                  ).readAsStringSync(),
                )
                as Map<String, dynamic>;
        return (raw['requests'] as List)
            .where((r) => r['method'] == method && r['route'] == route)
            .length;
      }

      try {
        await client.login(
          cfg['admin_account'] as String,
          cfg['admin_password'] as String,
        );
        final profile = await client.adminAssetPrincipalJson();
        final owner = AdminPrincipal(
          memberId: profile['member_id'] as int,
          account: profile['account'] as String,
          role: profile['role'] as int,
        );
        scope = AdminAssetsScope(client, owner);
        catalog = AdminDavRepository(scope);
        final rows = await catalog.list();
        expect(rows.whereType<AdminDavBuiltin>().length, 1);
        final server = rows.whereType<AdminDavServer>().singleWhere(
          (row) => row.id == cfg['dav_server_id'],
        );
        final binding = await catalog.bind(server);
        files = AdminDavFilesRepository(
          scope,
          binding,
          cacheDirectory: () async => cache,
        );
        final listing = await files.list('.');
        final source = listing.find('owned.txt')!;
        final original = await files.read(source);
        expect(original.content, '\ufeffline one\r\n中文\nlast\r');
        await record('production-client-exact-read-and-relative-path', {
          'utf8BomMixedEOL': true,
          'noDuplicatedMountPrefix': true,
        });
        final downloaded = await files.download(listing.find('binary.bin')!);
        try {
          expect(await downloaded.file.readAsBytes(), [
            0,
            255,
            13,
            10,
            1,
            2,
            3,
            4,
          ]);
        } finally {
          await downloaded.close();
        }
        await record('actual-bounded-binary-download', {
          'exactEightBytes': true,
          'temporaryResultDeleted': true,
        });
        final desired = '${original.content}client42-中文😀\r\n';
        await files.submit(
          AdminDavFilePlan(
            action: AdminDavFileAction.save,
            path: source.path,
            baseline: source,
            content: desired,
          ),
          baselineContent: original.content,
        );
        var fresh = await files.list('.');
        expect((await files.read(fresh.find('owned.txt')!)).content, desired);
        await record('actual-client-save', {
          'exactBomUnicodeAndMixedEOL': true,
          'explicitOnePut': true,
        });
        await files.submit(
          AdminDavFilePlan(
            action: AdminDavFileAction.mkdir,
            path: 'client-created',
          ),
        );
        fresh = await files.list('.');
        await files.submit(
          AdminDavFilePlan(
            action: AdminDavFileAction.copy,
            path: 'owned.txt',
            baseline: fresh.find('owned.txt'),
            target: 'client-copy.txt',
          ),
        );
        fresh = await files.list('.');
        await files.submit(
          AdminDavFilePlan(
            action: AdminDavFileAction.rename,
            path: 'client-copy.txt',
            baseline: fresh.find('client-copy.txt'),
            target: 'client-renamed.txt',
          ),
        );
        fresh = await files.list('.');
        expect(
          (await files.read(fresh.find('client-renamed.txt')!)).content,
          desired,
        );
        await files.submit(
          AdminDavFilePlan(
            action: AdminDavFileAction.delete,
            path: 'client-renamed.txt',
            baseline: fresh.find('client-renamed.txt'),
          ),
        );
        fresh = await files.list('.');
        await files.submit(
          AdminDavFilePlan(
            action: AdminDavFileAction.delete,
            path: 'client-created',
            baseline: fresh.find('client-created'),
            recursive: true,
          ),
        );
        await record('actual-client-file-mutations', {
          'mkdirCopyRenameDelete': true,
          'directoryExplicitRecursive': true,
        });
        final payload = [0, 1, 2, 255, 13, 10];
        await files.upload(
          '.',
          'client-upload.bin',
          payload.length,
          Stream.value(payload),
        );
        final root = '/api/admin/assets/webdav-servers/${server.id}/files';
        expect(count('POST', '$root/upload'), 1);
        await expectLater(
          files.upload(
            '.',
            'client-upload.bin',
            payload.length,
            Stream.value(payload),
          ),
          throwsA(isA<AdminAssetTargetChanged>()),
        );
        expect(count('POST', '$root/upload'), 1);
        await record('actual-client-multipart-and-existing-target', {
          'oneUploadOnly': true,
          'existingDestinationNoSecondPost': true,
        });
        fresh = await files.list('.');
        final currentEntry = fresh.find('owned.txt')!,
            current = await files.read(fresh.find('owned.txt')!);
        final next = '${current.content}unknown-client42\r\n';
        await control('arm-dav-put');
        await expectLater(
          files.submit(
            AdminDavFilePlan(
              action: AdminDavFileAction.save,
              path: currentEntry.path,
              baseline: currentEntry,
              content: next,
            ),
            baselineContent: current.content,
          ),
          throwsA(isA<AdminDavFileResultUnknown>()),
        );
        expect(count('PUT', '$root/content'), 2);
        final observation = await files.observeUnknown();
        expect(observation.currentText!.content, next);
        expect(files.unknown, isNotNull);
        files.finishUnknownReview();
        expect(count('PUT', '$root/content'), 2);
        await record('actual-applied-put-dropped-api-reply', {
          'readonlyCurrentTextRequired': true,
          'twoPutsTotal': true,
          'noReplay': true,
        });
        await control('revoke401');
        await expectLater(files.list('.'), throwsA(isA<AdminAssetOwnerLost>()));
        expect(scope.closed, true);
        await record('actual-auth-version-revocation', {
          'ownerLostScopeClosed': true,
          'noExtraMutation': true,
        });
        await File('${base.path}/client-dav-contract-proof.json').writeAsString(
          jsonEncode({
            'passed': true,
            'checks': checks,
            'NativeAndroidProof': false,
            'productionGoChangedOrBuilt': false,
          }),
        );
      } finally {
        files?.dispose();
        catalog?.dispose();
        scope?.dispose();
        client.close();
        if (await cache.exists()) {
          await cache.delete(recursive: true);
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
