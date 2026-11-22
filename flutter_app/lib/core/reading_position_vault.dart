import 'dart:convert';
import 'secure_record_store.dart';

class ReadingPosition {
  const ReadingPosition(this.fraction, this.modifiedAt);
  final double fraction;
  final String modifiedAt;
}

class ReadingPositionVault extends SecureRecordStore {
  ReadingPositionVault({
    required super.namespace,
    super.maintenance,
    required super.readValue,
    required super.writeValue,
    required super.deleteValue,
  }) : super(prefix: 'bookstark.reading-position.v1');
  Future<ReadingPosition?> read(int documentId) async {
    final value = await readRecord(documentId);
    if (value == null) return null;
    if (value.length > 2048) {
      throw const FormatException('Invalid reading position');
    }
    final row = jsonDecode(value) as Map;
    final fraction = row['fraction'];
    if (row['version'] != 1 ||
        fraction is! num ||
        !fraction.isFinite ||
        fraction < 0 ||
        fraction > 1 ||
        row['modified_at'] is! String) {
      throw const FormatException('Invalid reading position');
    }
    return ReadingPosition(fraction.toDouble(), row['modified_at'] as String);
  }

  Future<void> write(int documentId, ReadingPosition position) {
    if (!position.fraction.isFinite ||
        position.fraction < 0 ||
        position.fraction > 1) {
      throw const FormatException('Invalid reading position');
    }
    return writeRecord(
      documentId,
      jsonEncode({
        'version': 1,
        'fraction': position.fraction,
        'modified_at': position.modifiedAt,
      }),
    );
  }
}
