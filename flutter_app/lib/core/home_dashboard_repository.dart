import 'dart:async';
import 'api_client.dart';
import 'home_dashboard_models.dart';

abstract interface class HomeDashboardRepository {
  Future<HomeDashboardSnapshot> load(
    HomeQuery query, {
    Future<void>? abortTrigger,
  });
  Future<List<HomeLayoutItem>> saveLayout(
    List<HomeLayoutItem> value, {
    Future<void>? abortTrigger,
  });
  Future<void> clearVisits({Future<void>? abortTrigger});
}

/// Optional local filter preferences; remote requests retain the server protocol.
abstract interface class HomeQueryPreferences {
  Future<HomeQuery?> restoreQuery();
  Future<void> rememberQuery(HomeQuery query);
}

final class HomeQueryPreferenceFailure implements Exception {
  const HomeQueryPreferenceFailure();
}

final class HomePreferencesCorrupt extends FormatException {
  const HomePreferencesCorrupt() : super('Invalid local home preferences');
}

/// No successful receipt was received. Read current state before another write.
final class HomeWriteUnconfirmed implements Exception {
  const HomeWriteUnconfirmed();
}

final class RemoteHomeDashboardRepository implements HomeDashboardRepository {
  RemoteHomeDashboardRepository(
    this.client, {
    this.deadline = const Duration(seconds: 15),
  });
  final BookstarkClient client;
  final Duration deadline;
  Future<T> _bounded<T>(
    Future<T> Function(Future<void>) action,
    Future<void>? parent,
  ) async {
    final abort = Completer<void>();
    void stop() {
      if (!abort.isCompleted) abort.complete();
    }

    if (parent != null) {
      unawaited(
        parent.then((_) => stop(), onError: (Object _, StackTrace _) => stop()),
      );
    }
    try {
      return await action(abort.future).timeout(
        deadline,
        onTimeout: () {
          stop();
          throw TimeoutException('Home request deadline');
        },
      );
    } finally {
      stop();
    }
  }

  @override
  Future<HomeDashboardSnapshot> load(
    HomeQuery query, {
    Future<void>? abortTrigger,
  }) => _bounded(
    (abort) async => HomeDashboardSnapshot.read(
      await client.get(query.apiPath, abortTrigger: abort),
    ),
    abortTrigger,
  );
  @override
  Future<List<HomeLayoutItem>> saveLayout(
    List<HomeLayoutItem> value, {
    Future<void>? abortTrigger,
  }) async {
    final normalized = readHomeLayout(value.map((e) => e.toJson()).toList());
    try {
      return await _bounded((abort) async {
        final reply = await client.mutate('PUT', '/api/home/layout', {
          'layout': normalized.map((e) => e.toJson()).toList(),
        }, abortTrigger: abort);
        if (reply['layout'] is! List) {
          throw const FormatException('Missing saved home layout');
        }
        return readHomeLayout(reply['layout']);
      }, abortTrigger);
    } on ApiFailure catch (error) {
      if ([
        400,
        401,
        403,
        404,
        405,
        409,
        413,
        422,
        429,
      ].contains(error.status)) {
        rethrow;
      }
      throw const HomeWriteUnconfirmed();
    } catch (_) {
      throw const HomeWriteUnconfirmed();
    }
  }

  @override
  Future<void> clearVisits({Future<void>? abortTrigger}) async {
    try {
      await _bounded(
        (abort) => client.mutate(
          'DELETE',
          '/api/home/recent',
          {},
          abortTrigger: abort,
        ),
        abortTrigger,
      );
    } on ApiFailure catch (error) {
      if ([
        400,
        401,
        403,
        404,
        405,
        409,
        413,
        422,
        429,
      ].contains(error.status)) {
        rethrow;
      }
      throw const HomeWriteUnconfirmed();
    } catch (_) {
      throw const HomeWriteUnconfirmed();
    }
  }
}

/// Resolves the current local database lazily, without opening another database
/// just because the root widget is rebuilding.
final class DeferredHomeDashboardRepository
    implements HomeDashboardRepository, HomeQueryPreferences {
  DeferredHomeDashboardRepository(this.create);
  final Future<HomeDashboardRepository> Function() create;
  Future<HomeDashboardRepository>? _opening;
  Future<HomeDashboardRepository> _get() async {
    final pending = _opening ??= create();
    try {
      return await pending;
    } catch (_) {
      if (identical(_opening, pending)) _opening = null;
      rethrow;
    }
  }

  @override
  Future<HomeQuery?> restoreQuery() async {
    final target = await _get();
    return target is HomeQueryPreferences
        ? (target as HomeQueryPreferences).restoreQuery()
        : null;
  }

  @override
  Future<void> rememberQuery(HomeQuery query) async {
    final target = await _get();
    if (target is HomeQueryPreferences) {
      await (target as HomeQueryPreferences).rememberQuery(query);
    }
  }

  @override
  Future<HomeDashboardSnapshot> load(
    HomeQuery query, {
    Future<void>? abortTrigger,
  }) async => (await _get()).load(query, abortTrigger: abortTrigger);
  @override
  Future<List<HomeLayoutItem>> saveLayout(
    List<HomeLayoutItem> value, {
    Future<void>? abortTrigger,
  }) async => (await _get()).saveLayout(value, abortTrigger: abortTrigger);
  @override
  Future<void> clearVisits({Future<void>? abortTrigger}) async =>
      (await _get()).clearVisits(abortTrigger: abortTrigger);
}

/// Root session/default-module effects stay scoped to the owner that created
/// this repository. The root callback checks its account generation again.
final class ObservedHomeDashboardRepository
    implements HomeDashboardRepository, HomeQueryPreferences {
  ObservedHomeDashboardRepository(
    this.inner, {
    this.onLoaded,
    this.onUnauthorized,
  });
  final HomeDashboardRepository inner;
  final FutureOr<void> Function()? onLoaded, onUnauthorized;
  Future<T> _attempt<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on ApiFailure catch (error) {
      if (error.status == 401) await onUnauthorized?.call();
      rethrow;
    }
  }

  @override
  Future<HomeQuery?> restoreQuery() async => inner is HomeQueryPreferences
      ? (inner as HomeQueryPreferences).restoreQuery()
      : null;
  @override
  Future<void> rememberQuery(HomeQuery query) async {
    if (inner is HomeQueryPreferences) {
      await (inner as HomeQueryPreferences).rememberQuery(query);
    }
  }

  @override
  Future<HomeDashboardSnapshot> load(
    HomeQuery query, {
    Future<void>? abortTrigger,
  }) => _attempt(() async {
    final result = await inner.load(query, abortTrigger: abortTrigger);
    await onLoaded?.call();
    return result;
  });
  @override
  Future<List<HomeLayoutItem>> saveLayout(
    List<HomeLayoutItem> value, {
    Future<void>? abortTrigger,
  }) => _attempt(() => inner.saveLayout(value, abortTrigger: abortTrigger));
  @override
  Future<void> clearVisits({Future<void>? abortTrigger}) =>
      _attempt(() => inner.clearVisits(abortTrigger: abortTrigger));
}
