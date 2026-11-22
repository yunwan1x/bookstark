import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'owned15_save_marker_metadata.dart';
import 'protected_owned_complex_journal.dart';

/// Same strict durable claim/known-storage-only/fresh-review primitive, with an
/// independent LOCAL15 principal and storage prefix. No fake server identity.
class Owned15SaveJournal extends ProtectedOwnedComplexJournal {
  Owned15SaveJournal({
    required String draftNamespace,
    required String collection,
    required int resourceId,
    required super.isCurrent,
    required super.readValue,
    required super.writeValue,
    required super.deleteValue,
    required super.flush,
  }) : super(
         ownerTag: ownerTagForGeneration(draftNamespace),
         scope: scopeForResource(
           draftNamespace: draftNamespace,
           collection: collection,
           resourceId: resourceId,
         ),
         recordPrefix: Owned15SaveMarkerMetadata.prefix,
       );
  static String ownerTagForGeneration(String draftNamespace) {
    if (draftNamespace.isEmpty || draftNamespace.length > 65536) {
      throw ArgumentError('Owned15 generation namespace required');
    }
    return sha256
        .convert(
          utf8.encode(jsonEncode(['owned15-save-owner-v1', draftNamespace])),
        )
        .toString();
  }

  /// The slot follows the resource across all7 kinds and protection changes.
  /// The full baseline fingerprint still binds epoch, actual kind/hash/cipher.
  static String scopeForResource({
    required String draftNamespace,
    required String collection,
    required int resourceId,
  }) {
    if (!const {'note', 'article'}.contains(collection) || resourceId <= 0) {
      throw ArgumentError('Owned15 resource identity required');
    }
    return sha256
        .convert(
          utf8.encode(
            jsonEncode([
              'owned15-save-resource-v1',
              ownerTagForGeneration(draftNamespace),
              collection,
              resourceId,
            ]),
          ),
        )
        .toString();
  }
}
