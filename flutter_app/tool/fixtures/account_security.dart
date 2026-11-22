import 'package:bookstark_flutter/core/account_password_repository.dart';

class AccountSecurityFixture implements AccountPasswordRepository {
  AccountSecurityFixture({
    this.loseReceipt = false,
    this.failFirstStore = false,
  });
  final bool loseReceipt, failFirstStore;
  String _password = 'current-pass';
  int _stores = 0;
  @override
  Future<void> change(String current, String next) async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    if (current != _password) {
      throw const AccountPasswordPreflightFailure();
    }
    _password = next;
    if (loseReceipt) {
      throw StateError('Fixture lost receipt');
    }
  }

  @override
  Future<void> verifyAndAdopt(String candidate) async {
    if (candidate != _password) {
      throw StateError('Fixture verification rejected');
    }
  }

  @override
  Future<bool> persistSession() async => !(failFirstStore && ++_stores == 1);
}
