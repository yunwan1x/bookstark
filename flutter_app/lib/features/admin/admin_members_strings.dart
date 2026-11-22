import 'admin_members_controller.dart';
import 'admin_members_models.dart';

class AdminMembersStrings {
  const AdminMembersStrings(this.english);
  final bool english;
  String t(String zh, String en) => english ? en : zh;
  String role(AdminMemberRole role) => role == AdminMemberRole.administrator
      ? t('管理员', 'Administrator')
      : t('普通用户', 'Member');
  String status(AdminMemberStatus status) => switch (status) {
    AdminMemberStatus.pending => t('待审批', 'Pending'),
    AdminMemberStatus.approved => t('已通过', 'Approved'),
    AdminMemberStatus.rejected => t('已拒绝', 'Rejected'),
  };
  String count(int count) =>
      english ? (count == 1 ? '1 member' : '$count members') : '共 $count 人';
  String page(int current, int total) =>
      t('第 $current / $total 页', 'Page $current / $total');
  String date(DateTime? value, {bool login = false}) {
    if (value == null) {
      return login ? t('尚未登录', 'Never signed in') : t('未提供', 'Not provided');
    }
    if (value.year <= 1) return t('未提供', 'Not provided');
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${local.year.toString().padLeft(4, "0")}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }

  String notice(AdminMembersNotice value) => switch (value) {
    AdminMembersNotice.loaded => t('已读取用户列表。', 'Member list loaded.'),
    AdminMembersNotice.empty => t(
      '当前页没有用户。',
      'There are no members on this page.',
    ),
    AdminMembersNotice.pageAdjusted => t(
      '列表页数已变化，已重新读取有效页。',
      'The page count changed. A valid page has been reloaded.',
    ),
    AdminMembersNotice.loadFailed => t(
      '用户列表读取失败，请重试。',
      'Could not load members. Please retry.',
    ),
    AdminMembersNotice.preflightFailed => t(
      '操作前核对未完成，请重新读取列表。',
      'The preflight check did not finish. Reload the member list.',
    ),
    AdminMembersNotice.targetChanged => t(
      '目标不在当前页或资料已变化，请重新读取后确认。',
      'The reviewed member changed or left this page. Reload before confirming.',
    ),
    AdminMembersNotice.operationRefused => t(
      '服务器拒绝了本次操作，请重新读取资料核对。',
      'The server refused this operation. Reload the member details.',
    ),
    AdminMembersNotice.protectedTarget => t(
      '服务器拒绝修改此用户角色。请返回列表重新核对。',
      'The server refused this role change. Return to the list and review the member.',
    ),
    AdminMembersNotice.ownerLost => t(
      '管理员身份或会话已变化，请返回重新连接。',
      'Administrator access or the session changed. Return and reconnect.',
    ),
    AdminMembersNotice.knownNeedsRead => t(
      '服务器已确认操作，当前资料回读未完成。重试只会读取列表。',
      'The server acknowledged the operation. Readback has not finished; retry only reloads the list.',
    ),
    AdminMembersNotice.knownRead => t(
      '操作已有成功回执，并已读取当前用户状态。',
      'The operation was acknowledged and the current member state has been read.',
    ),
    AdminMembersNotice.knownTargetMissing => t(
      '操作已有成功回执，但当前页未找到原目标，请重新核对列表。',
      'The operation was acknowledged, but the original member was not found on the current page. Review the list.',
    ),
    AdminMembersNotice.knownObservedDifferent => t(
      '操作已有成功回执，当前状态与本次选择不同，请核对。',
      'The operation was acknowledged, but the current state differs from your choice. Please review it.',
    ),
    AdminMembersNotice.knownPasswordReset => t(
      '服务器已确认重置密码，并已重新读取用户资料。列表不能用于读取密码。',
      'The server acknowledged the password reset and member details were reloaded. Passwords cannot be read from this list.',
    ),
    AdminMembersNotice.knownWriteOwnerLost => t(
      '服务器已确认操作；随后当前会话失效或权限变化，请重新连接。',
      'The server acknowledged the operation. The session or permissions then changed; reconnect.',
    ),
    AdminMembersNotice.unknown => t(
      '本次操作结果未知。不会自动重复提交，请先读取当前列表核对。',
      'The result is unknown. The request will not be replayed; read the current list first.',
    ),
    AdminMembersNotice.unknownCurrent => t(
      '以下是重新读取的当前资料，不能据此确认上次请求结果。',
      'These are freshly read member details. They cannot establish the result of the earlier request.',
    ),
    AdminMembersNotice.unknownReviewed => t(
      '已结束本次核对；上次请求结果仍未被确认，没有重新提交。',
      'This review is complete. The earlier result remains unconfirmed and the request was not replayed.',
    ),
  };
}
