import 'package:flutter/material.dart';
import '../../core/attachments.dart';
import '../../core/completion_repository.dart';
import '../../core/draft_vault.dart';
import '../../core/task_draft_vault.dart';
import '../../core/tasks_repository.dart';
import '../../core/topic_draft_vault.dart';
import '../../core/topic_resource_picker_repository.dart';
import '../../core/topics_repository.dart';
import 'topic_calendar_page.dart';
import 'topic_detail_page.dart';
import 'topics_page.dart';

class TopicsFeature extends StatelessWidget {
  const TopicsFeature({
    super.key,
    required this.repository,
    required this.tasks,
    required this.picker,
    required this.onOpenResource,
    this.initialTopicId,
    this.onRecoverCreations,
    this.topicDrafts,
    this.summaryDrafts,
    this.commentDrafts,
    this.taskDrafts,
    this.recoverTaskCreation,
    this.attachments,
    this.completion,
    this.onSpeak,
    this.english = false,
    this.local = false,
  });
  final int? initialTopicId;
  final Future<void> Function(BuildContext)? onRecoverCreations;
  final TopicsRepository repository;
  final TasksRepository tasks;
  final TopicResourcePickerRepository picker;
  final Future<void> Function(BuildContext context, TopicResource resource)
  onOpenResource;
  final TopicDraftVault? topicDrafts;
  final DraftVault Function(int topicId)? summaryDrafts;
  final DraftVault Function(int topicId, TopicCommentTarget type, int targetId)?
  commentDrafts;
  final TaskDraftVault Function(int topicId)? taskDrafts;
  final Future<void> Function()? recoverTaskCreation;
  final AttachmentRepository? attachments;
  final CompletionRepository? completion;
  final Future<void> Function(String markdown, String title, String context)?
  onSpeak;
  final bool english, local;
  Widget _detail(BuildContext context, int id) => TopicDetailPage(
    key: ValueKey((repository, tasks, id, local)),
    repository: repository,
    topicId: id,
    tasks: tasks,
    picker: picker,
    onOpenResource: (resource) => onOpenResource(context, resource),
    topicDrafts: topicDrafts,
    summaryDrafts: summaryDrafts?.call(id),
    commentDrafts: commentDrafts == null
        ? null
        : (type, target) => commentDrafts!(id, type, target),
    taskDrafts: taskDrafts?.call(id),
    recoverTaskCreation: recoverTaskCreation,
    attachments: attachments,
    completion: completion,
    onSpeak: onSpeak,
    english: english,
    local: local,
  );
  @override
  Widget build(BuildContext context) => initialTopicId != null
      ? _detail(context, initialTopicId!)
      : TopicsPage(
          key: ValueKey((repository, tasks, local)),
          repository: repository,
          onRecoverCreations: onRecoverCreations,
          vault: topicDrafts,
          english: english,
          onCalendar: (selected) => Navigator.push<String>(
            context,
            MaterialPageRoute(
              builder: (_) => TopicCalendarPage(
                repository: repository,
                selectedDate: selected,
                english: english,
              ),
            ),
          ),
          onOpenTopic: (id) => Navigator.push<void>(
            context,
            MaterialPageRoute(builder: (context) => _detail(context, id)),
          ),
        );
}
