import 'dart:async';
import 'image_library_owner.dart';
export 'image_library_owner.dart';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/images_repository.dart';
import '../../widgets/native_image.dart';
import 'image_format.dart';
import 'image_preview_page.dart';
import 'image_upload_page.dart';

class ImagesPage extends StatefulWidget {
  const ImagesPage({
    super.key,
    required this.repository,
    this.owner,
    this.english = false,
  });
  final ImagesRepository repository;
  final ImageLibraryOwner? owner;
  final bool english;
  @override
  State<ImagesPage> createState() => _ImagesPageState();
}

class _ImagesPageState extends State<ImagesPage> {
  late ImageLibraryOwner _owner;
  final _search = TextEditingController();
  final _selected = <int>{};
  final _unknown = <int, ManagedImage>{};
  final _cleanup = <int, ManagedImage>{};
  List<ManagedImage> _items = [];
  ImageCategory? _category;
  String _keyword = '', _notice = '';
  String? _error;
  int _page = 0, _total = 0, _size = 0, _generation = 0;
  bool _listMode = false;
  bool _loading = false, _selecting = false, _batch = false, _stop = false;
  bool get _hasMore => _page * 20 < _total;
  String t(String zh, String en) => widget.english ? en : zh;
  @override
  void initState() {
    super.initState();
    _owner = widget.owner ?? ImageLibraryOwner();
    _load();
  }

