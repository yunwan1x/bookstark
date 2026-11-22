import 'package:flutter/material.dart';
import '../../core/protected_shared_lifetime.dart';

/// A nested confirmation belongs to the same owner. Retirement removes these
/// exact routes, not whatever foreign route happens to be topmost later.
Future<T?> pushProtectedSharedRoute<T>(
  BuildContext context,
  ProtectedSharedLifetime owner,
  TransitionRoute<T> route,
) async {
  if (!context.mounted || !owner.current) {
    throw StateError('Protected shared route retired');
  }
  final navigator = Navigator.of(context), previous = owner.routeCloser;
  var pushed = false;
  Future<void> close() async {
    if (pushed) {
      if (route.isActive && navigator.mounted) navigator.removeRoute(route);
      await route.completed;
    }
    if (previous != null) await previous();
  }

  owner.bindRoute(close);
  try {
    final completion = navigator.push<T>(route);
    pushed = true;
    final result = await completion;
    await route.completed;
    return result;
  } finally {
    if (owner.current && identical(owner.routeCloser, close)) {
      owner.bindRoute(previous);
    }
  }
}
