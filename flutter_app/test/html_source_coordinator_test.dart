import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/complex_editor_transport.dart';
import 'package:bookstark_flutter/core/html_editor_controller.dart';
import 'package:bookstark_flutter/core/html_notes_repository.dart';
import 'package:bookstark_flutter/core/html_recovery_vault.dart';
import 'package:bookstark_flutter/features/complex_editors/complex_editor_browser.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookstark_flutter/features/html/html_source_coordinator.dart';

// Fake protocol peer only. These tests do not model Android WebView, lease,
// platform-view input, secure storage encryption, or native screenshot proof.
class _FakeHost {
  _FakeHost(this.source);

  String source;
  int generation = 0;
  int revision = 0;
  bool inputLocked = true;
  bool closed = false;
  int loadCount = 0;
  int snapshotCount = 0;
  int endedSnapshots = 0;
  int ackCount = 0;
  Completer<void>? readStarted;
  Completer<void>? readGate;
  bool _usedReadGate = false;
  int _loadSequence = 0;
  int _snapshotSequence = 0;
  final Map<String, Uint8List> _snapshots = {};
  final BytesBuilder _loadBuffer = BytesBuilder(copy: false);
  int _loadBytes = 0;
  ComplexEditorKind _kind = ComplexEditorKind.html;
  bool _readOnly = true;

  void userEdit(String value) {
    if (inputLocked || closed) throw StateError('Fake host input is locked');
    source = value;
    revision++;
  }

  Map<String, Object?> _state() => {
    'version': 1,
    'kind': _kind.name,
    'generation': generation,
    'revision': revision,
    'ready': true,
    'dirty': revision > 0,
    'inputLocked': inputLocked || _readOnly,
  };

  Future<Object?> command(String name, List<Object?> args) async {
    switch (name) {
      case 'beginLoad':
        _kind = ComplexEditorKind.parse(args[0] as String);
        _readOnly = (args[3] as Map)['readOnly'] as bool;
        _loadBuffer.clear();
        _loadBytes = 0;
        loadCount++;
        return {
          'id': 'load-${++_loadSequence}',
          'bytes': args[1],
          'chunkBytes': ComplexEditorTransport.chunkBytes,
        };
      case 'appendLoad':
        final text = args[2] as String;
        final bytes = base64Decode(text);
        _loadBuffer.add(bytes);
        _loadBytes += bytes.length;
        return {'id': args[0], 'index': args[1], 'received': _loadBytes};
      case 'commitLoad':
        source = utf8.decode(_loadBuffer.takeBytes(), allowMalformed: false);
        generation++;
        revision = 0;
        inputLocked = _readOnly;
        return {..._state(), 'readOnly': _readOnly};
      case 'abortLoad':
        return null;
      case 'setInputLocked':
        if (args[1] != generation) throw StateError('stale generation');
        inputLocked = args[0] as bool;
        return _state();
      case 'beginSnapshot':
        snapshotCount++;
        final bytes = Uint8List.fromList(utf8.encode(source));
        final id = 'snapshot-${++_snapshotSequence}';
        _snapshots[id] = bytes;
        return {
          'id': id,
          'bytes': bytes.length,
          'chunks':
              (bytes.length + ComplexEditorTransport.chunkBytes - 1) ~/
              ComplexEditorTransport.chunkBytes,
          'generation': generation,
          'revision': revision,
          'sha256': sha256.convert(bytes).toString(),
        };
      case 'readSnapshot':
        final id = args[0] as String;
        final bytes = _snapshots[id]!;
        if (!_usedReadGate && readGate != null) {
          _usedReadGate = true;
          if (!(readStarted?.isCompleted ?? true)) readStarted!.complete();
          await readGate!.future;
        }
        final index = args[1] as int;
        final start = index * ComplexEditorTransport.chunkBytes;
        final end = (start + ComplexEditorTransport.chunkBytes).clamp(
          0,
          bytes.length,
        );
        return {
          'id': id,
          'generation': generation,
          'index': index,
          'base64': base64Encode(bytes.sublist(start, end)),
        };
      case 'endSnapshot':
        if (_snapshots.remove(args[0]) != null) endedSnapshots++;
        return null;
      case 'acknowledgeSnapshot':
        if (_snapshots.remove(args[0]) == null) {
          throw StateError('unknown snapshot');
        }
        ackCount++;
        return _state();
      case 'retire':
        closed = true;
        return null;
      default:
        throw StateError('Unexpected fake host command: $name');
    }
  }
}

class _Repository implements HtmlNotesRepository {
  _Repository(this.current, {this.events});

