import 'dart:async';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/strings.dart';
import 'package:bookstark_flutter/features/auth/auth_feedback.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final english in [false, true]) {
    final strings = AppStrings(english: english);
    test('known login rejection is not a transport failure ($english)', () {
      final feedback = authFailureFeedback(
        const ApiFailure(401, '账号或密码错误'),
        AuthOperation.login,
        strings,
      );
      expect(feedback.title, strings.text('authLoginRejectedTitle'));
      expect(feedback.message, strings.text('authBadCredentials'));
      expect(feedback.verificationFirst, false);
      expect(feedback.kind, AuthFeedbackKind.error);
    });
    test('approval differs from wrong credentials ($english)', () {
      final feedback = authFailureFeedback(
        const ApiFailure(403, '账号未通过审批'),
        AuthOperation.login,
        strings,
      );
      expect(feedback.message, strings.text('authApprovalRequired'));
    });
    for (final operation in [AuthOperation.forgot, AuthOperation.reset]) {
      test(
        'mail unavailable is not a connection failure ($operation/$english)',
        () {
          final feedback = authFailureFeedback(
            const ApiFailure(503, '找回密码服务暂不可用，请联系管理员'),
            operation,
            strings,
            mutationStarted: true,
          );
          expect(feedback.title, strings.text('authMailUnavailableTitle'));
          expect(feedback.kind, AuthFeedbackKind.warning);
          expect(feedback.verificationFirst, false);
        },
      );
    }
    test(
      'reset rejection uses actual invalid-or-expired meaning ($english)',
      () {
        final feedback = authFailureFeedback(
          const ApiFailure(400, '重置链接无效或已过期'),
          AuthOperation.reset,
          strings,
          mutationStarted: true,
        );
        expect(feedback.title, strings.text('authResetInvalidTitle'));
        expect(feedback.verificationFirst, false);
      },
    );
  }
  const strings = AppStrings(english: true);
  test('untrusted API and exception messages never enter feedback', () {
    const secret =
        'private-password /data/private/auth.json https://user:secret@example.invalid/?token=secret';
    for (final operation in AuthOperation.values) {
      for (final error in [const ApiFailure(400, secret), StateError(secret)]) {
        final feedback = authFailureFeedback(error, operation, strings);
        expect(feedback.title + feedback.message, isNot(contains('secret')));
        expect(feedback.title + feedback.message, isNot(contains('/data/')));
      }
    }
  });
  test('rate limiting does not invent a countdown', () {
    final feedback = authFailureFeedback(
      const ApiFailure(429, 'server-defined delay'),
      AuthOperation.forgot,
      strings,
      mutationStarted: true,
    );
    expect(feedback.title, strings.text('authRateTitle'));
    expect(feedback.message, strings.text('authRateBody'));
  });
  for (final operation in [AuthOperation.register, AuthOperation.reset]) {
    for (final error in [
      TimeoutException('private'),
      const ApiFailure(200, '服务器没有返回有效的 JSON 响应'),
      const ApiFailure(500, 'internal'),
    ]) {
      test(
        'submitted $operation needs checking without a rejection (${error.runtimeType}/${error is ApiFailure ? error.status : 0})',
        () {
          final feedback = authFailureFeedback(
            error,
            operation,
            strings,
            mutationStarted: true,
          );
          expect(feedback.verificationFirst, true);
          expect(feedback.kind, AuthFeedbackKind.warning);
          expect(feedback.title, strings.text('authUnconfirmedTitle'));
        },
      );
    }
  }
  test('preparation timeout does not pretend form was submitted', () {
    final feedback = authFailureFeedback(
      TimeoutException('private'),
      AuthOperation.register,
      strings,
    );
    expect(feedback.verificationFirst, false);
    expect(feedback.title, strings.text('authConnectionFailedTitle'));
  });
  test(
    'mail transport loss directs inbox checking without claiming delivery',
    () {
      final feedback = authFailureFeedback(
        TimeoutException('private'),
        AuthOperation.forgot,
        strings,
        mutationStarted: true,
      );
      expect(feedback.title, strings.text('authMailUnconfirmedTitle'));
      expect(feedback.verificationFirst, false);
    },
  );
  for (final row in [
    (
      '注册成功，请等待管理员审批',
      'authRegistrationPendingTitle',
      'authRegistrationPendingBody',
    ),
    (
      '注册成功，请登录',
      'authRegistrationApprovedTitle',
      'authRegistrationApprovedBody',
    ),
    (
      'untrusted private text',
      'authRegistrationSubmittedTitle',
      'registerSuccess',
    ),
  ]) {
    test('registration authoritative outcome: ${row.$2}', () {
      final feedback = authRegistrationFeedback({'message': row.$1}, strings);
      expect(feedback.title, strings.text(row.$2));
      expect(feedback.message, strings.text(row.$3));
      expect(feedback.kind, AuthFeedbackKind.success);
    });
  }
  test('oversized input is actionable and not an unknown commit', () {
    final feedback = authFailureFeedback(
      const FormatException('Authentication request exceeds limit'),
      AuthOperation.reset,
      strings,
    );
    expect(feedback.message, strings.text('authInputTooLong'));
    expect(feedback.verificationFirst, false);
  });
}
