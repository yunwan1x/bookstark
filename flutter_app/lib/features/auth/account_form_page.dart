import 'dart:convert';
import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/app_theme.dart';
import '../../core/strings.dart';
import 'auth_feedback.dart';

enum AccountForm { register, forgot, reset }

class AccountFormPage extends StatefulWidget {
  const AccountFormPage({
    super.key,
    required this.form,
    required this.strings,
    required this.clientFactory,
    this.server = '',
    required this.onBack,
    required this.onReset,
  });
  final AccountForm form;
  final AppStrings strings;
  final String server;
  final BookstarkClient Function(String) clientFactory;
  final VoidCallback onBack, onReset;
  @override
  State<AccountFormPage> createState() => _AccountFormPageState();
}

class _AccountFormPageState extends State<AccountFormPage> {
  final _form = GlobalKey<FormState>();
  final _fields = <String, TextEditingController>{};
  bool _busy = false,
      _visible = false,
      _confirmVisible = false,
      _invite = false,
      _needsInvite = false;
  bool _completed = false, _verificationFirst = false;
  AuthFeedback? _feedback;
  String t(String key) => widget.strings.text(key);
  bool get _register => widget.form == AccountForm.register;
  bool get _forgot => widget.form == AccountForm.forgot;
  AuthOperation get _operation => _register
      ? AuthOperation.register
      : _forgot
      ? AuthOperation.forgot
      : AuthOperation.reset;
  TextEditingController controller(String key) => _fields.putIfAbsent(
    key,
    () => TextEditingController(text: key == 'server' ? widget.server : ''),
  );
  String value(String key) => controller(key).text.trim();
  String get _action => _register
      ? 'createAccount'
      : _forgot
      ? 'sendReset'
      : 'savePassword';

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _resetToken() {
    final input = value('token');
    if (!input.contains('://')) return input;
    final url = Uri.parse(input),
        server = BookstarkClient.normalizeServer(value('server'));
    if (url.origin != server.origin ||
        url.path != '${server.path}/reset-password') {
      throw FormatException(t('wrongResetServer'));
    }
    final token = Uri.splitQueryString(url.fragment)['token'];
    if (token == null || token.isEmpty) {
      throw FormatException(t('invalidResetLink'));
    }
    return token;
  }

  String? _validate(String key, String? input) {
    final text = input?.trim() ?? '';
    if (text.isEmpty && (key != 'invite' || _needsInvite)) return t('required');
    if (key == 'server') {
      try {
        BookstarkClient.normalizeServer(text);
      } on FormatException {
        return t('invalidServer');
      }
    }
    if (key == 'email' &&
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(text)) {
      return t('invalidEmail');
    }
    if (key == 'password' && (input?.runes.length ?? 0) < 6) {
      return t('passwordShort');
    }
    if (key == 'password' && utf8.encode(input ?? '').length > 72) {
      return t('passwordLong');
    }
    if (key == 'confirm' && input != controller('password').text) {
      return t('passwordMismatch');
    }
    if (key == 'token') {
      try {
        _resetToken();
      } on FormatException catch (error) {
        return error.message;
      }
    }
    return null;
  }

