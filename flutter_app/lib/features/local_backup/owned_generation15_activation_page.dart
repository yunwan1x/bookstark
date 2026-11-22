import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/attachments.dart';
import '../../core/local_backup_importer.dart';
import 'local_legacy_candidate_review_page.dart';

class Owned15ActivationSummary {
  const Owned15ActivationSummary({
    required this.notes,
    required this.articles,
    required this.protectedItems,
    required this.attachments,
  });
  final int notes, articles, protectedItems, attachments;
}

/// Dedicated explicit activation, never a promotion of a read-only review.
/// The caller owns the fresh-source staging job and its Root retirement scope.
class OwnedGeneration15ActivationPage extends StatefulWidget {
  const OwnedGeneration15ActivationPage({
    super.key,
    required this.summary,
    required this.prepareCandidate,
    required this.activate,
    required this.onReview,
    required this.onCancel,
    required this.isCurrentScope,
    this.english = false,
  });
  final Owned15ActivationSummary summary;
  final Future<LocalBackupCandidate> Function(AttachmentCancellation)
  prepareCandidate;
  final Future<void> Function(LocalBackupCandidate) activate;
  final Future<void> Function() onReview, onCancel;
  final bool Function() isCurrentScope;
  final bool english;
  @override
  State<OwnedGeneration15ActivationPage> createState() =>
      _Owned15ActivationState();
}

class _Owned15ActivationState extends State<OwnedGeneration15ActivationPage> {
  final _request = AttachmentCancellation();
  late final Future<void> _preparation;
  LocalBackupCandidate? _candidate;
  Future<void>? _closing;
  bool _retentionConfirmed = false,
      _submitted = false,
      _running = false,
      _prepareFailed = false,
      _switched = false,
      _cleanupFailed = false,
      _reviewFailed = false;
  bool get current => mounted && widget.isCurrentScope();
  String t(String zh, String en) => widget.english ? en : zh;
  @override
  void initState() {
    super.initState();
    _preparation = _prepare();
  }

  Future<void> _prepare() async {
    try {
      final candidate = await widget.prepareCandidate(_request);
      if (candidate.manifest.databaseSchema != 15 ||
          !current ||
          _request.cancelled) {
        await candidate.discardUnprepared();
        if (!_request.cancelled && current) {
          throw StateError('Expected independent owned candidate');
        }
        return;
      }
      _candidate = candidate;
      if (current) setState(() {});
    } catch (_) {
      if (current && !_request.cancelled) setState(() => _prepareFailed = true);
    }
  }

  Future<void> _cleanup() {
    final existing = _closing;
    if (existing != null) return existing;
    final work = () async {
      _request.cancel();
      await _preparation;
      if (!_submitted) {
        final candidate = _candidate;
        if (candidate != null) {
          await candidate.discardUnprepared();
          _candidate = null;
        }
      }
      await widget.onCancel();
    }();
    _closing = work;
    unawaited(
      work.catchError((Object _, StackTrace _) {
        if (identical(_closing, work)) _closing = null;
      }),
    );
    return work;
  }

  Future<void> _back() async {
    if (_running) return;
    if (_submitted) {
      await _review();
      return;
    }
    setState(() => _running = true);
    try {
      await _cleanup();
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) setState(() => _cleanupFailed = true);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _apply() async {
    final candidate = _candidate;
    if (!current ||
        _running ||
        _submitted ||
        !_retentionConfirmed ||
        candidate == null) {
      return;
    }
    setState(() {
      _submitted = true;
      _running = true;
    });
    try {
      if (!current) throw StateError('Activation owner changed');
      await widget.activate(candidate);
      if (current) setState(() => _switched = true);
    } catch (_) {
      if (current) setState(() => _switched = false);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _review() async {
    if (!current || _running) return;
    setState(() => _running = true);
    try {
      await widget.onReview();
    } catch (_) {
      if (current) setState(() => _reviewFailed = true);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  void dispose() {
    // Submission authority belongs to the caller's native coordinator. Never
    // discard its candidate/retention or replay it because this route closes.
    if (!_submitted) unawaited(_cleanup().catchError((Object _) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final summary = widget.summary;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_back());
      },
      child: CandidateReviewFrame(
        title: t('启用独立本地空间', 'Activate an independent local space'),
        onBack: _running ? null : () => unawaited(_back()),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  t(
                    '保留原有保护与加密状态，不自动转换原文。',
                    'Keep the original protection and encryption state without converting content.',
                  ),
                ),
                const SizedBox(height: 16),
                CandidateReviewCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t('已核对的资料', 'Verified source'),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 24,
                        runSpacing: 12,
                        children: [
                          for (final entry in [
                            (t('笔记', 'Notes'), summary.notes),
                            (t('文章', 'Articles'), summary.articles),
                            (t('受保护', 'Protected'), summary.protectedItems),
                            (t('附件', 'Attachments'), summary.attachments),
                          ])
                            Text('${entry.$1} · ${entry.$2}'),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (_cleanupFailed)
                  Text(
                    t(
                      '临时副本清理尚未确认，请重试返回。',
                      'Temporary-copy cleanup is unconfirmed. Retry Back.',
                    ),
                  ),
                if (_reviewFailed)
                  Text(
                    t(
                      '暂时无法核对结果，请重试核对。',
                      'Result review is unavailable. Retry the read-only review.',
                    ),
                  ),
                if (_prepareFailed)
                  Text(
                    t(
                      '独立副本尚未通过完整检查。请返回重新检查来源。',
                      'The independent copy did not pass complete checks. Return and inspect the source again.',
                    ),
                  ),
                if (!_submitted && !_prepareFailed && _candidate == null)
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      t('正在准备独立副本…', 'Preparing an independent copy…'),
                    ),
                  ),
                if (!_submitted && _candidate != null) ...[
                  Text(
                    t('启用前确认', 'Before activation'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _retentionConfirmed,
                    onChanged: _running
                        ? null
                        : (value) => setState(
                            () => _retentionConfirmed = value ?? false,
                          ),
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(
                      t(
                        '完整保留当前本地空间，便于之后恢复。',
                        'Keep a complete copy of the current local space for recovery.',
                      ),
                    ),
                  ),
                  Text(
                    t(
                      '本次输入的密码仅在内存中使用，不写入备份。',
                      'Passwords entered in this session stay in memory and are not added to backups.',
                    ),
                  ),
                ],
                if (_submitted)
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _running
                          ? t(
                              '正在启用，请勿再次提交。',
                              'Activating. Do not submit again.',
                            )
                          : _switched
                          ? t(
                              '已切换，请只读核对激活结果。',
                              'Switched. Review the activated result read-only.',
                            )
                          : t(
                              '激活结果尚未确认。请核对结果，不会自动再次启用。',
                              'The activation result is unconfirmed. Review it; activation will not be replayed.',
                            ),
                    ),
                  ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    if (!_submitted)
                      OutlinedButton(
                        onPressed: _running ? null : () => unawaited(_back()),
                        child: Text(t('返回', 'Back')),
                      ),
                    if (!_submitted)
                      FilledButton(
                        onPressed:
                            current &&
                                !_running &&
                                _candidate != null &&
                                _retentionConfirmed
                            ? () => unawaited(_apply())
                            : null,
                        child: Text(t('启用独立空间', 'Activate independent space')),
                      ),
                    if (_submitted)
                      FilledButton(
                        onPressed: _running ? null : () => unawaited(_review()),
                        child: Text(t('核对激活结果', 'Review activation result')),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
