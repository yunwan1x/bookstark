import 'dart:async';
import 'package:flutter/material.dart';

/// Retires an asynchronously prepared owner even if no child route ever mounts.
class OwnedRemoteEntryLoader extends StatefulWidget {
  const OwnedRemoteEntryLoader({
    super.key,
    required this.create,
    required this.retire,
  });
  final Future<Widget> Function(bool Function() routeCurrent) create;
  final void Function(Widget page) retire;
  @override
  State<OwnedRemoteEntryLoader> createState() => _LoaderState();
}

class _LoaderState extends State<OwnedRemoteEntryLoader> {
  bool alive = true;
  Widget? page;
  bool failed = false;
  @override
  void initState() {
    super.initState();
    unawaited(open());
  }

  Future<void> open() async {
    try {
      final prepared = await widget.create(() => mounted && alive);
      if (!mounted || !alive) {
        widget.retire(prepared);
        return;
      }
      setState(() => page = prepared);
    } catch (_) {
      if (mounted && alive) setState(() => failed = true);
    }
  }

  @override
  void dispose() {
    alive = false;
    final owned = page;
    if (owned != null) widget.retire(owned);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      page ??
      Scaffold(
        appBar: AppBar(),
        body: Center(
          child: failed
              ? const Text('Could not open this scope. Records retained.')
              : const CircularProgressIndicator(),
        ),
      );
}
