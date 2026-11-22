import 'dart:async';
import '../../core/complex_editor_document.dart';
import '../../core/owned_preview_controller.dart';
import 'protected_shared_routes.dart';
import 'package:flutter/material.dart';
import '../../core/anonymous_shared_capability.dart';
import '../../core/protected_shared_identity.dart';
import '../../core/protected_shared_journal.dart';
import '../../core/protected_shared_lifetime.dart';
import '../../core/protected_shared_marker_metadata.dart';
import '../complex_editors/complex_editor_browser.dart';

/// Current actual source only. The previous edited body was never persisted.
class ProtectedSharedReviewPage extends StatefulWidget {
  const ProtectedSharedReviewPage({
    super.key,
    required this.owner,
    required this.journal,
    required this.initial,
    required this.records,
    required this.readFresh,
    required this.server,
    this.english = false,
    this.sessionBodyAvailable = false,
  });
  final ProtectedSharedLifetime owner;
  final ProtectedSharedJournal journal;
  final SharedCapabilitySource initial;
  final List<ProtectedSharedMarkerMetadata> records;
  final Future<SharedCapabilitySource> Function() readFresh;
  final Uri server;
  final bool english, sessionBodyAvailable;
  @override
  State<ProtectedSharedReviewPage> createState() => _ReviewState();
}

class _ReviewState extends State<ProtectedSharedReviewPage> {
  OwnedPreviewController _preview = OwnedPreviewController();
  late final ProtectedSharedLifetime _previewOwner;
  @override
  void initState() {
    super.initState();
    _previewOwner = widget.owner;
    _previewOwner.registerPreview(_preview);
  }

