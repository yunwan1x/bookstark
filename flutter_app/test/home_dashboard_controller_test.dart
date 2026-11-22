import 'dart:async';
import 'package:bookstark_flutter/core/home_dashboard_models.dart';
import 'package:bookstark_flutter/core/home_dashboard_repository.dart';
import 'package:bookstark_flutter/features/home_dashboard_controller.dart';
import 'package:flutter_test/flutter_test.dart';

HomeDashboardSnapshot snapshot(int id) => HomeDashboardSnapshot(
  layout: readHomeLayout(null),
  sections: const [],
  recent: [HomeRecentVisit(kind: 'note', id: id, title: 'Item $id')],
  activity: const {},
);

class FakeHome implements HomeDashboardRepository {
  final reads = <Completer<HomeDashboardSnapshot>>[];
  final aborted = <bool>[];
  int clears = 0, saves = 0;
  bool unknown = false;
  @override
  Future<HomeDashboardSnapshot> load(
    HomeQuery query, {
    Future<void>? abortTrigger,
  }) {
    final index = reads.length;
    final value = Completer<HomeDashboardSnapshot>();
    reads.add(value);
    aborted.add(false);
    unawaited(
      abortTrigger?.then((_) {
        aborted[index] = true;
      }),
    );
    return value.future;
  }

  @override
  Future<List<HomeLayoutItem>> saveLayout(
    List<HomeLayoutItem> value, {
    Future<void>? abortTrigger,
  }) async {
    saves++;
    if (unknown) throw const HomeWriteUnconfirmed();
    return value;
  }

  @override
  Future<void> clearVisits({Future<void>? abortTrigger}) async {
    clears++;
    if (unknown) throw const HomeWriteUnconfirmed();
  }
}

class QueryHome extends FakeHome implements HomeQueryPreferences {
  HomeQuery? stored;
  Completer<HomeQuery?>? restoring;
  bool failRemember = false;
  final remembered = <HomeQuery>[];
  final queries = <HomeQuery>[];
  @override
  Future<HomeQuery?> restoreQuery() async =>
      restoring == null ? stored : restoring!.future;
  @override
  Future<void> rememberQuery(HomeQuery query) async {
    remembered.add(query);
    if (failRemember) throw StateError('preferences unavailable');
    stored = query;
  }

  @override
  Future<HomeDashboardSnapshot> load(
    HomeQuery query, {
    Future<void>? abortTrigger,
  }) {
    queries.add(query);
    return super.load(query, abortTrigger: abortTrigger);
  }
}

Future<void> seed(HomeDashboardController c, FakeHome r) async {
  final load = c.load();
  r.reads.last.complete(snapshot(1));
  expect(await load, true);
}

void main() {
  test(
    'late prior-filter response cannot overwrite new filter or clear its loading flag',
    () async {
      final repo = FakeHome();
      final c = HomeDashboardController(repo);
      addTearDown(c.dispose);
      final first = c.load(HomeQuery(end: '2026-01-01'));
      final second = c.load(HomeQuery(end: '2026-02-01'));
      repo.reads[0].complete(snapshot(1));
      expect(await first, false);
      expect(c.loading, true);
      repo.reads[1].complete(snapshot(2));
      expect(await second, true);
      expect(c.snapshot!.recent.single.id, 2);
      expect(c.query.end, '2026-02-01');
      expect(repo.aborted.first, true);
      expect(c.loading, false);
    },
  );
  test(
    'unknown clear preserves visible visits and blocks replay until explicit readback',
    () async {
      final repo = FakeHome();
      final c = HomeDashboardController(repo);
      addTearDown(c.dispose);
      await seed(c, repo);
      repo.unknown = true;
      expect(await c.clearVisits(), false);
      expect(c.needsReadback, true);
      expect(c.snapshot!.recent.length, 1);
      expect(await c.clearVisits(), false);
      expect(repo.clears, 1);
      repo.unknown = false;
      final read = c.load();
      repo.reads.last.complete(snapshot(3));
      expect(await read, true);
      expect(c.needsReadback, false);
      expect(repo.clears, 1);
      expect(await c.clearVisits(), true);
      expect(repo.clears, 2);
      expect(c.snapshot!.recent, isEmpty);
    },
  );
  test(
    'uncertain layout is not published as saved and another write is not queued',
    () async {
      final repo = FakeHome();
      final c = HomeDashboardController(repo);
      addTearDown(c.dispose);
      await seed(c, repo);
      repo.unknown = true;
      expect(
        await c.saveLayout([const HomeLayoutItem(key: 'books', width: 3)]),
        false,
      );
      expect(c.snapshot!.layout.first.key, 'notes');
      expect(c.needsReadback, true);
      expect(await c.saveLayout(readHomeLayout(null)), false);
      expect(repo.saves, 1);
    },
  );
  test(
    'disposing retires actual read and ignores its later successful reply',
    () async {
      final repo = FakeHome();
      final c = HomeDashboardController(repo);
      var notices = 0;
      c.addListener(() => notices++);
      final pending = c.load();
      expect(notices, 1);
      c.dispose();
      repo.reads.single.complete(snapshot(4));
      expect(await pending, false);
      expect(repo.aborted.single, true);
      expect(notices, 1);
      expect(c.snapshot, isNull);
    },
  );
  test(
    'deferred and observed wrappers restore local filters across controller recreation',
    () async {
      final repo = QueryHome()
        ..stored = HomeQuery(
          month: DateTime(2024, 2),
          order: 'created',
          limit: 50,
          end: '2024-02-29',
          view: HomeCalendarView.month,
        );
      final wrapper = ObservedHomeDashboardRepository(
        DeferredHomeDashboardRepository(() async => repo),
      );
      final c = HomeDashboardController(wrapper);
      addTearDown(c.dispose);
      final pending = c.load();
      await Future<void>.delayed(Duration.zero);
      expect(repo.queries.single.toPreference(), repo.stored!.toPreference());
      repo.reads.single.complete(snapshot(1));
      expect(await pending, true);
      expect(c.query.end, '2024-02-29');
      expect(repo.remembered, isEmpty);
    },
  );
  test(
    'late preference restore cannot replace a newer explicit filter',
    () async {
      final repo = QueryHome()..restoring = Completer<HomeQuery?>();
      final c = HomeDashboardController(repo);
      addTearDown(c.dispose);
      final old = c.load();
      final next = HomeQuery(limit: 20, end: '2026-11-01');
      final newer = c.load(next);
      await Future<void>.delayed(Duration.zero);
      repo.reads.single.complete(snapshot(2));
      expect(await newer, true);
      repo.restoring!.complete(HomeQuery(limit: 5));
      expect(await old, false);
      expect(c.query.toPreference(), next.toPreference());
      expect(c.snapshot!.recent.single.id, 2);
      expect(repo.queries.length, 1);
    },
  );
  test(
    'failed filter preference write is explicit and retry retains selected filter',
    () async {
      final repo = QueryHome()..failRemember = true;
      final c = HomeDashboardController(repo);
      addTearDown(c.dispose);
      final next = HomeQuery(limit: 50);
      expect(await c.load(next), false);
      expect(c.problem, isA<HomeQueryPreferenceFailure>());
      expect(repo.reads, isEmpty);
      repo.failRemember = false;
      final retry = c.load();
      await Future<void>.delayed(Duration.zero);
      repo.reads.single.complete(snapshot(3));
      expect(await retry, true);
      expect(repo.stored!.limit, 50);
      expect(repo.remembered.length, 2);
    },
  );
}
