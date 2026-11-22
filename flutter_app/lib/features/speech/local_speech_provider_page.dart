import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/speech_repository.dart';
import '../../core/speech_runtime.dart';
import '../../core/scoped_speech_repository.dart';
import '../../core/speech_text.dart';

/// Only real reader/engine captures may construct this. Never derive a range
/// by searching complex JSON; bindingId retains the full caller binding.
class LocalSpeechSelection {
  LocalSpeechSelection.captured({
    required this.text,
    required this.bindingId,
    required this.selectionKind,
    required this.isCurrentBinding,
    required this.verifyFreshBinding,
  }) {
    if (text.trim().isEmpty ||
        bindingId.isEmpty ||
        !{
          'text',
          'cells',
          'elements',
          'nodes',
          'slide',
        }.contains(selectionKind)) {
      throw const FormatException('Invalid speech selection capture');
    }
  }
  final String text, bindingId, selectionKind;
  final bool Function() isCurrentBinding;
  final Future<bool> Function() verifyFreshBinding;
  bool get current => isCurrentBinding();
}

/// One explicit text grant; never serializes/imports Root cookies.
class LocalSpeechGrant {
  LocalSpeechGrant._(
    this.client,
    this.memberId,
    this.account,
    this.owner,
    this._authorizedText,
    this.selection,
  ) {
    owner.retired.then((_) => close());
  }
  final String _authorizedText;
  final LocalSpeechSelection? selection;
  final BookstarkClient client;
  final int memberId;
  final String account;
  final SpeechOwner owner;
  SpeechRuntime? _runtime;
  bool _closed = false;
  Future<void>? _closeFuture;
  String get authorizedText => _authorizedText;
  Future<SpeechRuntime> start(
    String text, {
    required String title,
    required String context,
  }) async {
    owner.check();
    if (selection != null &&
        (!selection!.current || !await selection!.verifyFreshBinding())) {
      throw StateError('Speech selection changed');
    }
    owner.check();
    if (text != _authorizedText) {
      throw StateError('Reading text differs from authorized input');
    }
    if (_closed || _runtime != null) {
      throw StateError('This reading grant cannot be reused');
    }
    final runtime = await SpeechRuntime.create(
      RemoteSpeechRepository(client),
      owner: owner,
      retireOwnerOnStop: true,
    );
    if (!owner.current) {
      await runtime.close();
      throw StateError('Reading owner retired');
    }
    _runtime = runtime;
    await runtime.controller.prepare(
      text,
      title: title,
      context: context,
      autoPlay: true,
    );
    return runtime;
  }

  Future<void> close() => _closeFuture ??= _finishClose();
  Future<void> _finishClose() async {
    if (_closed) return;
    _closed = true;
    owner.retire();
    try {
      await _runtime?.close();
    } finally {
      client.close();
    }
  }
}

class LocalSpeechProviderPage extends StatefulWidget {
  const LocalSpeechProviderPage({
    super.key,
    required this.text,
    required this.title,
    required this.isCurrentScope,
    this.english = false,
    this.clientFactory,
    this.selection,
  });
  final String text, title;
  final bool Function() isCurrentScope;
  final bool english;
  final BookstarkClient Function(String server)? clientFactory;
  final LocalSpeechSelection? selection;
  @override
  State<LocalSpeechProviderPage> createState() => _ProviderState();
}

class _ProviderState extends State<LocalSpeechProviderPage> {
  final server = TextEditingController(),
      account = TextEditingController(),
      password = TextEditingController();
  BookstarkClient? client;
  int? member;
  String? verifiedAccount, error;
  bool busy = false, consent = false, handed = false;
  int generation = 0;
  String range = 'full';
  @override
  void initState() {
    super.initState();
    if (widget.text.trim().isEmpty && widget.selection != null) {
      range = 'selection';
    }
  }

  bool get hasFull => widget.text.trim().isNotEmpty;
  bool get hasSelection =>
      widget.selection != null && widget.selection!.current;
  String get selectedText =>
      range == 'selection' ? (widget.selection?.text ?? '') : widget.text;
  String t(String zh, String en) => widget.english ? en : zh;
  bool get current => mounted && widget.isCurrentScope();
  Future<void> authenticate() async {
    if (busy || !current) return;
    final epoch = ++generation;
    setState(() {
      busy = true;
      error = null;
      consent = false;
    });
    client?.close();
    client = null;
    member = null;
    BookstarkClient? fresh;
    try {
      speechSegments(selectedText);
      fresh =
          widget.clientFactory?.call(server.text.trim()) ??
          BookstarkClient(server.text.trim());
      if (fresh.baseUri.scheme != 'https') {
        throw StateError('HTTPS speech server required');
      }
      final loginAccount = account.text.trim();
      await fresh.login(loginAccount, password.text);
      password.clear();
      if (!current || epoch != generation) {
        throw StateError('Reading owner changed');
      }
      final profile = await fresh.profileSettingsJson();
      final id = profile['member_id'];
      if (id is! int || id <= 0) {
        throw StateError('Unable to verify speech account');
      }
      await RemoteSpeechRepository(fresh).voices();
      if (!current || epoch != generation) {
        throw StateError('Reading owner changed');
      }
      setState(() {
        client = fresh;
        member = id;
        verifiedAccount = loginAccount;
      });
      fresh = null;
    } catch (_) {
      if (current && epoch == generation) {
        setState(
          () => error = t(
            '无法验证语音服务，请检查账号和服务器',
            'Unable to verify speech service',
          ),
        );
      }
    } finally {
      fresh?.close();
      password.clear();
      if (mounted && epoch == generation) setState(() => busy = false);
    }
  }

