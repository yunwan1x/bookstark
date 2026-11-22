import 'dart:convert';
import 'drive_models.dart';
import 'drive_repository.dart';
import 'secure_record_store.dart';

class FileDraftRecord {
  const FileDraftRecord({
    required this.id,
    required this.path,
    required this.content,
    required this.baseHash,
    required this.baseEtag,
    required this.mime,
    required this.hasBom,
    required this.isPublic,
    required this.publicPath,
    required this.changedOn,
    this.pendingHash,
  });
  final int id;
  final String path, content, baseHash, baseEtag, mime, publicPath;
  final bool hasBom, isPublic;
  final DateTime changedOn;
  final String? pendingHash;
  factory FileDraftRecord.fromDocument(
    DriveText document,
    String content, {
    String? pendingHash,
    DateTime? changedOn,
  }) => FileDraftRecord(
    id: document.node.id,
    path: document.node.path,
    content: content,
    baseHash: document.hash,
    baseEtag: document.node.etag,
    mime: document.node.mime,
    hasBom: document.hasBom,
    isPublic: document.node.isPublic,
    publicPath: document.node.publicPath,
    changedOn: changedOn ?? DateTime.now().toUtc(),
    pendingHash: pendingHash,
  );
  bool sameBase(DriveText document) =>
      id == document.node.id &&
      path == document.node.path &&
      baseHash == document.hash &&
      hasBom == document.hasBom &&
      mime == document.node.mime &&
      isPublic == document.node.isPublic &&
      publicPath == document.node.publicPath;
}

class FileDraftVault extends SecureRecordStore {
  FileDraftVault({
    required super.namespace,
    super.maintenance,
    required super.readValue,
    required super.writeValue,
    required super.deleteValue,
  }) : super(prefix: 'bookstark.file-draft.v1');
  List<Object> _identity(DriveNode node) => [node.id, drivePath(node.path)];
  Future<FileDraftRecord?> read(DriveNode node) async {
    final raw = await readRecord(_identity(node));
    if (raw == null) return null;
    if (utf8.encode(raw).length > 4 * 1024 * 1024 + 65536) {
      throw const FormatException('File draft exceeds record bound');
    }
    final row = jsonDecode(raw);
    if (row is! Map ||
        row['version'] != 1 ||
        row['id'] != node.id ||
        row['path'] != node.path ||
        row['content'] is! String ||
        row['base_hash'] is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(row['base_hash'] as String) ||
        row['base_etag'] is! String ||
        row['mime'] is! String ||
        row['bom'] is! bool ||
        row['is_public'] is! bool ||
        row['public_path'] is! String ||
        row['changed_on'] is! String ||
        row['pending_hash'] != null &&
            (row['pending_hash'] is! String ||
                !RegExp(
                  r'^[0-9a-f]{64}$',
                ).hasMatch(row['pending_hash'] as String))) {
      throw const FormatException('Invalid file draft record');
    }
    final text = row['content'] as String;
    if (utf8.encode('${row['bom'] == true ? '\ufeff' : ''}$text').length >
        maxDriveTextBytes) {
      throw const FormatException('File draft exceeds text editor bound');
    }
    if (row['is_public'] == true) drivePublicPath(row['public_path'] as String);
    return FileDraftRecord(
      id: node.id,
      path: node.path,
      content: text,
      baseHash: row['base_hash'] as String,
      baseEtag: row['base_etag'] as String,
      mime: row['mime'] as String,
      hasBom: row['bom'] as bool,
      isPublic: row['is_public'] as bool,
      publicPath: row['public_path'] as String,
      changedOn: DateTime.parse(row['changed_on'] as String),
      pendingHash: row['pending_hash'] as String?,
    );
  }

  Future<void> write(FileDraftRecord record) {
    if (drivePath(record.path) != record.path) {
      throw const FormatException('Draft path must be canonical');
    }
    if (record.id <= 0 ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(record.baseHash) ||
        record.pendingHash != null &&
            !RegExp(r'^[0-9a-f]{64}$').hasMatch(record.pendingHash!) ||
        utf8
                .encode('${record.hasBom ? '\ufeff' : ''}${record.content}')
                .length >
            maxDriveTextBytes) {
      throw const FormatException('Invalid file draft');
    }
    if (record.isPublic) drivePublicPath(record.publicPath);
    final raw = jsonEncode({
      'version': 1,
      'id': record.id,
      'path': record.path,
      'content': record.content,
      'base_hash': record.baseHash,
      'base_etag': record.baseEtag,
      'mime': record.mime,
      'bom': record.hasBom,
      'is_public': record.isPublic,
      'public_path': record.publicPath,
      'changed_on': record.changedOn.toUtc().toIso8601String(),
      'pending_hash': record.pendingHash,
    });
    if (utf8.encode(raw).length > 4 * 1024 * 1024 + 65536) {
      throw const FormatException('File draft exceeds record bound');
    }
    return writeRecord([record.id, record.path], raw);
  }

  Future<void> remove(DriveNode node) => removeRecord(_identity(node));
}
