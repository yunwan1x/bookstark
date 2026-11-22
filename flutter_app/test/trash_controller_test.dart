import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/trash_repository.dart';
import 'package:bookstark_flutter/core/trash_controller.dart';

TrashEntry entry(int id) => TrashEntry(
  id: id,
  memberId: 7,
  type: 'blog',
  name: 'note$id',
  deletedAt: '2026-11-05T08:00:00Z',
);

class Repo implements TrashRepository {
  final rows = [entry(1), entry(2), entry(3)];
  int writes = 0, reads = 0, probes = 0;
  int? rejectId, loseId;
  bool failProbe = false, disposed = false;
  Completer<void>? writeGate;
  @override
  Future<TrashPageData> read({String type = '', int page = 1}) async {
    reads++;
    return TrashPageData(
      entries: rows,
      total: rows.length,
      page: page,
      pageSize: 20,
    );
  }

  @override
  Future<void> apply(TrashEntry row, TrashOperation operation) async {
    writes++;
    if (row.id == rejectId) {
      throw const TrashPreflightFailure();
    }
    await writeGate?.future;
    rows.removeWhere((v) => v.id == row.id);
    if (row.id == loseId) {
      throw StateError('Lost receipt');
    }
  }

  @override
  Future<bool> isAbsent(TrashEntry row) async {
    probes++;
    if (failProbe) {
      throw StateError('Read unavailable');
    }
    return !rows.any((v) => v.id == row.id);
  }

  @override
  void dispose() {
    disposed = true;
  }
}

void main() {
  test('selection is explicit and readonly navigation never writes', () async {
    final r = Repo(), c = TrashController(Repo());
    c.dispose();
    final controller = TrashController(r);
    await controller.load();
    expect(controller.selected, isEmpty);
    controller.selectPage();
    expect(controller.selected.length, 3);
    await controller.load(filter: 'task');
    expect(controller.type, '');
    controller.clearSelection();
    await controller.load(filter: 'task');
    expect(controller.type, 'task');
    expect(r.writes, 0);
    controller.dispose();
  });
  test(
    'partial known rejection keeps only failed selection, checks every acknowledged removal',
    () async {
      final r = Repo()..rejectId = 2;
      final c = TrashController(r);
      await c.load();
      c.selectPage();
      await c.apply(c.selected.values.toList(), TrashOperation.restore);
      expect(r.writes, 3);
      expect(r.probes, 2);
      expect(c.selected.keys, [2]);
      expect(c.results[2]!.phase, TrashItemPhase.failed);
      expect(c.results[1]!.phase, TrashItemPhase.acknowledgedRemoved);
      expect(c.results[3]!.phase, TrashItemPhase.acknowledgedRemoved);
      c.dispose();
    },
  );
  test(
    'unknown receipt stops remaining writes and explicit verification never repeats mutation',
    () async {
      final r = Repo()..loseId = 1;
      final c = TrashController(r);
      await c.load();
      c.selectPage();
      await c.apply(c.selected.values.toList(), TrashOperation.delete);
      expect(r.writes, 1);
      expect(c.unresolved, true);
      expect(c.selected.length, 3);
      await c.apply([entry(1)], TrashOperation.delete);
      expect(r.writes, 1);
      await c.verify();
      expect(r.writes, 1);
      expect(c.results[1]!.phase, TrashItemPhase.absentWithoutReceipt);
      expect(c.selected.keys, [2, 3]);
      expect(c.unresolved, false);
      c.dispose();
    },
  );
  test(
    'acknowledged operation with failed readback retains selection and only readback is retried',
    () async {
      final r = Repo()..failProbe = true;
      final c = TrashController(r);
      await c.load();
      await c.apply([entry(1)], TrashOperation.restore);
      expect(c.results[1]!.phase, TrashItemPhase.unverified);
      expect(c.selected.keys, [1]);
      r.failProbe = false;
      await c.verify();
      expect(r.writes, 1);
      expect(c.results[1]!.phase, TrashItemPhase.acknowledgedRemoved);
      expect(c.selected, isEmpty);
      c.dispose();
    },
  );
  test(
    'unobserved metadata cannot trigger writes and disposal ignores late receipt',
    () async {
      final r = Repo();
      final c = TrashController(r);
      await c.load();
      await c.apply([entry(99)], TrashOperation.delete);
      expect(r.writes, 0);
      r.writeGate = Completer<void>();
      final pending = c.apply([entry(1)], TrashOperation.delete);
      await Future<void>.delayed(Duration.zero);
      c.dispose();
      r.writeGate!.complete();
      await pending;
      expect(r.disposed, true);
      expect(c.data, isNull);
      expect(c.results, isEmpty);
      expect(r.probes, 0);
    },
  );
}