  HtmlNote current;
  final List<String>? events;
  bool unknown = false;
  Completer<void>? saveStarted;
  Completer<void>? saveGate;
  int saveCalls = 0;
  int contentWrites = 0;
  int labelWrites = 0;

  @override
  bool get labelsUseCsv => true;

  @override
  Future<HtmlNote> read(int id, {String? password}) async => current;

  @override
  Future<HtmlSaveOutcome> save(HtmlNote baseline, HtmlNoteEdit edit) async {
    saveCalls++;
    events?.add('repository.save');
    if (saveStarted != null && !saveStarted!.isCompleted) {
      saveStarted!.complete();
    }
    if (saveGate != null) await saveGate!.future;
    final attempt = HtmlSaveAttempt(baseline: baseline, edit: edit);
    contentWrites++;
    if (unknown) throw HtmlSaveIncomplete(attempt);
    final updated = HtmlNote(
      metadata: HtmlNoteMetadata(
        id: baseline.metadata.id,
        memberId: baseline.metadata.memberId,
        collection: baseline.metadata.collection,
        title: edit.title,
        version: baseline.metadata.version + 1,
        modifiedAt: baseline.metadata.modifiedAt + 1,
        protected: baseline.metadata.protected,
      ),
      source: edit.source,
      labels: edit.labels,
      unlockPassword: baseline.unlockPassword,
    );
    current = updated;
    if (attempt.requiresLabelWrite) labelWrites++;
    return HtmlSaveOutcome(
      updated,
      attempt.acknowledged(content: true, labels: true),
    );
  }

  @override
  Future<HtmlSaveOutcome> finishLabels(HtmlSaveAttempt attempt) async =>
      throw StateError('Unexpected label continuation');

  @override
  void dispose() {}
}

class _RecoveryMemory {
  final values = <String, String>{};
  final history = <String>[];
  final events = <String>[];
  bool failWrite = false;

  HtmlRecoveryVault vault({int memberId = 7, String collection = 'note'}) =>
      HtmlRecoveryVault(
        server: Uri.parse('https://fixture.example'),
        memberId: memberId,
        collection: collection,
        readValue: (key) async => values[key],
        writeValue: (key, value) async {
          events.add('vault.write');
          history.add(value);
          if (failWrite) throw StateError('fake vault write failure');
          values[key] = value;
        },
        deleteValue: (key) async {
          events.add('vault.delete');
          values.remove(key);
        },
      );
}

HtmlNote _baseline({bool protected = false}) => HtmlNote(
  metadata: HtmlNoteMetadata(
    id: 42,
    memberId: 7,
    collection: 'note',
    title: protected ? 'PROTECTED_TITLE_MARKER' : 'Original title',
    version: 3,
    modifiedAt: 100,
    protected: protected,
  ),
  source: protected ? '<p>PROTECTED_BODY_MARKER</p>' : '<p>original</p>',
  labels: const ['base'],
  unlockPassword: protected ? 'PROTECTED_PASSWORD_MARKER' : null,
);

class _Fixture {
  _Fixture({
    required this.host,
    required this.repository,
    required this.controller,
    required this.coordinator,
    required this.transport,
    required this.seed,
    required this.memory,
  });

  final _FakeHost host;
  final _Repository repository;
  final HtmlEditorController controller;
  final HtmlSourceCoordinator coordinator;
  final ComplexEditorTransport transport;
  final ComplexEditorDocument seed;
  final _RecoveryMemory memory;

  static Future<_Fixture> open({
    bool protected = false,
    bool withRecovery = false,
    void Function(String source)? onFreeze,
  }) async {
    final memory = _RecoveryMemory();
    final baseline = _baseline(protected: protected);
    final repository = _Repository(baseline, events: memory.events);
    final controller = HtmlEditorController(
      repository,
      baseline,
      recovery: withRecovery ? memory.vault() : null,
    );
    var title = baseline.metadata.title;
    var labels = baseline.labels;
    final coordinator = HtmlSourceCoordinator(
      controller,
      freezeEdit: (source) {
        onFreeze?.call(source);
        return HtmlNoteEdit(title: title, source: source, labels: labels);
      },
    );
    final seed = coordinator.beginGeneration();
    final host = _FakeHost(seed.source);
    final transport = ComplexEditorTransport(host.command);
    await transport.load(seed, readOnly: false, title: title);
    await coordinator.bind(transport, generation: host.generation);
    final fixture = _Fixture(
      host: host,
      repository: repository,
      controller: controller,
      coordinator: coordinator,
      transport: transport,
      seed: seed,
      memory: memory,
    );
    fixture.setMetadata = (valueTitle, valueLabels) {
      title = valueTitle;
      labels = List<String>.unmodifiable(valueLabels);
    };
    return fixture;
  }

