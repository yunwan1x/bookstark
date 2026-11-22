// Owned real Go contract; deliberately outside test/ and never uses production data.
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/features/admin/admin_assets_repository.dart';
import 'package:bookstark_flutter/features/admin/admin_assets_scope.dart';
import 'package:bookstark_flutter/features/admin/admin_settings_repository.dart';
import 'package:bookstark_flutter/features/admin/admin_files_models.dart';
import 'package:bookstark_flutter/features/admin/admin_files_repository.dart';

void main() {
  test(
    'Remote file production client against owned SFTP/shell Go fixtures',
    () async {
      final location = Platform.environment['BOOKSTARK_ADMIN41_FIXTURE'];
      if (location == null) throw StateError('Owned admin41 runner required');
      final base = Directory(location);
      if (!base.resolveSymbolicLinksSync().startsWith(
        '/vol1/1000/wy/photos-apk-test/complex-webview-host/next-stage/admin41-api-contract/',
      )) {
        throw StateError('Contract outside owned fixture root');
      }
      final cfg =
          jsonDecode(
                await File('${base.path}/fixture-private.json').readAsString(),
              )
              as Map<String, dynamic>;
      final cache = Directory('${base.path}/client-cache');
      await cache.create();
      final client = BookstarkClient(cfg['client_base'] as String);
      final scopes = <AdminAssetsScope>[],
          repositories = <AdminFilesRepository>[];
      final checks = <Map<String, Object?>>[];
      const original = '\ufeff中文😀\r\nline two\nlast\r\n';
      Future<void> record(String name, Map<String, Object?> facts) async {
        checks.add({'name': name, ...facts});
        await File(
          '${base.path}/client-checkpoints.json',
        ).writeAsString(jsonEncode(checks));
      }

      Future<void> control(String operation) async {
        final result = await Process.run('python3', [
          '${base.path}/fixture_adapter.py',
          operation,
        ]);
        if (result.exitCode != 0) {
          throw StateError('Owned file fault operation failed');
        }
      }

      int puts(int id) {
        final data =
            jsonDecode(
                  File(
                    '${base.path}/relay-control.private.json',
                  ).readAsStringSync(),
                )
                as Map<String, dynamic>;
        return (data['requests'] as List)
            .where(
              (r) =>
                  r['method'] == 'PUT' &&
                  r['route'] == '/api/admin/assets/ssh-hosts/$id/files/content',
            )
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
        expect(owner.role, 0);
        final catalog = AdminAssetsRepository(client);
        final hosts = await catalog.readHosts(owner);
        catalog.dispose();
        for (final fixture in (cfg['file_hosts'] as List).where(
          (r) => r['auth'] == 'password',
        )) {
          final host = hosts.singleWhere((row) => row.id == fixture['id']);
          final scope = AdminAssetsScope(client, owner);
          scopes.add(scope);
          final repo = AdminFilesRepository(
            scope,
            host,
            cacheDirectory: () async => cache,
          );
          repositories.add(repo);
          final root = fixture['cwd'] as String,
              mode = fixture['mode'] as String;
          final listing = await repo.list(root);
          expect(listing.truncated, false);
          expect(listing.items.any((e) => e.name.contains('\n')), true);
          final entry = listing.items.singleWhere((e) => e.name == 'owned.txt');
          final source = await repo.read(entry);
          expect(source.content, original);
          final oversize = listing.items.singleWhere(
            (e) => e.name == 'oversize.txt',
          );
          await expectLater(repo.read(oversize), throwsFormatException);
          final binary = listing.items.singleWhere(
            (e) => e.name == 'binary.bin',
          );
          final file = await repo.download(binary);
          try {
            expect(await file.file.readAsBytes(), [0, 255, 13, 10, 1, 2, 3, 4]);
          } finally {
            await file.close();
          }
          final desired = '\ufeffclient 中文😀\r\nmixed\nlast\r\n';
          await repo.submit(
            AdminFileWritePlan(
              action: AdminFileAction.save,
              path: entry.path,
              baseline: entry,
              content: desired,
            ),
            baselineContent: source.content,
          );
          final after = (await repo.list(root)).find(entry.path)!;
          expect((await repo.read(after)).content, desired);
          final directory = '$root/client-owned';
          await repo.submit(
            AdminFileWritePlan(action: AdminFileAction.mkdir, path: directory),
          );
          final upload = utf8.encode('owned upload 中文😀\r\n');
          await repo.upload(
            directory,
            'upload.txt',
            upload.length,
            Stream.value(upload),
          );
          final uploaded = (await repo.list(directory)).items.single;
          final downloaded = await repo.download(uploaded);
          try {
            expect(await downloaded.file.readAsBytes(), upload);
          } finally {
            await downloaded.close();
          }
          final renamed = '$directory/renamed.txt';
          await repo.submit(
            AdminFileWritePlan(
              action: AdminFileAction.rename,
              path: uploaded.path,
              baseline: uploaded,
              target: renamed,
            ),
          );
          final row = (await repo.list(directory)).find(renamed)!;
          await repo.submit(
            AdminFileWritePlan(
              action: AdminFileAction.chmod,
              path: renamed,
              baseline: row,
              mode: '0600',
            ),
          );
          final changed = (await repo.list(directory)).find(renamed)!;
          expect(changed.mode, '0600');
          await repo.submit(
            AdminFileWritePlan(
              action: AdminFileAction.delete,
              path: renamed,
              baseline: changed,
            ),
          );
          expect((await repo.list(directory)).items, isEmpty);
          final folder = (await repo.list(root)).find(directory)!;
          await repo.submit(
            AdminFileWritePlan(
              action: AdminFileAction.delete,
              path: directory,
              baseline: folder,
              recursive: true,
            ),
          );
          expect((await repo.list(root)).find(directory), isNull);
          final many = await repo.list('$root/many');
          expect(many.truncated, true);
          expect(many.items, hasLength(1000));
          await record('actual-client-$mode', {
            'actualProductionClientRepository': true,
            'hostID': host.id,
            'readSavePreserveBOMAndMixedEOL': true,
            'downloadUploadExactBytes': true,
            'renamePermissionsExplicitDelete': true,
            'truncation1000': true,
            'oversizeRejectedFromStat': true,
          });
        }
        final fixture = (cfg['file_hosts'] as List).firstWhere(
          (r) => r['mode'] == 'sftp' && r['auth'] == 'password',
        );
        final host = hosts.singleWhere((row) => row.id == fixture['id']);
        final scope = AdminAssetsScope(client, owner);
        scopes.add(scope);
        final repo = AdminFilesRepository(
          scope,
          host,
          cacheDirectory: () async => cache,
        );
        repositories.add(repo);
        final root = fixture['cwd'] as String;
        final entry = (await repo.list(
          root,
        )).items.singleWhere((e) => e.name == 'owned.txt');
        final before = await repo.read(entry),
            desired = '${before.content}uncertain\r\n';
        final originalPuts = puts(host.id);
        await control('arm-file-put');
        await expectLater(
          repo.submit(
            AdminFileWritePlan(
              action: AdminFileAction.save,
              path: entry.path,
              baseline: entry,
              content: desired,
            ),
            baselineContent: before.content,
          ),
          throwsA(isA<AdminFileResultUnknown>()),
        );
        expect(puts(host.id), originalPuts + 1);
        final observed = await repo.observeUnknown();
        expect(observed.currentText!.content, desired);
        expect(repo.unknown!.observationRead, true);
        expect(puts(host.id), originalPuts + 1);
        repo.finishUnknownReview();
        await record('actual-client-unknown-save', {
          'appliedPutThenResponseDropped': true,
          'currentTextReadOnlyObservationExact': true,
          'oneActualPutNoReplay': true,
          'observationNotOldReceipt': true,
        });
        final current = (await repo.list(root)).find(entry.path)!;
        final currentText = await repo.read(current);
        final next = '${currentText.content}confirmed\r\n';
        await control('arm-file-read-after-write');
        await repo.submit(
          AdminFileWritePlan(
            action: AdminFileAction.save,
            path: current.path,
            baseline: current,
            content: next,
          ),
          baselineContent: currentText.content,
        );
        final knownPuts = puts(host.id);
        await expectLater(repo.list(root), throwsA(isA<ApiFailure>()));
        final retried = (await repo.list(root)).find(entry.path)!;
        expect((await repo.read(retried)).content, next);
        expect(puts(host.id), knownPuts);
        await record('actual-client-confirmed-write-read-failure', {
          'putConfirmedSeparately': true,
          'followingRead503ThenExplicitReadRetry': true,
          'noWriteReplay': true,
        });
        await File(
          '${base.path}/client-files-contract-proof.json',
        ).writeAsString(
          jsonEncode({
            'passed': true,
            'checks': checks,
            'NativeAndroidProof': false,
            'actualSftpAndShellClientInterop': true,
            'backendKnownStreamTruncationNotAcceptedByClient': true,
          }),
        );
      } finally {
        for (final repo in repositories) {
          repo.dispose();
        }
        for (final scope in scopes) {
          scope.dispose();
        }
        client.close();
        if (await cache.exists()) await cache.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(seconds: 180)),
  );
}
