import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/task_action_drafts.dart';

/// One actual service owner per editor route. No SQL/mutation capability.
class TaskEditorOwnedActions {
  const TaskEditorOwnedActions({required this.bindings, required this.retire});
  final TaskEditorActionBindings bindings;
  final void Function() retire;
}

typedef TaskEditorActionsFactory =
    Future<TaskEditorOwnedActions> Function({
      required bool Function() isCurrent,
      required Future<void> abortTrigger,
    });
Widget ownedTaskEditorRoute({
  TaskEditorActionsFactory? factory,
  required Widget Function(TaskEditorActionBindings? actions) builder,
  bool english = false,
}) => factory == null
    ? builder(null)
    : _TaskEditorActionRoute(
        factory: factory,
        builder: builder,
        english: english,
      );

class _TaskEditorActionRoute extends StatefulWidget {
  const _TaskEditorActionRoute({
    required this.factory,
    required this.builder,
    required this.english,
  });
  final TaskEditorActionsFactory factory;
  final Widget Function(TaskEditorActionBindings?) builder;
  final bool english;
  @override
  State<_TaskEditorActionRoute> createState() => _TaskEditorActionRouteState();
}

class _TaskEditorActionRouteState extends State<_TaskEditorActionRoute> {
  final _stop = Completer<void>();
  TaskEditorOwnedActions? _owner;
  Widget? _editor;
  bool _retired = false, _failed = false;
  bool _current() => mounted && !_retired && !_stop.isCompleted;
  @override
  void initState() {
    super.initState();
    unawaited(_prepare());
  }

  Future<void> _prepare() async {
    try {
      final owner = await widget.factory(
        isCurrent: _current,
        abortTrigger: _stop.future,
      );
      if (!_current()) {
        owner.retire();
        return;
      }
      if (!owner.bindings.isCurrent()) {
        owner.retire();
        throw StateError('Task owner retired');
      }
      _owner = owner;
      final bindings = owner.bindings.guarded(_current);
      final editor = widget.builder(bindings);
      if (!_current()) {
        owner.retire();
        _owner = null;
        return;
      }
      setState(() => _editor = editor);
    } catch (_) {
      if (_current()) setState(() => _failed = true);
    }
  }

  void _retire() {
    _retired = true;
    if (!_stop.isCompleted) _stop.complete();
    final owner = _owner;
    _owner = null;
    owner?.retire();
  }

  @override
  void didUpdateWidget(covariant _TaskEditorActionRoute old) {
    super.didUpdateWidget(old);
    // Changing route owner requires a new keyed route; never adopt stale results.
    if (!identical(old.factory, widget.factory)) {
      _retire();
      _editor = null;
      _failed = true;
    }
  }

  @override
  void dispose() {
    _retire();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _editor ??
      Scaffold(
        appBar: AppBar(),
        body: Center(
          child: _failed
              ? Text(
                  widget.english
                      ? 'Unable to prepare this task. Go back and retry.'
                      : '无法准备当前任务操作，请返回后重试。',
                )
              : const CircularProgressIndicator(),
        ),
      );
}
