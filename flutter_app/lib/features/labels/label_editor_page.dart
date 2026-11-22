import '../../core/local_label_management_repository.dart';
import '../../core/label_creation_resolution.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/draft_vault.dart';
import '../../core/notes_repository.dart';
import '../../core/label_management_repository.dart';

class LabelEditorPage extends StatefulWidget {
  const LabelEditorPage({
    super.key,
    required this.repository,
    this.label,
    this.vault,
    this.english = false,
    this.local = false,
  });
  final LabelManagementRepository repository;
  final ManagedLabel? label;
  final DraftVault? vault;
  final bool english, local;
  @override
  State<LabelEditorPage> createState() => _LabelEditorPageState();
}

class _LabelEditorPageState extends State<LabelEditorPage>
    with WidgetsBindingObserver {
  late final _name = TextEditingController(text: widget.label?.name ?? '');
  ManagedLabel? _saved;
  LabelCreationOrigin? _creationOrigin;
  String _savedName = '';
  String? _error, _draftError;
  bool _ready = false, _busy = false, _allowLeave = false, _uncertain = false;
  Timer? _timer;
  int _ownerEpoch = 0;
  bool _owns(
    int epoch,
    LabelManagementRepository repository,
    DraftVault? vault,
  ) =>
      mounted &&
      epoch == _ownerEpoch &&
      identical(repository, widget.repository) &&
      identical(vault, widget.vault);
  bool _durableCreate(LabelManagementRepository repository) =>
      (repository is DurableLabelCreationHost &&
          (repository as DurableLabelCreationHost).durableLabelCreation) ||
      (repository is DurableLocalLabelCreationHost &&
          (repository as DurableLocalLabelCreationHost)
              .durableLocalLabelCreation);

  String t(String zh, String en) => widget.english ? en : zh;
  Future<LabelCreationResolution> _create(
    LabelManagementRepository repository,
    String name,
  ) =>
      repository is DurableLocalLabelCreationHost &&
          (repository as DurableLocalLabelCreationHost)
              .durableLocalLabelCreation
      ? (repository as DurableLocalLabelCreationHost).createLocalLabel(name)
      : (repository as DurableLabelCreationHost).createGlobalLabel(name);

  bool get _editable => _saved == null || widget.repository.canManage;
  bool get _dirty => _name.text != _savedName;
  @override
  void initState() {
    super.initState();
    _saved = widget.label;
    _savedName = _name.text;
    WidgetsBinding.instance.addObserver(this);
    _name.addListener(_changed);
    _restore();
  }

  @override
  void didUpdateWidget(covariant LabelEditorPage old) {
    super.didUpdateWidget(old);
    if (!identical(old.repository, widget.repository) ||
        !identical(old.vault, widget.vault) ||
        old.label?.id != widget.label?.id ||
        old.local != widget.local) {
      _ownerEpoch++;
      _timer?.cancel();
      _ready = false;
      _busy = false;
      _allowLeave = false;
      _uncertain = false;
      _error = null;
      _draftError = null;
      _creationOrigin = null;
      _saved = widget.label;
      _savedName = widget.label?.name ?? '';
      _name.removeListener(_changed);
      _name.text = _savedName;
      _name.addListener(_changed);
      _restore();
    }
  }

  @override
  void dispose() {
    _ownerEpoch++;
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _name.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _timer?.cancel();
      unawaited(_persist());
    }
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    if (_ready) {
      _timer?.cancel();
      _timer = Timer(
        const Duration(milliseconds: 400),
        () => unawaited(_persist()),
      );
    }
  }

  Future<void> _persist() async {
    if (!_ready || !_dirty || widget.vault == null || _uncertain) return;
    final epoch = _ownerEpoch,
        repository = widget.repository,
        vault = widget.vault;
    final id = _saved?.id, name = _name.text;
    try {
      await vault!.write(Note(id: id, title: name, content: ''));
      if (_owns(epoch, repository, vault)) setState(() => _draftError = null);
    } catch (error) {
      if (_owns(epoch, repository, vault)) {
        setState(() => _draftError = error.toString());
      }
    }
  }

  Future<void> _restore() async {
    final epoch = _ownerEpoch,
        repository = widget.repository,
        vault = widget.vault;
    final id = _saved?.id;
    try {
      final draft = await vault?.read(id);
      if (!mounted || !_owns(epoch, repository, vault)) return;
      if (draft != null && draft.title != _name.text) {
        final restore = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: Text(t('发现标签草稿', 'Label draft found')),
            content: Text(t('恢复上次未保存的名称？', 'Restore the unsaved name?')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(t('放弃草稿', 'Discard draft')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(t('恢复', 'Restore')),
              ),
            ],
          ),
        );
        if (!_owns(epoch, repository, vault)) return;
        if (restore == true) {
          _name.text = draft.title;
        } else {
          await vault!.remove(id);
          if (!_owns(epoch, repository, vault)) return;
        }
      }
      if (_owns(epoch, repository, vault)) setState(() => _ready = true);
    } catch (error) {
      if (_owns(epoch, repository, vault)) {
        setState(() => _draftError = error.toString());
      }
    }
  }

  Future<void> _clearBrokenDraft() async {
    final epoch = _ownerEpoch,
        repository = widget.repository,
        vault = widget.vault,
        id = _saved?.id;
    try {
      await vault?.remove(id);
      if (_owns(epoch, repository, vault)) {
        setState(() {
          _draftError = null;
          _ready = true;
        });
      }
    } catch (error) {
      if (_owns(epoch, repository, vault)) {
        setState(() => _draftError = error.toString());
      }
    }
  }

  Future<List<ManagedLabel>> _matching(String name) async {
    final epoch = _ownerEpoch,
        repository = widget.repository,
        vault = widget.vault;
    final matches = <ManagedLabel>[];
    for (var page = 1; page <= 500; page++) {
      final result = await repository.list(
        LabelManagementQuery(keyword: name, page: page),
      );
      if (!_owns(epoch, repository, vault)) {
        throw StateError('Label editor owner retired');
      }
      if (result.page != page || (result.hasMore && result.items.isEmpty)) {
        throw const FormatException('Invalid labels pagination');
      }
      matches.addAll(result.items.where((item) => item.name == name));
      if (!result.hasMore) return matches;
    }
    throw const FormatException('Exact-name lookup exceeds page budget');
  }

  Future<void> _verify() async {
    if (_busy || !_uncertain) return;
    final epoch = _ownerEpoch,
        repository = widget.repository,
        vault = widget.vault;
    final name = _name.text;
    setState(() => _busy = true);
    try {
      if (_durableCreate(repository)) {
        // Coordinator loads the retained slot. Unknown never POSTs; pending
        // submits only via its explicit recovery-page button.
        final resolution = await _create(repository, name);
        final actual = ManagedLabel.fromJson(resolution.wire);
        if (!_owns(epoch, repository, vault)) return;
        setState(() {
          _saved = actual;
          _savedName = actual.name;
          _creationOrigin = resolution.origin;
          _uncertain = false;
          _error = null;
        });
        await vault?.remove(null);
        return;
      }
      final rows = await _matching(name);
      if (!_owns(epoch, repository, vault)) return;
      if (rows.length == 1) {
        setState(() {
          _saved = rows.single;
          _savedName = rows.single.name;
          _uncertain = false;
          _error = null;
        });
        await vault?.remove(null);
      } else if (rows.isEmpty) {
        setState(() {
          _uncertain = false;
          _error = t(
            '尚未找到同名标签，可核对后重新保存',
            'No exact label found; review before saving again',
          );
        });
      } else {
        throw StateError(
          t('存在多个同名标签，请返回列表核对', 'Multiple exact labels found; check the list'),
        );
      }
    } catch (error) {
      if (_owns(epoch, repository, vault)) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (_owns(epoch, repository, vault)) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_busy || !_ready || _uncertain || !_editable) return;
    try {
      validateLabelName(_name.text);
    } catch (error) {
      setState(() => _error = error.toString());
      return;
    }
    final epoch = _ownerEpoch,
        repository = widget.repository,
        vault = widget.vault;
    final name = _name.text, oldId = _saved?.id;
    _timer?.cancel();
    setState(() {
      _busy = true;
      _error = null;
    });
    var dispatched = false;
    try {
      if (oldId == null &&
          !_durableCreate(repository) &&
          (await _matching(name)).isNotEmpty) {
        throw StateError(
          t('标签已存在，请返回列表查看', 'This label exists; return to the list'),
        );
      }
      if (!_owns(epoch, repository, vault)) return;
      dispatched = true;
      LabelCreationResolution? resolution;
      final ManagedLabel actual;
      if (oldId == null && _durableCreate(repository)) {
        resolution = await _create(repository, name);
        actual = ManagedLabel.fromJson(resolution.wire);
      } else {
        actual = await repository.save(name, id: oldId);
      }
      if (!_owns(epoch, repository, vault)) return;
      setState(() {
        _saved = actual;
        _savedName = actual.name;
        _creationOrigin = resolution?.origin;
      });
      try {
        await vault?.remove(oldId);
        if (_owns(epoch, repository, vault)) setState(() => _draftError = null);
      } catch (error) {
        if (_owns(epoch, repository, vault)) {
          setState(() => _draftError = error.toString());
        }
      }
      if (_owns(epoch, repository, vault) && _dirty) await _persist();
    } catch (error) {
      if (_owns(epoch, repository, vault)) {
        setState(() {
          _error = error.toString();
          if (oldId == null &&
              dispatched &&
              !(error is ApiFailure &&
                  error.status >= 400 &&
                  error.status < 500)) {
            _uncertain = true;
          }
        });
      }
    } finally {
      if (_owns(epoch, repository, vault)) setState(() => _busy = false);
    }
  }

  Future<void> _leave() async {
    if (_busy) return;
    final epoch = _ownerEpoch,
        repository = widget.repository,
        vault = widget.vault,
        id = _saved?.id;
    if (!_dirty && !_uncertain) {
      setState(() => _allowLeave = true);
      Navigator.pop(context, id);
      return;
    }
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        title: Text(t('离开标签编辑？', 'Leave label editor?')),
        content: Text(
          _uncertain
              ? (_durableCreate(repository)
                    ? t(
                        '创建尚未核对。记录会保留，请从标签列表的创建恢复入口重新核对；不要按同名推断成功。',
                        'Creation is unverified. Keep its record and use Creation recovery from Labels. Matching names are not proof.',
                      )
                    : t(
                        '保存结果尚未核对，请返回列表检查实际标签；不会自动确认创建成功。',
                        'The save is unverified. Inspect actual labels in the list; creation is not automatically confirmed.',
                      ))
              : t('名称尚未保存。', 'The name is unsaved.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t('继续编辑', 'Keep editing')),
          ),
          if (vault != null && !_uncertain && _ready)
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'keep'),
              child: Text(t('保留草稿', 'Keep draft')),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'discard'),
            child: Text(t('离开', 'Leave')),
          ),
        ],
      ),
    );
    if (choice == null || !_owns(epoch, repository, vault)) return;
    if (choice == 'keep') {
      await _persist();
      if (!_owns(epoch, repository, vault) || _draftError != null) return;
    } else {
      try {
        await vault?.remove(id);
      } catch (error) {
        if (_owns(epoch, repository, vault)) {
          setState(() => _draftError = error.toString());
        }
        return;
      }
    }
    if (mounted && _owns(epoch, repository, vault)) {
      setState(() => _allowLeave = true);
      Navigator.pop(context, _saved?.id);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _allowLeave,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) unawaited(_leave());
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text(
          _saved == null ? t('新建标签', 'New label') : t('编辑标签', 'Edit label'),
        ),
        actions: [
          TextButton(
            onPressed: _editable && _ready && !_busy && !_uncertain
                ? _save
                : null,
            child: Text(t('保存', 'Save')),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_creationOrigin != null)
              Text(
                _creationOrigin == LabelCreationOrigin.manualExisting
                    ? (widget.local
                          ? t(
                              '已采用既有本地标签；不证明本次创建来源。',
                              'Existing local label adopted. This is not creation proof.',
                            )
                          : t(
                              '已采用既有全局标签；这不证明本次创建请求成功。',
                              'Existing global label adopted. This is not proof that this creation request succeeded.',
                            ))
                    : _creationOrigin ==
                          LabelCreationOrigin.localTransactionAcknowledgement
                    ? t(
                        '已收到真实本地事务完成后的实际 ID。',
                        'The actual ID returned after the local transaction completed.',
                      )
                    : t(
                        '已收到本次创建的实际 ID 回执。',
                        'The actual ID acknowledgement for this creation was received.',
                      ),
              ),
            if (_error != null) ...[
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 12),
            ],
            if (_uncertain)
              FilledButton.tonal(
                onPressed: _busy ? null : _verify,
                child: Text(t('核对创建结果', 'Verify creation result')),
              ),
            if (_draftError != null) ...[
              Text(
                _draftError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              if (!_ready)
                TextButton(
                  onPressed: _busy ? null : _clearBrokenDraft,
                  child: Text(t('清除不可读草稿', 'Clear unreadable draft')),
                ),
            ],
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t('标签名称', 'Label name'),
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _name,
                      enabled: _editable && _ready && !_busy && !_uncertain,
                      decoration: InputDecoration(
                        helperText: t(
                          '最大100字节（UTF-8）',
                          'At most 100 UTF-8 bytes',
                        ),
                        counterText:
                            '${utf8.encode(_name.text).length} / 100 ${t('字节', 'bytes')}',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Card(
              color: const Color(0xfff1f5f9),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.local
                          ? t('当前本地空间', 'Current local space')
                          : t('共享标签', 'Shared label'),
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.local
                          ? t(
                              '名称修改会影响此空间内使用该标签的资源。',
                              'Renaming affects resources in this space.',
                            )
                          : t(
                              '修改名称会影响服务器内使用此标签的资源。',
                              'Renaming affects resources using this label across the server.',
                            ),
                    ),
                  ],
                ),
              ),
            ),
            if (_busy) const Center(child: CircularProgressIndicator()),
          ],
        ),
      ),
    ),
  );
}
