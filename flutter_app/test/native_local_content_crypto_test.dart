import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bookstark_flutter/core/attachments.dart';
import 'package:bookstark_flutter/core/native_local_content_crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('bookstark/local_content_crypto');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Map<String, dynamic> vector;
  setUpAll(() async {
    vector =
        ((jsonDecode(
                          await File(
                            'tool/legacy_crypto_test/go-vectors.json',
                          ).readAsString(),
                        )
                        as List)
                    .first
                as Map)
            .cast<String, dynamic>();
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  Matcher reason(LocalContentCryptoReason expected) =>
      isA<LocalContentCryptoFailure>().having(
        (e) => e.reason,
        'reason',
        expected,
      );
  Future<String> unlock(
    NativeLocalContentCrypto crypto, {
    AttachmentCancellation? cancellation,
  }) => crypto.unlock(
    password: vector['password'] as String,
    passwordHash: vector['hash'] as String,
    body: vector['body'] as String,
    cancellation: cancellation,
  );
  Map<String, Object?> reply(MethodCall call, String body) => {
    'format': 1,
    'id': (call.arguments as Map)['id'],
    'body': Uint8List.fromList(utf8.encode(body)),
  };

  test(
    'unlock returns exact BOM CRLF and binds response to random request ID',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'unlock');
        final args = call.arguments as Map;
        expect(args['id'], matches(RegExp(r'^[a-f0-9]{32}$')));
        expect(args['password'], vector['password']);
        expect(args['hash'], vector['hash']);
        expect(args['body'], utf8.encode(vector['body'] as String));
        return reply(call, vector['plain'] as String);
      });
      expect(await unlock(NativeLocalContentCrypto()), vector['plain']);
    },
  );

  test(
    'encrypt existing validates encrypted envelope without changing source',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'encryptExisting');
        expect(
          (call.arguments as Map)['body'],
          utf8.encode(vector['plain'] as String),
        );
        return reply(call, vector['body'] as String);
      });
      expect(
        await NativeLocalContentCrypto().encryptExisting(
          password: vector['password'] as String,
          passwordHash: vector['hash'] as String,
          plaintext: vector['plain'] as String,
        ),
        vector['body'],
      );
    },
  );

  test(
    'new protection requires a complete encrypted result and Go-style hash',
    () async {
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => {
          ...reply(call, vector['body'] as String),
          'hash': vector['hash'],
        },
      );
      final body = await NativeLocalContentCrypto().protectNew(
        password: vector['password'] as String,
        plaintext: vector['plain'] as String,
      );
      expect(body.passwordHash, vector['hash']);
      expect(body.body, vector['body']);
    },
  );

  test(
    'native errors are typed and never echo provider messages or secrets',
    () async {
      for (final item in [
        ('WRONG_PASSWORD', LocalContentCryptoReason.wrongPassword),
        ('BUSY', LocalContentCryptoReason.busy),
        ('CANCELLED', LocalContentCryptoReason.cancelled),
        ('UNSUPPORTED', LocalContentCryptoReason.unsupported),
        ('INVALID_CONTENT', LocalContentCryptoReason.invalidContent),
        ('unknown', LocalContentCryptoReason.unavailable),
      ]) {
        messenger.setMockMethodCallHandler(channel, (call) async {
          throw PlatformException(
            code: item.$1,
            message: 'synthetic-password-body-marker',
            details: {'key': 'synthetic'},
          );
        });
        try {
          await unlock(NativeLocalContentCrypto());
          fail('Expected failure');
        } on LocalContentCryptoFailure catch (error) {
          expect(error.reason, item.$2);
          expect(error.toString(), isNot(contains('marker')));
        }
      }
    },
  );

  test('invalid request does not start native computation', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls++;
      return null;
    });
    for (final password in ['', '\uD800', 'x' * 4097]) {
      await expectLater(
        NativeLocalContentCrypto().unlock(
          password: password,
          passwordHash: vector['hash'] as String,
          body: vector['body'] as String,
        ),
        throwsA(reason(LocalContentCryptoReason.unsupported)),
      );
    }
    await expectLater(
      NativeLocalContentCrypto().protectNew(
        password: 'x' * 73,
        plaintext: 'body',
      ),
      throwsA(reason(LocalContentCryptoReason.unsupported)),
    );
    await expectLater(
      NativeLocalContentCrypto().encryptExisting(
        password: 'pw',
        passwordHash: vector['hash'] as String,
        plaintext: '\uD800',
      ),
      throwsA(reason(LocalContentCryptoReason.unsupported)),
    );
    expect(calls, 0);
  });

  test('malformed or foreign replies cannot be adopted', () async {
    final mutations = <Object? Function(MethodCall)>[
      (call) => null,
      (call) => 'plaintext',
      (call) => {...reply(call, 'body'), 'format': 1.0},
      (call) => {...reply(call, 'body'), 'id': 'f' * 32},
      (call) => {...reply(call, 'body'), 'password': 'synthetic'},
      (call) => {...reply(call, 'body')}..remove('body'),
      (call) => {...reply(call, 'body'), 'body': 7},
      (call) => {
        ...reply(call, 'body'),
        'body': Uint8List.fromList([0xff]),
      },
    ];
    for (final mutation in mutations) {
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => mutation(call),
      );
      await expectLater(
        unlock(NativeLocalContentCrypto()),
        throwsA(reason(LocalContentCryptoReason.invalidContent)),
      );
    }
  });

  test('new protection never accepts plaintext or a missing hash', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => {...reply(call, 'plaintext'), 'hash': vector['hash']},
    );
    await expectLater(
      NativeLocalContentCrypto().protectNew(password: 'pw', plaintext: 'body'),
      throwsA(reason(LocalContentCryptoReason.invalidContent)),
    );
  });

  test('pre-cancelled owner never invokes native', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls++;
      return null;
    });
    final cancellation = AttachmentCancellation()..cancel();
    await expectLater(
      unlock(NativeLocalContentCrypto(), cancellation: cancellation),
      throwsA(reason(LocalContentCryptoReason.cancelled)),
    );
    expect(calls, 0);
  });

  test(
    'cancel retires once and a late plaintext reply is never adopted',
    () async {
      final cancellation = AttachmentCancellation();
      final entered = Completer<void>();
      final pending = Completer<Object?>();
      MethodCall? request;
      var cancels = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'cancel') {
          cancels++;
          expect(
            (call.arguments as Map)['id'],
            (request!.arguments as Map)['id'],
          );
          return null;
        }
        request = call;
        entered.complete();
        return pending.future;
      });
      final future = unlock(
        NativeLocalContentCrypto(),
        cancellation: cancellation,
      );
      final rejected = expectLater(
        future,
        throwsA(reason(LocalContentCryptoReason.cancelled)),
      );
      await entered.future;
      cancellation.cancel();
      await rejected;
      pending.complete(reply(request!, 'late synthetic plaintext'));
      await Future<void>.delayed(Duration.zero);
      expect(cancels, 1);
    },
  );

  test(
    'timeout cancels once and does not retry or adopt a late result',
    () async {
      final pending = Completer<Object?>();
      MethodCall? request;
      var calls = 0, cancels = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'cancel') {
          cancels++;
          return null;
        }
        calls++;
        request = call;
        return pending.future;
      });
      await expectLater(
        unlock(
          NativeLocalContentCrypto(deadline: const Duration(milliseconds: 20)),
        ),
        throwsA(reason(LocalContentCryptoReason.unavailable)),
      );
      pending.complete(reply(request!, 'late plaintext'));
      await Future<void>.delayed(Duration.zero);
      expect(calls, 1);
      expect(cancels, 1);
    },
  );

  test(
    'completed request disconnects a long-lived cancellation owner',
    () async {
      final cancellation = AttachmentCancellation();
      var cancels = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'cancel') {
          cancels++;
          return null;
        }
        return reply(call, 'exact');
      });
      expect(
        await unlock(NativeLocalContentCrypto(), cancellation: cancellation),
        'exact',
      );
      await Future<void>.delayed(Duration.zero);
      cancellation.cancel();
      await Future<void>.delayed(Duration.zero);
      expect(cancels, 0);
    },
  );
}