  @override
  void didUpdateWidget(covariant ImagesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.repository, widget.repository) ||
        !identical(oldWidget.owner, widget.owner)) {
      unawaited(_owner.retireAndDrain());
      _owner = widget.owner ?? ImageLibraryOwner();
      _generation++;
      _stop = false;
      _batch = false;
      _loading = false;
      _selected.clear();
      _unknown.clear();
      _cleanup.clear();
      _items = [];
      _page = _total = _size = 0;
      _notice = '';
      _error = null;
      _search.clear();
      _keyword = '';
      _category = null;
      _load();
    }
  }

  Future<T> _repositoryWork<T>(
    ImageLibraryOwner owner,
    Future<T> Function() work,
  ) => owner.run(work);

  bool _owns(ImageLibraryOwner owner, ImagesRepository repository) =>
      mounted &&
      identical(_owner, owner) &&
      owner.isCurrent &&
      identical(widget.repository, repository);

  @override
  void dispose() {
    _generation++;
    _stop = true;
    unawaited(_owner.retireAndDrain());
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool more = false, bool retainPages = false}) async {
    final owner = _owner;
    final repository = widget.repository;
    if (!_owns(owner, repository)) return;

    if (more && (_loading || !_hasMore)) return;
    final generation = ++_generation;
    final keyword = _keyword, category = _category;
    final first = more ? _page + 1 : 1;
    final last = !more && retainPages && _page > 1 ? _page : first;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final collected = <ManagedImage>[];
      ImagesPageResult? result;
      for (var page = first; page <= last; page++) {
        if (!_owns(owner, repository)) return;
        final next = await _repositoryWork<ImagesPageResult>(
          owner,
          () => repository.list(
            ImagesQuery(keyword: keyword, category: category, page: page),
          ),
        );
        if (!_owns(owner, repository) || generation != _generation) return;
        result = next;
        collected.addAll(next.items);
        if (!next.hasMore) break;
      }
      if (!_owns(owner, repository)) return;
      final pendingCleanup = await _repositoryWork(
        owner,
        () => repository.pendingCleanup(),
      );
      if (!_owns(owner, repository) ||
          generation != _generation ||
          result == null) {
        return;
      }
      setState(() {
        final merged = <int, ManagedImage>{
          for (final item in more ? _items : <ManagedImage>[]) item.id: item,
          for (final item in collected) item.id: item,
        };
        _items = merged.values.toList();
        _total = result!.total;
        _size = result.totalImageBytes;
        _page = result.page;
        _cleanup
          ..clear()
          ..addEntries(
            pendingCleanup.map((image) => MapEntry(image.id, image)),
          );
        _selected.removeWhere((id) => !_items.any((item) => item.id == id));
      });
    } catch (error) {
      if (_owns(owner, repository) && generation == _generation) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (_owns(owner, repository) && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _filter(ImageCategory? category) async {
    final owner = _owner;
    final repository = widget.repository;
    if (!_owns(owner, repository)) return;

    if (_batch) return;
    if (_selected.isNotEmpty) {
      final yes = await _confirm(
        t('清空当前选择？', 'Clear selection?'),
        t('切换筛选会清空已选择的图片。', 'Changing filters clears selected images.'),
      );
      if (!yes || !_owns(owner, repository)) return;
    }
    setState(() {
      _category = category;
      _keyword = _search.text.trim();
      _items = [];
      _selected.clear();
      _page = 0;
      _total = 0;
      _notice = '';
    });
    await _load();
  }

  Future<bool> _confirm(String title, String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(t('取消', 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(t('确认', 'Confirm')),
            ),
          ],
        ),
      ) ??
      false;

  String _removalNotice(ImageRemovalResult result) => result.cleanupPending
      ? t(
          '记录已删除，本地文件仍待清理，可重试清理。',
          'Record removed; local file cleanup is pending. Retry cleanup.',
        )
      : result.linkAvailable == true
      ? t(
          '记录已删除，但文件链接仍可访问；已有缓存也可能保留。',
          'Record removed, but the file link remains available; cached copies may also remain.',
        )
      : result.linkAvailable == null
      ? t(
          '记录已删除，文件链接可用性尚未确认。',
          'Record removed; file link availability remains unconfirmed.',
        )
      : t(
          '记录已删除。引用此图的内容可能失效，已有缓存可能保留。',
          'Record removed. References may break; cached copies may remain.',
        );

  Future<void> _preview(ManagedImage image) async {
    final owner = _owner;
    final repository = widget.repository;
    if (!_owns(owner, repository)) return;

    if (_batch) return;
    if (_selecting) {
      setState(
        () => _selected.contains(image.id)
            ? _selected.remove(image.id)
            : _selected.add(image.id),
      );
      return;
    }
    final outcome = await Navigator.push<ImagePreviewOutcome>(
      context,
      MaterialPageRoute(
        builder: (_) => ImagePreviewPage(
          repository: repository,
          owner: owner,
          image: image,
          english: widget.english,
        ),
      ),
    );
    if (!_owns(owner, repository)) return;
    if (outcome?.needsVerification == true) _unknown[image.id] = image;
    final removal = outcome?.removal;
    if (removal != null) {
      if (removal.cleanupPending) _cleanup[image.id] = image;
      setState(() => _notice = _removalNotice(removal));
    }
    await _load(retainPages: true);
  }

  Future<void> _upload() async {
    final owner = _owner;
    final repository = widget.repository;
    if (!_owns(owner, repository)) return;

    final outcome = await Navigator.push<ImageUploadOutcome>(
      context,
      MaterialPageRoute(
        builder: (_) => ImageUploadPage(
          repository: repository,
          owner: owner,
          english: widget.english,
        ),
      ),
    );
    if (!_owns(owner, repository)) return;
    if (outcome?.needsVerification == true) {
      setState(
        () => _notice = t(
          '有上传结果尚未确认。请先查看列表或按文件哈希核对，避免重复上传。',
          'Some upload results remain unconfirmed. Check the list or file hash before uploading again.',
        ),
      );
    }
    await _load(retainPages: true);
  }

  Future<void> _deleteSelected() async {
    final owner = _owner;
    final repository = widget.repository;
    if (!_owns(owner, repository)) return;

    if (_batch || _selected.isEmpty || _selected.any(_unknown.containsKey)) {
      return;
    }
    final targets = _items
        .where((item) => _selected.contains(item.id))
        .toList();
    if (!await _confirm(
          t('删除所选图片？', 'Delete selected images?'),
          t(
            '将逐项删除 ${targets.length} 张图片。引用可能失效；失败项会保留，结果未知时先核对。',
            'Delete ${targets.length} images one at a time. References may break. Failed items stay selected; unknown results require verification.',
          ),
        ) ||
        !_owns(owner, repository)) {
      return;
    }
    setState(() {
      _batch = true;
      _stop = false;
      _error = null;
    });
    var removed = 0, failed = 0, retainedLinks = 0;
    final errors = <String>[];
    for (final item in targets) {
      if (_stop || !_owns(owner, repository)) break;
      try {
        final result = await _repositoryWork(
          owner,
          () => repository.remove(item),
        );
        if (!_owns(owner, repository)) return;
        if (result.recordRemoved) {
          removed++;
          _selected.remove(item.id);
          _unknown.remove(item.id);
          if (result.cleanupPending) _cleanup[item.id] = item;
          if (result.linkAvailable != false) retainedLinks++;
        } else {
          _unknown[item.id] = item;
          failed++;
        }
      } catch (error) {
        if (!_owns(owner, repository)) return;
        failed++;
        errors.add('${item.name}: $error');
        if (!(error is ApiFailure &&
            {400, 401, 403, 405}.contains(error.status))) {
          _unknown[item.id] = item;
        }
      }
      if (_owns(owner, repository)) {
        setState(
          () => _notice = t(
            '已删除 $removed，未完成 $failed',
            'Removed $removed; incomplete $failed',
          ),
        );
      }
    }
    if (!_owns(owner, repository)) return;
    setState(() {
      _batch = false;
      _notice = t(
        '已删除 $removed，未完成 $failed${_stop ? '，已停止后续项目' : ''}。${retainedLinks > 0 ? '部分文件链接仍可访问或尚未确认。' : ''}',
        'Removed $removed; incomplete $failed${_stop ? '; remaining items stopped' : ''}.${retainedLinks > 0 ? ' Some file links remain available or unconfirmed.' : ''}',
      );
      _error = errors.isEmpty ? null : errors.take(5).join('\n');
    });
    await _load(retainPages: true);
    // Preserve per-item failures after the list refresh (which clears read errors).
    if (_owns(owner, repository) && errors.isNotEmpty) {
      setState(() => _error = errors.take(5).join('\n'));
    }
  }

  Future<void> _verify() async {
    final owner = _owner;
    final repository = widget.repository;
    if (!_owns(owner, repository)) return;

    if (_batch) return;
    setState(() {
      _batch = true;
      _stop = false;
      _error = null;
    });
    final messages = <String>[];
    for (final image in _unknown.values.toList()) {
      if (_stop || !_owns(owner, repository)) break;
      try {
        final result = await _repositoryWork(
          owner,
          () => repository.verifyRemoval(image),
        );
        if (!_owns(owner, repository)) return;
        _unknown.remove(image.id);
        if (result.recordRemoved) {
          _selected.remove(image.id);
          if (result.cleanupPending) _cleanup[image.id] = image;
          messages.add('${image.name}: ${_removalNotice(result)}');
        } else {
          messages.add(
            '${image.name}: ${t('记录仍存在，可检查后重新删除。', 'Record still exists; review before deleting again.')}',
          );
        }
      } catch (error) {
        if (!_owns(owner, repository)) return;
        messages.add('${image.name}: $error');
      }
    }
    if (!_owns(owner, repository)) return;
    setState(() {
      _batch = false;
      _notice = messages.join('\n');
    });
    await _load(retainPages: true);
  }

  Future<void> _retryCleanup() async {
    final owner = _owner;
    final repository = widget.repository;
    if (!_owns(owner, repository)) return;

    if (_batch) return;
    setState(() {
      _batch = true;
      _stop = false;
    });
    final messages = <String>[];
    for (final image in _cleanup.values.toList()) {
      if (_stop || !_owns(owner, repository)) break;
      try {
        final result = await _repositoryWork(
          owner,
          () => repository.remove(image),
        );
        if (!_owns(owner, repository)) return;
        if (!result.cleanupPending) _cleanup.remove(image.id);
        messages.add('${image.name}: ${_removalNotice(result)}');
      } catch (error) {
        if (!_owns(owner, repository)) return;
        messages.add('${image.name}: $error');
      }
    }
    if (_owns(owner, repository)) {
      setState(() {
        _batch = false;
        _notice = messages.join('\n');
      });
    }
  }

  Widget _header() => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          color: const Color(0xffdbeafe),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline, color: Color(0xff2563eb)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.repository.publicLinks
                        ? t(
                            '图片链接公开，删除需权限。',
                            'Image links are public. Deletion requires permission.',
                          )
                        : t(
                            '本地图片，仅本空间可用。',
                            'Local images, available only in this space.',
                          ),
                    style: const TextStyle(color: Color(0xff2563eb)),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _search,
          enabled: !_batch,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _filter(_category),
          decoration: InputDecoration(
            labelText: t('搜索图片文件名', 'Search image file name'),
            prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(
              tooltip: t('搜索', 'Search'),
              onPressed: _batch ? null : () => _filter(_category),
              icon: const Icon(Icons.arrow_forward),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: Text(t('全部', 'All')),
              selected: _category == null,
              onSelected: _batch ? null : (_) => _filter(null),
            ),
            for (final category in ImageCategory.values)
              ChoiceChip(
                label: Text(
                  imageCategoryLabel(category.name, english: widget.english),
                ),
                selected: _category == category,
                onSelected: _batch ? null : (_) => _filter(category),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              t(
                '已加载 ${_items.length} / $_total 张',
                'Loaded ${_items.length} / $_total images',
              ),
            ),
            OutlinedButton(
              onPressed: _batch
                  ? null
                  : () => setState(() {
                      _selecting = !_selecting;
                      if (!_selecting) _selected.clear();
                    }),
              child: Text(
                _selecting ? t('结束选择', 'Done selecting') : t('选择', 'Select'),
              ),
            ),
          ],
        ),
        Text(
          t(
            '图片合计 ${imageSizeLabel(_size)}',
            'Total image files ${imageSizeLabel(_size)}',
          ),
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        if (_selecting)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              TextButton(
                onPressed: _batch
                    ? null
                    : () => setState(
                        () => _selected.addAll(_items.map((item) => item.id)),
                      ),
                child: Text(t('选择已加载', 'Select loaded')),
              ),
              TextButton(
                onPressed: _batch ? null : () => setState(_selected.clear),
                child: Text(t('清空选择', 'Clear selection')),
              ),
              FilledButton.icon(
                onPressed:
                    _batch ||
                        _selected.isEmpty ||
                        _selected.any(_unknown.containsKey)
                    ? null
                    : _deleteSelected,
                icon: const Icon(Icons.delete_outline),
                label: Text(
                  t(
                    '删除所选 ${_selected.length}',
                    'Delete selected ${_selected.length}',
                  ),
                ),
              ),
            ],
          ),
        if (_unknown.isNotEmpty)
          OutlinedButton(
            onPressed: _batch ? null : _verify,
            child: Text(
              t(
                '核对 ${_unknown.length} 项删除结果',
                'Verify ${_unknown.length} deletion results',
              ),
            ),
          ),
        if (_cleanup.isNotEmpty)
          OutlinedButton(
            onPressed: _batch ? null : _retryCleanup,
            child: Text(
              t(
                '重试 ${_cleanup.length} 项本地清理',
                'Retry ${_cleanup.length} local cleanups',
              ),
            ),
          ),
        if (_batch)
          TextButton(
            onPressed: _stop ? null : () => setState(() => _stop = true),
            child: Text(t('停止后续项目', 'Stop remaining items')),
          ),
        if (_notice.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_notice),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: LinearProgressIndicator(),
          ),
        if (_error != null && !_loading)
          TextButton(
            onPressed: _batch ? null : () => _load(retainPages: true),
            child: Text(t('重试读取', 'Retry loading')),
          ),
      ],
    ),
  );

  Widget _tile(ManagedImage image, bool list) => Card(
    key: ValueKey('managed-image-${image.id}'),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: _batch ? null : () => _preview(image),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: list ? 180 : 136,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ImageLibraryThumbnail(
                  owner: _owner,
                  repository: widget.repository,
                  image: image,
                  english: widget.english,
                ),
                if (_selecting)
                  Align(
                    alignment: Alignment.topRight,
                    child: Checkbox(
                      value: _selected.contains(image.id),
                      onChanged: _batch ? null : (_) => _preview(image),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  image.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${image.knownDimensions ? '${image.width}×${image.height}' : t('尺寸未知', 'Dimensions unknown')} · ${imageSizeLabel(image.size)}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _owner,
    builder: (_, _) => _owner.isCurrent
        ? _buildCurrent(context)
        : Scaffold(appBar: AppBar(), body: const SizedBox.shrink()),
  );
  Widget _buildCurrent(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(t('图片库', 'Images')),
      actions: [
        IconButton(
          tooltip: t('网格视图', 'Grid view'),
          isSelected: !_listMode,
          onPressed: _batch ? null : () => setState(() => _listMode = false),
          icon: const Icon(Icons.grid_view_outlined),
        ),
        IconButton(
          tooltip: t('列表视图', 'List view'),
          isSelected: _listMode,
          onPressed: _batch ? null : () => setState(() => _listMode = true),
          icon: const Icon(Icons.view_list_outlined),
        ),

        IconButton(
          tooltip: t('刷新', 'Refresh'),
          onPressed: _batch || _loading ? null : () => _load(retainPages: true),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _batch ? null : _upload,
      icon: const Icon(Icons.add_photo_alternate_outlined),
      label: Text(
        widget.repository.publicLinks
            ? t('上传图片', 'Upload images')
            : t('添加图片', 'Add images'),
      ),
    ),
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
          final columns = (constraints.maxWidth / (180 * scale.clamp(1, 2)))
              .floor()
              .clamp(1, 5);
          final list = _listMode || columns == 1 || scale > 1.5;
          return RefreshIndicator(
            onRefresh: () async {
              if (!_batch) await _load(retainPages: true);
            },
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(child: _header()),
                if (_items.isEmpty && !_loading)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _error != null
                            ? t(
                                '图片未能读取，请重试。',
                                'Images could not be loaded; retry.',
                              )
                            : t('当前筛选没有图片', 'No images match these filters'),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                if (list)
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    sliver: SliverList.builder(
                      itemCount: _items.length,
                      itemBuilder: (_, index) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _tile(_items[index], true),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    sliver: SliverGrid.builder(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                        mainAxisExtent: 136 + 120 * scale,
                      ),
                      itemCount: _items.length,
                      itemBuilder: (_, index) => _tile(_items[index], false),
                    ),
                  ),
                if (_hasMore)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: OutlinedButton(
                        onPressed: _loading || _batch
                            ? null
                            : () => _load(more: true),
                        child: Text(t('加载更多', 'Load more')),
                      ),
                    ),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 112)),
              ],
            ),
          );
        },
      ),
    ),
  );
}

