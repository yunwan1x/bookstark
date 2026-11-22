import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/features/admin/admin_assets_repository.dart';
import 'package:bookstark_flutter/features/admin/admin_docker_models.dart';
import 'package:bookstark_flutter/features/admin/admin_docker_repository.dart';
import 'package:bookstark_flutter/features/admin/admin_docker_controller.dart';
import 'admin_docker_test_fixture.dart';

void main() {
  late DockerHarness h;
  setUp(() => h = DockerHarness());
  tearDown(() => h.dispose());
  test(
    'short catalog ID resolves through inspect and only full ID dispatches',
    () async {
      final plan = await h.repo.reviewAction(
        h.row(DockerResource.containers),
        'stop',
      );
      expect(plan.target, List.filled(64, 'a').join());
      expect(h.mutations, 0);
      await h.repo.commit(plan);
      expect(h.mutations, 1);
      expect(
        h.requests.last.url.path,
        endsWith('/${List.filled(64, 'a').join()}/stop'),
      );
      await expectLater(
        h.repo.commit(plan),
        throwsA(isA<AdminAssetTargetChanged>()),
      );
      expect(h.mutations, 1);
    },
  );
  test(
    'host socket change between review and confirmation sends no mutation',
    () async {
      final plan = await h.repo.reviewAction(
        h.row(DockerResource.containers),
        'stop',
      );
      h.host['docker_socket_path'] = '/different-owned.sock';
      await expectLater(
        h.repo.commit(plan),
        throwsA(isA<AdminAssetTargetChanged>()),
      );
      expect(h.mutations, 0);
    },
  );
  test(
    'credential rotation after review blocks both mutation and later reads',
    () async {
      final plan = await h.repo.reviewAction(
        h.row(DockerResource.volumes),
        'delete',
      );
      h.credential['modify_time'] = '2026-11-08T01:00:00Z';
      await expectLater(
        h.repo.commit(plan),
        throwsA(isA<AdminAssetTargetChanged>()),
      );
      await expectLater(
        h.repo.list(DockerResource.volumes),
        throwsA(isA<AdminAssetTargetChanged>()),
      );
      expect(h.mutations, 0);
    },
  );
  test(
    'container replaced or lifecycle changed after review is refused',
    () async {
      final plan = await h.repo.reviewAction(
        h.row(DockerResource.containers),
        'stop',
      );
      h.detail = {...h.detail, 'restart_policy': 'always'};
      await expectLater(
        h.repo.commit(plan),
        throwsA(isA<AdminAssetTargetChanged>()),
      );
      expect(h.mutations, 0);
    },
  );
  test(
    'running delete is unavailable; explicit stopped target can be deleted',
    () async {
      await expectLater(
        h.repo.reviewAction(h.row(DockerResource.containers), 'delete'),
        throwsA(isA<AdminAssetTargetChanged>()),
      );
      expect(h.mutations, 0);
      h.detail = {...h.detail, 'running': false, 'status': 'stopped'};
      final plan = await h.repo.reviewAction(
        h.row(DockerResource.containers),
        'delete',
      );
      await h.repo.commit(plan);
      expect(h.mutations, 1);
    },
  );
  test(
    'applied stop with lost reply becomes unknown and never replays',
    () async {
      final plan = await h.repo.reviewAction(
        h.row(DockerResource.containers),
        'stop',
      );
      h.drop = true;
      await expectLater(
        h.repo.commit(plan),
        throwsA(isA<DockerMutationUnknown>()),
      );
      expect(h.mutations, 1);
      expect(h.detail['running'], false);
      await expectLater(
        h.repo.reviewAction(h.row(DockerResource.containers), 'start'),
        throwsA(isA<DockerMutationUnknown>()),
      );
      expect(
        () => h.repo.finishUnknownReview(),
        throwsA(isA<AdminAssetTargetChanged>()),
      );
      final observed = await h.repo.observeUnknown();
      expect(observed.container!.running, false);
      expect(h.mutations, 1);
      h.repo.finishUnknownReview();
      expect(h.repo.unknown, isNull);
      expect(h.mutations, 1);
    },
  );
  test(
    'create review freezes nested environment values and never starts by default',
    () async {
      final values = [
        {'key': 'OWNED', 'value': 'original'},
      ];
      final plan = await h.repo.reviewContainerCreate(
        DockerCreateDraft(
          name: 'new-owned43',
          image: 'owned43:v1',
          env: values,
        ),
      );
      values.single['value'] = 'changed';
      expect(() => plan.body!['name'] = 'different', throwsUnsupportedError);
      expect(
        () =>
            ((plan.body!['env'] as List).single as Map)['value'] = 'different',
        throwsUnsupportedError,
      );
      await h.repo.commit(plan);
      final body = jsonDecode(h.requests.last.body) as Map;
      expect(body['start_after_create'], false);
      expect((body['env'] as List).single['value'], 'original');
    },
  );
  test(
    'newly occupied name after create review refuses without POST',
    () async {
      final plan = await h.repo.reviewNamedCreate(
        DockerResource.volumes,
        'new-volume',
        'local',
      );
      h.volumes.add({'name': 'new-volume', 'driver': 'local'});
      await expectLater(
        h.repo.commit(plan),
        throwsA(isA<AdminAssetTargetChanged>()),
      );
      expect(h.mutations, 0);
    },
  );
  test(
    'prune checks whole inventory and changes outside UI filter block commit',
    () async {
      final plan = await h.repo.reviewPrune(DockerResource.volumes);
      h.volumes.add({'name': 'not-visible-filter', 'driver': 'local'});
      await expectLater(
        h.repo.commit(plan),
        throwsA(isA<AdminAssetTargetChanged>()),
      );
      expect(h.mutations, 0);
    },
  );
  test(
    'image deletion keeps registry port, repository slash and exact tag',
    () async {
      final plan = await h.repo.reviewAction(
        h.row(DockerResource.images),
        'delete',
      );
      await h.repo.commit(plan);
      expect(h.requests.last.method, 'DELETE');
      expect(
        Uri.decodeComponent(h.requests.last.url.path),
        endsWith('/docker-images/registry:5000/owned/image:v1'),
      );
      expect(h.mutations, 1);
    },
  );
  test(
    'malformed success receipt becomes unknown and cannot be replayed',
    () async {
      final plan = await h.repo.reviewAction(
        h.row(DockerResource.containers),
        'stop',
      );
      h.intercept = (request) async {
        if (request.url.path.endsWith('/stop')) {
          h.mutations++;
          return h.json({
            'id': List.filled(64, 'b').join(),
            'action': 'stop',
            'output': '',
          });
        }
        return null;
      };
      await expectLater(
        h.repo.commit(plan),
        throwsA(isA<DockerMutationUnknown>()),
      );
      expect(h.mutations, 1);
      expect(h.repo.unknown, isNotNull);
      await expectLater(
        h.repo.commit(plan),
        throwsA(isA<AdminAssetTargetChanged>()),
      );
      expect(h.mutations, 1);
    },
  );
  test(
    'server revocation closes scope and cannot send pending reviewed action',
    () async {
      final plan = await h.repo.reviewAction(
        h.row(DockerResource.networks),
        'delete',
      );
      h.role = -1;
      await expectLater(
        h.repo.commit(plan),
        throwsA(isA<AdminAssetOwnerLost>()),
      );
      expect(h.scope.active, false);
      expect(h.mutations, 0);
    },
  );
  test(
    'known receipt disappears on a new unknown write and observations are not receipts',
    () async {
      final c = AdminDockerController(h.repo);
      await c.read();
      final first = await c.review(
        () => h.repo.reviewAction(h.row(DockerResource.containers), 'stop'),
      );
      expect(await c.commit(first!), true);
      expect(c.receipt, true);
      expect(c.receiptSummary?.resource, DockerResource.containers);
      expect(c.receiptSummary?.action, 'stop');
      expect(c.receiptSummary?.target, List.filled(64, 'a').join());
      final receipt = c.receiptSummary;
      await c.read(DockerResource.volumes);
      expect(identical(c.receiptSummary, receipt), true);
      await c.read(DockerResource.containers);
      expect(identical(c.receiptSummary, receipt), true);
      h.drop = true;
      final second = await c.review(
        () => h.repo.reviewAction(h.row(DockerResource.containers), 'start'),
      );
      expect(await c.commit(second!), false);
      expect(c.receipt, false);
      expect(c.receiptSummary, isNull);
      expect(c.unknown, true);
      await c.observe();
      expect(c.receipt, false);
      expect(h.mutations, 2);
      c.finishObservation();
      expect(c.receipt, false);
      expect(h.mutations, 2);
      c.dispose();
    },
  );
  test(
    'background clears all visible data; resume never automatically connects',
    () async {
      final c = AdminDockerController(h.repo);
      await c.read();
      expect(c.rows, isNotEmpty);
      c.filter('owned');
      c.background();
      expect(c.rows, isEmpty);
      expect(c.query, '');
      final count = h.requests.length;
      c.resume();
      await Future<void>.delayed(Duration.zero);
      expect(h.requests.length, count);
      expect(c.phase, DockerPhase.idle);
      c.dispose();
    },
  );
}
