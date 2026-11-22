import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/features/admin/admin_files_lease.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('bookstark/admin_file_editor/741');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  test(
    'Retiring before creation prevents a late native view from being created',
    () async {
      final lease = AdminFileEditorLease();
      var creates = 0;
      await lease.retire();
      await lease.create(741, () async {
        creates++;
      });
      expect(creates, 0);
      expect(lease.retired, true);
    },
  );
  test(
    'Native creation and destruction acknowledgements precede window release',
    () async {
      final creation = Completer<void>(), destroyed = Completer<void>();
      final lease = AdminFileEditorLease();
      var retireCalls = 0, windowReleased = false;
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'retire');
        retireCalls++;
        await destroyed.future;
        return null;
      });
      final creating = lease.create(741, () => creation.future);
      final close = lease.retire().then((_) {
        windowReleased = true;
      });
      await Future<void>.delayed(Duration.zero);
      expect(lease.closed, true);
      expect(retireCalls, 0);
      expect(windowReleased, false);
      creation.complete();
      await creating;
      await Future<void>.delayed(Duration.zero);
      expect(retireCalls, 1);
      expect(windowReleased, false);
      destroyed.complete();
      await close;
      expect(windowReleased, true);
      expect(lease.retired, true);
    },
  );
  test('Repeated retirement sends only one native destroy command', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls++;
      return null;
    });
    final lease = AdminFileEditorLease();
    await lease.create(741, () async {});
    final first = lease.retire(), second = lease.retire();
    expect(identical(first, second), true);
    await Future.wait([first, second]);
    expect(calls, 1);
  });
  test(
    'Unconfirmed native destruction cannot be treated as successful retirement',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'owned-retire-failure');
      });
      final lease = AdminFileEditorLease();
      await lease.create(741, () async {});
      await expectLater(lease.retire(), throwsA(isA<PlatformException>()));
      expect(lease.closed, true);
      expect(lease.retired, false);
    },
  );
}
