import 'package:flutter/material.dart';

class AdminFilePathDialog extends StatefulWidget {
  const AdminFilePathDialog({
    super.key,
    required this.title,
    required this.initial,
    this.english = false,
  });
  final String title, initial;
  final bool english;
  @override
  State<AdminFilePathDialog> createState() => _PathDialogState();
}

class _PathDialogState extends State<AdminFilePathDialog>
    with WidgetsBindingObserver {
  late final TextEditingController input = TextEditingController(
    text: widget.initial,
  );
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      input.clear();
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: input,
      autofocus: true,
      autocorrect: false,
      enableSuggestions: false,
      decoration: InputDecoration(
        labelText: widget.english ? 'Full path' : '完整路径',
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(widget.english ? 'Cancel' : '取消'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, input.text),
        child: Text(widget.english ? 'Next' : '下一步'),
      ),
    ],
  );
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    input.dispose();
    super.dispose();
  }
}

class AdminFilePermissionsDialog extends StatefulWidget {
  const AdminFilePermissionsDialog({
    super.key,
    required this.path,
    required this.mode,
    this.english = false,
  });
  final String path, mode;
  final bool english;
  @override
  State<AdminFilePermissionsDialog> createState() => _PermissionDialogState();
}

class _PermissionDialogState extends State<AdminFilePermissionsDialog>
    with WidgetsBindingObserver {
  late int mode = int.parse(widget.mode, radix: 8) & 0x1ff;
  late final TextEditingController input = TextEditingController(
    text: mode.toRadixString(8).padLeft(4, '0'),
  );
  bool valid = true;
  String t(String zh, String en) => widget.english ? en : zh;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      input.clear();
      if (mounted) setState(() => valid = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(t('权限', 'Permissions')),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.path),
          const SizedBox(height: 12),
          TextField(
            controller: input,
            maxLength: 4,
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
            decoration: InputDecoration(
              labelText: t('八进制权限', 'Octal permissions'),
              helperText: '0000–0777',
              errorText: valid
                  ? null
                  : t(
                      '请输入普通八进制权限（0000–0777）。',
                      'Enter ordinary octal permissions (0000–0777).',
                    ),
            ),
            onChanged: (text) => setState(() {
              valid = RegExp(r'^0?[0-7]{3}$').hasMatch(text);
              if (valid) mode = int.parse(text, radix: 8);
            }),
          ),
          for (var group = 0; group < 3; group++)
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 80,
                  child: Text(
                    [
                      t('所有者', 'Owner'),
                      t('用户组', 'Group'),
                      t('其他', 'Other'),
                    ][group],
                  ),
                ),
                for (var bit = 0; bit < 3; bit++)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Checkbox(
                        value: (mode & (1 << (8 - group * 3 - bit))) != 0,
                        onChanged: (value) => setState(() {
                          final mask = 1 << (8 - group * 3 - bit);
                          mode = value == true ? mode | mask : mode & ~mask;
                          valid = true;
                          input.text = mode.toRadixString(8).padLeft(4, '0');
                        }),
                      ),
                      Text(['r', 'w', 'x'][bit]),
                    ],
                  ),
              ],
            ),
          Text(
            t(
              '设置普通 rwx 权限将清除特殊位。现有 SFTP 清单不报告特殊位。',
              'Setting ordinary rwx permissions clears special bits. Existing SFTP listings do not report special bits.',
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(t('取消', 'Cancel')),
      ),
      FilledButton(
        onPressed: valid ? () => Navigator.pop(context, mode) : null,
        child: Text(t('下一步', 'Next')),
      ),
    ],
  );
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    input.dispose();
    super.dispose();
  }
}
