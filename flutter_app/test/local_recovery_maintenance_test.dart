import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/local_data_maintenance.dart';
import 'package:bookstark_flutter/core/local_draft_namespace.dart';
import 'package:bookstark_flutter/core/secure_record_store.dart';
import 'package:bookstark_flutter/core/html_recovery_vault.dart';
import 'package:bookstark_flutter/core/html_creation_vault.dart';
import 'package:bookstark_flutter/core/complex_recovery_vault.dart';
import 'package:bookstark_flutter/core/complex_recovery_store.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/document_creation.dart';

class _PendingWork {
  final gate = LocalDataMaintenance();
  final entered = Completer<void>(), release = Completer<void>();
  final events = <String>[];
  int calls = 0;
  Future<void> persist() async {
    final index = ++calls;
    if (index == 1) {
      entered.complete();
      await release.future;
    }
    events.add('persist$index');
  }

  Future<void> exercise(Future<void> Function() operation) async {
    final first = operation();
    await entered.future;
    final second = operation();
    final backup = gate.exclusive(() => events.add('snapshot'));
    expect(calls, 1);
    release.complete();
    await Future.wait([
      first,
      second,
      backup,
    ]).timeout(const Duration(seconds: 2));
    expect(events, ['persist1', 'persist2', 'snapshot']);
  }
}

class _Bytes implements ComplexRecoveryBytesStore {
  _Bytes(this.persist);
  final Future<void> Function() persist;
  @override
  Future<Uint8List?> read(String key) async => null;
  @override
  Future<void> write(String key, Uint8List bytes) => persist();
  @override
  Future<void> remove(String key) => persist();
}

void main() {
  test(
    'ordinary queued drafts finish before pending-recovery inventory',
    () async {
      final work = _PendingWork();
      final vault = SecureRecordStore(
        prefix: 'owned',
        namespace: 'local',
        maintenance: work.gate,
        readValue: (_) async => null,
        writeValue: (_, value) => work.persist(),
        deleteValue: (_) async {},
      );
      await work.exercise(() => vault.writeRecord(1, '原文😀'));
    },
  );

  test(
    'two HTML editor lifetimes retain leases while the global queue waits',
    () async {
      final work = _PendingWork();
      HtmlRecoveryVault make() => HtmlRecoveryVault(
        server: Uri.parse('https://local.invalid/owned44-edit'),
        memberId: 1,
        collection: 'note',
        localDatabase: true,
        maintenance: work.gate,
        readValue: (_) async => null,
        writeValue: (_, value) async {},
        deleteValue: (_) => work.persist(),
      );
      final a = make(), b = make();
      var calls = 0;
      await work.exercise(() => ++calls == 1 ? a.remove(1) : b.remove(1));
    },
  );

  test('HTML creation queue cannot delete recovery after inventory', () async {
    final work = _PendingWork();
    HtmlCreationVault make() => HtmlCreationVault(
      server: Uri.parse('https://local.invalid/owned44-new'),
      memberId: 1,
      collection: 'note',
      localDatabase: true,
      maintenance: work.gate,
      readValue: (_) async => null,
      writeValue: (_, value) async {},
      deleteValue: (_) => work.persist(),
    );
    final a = make(), b = make();
    var calls = 0;
    await work.exercise(() => ++calls == 1 ? a.remove() : b.remove());
  });

  test('complex encrypted file queue drains before inventory', () async {
    final work = _PendingWork();
    final vault = ComplexRecoveryVault(
      scope: 'a' * 64,
      collection: 'note',
      kind: ComplexEditorKind.drawing,
      store: _Bytes(work.persist),
      maintenance: work.gate,
    );
    await work.exercise(() => vault.remove(1));
  });

  test(
    'chapter creation journal waits before inventory even when queued',
    () async {
      final work = _PendingWork();
      final vault = DocumentCreationVault(
        namespace: 'local',
        maintenance: work.gate,
        readValue: (_) async => null,
        writeValue: (_, value) async {},
        deleteValue: (_) => work.persist(),
      );
      await work.exercise(vault.clear);
    },
  );

  test(
    'old draft callbacks cannot publish after generation retirement',
    () async {
      final gate = LocalDataMaintenance();
      final entered = Completer<void>(), release = Completer<void>();
      var writes = 0;
      final vault = SecureRecordStore(
        prefix: 'owned',
        namespace: 'local',
        maintenance: gate,
        readValue: (_) async => null,
        writeValue: (_, value) async {
          writes++;
        },
        deleteValue: (_) async {},
      );
      final restore = gate.exclusive(() async {
        entered.complete();
        await release.future;
        gate.retire();
      });
      await entered.future;
      final pending = vault.writeRecord(1, 'must not resurrect');
      final rejected = expectLater(
        pending,
        throwsA(isA<LocalStorageRetired>()),
      );
      release.complete();
      await Future.wait([restore, rejected]);
      expect(writes, 0);
    },
  );

  test('local nested scopes are distinct from a server mentioning local', () {
    final generation = LocalDraftNamespace.generation('b' * 32);
    for (final base in ['local', generation]) {
      for (final namespace in [
        base,
        jsonEncode([base, 'article']),
        jsonEncode([
          jsonEncode([base, 'topic']),
          7,
          'comment',
        ]),
      ]) {
        expect(LocalDraftNamespace.isLocal(namespace), isTrue);
      }
    }
    for (final namespace in [
      'https://local.invalid',
      jsonEncode(['https://local.invalid', 1]),
      jsonEncode([
        jsonEncode(['https://server.test/local', 1]),
        'article',
      ]),
      'local-generation:invalid',
      '[broken',
      '{}',
      jsonEncode([1, 'local']),
    ]) {
      expect(LocalDraftNamespace.isLocal(namespace), isFalse);
    }
  });
}
