import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/app_theme.dart';
import '../../core/strings.dart';
import 'auth_feedback.dart';

class ConnectionPage extends StatefulWidget {
  const ConnectionPage({
    super.key,
    required this.strings,
    required this.onLanguage,
    required this.onLogin,
    required this.onLocal,
    required this.onRegister,
    required this.onForgot,
  });
  final AppStrings strings;
  final VoidCallback onLanguage, onLocal, onRegister, onForgot;
  final Future<void> Function(String server, String account, String password)
  onLogin;
  @override
  State<ConnectionPage> createState() => _ConnectionPageState();
}

class _ConnectionPageState extends State<ConnectionPage> {
  final _form = GlobalKey<FormState>();
  final _server = TextEditingController();
  final _account = TextEditingController();
  final _password = TextEditingController();
  bool _local = false, _visible = false, _busy = false;
  AuthFeedback? _feedback;
  String t(String key) => widget.strings.text(key);

  @override
  void dispose() {
    _server.dispose();
    _account.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_local) {
      widget.onLocal();
      return;
    }
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _feedback = null;
    });
    try {
      await widget.onLogin(
        _server.text.trim(),
        _account.text.trim(),
        _password.text,
      );
    } catch (error) {
      if (mounted) {
        setState(() {
          _feedback = authFailureFeedback(
            error,
            AuthOperation.login,
            widget.strings,
          );
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(
    String key,
    TextEditingController controller, {
    bool password = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t(key),
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        TextFormField(
          key: Key(key),
          controller: controller,
          enabled: !_busy,
          obscureText: password && !_visible,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: key == 'server'
              ? TextInputType.url
              : TextInputType.text,
          autofillHints: key == 'account'
              ? const [AutofillHints.username]
              : password
              ? const [AutofillHints.password]
              : null,
          textInputAction: password
              ? TextInputAction.done
              : TextInputAction.next,
          onFieldSubmitted: password ? (_) => _submit() : null,
          decoration: InputDecoration(
            prefixIcon: Icon(
              key == 'server'
                  ? Icons.link_outlined
                  : password
                  ? Icons.lock_outline
                  : Icons.person_outline,
            ),
            hintText: key == 'server'
                ? 'https://your-bookstark.example'
                : t(password ? 'enterPassword' : 'enterAccount'),
            suffixIcon: password
                ? IconButton(
                    tooltip: t(_visible ? 'hidePassword' : 'showPassword'),
                    onPressed: _busy
                        ? null
                        : () => setState(() => _visible = !_visible),
                    icon: Icon(
                      _visible
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                  )
                : null,
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) return t('required');
            if (key == 'server') {
              try {
                BookstarkClient.normalizeServer(value);
              } on FormatException {
                return t('invalidServer');
              }
            }
            return null;
          },
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: AutofillGroup(
            child: Form(
              key: _form,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final stacked =
                          constraints.maxWidth < 300 ||
                          MediaQuery.textScalerOf(context).scale(16) > 20;
                      final language = Align(
                        alignment: Alignment.topRight,
                        child: TextButton(
                          onPressed: widget.onLanguage,
                          child: Text(
                            widget.strings.english ? 'EN / 中文' : '中文 / EN',
                          ),
                        ),
                      );
                      final identity = Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Column(
                          children: [
                            const Icon(
                              Icons.menu_book_outlined,
                              color: AppColors.primary,
                              size: 52,
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'BookStark',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              t('authWelcomeTitle'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 28,
                                height: 1.2,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (_feedback == null) ...[
                              const SizedBox(height: 8),
                              Text(
                                t('welcomeHint'),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: AppColors.secondary,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                      return stacked
                          ? Column(children: [language, identity])
                          : Stack(children: [identity, language]);
                    },
                  ),
                  const SizedBox(height: 24),
                  SegmentedButton<bool>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                        value: false,
                        label: Text(t('serverSpace')),
                      ),
                      ButtonSegment(value: true, label: Text(t('localSpace'))),
                    ],
                    selected: {_local},
                    style: ButtonStyle(
                      backgroundColor: WidgetStateProperty.resolveWith(
                        (states) => states.contains(WidgetState.selected)
                            ? AppColors.primary
                            : AppColors.surface,
                      ),
                      foregroundColor: WidgetStateProperty.resolveWith(
                        (states) => states.contains(WidgetState.selected)
                            ? Colors.white
                            : AppColors.secondary,
                      ),
                      shape: WidgetStatePropertyAll(
                        RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      minimumSize: const WidgetStatePropertyAll(Size(0, 48)),
                    ),
                    onSelectionChanged: _busy
                        ? null
                        : (selection) => setState(() {
                            _local = selection.single;
                            _feedback = null;
                          }),
                  ),
                  const SizedBox(height: 28),
                  if (_local) ...[
                    const SizedBox(height: 24),
                    const Icon(
                      Icons.offline_bolt_outlined,
                      size: 56,
                      color: AppColors.primary,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      t('localDescription'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.secondary,
                        height: 1.7,
                      ),
                    ),
                    const SizedBox(height: 40),
                  ] else ...[
                    _field('server', _server),
                    _field('account', _account),
                    _field('password', _password, password: true),
                  ],
                  if (_feedback case final feedback?)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: AuthFeedbackCard(
                        key: const Key('login-error'),
                        feedback: feedback,
                      ),
                    ),
                  const SizedBox(height: 12),
                  FilledButton(
                    key: const Key('login'),
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(t('connecting')),
                            ],
                          )
                        : Text(t(_local ? 'openLocal' : 'connect')),
                  ),
                  if (!_local)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: OverflowBar(
                        alignment: MainAxisAlignment.spaceBetween,
                        overflowAlignment: OverflowBarAlignment.center,
                        spacing: 16,
                        overflowSpacing: 4,
                        children: [
                          TextButton(
                            onPressed: _busy ? null : widget.onForgot,
                            child: Text(t('authForgotLink')),
                          ),
                          TextButton(
                            onPressed: _busy ? null : widget.onRegister,
                            child: Text(t('authRegisterBarTitle')),
                          ),
                        ],
                      ),
                    ),
                  if (_feedback == null || _local) ...[
                    const SizedBox(height: 40),
                    Text(
                      t('localHint'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.secondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
