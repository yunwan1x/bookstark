import 'package:bookstark_flutter/core/reminder_repository.dart';

class ReminderFixture implements ReminderRepository {
  ReminderFixture({this.loseReceipt = false, this.available = true});
  final bool loseReceipt, available;
  ReminderDraft _preferences = const ReminderDraft(
    enabled: true,
    sendTime: '09:00',
    days: 1,
    overdue: true,
  );
  @override
  Future<ReminderSettings> read() async => ReminderSettings(
    preferences: _preferences,
    email: 'xiao.lin@example.test',
    available: available,
    processedDate: '',
  );
  @override
  Future<void> update(ReminderDraft draft) async {
    _preferences = draft;
    if (loseReceipt) {
      throw StateError('Fixture lost receipt');
    }
  }

  @override
  Future<void> sendTest(String confirmedEmail) async {
    if (confirmedEmail != 'xiao.lin@example.test') {
      throw const ReminderPreflightFailure();
    }
  }
}
