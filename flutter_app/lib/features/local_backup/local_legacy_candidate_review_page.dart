import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/local_generation_content_repository.dart';
import '../../core/local_legacy_candidate_review.dart';
import '../../core/local_legacy_format_selection.dart';
import '../../core/owned_preview_controller.dart';
import '../admin/admin_asset_secure_window.dart';
import 'local_legacy_candidate_reader_page.dart';

const reviewBlue = Color(0xff0b57ee),
    reviewInk = Color(0xff0c192e),
    reviewBackground = Color(0xfff7faff),
    reviewLine = Color(0xffe0e7f2);
ThemeData candidateReviewTheme(ThemeData base) => base.copyWith(
  colorScheme: base.colorScheme.copyWith(
    primary: reviewBlue,
    onPrimary: Colors.white,
    surface: Colors.white,
  ),
  textTheme: base.textTheme.apply(
    bodyColor: reviewInk,
    displayColor: reviewInk,
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size(0, 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(0, 48),
      side: const BorderSide(color: reviewBlue),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  ),
);

class CandidateReviewBadge extends StatelessWidget {
  const CandidateReviewBadge(this.text, {super.key, this.locked = false});
  final String text;
  final bool locked;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: locked ? const Color(0xfffff4d6) : const Color(0xffeaf2ff),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 14,
        color: locked ? const Color(0xff7a5600) : reviewBlue,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class CandidateReviewFrame extends StatelessWidget {
  const CandidateReviewFrame({
    super.key,
    required this.title,
    required this.body,
    required this.onBack,
    this.actions = const [],
  });
  final String title;
  final Widget body;
  final VoidCallback? onBack;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w700,
      color: reviewInk,
    );
    final media = MediaQuery.of(context);
    final stacked = media.size.width < 350 || media.textScaler.scale(16) > 24;
    final painter =
        TextPainter(
          text: TextSpan(text: title, style: style),
          textDirection: Directionality.of(context),
          textScaler: media.textScaler,
          maxLines: 6,
        )..layout(
          maxWidth:
              (media.size.width -
                      media.padding.horizontal -
                      (stacked ? 88 : 136))
                  .clamp(1, double.infinity)
                  .toDouble(),
        );
    final height = (painter.height + 16).clamp(56, double.infinity).toDouble();
    painter.dispose();
    return Theme(
      data: candidateReviewTheme(Theme.of(context)),
      child: Scaffold(
        backgroundColor: reviewBackground,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: reviewInk,
          toolbarHeight: height,
          title: Text(title, style: style, maxLines: 6),
          leading: IconButton(
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back),
          ),
          actions: stacked ? const [] : [...actions, const SizedBox(width: 12)],
        ),
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (stacked && actions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: actions,
                  ),
                ),
              Expanded(child: body),
            ],
          ),
        ),
      ),
    );
  }
}

class CandidateReviewCard extends StatelessWidget {
  const CandidateReviewCard({
    super.key,
    required this.child,
    this.color = Colors.white,
  });
  final Widget child;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: color,
      border: Border.all(color: reviewLine),
      borderRadius: BorderRadius.circular(12),
    ),
    child: child,
  );
}

