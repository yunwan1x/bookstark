import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/local_recovery_inventory.dart';
import 'package:bookstark_flutter/core/protected_owned_marker_metadata.dart';
import 'local_recovery_inventory_test.dart' show prefs, complex, inventory;

void main() {
  String hex(String value) => List.filled(64, value).join();
  String owned() =>
      ProtectedOwnedMarkerMetadata.keyPrefix +
      base64Url.encode(
        utf8.encode(
          jsonEncode([
            jsonEncode([hex('a'), hex('b')]),
            0,
          ]),
        ),
      );
  String shared() => 'bookstark.protectedSharedOp.v1.${hex('c')}';
  test('all-owner opaque markers block 44 without reading any value', () async {
    final result = await inventory(
      prefs(keys: [owned(), shared()]),
      complex(),
      namespaces: {'local-generation:${hex('e').substring(0, 32)}'},
    ).read();
    expect(result.references.map((r) => r.kind), [
      'protected-owned',
      'protected-shared',
    ]);
    expect(result.needsAttention, isTrue);
    expect(result.requireClear, throwsA(isA<PendingLocalRecovery>()));
  });
  test('wrong storage and corrupt keys remain unknown blocking', () async {
    final result = await inventory(
      prefs(
        keys: [
          '${ProtectedOwnedMarkerMetadata.keyPrefix}broken',
          'bookstark.protectedSharedOp.v1.not-hex',
        ],
        html: [owned(), shared()],
      ),
      complex(),
    ).read();
    expect(result.references, isEmpty);
    expect(result.needsAttention, isTrue);
    expect(result.requireClear, throwsA(isA<PendingLocalRecovery>()));
  });
}
