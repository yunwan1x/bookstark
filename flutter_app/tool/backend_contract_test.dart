// Deliberately outside test/: only the disposable ./build.py --contract runs it.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'backend_contract.dart' as contract;

void main() {
  test(
    'production repositories interoperate with isolated real Go backend',
    () async {
      final path = Platform.environment['BOOKSTARK_FIXTURE_CONFIG'];
      if (path == null) throw StateError('Run ./build.py --contract');
      await contract.main([path]);
    },
    timeout: const Timeout(Duration(seconds: 100)),
  );
}
