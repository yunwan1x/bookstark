import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/secure_record_store.dart';
import 'package:bookstark_flutter/core/owned15_creation_marker_metadata.dart';

void main() {
  test('canonical real SecureRecordStore key yields only opaque owner', () {
    final store = SecureRecordStore(
      prefix: Owned15CreationMarkerMetadata.prefix,
      namespace: 'a' * 64,
      readValue: (key) async => null,
      writeValue: (key, value) async {},
      deleteValue: (key) async {},
    );
    expect(
      Owned15CreationMarkerMetadata.parse(store.metadataKey(0)).ownerTag,
      'a' * 64,
    );
  });
  test('malformed identities and noncanonical encoding are never absence', () {
    for (final value in [
      ['a' * 64, 1],
      ['a' * 64, null],
      ['private title', 0],
      ['a' * 64, 0, 'extra'],
    ]) {
      final key =
          Owned15CreationMarkerMetadata.keyPrefix +
          base64Url.encode(utf8.encode(jsonEncode(value)));
      expect(
        () => Owned15CreationMarkerMetadata.parse(key),
        throwsFormatException,
      );
    }
    expect(
      () => Owned15CreationMarkerMetadata.parse(
        '${Owned15CreationMarkerMetadata.prefix}.${'x' * 700}',
      ),
      throwsFormatException,
    );
  });
}
