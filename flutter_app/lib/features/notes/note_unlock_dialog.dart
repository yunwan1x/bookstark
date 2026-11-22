import 'package:flutter/material.dart';

class NoteUnlockDialog<T> extends StatefulWidget {
  const NoteUnlockDialog({
    super.key,
    required this.onUnlock,
    this.english = false,
  });
  final Future<T> Function(String password) onUnlock;
  final bool english;
  @override
  State<NoteUnlockDialog<T>> createState() => _NoteUnlockDialogState<T>();
}

class _NoteUnlockDialogState<T> extends State<NoteUnlockDialog<T>> {
  final _password = TextEditingController();
  bool _busy = false, _visible = false;
  String? _error;
  String t(String zh, String en) => widget.english ? en : zh;
  Future<void> _unlock() async {
    if (_busy) return;
    if (_password.text.isEmpty) {
      setState(() => _error = t('请输入密码', 'Enter the note password'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final note = await widget.onUnlock(_password.text);
      if (!mounted) return;
      setState(() => _busy = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context, note);
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error.toString();
        });
      }
    }
  }

  @override
  void dispose() {
    _password.clear();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      icon: Icon(
        Icons.lock_outline,
        color: Theme.of(context).colorScheme.primary,
        size: 40,
      ),
      title: Text(t('解锁笔记', 'Unlock note')),
      scrollable: true,
      content: SizedBox(
        width: 292,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t(
                '输入此笔记的密码，解锁后继续编辑',
                'Enter this note’s password to continue editing.',
              ),
            ),
            const SizedBox(height: 24),
            TextField(
              key: const Key('note-password'),
              controller: _password,
              obscureText: !_visible,
              enabled: !_busy,
              autofocus: true,
              onSubmitted: (_) => _unlock(),
              decoration: InputDecoration(
                labelText: t('笔记密码', 'Note password'),
                errorText: _error,
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _visible = !_visible),
                  tooltip: _visible
                      ? t('隐藏密码', 'Hide password')
                      : t('显示密码', 'Show password'),
                  icon: Icon(
                    _visible ? Icons.visibility_off : Icons.visibility,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              t(
                '解锁密码仅用于当前编辑，不会保存在草稿中',
                'The password is used only for this editor and is never stored in drafts.',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(t('取消', 'Cancel')),
        ),
        FilledButton(
          onPressed: _busy ? null : _unlock,
          child: Text(_busy ? t('解锁中…', 'Unlocking…') : t('解锁', 'Unlock')),
        ),
      ],
    ),
  );
}
