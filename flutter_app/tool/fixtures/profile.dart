import 'package:flutter/material.dart';
import 'package:bookstark_flutter/core/profile_repository.dart';
import 'package:bookstark_flutter/features/profile/profile_page.dart';

class ProfileFixture implements ProfileRepository {
  static const initial = MemberProfile(
    id: 7,
    account: 'xiao_lin',
    email: 'xiao.lin@example.test',
    role: 1,
    defaultHome: 'notes',
  );
  ProfileFixture({this.loseReceipt = false, bool conflict = false})
    : current = conflict
          ? const MemberProfile(
              id: 7,
              account: 'xiao_lin',
              email: 'remote.profile@example.test',
              role: 1,
              defaultHome: 'books',
            )
          : initial;
  MemberProfile current;
  final bool loseReceipt;
  @override
  Future<MemberProfile> read() async => current;
  @override
  Future<void> update(ProfileDraft draft) async {
    current = MemberProfile(
      id: 7,
      account: 'xiao_lin',
      email: draft.email,
      role: 1,
      defaultHome: draft.defaultHome,
    );
    if (loseReceipt) {
      throw StateError('Fixture lost profile receipt');
    }
  }
}

class ProfileFixtureShell extends StatefulWidget {
  const ProfileFixtureShell({super.key, this.english = false});
  final bool english;
  @override
  State<ProfileFixtureShell> createState() => _ProfileFixtureShellState();
}

class _ProfileFixtureShellState extends State<ProfileFixtureShell> {
  final _repository = ProfileFixture();
  late bool _english = widget.english;
  bool _signedOut = false;
  @override
  Widget build(BuildContext context) => Localizations.override(
    context: context,
    locale: Locale(_english ? 'en' : 'zh'),
    child: _signedOut
        ? Scaffold(
            appBar: AppBar(title: Text(_english ? 'Signed out' : '已退出当前会话')),
            body: Center(
              child: Text(
                _english ? 'Isolated fixture session cleared.' : '独立原型会话已清除。',
              ),
            ),
          )
        : ProfilePage(
            repository: _repository,
            server: Uri.parse('https://books.example'),
            english: _english,
            onLanguage: (english) async {
              setState(() => _english = english);
            },
            onLogout: () async {
              setState(() => _signedOut = true);
            },
          ),
  );
}
