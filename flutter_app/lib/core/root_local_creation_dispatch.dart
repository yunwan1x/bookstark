import 'local_store.dart';
import 'owned_writable_generation15.dart';
import 'resolved_local_storage.dart';

final class LocalCreationUnavailable implements Exception {
  const LocalCreationUnavailable();
  static const message =
      '此空间尚未提供安全的新建功能。已有资料仍可编辑，旧草稿保持不变。 / Safe creation is not available in this space yet. Existing content remains editable and old drafts are retained.';
  @override
  String toString() => message;
}

/// Actual Root creation dispatch gate. A sealed owned15 capability is never
/// mistaken for an ordinary14/16 LocalStore or a nullable-ID INSERT target.
abstract final class RootLocalCreationDispatch {
  static T dispatch<T>({
    required ResolvedLocalStorage? resolved,
    required OwnedWritableGeneration15? owned,
    required T Function(LocalStore ordinary) create,
  }) {
    if (owned != null ||
        resolved is! OrdinaryResolvedLocalStorage ||
        resolved.store.maintenance.retired) {
      throw const LocalCreationUnavailable();
    }
    return create(resolved.store);
  }
}
