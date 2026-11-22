import 'dart:async';

import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/label_management_repository.dart';
import 'package:bookstark_flutter/features/admin/admin_recommendations_controller.dart';
import 'package:bookstark_flutter/features/admin/admin_recommendations_page.dart';
import 'package:bookstark_flutter/features/admin/admin_settings_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const owner = AdminPrincipal(memberId: 1, account: 'fixture', role: 0);

class RecommendationRepository extends AdminSettingsRepository {
  RecommendationRepository()
    : super(BookstarkClient('https://example.invalid'));
  LabelRecommendationSettings value = const LabelRecommendationSettings(
    strategy: LabelRecommendationStrategy.manual,
    manualLabels: ['技术'],
    pageSize: 10,
  );
  int puts = 0;
  Map<String, Object?>? body;
  Object? saveError;
  bool failRead = false;
  @override
  Future<AdminSettingsSnapshot> read(
    AdminPrincipal owner, {
    Future<void>? abortTrigger,
  }) async {
    if (failRead) throw const FormatException('fixture');
    return AdminSettingsSnapshot.parse(<Object?>[]);
  }

  @override
  Future<LabelRecommendationSettings> readRecommendations(
    AdminPrincipal owner, {
    Future<void>? abortTrigger,
  }) async => value;
  @override
  Future<void> saveRecommendations(
    AdminPrincipal owner,
    LabelRecommendationSettings value, {
    Future<void>? abortTrigger,
  }) async {
    puts++;
    body = value.writeBody();
    if (saveError != null) throw saveError!;
    this.value = LabelRecommendationSettings.fromJson(body!);
  }
}

void main() {
  test(
    'recommendation save sends full reviewed config and adopts normalized response',
    () async {
      final repo = RecommendationRepository();
      final c = AdminRecommendationsController(repo, owner);
      await c.load();
      c.edit('tag_recommend_manual_labels', ' 技术 \n阅读\n技术\n');
      await c.save();
      expect(repo.body, {
        'strategy': 'manual',
        'manual_labels': ['技术', '阅读'],
        'page_size': 10,
      });
      expect(c.draft['tag_recommend_manual_labels'], '技术\n阅读');
      expect(c.dirty, isFalse);
      c.dispose();
    },
  );
  test(
    'recommendation form blocks out-of-range and lossy comma names',
    () async {
      final repo = RecommendationRepository();
      final c = AdminRecommendationsController(repo, owner);
      await c.load();
      c.edit('tag_recommend_page_size', '51');
      await c.save();
      expect(repo.puts, 0);
      c.edit('tag_recommend_page_size', '10');
      c.edit('tag_recommend_manual_labels', 'a,b');
      await c.save();
      expect(repo.puts, 0);
      c.dispose();
    },
  );
  test('unknown recommendation save never auto replays', () async {
    final repo = RecommendationRepository()
      ..saveError = TimeoutException('fixture');
    final c = AdminRecommendationsController(repo, owner);
    await c.load();
    c.edit('tag_recommend_page_size', '20');
    await c.save();
    expect(c.phase, AdminRecommendationsPhase.unknown);
    await c.save();
    await c.readCurrent();
    expect(repo.puts, 1);
    expect(c.phase, AdminRecommendationsPhase.reviewingCurrent);
    c.dispose();
  });
  test('known recommendation receipt read failure retries only GET', () async {
    final repo = RecommendationRepository();
    final c = AdminRecommendationsController(repo, owner);
    await c.load();
    c.edit('tag_recommend_page_size', '20');
    repo.failRead = true;
    await c.save();
    expect(c.phase, AdminRecommendationsPhase.committedNeedsRead);
    repo.failRead = false;
    await c.readCurrent();
    expect(repo.puts, 1);
    expect(c.phase, AdminRecommendationsPhase.saved);
    c.dispose();
  });
  testWidgets('recommendations 320dp200% keeps manual input reachable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = AdminRecommendationsController(RecommendationRepository(), owner);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: AdminRecommendationsPage(controller: c, onReturn: () {}),
      ),
    );
    await tester.pumpAndSettle();
    final manual = find.byKey(const ValueKey('tag_recommend_manual_labels'));
    await tester.scrollUntilVisible(
      manual,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(manual, findsOneWidget);
    expect(find.text('保存推荐设置'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
