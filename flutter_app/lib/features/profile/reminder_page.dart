import '../../core/app_theme.dart';
import 'package:flutter/material.dart';
import '../../core/reminder_repository.dart';
import '../../core/reminder_controller.dart';

class ReminderPage extends StatefulWidget {
  const ReminderPage({
    super.key,
    required this.repository,
    required this.settings,
    required this.onEditEmail,
    this.english = false,
  });
  final ReminderRepository repository;
  final ReminderSettings settings;
  final Future<void> Function() onEditEmail;
  final bool english;
  @override
  State<ReminderPage> createState() => _ReminderPageState();
}

class _ReminderPageState extends State<ReminderPage> {
  late final _controller = ReminderController(
    widget.repository,
    widget.settings,
  );
  late bool _enabled = widget.settings.preferences.enabled,
      _overdue = widget.settings.preferences.overdue;
  late int _days = widget.settings.preferences.days;
  late final _time = TextEditingController(
    text: widget.settings.preferences.sendTime,
  );
  final _form = GlobalKey<FormState>();
  bool _leaving = false;
  String t(String zh, String en) => widget.english ? en : zh;
  ReminderDraft get _draft => ReminderDraft(
    enabled: _enabled,
    sendTime: _time.text,
    days: _days,
    overdue: _overdue,
  );
  bool get _dirty => !_draft.same(_controller.baseline.preferences);
  @override
  void initState() {
    super.initState();
    _controller.addListener(_changed);
    _time.addListener(_changed);
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
    _time.removeListener(_changed);
    _time.dispose();
    super.dispose();
  }

  void _use(ReminderSettings settings) {
    setState(() {
      _enabled = settings.preferences.enabled;
      _overdue = settings.preferences.overdue;
      _days = settings.preferences.days;
      _time.text = settings.preferences.sendTime;
    });
  }

  Future<bool> _confirm(String title, String body, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => Dialog(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 16),
                Text(body),
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
      ) ??
      false;
  Future<void> _save() async {
    if (!_form.currentState!.validate()) {
      return;
    }
    FocusScope.of(context).unfocus();
    await _controller.save(_draft);
  }

  Future<void> _test() async {
    final email = _controller.baseline.email;
    if (email.isEmpty || _controller.busy) {
      return;
    }
    final ok = await _confirm(
      t('发送一封测试邮件？', 'Send one test email?'),
      t(
        '将向当前账户邮箱 $email 发送一封测试邮件。每10分钟最多3封，结果未知时不会自动重试。',
        'One test email will be sent to this account: $email. Maximum3 per10 minutes. Unknown results are not retried automatically.',
      ),
      t('确认发送一封', 'Send one email'),
    );
    if (ok && mounted) {
      await _controller.sendTest(email);
    }
  }

