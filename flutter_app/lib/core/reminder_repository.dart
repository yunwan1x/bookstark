import 'dart:convert';
import 'api_client.dart';
import 'profile_repository.dart';

class ReminderDraft {
  const ReminderDraft({
    required this.enabled,
    required this.sendTime,
    required this.days,
    required this.overdue,
  });
  final bool enabled, overdue;
  final String sendTime;
  final int days;
  void validate() {
    if (!RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$').hasMatch(sendTime) ||
        days < 0 ||
        days > 30) {
      throw const FormatException('Invalid reminder preferences');
    }
  }

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'send_time': sendTime,
    'remind_before_days': days,
    'include_overdue': overdue,
  };
  bool same(ReminderDraft other) =>
      enabled == other.enabled &&
      sendTime == other.sendTime &&
      days == other.days &&
      overdue == other.overdue;
}

class ReminderSettings {
  const ReminderSettings({
    required this.preferences,
    required this.email,
    required this.available,
    required this.processedDate,
  });
  final ReminderDraft preferences;
  final String email, processedDate;
  final bool available;
  bool sameContext(ReminderSettings other) =>
      preferences.same(other.preferences) &&
      email == other.email &&
      available == other.available;
}

class ReminderPreflightFailure implements Exception {
  const ReminderPreflightFailure();
}

abstract interface class ReminderRepository {
  Future<ReminderSettings> read();
  Future<void> update(ReminderDraft draft);
  Future<void> sendTest(String confirmedEmail);
}

class RemoteReminderRepository implements ReminderRepository {
  RemoteReminderRepository(this.client, {required this.memberId});
  final BookstarkClient client;
  final int memberId;
  String? _verifiedSession;
  bool _verified = false;
  @override
  Future<ReminderSettings> read() async {
    _verified = false;
    final session = client.exportSession()['token'];
    await RemoteProfileRepository(client, memberId: memberId).read();
    final row = await client.reminderSettingsJson();
    if (client.exportSession()['token'] != session) {
      throw StateError('Reminder session changed');
    }
    final enabled = row['enabled'],
        time = row['send_time'],
        days = row['remind_before_days'],
        overdue = row['include_overdue'],
        email = row['email'],
        available = row['available'],
        processed = row['last_processed_date'];
    if (enabled is! bool ||
        time is! String ||
        days is! int ||
        overdue is! bool ||
        email is! String ||
        utf8.encode(email).length > 200 ||
        available is! bool ||
        processed is! String ||
        processed.length > 10 ||
        processed.isNotEmpty &&
            !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(processed)) {
      throw const FormatException('Invalid reminder response');
    }
    final draft = ReminderDraft(
      enabled: enabled,
      sendTime: time,
      days: days,
      overdue: overdue,
    )..validate();
    _verifiedSession = session;
    _verified = true;
    return ReminderSettings(
      preferences: draft,
      email: email,
      available: available,
      processedDate: processed,
    );
  }

  void _receipt(Map<String, Object?> row) {
    if (!{0, 200}.contains(row['code']) || row['message'] is! String) {
      throw const FormatException('Missing actual reminder receipt');
    }
  }

  @override
  Future<void> update(ReminderDraft draft) async {
    draft.validate();
    if (!_verified || client.exportSession()['token'] != _verifiedSession) {
      throw const ReminderPreflightFailure();
    }
    _receipt(await client.reminderSettingsJson(body: draft.toJson()));
  }

  @override
  Future<void> sendTest(String confirmedEmail) async {
    try {
      final fresh = await read();
      if (confirmedEmail.isEmpty || fresh.email != confirmedEmail) {
        throw const ReminderPreflightFailure();
      }
    } catch (_) {
      throw const ReminderPreflightFailure();
    }
    _receipt(await client.reminderTestJson());
  }
}
