import 'dart:convert';

class TopicCreationMetadata {
  const TopicCreationMetadata(this.scope, this.identity, this.slot);
  static const recordPrefix = 'bookstark.topic-create.v1.';
  static const slotPrefix = 'bookstark.topic-create-slot.v1.';
  final String scope, identity;
  final bool slot;
  static TopicCreationMetadata parse(String key) {
    if (key.startsWith(recordPrefix)) {
      final suffix = key.substring(recordPrefix.length),
          parts = suffix.split('.');
      if (parts.length != 2 ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(parts[0]) ||
          !RegExp(r'^[a-f0-9]{32}$').hasMatch(parts[1])) {
        throw const FormatException('Invalid topic creation record key');
      }
      return TopicCreationMetadata(parts[0], parts[1], false);
    }
    if (!key.startsWith(slotPrefix) || key.length > 4096) {
      throw const FormatException('Invalid topic creation slot key');
    }
    final suffix = key.substring(slotPrefix.length);
    final v = jsonDecode(
      utf8.decode(base64Url.decode(suffix), allowMalformed: false),
    );
    if (v is! List ||
        v.length != 5 ||
        v[0] is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(v[0] as String) ||
        !{'topic', 'summary', 'comment'}.contains(v[1]) ||
        v[2] is! int ||
        v[3] is! String ||
        v[4] is! int ||
        (v[1] == 'topic' ? v[2] != 0 : v[2] <= 0) ||
        (v[1] == 'comment'
            ? !{'summary', 'resource', 'task'}.contains(v[3]) || v[4] <= 0
            : v[3] != '' || v[4] != 0) ||
        base64Url.encode(utf8.encode(jsonEncode(v))) != suffix) {
      throw const FormatException('Invalid topic creation slot tuple');
    }
    return TopicCreationMetadata(v[0] as String, suffix, true);
  }
}
