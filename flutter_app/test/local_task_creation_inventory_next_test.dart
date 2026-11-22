import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/local_recovery_inventory.dart';
import 'local_recovery_inventory_test.dart' show inventory, prefs, complex;

void main() {
  test(
    'ordinary local and remote task creation keys both block with no value reads',
    () async {
      final summary = await inventory(
        prefs(
          keys: [
            'bookstark.local-task-create.v1.aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
            'bookstark.local-task-create-slot.v1.aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            'bookstark.task-create.v1.aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
            'bookstark.task-create-slot.v1.aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          ],
        ),
        complex(),
        namespaces: {'local-generation:cccccccccccccccccccccccccccccccc'},
      ).read();
      expect(summary.references.map((r) => r.kind), [
        'local-task-create',
        'local-task-create-slot',
        'task-create',
        'task-create-slot',
      ]);
      expect(summary.requireClear, throwsA(isA<PendingLocalRecovery>()));
    },
  );
  test(
    'local task malformed and wrong-store keys remain blocking unknown',
    () async {
      final summary = await inventory(
        prefs(
          keys: [
            'bookstark.local-task-create.v1.bad',
            'bookstark.local-task-create-slot.v1.bad',
          ],
          html: [
            'bookstark.local-task-create-slot.v1.aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          ],
        ),
        complex(),
        namespaces: {'local'},
      ).read();
      expect(summary.references, isEmpty);
      expect(summary.unknown, 3);
      expect(summary.requireClear, throwsA(isA<PendingLocalRecovery>()));
    },
  );
}
