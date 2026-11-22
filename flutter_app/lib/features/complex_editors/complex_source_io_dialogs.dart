import 'package:flutter/material.dart';
import '../../core/complex_source_io_controller.dart';
import '../../core/native_complex_source_io.dart';

enum ComplexSourceIoAction { importSource, exportSource }

Future<ComplexSourceIoAction?> showComplexSourceIoSheet(
  BuildContext context, {
  required String format,
  bool english = false,
}) {
  String t(String zh, String en) => english ? en : zh;
  return showModalBottomSheet<ComplexSourceIoAction>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              t('源文件导入与导出', 'Source file import and export'),
              style: Theme.of(ctx).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            Text(t('当前类型：', 'Current format: ') + format),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () =>
                  Navigator.pop(ctx, ComplexSourceIoAction.importSource),
              icon: const Icon(Icons.folder_open),
              label: Text(t('导入同类型源文件', 'Import same-format source')),
            ),
            OutlinedButton.icon(
              onPressed: () =>
                  Navigator.pop(ctx, ComplexSourceIoAction.exportSource),
              icon: const Icon(Icons.save_alt),
              label: Text(t('导出当前源文件', 'Export current source')),
            ),
            const SizedBox(height: 16),
            Text(
              t(
                '仅支持当前编辑器原始格式，不转换 Office 文件。',
                'Only the current editor source format is supported. No Office conversion.',
              ),
            ),
            const SizedBox(height: 12),
            Text(
              t(
                '导入仅替换草稿，需手动保存。导出不会保存文档。',
                'Import only replaces the draft and requires explicit Save. Export does not save the document.',
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<bool> confirmComplexSourceImport(
  BuildContext context,
  ComplexSourceFile file, {
  bool english = false,
}) async {
  String t(String zh, String en) => english ? en : zh;
  var checked = false;
  return await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, set) => Dialog(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      t('替换当前草稿？', 'Replace current draft?'),
                      style: Theme.of(ctx).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 16),
                    SelectableText(file.name),
                    Text(
                      '${file.document.kind.name} · ${file.document.byteLength} bytes',
                    ),
                    const SizedBox(height: 16),
                    Text(
                      t(
                        '当前未保存草稿将被替换，已保存内容不变。',
                        'This replaces the current unsaved draft. Saved content is unchanged.',
                      ),
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: checked,
                      onChanged: (v) => set(() => checked = v == true),
                      title: Text(
                        t('我确认替换当前草稿', 'I confirm replacing the current draft'),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: checked
                          ? () => Navigator.pop(ctx, true)
                          : null,
                      child: Text(t('确认导入为草稿', 'Import as draft')),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text(
                        t('取消并保留原草稿', 'Cancel and retain original draft'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ) ??
      false;
}

class ComplexSourceExportProgress extends StatelessWidget {
  const ComplexSourceExportProgress({
    super.key,
    required this.controller,
    required this.name,
    this.english = false,
  });
  final ComplexSourceIoController controller;
  final String name;
  final bool english;
  @override
  Widget build(BuildContext context) {
    String t(String zh, String en) => english ? en : zh;
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(t('导出源文件', 'Export source file')),
        ),
        body: AnimatedBuilder(
          animation: controller,
          builder: (context, _) => ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SelectableText(name),
                ),
              ),
              const SizedBox(height: 24),
              LinearProgressIndicator(
                value: controller.total <= 0
                    ? null
                    : controller.written / controller.total,
              ),
              const SizedBox(height: 16),
              Text(
                t(
                  '正在写入系统选择的位置…',
                  'Writing to the system-selected destination…',
                ),
              ),
              Text('${controller.written} / ${controller.total} bytes'),
              const SizedBox(height: 24),
              OutlinedButton(
                onPressed: () => controller.cancel(),
                child: Text(t('取消导出', 'Cancel export')),
              ),
              const SizedBox(height: 16),
              Text(
                t(
                  '仅写全、核对传输字节并关闭目标后显示完成。无法读回的提供方不声称目标指纹验证。',
                  'Completion requires full checked transfer and destination close. No destination hash verification is claimed without readback.',
                ),
              ),
              const SizedBox(height: 16),
              Text(
                t(
                  '取消或失败时目标可能包含部分内容。不会自动保存编辑中的文档。',
                  'Cancellation or failure may leave partial content. The editor document is not saved.',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
