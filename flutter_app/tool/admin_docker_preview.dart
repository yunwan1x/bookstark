// Synthetic Docker shell only. No real SSH, Docker, socket or native evidence.
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/app_theme.dart';
import 'package:bookstark_flutter/features/admin/admin_asset_models.dart';
import 'package:bookstark_flutter/features/admin/admin_asset_secure_window.dart';
import 'package:bookstark_flutter/features/admin/admin_assets_scope.dart';
import 'package:bookstark_flutter/features/admin/admin_settings_repository.dart';
import 'package:bookstark_flutter/features/admin/admin_docker_page.dart';

class _Guard implements AdminAssetWindowGuard {
  @override
  Future<void> acquire() async {}
  @override
  Future<void> close() async {}
}

class _DockerTransport extends http.BaseClient {
  _DockerTransport(this.handle);
  final Future<http.Response> Function(http.Request) handle;
  final controllers = <StreamController<List<int>>>[];
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (!request.url.path.endsWith('/logs/stream')) {
      return MockClient(handle).send(request);
    }
    late StreamController<List<int>> stream;
    Timer? timer;
    stream = StreamController(
      onListen: () {
        stream.add(
          utf8.encode('event: status\ndata: {"state":"connecting"}\n\n'),
        );
        timer = Timer.periodic(const Duration(milliseconds: 300), (_) {
          stream.add(
            utf8.encode(
              'event: log\ndata: ${jsonEncode({'data': '12:08:24  INFO  api ready · 中文😀\n'})}\n\n',
            ),
          );
        });
      },
      onCancel: () => timer?.cancel(),
    );
    controllers.add(stream);
    if (request is http.AbortableRequest) {
      request.abortTrigger?.then((_) {
        timer?.cancel();
        if (!stream.isClosed) unawaited(stream.close());
      });
    }
    return http.StreamedResponse(
      stream.stream,
      200,
      headers: {'content-type': 'text/event-stream'},
    );
  }

  @override
  void close() {
    for (final stream in controllers) {
      if (!stream.isClosed) unawaited(stream.close());
    }
  }
}

