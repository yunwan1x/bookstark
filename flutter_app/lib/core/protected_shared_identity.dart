import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'anonymous_shared_capability.dart';
import 'protected_shared_journal.dart';

String protectedSharedIdentity(SharedCapabilityIdentity identity) {
  const names = [
    'share_id',
    'target_id',
    'owner_member_id',
    'book_id',
    'share_type',
    'format',
    'protected',
    'blog_type',
  ];
  return sha256
      .convert(
        utf8.encode(
          jsonEncode([for (final name in names) identity.json[name]]),
        ),
      )
      .toString();
}

ProtectedSharedObservation protectedSharedObservation(
  SharedCapabilitySource source,
) => ProtectedSharedObservation(
  identity: protectedSharedIdentity(source.identity),
  sourceDigest: source.document.digest,
  fingerprint: source.fingerprint,
  modified: source.modified,
);
