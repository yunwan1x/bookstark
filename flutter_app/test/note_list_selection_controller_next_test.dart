import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/note_list_selection_controller.dart';

void main() {
  test(
    'only explicitly loaded IDs are selected and offscreen count does not authorize other pages',
    () {
      final controller = NoteListSelectionController(scope: 'owner1');
      controller.selectLoaded([1, 2, 2]);
      expect(controller.selectedIds, {1, 2});
      expect(controller.offscreenCount([3, 4]), 2);
      expect(controller.offscreenCount([2, 3]), 1);
      expect(() => controller.selectedIds.add(999), throwsUnsupportedError);
    },
  );
  test(
    'frozen IDs and same-selection versions preserve failure and new selections',
    () {
      final controller = NoteListSelectionController(scope: 'owner1')
        ..selectLoaded([1, 3]);
      final snapshot = controller.capture();
      controller.setSelected(2, true);
      controller.reconcile(snapshot, verifiedIds: [1]);
      expect(controller.selectedIds, {2, 3});
      expect(snapshot.ids, {1, 3});
      expect(
        () => controller.reconcile(snapshot, verifiedIds: [99]),
        throwsFormatException,
      );
      expect(controller.selectedIds, {2, 3});
    },
  );
  test('old completion cannot remove a deselected and newly reselected ID', () {
    final controller = NoteListSelectionController(scope: 'owner1')
      ..setSelected(7, true);
    final snapshot = controller.capture();
    controller.setSelected(7, false);
    controller.setSelected(7, true);
    controller.reconcile(snapshot, verifiedIds: [7]);
    expect(controller.selectedIds, {7});
  });
  test(
    'query change cancellation preserves selection and confirmed change invalidates stale results',
    () {
      final controller = NoteListSelectionController(scope: 'owner1')
        ..selectLoaded([1, 2]);
      final old = controller.capture();
      expect(controller.clearForQueryChange(confirmed: false), false);
      expect(controller.selectedIds, {1, 2});
      expect(controller.clearForQueryChange(confirmed: true), true);
      controller.setSelected(3, true);
      expect(
        () => controller.reconcile(old, verifiedIds: [1]),
        throwsA(isA<NoteSelectionRetired>()),
      );
      expect(controller.selectedIds, {3});
    },
  );
  test(
    'another controller same textual scope cannot apply a foreign completion',
    () {
      final original = NoteListSelectionController(scope: 'owner1')
        ..setSelected(1, true);
      final replacement = NoteListSelectionController(scope: 'owner1')
        ..setSelected(1, true);
      expect(
        () => replacement.reconcile(original.capture(), verifiedIds: [1]),
        throwsA(isA<NoteSelectionRetired>()),
      );
      expect(replacement.selectedIds, {1});
    },
  );
  test('retired owner clears IDs and rejects late completion or additions', () {
    var current = true;
    final controller = NoteListSelectionController(
      scope: 'owner1',
      isCurrent: () => current,
    )..selectLoaded([1, 2]);
    final snapshot = controller.capture();
    current = false;
    controller.retire();
    expect(controller.selectedIds, isEmpty);
    expect(
      () => controller.reconcile(snapshot, verifiedIds: [1]),
      throwsA(isA<NoteSelectionRetired>()),
    );
    expect(
      () => controller.setSelected(3, true),
      throwsA(isA<NoteSelectionRetired>()),
    );
    expect(() => controller.capture(), throwsA(isA<NoteSelectionRetired>()));
  });
}
