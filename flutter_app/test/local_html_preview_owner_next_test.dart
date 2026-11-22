import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/local_html_preview_owner.dart';

void main() {
  test('replacement waits real close ACK; late release cannot retire successor',
      () async {
    final owner = LocalHtmlPreviewOwner(isCurrentScope: () => true);
    final first = await owner.nextPreview();
    final ack = Completer<void>();
    var closes = 0;
    first.bind(Object(), () { closes++; return ack.future; });
    var opened = false;
    final replacement = owner.nextPreview().then((body) {
      opened = true;
      return body;
    });
    await Future<void>.delayed(Duration.zero);
    expect(first.retired, isTrue);
    expect(opened, isFalse);
    expect(closes, 1);
    ack.complete();
    final second = await replacement;
    expect(identical(first, second), isFalse);
    expect(second.retired, isFalse);
    await owner.release(first);
    expect(second.retired, isFalse);
    await owner.retireAndDrain();
    expect(second.retired, isTrue);
  });

  test('retirement invalidates synchronously and joins actual held resource IO',
      () async {
    var current = true;
    final owner = LocalHtmlPreviewOwner(isCurrentScope: () => current);
    final body = await owner.nextPreview();
    final io = Completer<int>();
    final read = owner.use(() => io.future);
    var drained = false;
    final retirement = owner.retireAndDrain().then((_) { drained = true; });
    expect(owner.current, isFalse);
    final denied = expectLater(owner.nextPreview(), throwsStateError);
    await Future<void>.delayed(Duration.zero);
    expect(body.retired, isTrue);
    expect(drained, isFalse);
    current = false;
    io.complete(7);
    expect(await read, 7);
    await retirement;
    await denied;
    expect(drained, isTrue);
    expect(() => owner.use(() async => 8), throwsStateError);
  });

  test('failed native close remains blocking and can retry without new body',
      () async {
    final owner = LocalHtmlPreviewOwner(isCurrentScope: () => true);
    final first = await owner.nextPreview();
    var attempts = 0;
    first.bind(Object(), () async {
      attempts++;
      if (attempts == 1) throw StateError('held native close failed');
    });
    await expectLater(owner.nextPreview(), throwsStateError);
    expect(first.retired, isTrue);
    expect(attempts, 1);
    // The same irreversible old body must acknowledge close before replacement.
    final next = await owner.nextPreview();
    expect(attempts, 2);
    expect(identical(next, first), isFalse);
    await owner.retireAndDrain();
  });

  test('owner loss during close ACK never activates a replacement', () async {
    var current = true;
    final owner = LocalHtmlPreviewOwner(isCurrentScope: () => current);
    final first = await owner.nextPreview();
    final ack = Completer<void>();
    first.bind(Object(), () => ack.future);
    final next = owner.nextPreview();
    await Future<void>.delayed(Duration.zero);
    current = false;
    ack.complete();
    await expectLater(next, throwsStateError);
    await owner.retireAndDrain();
  });
}
