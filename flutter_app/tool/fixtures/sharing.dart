import 'package:bookstark_flutter/core/public_share_models.dart';
import 'package:bookstark_flutter/core/share_settings_repository.dart';
import 'package:bookstark_flutter/core/content_password_repository.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'public_shares.dart';

class SharingFixture implements ShareSettingsRepository {
  bool published = true;
  String token = List.filled(64, 'a').join();
  bool enabled = true;
  final bool loseTokenReceipt;
  SharingFixture({this.loseTokenReceipt = false});
  @override
  Future<bool> status(OwnerShareTarget target) async => published;
  OwnerShareReceipt receipt(OwnerShareTarget target) => OwnerShareReceipt(
    target,
    PublicShareReference(PublicSharesFixture.server, 'reader'),
    enabled ? token : '',
  );
  @override
  Future<OwnerShareReceipt> publish(OwnerShareTarget target) async {
    published = true;
    return receipt(target);
  }

  @override
  Future<OwnerShareReceipt> changeToken(
    OwnerShareTarget target,
    OwnerShareReceipt old,
    ShareTokenAction action,
  ) async {
    enabled = action != ShareTokenAction.disable;
    token = List.filled(64, 'b').join();
    if (loseTokenReceipt) {
      throw StateError('Fixture lost token receipt');
    }
    return receipt(target);
  }

  @override
  Future<void> unpublish(OwnerShareTarget target) async {
    published = false;
    enabled = false;
  }
}

class ContentPasswordFixture implements ContentPasswordRepository {
  ContentPasswordFixture({this.loseReceipt = false});
  String? password = 'fixture-only';
  final bool loseReceipt;
  @override
  Future<ContentProtection> read(int id) async =>
      ContentProtection(id: id, title: '阅读方法笔记', protected: password != null);
  @override
  Future<void> change(
    ContentProtection baseline, {
    required String newPassword,
    String? currentPassword,
  }) async {
    if (password != null && password != currentPassword) {
      throw const ApiFailure(400, 'Wrong fixture password');
    }
    password = newPassword.isEmpty ? null : newPassword;
    if (loseReceipt) {
      throw StateError('Fixture lost password receipt');
    }
  }

  @override
  Future<void> verify(int id, String candidate) async {
    if (candidate != password) {
      throw const ApiFailure(400, 'Wrong fixture password');
    }
  }
}