class ImageLibraryThumbnail extends StatefulWidget {
  const ImageLibraryThumbnail({
    super.key,
    required this.repository,
    required this.image,
    this.english = false,
    this.owner,
  });
  final ImagesRepository repository;
  final ImageLibraryOwner? owner;
  final ManagedImage image;
  final bool english;
  @override
  State<ImageLibraryThumbnail> createState() => _ImageLibraryThumbnailState();
}

class _ImageLibraryThumbnailState extends State<ImageLibraryThumbnail> {
  late Future<Uint8List> _bytes;
  bool _original = false;
  void _read({bool reload = false}) {
    final owner = widget.owner;
    Future<Uint8List> work() => widget.repository.bytes(
      _original ? widget.image.uri : widget.image.thumbnail ?? widget.image.uri,
      reload: reload,
    );
    _bytes = owner?.run(work) ?? work();
  }

  @override
  void initState() {
    super.initState();
    _read();
  }

  @override
  void didUpdateWidget(covariant ImageLibraryThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image.uri != widget.image.uri ||
        oldWidget.image.thumbnail != widget.image.thumbnail ||
        oldWidget.repository != widget.repository) {
      _original = false;
      _read();
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
    future: _bytes,
    builder: (_, snapshot) {
      if (!(widget.owner?.isCurrent ?? true)) return const SizedBox.shrink();
      if (snapshot.hasError) {
        return Center(
          child: IconButton(
            tooltip: widget.english ? 'Retry image' : '重试图片',
            onPressed: !(widget.owner?.isCurrent ?? true)
                ? null
                : () => setState(() {
                    _original = true;
                    _read(reload: true);
                  }),
            icon: const Icon(Icons.broken_image_outlined),
          ),
        );
      }
      if (!snapshot.hasData) {
        return const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      }
      return NativeImage(
        bytes: snapshot.data!,
        label: widget.image.name,
        maxDecodeSide: 512,
        compact: true,
        english: widget.english,
        onRetry: () {
          if (!(widget.owner?.isCurrent ?? true)) return;
          setState(() {
            _original = true;
            _read(reload: true);
          });
        },
      );
    },
  );
}
