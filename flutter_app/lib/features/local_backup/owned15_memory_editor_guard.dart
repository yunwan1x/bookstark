import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/owned15_editor_lifetime.dart';

/// Uses the existing native editor layout. Inactive/background retires the real
/// plaintext owner, so merely returning cannot reveal a stale unlocked editor.
class Owned15MemoryEditorGuard extends StatefulWidget {
  const Owned15MemoryEditorGuard({
    super.key,
    required this.owner,
    required this.child,
    this.english = false,
  });
  final Owned15EditorLifetime owner;
  final Widget child;
  final bool english;
  @override
  State<Owned15MemoryEditorGuard> createState() =>
      _Owned15MemoryEditorGuardState();
}

class _Owned15MemoryEditorGuardState extends State<Owned15MemoryEditorGuard>
    with WidgetsBindingObserver {
  bool _locked = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _watch(widget.owner);
  }

  void _watch(Owned15EditorLifetime owner) {
    unawaited(
      owner.abortTrigger.then((_) {
        if (mounted && identical(widget.owner, owner)) {
          setState(() => _locked = true);
        }
      }),
    );
  }

  @override
  void didUpdateWidget(covariant Owned15MemoryEditorGuard old) {
    super.didUpdateWidget(old);
    if (!identical(old.owner, widget.owner)) {
      unawaited(old.owner.retire().catchError((Object _) {}));
      _locked = false;
      _watch(widget.owner);
    }
  }

  void _retire() {
    if (!_locked && mounted) setState(() => _locked = true);
    unawaited(widget.owner.retire().catchError((Object _) {}));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _retire();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(widget.owner.retire().catchError((Object _) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_locked && widget.owner.current) return widget.child;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              widget.english
                  ? 'This editor is locked. Reopen the resource to continue. Unsaved changes are no longer available; no disk draft was created.'
                  : '此编辑器已锁定，请重新打开资料。未保存的修改现已丢失，未生成磁盘草稿。',
            ),
          ),
        ),
      ),
    );
  }
}
