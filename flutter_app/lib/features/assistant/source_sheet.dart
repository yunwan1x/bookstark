import 'package:flutter/material.dart';
import '../../core/assistant_repository.dart';
import '../../core/attachments.dart';
import '../../widgets/bookstark_markdown.dart';

class AssistantSourceSheet extends StatefulWidget {
  const AssistantSourceSheet({
    super.key,
    required this.repository,
    required this.source,
    this.attachments,
    this.english = false,
  });
  final AssistantDataSource repository;
  final Map<String, Object?> source;
  final AttachmentRepository? attachments;
  final bool english;
  @override
  State<AssistantSourceSheet> createState() => _AssistantSourceSheetState();
}

class _AssistantSourceSheetState extends State<AssistantSourceSheet> {
  late Future<AssistantResourceDetail> _detail;
  @override
  void initState() {
    super.initState();
    _detail = widget.repository.readSource(widget.source);
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: MediaQuery.sizeOf(context).height * 0.8,
    child: Column(
      children: [
        ListTile(
          title: Text(widget.english ? 'Source material' : '来源资料'),
          trailing: IconButton(
            tooltip: widget.english ? 'Close' : '关闭',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
        ),
        Expanded(
          child: FutureBuilder<AssistantResourceDetail>(
            future: _detail,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    Text(snapshot.error.toString()),
                    FilledButton(
                      onPressed: () {
                        setState(() {
                          _detail = widget.repository.readSource(widget.source);
                        });
                      },
                      child: Text(widget.english ? 'Retry' : '重试'),
                    ),
                  ],
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final detail = snapshot.data!;
              return ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Text(
                    detail.title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  if (detail.metadata['due_date'] is String)
                    Text(
                      '${widget.english ? 'Due' : '日期'}: ${detail.metadata['due_date']}',
                    ),
                  if (detail.metadata['done'] is bool)
                    Text(
                      detail.metadata['done'] == true
                          ? (widget.english ? 'Done' : '已完成')
                          : (widget.english ? 'Pending' : '未完成'),
                    ),
                  if (detail.metadata['url'] is String)
                    SelectableText(detail.metadata['url'] as String),
                  const SizedBox(height: 16),
                  BookstarkMarkdown(
                    data: detail.content,
                    attachments: widget.attachments,
                    english: widget.english,
                  ),
                ],
              );
            },
          ),
        ),
      ],
    ),
  );
}
