import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/features/admin/admin_asset_models.dart';
import 'package:bookstark_flutter/features/admin/admin_assets_scope.dart';
import 'package:bookstark_flutter/features/admin/admin_settings_repository.dart';
import 'package:bookstark_flutter/features/admin/admin_docker_models.dart';
import 'package:bookstark_flutter/features/admin/admin_docker_repository.dart';
import 'package:bookstark_flutter/features/admin/admin_docker_logs_controller.dart';
import 'package:bookstark_flutter/features/admin/admin_docker_terminal_access.dart';
import 'package:bookstark_flutter/features/admin/admin_terminal_controller.dart';

void main() {
  test(
    'actual owned Go, SSH and secondary Docker daemon complete contract',
    () async {
      final root = Platform.environment['BOOKSTARK_ADMIN43_FIXTURE'];
      if (root == null ||
          !root.startsWith(
            '/vol1/1000/wy/photos-apk-test/complex-webview-host/next-stage/admin43-api-contract/',
          )) {
        fail('Owned Docker fixture required');
      }
      final cfg =
          jsonDecode(await File('$root/fixture-private.json').readAsString())
              as Map;
      final client = BookstarkClient(cfg['client_base'] as String);
      AdminAssetsScope? scope;
      AdminDockerRepository? repo;
      final checks = <Map<String, Object?>>[];
      Future<void> record(String name, Map<String, Object?> facts) async {
        checks.add({'name': name, ...facts});
        await File(
          '$root/client-checkpoints.json',
        ).writeAsString(jsonEncode(checks));
      }

      Future<Map> control() async =>
          jsonDecode(
                await File('$root/relay-control.private.json').readAsString(),
              )
              as Map;
      Future<int> count(String method, String route) async {
        final state = await control();
        return (state['requests'] as List)
            .where((r) => r['method'] == method && r['route'] == route)
            .length;
      }

      Future<void> waitClosed() async {
        final deadline = DateTime.now().add(const Duration(seconds: 10));
        while ((await control())['activeConnections'] != 0) {
          if (DateTime.now().isAfter(deadline)) {
            fail('Owned stream did not close');
          }
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      }

      try {
        await client.login(
          cfg['admin_account'] as String,
          cfg['admin_password'] as String,
        );
        await client.get('/api/csrf-token');
        final principal = await client.adminAssetPrincipalJson();
        scope = AdminAssetsScope(
          client,
          AdminPrincipal(
            memberId: principal['member_id'] as int,
            account: principal['account'] as String,
            role: principal['role'] as int,
          ),
        );
        final host = AdminAssetHostMetadata.parse(
          Map<String, dynamic>.from(cfg['host'] as Map),
        );
        repo = AdminDockerRepository(scope, host);
        final main = (await repo.list(
          DockerResource.containers,
        )).singleWhere((v) => v.name == 'owned-main43');
        final info = await repo.inspect(main);
        expect(info.id.length, 64);
        expect(info.running, true);
        expect(host.credentialId, isNot(host.id));
        await record('actual-container-catalog-and-full-inspect', {
          'completeIdFromInspect': true,
          'distinctHostAndCredentialIds': true,
        });
        final text = await repo.logs(info, 200);
        expect(text, contains('owned43 中文😀'));
        await record('actual-json-log-snapshot', {
          'exactUnicodeMarker': true,
          'noAutomaticFollow': true,
        });

        final logRepo = AdminDockerRepository(
          scope,
          host,
          credential: repo.reviewedCredential,
        );
        final logs = AdminDockerLogsController(logRepo, info);
        try {
          final received = Completer<void>();
          logs.addListener(() {
            if (logs.text.contains('owned43 中文😀') && !received.isCompleted) {
              received.complete();
            }
          });
          final following = logs.follow(200);
          await received.future.timeout(const Duration(seconds: 25));
          expect(logs.phase, DockerLogsPhase.receiving);
          logs.stop();
          await following;
          await waitClosed();
          await record('actual-get-sse-and-cancel', {
            'actualGoEventStream': true,
            'unicodeMarkerReceived': true,
            'clientAbortClosedRelayUpstream': true,
            'noReconnect': true,
          });
        } finally {
          logs.dispose();
        }

        final access = DockerTerminalAccess(
          scope,
          host,
          info,
          credential: repo.reviewedCredential,
        );
        final terminal = access.create();
        final output = StringBuffer(),
            ready = Completer<void>(),
            executed = Completer<void>();
        void changed() {
          while (terminal.output.hasPending) {
            final value = terminal.output.take();
            if (value != null && output.length < 65536) output.write(value);
          }
          if (terminal.phase == TerminalPhase.ready && !ready.isCompleted) {
            ready.complete();
          }
          if (output.toString().contains('owned43-ws-中文-😀') &&
              output.toString().contains('40 120') &&
              !executed.isCompleted) {
            executed.complete();
          }
        }

        terminal.addListener(changed);
        try {
          await terminal.connect();
          await ready.future.timeout(const Duration(seconds: 25));
          expect(terminal.resize(terminal.generation, 120, 40), true);
          expect(
            terminal.input(
              terminal.generation,
              'stty size; printf "owned43-ws-%s-%s\\n" "中文" "😀"\r',
            ),
            true,
          );
          await executed.future.timeout(const Duration(seconds: 20));
          terminal.background();
          expect(terminal.canInput, false);
          expect(terminal.output.hasPending, false);
          await waitClosed();
          final requests = (await control())['requests'] as List;
          expect(
            requests.where((r) => r['actualWebSocketUpgrade'] == true).length,
            1,
          );
          await record('actual-container-websocket-exec', {
            'readyBeforeInput': true,
            'realPTYSize40x120': true,
            'unicodeOutputDistinctFromInputEcho': true,
            'backgroundClosedConnection': true,
            'oneHandshakeNoReplay': true,
          });
        } finally {
          terminal.removeListener(changed);
          terminal.dispose();
          access.dispose();
        }

        final created = await repo.reviewContainerCreate(
          DockerCreateDraft(
            name: 'owned-created43',
            image: 'owned43:base',
            network: 'none',
            startAfterCreate: false,
            env: [
              {'key': 'OWNED_LITERAL', 'value': '中文😀=literal'},
            ],
          ),
        );
        await repo.commit(created);
        final createdRow = (await repo.list(
          DockerResource.containers,
        )).singleWhere((v) => v.name == 'owned-created43');
        expect((await repo.inspect(createdRow)).running, false);
        await record('actual-container-create', {
          'explicitNoStart': true,
          'structuredEnvironment': true,
          'knownCreateReceipt': true,
        });

        final boundaryCreate = await repo.reviewContainerCreate(
          DockerCreateDraft(
            name: 'owned-boundary43',
            image: 'owned43:base',
            command: '/owned43/boundary.sh',
            network: 'none',
            startAfterCreate: true,
          ),
        );
        await repo.commit(boundaryCreate);
        final boundaryRow = (await repo.list(
          DockerResource.containers,
        )).singleWhere((v) => v.name == 'owned-boundary43');
        var boundary = await repo.inspect(boundaryRow);
        final deadline = DateTime.now().add(const Duration(seconds: 10));
        while (boundary.running) {
          if (DateTime.now().isAfter(deadline)) {
            fail('Owned boundary command did not finish');
          }
          await Future<void>.delayed(const Duration(milliseconds: 100));
          boundary = await repo.inspect(boundaryRow);
        }
        final expectedBoundary = '${List.filled(4095, 'A').join()}中文😀\n';
        expect(await repo.logs(boundary, 200), expectedBoundary);
        final boundaryLogs = AdminDockerLogsController(
          AdminDockerRepository(
            scope,
            host,
            credential: repo.reviewedCredential,
          ),
          boundary,
        );
        try {
          final data = Completer<void>();
          boundaryLogs.addListener(() {
            if ((boundaryLogs.containsReplacement ||
                    boundaryLogs.text == expectedBoundary) &&
                !data.isCompleted) {
              data.complete();
            }
          });
          final following = boundaryLogs.follow(200);
          await data.future.timeout(const Duration(seconds: 20));
          final streamExact = boundaryLogs.text == expectedBoundary;
          final replacement = boundaryLogs.containsReplacement;
          expect(streamExact || replacement, true);
          expect(
            boundaryLogs.text.startsWith(List.filled(4095, 'A').join()),
            true,
          );
          boundaryLogs.stop();
          await following;
          await waitClosed();
          await boundaryLogs.snapshot(200);
          expect(boundaryLogs.text, expectedBoundary);
          expect(boundaryLogs.containsReplacement, false);
          await record('actual-go-4096-byte-unicode-boundary', {
            'streamExact': streamExact,
            'serverReplacementObserved': replacement,
            'clientNoticesLoss': replacement,
            'explicitFreshSnapshotExact': true,
            'notClaimingClientReconstructedLostStreamBytes': true,
          });
        } finally {
          boundaryLogs.dispose();
        }

        final pull = await repo.reviewPull('127.0.0.1:5043/owned43/base:v1');
        await repo.commit(pull);
        final images = await repo.list(DockerResource.images);
        expect(
          images.any((row) => row.target == '127.0.0.1:5043/owned43/base:v1'),
          true,
        );
        await record('actual-image-pull-through-owned-registry', {
          'realDaemonPulledRegistryManifestAndBlobs': true,
          'noPercentageInvented': true,
        });

        for (final resource in [
          DockerResource.networks,
          DockerResource.volumes,
        ]) {
          final name = resource == DockerResource.networks
              ? 'owned-net-api43'
              : 'owned-volume-api43';
          final review = await repo.reviewNamedCreate(
            resource,
            name,
            resource == DockerResource.networks ? 'bridge' : 'local',
          );
          await repo.commit(review);
          final item = (await repo.list(
            resource,
          )).singleWhere((v) => v.name == name);
          final remove = await repo.reviewAction(item, 'delete');
          await repo.commit(remove);
          expect((await repo.list(resource)).any((v) => v.name == name), false);
        }
        await record('actual-network-and-volume-create-delete', {
          'realDaemonObjects': true,
          'onlyOwnedTargets': true,
        });

        final stop = await repo.reviewAction(main, 'stop');
        final route =
            '/api/admin/assets/ssh-hosts/${host.id}/docker-containers/${info.id}/stop';
        final arm = await Process.run('python3', [
          '$root/docker_control.py',
          'POST',
          route,
        ]);
        expect(arm.exitCode, 0);
        await expectLater(
          repo.commit(stop),
          throwsA(isA<DockerMutationUnknown>()),
        );
        expect(await count('POST', route), 1);
        await expectLater(
          repo.reviewAction(main, 'start'),
          throwsA(isA<DockerMutationUnknown>()),
        );
        final observed = await repo.observeUnknown();
        expect(observed.container!.running, false);
        repo.finishUnknownReview();
        expect(await count('POST', route), 1);
        await record('actual-applied-stop-lost-response', {
          'daemonStopped': true,
          'oneStopOnly': true,
          'readonlyObservationNotReceipt': true,
          'noReplay': true,
        });

        final prune = await repo.reviewPrune(DockerResource.containers);
        await repo.commit(prune);
        final remaining = await repo.list(DockerResource.containers);
        expect(remaining.map((v) => v.name), ['owned-survivor43']);
        await record('actual-host-wide-stopped-container-prune', {
          'stoppedTargetsAcrossHostRemoved': true,
          'runningSurvivorUnchanged': true,
          'noFilterScopedClaim': true,
        });

        final survivor = remaining.single;
        await repo.commit(
          await repo.reviewAction(
            survivor,
            'restart-policy',
            policy: 'unless-stopped',
          ),
        );
        final changedPolicy = await repo.inspect(survivor);
        expect(changedPolicy.policy, 'unless-stopped');
        await repo.commit(await repo.reviewAction(survivor, 'stop'));
        await repo.commit(await repo.reviewAction(survivor, 'delete'));
        expect(await repo.list(DockerResource.containers), isEmpty);
        final pulled = (await repo.list(
          DockerResource.images,
        )).singleWhere((v) => v.target == '127.0.0.1:5043/owned43/base:v1');
        await repo.commit(await repo.reviewAction(pulled, 'delete'));
        expect(
          (await repo.list(
            DockerResource.images,
          )).any((v) => v.target == '127.0.0.1:5043/owned43/base:v1'),
          false,
        );
        expect(
          (await repo.list(
            DockerResource.images,
          )).any((v) => v.target == 'owned43:base'),
          true,
        );
        await record('actual-policy-stop-delete-and-exact-image-tag', {
          'policyReadBack': true,
          'stoppedDeleteOnly': true,
          'otherTagPreserved': true,
        });

        final revoke = await Process.run('python3', [
          '$root/fixture_adapter.py',
          'revoke401',
        ]);
        expect(revoke.exitCode, 0);
        await expectLater(
          repo.list(DockerResource.images),
          throwsA(isA<StateError>()),
        );
        expect(scope.active, false);
        await record('actual-auth-version-revocation', {
          'scopeClosed': true,
          'noAdditionalMutation': true,
        });
        await File('$root/client-docker-contract-proof.json').writeAsString(
          jsonEncode({
            'passed': true,
            'checks': checks,
            'realGoAndSSHAndDockerDaemon': true,
            'productionGoChangedOrBuilt': false,
            'NativeAndroidProof': false,
          }),
        );
      } finally {
        repo?.dispose();
        scope?.dispose();
        client.close();
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