  late SharedCapabilitySource _source = widget.initial;
  late List<ProtectedSharedMarkerMetadata> _records = widget.records;
  int _selected = 0, _epoch = 0;
  bool _busy = false, _invalid = false;
  String? _error;
  String t(String zh, String en) => widget.english ? en : zh;
  bool get current => mounted && !_invalid && widget.owner.current;
  Future<void> _refresh() async {
    if (_busy || !current) return;
    final epoch = ++_epoch;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _preview.retire();
      if (!mounted || !current || epoch != _epoch) return;
      _previewOwner.unregisterPreview(_preview);
      _preview.dispose();
      _preview = OwnedPreviewController();
      _previewOwner.registerPreview(_preview);
      final source = await widget.readFresh(),
          records = await widget.journal.loadGroup();
      if (!mounted || !current || epoch != _epoch) return;
      if (records.isEmpty) {
        Navigator.pop(context, true);
        return;
      }
      setState(() {
        _source = source;
        _records = records;
        _selected = 0;
      });
    } catch (_) {
      if (current) {
        setState(
          () => _error = t(
            '无法核对，原记录已保留。',
            'Unable to review. Original records are retained.',
          ),
        );
      }
    } finally {
      if (current && epoch == _epoch) setState(() => _busy = false);
    }
  }

  Future<void> _end() async {
    if (_busy || !current || _records.isEmpty) return;
    final record = _records[_selected], source = _source, epoch = _epoch;
    final changed = protectedSharedIdentity(source.identity) != record.identity;
    final confirmed = await pushProtectedSharedRoute<bool>(
      context,
      widget.owner,
      DialogRoute<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          scrollable: true,
          title: Text(t('结束核对记录？', 'End review record?')),
          content: Text(
            widget.sessionBodyAvailable
                ? t(
                    '仅结束提交元数据记录，不会撤销服务器操作，也不能证明上次操作未执行。不会保存或清除当前内存草稿，不会自动重发；继续编辑仍须核对当前版本。',
                    'Only submission metadata is ended. This does not undo the server operation or prove nonexecution. It neither saves nor clears the current memory draft and never resends it; continuing still requires review of the current version.',
                  )
                : changed
                ? t(
                    '当前分享身份已变化，无法核对旧提交。仅结束这条元数据记录，不会撤销服务器操作，也不能证明上次操作未执行。旧正文未保留，不会自动重发。',
                    'The share identity changed, so the old submission cannot be verified. Ending only this metadata record does not undo the server operation or prove nonexecution. The previous body was not retained and will not be resent.',
                  )
                : t(
                    '这不会撤销服务器操作，也不能证明上次操作未执行。将再次核对当前版本后仅清理元数据；上次草稿正文未保留。之后只能基于当前版本重新编辑。',
                    'This does not undo the server operation or prove nonexecution. The current version is checked again before metadata cleanup. The prior draft body was not retained; subsequent editing starts from the current version.',
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: Text(t('保留记录', 'Keep record')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: Text(t('确认结束', 'Confirm end')),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true ||
        !current ||
        epoch != _epoch ||
        _records.isEmpty ||
        !identical(_records[_selected], record) ||
        !identical(_source, source)) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.journal.endReviewed(
        record,
        reviewedFingerprint: source.fingerprint,
        allowUnverifiable: changed,
        fresh: () async => protectedSharedObservation(await widget.readFresh()),
      );
      if (!current) return;
      final records = await widget.journal.loadGroup();
      if (!mounted || !current) return;
      if (records.isEmpty) {
        Navigator.pop(context, true);
        return;
      }
      setState(() {
        _records = records;
        _selected = 0;
      });
    } catch (_) {
      if (current) {
        setState(
          () => _error = t(
            '清理未确认或版本已变化。记录保留；不会重新保存。',
            'Cleanup is unconfirmed or the version changed. The record is retained; no save is replayed.',
          ),
        );
      }
    } finally {
      if (current) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _epoch++;
    final preview = _preview, owner = _previewOwner;
    unawaited(
      preview.retire().then<void>(
        (_) {
          owner.unregisterPreview(preview);
          preview.dispose();
        },
        onError: (Object _, StackTrace _) {
          // Remain registered until Root can confirm native close on retry.
        },
      ),
    );
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ProtectedSharedReviewPage old) {
    super.didUpdateWidget(old);
    if (!identical(old.owner, widget.owner) ||
        !identical(old.journal, widget.journal)) {
      _invalid = true;
      _epoch++;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_invalid || !widget.owner.current) {
      return const Scaffold(body: SizedBox.shrink());
    }
    final record = _records[_selected],
        changed = protectedSharedIdentity(_source.identity) != record.identity;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          changed
              ? t('共享身份已变化', 'Shared identity changed')
              : t('受保护的共享编辑', 'Protected shared editing'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            t('原文仅保留在本次内存', 'Body remains only in this session memory'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          Text(
            t(
              '关闭后未保存正文无法恢复；恢复存储仅保留不含正文的提交核对记录。',
              'Unsaved body cannot be recovered after closing. Recovery storage retains only a submission review record without the body.',
            ),
          ),
          if (_records.length > 1)
            DropdownButton<int>(
              isExpanded: true,
              value: _selected,
              items: [
                for (var i = 0; i < _records.length; i++)
                  DropdownMenuItem(
                    value: i,
                    child: Text('${t('核对记录', 'Review record')} ${i + 1}'),
                  ),
              ],
              onChanged: _busy
                  ? null
                  : (value) {
                      if (value != null) setState(() => _selected = value);
                    },
            ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    record.phase == ProtectedSharedMarkerPhase.known
                        ? t(
                            '已有保存回执，仍需核对当前版本',
                            'Save receipt exists; review the current version',
                          )
                        : t('上次保存结果未知', 'Previous save result unknown'),
                  ),
                  Text(
                    widget.sessionBodyAvailable
                        ? t(
                            '本次草稿仍仅在前一编辑页的内存中，关闭后无法恢复。',
                            'This draft remains only in the previous editor session memory and cannot be recovered after closing.',
                          )
                        : t(
                            '上次编辑正文未保留。',
                            'The previous edited body was not retained.',
                          ),
                  ),
                  Text(
                    t('记录中的资源指纹：', 'Recorded resource fingerprint: ') +
                        record.identity.substring(0, 12),
                  ),
                  Text(
                    t('当前资源指纹：', 'Current resource fingerprint: ') +
                        protectedSharedIdentity(
                          _source.identity,
                        ).substring(0, 12),
                  ),
                  Text(
                    t('提交前正文摘要：', 'Expected source digest: ') +
                        record.expectedSource.substring(0, 12),
                  ),
                  Text(
                    t('本次提交正文摘要：', 'Submitted source digest: ') +
                        record.submittedSource.substring(0, 12),
                  ),
                  Text(
                    t('当前正文摘要：', 'Current source digest: ') +
                        _source.document.digest.substring(0, 12),
                  ),
                  if (record.modified != null)
                    Text(t('保存回执时间：', 'Receipt time: ') + record.modified!),
                  if (changed)
                    Text(
                      t(
                        '不能把新资源当作旧提交的证明，不会自动重发。',
                        'A new resource cannot prove the old submission. Nothing is automatically resent.',
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (_error != null) Text(_error!, semanticsLabel: _error),
          if (_busy) const LinearProgressIndicator(),
          Text(
            t('当前服务器版本', 'Current server version'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          SizedBox(
            height: 360,
            child: ComplexEditorBrowser(
              key: ValueKey((_source.fingerprint, _preview)),
              document: _source.document,
              title: _source.title,
              english: widget.english,
              readOnly: true,
              publicServer: widget.server,
              publicComplexReadOnly:
                  _source.document.kind != ComplexEditorKind.markdown,
              retirementController: _preview,
              onReloadRequested: _refresh,
            ),
          ),
          OutlinedButton.icon(
            onPressed: _busy ? null : _refresh,
            icon: const Icon(Icons.refresh),
            label: Text(t('重新核对服务器版本', 'Review server version again')),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: _busy ? null : () => Navigator.pop(context, false),
                child: Text(t('返回只读', 'Return to read-only')),
              ),
              FilledButton(
                onPressed: _busy ? null : _end,
                child: Text(t('结束核对记录', 'End review record')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
