import 'dart:convert';
import 'api_client.dart';
import 'profile_repository.dart';

void validateLoginPassword(String value, {bool newPassword = false}) {
  for (var i = 0; i < value.length; i++) {
    final unit = value.codeUnitAt(i);
    if (unit >= 0xd800 && unit <= 0xdbff) {
      if (++i >= value.length ||
          value.codeUnitAt(i) < 0xdc00 ||
          value.codeUnitAt(i) > 0xdfff) {
        throw const FormatException('Invalid login password Unicode');
      }
    } else if (unit >= 0xdc00 && unit <= 0xdfff) {
      throw const FormatException('Invalid login password Unicode');
    }
  }
  final length = utf8.encode(value).length;
  if (value.isEmpty ||
      newPassword && (value.runes.length < 6 || length > 72) ||
      !newPassword && length > 4096) {
    throw const FormatException('Invalid login password length');
  }
}

class AccountPasswordPreflightFailure implements Exception {
  const AccountPasswordPreflightFailure();
  @override
  String toString() => 'Account password preflight did not complete';
}

abstract interface class AccountPasswordRepository {
  Future<void> change(String current, String next);
  Future<void> verifyAndAdopt(String candidate);
  Future<bool> persistSession();
}

class RemoteAccountPasswordRepository implements AccountPasswordRepository {
  RemoteAccountPasswordRepository(
    this.client, {
    required this.member,
    required this.saveSession,
    BookstarkClient Function(String)? verifierFactory,
  }) : _verifierFactory =
           verifierFactory ?? ((server) => BookstarkClient(server));
  final BookstarkClient client;
  final MemberProfile member;
  final Future<bool> Function() saveSession;
  final BookstarkClient Function(String) _verifierFactory;
  @override
  Future<void> change(String current, String next) async {
    validateLoginPassword(current);
    validateLoginPassword(next, newPassword: true);
    try {
      final fresh = await RemoteProfileRepository(
        client,
        memberId: member.id,
      ).read();
      if (fresh.account != member.account) {
        throw const AccountPasswordPreflightFailure();
      }
    } catch (_) {
      throw const AccountPasswordPreflightFailure();
    }
    final row = await client.accountPasswordJson(current, next);
    if (!{0, 200}.contains(row['code']) || row['message'] is! String) {
      throw const FormatException('Missing actual account password receipt');
    }
  }

  @override
  Future<void> verifyAndAdopt(String candidate) async {
    validateLoginPassword(candidate, newPassword: true);
    final verifier = _verifierFactory(client.baseUri.toString());
    if (identical(verifier, client)) {
      throw StateError('Credential verification requires an isolated client');
    }
    verifier.language = client.language;
    try {
      if (verifier.baseUri != client.baseUri) {
        throw StateError('Credential verification must use the current server');
      }
      await verifier.credentialLoginJson(member.account, candidate);
      if (!verifier.exportSession().containsKey('token')) {
        throw const FormatException('No actual verified session cookie');
      }
      final fresh = await RemoteProfileRepository(
        verifier,
        memberId: member.id,
      ).read();
      if (fresh.account != member.account) {
        throw StateError('Verified credentials changed member identity');
      }
      client.restoreSession(verifier.exportSession());
    } finally {
      verifier.close();
    }
  }

  @override
  Future<bool> persistSession() async {
    if (!client.exportSession().containsKey('token')) {
      return false;
    }
    return saveSession();
  }
}
