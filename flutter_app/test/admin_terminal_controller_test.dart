import 'dart:async';
import 'dart:convert';
import 'package:bookstark_flutter/features/admin/admin_terminal_controller.dart';
import 'package:bookstark_flutter/features/admin/admin_terminal_protocol.dart';
import 'package:bookstark_flutter/features/admin/admin_terminal_transport.dart';
import 'package:flutter_test/flutter_test.dart';

class Wire implements TerminalTransport {
  final frames = StreamController<Object?>();
  final sent = <String>[];
  int connects = 0, aborts = 0;
  Completer<void>? gate;
  @override
  Future<Stream<Object?>> connect(Uri uri, String token) async {
    connects++;
    if (gate != null) await gate!.future;
    return frames.stream;
  }

  @override
  void send(String frame) {
    if (aborts != 0) throw const TerminalException(TerminalFailure.closed);
    sent.add(frame);
  }

  @override
  void abort() {
    aborts++;
  }

  void emit(String type, [String? data]) =>
      frames.add(jsonEncode({'type': type, 'data': ?data}));
}

Future<void> tick() => Future<void>.delayed(Duration.zero);
void main() {
  late List<Wire> wires;
  late AdminTerminalController c;
  late bool active;
  late int preparations, verifications;
  Completer<void>? prepareGate, verifyGate;
  TerminalFailure? prepareError, verifyError;
  setUp(() {
    wires = [];
    active = true;
    preparations = 0;
    verifications = 0;
    prepareGate = null;
    verifyGate = null;
    prepareError = null;
    verifyError = null;
    c = AdminTerminalController(
      endpoint: Uri.parse('ws://owned.invalid/terminal'),
      token: 'owned-token',
      ownerActive: () => active,
      prepare: () async {
        preparations++;
        if (prepareGate != null) await prepareGate!.future;
        if (prepareError != null) throw TerminalException(prepareError!);
      },
      verifyOwner: () async {
        verifications++;
        if (verifyGate != null) await verifyGate!.future;
        if (verifyError != null) throw TerminalException(verifyError!);
      },
      transportFactory: () {
        final wire = Wire();
        wires.add(wire);
        return wire;
      },
    );
  });
  tearDown(() async {
    c.dispose();
    for (final wire in wires) {
      await wire.frames.close();
    }
  });
  Future<Wire> ready() async {
    await c.connect();
    final wire = wires.last;
    wire.emit('ready', 'connected');
    await tick();
    expect(c.phase, TerminalPhase.ready);
    return wire;
  }

  test(
    'entering review makes no connection; HTTP101 still blocks all input',
    () async {
      expect(preparations, 0);
      expect(wires, isEmpty);
      await c.connect();
      expect(c.phase, TerminalPhase.connecting);
      expect(c.input(c.generation, 'must not send'), isFalse);
      expect(c.resize(c.generation, 80, 24), isFalse);
      expect(wires.single.sent, isEmpty);
      wires.single.emit('ready', 'connected');
      await tick();
      expect(c.input(c.generation, 'printf 中文😀\r'), isTrue);
      expect(jsonDecode(wires.single.sent.single)['data'], 'printf 中文😀\r');
    },
  );
  test(
    'single connection while verification or handshake is pending',
    () async {
      prepareGate = Completer<void>();
      final first = c.connect();
      await c.connect();
      expect(preparations, 1);
      expect(wires, isEmpty);
      prepareGate!.complete();
      await first;
      await c.connect();
      expect(wires.length, 1);
    },
  );
  test('changed host refuses before creating any transport', () async {
    prepareError = TerminalFailure.targetChanged;
    await c.connect();
    expect(c.phase, TerminalPhase.disconnected);
    expect(c.failure, TerminalFailure.targetChanged);
    expect(wires, isEmpty);
  });
  test(
    'background during verification prevents late connect and clears output',
    () async {
      prepareGate = Completer<void>();
      final first = c.connect();
      c.output.add('owned secret');
      c.background();
      prepareGate!.complete();
      await first;
      expect(c.phase, TerminalPhase.background);
      expect(wires, isEmpty);
      expect(c.output.hasPending, isFalse);
    },
  );
  test(
    'foreground network loss preserves displayed backlog; explicit reconnect never replays',
    () async {
      final old = await ready();
      final oldGeneration = c.generation;
      c.input(oldGeneration, 'one-command\r');
      old.emit('output', 'owned tail');
      await tick();
      await old.frames.close();
      await tick();
      expect(c.phase, TerminalPhase.disconnected);
      expect(c.output.hasPending, isTrue);
      expect(c.input(oldGeneration, 'late'), isFalse);
      final fresh = await ready();
      expect(preparations, 2);
      expect(c.output.hasPending, isFalse);
      expect(fresh.sent, isEmpty);
      expect(old.sent.length, 1);
      expect(c.input(oldGeneration, 'stale bridge'), isFalse);
      expect(fresh.sent, isEmpty);
    },
  );
  test(
    'background closes connection, clears output and requires explicit reconnect',
    () async {
      final wire = await ready();
      wire.emit('output', 'owned private tail');
      await tick();
      c.background();
      expect(wire.aborts, 1);
      expect(c.output.hasPending, isFalse);
      wire.emit('output', 'late output');
      await tick();
      expect(c.output.hasPending, isFalse);
      expect(wires.length, 1);
      expect(c.canInput, isFalse);
    },
  );
  test(
    'explicit close sends one close, never claims command receipt',
    () async {
      final wire = await ready();
      c.input(c.generation, '\u0003');
      c.disconnect();
      expect(wire.sent.map(jsonDecode), [
        {'type': 'input', 'data': '\u0003'},
        {'type': 'close'},
      ]);
      expect(wire.aborts, 1);
      expect(c.output.hasPending, isFalse);
      c.disconnect();
      expect(wire.sent.length, 2);
    },
  );
  test(
    'fresh owner refusal revokes all terminal state and prevents reconnect',
    () async {
      final wire = await ready();
      c.output.add('owned hidden');
      verifyError = TerminalFailure.unauthorized;
      await c.checkOwner();
      expect(verifications, 1);
      expect(c.phase, TerminalPhase.revoked);
      expect(c.token, isNull);
      expect(c.output.hasPending, isFalse);
      expect(wire.aborts, 1);
      await c.connect();
      expect(wires.length, 1);
    },
  );
  test(
    'failed owner check also closes unchecked interactive connection',
    () async {
      final wire = await ready();
      verifyError = TerminalFailure.network;
      await c.checkOwner();
      expect(verifications, 1);
      expect(c.phase, TerminalPhase.disconnected);
      expect(wire.aborts, 1);
      expect(c.canInput, isFalse);
    },
  );
  test(
    'session replacement blocks synchronous input before any periodic poll',
    () async {
      final wire = await ready();
      active = false;
      expect(c.input(c.generation, 'late command'), isFalse);
      expect(c.phase, TerminalPhase.revoked);
      expect(wire.sent, isEmpty);
    },
  );
  test('duplicate ready and malformed/binary frames retire protocol', () async {
    final wire = await ready();
    wire.emit('ready', 'connected');
    await tick();
    expect(c.failure, TerminalFailure.protocol);
    expect(wire.aborts, 1);
    final fresh = await ready();
    fresh.frames.add(<int>[0]);
    await tick();
    expect(c.failure, TerminalFailure.protocol);
    expect(fresh.aborts, 1);
  });
  test(
    'late identity failure from an old generation cannot revoke a new session',
    () async {
      await ready();
      verifyGate = Completer<void>();
      final old = c.checkOwner();
      c.disconnect();
      await ready();
      verifyError = TerminalFailure.unauthorized;
      verifyGate!.complete();
      await old;
      expect(c.phase, TerminalPhase.ready);
    },
  );
  test(
    'disposal drops references and prevents future or late output',
    () async {
      final wire = await ready();
      c.output.add('owned private tail');
      c.dispose();
      wire.emit('output', 'late');
      await tick();
      expect(c.token, isNull);
      expect(c.output.hasPending, isFalse);
      expect(c.input(c.generation, 'late'), isFalse);
    },
  );
  test(
    'retired presentation cannot consume a new generation or fail its transport',
    () async {
      final first = await ready();
      final old = c.generation;
      expect(c.presentationOwnsOutput(old), isTrue);
      first.emit('output', 'old tail');
      await tick();
      await first.frames.close();
      await tick();
      expect(c.presentationOwnsOutput(old), isTrue);
      final fresh = await ready();
      c.output.add('new owned tail');
      expect(c.presentationOwnsOutput(old), isFalse);
      c.presentationFailed(old);
      expect(c.phase, TerminalPhase.ready);
      expect(fresh.aborts, 0);
      expect(c.output.take(), 'new owned tail');
      c.presentationFailed(c.generation);
      expect(c.phase, TerminalPhase.disconnected);
      expect(c.failure, TerminalFailure.protocol);
      expect(fresh.aborts, 1);
    },
  );
  test(
    'background presentation cannot drain output or replace the background state',
    () async {
      await ready();
      final held = c.generation;
      c.background();
      expect(c.presentationOwnsOutput(held), isFalse);
      c.presentationFailed(held);
      expect(c.phase, TerminalPhase.background);
      expect(c.output.hasPending, isFalse);
    },
  );
}
