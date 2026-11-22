import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/public_share_models.dart';
import 'package:bookstark_flutter/core/public_share_attachments.dart';
import 'package:bookstark_flutter/core/public_shares_repository.dart';
import 'package:bookstark_flutter/features/public_shares/share_book_page.dart';
import 'package:bookstark_flutter/features/public_shares/share_chapter_page.dart';

final ref = PublicShareReference(Uri.parse('https://example.test'), 'book');
PublicShareDetail book({bool empty = false}) =>
    PublicShareDetail.fromJson(ref, {
      'share_type': 'book',
      'share_id': 7,
      'target_id': 3,
      'share_identify': 'book',
      'has_password': false,
      'title': 'Actual shared book',
      'doc_tree': empty
          ? []
          : [
              {
                'document_id': 10,
                'parent_id': 0,
                'identify': 'parent',
                'document_name': 'Parent chapter',
                'doc_type': 'markdown',
                'children': [
                  {
                    'document_id': 12,
                    'parent_id': 10,
                    'identify': 'child',
                    'document_name': 'Child chapter',
                    'doc_type': 'markdown',
                    'children': [],
                  },
                ],
              },
            ],
    });

class Repository implements PublicSharesRepository {
  bool revoked = false, empty = false;
  final calls = <String>[];
  Completer<PublicShareChapter>? pending;
  @override
  Future<PublicShareDetail> load(
    PublicShareReference ref, {
    Future<void>? abortTrigger,
  }) async {
    if (revoked) throw StateError('revoked');
    return book(empty: empty);
  }

  @override
  Future<PublicShareChapter> chapter(
    PublicShareDetail value,
    String identify, {
    Future<void>? abortTrigger,
  }) async {
    calls.add(identify);
    if (identify == 'parent' && pending != null) return pending!.future;
    final node = flattenPublicChapters(
      value.nodes,
    ).singleWhere((node) => node.identify == identify);
    return PublicShareChapter(
      node: node,
      title: node.name,
      content: '# Body of $identify',
      format: 'markdown',
      rawAvailable: false,
    );
  }

  @override
  Future<PublicShareDetail> unlock(
    PublicShareDetail detail,
    String password, {
    Future<void>? abortTrigger,
  }) async => throw UnimplementedError();
}

void main() {
  late PublicShareAttachments attachments;
  setUp(
    () => attachments = PublicShareAttachments(
      ref.server,
      publicTransport: MockClient((_) async => http.Response('', 404)),
    ),
  );
  tearDown(() => attachments.close());
  testWidgets(
    'parent document remains readable and child expansion preserves actual node ID',
    (tester) async {
      final opened = <int>[];
      final repo = Repository();
      await tester.pumpWidget(
        MaterialApp(
          home: ShareBookPage(
            reference: ref,
            repository: repo,
            english: true,
            onOpen: (value, node) async {
              opened.add(node.id);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('2 chapters loaded'), findsOneWidget);
      await tester.tap(find.text('Parent chapter'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Child chapter'));
      await tester.pumpAndSettle();
      expect(opened, [10, 12]);
      await tester.tap(find.byTooltip('Collapse'));
      await tester.pumpAndSettle();
      expect(find.text('Child chapter'), findsNothing);
      expect(find.text('Parent chapter'), findsOneWidget);
      repo.revoked = true;
      await tester.tap(find.byTooltip('Reload'));
      await tester.pumpAndSettle();
      expect(find.text('Parent chapter'), findsNothing);
      expect(find.text('Retry'), findsOneWidget);
    },
  );
  testWidgets(
    'chapter switches through real loaded order and clears body when share revoked',
    (tester) async {
      final repo = Repository();
      await tester.pumpWidget(
        MaterialApp(
          home: ShareChapterPage(
            book: book(),
            identify: 'parent',
            repository: repo,
            attachments: attachments,
            english: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Body of parent'), findsOneWidget);
      expect(find.text('1 / 2'), findsOneWidget);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(repo.calls, ['parent', 'child']);
      expect(find.text('Body of child'), findsOneWidget);
      expect(find.text('2 / 2'), findsOneWidget);
      repo.revoked = true;
      await tester.tap(find.text('Previous'));
      await tester.pumpAndSettle();
      expect(find.text('Body of child'), findsNothing);
      expect(find.text('Retry'), findsOneWidget);
    },
  );
  testWidgets(
    'late chapter response cannot overwrite changed initial chapter',
    (tester) async {
      final repo = Repository()..pending = Completer();
      Widget app(String id) => MaterialApp(
        home: ShareChapterPage(
          book: book(),
          identify: id,
          repository: repo,
          attachments: attachments,
          english: true,
        ),
      );
      await tester.pumpWidget(app('parent'));
      await tester.pump();
      await tester.pumpWidget(app('child'));
      await tester.pumpAndSettle();
      final parent = book().nodes.single;
      repo.pending!.complete(
        PublicShareChapter(
          node: parent,
          title: 'Parent',
          content: '# Late body',
          format: 'markdown',
          rawAvailable: false,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Late body'), findsNothing);
      expect(find.text('Body of child'), findsOneWidget);
    },
  );
  testWidgets(
    '320dp English 200 percent book empty and chapter controls have no overflow',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Widget app(Widget child) => MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: child,
      );
      final repo = Repository()..empty = true;
      await tester.pumpWidget(
        app(
          ShareBookPage(
            reference: ref,
            repository: repo,
            english: true,
            onOpen: (_, _) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('0 chapters loaded'), findsOneWidget);
      expect(tester.takeException(), isNull);
      repo.empty = false;
      await tester.pumpWidget(
        app(
          ShareChapterPage(
            book: book(),
            identify: 'child',
            repository: repo,
            attachments: attachments,
            english: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('2 / 2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
