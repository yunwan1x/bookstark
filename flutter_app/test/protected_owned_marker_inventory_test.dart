import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/protected_owned_marker_inventory.dart';
import 'package:bookstark_flutter/core/protected_owned_marker_metadata.dart';

void main() {
  String hex(String v) => List.filled(64, v).join();
  String key(String owner) =>
      ProtectedOwnedMarkerMetadata.keyPrefix +
      base64Url.encode(
        utf8.encode(
          jsonEncode([
            jsonEncode([owner, hex('c')]),
            0,
          ]),
        ),
      );
  Map<String, Object?> metadata({
    List<String> keys = const [],
    List<String> html = const [],
    bool overflow = false,
  }) => {
    'format': 1,
    'secureKeys': keys,
    'htmlKeys': html,
    'overflow': overflow,
    'valuesIncluded': false,
  };
  test(
    'same owner blocks article module; other owners do not trap account return',
    () {
      final data = metadata(keys: [key(hex('a')), key(hex('b'))]);
      expect(protectedOwnedMarkersForOwner(data, hex('a')).length, 1);
      expect(protectedOwnedMarkersForOwner(data, hex('d')), isEmpty);
    },
  );
  test('missing/corrupt/overbound/wrong storage never means no records', () {
    for (final data in <Object?>[
      {'format': 1, 'secureKeys': [], 'htmlKeys': [], 'valuesIncluded': false},
      metadata(overflow: true),
      metadata(keys: ['${ProtectedOwnedMarkerMetadata.keyPrefix}broken']),
      metadata(html: [key(hex('a'))]),
      metadata(keys: List.filled(4097, 'irrelevant')),
    ]) {
      expect(
        () => protectedOwnedMarkersForOwner(data, hex('a')),
        throwsFormatException,
      );
    }
  });
}
