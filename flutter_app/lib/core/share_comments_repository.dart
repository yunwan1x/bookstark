import 'api_client.dart';
import 'public_share_models.dart';
import 'share_comment_models.dart';

abstract interface class ShareCommentsRepository {
  Future<ShareCommentCapabilities> capabilities(
    PublicShareDetail context, {
    Future<void>? abortTrigger,
  });
  Future<PublicShareCommentPage> list(
    PublicShareDetail context,
    int page, {
    Future<void>? abortTrigger,
  });
  Future<PublicShareComment> create(
    PublicShareDetail context,
    ShareCommentCapabilities capabilities,
    PublicCommentInput input,
  );
  Future<void> remove(PublicShareDetail context, PublicShareComment comment);
}

class RemoteShareCommentsRepository implements ShareCommentsRepository {
  RemoteShareCommentsRepository(this.client);
  final BookstarkClient client;
  void _check(PublicShareDetail context) {
    if (context.reference.server != client.baseUri || context.locked) {
      throw StateError('Public comments require the current readable share');
    }
  }

  @override
  Future<ShareCommentCapabilities> capabilities(
    PublicShareDetail context, {
    Future<void>? abortTrigger,
  }) async {
    _check(context);
    return parseShareCommentCapabilities(
      await client.publicSharePageHtml(
        context.reference,
        abortTrigger: abortTrigger,
      ),
      context.reference,
    );
  }

  @override
  Future<PublicShareCommentPage> list(
    PublicShareDetail context,
    int page, {
    Future<void>? abortTrigger,
  }) async {
    _check(context);
    return PublicShareCommentPage.parse(
      await client.publicCommentsJson(
        context.reference,
        page: page,
        abortTrigger: abortTrigger,
      ),
      context,
      requestedPage: page,
    );
  }

  @override
  Future<PublicShareComment> create(
    PublicShareDetail context,
    ShareCommentCapabilities capabilities,
    PublicCommentInput input,
  ) async {
    _check(context);
    final body = input.body(capabilities);
    final row = await client.publicCommentsJson(context.reference, body: body);
    final parsed = PublicShareComment.parse(
      row,
      context,
      root: input.parentId == 0 ? null : row['root_comment_id'] as int?,
    );
    if (parsed.deleted ||
        parsed.parentId != input.parentId ||
        parsed.replyToId != input.replyToId) {
      throw const FormatException('Comment receipt changed reply membership');
    }
    return parsed;
  }

  @override
  Future<void> remove(
    PublicShareDetail context,
    PublicShareComment comment,
  ) async {
    _check(context);
    if (!comment.canDelete || comment.deleted) {
      throw StateError('Comment deletion is not permitted');
    }
    await client.publicCommentsJson(context.reference, deleteId: comment.id);
  }
}

enum PublicCommentSubmissionPhase { editing, submitting, unknown, acknowledged }

class PublicCommentSubmission {
  PublicCommentSubmission(this.repository, this.context);
  final ShareCommentsRepository repository;
  final PublicShareDetail context;
  PublicCommentSubmissionPhase phase = PublicCommentSubmissionPhase.editing;
  PublicCommentInput? input;
  PublicShareComment? receipt;
  Future<PublicShareComment> submit(
    ShareCommentCapabilities capabilities,
    PublicCommentInput value,
  ) async {
    if (phase != PublicCommentSubmissionPhase.editing) {
      throw StateError('Submission cannot be repeated');
    }
    value.body(capabilities);
    input = value;
    phase = PublicCommentSubmissionPhase.submitting;
    try {
      final result = await repository.create(context, capabilities, value);
      receipt = result;
      phase = PublicCommentSubmissionPhase.acknowledged;
      return result;
    } catch (error) {
      phase =
          error is ApiFailure &&
              {400, 401, 403, 404, 409, 413, 422, 429}.contains(error.status)
          ? PublicCommentSubmissionPhase.editing
          : PublicCommentSubmissionPhase.unknown;
      rethrow;
    }
  }

  void reset({required bool acknowledgeUnknown}) {
    if (phase == PublicCommentSubmissionPhase.submitting ||
        phase == PublicCommentSubmissionPhase.unknown && !acknowledgeUnknown) {
      throw StateError('Unconfirmed comment submission retained');
    }
    phase = PublicCommentSubmissionPhase.editing;
    input = null;
    receipt = null;
  }
}
