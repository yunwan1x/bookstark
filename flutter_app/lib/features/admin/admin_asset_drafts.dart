import 'package:bookstark_flutter/core/go_text.dart';
import 'admin_asset_models.dart';

class AdminAssetDraftInvalid extends FormatException {
  const AdminAssetDraftInvalid() : super('Invalid asset form configuration');
}

final class AdminAssetHostDraft {
  const AdminAssetHostDraft({
    required this.name,
    required this.host,
    required this.port,
    required this.shell,
    required this.cwd,
    required this.dockerSocket,
    required this.credentialId,
    required this.username,
    required this.auth,
  });
  factory AdminAssetHostDraft.fromMetadata(AdminAssetHostMetadata host) =>
      AdminAssetHostDraft(
        name: host.name,
        host: host.host,
        port: host.port,
        shell: host.shell,
        cwd: host.cwd,
        dockerSocket: host.dockerSocket,
        credentialId: host.credentialId,
        username: host.username,
        auth: host.auth,
      );
  final String name, host, shell, cwd, dockerSocket, username;
  final int port, credentialId;
  final AdminAssetAuth auth;

  Map<String, Object?> toRequest({required bool creating}) {
    final normalizedName = trimGoSpace(name);
    final normalizedHost = trimGoSpace(host);
    final normalizedShell = trimGoSpace(shell);
    final normalizedCwd = trimGoSpace(cwd);
    final normalizedSocket = trimGoSpace(dockerSocket);
    if (normalizedName.isEmpty ||
        normalizedHost.isEmpty ||
        port < 1 ||
        port > 65535 ||
        credentialId < (creating ? 1 : 0) ||
        credentialId > 9007199254740991 ||
        [shell, cwd, dockerSocket].any((s) => RegExp(r'[\r\n]').hasMatch(s)) ||
        normalizedSocket.isNotEmpty && !normalizedSocket.startsWith('/') ||
        credentialId == 0 && trimGoSpace(username).isEmpty) {
      throw const AdminAssetDraftInvalid();
    }
    return Map.unmodifiable({
      'name': normalizedName,
      'host': normalizedHost,
      'port': port,
      'shell': normalizedShell.isEmpty ? '/bin/sh' : normalizedShell,
      'cwd': normalizedCwd,
      'docker_socket_path': normalizedSocket.isEmpty
          ? '/var/run/docker.sock'
          : normalizedSocket,
      'credential_id': credentialId,
      'username': trimGoSpace(username),
      'auth_type': auth.value,
    });
  }

  @override
  String toString() => 'AdminAssetHostDraft';
}

/// Contains safe metadata only. A replacement secret is passed once to a write.
final class AdminAssetCredentialDraft {
  const AdminAssetCredentialDraft({
    required this.name,
    required this.username,
    required this.auth,
  });
  factory AdminAssetCredentialDraft.fromMetadata(
    AdminAssetCredentialMetadata value,
  ) => AdminAssetCredentialDraft(
    name: value.name,
    username: value.username,
    auth: value.auth,
  );
  final String name, username;
  final AdminAssetAuth auth;

  Map<String, Object?> toRequest({
    required bool creating,
    required String? replacement,
  }) {
    final n = trimGoSpace(name), u = trimGoSpace(username);
    if (n.isEmpty ||
        u.isEmpty ||
        creating && replacement == null ||
        replacement != null && trimGoSpace(replacement).isEmpty) {
      throw const AdminAssetDraftInvalid();
    }
    return Map.unmodifiable({
      'name': n,
      'username': u,
      'auth_type': auth.value,
      'credential': replacement ?? '',
    });
  }

  @override
  String toString() => 'AdminAssetCredentialDraft';
}

enum AdminAssetConnectionReason {
  connected,
  refused,
  timeout,
  authentication,
  unsupportedKey,
  unspecified,
}

final class AdminAssetConnectionReceipt {
  AdminAssetConnectionReceipt._(this.status, this.checked, this.reason);
  final AdminAssetStatus status;
  final AdminAssetTimestamp checked;
  final AdminAssetConnectionReason reason;

  factory AdminAssetConnectionReceipt.parse(Map<String, dynamic> data) {
    final status = AdminAssetStatus.parse(data['status']);
    final checked = AdminAssetTimestamp.parse(data['checked_at']);
    final message = data['message'];
    if (status == AdminAssetStatus.unknown ||
        !checked.meaningful ||
        message is! String) {
      throw const FormatException('Invalid asset connection receipt');
    }
    // Only retain a controlled reason. The original SSH error is discarded.
    final lower = message.toLowerCase();
    final reason = status == AdminAssetStatus.online
        ? AdminAssetConnectionReason.connected
        : lower.contains('connection refused')
        ? AdminAssetConnectionReason.refused
        : lower.contains('timeout') || lower.contains('timed out')
        ? AdminAssetConnectionReason.timeout
        : lower.contains('unable to authenticate')
        ? AdminAssetConnectionReason.authentication
        : lower.contains('private key') ||
              lower.contains('no key found') ||
              lower.contains('passphrase')
        ? AdminAssetConnectionReason.unsupportedKey
        : AdminAssetConnectionReason.unspecified;
    return AdminAssetConnectionReceipt._(status, checked, reason);
  }
  @override
  String toString() => 'AdminAssetConnectionReceipt';
}

final class AdminAssetDeleteReceipt {
  const AdminAssetDeleteReceipt(this.resource, this.requestedId);
  final String resource;
  final int requestedId;
  // The Go endpoint supplies no affected-row count.
  @override
  String toString() => 'AdminAssetDeleteReceipt';
}
