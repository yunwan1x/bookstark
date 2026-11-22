import 'package:flutter/material.dart';
import '../../core/attachments.dart';
import '../../core/tasks_repository.dart';
import '../../widgets/bookstark_markdown.dart';

enum TaskCardAction { edit, addChild, children, trash }

class TaskCard extends StatelessWidget {
  const TaskCard({
    super.key,
    required this.task,
    this.children = const [],
    this.busyIds = const {},
    this.english = false,
    this.enableActions = true,
    this.allowStatusChanges = true,
    this.showParent = true,
    this.attachments,
    required this.onToggle,
    required this.onEdit,
    required this.onAddChild,
    required this.onChildren,
    required this.onRemove,
    required this.onParent,
  });
  final TaskItem task;
  final List<TaskItem> children;
  final Set<int> busyIds;
  final bool english, enableActions, showParent, allowStatusChanges;
  final AttachmentRepository? attachments;
  final void Function(TaskItem, bool) onToggle;
  final void Function(TaskItem) onEdit, onAddChild, onChildren, onRemove;
  final void Function(int) onParent;
  String t(String zh, String en) => english ? en : zh;
  Widget _row(BuildContext context, TaskItem item, {bool child = false}) {
    final busy = busyIds.contains(item.id);
    final title = String.fromCharCodes(
      item.content.split('\n').first.runes.take(60),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          label: item.done
              ? t('重新打开：$title', 'Reopen: $title')
              : t('标记完成：$title', 'Complete: $title'),
          child: Checkbox(
            value: item.done,
            onChanged: busy || !allowStatusChanges
                ? null
                : (value) => onToggle(item, value!),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BookstarkMarkdown(
                  data: item.content,
                  paragraphStyle: item.content.contains('\n')
                      ? null
                      : Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  attachments: attachments,
                  english: english,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      item.dueDate.isEmpty
                          ? t('未设置截止日期', 'No due date set')
                          : t('截止：${item.dueDate}', 'Due: ${item.dueDate}'),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (busy)
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          semanticsLabel: t('正在更新状态', 'Updating status'),
                        ),
                      ),
                    if (item.childTotal > 0)
                      Text(
                        t(
                          '子待办 ${item.childDone}/${item.childTotal}',
                          'Subtasks ${item.childDone}/${item.childTotal}',
                        ),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    if (!child && showParent && item.parentId > 0)
                      TextButton(
                        onPressed: enableActions
                            ? () => onParent(item.parentId)
                            : null,
                        child: Text(t('查看父待办', 'View parent task')),
                      ),
                  ],
                ),
                if (!child && item.childTotal > 0)
                  TextButton(
                    onPressed: enableActions ? () => onAddChild(item) : null,
                    child: Text(t('添加子待办', 'Add subtask')),
                  ),
              ],
            ),
          ),
        ),
        PopupMenuButton<TaskCardAction>(
          enabled: enableActions && !busy,
          tooltip: t('待办操作', 'Task actions'),
          onSelected: (action) {
            switch (action) {
              case TaskCardAction.edit:
                onEdit(item);
                break;
              case TaskCardAction.addChild:
                onAddChild(item);
                break;
              case TaskCardAction.children:
                onChildren(item);
                break;
              case TaskCardAction.trash:
                onRemove(item);
                break;
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: TaskCardAction.edit,
              child: Text(t('编辑', 'Edit')),
            ),
            PopupMenuItem(
              value: TaskCardAction.addChild,
              child: Text(t('添加子待办', 'Add subtask')),
            ),
            PopupMenuItem(
              value: TaskCardAction.children,
              child: Text(t('查看子待办', 'View subtasks')),
            ),
            PopupMenuItem(
              value: TaskCardAction.trash,
              child: Text(t('移到回收站', 'Move to trash')),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _row(context, task),
          for (final child in children)
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Column(
                children: [
                  Divider(color: Theme.of(context).colorScheme.outline),
                  _row(context, child, child: true),
                ],
              ),
            ),
          if (task.childTotal > children.length)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: enableActions ? () => onChildren(task) : null,
                child: Text(
                  t(
                    '查看全部${task.childTotal}条子待办',
                    'View all ${task.childTotal} subtasks',
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
