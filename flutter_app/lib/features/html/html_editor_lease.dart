import 'package:flutter/material.dart';

/// A vault queue orders storage operations but cannot arbitrate two editors.
/// Hold ownership until route disposal, including the exit transition.
class HtmlEditorLease {
  HtmlEditorLease(this.key, this.ownerContext);
  final BuildContext ownerContext;
  final String key;
  static final _active = <String, HtmlEditorLease>{};
  static HtmlEditorLease? acquire(BuildContext context, String key) {
    // Disposing an entire Navigator need not complete dialog push futures.
    // An unmounted owner can no longer edit or checkpoint its record.
    _active.removeWhere((_, lease) => !lease.ownerContext.mounted);
    if (_active.containsKey(key)) return null;
    return _active[key] = HtmlEditorLease(key, context);
  }

  void release() {
    if (identical(_active[key], this)) _active.remove(key);
  }
}