void main() {
  final query = Uri.base.queryParameters,
      english = query['lang'] == 'en',
      fault = query['fault'];
  final scale = double.tryParse(query['scale'] ?? '1') ?? 1;
  const stamp = '2026-11-08T08:00:00.123456789Z';
  final host = <String, dynamic>{
    'id': 43,
    'name': english ? 'Production host' : '应用服务器',
    'host': 'docker.example.invalid',
    'port': 22,
    'username': 'operator',
    'auth_type': 'key',
    'credential_id': 9,
    'credential_name': english ? 'Operator key' : '运维密钥',
    'credential_hint': 'key',
    'shell': '/bin/sh',
    'cwd': '/workspace',
    'docker_socket_path': '/var/run/docker.sock',
    'status': 'online',
    'last_check_time': stamp,
    'created_by': 1,
    'create_time': stamp,
    'modify_time': stamp,
  };
  final credential = <String, dynamic>{
    'id': 9,
    'name': host['credential_name'],
    'username': 'operator',
    'auth_type': 'key',
    'credential_hint': 'key',
    'created_by': 1,
    'create_time': stamp,
    'modify_time': stamp,
  };
  final id = List.filled(64, 'a').join(),
      secondId = List.filled(64, 'b').join();
  var containers = <Map<String, dynamic>>[
    {
      'id': id.substring(0, 12),
      'name': 'bookstark-api',
      'image': 'bookstark:latest',
      'command': '/app/bookstark',
      'ports': '127.0.0.1:8080 → 8080/tcp',
      'status': 'running',
      'status_text': 'Up 2 hours',
    },
    {
      'id': secondId.substring(0, 12),
      'name': 'nightly-backup',
      'image': 'backup:v2',
      'command': '/bin/sh',
      'ports': '',
      'status': 'stopped',
      'status_text': 'Exited (0)',
    },
  ];
  final networks = <Map<String, dynamic>>[
    {
      'id': 'cccccccccccc',
      'name': 'app-network',
      'driver': 'bridge',
      'scope': 'local',
    },
    {'id': 'dddddddddddd', 'name': 'host', 'driver': 'host', 'scope': 'local'},
  ];
  final volumes = <Map<String, dynamic>>[
    {
      'name': 'bookstark-data',
      'driver': 'local',
      'scope': 'local',
      'mountpoint': '/var/lib/docker/volumes/bookstark-data/_data',
      'created_at': stamp,
    },
  ];
  final images = <Map<String, dynamic>>[
    {
      'id': 'eeeeeeeeeeee',
      'repository': 'bookstark',
      'tag': 'latest',
      'size': '148 MB',
      'created_since': '2 days ago',
      'created_at': stamp,
    },
    {
      'id': 'ffffffffffff',
      'repository': 'backup',
      'tag': 'v2',
      'size': '32 MB',
      'created_since': '4 days ago',
      'created_at': stamp,
    },
  ];
  final fullIds = <String, String>{
    id.substring(0, 12): id,
    secondId.substring(0, 12): secondId,
  };
  final policies = <String, String>{
    id.substring(0, 12): 'unless-stopped',
    secondId.substring(0, 12): 'no',
  };
  var nextId = 3;
  bool readFailed = false, dropped = false;
  http.Response json(Object? data) => http.Response(
    jsonEncode({'code': 0, 'data': data}),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
  final transport = _DockerTransport((request) async {
    final path = request.url.path;
    if (path.endsWith('/profile')) {
      return fault == 'denied'
          ? http.Response('owned denied', 401)
          : json({'member_id': 1, 'account': 'owned43', 'role': 0});
    }
    if (path.endsWith('/ssh-hosts')) return json([host]);
    if (path.endsWith('/credentials')) return json([credential]);
    if (path.endsWith('/settings')) {
      return json({
        'terminal_idle_timeout_seconds': 1800,
        'terminal_scrollback_lines': 5000,
        'credential_secret': '',
      });
    }
    if (path.endsWith('/inspect')) {
      final short = path
          .split('/')[path.split('/').length - 2]
          .substring(0, 12);
      final row = containers.singleWhere((v) => v['id'] == short);
      return json({
        'id': fullIds[short],
        'name': row['name'],
        'image': row['image'],
        'status': row['status'],
        'raw_status': row['status'] == 'running' ? 'running' : 'exited',
        'running': row['status'] == 'running',
        'exit_code': 0,
        'created': stamp,
        'started_at': stamp,
        'finished_at': '',
        'hostname': 'bookstark-api',
        'ip_address': '172.20.0.3',
        'restart_policy': policies[short] ?? 'no',
        'command': [row['command']],
        'checked_at': stamp,
      });
    }
    if (path.endsWith('/logs')) {
      return json({
        'id': path.split('/')[path.split('/').length - 2],
        'tail': int.parse(request.url.queryParameters['tail'] ?? '200'),
        'logs':
            '12:08:20  INFO  starting service\n12:08:24  INFO  api ready · 中文😀\n',
      });
    }
    if (request.method == 'GET') {
      if (fault == 'read' && !readFailed) {
        readFailed = true;
        return http.Response('owned failed read', 503);
      }
      if (path.endsWith('/docker-containers')) {
        return json(fault == 'empty' ? [] : containers);
      }
      if (path.endsWith('/docker-networks')) return json(networks);
      if (path.endsWith('/docker-volumes')) return json(volumes);
      if (path.endsWith('/docker-images')) return json(images);
    }
    final payload = request.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(request.body) as Map<String, dynamic>;
    final parts = request.url.pathSegments;
    final result = <String, Object?>{'output': 'synthetic acknowledgement'};
    if (path.endsWith('/prune')) {
      if (parts[parts.length - 2] == 'containers') {
        containers = containers.where((v) => v['status'] == 'running').toList();
      }
      result['resource'] = parts[parts.length - 2];
    } else if (path.endsWith('/docker-containers')) {
      final full = (nextId++).toRadixString(16).padRight(64, '0'),
          short = (nextId - 1).toRadixString(16).padRight(12, '0');
      fullIds[short] = full;
      policies[short] = payload['restart_policy'] as String;
      containers.add({
        'id': short,
        'name': payload['name'],
        'image': payload['image'],
        'command': payload['command'],
        'ports': '',
        'status': payload['start_after_create'] == true ? 'running' : 'stopped',
        'status_text': '',
      });
      result.addAll({
        'id': full,
        'name': payload['name'],
        'image': payload['image'],
        'start_after_create': payload['start_after_create'],
      });
    } else if (path.contains('/docker-containers/')) {
      final full = parts[parts.length - 2],
          short = parts[parts.length - 2].substring(0, 12),
          action = parts.last;
      final index = containers.indexWhere((v) => v['id'] == short);
      if (action == 'stop' || action == 'start') {
        containers[index] = {
          ...containers[index],
          'status': action == 'stop' ? 'stopped' : 'running',
        };
      }
      if (action == 'delete') containers.removeAt(index);
      if (action == 'restart-policy') {
        policies[short] = payload['policy'] as String;
      }
      result.addAll({'id': full, 'action': action});
      if (action == 'restart-policy') result['policy'] = payload['policy'];
    } else if (path.contains('/docker-images')) {
      if (request.method == 'POST') {
        final reference = payload['image'] as String,
            colon = (payload['image'] as String).lastIndexOf(':');
        final split = colon > reference.lastIndexOf('/');
        final repository = split ? reference.substring(0, colon) : reference,
            tag = split ? reference.substring(colon + 1) : 'latest';
        images.add({
          'id': (nextId++).toRadixString(16).padRight(12, '0'),
          'repository': repository,
          'tag': tag,
        });
        result['image'] = reference;
      } else {
        final target = parts
            .sublist(parts.indexOf('docker-images') + 1)
            .join('/');
        images.removeWhere(
          (row) => '${row['repository']}:${row['tag']}' == target,
        );
        result['image'] = target;
      }
    } else {
      final isNetwork = path.contains('/docker-networks'),
          rows = isNetwork ? networks : volumes;
      if (request.method == 'POST') {
        rows.add({
          'id': (nextId++).toRadixString(16).padRight(12, '0'),
          'name': payload['name'],
          'driver': payload['driver'],
          'scope': 'local',
        });
        result['name'] = payload['name'];
      } else {
        rows.removeWhere((row) => row['name'] == parts.last);
        result['name'] = parts.last;
      }
    }
    if (fault == 'unknown' && !dropped) {
      dropped = true;
      throw http.ClientException('synthetic applied reply lost');
    }
    return json(result);
  });
  final client = BookstarkClient('https://owned.invalid', transport: transport);
  client.restoreSession({
    'token': 'owned43-preview-token',
    'csrf_token': 'owned43-preview-csrf',
  });
  final scope = AdminAssetsScope(
    client,
    const AdminPrincipal(memberId: 1, account: 'owned43', role: 0),
  );
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: bookstarkTheme(),
      locale: Locale(english ? 'en' : 'zh'),
      supportedLocales: const [Locale('zh'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: AdminDockerPage(
        scope: scope,
        host: AdminAssetHostMetadata.parse(host),
        english: english,
        secureWindowFactory: () => _Guard(),
        onReturn: scope.close,
      ),
    ),
  );
}
