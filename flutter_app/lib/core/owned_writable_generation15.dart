import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import 'local_data_paths.dart';
import 'local_data_maintenance.dart';
import 'local_generation_state.dart';
import 'local_generation_content_repository.dart';
import 'native_local_content_crypto.dart';
import 'native_local_data_control.dart';
import 'owned_generation15_schema.dart';

import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'attachments.dart';
import 'bounded_note_text_reader.dart';
import 'complex_editor_document.dart';
import 'local_content_protection_format.dart';
import 'local_content_crypto_limits.dart';

part 'owned15_generation_creator.dart';

/// A live, writable OWNED generation. No constructor accepts a Database or a
/// candidate/review session. Root must register this owner before exposing it,
/// synchronously retire it before any control transition, and await drain.
final class OwnedWritableGeneration15 {
  OwnedWritableGeneration15._(
    this.generation,
    this.pointer,
    this._database,
    this._control,
    this._scope,
    this._canonicalRoot,
    this._lease,
    this._maintenance,
    NativeLocalContentCrypto? crypto,
  ) {
    content = LocalGenerationContentRepository(
      database: _database,
      generation: generation,
      isCurrent: () => current,
      maintenance: _maintenance,
      crypto: crypto,
      beforeWrite: confirmCurrent,
    );
  }
  final LocalDataPaths generation;
  final LocalGenerationPointer pointer;
  final Database _database;
  final NativeLocalDataControl _control;
  final bool Function() _scope;
  final String _canonicalRoot;
  final Object _lease;
  final LocalDataMaintenance _maintenance;
  late final LocalGenerationContentRepository content;
  final Set<Owned15GenerationCreator> _creationOwners = {};
  bool _retired = false;
  Future<void>? _closing;
  static final _leases = <String, Object>{};
  String get _canonicalDatabase => path.join(
    _canonicalRoot,
    'local-data-v1',
    'generations',
    generation.generationId!,
    'database',
    'content.db',
  );
  bool get current {
    if (_retired ||
        !_database.isOpen ||
        !identical(_leases[_canonicalDatabase], _lease)) {
      return false;
    }
    try {
      return _scope();
    } catch (_) {
      return false;
    }
  }

  static Future<void> _paths(
    LocalDataPaths generation,
    String canonicalRoot,
  ) async {
    final support = generation.privateSupport;
    if (await FileSystemEntity.type(support.path, followLinks: false) !=
            FileSystemEntityType.directory ||
        await support.resolveSymbolicLinks() != canonicalRoot) {
      throw const FormatException('Owned private root changed');
    }
    var root = support.path;
    for (final component in [
      'local-data-v1',
      'generations',
      generation.generationId!,
      'database',
    ]) {
      root = path.join(root, component);
      if (await FileSystemEntity.type(root, followLinks: false) !=
          FileSystemEntityType.directory) {
        throw const FormatException('Owned generation directory unavailable');
      }
    }
    if (await FileSystemEntity.type(
              generation.databasePath,
              followLinks: false,
            ) !=
            FileSystemEntityType.file ||
        await File(generation.databasePath).length() > 512 * 1024 * 1024 ||
        await File(generation.databasePath).resolveSymbolicLinks() !=
            path.join(
              canonicalRoot,
              'local-data-v1',
              'generations',
              generation.generationId!,
              'database',
              'content.db',
            )) {
      throw const FormatException('Owned database identity changed');
    }
    for (final folder in [generation.attachments, generation.driveBlobs]) {
      if (await FileSystemEntity.type(folder.path, followLinks: false) !=
              FileSystemEntityType.directory ||
          await folder.resolveSymbolicLinks() !=
              path.join(
                canonicalRoot,
                'local-data-v1',
                'generations',
                generation.generationId!,
                path.basename(folder.path),
              )) {
        throw const FormatException('Owned resource root changed');
      }
    }
    for (final suffix in ['-wal', '-shm', '-journal']) {
      final type = await FileSystemEntity.type(
        generation.databasePath + suffix,
        followLinks: false,
      );
      if (type != FileSystemEntityType.notFound &&
          type != FileSystemEntityType.file) {
        throw const FormatException('Owned database sidecar identity changed');
      }
    }
  }

  static void _matches(
    LocalDataControlState state,
    LocalGenerationPointer expected,
  ) {
    if (state.observation.phase != LocalGenerationPhase.ready ||
        state.intentRaw != null ||
        state.pointerRaw != expected.encode() ||
        state.observation.pointer?.generation != expected.generation) {
      throw const FormatException(
        'Owned activation requires unchanged ready pointer',
      );
    }
  }

