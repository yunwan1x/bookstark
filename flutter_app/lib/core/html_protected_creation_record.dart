import 'html_creation_vault.dart'
    show validHtmlCreationKey, htmlCreationInputDigest;
import 'html_notes_repository.dart';

/// A protected server candidate replaces plaintext recovery before unlocking.
/// Candidate hints are never interpreted as an acknowledged POST identity.
class HtmlProtectedCreationRecord {
  HtmlProtectedCreationRecord({
    required this.key,
    required this.memberId,
    required this.collection,
    required this.inputDigest,
    this.createdId,
    this.candidateId,
  }) {
    if (!validHtmlCreationKey(key) ||
        memberId <= 0 ||
        !{'note', 'article'}.contains(collection) ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(inputDigest) ||
        createdId != null && createdId! <= 0 ||
        candidateId != null && candidateId! <= 0) {
      throw const FormatException('Invalid protected HTML creation record');
    }
  }
  factory HtmlProtectedCreationRecord.seal({
    required String key,
    required int memberId,
    required String collection,
    required HtmlNoteEdit edit,
    int? createdId,
    int? candidateId,
  }) => HtmlProtectedCreationRecord(
    key: key,
    memberId: memberId,
    collection: collection,
    inputDigest: htmlCreationInputDigest(edit),
    createdId: createdId,
    candidateId: candidateId,
  );
  final String key, collection, inputDigest;
  final int memberId;
  final int? createdId, candidateId;
  Map<String, Object?> toJson() => {
    'schema': 2,
    'protected': true,
    'pending': true,
    'key': key,
    'member_id': memberId,
    'collection': collection,
    'input_digest': inputDigest,
    'created_id': createdId,
    'candidate_id': candidateId,
  };
  factory HtmlProtectedCreationRecord.parse(Object? value) {
    const keys = {
      'schema',
      'protected',
      'pending',
      'key',
      'member_id',
      'collection',
      'input_digest',
      'created_id',
      'candidate_id',
    };
    if (value is! Map ||
        value.keys.length != keys.length ||
        value.keys.toSet().difference(keys).isNotEmpty ||
        value['schema'] != 2 ||
        value['protected'] != true ||
        value['pending'] != true ||
        value['key'] is! String ||
        value['member_id'] is! int ||
        value['collection'] is! String ||
        value['input_digest'] is! String ||
        value['created_id'] != null && value['created_id'] is! int ||
        value['candidate_id'] != null && value['candidate_id'] is! int) {
      throw const FormatException('Invalid protected HTML creation schema');
    }
    return HtmlProtectedCreationRecord(
      key: value['key'] as String,
      memberId: value['member_id'] as int,
      collection: value['collection'] as String,
      inputDigest: value['input_digest'] as String,
      createdId: value['created_id'] as int?,
      candidateId: value['candidate_id'] as int?,
    );
  }
}
