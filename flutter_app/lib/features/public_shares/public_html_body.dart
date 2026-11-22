import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../html/html_preview.dart';
import 'public_html_browser_preview.dart';

class PublicHtmlBody extends StatefulWidget {
  const PublicHtmlBody({
    super.key,
    required this.source,
    required this.server,
    this.english = false,
  });
  final String source;
  final Uri server;
  final bool english;
  @override
  State<PublicHtmlBody> createState() => _PublicHtmlBodyState();
}

class _PublicHtmlBodyState extends State<PublicHtmlBody> {
  bool _interactive = false;
  String t(String zh, String en) => widget.english ? en : zh;
  @override
  void didUpdateWidget(covariant PublicHtmlBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source ||
        oldWidget.server != widget.server) {
      _interactive = false;
    }
  }

  void select(bool value) => setState(() => _interactive = value);
  @override
  Widget build(BuildContext context) {
    final supported =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (supported) ...[
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 280 ||
                  MediaQuery.textScalerOf(context).scale(14) > 19) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final mode in [false, true])
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: OutlinedButton(
                          onPressed: () => select(mode),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              children: [
                                Icon(
                                  _interactive == mode
                                      ? Icons.check
                                      : mode
                                      ? Icons.touch_app_outlined
                                      : Icons.article_outlined,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    mode
                                        ? t('交互预览', 'Interactive preview')
                                        : t('轻量预览', 'Light preview'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              }
              return SegmentedButton<bool>(
                segments: [
                  ButtonSegment(
                    value: false,
                    icon: const Icon(Icons.article_outlined),
                    label: Text(t('轻量预览', 'Light preview')),
                  ),
                  ButtonSegment(
                    value: true,
                    icon: const Icon(Icons.touch_app_outlined),
                    label: Text(t('交互预览', 'Interactive preview')),
                  ),
                ],
                selected: {_interactive},
                onSelectionChanged: (value) => select(value.single),
              );
            },
          ),
          const SizedBox(height: 12),
        ],
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xffe8efff),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _interactive && supported
                      ? t(
                          '交互预览会运行作者脚本，仅加载此服务器的公开资源。',
                          'Interactive preview runs the author’s scripts and loads public resources from this server only.',
                        )
                      : t('轻量模式不运行脚本。', 'Light preview does not run scripts.'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (_interactive && supported)
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: PublicHtmlBrowserPreview(
              source: widget.source,
              server: widget.server,
              english: widget.english,
            ),
          )
        else
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: NativeHtmlPreview(
              source: widget.source,
              english: widget.english,
            ),
          ),
      ],
    );
  }
}
