import 'package:flutter/material.dart';
import '../../core/anonymous_shared_capability.dart';
import '../../core/local_complex_editor_controller.dart';
import '../../core/protected_shared_journal.dart';
import '../../core/protected_shared_lifetime.dart';
import 'protected_shared_review_page.dart';
import 'protected_shared_routes.dart';

class ProtectedSharedRecordActions extends StatefulWidget {
  const ProtectedSharedRecordActions({
    super.key,
    required this.owner,
    required this.journal,
    this.controller,
    required this.readFresh,
    this.english = false,
  });
  final ProtectedSharedLifetime owner;
  final ProtectedSharedJournal journal;
  final LocalComplexEditorController? controller;
  final Future<SharedCapabilitySource> Function() readFresh;
  final bool english;
  @override
  State<ProtectedSharedRecordActions> createState() => _ActionsState();
}

class _ActionsState extends State<ProtectedSharedRecordActions> {
  bool _busy = false, _invalid = false;
  String? _error;
  late final ProtectedSharedLifetime _owner;
  late final ProtectedSharedJournal _journal;
  late final LocalComplexEditorController? _controller;
  late final Future<SharedCapabilitySource> Function() _readFresh;
  String t(String zh, String en) => widget.english ? en : zh;
  bool get current => mounted && !_invalid && _owner.current;
  @override
  void initState() {
    super.initState();
    _owner = widget.owner;
    _journal = widget.journal;
    _controller = widget.controller;
    _readFresh = widget.readFresh;
    _controller?.addListener(_changed);
  }

  void _changed() {
    if (current) setState(() {});
  }

  @override
  void didUpdateWidget(covariant ProtectedSharedRecordActions old) {
    super.didUpdateWidget(old);
    if (!identical(widget.owner, _owner) ||
        !identical(widget.journal, _journal) ||
        !identical(widget.controller, _controller)) {
      _invalid = true;
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_changed);
    super.dispose();
  }

  Future<void> _run(Future<void> Function() work) async {
    if (!current || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await work();
    } catch (_) {
      if (current) {
        setState(
          () => _error = t(
            '核对或本机记录存储未确认；正文仍仅在本次内存，不会自动重发。',
            'Review or local record storage is unconfirmed. Body remains in this session memory; nothing is automatically resent.',
          ),
        );
      }
    } finally {
      if (current) setState(() => _busy = false);
    }
  }

  Future<void> _review() => _run(() async {
    final source = await _readFresh(), records = await _journal.loadGroup();
    if (!mounted || !current || records.isEmpty) return;
    await pushProtectedSharedRoute<bool>(
      context,
      _owner,
      MaterialPageRoute<bool>(
        builder: (_) => ProtectedSharedReviewPage(
          owner: _owner,
          journal: _journal,
          initial: source,
          records: records,
          readFresh: _readFresh,
          server: _owner.transport.link.reference.server,
          english: widget.english,
          sessionBodyAvailable: true,
        ),
      ),
    );
  });
  @override
  Widget build(BuildContext context) {
    if (!current || !_journal.hasAttempt) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_error != null) Text(_error!),
          if (_busy) const LinearProgressIndicator(),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: _busy ? null : _review,
                child: Text(t('核对提交记录', 'Review submission record')),
              ),
              if (_journal.hasKnown)
                OutlinedButton(
                  onPressed: _busy ? null : () => _run(_journal.persistKnown),
                  child: Text(t('仅重试回执存储', 'Retry receipt storage only')),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