  late void Function(String title, List<String> labels) setMetadata;

  void publishState() {
    coordinator.onState(
      transport,
      ComplexEditorState(
        generation: host.generation,
        revision: host.revision,
        ready: true,
        dirty: host.revision > 0,
        inputLocked: host.inputLocked,
      ),
    );
  }

  Future<void> retire() async {
    await coordinator.beforeRetire(transport);
    await transport.retire();
  }
}

void main() {
  test(
    'transport generation is null before load, changes on load, and clears on retire',
    () async {
      final document = ComplexEditorDocument.parse(
        ComplexEditorKind.html,
        '<p>seed</p>',
      );
      final host = _FakeHost(document.source);
      final transport = ComplexEditorTransport(host.command);

      expect(transport.generation, isNull);
      await transport.load(document, readOnly: false);
      expect(transport.generation, 1);
      await transport.load(
        document.withSource('<p>second</p>'),
        readOnly: false,
      );
      expect(transport.generation, 2);
      await transport.retire();
      expect(transport.generation, isNull);
    },
  );

  test(
    'checkpoint stores exact captured source and never changes mounted seed',
    () async {
      final f = await _Fixture.open(withRecovery: true);
      final source = '\uFEFF<!doctype html>\r\n<p>中文😀</p>\r\n';
      f.host.userEdit(source);
      f.publishState();

      expect(f.coordinator.ready, isTrue);
      expect(await f.coordinator.checkpoint(), isTrue);
      expect(f.controller.draft.source, source);
      expect(f.coordinator.seed, same(f.seed));
      expect(f.transport.generation, f.host.generation);
      expect(f.host.endedSnapshots, 1);
      expect(f.host.inputLocked, isFalse);
      final savedRecord =
          (jsonDecode(f.memory.history.single) as Map)['edit'] as Map;
      expect(savedRecord['source'], source);

      await f.retire();
      f.controller.dispose();
    },
  );

  test(
    'save freezes latest metadata and exact source, waits for durable pending, then acks once',
    () async {
      final f = await _Fixture.open(withRecovery: true);
      const source = '\uFEFF<html>\r\n<p>edited😀</p>\r\n</html>';
      f.host.userEdit(source);
      f.setMetadata('Changed title', const ['base', 'new-label']);
      await f.coordinator.updateMetadata(
        title: 'Changed title',
        labels: const ['base', 'new-label'],
      );
      f.publishState();

      final outcome = await f.coordinator.save();

      expect(outcome, isNotNull);
      expect(outcome!.allReceiptsKnown, isTrue);
      expect(outcome.note.source, source);
      expect(outcome.note.metadata.title, 'Changed title');
      expect(outcome.note.labels, const ['base', 'new-label']);
      expect(f.repository.saveCalls, 1);
      expect(f.host.ackCount, 1);
      expect(f.host.endedSnapshots, 0);
      expect(
        f.memory.events.indexOf('vault.write'),
        lessThan(f.memory.events.indexOf('repository.save')),
      );
      expect(f.coordinator.seed, same(f.seed));
      expect(f.host.inputLocked, isFalse);

      await f.retire();
      f.controller.dispose();
    },
  );

  test(
    'no-op save removes an earlier dirty checkpoint without SQL or fake ack',
    () async {
      final f = await _Fixture.open(withRecovery: true);
      f.host.userEdit('<p>temporary dirty body</p>');
      expect(await f.coordinator.checkpoint(), isTrue);
      expect(f.memory.values, isNotEmpty);
      final writesBefore = f.repository.saveCalls;

      f.host.userEdit('<p>original</p>');
      expect(await f.coordinator.save(), isNull);

      expect(f.repository.saveCalls, writesBefore);
      expect(f.host.ackCount, 0);
      expect(f.memory.values, isEmpty);
      expect(f.host.inputLocked, isFalse);
      await f.retire();
      f.controller.dispose();
    },
  );

  test(
    'forced retirement waits for active save and preserves real receipt without ack',
    () async {
      final f = await _Fixture.open();
      f.repository.saveStarted = Completer<void>();
      f.repository.saveGate = Completer<void>();
      f.host.userEdit('<p>committing while lease retires</p>');

      final save = f.coordinator.save();
      await f.repository.saveStarted!.future;
      final retirement = f.coordinator.beforeRetire(f.transport);
      expect(f.coordinator.busy, isTrue);

      f.repository.saveGate!.complete();
      final outcome = await save;
      await retirement;

      expect(outcome, isNotNull);
      expect(outcome!.allReceiptsKnown, isTrue);
      expect(outcome.note.source, '<p>committing while lease retires</p>');
      expect(f.repository.saveCalls, 1);
      // Retirement changes the epoch before the repository returns. A genuine
      // SQL receipt is preserved for UI reporting, but stale host state cannot
      // be acknowledged through the retiring lease.
      expect(f.host.ackCount, 0);
      expect(f.host.inputLocked, isTrue);
      expect(f.coordinator.generation, isNull);
      await f.transport.retire();
      expect(f.host.closed, isTrue);
      f.controller.dispose();
    },
  );

  test(
    'unknown save does not ack or retry and forced retirement skips another capture',
    () async {
      final f = await _Fixture.open();
      f.repository.unknown = true;
      f.host.userEdit('<p>unknown result</p>');
      final first = await f.coordinator.save();
      final snapshotsAfterSave = f.host.snapshotCount;

      expect(first, isNull);
      expect(f.controller.hasPendingOperation, isTrue);
      expect(f.host.ackCount, 0);
      expect(f.host.inputLocked, isTrue);
      expect(await f.coordinator.checkpoint(), isTrue);
      expect(f.host.snapshotCount, snapshotsAfterSave);
      expect(f.host.inputLocked, isTrue);
      expect(await f.coordinator.save(), isNull);
      expect(f.repository.saveCalls, 1);

      await f.coordinator.beforeRetire(f.transport);
      expect(f.host.snapshotCount, snapshotsAfterSave);
      expect(f.coordinator.retirementFailure, isNull);
      await f.transport.retire();
      expect(f.host.closed, isTrue);
      f.controller.dispose();
    },
  );

  test(
    'late capture from invalidated transport cannot edit or persist old generation',
    () async {
      final f = await _Fixture.open(withRecovery: true);
      f.host.userEdit('<p>old generation only</p>');
      f.host.readStarted = Completer<void>();
      f.host.readGate = Completer<void>();
      final checkpoint = f.coordinator.checkpoint();
      await f.host.readStarted!.future;

      f.coordinator.invalidate();
      final newSeed = f.coordinator.beginGeneration();
      final newHost = _FakeHost(newSeed.source)..generation = 1;
      final newTransport = ComplexEditorTransport(newHost.command);
      await newTransport.load(newSeed, readOnly: false);
      await f.coordinator.bind(newTransport, generation: newHost.generation);
      f.host.readGate!.complete();

      expect(await checkpoint, isFalse);
      expect(f.controller.draft.source, '<p>original</p>');
      expect(f.memory.history, isEmpty);
      expect(f.host.endedSnapshots, 1);

      await f.transport.retire();
      await f.coordinator.beforeRetire(newTransport);
      await newTransport.retire();
      f.controller.dispose();
    },
  );

  test(
    'pre-SQL recovery failure unlocks only editable state and never calls repository',
    () async {
      final f = await _Fixture.open(withRecovery: true);
      f.memory.failWrite = true;
      f.host.userEdit('<p>recoverable source</p>');

      expect(await f.coordinator.save(), isNull);
      expect(f.repository.saveCalls, 0);
      expect(f.controller.canEdit, isTrue);
      expect(f.controller.hasPendingOperation, isFalse);
      expect(f.host.inputLocked, isFalse);
      expect(f.host.ackCount, 0);

      await f.retire();
      f.controller.dispose();
    },
  );

  test(
    'protected checkpoint/save recovery records never contain protected fields',
    () async {
      final f = await _Fixture.open(protected: true, withRecovery: true);
      const secret = '<p>PROTECTED_BODY_MARKER</p>';
      f.host.userEdit(secret);
      f.setMetadata('PROTECTED_TITLE_MARKER', const ['private-label']);
      await f.coordinator.checkpoint();
      await f.coordinator.save();

      final storedHistory = f.memory.history.join('\n');
      expect(storedHistory, isNot(contains('PROTECTED_BODY_MARKER')));
      expect(storedHistory, isNot(contains('PROTECTED_TITLE_MARKER')));
      expect(storedHistory, isNot(contains('PROTECTED_PASSWORD_MARKER')));

      await f.retire();
      f.controller.dispose();
    },
  );

  test(
    'forced retirement returns despite vault failure and leaves captured source in memory',
    () async {
      final f = await _Fixture.open(withRecovery: true);
      f.memory.failWrite = true;
      f.host.userEdit('<p>keep in memory for forced close</p>');

      await expectLater(f.coordinator.beforeRetire(f.transport), completes);

      expect(
        f.controller.draft.source,
        '<p>keep in memory for forced close</p>',
      );
      expect(f.coordinator.retirementFailure, isNotNull);
      await f.transport.retire();
      expect(f.host.closed, isTrue);
      f.controller.dispose();
    },
  );
}
