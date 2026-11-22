class LocalTaskCreationMetadata {
  const LocalTaskCreationMetadata(this.scope, this.identity, this.slot);
  static const recordPrefix = 'bookstark.local-task-create.v1.';
  static const slotPrefix = 'bookstark.local-task-create-slot.v1.';
  final String scope, identity;
  final bool slot;
  static LocalTaskCreationMetadata parse(String key) {
    if (key.startsWith(recordPrefix)) {
      final parts = key.substring(recordPrefix.length).split('.');
      if (parts.length != 2 ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(parts[0]) ||
          !RegExp(r'^[a-f0-9]{32}$').hasMatch(parts[1])) {
        throw const FormatException('Invalid task creation record key');
      }
      return LocalTaskCreationMetadata(parts[0], parts[1], false);
    }
    if (!key.startsWith(slotPrefix)) {
      throw const FormatException('Unknown task creation key');
    }
    final scope = key.substring(slotPrefix.length);
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(scope)) {
      throw const FormatException('Invalid task creation account slot');
    }
    return LocalTaskCreationMetadata(scope, 'account', true);
  }
}
