import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/local_recovery_inventory.dart';
import 'local_recovery_inventory_test.dart' show prefs, complex, inventory;

void main() {
  test('all-owner task journal and slot block backup through keys only', () async {
    final result = await inventory(
      prefs(
        keys: [
          'bookstark.task-create.v1.aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
          'bookstark.task-create-slot.v1.aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        ],
      ),
      complex(),
      namespaces: {'local-generation:cccccccccccccccccccccccccccccccc'},
    ).read();
    expect(result.references.map((r) => r.kind), [
      'task-create',
      'task-create-slot',
    ]);
    expect(result.needsAttention, true);
    expect(result.requireClear, throwsA(isA<PendingLocalRecovery>()));
  });
  test(
    'malformed task key and wrong native storage are blocking unknown',
    () async {
      final result = await inventory(
        prefs(
          keys: ['bookstark.task-create.v1.bad'],
          html: [
            'bookstark.task-create-slot.v1.aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          ],
        ),
        complex(),
        namespaces: {'local-generation:cccccccccccccccccccccccccccccccc'},
      ).read();
      expect(result.references, isEmpty);
      expect(result.needsAttention, true);
    },
  );
}