class CandidateReviewFailure extends StatelessWidget {
  const CandidateReviewFailure({
    super.key,
    required this.english,
    required this.onReturn,
    this.busy = false,
  });
  final bool english, busy;
  final VoidCallback? onReturn;
  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: CandidateReviewCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.find_in_page_outlined,
              size: 64,
              color: Color(0xff43536d),
            ),
            const SizedBox(height: 24),
            Text(
              english ? 'Cannot read review copy' : '无法读取审阅副本',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            Text(
              english
                  ? 'Original files and current data are unaffected.'
                  : '原文件和当前数据未受影响。',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: busy ? null : onReturn,
                child: Text(english ? 'Return to migration checks' : '返回迁移检查'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class LocalLegacyCandidateReviewPage extends StatefulWidget {
  const LocalLegacyCandidateReviewPage({
    super.key,
    required this.session,
    this.english = false,
    this.windowGuardFactory,
  });
  final LegacyCandidateReviewSession session;
  final bool english;
  final AdminAssetWindowGuard Function()? windowGuardFactory;
  @override
  State<LocalLegacyCandidateReviewPage> createState() =>
      _LocalLegacyCandidateReviewPageState();
}

class _LocalLegacyCandidateReviewPageState
    extends State<LocalLegacyCandidateReviewPage>
    with WidgetsBindingObserver {
  late final LegacyCandidateReviewSession _session;
  final _readers = <Route<dynamic>, OwnedPreviewController>{};
  GenerationContentCounts? _counts;
  List<GenerationContentListEntry> _items = const [];
  String _collection = 'all';
  var _page = 1, _epoch = 0;
  bool _loading = true,
      _failed = false,
      _leaving = false,
      _disposed = false,
      _more = false;
  String t(String zh, String en) => widget.english ? en : zh;
  @override
  void initState() {
    super.initState();
    _session = widget.session;
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  Future<void> _load({bool append = false}) async {
    final epoch = ++_epoch;
    if (mounted && !_disposed) {
      setState(() {
        _loading = true;
        _failed = false;
      });
    }
    try {
      final counts = await _session.counts(),
          items = await _session.list(collection: _collection, page: _page);
      if (!mounted || _disposed || _leaving || epoch != _epoch) return;
      setState(() {
        _counts = counts;
        _items = append ? [..._items, ...items] : items;
        _more = items.length == 20;
        _loading = false;
      });
    } catch (_) {
      if (mounted && !_disposed && !_leaving && epoch == _epoch) {
        setState(() {
          _failed = true;
          _loading = false;
          _counts = null;
          _items = const [];
        });
      }
    }
  }

  Future<void> _closeResources() async {
    for (final controller in _readers.values.toList()) {
      await controller.retire();
    }
    for (final route in _readers.keys.toList()) {
      final nav = route.navigator;
      if (nav != null && nav.mounted && route.isActive) nav.removeRoute(route);
    }
    _readers.clear();
    await _session.close();
  }

  Future<void> _leave() async {
    if (_leaving || _disposed || !mounted) return;
    _epoch++;
    setState(() => _leaving = true);
    try {
      await _closeResources();
      if (mounted && !_disposed) Navigator.of(context).pop();
    } catch (_) {
      if (mounted && !_disposed) {
        setState(() {
          _leaving = false;
          _failed = true;
        });
      }
    }
  }

  Future<void> _open(GenerationContentMetadata metadata) async {
    if (_leaving || _loading || _readers.isNotEmpty || !_session.isCurrent) {
      return;
    }
    final controller = OwnedPreviewController();
    final route = MaterialPageRoute<void>(
      builder: (_) => LocalLegacyCandidateReaderPage(
        session: _session,
        metadata: metadata,
        routeController: controller,
        english: widget.english,
        windowGuardFactory: widget.windowGuardFactory,
        onReturnToChecks: _leave,
      ),
    );
    _session.attachViewer(controller, controller.retire);
    _readers[route] = controller;
    try {
      await Navigator.of(context).push(route);
    } finally {
      try {
        await _session.detachViewer(controller);
        _readers.remove(route);
        controller.dispose();
      } catch (_) {
        if (mounted && !_disposed) setState(() => _failed = true);
      }
    }
  }

  @override
  void didUpdateWidget(covariant LocalLegacyCandidateReviewPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.session, _session) || !_session.isCurrent) {
      _epoch++;
      _failed = true;
      _loading = false;
      unawaited(_closeResources().catchError((Object _) {}));
      unawaited(widget.session.close().catchError((Object _) {}));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_leaving && !_disposed) {
      if (!_session.isCurrent) {
        unawaited(_closeResources().catchError((Object _) {}));
      }
      _page = 1;
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(() async {
      // Sibling routes may be unmounting in the same frame.
      await Future<void>.value();
      for (var attempt = 0; attempt < 3; attempt++) {
        try {
          await _closeResources();
          return;
        } catch (_) {}
      }
    }());
    super.dispose();
  }

  Widget _summary() => CandidateReviewCard(
    color: const Color(0xffeaf2ff),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.check_circle, color: reviewBlue, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t('副本已校验', 'Copy verified'),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(t('当前数据尚未切换', 'Current data has not been switched')),
                  Text(
                    t('旧版导出 · 本地副本', 'Legacy export · Local copy'),
                    style: const TextStyle(fontSize: 14),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),
        LayoutBuilder(
          builder: (context, box) {
            final wide =
                MediaQuery.textScalerOf(context).scale(16) <= 25 &&
                box.maxWidth >= 240;
            final stats = [
              (t('笔记', 'Notes'), _counts!.notes),
              (t('文章', 'Articles'), _counts!.articles),
              (t('受保护', 'Protected'), _counts!.protectedItems),
            ];
            Widget value((String, int) stat) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(stat.$1, style: const TextStyle(fontSize: 14)),
                const SizedBox(height: 4),
                Text(
                  stat.$2.toString(),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            );
            return wide
                ? Row(
                    children: [
                      for (var i = 0; i < stats.length; i++) ...[
                        Expanded(child: value(stats[i])),
                        if (i < stats.length - 1)
                          const SizedBox(
                            height: 40,
                            child: VerticalDivider(
                              color: reviewLine,
                              width: 16,
                            ),
                          ),
                      ],
                    ],
                  )
                : Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      for (final stat in stats)
                        SizedBox(width: box.maxWidth, child: value(stat)),
                    ],
                  );
          },
        ),
      ],
    ),
  );
  Widget _row(GenerationContentMetadata metadata) {
    final collection = metadata.collection == 'article'
        ? t('文章', 'Article')
        : t('笔记', 'Note');
    final format = metadata.format == LegacyContentFormat.markdown
        ? 'Markdown'
        : metadata.format == LegacyContentFormat.html
        ? 'HTML'
        : metadata.format.name;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: reviewLine),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _leaving ? null : () => _open(metadata),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        metadata.title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$collection · $format',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xff536079),
                        ),
                      ),
                    ],
                  ),
                ),
                if (metadata.isProtected) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: CandidateReviewBadge(
                      t('已锁定', 'Locked'),
                      locked: true,
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final counts = _counts;
    Widget body;
    if (_failed || (!_leaving && !_session.isCurrent)) {
      body = CandidateReviewFailure(
        english: widget.english,
        onReturn: _leave,
        busy: _leaving,
      );
    } else if (counts == null) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      body = CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList.list(
              children: [
                _summary(),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final filter in [
                      ('all', t('全部', 'All')),
                      ('note', t('笔记', 'Notes')),
                      ('article', t('文章', 'Articles')),
                    ])
                      ChoiceChip(
                        label: Text(filter.$2),
                        selected: _collection == filter.$1,
                        selectedColor: const Color(0xffeaf2ff),
                        backgroundColor: Colors.white,
                        checkmarkColor: reviewBlue,
                        labelStyle: TextStyle(
                          color: _collection == filter.$1
                              ? reviewBlue
                              : reviewInk,
                        ),
                        side: BorderSide(
                          color: _collection == filter.$1
                              ? reviewBlue
                              : reviewLine,
                        ),
                        onSelected: _loading || _leaving
                            ? null
                            : (_) {
                                setState(() {
                                  _collection = filter.$1;
                                  _page = 1;
                                });
                                unawaited(_load());
                              },
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_loading) const LinearProgressIndicator(),
                if (_items.isEmpty && !_loading)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Text(
                      t('没有可审阅的内容', 'No content to review'),
                      textAlign: TextAlign.center,
                    ),
                  ),
                for (final item in _items) _row(item.metadata),
                if (_more)
                  TextButton(
                    onPressed: _loading || _leaving
                        ? null
                        : () {
                            _page++;
                            unawaited(_load(append: true));
                          },
                    child: Text(t('加载更多', 'Load more')),
                  ),
              ],
            ),
          ),
          SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    t(
                      '只读查看，不会替换当前数据。',
                      'Read only. Current data will not be replaced.',
                    ),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xff536079),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _leaving ? null : _leave,
                    child: Text(t('返回迁移检查', 'Return to migration checks')),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_leave());
      },
      child: CandidateReviewFrame(
        title: t('审阅迁移副本', 'Review migration copy'),
        onBack: _leaving ? null : _leave,
        actions: [CandidateReviewBadge(t('只读', 'Read only'))],
        body: body,
      ),
    );
  }
}
