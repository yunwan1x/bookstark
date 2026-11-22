import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'admin_terminal_protocol.dart' show terminalValidUnicode;

/// Remote metadata only. Never serializes itself to logs or durable drafts.
enum DockerResource {
  containers('docker-containers'),
  networks('docker-networks'),
  volumes('docker-volumes'),
  images('docker-images');

  const DockerResource(this.route);
  final String route;
}

String dockerText(
  Object? value, {
  bool requiredValue = false,
  int limit = 8192,
}) {
  if (value is! String ||
      value.length > limit ||
      !terminalValidUnicode(value) ||
      value.contains('\u0000') ||
      (requiredValue && value.isEmpty)) {
    throw const FormatException('Invalid Docker metadata');
  }
  return value;
}

String dockerObjectName(String value) {
  if (!RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,254}$').hasMatch(value)) {
    throw const FormatException('Invalid Docker object name');
  }
  return value;
}

String dockerImageReference(String value) {
  if (value.isEmpty ||
      value.length > 1024 ||
      value.startsWith('-') ||
      RegExp(r'[\s\u0000-\u001f\u007f]').hasMatch(value) ||
      !terminalValidUnicode(value)) {
    throw const FormatException('Invalid Docker image reference');
  }
  return value;
}

String dockerIdentifier(String value) {
  if (!RegExp(r'^(?:sha256:)?[a-f0-9]{12,64}$').hasMatch(value)) {
    throw const FormatException('Invalid Docker identifier');
  }
  return value;
}

String dockerDigest(Object? data) =>
    sha256.convert(utf8.encode(jsonEncode(data))).toString();
const dockerPolicies = {'no', 'always', 'unless-stopped', 'on-failure'};

final class DockerRecord {
  DockerRecord._(this.resource, Map<String, Object?> fields)
    : fields = Map.unmodifiable(fields),
      fingerprint = dockerDigest(
        Map<String, Object?>.from(fields)
          ..remove('status_text')
          ..remove('created_since'),
      );
  final DockerResource resource;
  final Map<String, Object?> fields;
  final String fingerprint;
  String get id => fields['id'] as String? ?? '';
  String get name =>
      resource == DockerResource.images ? target : fields['name'] as String;
  String get image => fields['image'] as String? ?? '';
  String get status => fields['status'] as String? ?? '';
  String get target {
    if (resource == DockerResource.volumes ||
        resource == DockerResource.networks) {
      return name;
    }
    if (resource == DockerResource.containers) return id;
    final repository = fields['repository'] as String;
    final tag = fields['tag'] as String;
    return repository != '<none>' && tag != '<none>' ? '$repository:$tag' : id;
  }

  static List<DockerRecord> parseList(DockerResource resource, Object? raw) {
    if (raw is! List || raw.length > 4096) {
      throw const FormatException('Invalid Docker list');
    }
    final result = <DockerRecord>[];
    final seen = <String>{};
    for (final item in raw) {
      if (item is! Map<String, dynamic>) {
        throw const FormatException('Invalid Docker entry');
      }
      final fields = <String, Object?>{};
      final keys = switch (resource) {
        DockerResource.containers => [
          'id',
          'name',
          'image',
          'command',
          'ports',
          'status',
          'status_text',
        ],
        DockerResource.networks => ['id', 'name', 'driver', 'scope'],
        DockerResource.volumes => [
          'name',
          'driver',
          'scope',
          'mountpoint',
          'size',
          'created_at',
        ],
        DockerResource.images => [
          'id',
          'repository',
          'tag',
          'size',
          'created_since',
          'created_at',
        ],
      };
      for (final key in keys) {
        final mandatory = switch (resource) {
          DockerResource.containers => {
            'id',
            'name',
            'image',
            'status',
          }.contains(key),
          DockerResource.networks || DockerResource.volumes => key == 'name',
          DockerResource.images => {'id', 'repository', 'tag'}.contains(key),
        };
        fields[key] = dockerText(
          item[key] ?? (mandatory ? null : ''),
          requiredValue: mandatory,
        );
      }
      if (resource == DockerResource.containers ||
          resource == DockerResource.images) {
        dockerIdentifier(fields['id'] as String);
      }
      if (resource == DockerResource.networks ||
          resource == DockerResource.volumes) {
        dockerObjectName(fields['name'] as String);
      }
      final row = DockerRecord._(resource, fields);
      if (!seen.add(row.target)) {
        throw const FormatException('Ambiguous Docker list');
      }
      result.add(row);
    }
    return List.unmodifiable(result);
  }

  @override
  String toString() => 'DockerRecord(${resource.name})';
}

