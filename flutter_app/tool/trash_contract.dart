import 'dart:io';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/notes_repository.dart';
import 'package:bookstark_flutter/core/trash_repository.dart';
import 'package:bookstark_flutter/core/trash_controller.dart';
import 'credentials_contract.dart' show LostCredentialReceipt;

void check(bool value, String reason) {
  if (!value) {
    throw StateError(reason);
  }
}

Future<void> runTrashContract(BookstarkClient client, int memberId) async {
  final notes = RemoteNotesRepository(client),
      repo = RemoteTrashRepository(client, memberId: memberId);
  final prefix = 'trash-contract-${DateTime.now().microsecondsSinceEpoch}';
  final ids = <int>[];
  for (var i = 0; i < 21; i++) {
    final id = await notes.save(
      Note(title: '$prefix-$i', content: '# actual trash restore\n原始内容 $i'),
    );
    ids.add(id);
    await notes.remove(id);
  }
  final first = await repo.read(type: 'blog');
  check(
    first.total >= 21 && first.entries.length == 20,
    'Actual trash pagination returns twenty with real total',
  );
  final all = <TrashEntry>[...first.entries];
  for (var p = 2; p <= first.pages; p++) {
    all.addAll((await repo.read(type: 'blog', page: p)).entries);
  }
  final own = all.where((v) => v.name.startsWith(prefix)).toList();
  check(
    own.length == 21 && own.every((v) => v.memberId == memberId),
    'Actual owned trash entries and complete pagination',
  );
  final restore = own.singleWhere((v) => v.name == '$prefix-0');
  await repo.apply(restore, TrashOperation.restore);
  check(
    await repo.isAbsent(restore),
    'Actual restored trash record disappears',
  );
  final restored = await notes.read(ids.first);
  check(
    restored.id == ids.first &&
        restored.title == '$prefix-0' &&
        restored.content == '# actual trash restore\n原始内容 0',
    'Actual restored note retains ID and full Markdown',
  );
  final lostEntry = own.singleWhere((v) => v.name == '$prefix-1');
  final lost = LostCredentialReceipt(
    '${client.baseUri.path}/api/trash/${lostEntry.id}/restore',
  );
  final interrupted = BookstarkClient(
    client.baseUri.toString(),
    transport: lost,
  )..restoreSession(client.exportSession());
  final interruptedRepo = RemoteTrashRepository(
    interrupted,
    memberId: memberId,
  );
  final controller = TrashController(interruptedRepo);
  await controller.load(filter: 'blog');
  // Explicitly select the actual observed page containing the target.
  if (!controller.data!.entries.any((v) => v.id == lostEntry.id)) {
    await controller.load(page: 2);
  }
  await controller.apply([lostEntry], TrashOperation.restore);
  check(
    controller.results[lostEntry.id]?.phase == TrashItemPhase.unknown &&
        lost.writes == 1,
    'Actual applied restore with discarded receipt stays unknown and is not repeated',
  );
  await controller.verify();
  check(
    controller.results[lostEntry.id]?.phase ==
            TrashItemPhase.absentWithoutReceipt &&
        lost.writes == 1,
    'Explicit readonly scan verifies absence without repeating restore',
  );
  check(
    (await notes.read(ids[1])).content == '# actual trash restore\n原始内容 1',
    'Lost receipt still restored actual source content',
  );
  controller.dispose();
  interrupted.close();
  for (final entry in own.where(
    (v) => v.id != restore.id && v.id != lostEntry.id,
  )) {
    await repo.apply(entry, TrashOperation.delete);
    check(
      await repo.isAbsent(entry),
      'Actual permanent deletion removes observed trash record',
    );
  }
  for (final id in ids.take(2)) {
    await notes.remove(id);
  }
  final leftovers = (await repo.read(
    type: 'blog',
  )).entries.where((v) => v.name.startsWith(prefix)).toList();
  for (final entry in leftovers) {
    await repo.apply(entry, TrashOperation.delete);
  }
  check(
    !(await repo.read(
      type: 'blog',
    )).entries.any((v) => v.name.startsWith(prefix)),
    'Disposable trash fixture records cleaned',
  );
  repo.dispose();
  stdout.writeln(
    'PASS actual Go trash: owner-scoped 21-item pagination, exact restore receipt plus original ID and full Markdown, actual applied lost receipt without resend, readonly absence verification, permanent deletion and cleanup; disposable fixture only',
  );
}
