import 'dart:convert';
import 'api_client.dart';

const profileHomeModules = {
  'home',
  'notes',
  'tasks',
  'articles',
  'books',
  'bookmarks',
  'nav',
  'search',
};

class MemberProfile {
  const MemberProfile({
    required this.id,
    required this.account,
    required this.email,
    required this.role,
    required this.defaultHome,
  });
  final int id, role;
  final String account, email, defaultHome;
  bool sameEditableFields(MemberProfile other) =>
      id == other.id &&
      email == other.email &&
      defaultHome == other.defaultHome;
}

class ProfileDraft {
  ProfileDraft({required String email, required this.defaultHome})
    : email = email.trim();
  final String email, defaultHome;
  void validate() {
    for (var i = 0; i < email.length; i++) {
      final unit = email.codeUnitAt(i);
      if (unit >= 0xd800 && unit <= 0xdbff) {
        if (++i >= email.length ||
            email.codeUnitAt(i) < 0xdc00 ||
            email.codeUnitAt(i) > 0xdfff) {
          throw const FormatException('Invalid profile email Unicode');
        }
      } else if (unit >= 0xdc00 && unit <= 0xdfff) {
        throw const FormatException('Invalid profile email Unicode');
      }
    }
    if (utf8.encode(email).length > 200 ||
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email) ||
        !profileHomeModules.contains(defaultHome)) {
      throw const FormatException(
        'Valid email and an existing default module are required',
      );
    }
  }

  bool matches(MemberProfile value) =>
      email == value.email && defaultHome == value.defaultHome;
}

abstract interface class ProfileRepository {
  Future<MemberProfile> read();
  Future<void> update(ProfileDraft draft);
}

class RemoteProfileRepository implements ProfileRepository {
  RemoteProfileRepository(this.client, {required this.memberId}) {
    if (memberId <= 0) {
      throw const FormatException('Current member identity required');
    }
  }
  final BookstarkClient client;
  final int memberId;
  bool _memberVerified = false;
  String? _verifiedSession;
  @override
  Future<MemberProfile> read() async {
    _memberVerified = false;
    final session = client.exportSession()['token'];
    final row = await client.profileSettingsJson();
    if (client.exportSession()['token'] != session) {
      throw StateError('Profile session changed during read');
    }
    final id = row['member_id'],
        account = row['account'],
        email = row['email'],
        role = row['role'],
        home = row['default_home'];
    if (id is! int ||
        id != memberId ||
        account is! String ||
        account.isEmpty ||
        account.length > 2000 ||
        email is! String ||
        utf8.encode(email).length > 200 ||
        role is! int ||
        !{0, 1}.contains(role) ||
        home is! String ||
        !profileHomeModules.contains(home)) {
      throw const FormatException('Invalid current member profile');
    }
    _verifiedSession = session;
    _memberVerified = true;
    return MemberProfile(
      id: id,
      account: account,
      email: email,
      role: role,
      defaultHome: home,
    );
  }

  @override
  Future<void> update(ProfileDraft draft) async {
    draft.validate();
    if (!_memberVerified ||
        client.exportSession()['token'] != _verifiedSession) {
      throw StateError(
        'Current member profile must be verified before writing',
      );
    }
    final row = await client.profileSettingsJson(
      update: true,
      body: {'email': draft.email, 'default_home': draft.defaultHome},
    );
    if (!{0, 200}.contains(row['code']) || row['message'] is! String) {
      throw const FormatException('Missing actual profile update receipt');
    }
  }
}