  Future<void> _email() async {
    if (_controller.busy || _controller.unresolved) {
      return;
    }
    if (_dirty &&
        !await _confirm(
          t('放弃未保存设置？', 'Discard unsaved preferences?'),
          t(
            '返回后将重新读取提醒设置。',
            'Reminder settings will be read again after returning.',
          ),
          t('继续修改邮箱', 'Edit email'),
        )) {
      return;
    }
    try {
      await widget.onEditEmail();
      final fresh = await widget.repository.read();
      if (mounted) {
        _controller.baseline = fresh;
        _controller.phase = ReminderPhase.ready;
        _controller.mailPhase = ReminderMailPhase.ready;
        _controller.submitted = null;
        _controller.observed = null;
        _controller.receivedReceipt = false;
        _use(fresh);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              t(
                '无法重新读取提醒设置，请返回重试。',
                'Cannot reload reminder settings. Return and try again.',
              ),
            ),
          ),
        );
      }
    }
  }

  Future<void> _leave() async {
    if (_leaving || _controller.busy) {
      return;
    }
    if ((_dirty || _controller.unresolved) &&
        !await _confirm(
          t('离开邮件提醒？', 'Leave email reminders?'),
          t(
            '未保存输入将丢弃；服务器可能已接受尚未确认的修改。',
            'Unsaved input is discarded. The server may have accepted an unconfirmed change.',
          ),
          t('离开', 'Leave'),
        )) {
      return;
    }
    if (mounted) {
      setState(() => _leaving = true);
      Navigator.pop(context);
    }
  }

  Widget _card(List<Widget> children) => Card(
    semanticContainer: false,
    margin: const EdgeInsets.only(bottom: 16),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    ),
  );
  String _status() => switch (_controller.phase) {
    ReminderPhase.checking => t('正在核对当前设置…', 'Checking current preferences…'),
    ReminderPhase.saving => t('正在保存…', 'Saving…'),
    ReminderPhase.failed => t(
      '未能保存，请核对服务状态、邮箱和连接。',
      'Could not save. Check service availability, email and connection.',
    ),
    ReminderPhase.unknown => t(
      '保存结果未知，不会自动重发。',
      'The save result is unknown. It will not be resent.',
    ),
    ReminderPhase.unverified => t(
      '已收到保存回执，尚未完成读取核对。',
      'The save was acknowledged. Readback verification is incomplete.',
    ),
    ReminderPhase.conflict => t(
      '服务器设置或邮箱已变化，请先读取采用。',
      'The server preferences or email changed. Review and use them first.',
    ),
    ReminderPhase.confirmed =>
      _dirty
          ? t(
              '上次提交已核对，当前输入尚未保存。',
              'The earlier submission was verified. Current input is unsaved.',
            )
          : t('实际提醒设置已核对。', 'Actual reminder preferences verified.'),
    _ => t(
      '保存后会重新读取实际设置核对。',
      'Actual preferences are read again after saving.',
    ),
  };
  String _mailStatus() => switch (_controller.mailPhase) {
    ReminderMailPhase.sending => t('正在提交测试邮件…', 'Submitting the test email…'),
    ReminderMailPhase.acknowledged => t(
      '服务器已确认发送请求，请自行检查邮箱。',
      'The server acknowledged sending. Check your mailbox.',
    ),
    ReminderMailPhase.rejected => t(
      '未能发送，请核对当前邮箱、会话与邮件服务。',
      'Could not send. Check the current email, session and mail service.',
    ),
    ReminderMailPhase.limited => t(
      '发送过于频繁，请稍后再试。',
      'Sending too frequently. Try later.',
    ),
    ReminderMailPhase.unknown => t(
      '发送结果未知，邮件可能已经发出。不会自动重试。',
      'The send result is unknown. The email may have been sent. There is no automatic retry.',
    ),
    _ => t(
      '测试发送有频率限制，请勿重复点击。',
      'Test sending is rate limited. Avoid repeated requests.',
    ),
  };
  @override
  Widget build(BuildContext context) {
    final c = _controller, b = c.baseline;
    final editable = !c.busy && !c.unresolved;
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
          title: Text(t('邮件提醒', 'Email reminders')),
          actions: [
            TextButton(
              onPressed: editable && c.phase != ReminderPhase.conflict
                  ? _save
                  : null,
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
                    const Icon(
                      Icons.mail_outline,
                      color: Color(0xff0b4eff),
                      size: 40,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      t('待办邮件提醒', 'Task email reminders'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      b.available
                          ? t('提醒服务可用', 'Reminder service available')
                          : t('定时提醒服务不可用', 'Scheduled reminders unavailable'),
                    ),
                    const SizedBox(height: 16),
                    SelectableText(
                      '${t('接收邮箱', 'Recipient')}: ${b.email.isEmpty ? t('未设置', 'Not set') : b.email}',
                    ),
                    TextButton(
                      onPressed: editable ? _email : null,
                      child: Text(t('修改邮箱', 'Edit email')),
                    ),
                    if (b.processedDate.isNotEmpty)
                      Text(
                        '${t('最后处理日期', 'Last processed date')}: ${b.processedDate}',
                      ),
                  ]),
                  _card([
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(t('启用待办提醒', 'Enable task reminders')),
                      value: _enabled,
                      onChanged: editable && (_enabled || b.available)
                          ? (v) => setState(() => _enabled = v)
                          : null,
                    ),
                    const Divider(),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _time,
                      enabled: editable,
                      keyboardType: TextInputType.datetime,
                      decoration: InputDecoration(
                        labelText: t('提醒时间 HH:MM', 'Reminder time HH:MM'),
                        prefixIcon: const Icon(Icons.schedule),
                      ),
                      validator: (v) =>
                          RegExp(
                            r'^(?:[01]\d|2[0-3]):[0-5]\d$',
                          ).hasMatch(v ?? '')
                          ? null
                          : t('请输入00:00—23:59', 'Enter00:00–23:59'),
                    ),
                    const SizedBox(height: 8),
                    Text(t('按服务器时间发送。', 'Sent according to server time.')),
                    const SizedBox(height: 24),
                    Text(t('提前提醒天数（0—30）', 'Days in advance (0–30)')),
                    Wrap(
                      spacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        IconButton(
                          tooltip: t('减少提前天数', 'Decrease advance days'),
                          onPressed: editable && _days > 0
                              ? () => setState(() => _days--)
                              : null,
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                        Text('$_days ${t('天', 'days')}'),
                        IconButton(
                          tooltip: t('增加提前天数', 'Increase advance days'),
                          onPressed: editable && _days < 30
                              ? () => setState(() => _days++)
                              : null,
                          icon: const Icon(Icons.add_circle_outline),
                        ),
                      ],
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(t('包含逾期待办', 'Include overdue tasks')),
                      value: _overdue,
                      onChanged: editable
                          ? (v) => setState(() => _overdue = v)
                          : null,
                    ),
                  ]),
                  _card([
                    Text(_status()),
                    if (c.unresolved)
                      TextButton(
                        onPressed: c.busy ? null : c.inspect,
                        child: Text(t('只读核对保存结果', 'Verify without writing')),
                      ),
                    if (c.phase == ReminderPhase.conflict) ...[
                      const SizedBox(height: 12),
                      Text(
                        '${c.observed!.email} · ${c.observed!.preferences.sendTime} · ${c.observed!.preferences.days} ${t('天', 'days')} · ${c.observed!.preferences.enabled} · ${c.observed!.preferences.overdue}',
                      ),
                      TextButton(
                        onPressed: () => _use(c.useObserved()),
                        child: Text(t('采用服务器设置', 'Use server preferences')),
                      ),
                    ],
                  ]),
                  FilledButton(
                    onPressed: editable && c.phase != ReminderPhase.conflict
                        ? _save
                        : null,
                    child: Text(t('保存提醒设置', 'Save reminder preferences')),
                  ),
                  const SizedBox(height: 24),
                  _card([
                    Text(
                      t('测试邮件', 'Test email'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      t(
                        '明确发送一封测试邮件到当前账户邮箱。',
                        'Explicitly send one test email to this account mailbox.',
                      ),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: !c.busy && b.email.isNotEmpty ? _test : null,
                      child: Text(t('发送测试邮件', 'Send test email')),
                    ),
                    const SizedBox(height: 12),
                    Text(_mailStatus()),
                  ]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