final class DockerInspect {
  DockerInspect._(this.fields, this.fingerprint);
  final Map<String, Object?> fields;
  final String fingerprint;
  String get id => fields['id'] as String;
  String get name => fields['name'] as String;
  String get image => fields['image'] as String;
  bool get running => fields['running'] as bool;
  String get status => fields['status'] as String;
  String get policy => fields['restart_policy'] as String;
  static DockerInspect parse(Object? raw) {
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('Invalid Docker inspect');
    }
    final fields = <String, Object?>{};
    for (final key in [
      'id',
      'name',
      'image',
      'status',
      'raw_status',
      'created',
      'started_at',
      'finished_at',
      'hostname',
      'ip_address',
      'restart_policy',
    ]) {
      fields[key] = dockerText(
        raw[key] ?? '',
        requiredValue: {'id', 'name', 'image', 'status'}.contains(key),
      );
    }
    final id = fields['id'] as String;
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(id) ||
        raw['running'] is! bool ||
        raw['exit_code'] is! int) {
      throw const FormatException('Invalid Docker identity');
    }
    final command = raw['command'];
    if (command is! List || command.length > 256) {
      throw const FormatException('Invalid Docker command');
    }
    fields['command'] = List.unmodifiable(command.map((v) => dockerText(v)));
    fields['running'] = raw['running'];
    fields['exit_code'] = raw['exit_code'];
    // checked_at is a read observation; including it would invalidate every fresh inspect.
    return DockerInspect._(Map.unmodifiable(fields), dockerDigest(fields));
  }

  void match(DockerRecord row) {
    if (row.resource != DockerResource.containers ||
        !id.startsWith(row.id) ||
        name != row.name ||
        image != row.image) {
      throw const FormatException('Docker target changed');
    }
  }

  @override
  String toString() => 'DockerInspect';
}

final class DockerCreateDraft {
  DockerCreateDraft({
    required this.name,
    required this.image,
    this.command = '',
    this.restartPolicy = 'no',
    this.startAfterCreate = false,
    this.ports = const [],
    this.volumes = const [],
    this.env = const [],
    this.network = '',
    this.privileged = false,
    this.memory = '',
    this.cpus = '',
  });
  final String name, image, command, restartPolicy, network, memory, cpus;
  final bool startAfterCreate, privileged;
  final List<Map<String, String>> ports, volumes, env;
  Map<String, Object?> toRequest() {
    dockerObjectName(name);
    dockerImageReference(image);
    dockerText(command, limit: 8192);
    if (!dockerPolicies.contains(restartPolicy)) {
      throw const FormatException('Invalid Docker policy');
    }
    if (network.isNotEmpty) dockerObjectName(network);
    if (memory.isNotEmpty &&
        !RegExp(r'^[1-9][0-9]*(?:[bkmgBKMG])?$').hasMatch(memory)) {
      throw const FormatException('Invalid Docker memory limit');
    }
    if (cpus.isNotEmpty) {
      final count = double.tryParse(cpus);
      if (count == null || !count.isFinite || count < 0 || count > 1000000) {
        throw const FormatException('Invalid Docker CPU limit');
      }
    }
    if (ports.length > 64 || volumes.length > 64 || env.length > 256) {
      throw const FormatException('Too many Docker options');
    }
    int port(String? value, {bool optional = false}) {
      if (optional && value == '') return 0;
      final n = int.tryParse(value ?? '');
      if (n == null || n < 1 || n > 65535 || value != n.toString()) {
        throw const FormatException('Invalid Docker port');
      }
      return n;
    }

    for (final row in ports) {
      if (row.keys.toSet().difference({
            'host_ip',
            'host_port',
            'container_port',
            'protocol',
          }).isNotEmpty ||
          row.length != 4 ||
          !{'tcp', 'udp', 'sctp'}.contains(row['protocol'])) {
        throw const FormatException('Invalid Docker port');
      }
      port(row['container_port']);
      port(row['host_port']);
      final ip = row['host_ip']!;
      final octets = ip.split('.');
      if (octets.length != 4 ||
          octets.any((part) {
            final n = int.tryParse(part);
            return n == null || n < 0 || n > 255 || part != n.toString();
          })) {
        throw const FormatException('Explicit IPv4 bind address required');
      }
    }
    for (final row in volumes) {
      if (row.length != 3 ||
          !row.keys.toSet().containsAll({
            'host_path',
            'container_path',
            'mode',
          }) ||
          !{'ro', 'rw'}.contains(row['mode'])) {
        throw const FormatException('Invalid Docker mount');
      }
      for (final key in ['host_path', 'container_path']) {
        final path = dockerText(row[key], requiredValue: true, limit: 4096);
        if (RegExp(r'[:\r\n]').hasMatch(path)) {
          throw const FormatException('Invalid Docker mount path');
        }
      }
      if (!row['container_path']!.startsWith('/')) {
        throw const FormatException('Invalid container mount path');
      }
    }
    final keys = <String>{};
    for (final row in env) {
      if (row.length != 2 ||
          !row.keys.toSet().containsAll({'key', 'value'}) ||
          !RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(row['key'] ?? '') ||
          !keys.add(row['key']!)) {
        throw const FormatException('Invalid Docker environment');
      }
      dockerText(row['value'], limit: 8192);
    }
    final body = <String, Object?>{
      'name': name,
      'image': image,
      'command': command,
      'restart_policy': restartPolicy,
      'start_after_create': startAfterCreate,
      'ports': [for (final p in ports) Map<String, String>.from(p)],
      'volumes': [for (final v in volumes) Map<String, String>.from(v)],
      'env': [for (final e in env) Map<String, String>.from(e)],
      'network': network,
      'privileged': privileged,
      'memory': memory,
      'cpus': cpus,
    };
    if (utf8.encode(jsonEncode(body)).length > 65536) {
      throw const FormatException('Docker request too large');
    }
    return body;
  }

  @override
  String toString() => 'DockerCreateDraft';
}