  Future<void> _submit() async {
    if (_busy ||
        _completed ||
        _verificationFirst ||
        !_form.currentState!.validate()) {
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _feedback = null;
    });
    BookstarkClient? client;
    var mutationStarted = false;
    try {
      client = widget.clientFactory(value('server'));
      if (_register) {
        final config = await client.accountFormConfiguration();
        if (!mounted) return;
        if (config['invite_code_enabled'] == true && value('invite').isEmpty) {
          setState(() {
            _invite = true;
            _needsInvite = true;
            _feedback = AuthFeedback(
              kind: AuthFeedbackKind.warning,
              title: t('authRegistrationRejected'),
              message: t('inviteRequired'),
            );
          });
          return;
        }
      }
      final endpoint = _register
          ? '/api/register'
          : _forgot
          ? '/api/password/forgot'
          : '/api/password/reset';
      final body = _register
          ? <String, Object?>{
              'account': value('account'),
              'email': value('email'),
              'password': controller('password').text,
              'confirm_password': controller('confirm').text,
              'invite_code': value('invite'),
            }
          : _forgot
          ? <String, Object?>{'identity': value('identity')}
          : <String, Object?>{
              'token': _resetToken(),
              'new_password': controller('password').text,
              'confirm_password': controller('confirm').text,
            };
      final result = await client.submitAccountForm(
        endpoint,
        body,
        onSubmitted: () => mutationStarted = true,
      );
      if (mounted) {
        setState(() {
          _feedback = _register
              ? authRegistrationFeedback(result, widget.strings)
              : AuthFeedback(
                  kind: AuthFeedbackKind.success,
                  title: t(
                    _forgot
                        ? 'authMailRequestedTitle'
                        : 'authResetCompleteTitle',
                  ),
                  message: t(_forgot ? 'resetNotice' : 'resetSuccess'),
                );
          _completed = !_forgot;
          if (!_forgot) {
            controller('password').clear();
            controller('confirm').clear();
            if (!_register) controller('token').clear();
          }
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _feedback = authFailureFeedback(
            error,
            _operation,
            widget.strings,
            mutationStarted: mutationStarted,
          );
          _verificationFirst = _feedback!.verificationFirst;
        });
      }
    } finally {
      client?.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget field(String key, {bool password = false, String? label}) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t(label ?? key),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        TextFormField(
          key: Key(key),
          controller: controller(key),
          enabled: !_busy,
          readOnly: _completed || _verificationFirst,
          obscureText:
              password && !(key == 'confirm' ? _confirmVisible : _visible),
          autocorrect: false,
          enableSuggestions: false,
          minLines: key == 'token' ? 2 : 1,
          maxLines: key == 'token' ? 3 : 1,
          keyboardType: key == 'email'
              ? TextInputType.emailAddress
              : key == 'server'
              ? TextInputType.url
              : TextInputType.text,
          validator: (v) => _validate(key, v),
          decoration: InputDecoration(
            prefixIcon: Icon(switch (key) {
              'server' || 'token' => Icons.link_outlined,
              'email' => Icons.mail_outline,
              'password' || 'confirm' => Icons.lock_outline,
              _ => Icons.person_outline,
            }),
            hintText: switch (key) {
              'server' => 'https://your-bookstark.example',
              'password' => t('enterPassword'),
              'confirm' => t('authRepeatPassword'),
              'token' => t('authPasteResetLink'),
              _ => null,
            },
            suffixIcon: password
                ? IconButton(
                    tooltip: t(
                      key == 'confirm'
                          ? (_confirmVisible
                                ? 'hideConfirmPassword'
                                : 'showConfirmPassword')
                          : (_visible ? 'hidePassword' : 'showPassword'),
                    ),
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                            if (key == 'confirm') {
                              _confirmVisible = !_confirmVisible;
                            } else {
                              _visible = !_visible;
                            }
                          }),
                    icon: Icon(
                      (key == 'confirm' ? _confirmVisible : _visible)
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                  )
                : null,
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: BackButton(onPressed: widget.onBack),
      title: Text(
        t(
          _register
              ? 'authRegisterBarTitle'
              : _forgot
              ? 'authForgotBarTitle'
              : 'authResetBarTitle',
        ),
      ),
      backgroundColor: accountCanvas(context, AppColors.background),
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const SizedBox(height: 16),
              if (_forgot)
                const Padding(
                  padding: EdgeInsets.only(bottom: 20),
                  child: Icon(
                    Icons.key_outlined,
                    color: AppColors.primary,
                    size: 48,
                  ),
                ),
              Text(
                t(
                  _register
                      ? 'registerTitle'
                      : _forgot
                      ? 'forgotTitle'
                      : 'resetTitle',
                ),
                style: Theme.of(context).textTheme.headlineLarge,
                textAlign: _forgot ? TextAlign.center : TextAlign.start,
              ),
              if (!_completed && _feedback == null) ...[
                const SizedBox(height: 12),
                Text(
                  t(
                    _register
                        ? 'registerHint'
                        : _forgot
                        ? 'forgotHint'
                        : 'resetHint',
                  ),
                  textAlign: _forgot ? TextAlign.center : TextAlign.start,
                  style: const TextStyle(
                    color: AppColors.secondary,
                    height: 1.5,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              field('server'),
              if (_register) ...[field('account'), field('email')],
              if (_forgot) field('identity'),
              if (!_forgot) ...[
                if (!_register) field('token'),
                field(
                  'password',
                  password: true,
                  label: _register ? 'password' : 'newPassword',
                ),
                field('confirm', password: true),
              ],
              if (_register && !_completed && !_verificationFirst) ...[
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() => _invite = !_invite),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          t(_needsInvite ? 'invite' : 'inviteOptional'),
                        ),
                      ),
                      Icon(_invite ? Icons.expand_less : Icons.expand_more),
                    ],
                  ),
                ),
                if (_invite) field('invite'),
              ],
              if (_feedback case final feedback?)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: AuthFeedbackCard(
                    key: Key(
                      feedback.kind == AuthFeedbackKind.success
                          ? 'form-success'
                          : 'form-error',
                    ),
                    feedback: feedback,
                  ),
                ),
              FilledButton(
                key: const Key('submit'),
                onPressed: _busy
                    ? null
                    : (_completed || _verificationFirst)
                    ? widget.onBack
                    : _submit,
                child: Text(
                  t(
                    _busy
                        ? 'submitting'
                        : _verificationFirst
                        ? 'authVerifyLogin'
                        : _completed
                        ? 'backLogin'
                        : _forgot &&
                              _feedback != null &&
                              _feedback!.kind != AuthFeedbackKind.success
                        ? 'authRetrySending'
                        : _action,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              if (!_completed)
                Text(
                  t(
                    _register
                        ? 'registerNote'
                        : _forgot
                        ? 'resetNotice'
                        : 'resetOnce',
                  ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.secondary,
                    height: 1.5,
                  ),
                ),
              if (_forgot) ...[
                const SizedBox(height: 8),
                Text(
                  t('resetCheckMail'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.secondary),
                ),
                const SizedBox(height: 20),
                TextButton(
                  onPressed: widget.onReset,
                  child: Text(t('haveResetLink')),
                ),
              ],
              const SizedBox(height: 24),
              if (!_completed && !_verificationFirst)
                TextButton(
                  onPressed: widget.onBack,
                  child: Text(t('backLogin')),
                ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    ),
  );
}
