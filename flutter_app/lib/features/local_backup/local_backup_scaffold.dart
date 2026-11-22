import 'package:flutter/material.dart';

/// Short pages place actions at the bottom; long content and all actions remain
/// in one scroll view. Changing logical page identity starts at the top.
class LocalBackupScaffold extends StatelessWidget {
  const LocalBackupScaffold({
    super.key,
    required this.title,
    required this.content,
    this.actions = const [],
    this.busy = false,
    this.onBack,
    this.scrollIdentity,
    this.wrapTitle = false,
  });
  final String title;
  final List<Widget> content, actions;
  final bool busy, wrapTitle;
  final VoidCallback? onBack;
  final Object? scrollIdentity;
  List<Widget> spaced(List<Widget> widgets) => [
    for (var i = 0; i < widgets.length; i++) ...[
      widgets[i],
      if (i + 1 < widgets.length) const SizedBox(height: 16),
    ],
  ];
  @override
  Widget build(BuildContext context) {
    double? toolbarHeight;
    if (wrapTitle) {
      final media = MediaQuery.of(context);
      final style =
          Theme.of(context).appBarTheme.titleTextStyle ??
          Theme.of(context).textTheme.titleLarge;
      final painter =
          TextPainter(
            text: TextSpan(text: title, style: style),
            textDirection: Directionality.of(context),
            textScaler: media.textScaler,
            maxLines: 6,
          )..layout(
            maxWidth: (media.size.width - media.padding.horizontal - 88)
                .clamp(1, double.infinity)
                .toDouble(),
          );
      toolbarHeight = (painter.height + 16)
          .clamp(kToolbarHeight, double.infinity)
          .toDouble();
      painter.dispose();
    }
    return PopScope(
      canPop: !busy,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          toolbarHeight: toolbarHeight,
          title: Text(
            title,
            maxLines: wrapTitle ? 6 : null,
            softWrap: wrapTitle ? true : null,
            overflow: wrapTitle ? TextOverflow.ellipsis : null,
          ),
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xff0c192e),
          leading: IconButton(
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: busy
                ? null
                : onBack ?? () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back),
          ),
        ),
        body: SafeArea(
          child: CustomScrollView(
            key: ValueKey(scrollIdentity),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverList.list(children: spaced(content)),
              ),
              if (actions.isNotEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: spaced(actions),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
