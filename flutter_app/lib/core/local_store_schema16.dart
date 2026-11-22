import 'package:sqflite/sqflite.dart';
import 'local_store.dart';
import 'local_assistant_creation_receipts.dart';

/// Active format; the frozen14 creator remains available for old backups.
/// Version15 is an isolated legacy-import candidate and must never be promoted
/// by this upgrade path.
const assistantActiveSchemaVersion = 16;

Future<void> createLocalSchema16(DatabaseExecutor db) async {
  await createLocalSchema14(db);
  await db.execute(assistantCreationReceiptSchema);
}

/// Must be called inside an owned migration transaction. A failed receipt DDL
/// leaves both the version and every original table unchanged.
Future<void> extendSchema14ForAssistant16(DatabaseExecutor tx) async {
  final version = await tx.rawQuery('PRAGMA user_version');
  if (version.length != 1 || version.single.values.single != 14) {
    throw const FormatException('Assistant migration requires active schema14');
  }
  await tx.execute(assistantCreationReceiptSchema);
  await tx.execute('PRAGMA user_version = 16');
}
