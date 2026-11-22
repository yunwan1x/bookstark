import 'local_assistant_draft_ledger.dart';
import 'local_assistant_draft_payload.dart';
import 'local_model_stream.dart';

/// Model tools persist proposals only. They never receive a content repository,
/// SQL executor, editor callback or authority to confirm a save.
class LocalAssistantProposalTools {
  LocalAssistantProposalTools(this.ledger);
  final LocalAssistantDraftLedger ledger;
  static final definitions = List<LocalModelToolDefinition>.unmodifiable([
    LocalModelToolDefinition(
      name: 'propose_note',
      description:
          'Prepare an unsaved Markdown note draft for user review and editing. This does not create a resource. Only the user can save in the editor.',
      parameters: {
        'type': 'object',
        'properties': {
          'title': {'type': 'string', 'maxLength': 200},
          'content': {'type': 'string', 'maxLength': 24000},
        },
        'required': ['title', 'content'],
        'additionalProperties': false,
      },
    ),
    LocalModelToolDefinition(
      name: 'propose_task',
      description:
          'Prepare an unsaved root task draft for user review. Optional due_date is YYYY-MM-DD. This does not create a task or confirm a save.',
      parameters: {
        'type': 'object',
        'properties': {
          'content': {'type': 'string', 'maxLength': 1000},
          'due_date': {'type': 'string'},
        },
        'required': ['content'],
        'additionalProperties': false,
      },
    ),
  ]);
  Future<Map<String, Object?>> invoke(
    String name,
    Map<String, Object?> args,
  ) async {
    final allowed = name == 'propose_note'
        ? {'title', 'content'}
        : name == 'propose_task'
        ? {'content', 'due_date'}
        : const <String>{};
    if (allowed.isEmpty || args.keys.any((key) => !allowed.contains(key))) {
      throw const FormatException('Unsupported proposal tool or fields');
    }
    final payload = LocalAssistantDraftPayload.fromJson({
      'kind': name == 'propose_note' ? 'note' : 'task',
      ...args,
    });
    final record = await ledger.propose(payload);
    return {
      'draft_id': record.id,
      'kind': record.payload.kind.name,
      'status': 'pending',
      'saved': false,
      'next_action': 'User must review and explicitly save in the editor.',
    };
  }
}
