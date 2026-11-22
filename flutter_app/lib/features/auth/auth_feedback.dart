import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/app_theme.dart';
import '../../core/strings.dart';

enum AuthOperation { login, register, forgot, reset }

enum AuthFeedbackKind { error, warning, success }

class AuthFeedback {
  const AuthFeedback({
    required this.kind,
    required this.title,
    required this.message,
    this.verificationFirst = false,
  });
  final AuthFeedbackKind kind;
  final String title, message;
  final bool verificationFirst;
}

AuthFeedback authFailureFeedback(
  Object error,
  AuthOperation operation,
  AppStrings strings, {
  bool mutationStarted = false,
}) {
  String t(String key) => strings.text(key);
  AuthFeedback feedback(
    String title,
    String message, {
    bool warning = false,
    bool verify = false,
  }) => AuthFeedback(
    kind: warning ? AuthFeedbackKind.warning : AuthFeedbackKind.error,
    title: t(title),
    message: t(message),
    verificationFirst: verify,
  );
  if (error is FormatException &&
      error.message == 'Authentication request exceeds limit') {
    return feedback('authRequestRejectedTitle', 'authInputTooLong');
  }
  if (error is ApiFailure) {
    if (error.status == 429) {
      return feedback('authRateTitle', 'authRateBody', warning: true);
    }
    final message = error.message;
    if (operation == AuthOperation.login) {
      if (message == '账号或密码错误') {
        return feedback('authLoginRejectedTitle', 'authBadCredentials');
      }
      if (message == '账号未通过审批') {
        return feedback('authLoginRejectedTitle', 'authApprovalRequired');
      }
    }
    if ((operation == AuthOperation.forgot ||
            operation == AuthOperation.reset) &&
        message == '找回密码服务暂不可用，请联系管理员') {
      return feedback(
        'authMailUnavailableTitle',
        'authMailUnavailableBody',
        warning: true,
      );
    }
    if (operation == AuthOperation.reset && message == '重置链接无效或已过期') {
      return feedback('authResetInvalidTitle', 'authResetInvalidBody');
    }
    if (operation == AuthOperation.register) {
      if (message == '注册失败，账号或邮箱可能已存在') {
        return feedback(
          'authRegistrationRejected',
          'authDuplicateRegistration',
        );
      }
      if (message == '邀请码错误' || message == '请输入邀请码') {
        return feedback('authRegistrationRejected', 'authInviteRejected');
      }
    }
    if (message == '密码长度不能超过72位' || message == '密码长度不能超过72个字符') {
      return feedback('authRequestRejectedTitle', 'passwordLong');
    }
    if (mutationStarted &&
        (operation == AuthOperation.register ||
            operation == AuthOperation.reset) &&
        !{400, 401, 403, 404, 405, 409, 413, 422, 429}.contains(error.status)) {
      return feedback(
        'authUnconfirmedTitle',
        operation == AuthOperation.register
            ? 'authRegistrationUnconfirmed'
            : 'authResetUnconfirmed',
        warning: true,
        verify: true,
      );
    }
    if (error.status >= 500) {
      return feedback(
        'authServiceUnavailableTitle',
        'authServiceUnavailableBody',
        warning: true,
      );
    }
    return feedback(
      operation == AuthOperation.login
          ? 'authLoginRejectedTitle'
          : 'authRequestRejectedTitle',
      'authRequestRejectedBody',
    );
  }
  if (mutationStarted &&
      (operation == AuthOperation.register ||
          operation == AuthOperation.reset)) {
    return feedback(
      'authUnconfirmedTitle',
      operation == AuthOperation.register
          ? 'authRegistrationUnconfirmed'
          : 'authResetUnconfirmed',
      warning: true,
      verify: true,
    );
  }
  if (mutationStarted && operation == AuthOperation.forgot) {
    return feedback(
      'authMailUnconfirmedTitle',
      'authMailUnconfirmedBody',
      warning: true,
    );
  }
  return feedback('authConnectionFailedTitle', 'connectionFailed');
}

AuthFeedback authRegistrationFeedback(
  Map<String, dynamic> result,
  AppStrings strings,
) {
  final message = result['message'];
  final pending = message == '注册成功，请等待管理员审批';
  final approved = message == '注册成功，请登录';
  return AuthFeedback(
    kind: AuthFeedbackKind.success,
    title: strings.text(
      pending
          ? 'authRegistrationPendingTitle'
          : approved
          ? 'authRegistrationApprovedTitle'
          : 'authRegistrationSubmittedTitle',
    ),
    message: strings.text(
      pending
          ? 'authRegistrationPendingBody'
          : approved
          ? 'authRegistrationApprovedBody'
          : 'registerSuccess',
    ),
  );
}

class AuthFeedbackCard extends StatelessWidget {
  const AuthFeedbackCard({super.key, required this.feedback});
  final AuthFeedback feedback;
  @override
  Widget build(BuildContext context) {
    final (background, border, ink, icon) = switch (feedback.kind) {
      AuthFeedbackKind.error => (
        const Color(0xfffef2f2),
        const Color(0xfffecaca),
        const Color(0xffb91c1c),
        Icons.error_outline,
      ),
      AuthFeedbackKind.warning => (
        const Color(0xfffffbeb),
        const Color(0xfffde68a),
        const Color(0xff92400e),
        Icons.warning_amber_outlined,
      ),
      AuthFeedbackKind.success => (
        AppColors.primarySurface,
        const Color(0xffbfdbfe),
        AppColors.primary,
        Icons.check_circle_outline,
      ),
    };
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: background,
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(child: Icon(icon, size: 24, color: ink)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    feedback.title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    feedback.message,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      color: AppColors.text,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
