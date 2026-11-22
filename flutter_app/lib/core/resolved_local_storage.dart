import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'local_data_paths.dart';
import 'package:path/path.dart' as path;
import 'native_local_data_control.dart';
import 'local_storage_session.dart';
import 'local_store.dart';
import 'native_local_content_crypto.dart';
import 'owned_writable_generation15.dart';

/// Resolve the native pointer and schema BEFORE choosing any writable opener.
/// A read-only review/candidate object cannot be promoted through this API.
sealed class ResolvedLocalStorage {
  const ResolvedLocalStorage();
  Future<void> retire();

  static Future<ResolvedLocalStorage> open({
    required LocalStorageSession session,
    required Directory verificationWorkspace,
    required bool Function() isCurrentScope,
    LocalControlReceipt? sourceReentry,
    NativeLocalContentCrypto? crypto,
  }) async {
    void scope() {
      if (!isCurrentScope()) throw StateError('Local storage owner changed');
    }

    scope();
    final state = await session.control.readState();
    scope();
    final layout = LocalDataPaths.fromObservation(
      observation: state.observation,
      legacyDatabasePath: session.legacyDatabasePath,
      privateSupport: session.privateSupport,
    );
    final generation = state.observation.pointer?.generation;
    if (generation != null) {
      final canonical = await session.privateSupport.resolveSymbolicLinks();
      var current = session.privateSupport.path;
      for (final component in [
        'local-data-v1',
        'generations',
        generation,
        'database',
      ]) {
        current = path.join(current, component);
        if (await FileSystemEntity.type(current, followLinks: false) !=
            FileSystemEntityType.directory) {
          throw const FormatException('Active generation path unavailable');
        }
        scope();
      }
      if (await File(layout.databasePath).resolveSymbolicLinks() !=
          path.join(
            canonical,
            'local-data-v1',
            'generations',
            generation,
            'database',
            'content.db',
          )) {
        throw const FormatException(
          'Active generation database escaped its owner',
        );
      }
    }
    final type = await FileSystemEntity.type(
      layout.databasePath,
      followLinks: false,
    );
    scope();
    int? version;
    if (type == FileSystemEntityType.file) {
      Database? readOnly;
      try {
        readOnly = await (session.factory ?? databaseFactory).openDatabase(
          layout.databasePath,
          options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
        );
        scope();
        final rows = await readOnly.rawQuery('PRAGMA user_version');
        scope();
        if (rows.length != 1 || rows.single.values.single is! int) {
          throw const FormatException('Local database schema unavailable');
        }
        version = rows.single.values.single as int;
      } finally {
        await readOnly?.close();
      }
    } else if (type != FileSystemEntityType.notFound ||
        state.observation.pointer != null) {
      throw const FormatException('Active local database is missing or linked');
    }
    // Positive schema evidence only. Unknown/corrupt versions never reach
    // LocalStore's onUpgrade, even if a caller mistakenly expects the old UI.
    if (version != null && (version < 1 || version > 16)) {
      throw const FormatException('Unsupported writable local schema');
    }
    final fresh = await session.control.readState();
    scope();
    if (fresh.pointerRaw != state.pointerRaw ||
        fresh.intentRaw != state.intentRaw ||
        fresh.observation.needsReview) {
      throw StateError('Local storage changed during schema resolution');
    }
    if (version == 15) {
      final pointer = fresh.observation.pointer;
      if (pointer == null) {
        throw StateError(
          'Schema15 requires explicit owned generation activation',
        );
      }
      final owner = await OwnedWritableGeneration15.openActive(
        privateSupport: session.privateSupport,
        workspace: verificationWorkspace,
        expectedPointer: pointer,
        isCurrentScope: isCurrentScope,
        control: session.control,
        factory: session.factory,
        crypto: crypto,
      );
      try {
        scope();
        await owner.confirmCurrent();
        return Owned15ResolvedLocalStorage._(owner);
      } catch (_) {
        await owner.retire();
        rethrow;
      }
    }
    final store = await session.open(sourceReentry: sourceReentry);
    try {
      scope();
      final latest = await session.control.readState();
      scope();
      if (latest.pointerRaw != fresh.pointerRaw ||
          latest.intentRaw != fresh.intentRaw ||
          latest.observation.needsReview) {
        throw StateError('Local storage changed before ordinary opener');
      }
      return OrdinaryResolvedLocalStorage._(store);
    } catch (_) {
      await store.close();
      rethrow;
    }
  }
}

final class OrdinaryResolvedLocalStorage extends ResolvedLocalStorage {
  const OrdinaryResolvedLocalStorage._(this.store);
  final LocalStore store;
  @override
  Future<void> retire() => store.close();
}

final class Owned15ResolvedLocalStorage extends ResolvedLocalStorage {
  const Owned15ResolvedLocalStorage._(this.owner);
  final OwnedWritableGeneration15 owner;
  @override
  Future<void> retire() => owner.retire();
}
