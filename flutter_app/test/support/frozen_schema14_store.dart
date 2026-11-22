import 'package:bookstark_flutter/core/local_store.dart';
import 'package:sqflite/sqflite.dart';

/// Historical backup fixtures must contain actual frozen14 bytes, even when
/// the application active store advances. Never fake this by lowering version.
class FrozenSchema14Store extends LocalStore {
  FrozenSchema14Store({required super.path, required super.factory});
  Future<Database>? _fixture;
  @override
  Future<Database> get database => _fixture ??= factory.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: 14,
      onCreate: (db, _) => createLocalSchema14(db),
    ),
  );
  @override
  Future<void> close() async {
    final fixture = _fixture;
    _fixture = null;
    if (fixture != null) await (await fixture).close();
  }
}
