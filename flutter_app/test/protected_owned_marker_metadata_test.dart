import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/protected_owned_marker_metadata.dart';

void main() {
  String repeated(String value, int count) => List.filled(count, value).join();
  String key(Object? id, {String? namespace}) =>
      ProtectedOwnedMarkerMetadata.keyPrefix +
      base64Url.encode(
        utf8.encode(
          jsonEncode([
            namespace ?? jsonEncode([repeated('a', 64), repeated('b', 64)]),
            id,
          ]),
        ),
      );
  test('canonical opaque owner and scope only', () {
    final value = ProtectedOwnedMarkerMetadata.parse(key(0));
    expect(value.ownerTag, repeated('a', 64));
    expect(value.scope, repeated('b', 64));
    expect(key(0), isNot(contains('password')));
  });
  test('strict malformed identity never treated as absent', () {
    for (final invalid in [
      key(null),
      key('0'),
      key(0.0),
      key(0, namespace: jsonEncode([repeated('a', 63), repeated('b', 64)])),
      key(0, namespace: '[ "NaN", "NaN" ]'),
      '${ProtectedOwnedMarkerMetadata.keyPrefix}broken!',
    ]) {
      expect(
        () => ProtectedOwnedMarkerMetadata.parse(invalid),
        throwsFormatException,
      );
    }
  });
}