  Future<void> begin() async {
    final selected = client, id = member, chosen = selectedText;
    final capture = range == 'selection' ? widget.selection : null;
    if (!current ||
        busy ||
        !consent ||
        selected == null ||
        id == null ||
        chosen.trim().isEmpty) {
      return;
    }
    setState(() => busy = true);
    try {
      speechSegments(chosen);
      if (capture != null &&
          (!capture.current || !await capture.verifyFreshBinding())) {
        throw StateError('Speech selection changed');
      }
      if (!current ||
          !identical(client, selected) ||
          !consent ||
          selectedText != chosen) {
        return;
      }
      if (!mounted) return;
      final owner = SpeechOwner(
        isCurrent: () => widget.isCurrentScope() && (capture?.current ?? true),
      );
      final grant = LocalSpeechGrant._(
        selected,
        id,
        verifiedAccount!,
        owner,
        chosen,
        capture,
      );
      handed = true;
      client = null;
      Navigator.pop(context, grant);
    } catch (_) {
      if (current) {
        setState(() {
          consent = false;
          error = t(
            '选中内容已变化，请返回重新选择',
            'Selection changed; return and select again',
          );
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    ++generation;
    if (!handed) client?.close();
    server.dispose();
    account.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(t('本地内容朗读', 'Read local content'))),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
          Text(
            t(
              '本次内容：${selectedText.runes.length} 字（按段发送）',
              'Current text: ${selectedText.runes.length} characters (sent in passages)',
            ),
          ),
          ListTile(
            enabled: !busy && hasFull,
            selected: range == 'full',
            leading: Icon(
              range == 'full'
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
            ),
            title: Text(t('全文（按段发送）', 'Complete text (sent in passages)')),
            subtitle: hasFull
                ? null
                : Text(t('未提供可读全文', 'Readable complete text unavailable')),
            onTap: busy || !hasFull
                ? null
                : () => setState(() {
                    range = 'full';
                    consent = false;
                  }),
          ),
          ListTile(
            enabled: !busy && hasSelection,
            selected: range == 'selection',
            leading: Icon(
              range == 'selection'
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
            ),
            title: Text(
              widget.selection?.selectionKind == 'slide'
                  ? t('当前页内容', 'Current slide content')
                  : t('当前选中内容', 'Current selection'),
            ),
            subtitle: hasSelection
                ? null
                : Text(t('未选择内容', 'No captured selection')),
            onTap: busy || !hasSelection
                ? null
                : () => setState(() {
                    range = 'selection';
                    consent = false;
                  }),
          ),
          const SizedBox(height: 16),
          Text(
            t(
              '本地文字将发送至您本次明确登录的服务器进行语音合成。不会使用应用其他账号的登录状态。',
              'Local text will be sent to the server you explicitly sign in to for this reading. Other app sessions are never reused.',
            ),
          ),
          const SizedBox(height: 16),
          if (member == null) ...[
            TextField(
              controller: server,
              enabled: !busy,
              decoration: InputDecoration(
                labelText: t('语音服务器 HTTPS 地址', 'Speech server HTTPS URL'),
              ),
              keyboardType: TextInputType.url,
            ),
            TextField(
              controller: account,
              enabled: !busy,
              decoration: InputDecoration(
                labelText: t('服务账号', 'Service account'),
              ),
            ),
            TextField(
              controller: password,
              enabled: !busy,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: t('密码（不保存）', 'Password (not saved)'),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: busy ? null : authenticate,
              child: Text(t('登录并验证语音服务', 'Sign in and verify speech')),
            ),
          ] else ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '${client!.baseUri}\n$verifiedAccount · member $member',
                ),
              ),
            ),
            CheckboxListTile(
              value: consent,
              onChanged: busy
                  ? null
                  : (value) => setState(() => consent = value ?? false),
              title: Text(
                t(
                  '我同意将本次所选范围按段发送至此账号的语音服务',
                  'I agree to send this text in passages to this speech account for this reading',
                ),
              ),
            ),
            FilledButton(
              onPressed: consent && !busy ? begin : null,
              child: Text(t('确认并开始', 'Confirm and start')),
            ),
          ],
          if (busy) const LinearProgressIndicator(),
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(context),
            child: Text(t('取消', 'Cancel')),
          ),
        ],
      ),
    ),
  );
}
