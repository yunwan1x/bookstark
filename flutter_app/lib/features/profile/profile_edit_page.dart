import '../../core/app_theme.dart';
import 'package:flutter/material.dart';
import '../../core/profile_repository.dart';
import '../../core/profile_edit_controller.dart';

class ProfileEditPage extends StatefulWidget {
  const ProfileEditPage({
    super.key,
    required this.repository,
    required this.profile,
    this.english = false,
  });
  final ProfileRepository repository;
  final MemberProfile profile;
  final bool english;
  @override
  State<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends State<ProfileEditPage> {
  late final _email = TextEditingController(text: widget.profile.email);
  late String _home = widget.profile.defaultHome;
  late final _controller = ProfileEditController(
    widget.repository,
    widget.profile,
  );
  final _form = GlobalKey<FormState>();
  bool _leaving = false;
  String t(String zh, String en) => widget.english ? en : zh;
  ProfileDraft get _draft =>
      ProfileDraft(email: _email.text, defaultHome: _home);
  bool get _dirty => !_draft.matches(_controller.baseline);
  static const _icons = {
    'home': Icons.home_outlined,
    'notes': Icons.note_outlined,
    'tasks': Icons.check_box_outlined,
    'articles': Icons.article_outlined,
    'books': Icons.menu_book_outlined,
    'bookmarks': Icons.bookmark_border,
    'nav': Icons.explore_outlined,
    'search': Icons.search,
  };
  String _module(String value) => switch (value) {
    'home' => t('首页', 'Home'),
    'notes' => t('笔记', 'Notes'),
    'tasks' => t('待办', 'Tasks'),
    'articles' => t('文章', 'Articles'),
    'books' => t('书籍', 'Books'),
    'bookmarks' => t('书签', 'Bookmarks'),
    'nav' => t('导航', 'Navigation'),
    'search' => t('搜索', 'Search'),
    _ => value,
  };
  @override
  void initState() {
    super.initState();
    _controller.addListener(_changed);
  }

  void _changed() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_changed);
    _controller.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<bool> _ask(String title, String message, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 16),
                  Text(message),
                  const SizedBox(height: 24),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: Text(t('取消', 'Cancel')),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: Text(action),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ) ??
      false;
  Future<void> _leave() async {
    if (_leaving) {
      return;
    }
    if (_controller.busy) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            t('正在核对或提交，请稍候。', 'Checking or submitting. Please wait.'),
          ),
        ),
      );
      return;
    }
    if ((_dirty ||
            _controller.unresolved ||
            _controller.phase == ProfileEditPhase.conflict) &&
        !await _ask(
          t('离开资料编辑？', 'Leave profile editing?'),
          _controller.unresolved
              ? t(
                  '上次提交可能已生效。离开会清除本次输入，不撤销服务器修改。',
                  'The previous update may have applied. Leaving clears these inputs and does not undo server changes.',
                )
              : t('离开会放弃本次尚未保存的输入。', 'Leaving discards these unsaved inputs.'),
          t('离开', 'Leave'),
        )) {
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() => _leaving = true);
    Navigator.pop(context, _controller.baseline);
  }

  Future<void> _save({MemberProfile? observed}) async {
    final c = _controller;
    if (c.busy || c.unresolved || !_form.currentState!.validate()) {
      return;
    }
    final draft = _draft;
    FocusScope.of(context).unfocus();
    try {
      await c.save(draft, overwriteObserved: observed);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              t(
                '请核对邮箱和默认模块后重试。',
                'Check your email and default module before retrying.',
              ),
            ),
          ),
        );
      }
    }
  }

  Future<void> _overwrite() async {
    final observed = _controller.observed;
    if (observed == null) {
      return;
    }
    if (!await _ask(
      t('明确覆盖服务器资料？', 'Explicitly replace the server profile?'),
      t(
        '请先核对下面的服务器邮箱和默认模块。上次请求若结果未知，可能已经生效；本次是一次新的明确保存，提交前会再次读取。',
        'Review the observed server email and default module first. An earlier unconfirmed request may have applied. This is a new explicit save and will recheck before submitting.',
      ),
      t('再次核对并保存', 'Recheck and save'),
    )) {
      return;
    }
    await _save(observed: observed);
  }

  Future<void> _useRemote() async {
    if (!await _ask(
      t('采用服务器资料？', 'Use the observed server profile?'),
      t(
        '将替换当前表单中的邮箱和默认模块，不向服务器写入。',
        'This replaces the form email and default module without writing to the server.',
      ),
      t('采用服务器资料', 'Use server profile'),
    )) {
      return;
    }
    if (!mounted) {
      return;
    }
    final actual = _controller.useObserved();
    _email.text = actual.email;
    setState(() => _home = actual.defaultHome);
  }

  String _status() {
    final c = _controller;
    if (c.busy) {
      return t('正在核对或提交…', 'Checking or submitting…');
    }
    if (c.phase == ProfileEditPhase.unknown) {
      return t(
        '提交结果未知，请先读取核对。',
        'The update result is unknown. Read to verify first.',
      );
    }
    if (c.phase == ProfileEditPhase.unverified) {
      return t(
        '已收到更新回执，仍需读取核对。',
        'An update receipt was received. Read verification is still needed.',
      );
    }
    if (c.phase == ProfileEditPhase.conflict) {
      return t(
        '服务器资料已变化，请先核对。',
        'The server profile changed. Review it first.',
      );
    }
    if (c.phase == ProfileEditPhase.failed) {
      return t(
        '操作未完成，请检查连接和权限。',
        'The operation failed. Check connection and permission.',
      );
    }
    if (_dirty) {
      return t('有未保存修改', 'Unsaved changes');
    }
    if (c.phase == ProfileEditPhase.confirmed) {
      return c.receivedWriteReceipt
          ? t('资料保存已核对', 'Profile save verified')
          : t('服务器资料已一致', 'Server profile matches');
    }
    return t('资料未修改', 'No profile changes');
  }

  Widget _card(List<Widget> children) => Card(
    semanticContainer: false,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    margin: const EdgeInsets.only(bottom: 16),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    ),
  );
  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
    ),
  );
  void _selectModule(String value) {
    FocusScope.of(context).unfocus();
    setState(() => _home = value);
  }

  Widget _moduleChoice(String value) => Semantics(
    button: true,
    selected: _home == value,
    label: _module(value),
    excludeSemantics: true,
    onTap: () => _selectModule(value),
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _selectModule(value),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _home == value ? const Color(0xffe3edff) : Colors.white,
          border: Border.all(
            color: _home == value
                ? const Color(0xff0b4eff)
                : const Color(0xffccd4df),
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              _icons[value],
              color: _home == value ? const Color(0xff0b4eff) : null,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(_module(value))),
            Icon(
              _home == value
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off,
              color: _home == value ? const Color(0xff0b4eff) : null,
            ),
          ],
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final c = _controller,
        observed = c.observed,
        canSave =
            !c.busy && !c.unresolved && c.phase != ProfileEditPhase.conflict;
    return PopScope(
      canPop: _leaving,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _leave();
        }
      },
      child: Scaffold(
        backgroundColor: accountCanvas(context, const Color(0xfff5f8fc)),
        appBar: AppBar(
          leading: IconButton(
            tooltip: t('返回', 'Back'),
            onPressed: _leave,
            icon: const Icon(Icons.arrow_back),
          ),
          title: Text(t('编辑资料', 'Edit profile')),
          actions: [
            TextButton(
              onPressed: canSave ? () => _save() : null,
              child: Text(t('保存', 'Save')),
            ),
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _card([
                    _heading(t('账号', 'Account')),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xffedf1f7),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.lock_outline),
                          const SizedBox(width: 12),
                          Expanded(child: SelectableText(c.baseline.account)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(t('账号不可修改。', 'The account cannot be changed.')),
                  ]),
                  _card([
                    _heading(t('联系邮箱', 'Contact email')),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(labelText: t('邮箱', 'Email')),
                      validator: (_) {
                        try {
                          _draft.validate();
                          return null;
                        } catch (_) {
                          return t(
                            '请输入有效邮箱，最多200 UTF8字节',
                            'Enter a valid email, up to200 UTF8 bytes',
                          );
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    Text(
                      t(
                        '用于找回密码和接收提醒。',
                        'Used for account recovery and reminders.',
                      ),
                    ),
                  ]),
                  _card([
                    _heading(t('默认打开模块', 'Default opening module')),
                    _moduleChoice(_home),
                    const SizedBox(height: 12),
                    LayoutBuilder(
                      builder: (context, size) {
                        final width =
                            size.maxWidth < 280 ||
                                MediaQuery.textScalerOf(context).scale(16) > 24
                            ? size.maxWidth
                            : (size.maxWidth - 12) / 2;
                        return Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            for (final value in profileHomeModules)
                              if (value != _home)
                                SizedBox(
                                  width: width,
                                  child: _moduleChoice(value),
                                ),
                          ],
                        );
                      },
                    ),
                  ]),
                  Container(
                    padding: const EdgeInsets.all(16),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xffe3edff),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      t(
                        '保存后会重新读取服务器资料核对。',
                        'Saving is followed by a fresh server profile read.',
                      ),
                    ),
                  ),
                  _card([
                    Text(_status()),
                    if (c.phase == ProfileEditPhase.confirmed && _dirty)
                      Text(
                        t(
                          '上次提交已核对，当前输入尚未保存。',
                          'The previous submission was verified. Current inputs are unsaved.',
                        ),
                      ),
                    if (c.unresolved)
                      TextButton(
                        onPressed: c.inspect,
                        child: Text(
                          t(
                            '只读核对提交结果',
                            'Verify the submission without writing',
                          ),
                        ),
                      ),
                  ]),
                  if (c.phase == ProfileEditPhase.conflict && observed != null)
                    _card([
                      _heading(t('服务器当前资料', 'Observed server profile')),
                      SelectableText('${t('邮箱', 'Email')}: ${observed.email}'),
                      Text(
                        '${t('默认打开', 'Default module')}: ${_module(observed.defaultHome)}',
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          OutlinedButton(
                            onPressed: _useRemote,
                            child: Text(t('采用服务器资料', 'Use server profile')),
                          ),
                          OutlinedButton(
                            onPressed: _overwrite,
                            child: Text(
                              t('保留本次并再次核对', 'Keep mine and recheck'),
                            ),
                          ),
                        ],
                      ),
                    ]),
                  FilledButton(
                    onPressed: canSave ? () => _save() : null,
                    child: Text(t('保存资料', 'Save profile')),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    t(
                      '返回前会提示尚未保存的修改。',
                      'Unsaved changes are reviewed before leaving.',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
