import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/images_repository.dart';
import 'package:bookstark_flutter/features/images/images_page.dart';
import 'package:bookstark_flutter/features/images/images_feature.dart';
import '../tool/fixtures/images.dart';

class ScopedLibrary extends ImagesFixture {
  Completer<void>? listGate, removeGate;
  bool disposed = false;
  final sentIds = <int>[];
  @override
  Future<ImagesPageResult> list(ImagesQuery query) async {
    await listGate?.future;
    return super.list(query);
  }

  @override
  Future<ImageRemovalResult> remove(ManagedImage item) async {
    sentIds.add(item.id);
    await removeGate?.future;
    return super.remove(item);
  }

  @override
  void dispose() {
    disposed = true;
  }
}

ScopedLibrary library(int count) {
  final result = ScopedLibrary();
  for (var i = 0; i < count; i++) {
    result.recordPayload(
      ImageUploadPayload.fromBytes(
        name: 'scope-$i.svg',
        category: ImageCategory.note,
        bytes: Uint8List.fromList(
          utf8.encode(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"><title>$i</title></svg>',
          ),
        ),
      ),
    );
  }
  return result;
}

Future<void> tap(WidgetTester tester, String label) async {
  final target = find.text(label);
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pump();
}

void main() {
  test(
    'owner retirement drains in-flight work and rejects new operations',
    () async {
      final owner = ImageLibraryOwner(), gate = Completer<void>();
      final pending = owner.run(() => gate.future);
      final rejectedLateResult = expectLater(pending, throwsStateError);
      var drained = false;
      final drain = owner.retireAndDrain().then((_) {
        drained = true;
      });
      expect(owner.isCurrent, isFalse);
      await expectLater(owner.run(() async {}), throwsStateError);
      expect(drained, isFalse);
      gate.complete();
      await rejectedLateResult;
      await drain;
      expect(drained, isTrue);
    },
  );
  testWidgets('repo replacement during confirmation cannot send old IDs', (
    tester,
  ) async {
    final first = library(2), second = library(1);
    Future<void> show(ImagesRepository repository) => tester.pumpWidget(
      MaterialApp(home: ImagesPage(repository: repository, english: true)),
    );
    await show(first);
    await tester.pumpAndSettle();
    await tap(tester, 'Select');
    await tap(tester, 'Select loaded');
    await tap(tester, 'Delete selected 2');
    await show(second);
    await tester.pump();
    await tap(tester, 'Confirm');
    await tester.pumpAndSettle();
    expect(first.sentIds, isEmpty);
    expect(second.sentIds, isEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets('scope retirement drains first delete but stops remaining IDs', (
    tester,
  ) async {
    final first = library(2)..removeGate = Completer<void>(),
        second = library(1);
    Future<void> show(ImagesRepository repository) => tester.pumpWidget(
      MaterialApp(home: ImagesPage(repository: repository, english: true)),
    );
    await show(first);
    await tester.pumpAndSettle();
    await tap(tester, 'Select');
    await tap(tester, 'Select loaded');
    await tap(tester, 'Delete selected 2');
    await tap(tester, 'Confirm');
    expect(first.sentIds.length, 1);
    await show(second);
    await tester.pump();
    first.removeGate!.complete();
    await tester.pumpAndSettle();
    expect(first.sentIds.length, 1);
    expect(second.sentIds, isEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets('feature delays old repository disposal until its read drains', (
    tester,
  ) async {
    final first = library(1)..listGate = Completer<void>(), second = library(1);
    await tester.pumpWidget(
      MaterialApp(
        home: ImagesFeature(ownerScope: 'A', createRepository: () => first),
      ),
    );
    await tester.pump();
    await tester.pumpWidget(
      MaterialApp(
        home: ImagesFeature(ownerScope: 'B', createRepository: () => second),
      ),
    );
    await tester.pump();
    expect(first.disposed, isFalse);
    first.listGate!.complete();
    await tester.pumpAndSettle();
    expect(first.disposed, isTrue);
    expect(second.disposed, isFalse);
    expect(tester.takeException(), isNull);
  });
}
