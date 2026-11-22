import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/features/admin/admin_asset_models.dart';
import 'package:bookstark_flutter/features/admin/admin_docker_models.dart';
import 'package:bookstark_flutter/features/admin/admin_docker_terminal_access.dart';
import 'package:bookstark_flutter/features/admin/admin_terminal_controller.dart';
import 'package:bookstark_flutter/features/admin/admin_terminal_protocol.dart';
import 'admin_docker_test_fixture.dart';
import 'admin_terminal_controller_test.dart' show Wire;

class DockerWire extends Wire {
  Uri? endpoint;
  @override
  Future<Stream<Object?>> connect(Uri uri, String token) {
    endpoint = uri;
    expect(token, 'owned43-token');
    return super.connect(uri, token);
  }
}

void main() {
  late DockerHarness h;
  late DockerTerminalAccess access;
  late AdminTerminalController c;
  late List<DockerWire> wires;
  setUp(() {
    h = DockerHarness();
    wires = [];
    h.intercept = (request) async => request.url.path.endsWith('/settings')
        ? h.json({
            'terminal_idle_timeout_seconds': 1800,
            'terminal_scrollback_lines': 1234,
            'credential_secret': 'owned-policy-secret-not-for-terminal',
          })
        : null;
    access = DockerTerminalAccess(
      h.scope,
      AdminAssetHostMetadata.parse(h.host),
      DockerInspect.parse(h.detail),
      credential: AdminAssetCredentialMetadata.parse(h.credential),
    );
    c = access.create(
      transportFactory: () {
        final wire = DockerWire();
        wires.add(wire);
        return wire;
      },
    );
  });
  tearDown(() async {
    c.dispose();
    access.dispose();
    h.dispose();
    for (final wire in wires) {
      await wire.frames.close();
    }
  });
  test(
    'Docker terminal preflight binds policy, owner, credential and complete container ID',
    () async {
      await c.connect();
      expect(c.phase, TerminalPhase.connecting);
      expect(access.scrollbackLines, 1234);
      expect(
        wires.single.endpoint!.path,
        '/prefix/api/admin/assets/ssh-hosts/43/docker-containers/${List.filled(64, 'a').join()}/terminal',
      );
      expect(wires.single.endpoint!.scheme, 'wss');
      expect(wires.single.endpoint!.hasQuery, false);
      expect(h.mutations, 0);
      expect(wires.single.sent, isEmpty);
    },
  );
  test(
    'inherited credential rotation prevents any Docker WebSocket handshake',
    () async {
      h.credential['modify_time'] = '2026-11-08T02:00:00Z';
      await c.connect();
      expect(c.failure, TerminalFailure.targetChanged);
      expect(wires, isEmpty);
      expect(h.mutations, 0);
    },
  );
  test(
    'stopped or replaced container cannot start a stale terminal session',
    () async {
      h.detail = {...h.detail, 'running': false, 'status': 'stopped'};
      await c.connect();
      expect(c.failure, TerminalFailure.targetChanged);
      expect(wires, isEmpty);
    },
  );
  test(
    'actual owner refusal is translated before opening terminal transport',
    () async {
      h.role = -1;
      await c.connect();
      expect(c.phase, TerminalPhase.revoked);
      expect(wires, isEmpty);
      expect(h.mutations, 0);
    },
  );
}
