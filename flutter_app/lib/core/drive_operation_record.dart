import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:bookstark_flutter/core/drive_models.dart';

enum DriveOperationKind { mkdir, rename, copy, remove }

enum DriveOperationState { pending, unknown, acknowledged }

enum DriveObservationState { root, found, missing }

void _text(String value) {
  for (var i = 0; i < value.length; i++) {
    final c = value.codeUnitAt(i);
    if (c >= 0xd800 && c <= 0xdbff) {
      if (++i >= value.length ||
          value.codeUnitAt(i) < 0xdc00 ||
          value.codeUnitAt(i) > 0xdfff) {
        throw const FormatException('Invalid Unicode');
      }
    } else if (c >= 0xdc00 && c <= 0xdfff) {
      throw const FormatException('Invalid Unicode');
    }
  }
  if (utf8.encode(value).length > 8192) {
    throw const FormatException('Metadata text exceeds bound');
  }
}

String driveMetadataDigest(Object value) =>
    sha256.convert(utf8.encode(jsonEncode(value))).toString();
Map<String, Object?> driveNodeMetadata(DriveNode n) => {
  'id': n.id,
  'name': n.name,
  'path': n.path,
  'type': n.directory ? 'dir' : 'file',
  'size': n.size,
  'stored_size': n.storedSize,
  'etag': n.etag,
  'mime_type': n.mime,
  'mod_time': n.modified,
  'create_time': n.created,
  'mode': n.mode,
  'is_public': n.isPublic,
  'public_path': n.publicPath,
};

