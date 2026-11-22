import 'dart:convert';
import 'complex_reading_protocol.dart';
import 'reading_position_vault.dart';
import 'secure_record_store.dart';

/// Separate typed records; no change to old Markdown fractional position bytes.
class ComplexReadingPositionVault extends SecureRecordStore {
  ComplexReadingPositionVault(
    ReadingPositionVault base, {
    required this.isCurrent,
  }) : super(
         prefix: 'bookstark.complex-reading-position.v1',
         namespace: base.namespace,
         maintenance: base.maintenance,
         readValue: (key) async {
           if (!isCurrent()) throw StateError('Reading scope retired');
           return base.readValue(key);
         },
         writeValue: (key, value) async {
           if (!isCurrent()) throw StateError('Reading scope retired');
           await base.writeValue(key, value);
         },
         deleteValue: (key) async {
           if (!isCurrent()) throw StateError('Reading scope retired');
           await base.deleteValue(key);
         },
       );
  final bool Function() isCurrent;
  Object _id(ComplexReadingIdentity identity) => [
    identity.bookId,
    identity.documentId,
    identity.kind.name,
  ];
  Future<ComplexReadingAnchor?> read(ComplexReadingIdentity identity) async {
    identity.validate();
    if (!isCurrent()) throw StateError('Reading scope retired');
    final bytes = await readRecord(_id(identity));
    if (!isCurrent()) throw StateError('Reading scope retired');
    if (bytes == null) return null;
    if (utf8.encode(bytes).length > 32768) {
      throw const FormatException('Reading anchor too large');
    }
    final v = jsonDecode(bytes);
    if (v is! Map || v['version'] != 1 || v['identity'] is! Map) {
      throw const FormatException('Invalid saved reading anchor');
    }
    final expected = identity.toJson(), actual = v['identity'] as Map;
    if (actual.length != expected.length ||
        !expected.entries.every((e) => actual[e.key] == e.value)) {
      return null; // same ID with another full source: never restore it.
    }
    return ComplexReadingAnchor.parse(identity.kind, v['anchor']);
  }

  Future<void> remove(ComplexReadingIdentity identity) async {
    identity.validate();
    if (!isCurrent()) throw StateError('Reading scope retired');
    await removeRecord(_id(identity));
  }

  Future<void> write(
    ComplexReadingIdentity identity,
    ComplexReadingAnchor anchor,
  ) async {
    identity.validate();
    if (!isCurrent() || anchor.kind != identity.kind) {
      throw StateError('Reading scope retired');
    }
    final checked = ComplexReadingAnchor.parse(anchor.kind, anchor.value);
    final value = jsonEncode({
      'version': 1,
      'identity': identity.toJson(),
      'anchor': checked.value,
    });
    if (utf8.encode(value).length > 32768) {
      throw const FormatException('Reading anchor too large');
    }
    await writeRecord(_id(identity), value);
    if (!isCurrent()) throw StateError('Reading scope retired');
  }
}
