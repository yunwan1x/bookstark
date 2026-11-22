import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/xml.dart';
import 'package:re_highlight/languages/javascript.dart';
import 'package:re_highlight/languages/css.dart';
import 'package:re_highlight/styles/github.dart';
import '../../core/html_source_buffer.dart';

/// Flutter code editor; HTML is text here and never executed. Browser preview
/// is a separate widget, so changing tabs cannot replace the saved source.
class HtmlSourceEditor extends StatefulWidget {
  const HtmlSourceEditor({
    super.key,
    required this.source,
    required this.onChanged,
    this.readOnly = false,
    this.english = false,
  });
  final String source;
  final ValueChanged<String> onChanged;
  final bool readOnly, english;
  @override
  State<HtmlSourceEditor> createState() => _HtmlSourceEditorState();
}

class _HtmlSourceEditorState extends State<HtmlSourceEditor> {
  late HtmlSourceBuffer _buffer;
  late CodeLineEditingController _code;
  late CodeFindController _find;
  late CodeLines _lastLines;
  final _focus = FocusNode();
  bool _wrap = false;
  String t(String zh, String en) => widget.english ? en : zh;
  @override
  void initState() {
    super.initState();
    _create();
  }

  void _create() {
    _buffer = HtmlSourceBuffer(widget.source);
    _code = CodeLineEditingController.fromText(_buffer.text);
    _lastLines = _code.codeLines;
    _find = CodeFindController(_code);
    _code.addListener(_changed);
  }

  void _release() {
    _code.removeListener(_changed);
    _find.dispose();
    _code.dispose();
  }

  void _changed() {
    // CodeEditor notifies when attaching its delegate during build, and when
    // only the caret moves. Neither changes source nor needs a parent rebuild.
    if (identical(_lastLines, _code.codeLines)) return;
    _lastLines = _code.codeLines;
    final before = _buffer.source;
    final after = _buffer.apply(_code.text);
    if (after == before) return;
    widget.onChanged(after);
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(HtmlSourceEditor old) {
    super.didUpdateWidget(old);
    if (widget.source != _buffer.source) {
      _release();
      _create();
    }
  }

  @override
  void dispose() {
    _release();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<CodeFindValue?>(
    valueListenable: _find,
    builder: (context, find, _) => Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            children: [
              IconButton(
                tooltip: t('撤销', 'Undo'),
                onPressed: !widget.readOnly && _code.canUndo
                    ? _code.undo
                    : null,
                icon: const Icon(Icons.undo),
              ),
              IconButton(
                tooltip: t('重做', 'Redo'),
                onPressed: !widget.readOnly && _code.canRedo
                    ? _code.redo
                    : null,
                icon: const Icon(Icons.redo),
              ),
              IconButton(
                tooltip: t('查找与替换', 'Find and replace'),
                onPressed: () {
                  if (find == null) {
                    _find.findMode();
                  } else {
                    _find.close();
                  }
                },
                icon: const Icon(Icons.find_replace),
              ),
              IconButton(
                tooltip: t('自动换行', 'Word wrap'),
                isSelected: _wrap,
                onPressed: () => setState(() => _wrap = !_wrap),
                icon: const Icon(Icons.wrap_text),
              ),
            ],
          ),
        ),
        if (find != null)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(8),
              child: Column(
                children: [
                  TextField(
                    key: const ValueKey('html-find'),
                    controller: _find.findInputController,
                    focusNode: _find.findInputFocusNode,
                    decoration: InputDecoration(labelText: t('查找', 'Find')),
                    onSubmitted: (_) => _find.nextMatch(),
                  ),
                  if (!widget.readOnly)
                    TextField(
                      key: const ValueKey('html-replace'),
                      controller: _find.replaceInputController,
                      focusNode: _find.replaceInputFocusNode,
                      decoration: InputDecoration(
                        labelText: t('替换为', 'Replace with'),
                      ),
                    ),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        find.searching
                            ? t('查找中…', 'Searching…')
                            : '${find.result?.matches.length ?? 0} ${t('处匹配', 'matches')}',
                      ),
                      IconButton(
                        tooltip: t('上一处', 'Previous match'),
                        onPressed: _find.previousMatch,
                        icon: const Icon(Icons.keyboard_arrow_up),
                      ),
                      IconButton(
                        tooltip: t('下一处', 'Next match'),
                        onPressed: _find.nextMatch,
                        icon: const Icon(Icons.keyboard_arrow_down),
                      ),
                      if (!widget.readOnly)
                        TextButton(
                          onPressed: _find.replaceMatch,
                          child: Text(t('替换', 'Replace')),
                        ),
                      if (!widget.readOnly)
                        TextButton(
                          onPressed: _find.replaceAllMatches,
                          child: Text(t('全部替换', 'Replace all')),
                        ),
                      IconButton(
                        tooltip: t('关闭查找', 'Close find'),
                        onPressed: _find.close,
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        Expanded(
          child: CodeEditor(
            controller: _code,
            findController: _find,
            focusNode: _focus,
            autofocus: false,
            readOnly: widget.readOnly,
            wordWrap: _wrap,
            autocompleteSymbols: false,
            padding: const EdgeInsets.all(12),
            border: Border.all(color: const Color(0xffd4dce9)),
            borderRadius: BorderRadius.circular(12),
            style: CodeEditorStyle(
              fontSize: MediaQuery.textScalerOf(context).scale(14),
              fontFamily: 'monospace',
              fontHeight: 1.5,
              backgroundColor: Colors.white,
              codeTheme: CodeHighlightTheme(
                languages: {
                  'xml': CodeHighlightThemeMode(mode: langXml),
                  'javascript': CodeHighlightThemeMode(mode: langJavascript),
                  'css': CodeHighlightThemeMode(mode: langCss),
                },
                theme: githubTheme,
              ),
            ),
            indicatorBuilder: (context, editing, chunks, notifier) => Row(
              children: [
                DefaultCodeLineNumber(controller: editing, notifier: notifier),
                DefaultCodeChunkIndicator(
                  width: 20,
                  controller: chunks,
                  notifier: notifier,
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
