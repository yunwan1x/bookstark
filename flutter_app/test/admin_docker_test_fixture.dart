import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/features/admin/admin_asset_models.dart';
import 'package:bookstark_flutter/features/admin/admin_assets_scope.dart';
import 'package:bookstark_flutter/features/admin/admin_settings_repository.dart';
import 'package:bookstark_flutter/features/admin/admin_docker_models.dart';
import 'package:bookstark_flutter/features/admin/admin_docker_repository.dart';
import 'admin_assets_repository_test.dart' as assets;
import 'admin_docker_models_test.dart' as models;

class DockerHarness {
  DockerHarness({http.Client? transport}) {
    client = BookstarkClient(
      'https://owned.invalid/prefix',
      transport: transport ?? MockClient(handle),
    );
    client.restoreSession({
      'token': 'owned43-token',
      'csrf_token': 'owned43-csrf',
    });
    scope = AdminAssetsScope(
      client,
      const AdminPrincipal(memberId: 1, account: 'owned-owner', role: 0),
    );
    repo = AdminDockerRepository(scope, AdminAssetHostMetadata.parse(host));
  }
  late final BookstarkClient client;
  late final AdminAssetsScope scope;
  late final AdminDockerRepository repo;
  final host = Map<String, dynamic>.from(assets.host(43));
  final credential = Map<String, dynamic>.from(assets.credential(9));
  Map<String, dynamic> detail = models.inspect();
  List<Map<String, dynamic>> containers = [
    {
      'id': 'aaaaaaaaaaaa',
      'name': 'owned43',
      'image': 'owned43:v1',
      'status': 'running',
      'ports': '',
    },
  ];
  List<Map<String, dynamic>> networks = [
    {
      'id': 'bbbbbbbbbbbb',
      'name': 'owned-network',
      'driver': 'bridge',
      'scope': 'local',
    },
  ];
  List<Map<String, dynamic>> volumes = [
    {
      'name': 'owned-volume',
      'driver': 'local',
      'scope': 'local',
      'mountpoint': '/owned43/volume',
    },
  ];
  List<Map<String, dynamic>> images = [
    {
      'id': 'cccccccccccc',
      'repository': 'registry:5000/owned/image',
      'tag': 'v1',
    },
  ];
  final requests = <http.Request>[];
  int mutations = 0, role = 0;
  bool drop = false;
  Future<http.Response?> Function(http.Request)? intercept;
  http.Response json(Object? data) => http.Response(
    jsonEncode({'code': 0, 'data': data}),
    200,
    headers: {'content-type': 'application/json'},
  );
  Future<http.Response> handle(http.Request request) async {
    requests.add(request);
    if (request.url.host != 'owned.invalid' ||
        !request.url.path.startsWith('/prefix/api/') ||
        request.followRedirects) {
      throw StateError('Unexpected test transport destination');
    }
    final overridden = await intercept?.call(request);
    if (overridden != null) return overridden;
    final path = request.url.path;
    if (path.endsWith('/profile')) {
      if (role < 0) return http.Response('owned unauthorized', 401);
      return json({'member_id': 1, 'account': 'owned-owner', 'role': role});
    }
    if (path.endsWith('/ssh-hosts')) return json([host]);
    if (path.endsWith('/credentials')) return json([credential]);
    if (path.endsWith('/inspect')) return json(detail);
    if (path.endsWith('/logs')) {
      return json({
        'id': detail['id'],
        'tail': int.parse(request.url.queryParameters['tail']!),
        'logs': '中文😀\nline two\n',
      });
    }
    if (request.method == 'GET') {
      if (path.endsWith('/docker-containers')) return json(containers);
      if (path.endsWith('/docker-networks')) return json(networks);
      if (path.endsWith('/docker-volumes')) return json(volumes);
      if (path.endsWith('/docker-images')) return json(images);
    }
    mutations++;
    if (request.headers['x-csrf-token'] != 'owned43-csrf') {
      throw StateError('Missing owned CSRF');
    }
    if (path.endsWith('/stop')) {
      detail = {
        ...detail,
        'running': false,
        'status': 'stopped',
        'raw_status': 'exited',
      };
    }
    if (path.endsWith('/start')) {
      detail = {...detail, 'running': true, 'status': 'running'};
    }
    if (path.endsWith('/restart-policy')) {
      detail = {
        ...detail,
        'restart_policy': (jsonDecode(request.body) as Map)['policy'],
      };
    }
    if (drop) throw http.ClientException('owned applied response dropped');
    final result = <String, Object?>{'output': 'owned test ack'};
    final parts = path.split('/');
    if (path.endsWith('/prune')) {
      result['resource'] = parts[parts.length - 2];
    } else if (path.endsWith('/docker-containers')) {
      final body = jsonDecode(request.body) as Map;
      result.addAll({
        'id': List.filled(64, 'd').join(),
        'name': body['name'],
        'image': body['image'],
        'start_after_create': body['start_after_create'],
      });
    } else if (path.contains('/docker-containers/')) {
      result.addAll({'id': parts[parts.length - 2], 'action': parts.last});
      if (parts.last == 'restart-policy') {
        result['policy'] = (jsonDecode(request.body) as Map)['policy'];
      }
    } else if (path.contains('/docker-images')) {
      result['image'] = request.method == 'POST'
          ? (jsonDecode(request.body) as Map)['image']
          : Uri.decodeComponent(
              path.substring(
                path.indexOf('/docker-images/') + '/docker-images/'.length,
              ),
            );
    } else {
      result['name'] = request.method == 'POST'
          ? (jsonDecode(request.body) as Map)['name']
          : parts.last;
    }
    return json(result);
  }

  DockerRecord row(DockerResource resource) =>
      DockerRecord.parseList(resource, switch (resource) {
        DockerResource.containers => containers,
        DockerResource.networks => networks,
        DockerResource.volumes => volumes,
        DockerResource.images => images,
      }).single;
  void dispose() {
    repo.dispose();
    scope.dispose();
    client.close();
  }
}