  /// Always uses the active native pointer. Schema15 backup validation and the
  /// durable activation receipt must precede this call; no migration occurs.
  static Future<OwnedWritableGeneration15> openActive({
    required Directory privateSupport,
    required Directory workspace,
    required LocalGenerationPointer expectedPointer,
    required bool Function() isCurrentScope,
    NativeLocalDataControl? control,
    DatabaseFactory? factory,
    NativeLocalContentCrypto? crypto,
  }) async {
    final native = control ?? NativeLocalDataControl(),
        dbFactory = factory ?? databaseFactory;
    final opening = Stopwatch()..start();
    void scope() {
      if (!isCurrentScope() || opening.elapsed >= const Duration(seconds: 90)) {
        throw StateError(
          'Owned activation retired or verification deadline exceeded',
        );
      }
    }

    bool verifying() {
      scope();
      return true;
    }

    scope();
    _matches(await native.readState(), expectedPointer);
    scope();
    if (await FileSystemEntity.type(privateSupport.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw const FormatException('Fixed application private root required');
    }
    final canonical = await privateSupport.resolveSymbolicLinks();
    scope();
    final generation = LocalDataPaths.generation(
      id: expectedPointer.generation,
      privateSupport: privateSupport,
    );
    await _paths(generation, canonical);
    scope();
    // Workspace is a separate, bounded application-private verification area.
    if (!path.isWithin(privateSupport.path, workspace.path) ||
        path.isWithin(path.dirname(generation.databasePath), workspace.path)) {
      throw const FormatException(
        'Separate private verification workspace required',
      );
    }
    if (await FileSystemEntity.type(workspace.path, followLinks: false) !=
            FileSystemEntityType.directory ||
        await workspace.resolveSymbolicLinks() !=
            path.join(
              canonical,
              path.relative(workspace.path, from: privateSupport.path),
            )) {
      throw const FormatException('Verification workspace identity changed');
    }
    final canonicalDatabase = path.join(
      canonical,
      'local-data-v1',
      'generations',
      generation.generationId!,
      'database',
      'content.db',
    );
    final lease = Object();
    if (_leases.containsKey(canonicalDatabase)) {
      throw StateError('Owned generation already open');
    }
    _leases[canonicalDatabase] = lease;
    Database? reading, writing;
    var published = false;
    try {
      final gate = OwnedGeneration15SchemaGate();
      reading = await dbFactory.openDatabase(
        generation.databasePath,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      scope();
      await reading.execute('PRAGMA trusted_schema=OFF');
      await gate.verify(reading, factory: dbFactory, workspace: workspace);
      scope();
      final before = await gate.rowDigests(reading, isCurrent: verifying);
      scope();
      await reading.close();
      reading = null;
      await _paths(generation, canonical);
      scope();
      _matches(await native.readState(), expectedPointer);
      scope();
      // No version, onCreate, onUpgrade, CREATE or ALTER callbacks.
      writing = await dbFactory.openDatabase(
        generation.databasePath,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      scope();
      await writing.execute('PRAGMA trusted_schema=OFF');
      final after = await gate.rowDigests(writing, isCurrent: verifying);
      scope();
      if (before.length != after.length ||
          before.entries.any((e) => after[e.key] != e.value)) {
        throw const FormatException(
          'Opening owned generation changed original rows',
        );
      }
      await _paths(generation, canonical);
      scope();
      _matches(await native.readState(), expectedPointer);
      scope();
      final owner = OwnedWritableGeneration15._(
        generation,
        expectedPointer,
        writing,
        native,
        isCurrentScope,
        canonical,
        lease,
        LocalDataMaintenance(),
        crypto,
      );
      published = true;
      return owner;
    } finally {
      await reading?.close();
      if (!published) {
        await writing?.close();
        if (identical(_leases[canonicalDatabase], lease)) {
          _leases.remove(canonicalDatabase);
        }
      }
    }
  }

  /// Fresh native check immediately after crypto and before a write transaction.
  Future<void> confirmCurrent() async {
    if (!current) {
      throw const GenerationContentFailure(GenerationContentReason.retired);
    }
    try {
      final state = await _control.readState();
      if (!current) throw StateError('Owned activation retired');
      _matches(state, pointer);
      await _paths(generation, _canonicalRoot);
      if (!current) throw StateError('Owned activation retired');
    } catch (_) {
      _retired = true;
      for (final creator in _creationOwners.toList()) {
        creator._cancel();
      }
      content.dispose();
      // Root joins retire() outside this active maintenance operation. Never
      // attempt a shared->exclusive upgrade from the before-write callback.
      throw const GenerationContentFailure(GenerationContentReason.retired);
    }
  }

  /// For the dedicated15 exporter only. It must validate all original tables,
  /// provenance and blobs; snapshots never include unlocked handles/passwords.
  Future<T> exclusiveSnapshot<T>(
    Future<T> Function(Database database) snapshot,
  ) => _maintenance.exclusive(() async {
    await confirmCurrent();
    return snapshot(_database);
  });

  /// Only the outermost fully-drained owned snapshot operation may seal a
  /// source AFTER its complete retained archive has been durably published.
  /// No read-only session exposes this operation.
  Future<void> sealForActivationWithinSnapshot() async {
    if (_maintenance.exclusiveIdentity == null ||
        !_maintenance.exclusiveOperationDrained ||
        _closing != null) {
      throw StateError('Activation sealing requires the source snapshot lease');
    }
    await confirmCurrent();
    _retired = true;
    for (final creator in _creationOwners.toList()) {
      creator._cancel();
    }
    content.dispose();
    try {
      await content.crypto.drain();
      await _database.close();
      _creationOwners.clear();
      _maintenance.retire();
    } finally {
      if (!_database.isOpen &&
          _maintenance.retired &&
          identical(_leases[_canonicalDatabase], _lease)) {
        _leases.remove(_canonicalDatabase);
      }
    }
  }

  Future<void> retire() {
    if (_maintenance.retired && !_database.isOpen) return Future<void>.value();
    _retired = true;
    for (final creator in _creationOwners.toList()) {
      creator._cancel();
    }
    content.dispose(); // synchronous rejection and handle erasure
    final pending = _closing;
    if (pending != null) return pending;
    final work = _maintenance.exclusive(() async {
      try {
        await content.crypto.drain();
        await _database.close();
        _creationOwners.clear();
        _maintenance.retire();
      } finally {
        if (!_database.isOpen &&
            _maintenance.retired &&
            identical(_leases[_canonicalDatabase], _lease)) {
          _leases.remove(_canonicalDatabase);
        }
      }
    });
    _closing = work;
    unawaited(
      work.catchError((Object _, StackTrace _) {
        if (identical(_closing, work)) _closing = null;
      }),
    );
    return work;
  }
}
