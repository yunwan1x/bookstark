class LocalLabelCreationMetadata {
  const LocalLabelCreationMetadata(this.scope, this.identity, this.slot);
  static const recordPrefix = 'bookstark.local-label-create.v1.';
  static const slotPrefix = 'bookstark.local-label-create-slot.v1.';
  final String scope, identity;
  final bool slot;
  static LocalLabelCreationMetadata parse(String key) {
    if (key.startsWith(recordPrefix)) {
      final parts = key.substring(recordPrefix.length).split('.');
      if (parts.length != 2 ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(parts[0]) ||
          !RegExp(r'^[a-f0-9]{32}$').hasMatch(parts[1])) {
        throw const FormatException('Invalid label creation record key');
      }
      return LocalLabelCreationMetadata(parts[0], parts[1], false);
    }
    if (!key.startsWith(slotPrefix)) {
      throw const FormatException('Unknown label creation key');
    }
    final scope = key.substring(slotPrefix.length);
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(scope)) {
      throw const FormatException('Invalid label creation account slot');
    }
    return LocalLabelCreationMetadata(scope, 'local-space', true);
  }
}