class DriveOperationScope {
  DriveOperationScope({
    required this.server,
    required this.member,
    required this.binding,
  }) {
    final uri = Uri.parse(server);
    if (!{'https', 'http'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        server.endsWith('/') ||
        member <= 0 ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(binding)) {
      throw const FormatException('Invalid remote drive scope');
    }
    _text(server);
  }
  final String server, binding;
  final int member;
  Map<String, Object> toJson() => {
    'server': server,
    'member': member,
    'binding': binding,
  };
  String get identity => jsonEncode(toJson());
}

class DriveOperationObservation {
  DriveOperationObservation({
    required this.path,
    required this.state,
    DriveNode? node,
  }) : node = node == null
           ? null
           : DriveNode.fromJson(driveNodeMetadata(node)) {
    _text(path);
    if (drivePath(path) != path ||
        (state == DriveObservationState.root) != (path.isEmpty) ||
        (state == DriveObservationState.found) != (this.node != null) ||
        this.node != null && this.node!.path != path) {
      throw const FormatException('Invalid drive observation');
    }
    if (this.node != null) {
      final metadata = driveNodeMetadata(this.node!);
      for (final value in metadata.values) {
        if (value is String) _text(value);
      }
      if (utf8.encode(jsonEncode(metadata)).length > 32768) {
        throw const FormatException('Metadata exceeds bound');
      }
    }
  }
  final String path;
  final DriveObservationState state;
  final DriveNode? node;
  Map<String, Object?> toJson() => {
    'path': path,
    'state': state.name,
    'node': node == null ? null : driveNodeMetadata(node!),
  };
  factory DriveOperationObservation.decode(Map value) {
    if (value.keys.toSet().difference({'path', 'state', 'node'}).isNotEmpty ||
        value.length != 3) {
      throw const FormatException('Invalid observation keys');
    }
    return DriveOperationObservation(
      path: value['path'] as String,
      state: DriveObservationState.values.byName(value['state'] as String),
      node: value['node'] == null
          ? null
          : DriveNode.fromJson(value['node'] as Map),
    );
  }
}

class DriveOperationRecord {
  DriveOperationRecord({
    required this.scope,
    required this.key,
    required this.kind,
    required this.state,
    required this.source,
    required this.sourceParent,
    required this.destination,
    required this.destinationParent,
    required this.destinationBefore,
    required this.createdAt,
  }) {
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(key)) {
      throw const FormatException('Invalid operation key');
    }
    _text(destination);
    if (createdAt.toUtc().toIso8601String() != createdAt.toIso8601String()) {
      throw const FormatException('UTC timestamp required');
    }
    if (kind == DriveOperationKind.mkdir) {
      if (source != null ||
          sourceParent != null ||
          destination.isEmpty ||
          destinationParent == null) {
        throw const FormatException('Invalid mkdir identity');
      }
    } else {
      if (source?.state != DriveObservationState.found ||
          sourceParent == null ||
          sourceParent!.path != driveParent(source!.path)) {
        throw const FormatException('Source identity required');
      }
      if (kind == DriveOperationKind.remove) {
        if (destination.isNotEmpty || destinationParent != null) {
          throw const FormatException('Delete has no destination');
        }
      } else if (destination.isEmpty ||
          destination == source!.path ||
          destination.startsWith('${source!.path}/') ||
          destinationParent == null) {
        throw const FormatException('Invalid destination');
      }
    }
    if (destination.isEmpty && destinationBefore != null ||
        destination.isNotEmpty &&
            (destinationBefore == null ||
                destinationBefore!.path != destination)) {
      throw const FormatException('Destination baseline required');
    }
    if (destination.isNotEmpty &&
        (drivePath(destination) != destination ||
            destinationParent!.path != driveParent(destination))) {
      throw const FormatException('Destination parent mismatch');
    }
    for (final parent in [sourceParent, destinationParent]) {
      if (parent != null &&
          parent.state != DriveObservationState.root &&
          (parent.state != DriveObservationState.found ||
              !parent.node!.directory)) {
        throw const FormatException('Existing directory parent required');
      }
    }
    if (utf8.encode(encode()).length > 128 * 1024) {
      throw const FormatException('Operation exceeds bound');
    }
  }
  final DriveOperationScope scope;
  final String key, destination;
  final DriveOperationKind kind;
  final DriveOperationState state;
  final DriveOperationObservation? source,
      sourceParent,
      destinationParent,
      destinationBefore;
  final DateTime createdAt;
  DriveOperationRecord withState(DriveOperationState next) =>
      DriveOperationRecord(
        scope: scope,
        key: key,
        kind: kind,
        state: next,
        source: source,
        sourceParent: sourceParent,
        destination: destination,
        destinationParent: destinationParent,
        destinationBefore: destinationBefore,
        createdAt: createdAt,
      );
  Map<String, Object?> toJson() => {
    'version': 1,
    'scope': scope.toJson(),
    'key': key,
    'kind': kind.name,
    'state': state.name,
    'source': source?.toJson(),
    'source_parent': sourceParent?.toJson(),
    'destination': destination,
    'destination_parent': destinationParent?.toJson(),
    'destination_before': destinationBefore?.toJson(),
    'created_at': createdAt.toIso8601String(),
  };
  String encode() => jsonEncode(toJson());
  String get fingerprint => driveMetadataDigest(toJson());
  factory DriveOperationRecord.decode(String raw) {
    if (utf8.encode(raw).length > 128 * 1024) {
      throw const FormatException('Operation exceeds bound');
    }
    final m = jsonDecode(raw) as Map;
    const keys = {
      'version',
      'scope',
      'key',
      'kind',
      'state',
      'source',
      'source_parent',
      'destination',
      'destination_parent',
      'destination_before',
      'created_at',
    };
    if (m.length != keys.length ||
        m.keys.toSet().difference(keys).isNotEmpty ||
        m['version'] != 1) {
      throw const FormatException('Invalid record schema');
    }
    final s = m['scope'] as Map;
    if (s.length != 3 ||
        s.keys.toSet().difference({'server', 'member', 'binding'}).isNotEmpty) {
      throw const FormatException('Invalid scope schema');
    }
    DriveOperationObservation? observation(String key) =>
        m[key] == null ? null : DriveOperationObservation.decode(m[key] as Map);
    return DriveOperationRecord(
      scope: DriveOperationScope(
        server: s['server'] as String,
        member: s['member'] as int,
        binding: s['binding'] as String,
      ),
      key: m['key'] as String,
      kind: DriveOperationKind.values.byName(m['kind'] as String),
      state: DriveOperationState.values.byName(m['state'] as String),
      source: observation('source'),
      sourceParent: observation('source_parent'),
      destination: m['destination'] as String,
      destinationParent: observation('destination_parent'),
      destinationBefore: observation('destination_before'),
      createdAt: DateTime.parse(m['created_at'] as String),
    );
  }
}
