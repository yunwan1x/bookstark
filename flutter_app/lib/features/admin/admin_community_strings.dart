import 'admin_community_controller.dart';
import 'admin_comment_models.dart';

class AdminCommunityStrings {
  const AdminCommunityStrings(this.english);
  final bool english;
  String t(String zh, String en) => english ? en : zh;
  String linksCount(int count) =>
      t('共 $count 条', count == 1 ? '1 link' : '$count links');
  String selectedCount(int count) =>
      t('已选 $count 条', count == 1 ? '1 selected' : '$count selected');
  String page(int page, int total) =>
      t('第 $page / $total 页', 'Page $page / $total');
  String status(AdminCommentStatus status) =>
      status == AdminCommentStatus.visible
      ? t('可见', 'Visible')
      : t('已删除', 'Deleted');
  String target(AdminCommentTarget target) => switch (target) {
    AdminCommentTarget.blog => t('博客', 'Blog'),
    AdminCommentTarget.book => t('书籍', 'Book'),
    AdminCommentTarget.document => t('文档', 'Document'),
  };
  String date(DateTime value) {
    if (value.year <= 1) {
      return t('未提供', 'Not provided');
    }
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${local.year.toString().padLeft(4, '0')}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }

  String notice(
    AdminCommunityNotice notice, {
    int? deleted,
  }) => switch (notice) {
    AdminCommunityNotice.loaded => t(
      '已读取服务器当前配置。',
      'Current server data loaded.',
    ),
    AdminCommunityNotice.empty => t('当前没有条目。', 'There are no items.'),
    AdminCommunityNotice.loadFailed => t(
      '读取失败，请重试。',
      'Could not load data. Please retry.',
    ),
    AdminCommunityNotice.invalidDraft => t(
      '草稿配置不合法，请检查名称、链接、长度及二维码分组说明。',
      'Check draft names, URLs, byte limits and QR group descriptions.',
    ),
    AdminCommunityNotice.changedBeforeWrite => t(
      '服务器资料已变化，本次没有提交。请重新读取核对。',
      'Server data changed. No write was sent. Read and review current data.',
    ),
    AdminCommunityNotice.changedCurrent => t(
      '以下为重新读取的服务器配置；采用它会放弃原本地草稿。',
      'This is freshly read server configuration. Adopting it discards the earlier local draft.',
    ),
    AdminCommunityNotice.operationRefused => t(
      '服务器拒绝了本次操作，请读取当前资料重新核对。',
      'The server refused this operation. Read current data before reviewing again.',
    ),
    AdminCommunityNotice.preflightFailed => t(
      '操作前核对未完成，没有确认提交成功。请重新读取。',
      'The preflight check did not finish. Submission was not confirmed; reload first.',
    ),
    AdminCommunityNotice.unknownWrite => t(
      '本次操作结果未知。不会自动重复提交，请先读取当前资料核对。',
      'The result is unknown. The request will not be replayed; read current data first.',
    ),
    AdminCommunityNotice.unknownCurrent => t(
      '以下为重新读取的当前资料，不能据此确认上次请求结果。',
      'These are freshly read details. They cannot establish the earlier request result.',
    ),
    AdminCommunityNotice.reviewEnded => t(
      '已结束核对；上次请求仍未被确认，没有重新提交。',
      'Review ended. The earlier result remains unconfirmed; the request was not replayed.',
    ),
    AdminCommunityNotice.staleDraftDiscarded => t(
      '已明确采用当前配置，原本地草稿已放弃。',
      'Current configuration adopted. The earlier local draft was discarded.',
    ),
    AdminCommunityNotice.knownNeedsRead => t(
      '服务器已确认操作，回读未完成。重试只会读取。',
      'The server acknowledged the operation. Readback did not finish; retry only reads data.',
    ),
    AdminCommunityNotice.knownLinksRead => t(
      '保存已有成功回执，并已读取当前配置。',
      'The save was acknowledged and current configuration was read.',
    ),
    AdminCommunityNotice.knownLinksDifferent => t(
      '保存已有成功回执，当前配置与本次草稿不同，请核对。',
      'The save was acknowledged, but current configuration differs from the draft. Please review.',
    ),
    AdminCommunityNotice.knownDeletedRead =>
      deleted == null
          ? t(
              '已收到删除回执，并已刷新列表。',
              'Deletion was acknowledged and the list was refreshed.',
            )
          : t(
              '服务器确认实际删除 $deleted 条，已刷新列表。',
              'The server reported $deleted deletions. The list was refreshed.',
            ),
    AdminCommunityNotice.knownDeleteZero => t(
      '服务器确认实际删除 0 条，已重新读取列表。',
      'The server reported 0 deletions. The list was read again.',
    ),
    AdminCommunityNotice.ownerLost => t(
      '管理员身份或会话已变化，请返回重新连接。',
      'Administrator access or the session changed. Return and reconnect.',
    ),
    AdminCommunityNotice.knownWriteOwnerLost => t(
      '服务器已确认操作；随后会话或权限变化，请重新连接。',
      'The server acknowledged the operation. Access then changed; reconnect.',
    ),
  };
}
