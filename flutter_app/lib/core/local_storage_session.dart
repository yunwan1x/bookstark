import 'dart:io';
import 'package:path/path.dart' as paths;
import 'package:sqflite/sqflite.dart';
import 'local_data_maintenance.dart';
import 'local_data_paths.dart';
import 'local_store.dart';
import 'native_local_data_control.dart';

/// Resolve native activation state BEFORE any local database can be opened.
/// No missing-plugin/error fallback is permitted for a device storage session.
class LocalStorageSession {
  LocalStorageSession({
    required this.control,
    required this.privateSupport,
    required this.legacyDatabasePath,
    this.factory,
  });
  static final _usedReentry = Expando<bool>();
  final NativeLocalDataControl control;
  final Directory privateSupport;
  final String legacyDatabasePath;
  final DatabaseFactory? factory;

  Future<LocalStore> open({LocalControlReceipt? sourceReentry}) async {
    final state = await control.readState();
    final layout = LocalDataPaths.fromObservation(
      observation: state.observation,
      legacyDatabasePath: legacyDatabasePath,
      privateSupport: privateSupport,
    );
    final identity = paths.normalize(paths.absolute(layout.databasePath));
    var gate = LocalDataMaintenance.forStorage(identity);
    if (gate.retired) {
      if (sourceReentry == null ||
          (sourceReentry.action != 'reentered' &&
              sourceReentry.action != 'reentered-ready') ||
          sourceReentry.state.pointerRaw != state.pointerRaw ||
          sourceReentry.state.observation.needsReview ||
          _usedReentry[sourceReentry] == true) {
        throw const LocalStorageRetired();
      }
      _usedReentry[sourceReentry] = true;
      gate = LocalDataMaintenance.renewRetiredStorage(identity);
    }
    return LocalStore(
      path: layout.databasePath,
      dataPaths: layout,
      factory: factory,
      maintenance: gate,
    );
  }
}
