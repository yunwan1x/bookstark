import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/app_theme.dart';
import 'package:bookstark_flutter/core/assistant_repository.dart';
import 'package:bookstark_flutter/features/assistant/assistant_page.dart';

const _session = '0123456789abcdef0123456789abcdef';
const _draft = 'abcdef0123456789abcdef0123456789';

class _Drafts implements AssistantDataSource {
  String status = 'pending';
  String url = '';
  int opens = 0, confirms = 0, cancels = 0;
  bool failRefresh = false;
  AssistantDraft get current => AssistantDraft.fromJson({
    'id': _draft,
    'status': status,
    'url': url,
    'payload': {
      'kind': 'note',
      'title': 'Reading notes',
      'content': '# Reading\n\nA proposed note.',
    },
  });
  @override
  Future<AssistantSession> open() async {
    opens++;
    if (failRefresh && opens > 1) {
      throw StateError('private-provider-url?secret=do-not-render');
    }
    return AssistantSession.fromJson({
      'id': _session,
      'busy': false,
      'drafts': [
        {
          'id': current.id,
          'status': current.status,
          'url': current.url,
          'payload': current.payload,
        },
      ],
    });
  }

  @override
  Future<AssistantDraft> resolve(
    String session,
    String id, {
    required bool confirm,
  }) async {
    expect(session, _session);
    expect(id, _draft);
    if (confirm) {
      confirms++;
      fail('Local draft must not confirm through repository');
    }
    cancels++;
    status = 'cancelled';
    return current;
  }

  @override
  Future<AssistantSession> reset(String id) async =>
      throw StateError('Unexpected reset');
  @override
  Future<AssistantResourceDetail> readSource(
    Map<String, Object?> source,
  ) async => throw StateError('Typed root callback should open the resource');
  @override
  Stream<AssistantUpdate> chat({
    required String session,
    required String message,
    required List<AssistantMessage> history,
    Future<void>? abortTrigger,
  }) => throw StateError('No model request is authorized by editing');
}

Future<void> _mount(
  WidgetTester tester,
  _Drafts repository, {
  Future<void> Function(String)? edit,
  Future<void> Function(Map<String, Object?>)? openSource,
  bool small = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = small
      ? const Size(320, 568)
      : const Size(390, 844);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: bookstarkTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(small ? 2 : 1),
          viewInsets: small
              ? const EdgeInsets.only(bottom: 180)
              : EdgeInsets.zero,
        ),
        child: child!,
      ),
      home: AssistantPage(
        repository: repository,
        local: true,
        english: small,
        modelLabel: 'My configured model',
        onEditLocalDraft: edit,
        onOpenSource: openSource,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String label) async {
  final target = find.text(label);
  await tester.scrollUntilVisible(
    target,
    120,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'pending edit delegates once, refreshes real draft and opens actual typed ID',
    (tester) async {
      final repository = _Drafts();
      final edited = <String>[], sources = <Map<String, Object?>>[];
      await _mount(
        tester,
        repository,
        edit: (id) async {
          edited.add(id);
          repository.status = 'done';
          repository.url = '/notes?tab=notes&id=731';
        },
        openSource: (source) async {
          sources.add(source);
        },
      );
      await _tap(tester, '编辑并保存');
      expect(edited, [_draft]);
      expect(repository.opens, 2);
      expect(repository.confirms, 0);
      expect(repository.cancels, 0);
      expect(find.text('已创建'), findsOneWidget);
      expect(find.text('编辑并保存'), findsNothing);
      await _tap(tester, '打开已创建资源');
      expect(sources.single['kind'], 'note');
      expect(sources.single['id'], 731);
      expect(repository.opens, 2);
    },
  );
  testWidgets(
    'unknown outcome delegates review and never creates or discards',
    (tester) async {
      final repository = _Drafts()..status = 'unknown';
      final edited = <String>[];
      await _mount(
        tester,
        repository,
        edit: (id) async {
          edited.add(id);
        },
      );
      expect(find.text('保存结果待核对'), findsOneWidget);
      expect(find.text('编辑并保存'), findsNothing);
      expect(find.text('放弃'), findsNothing);
      await _tap(tester, '核对保存结果');
      expect(edited, [_draft]);
      expect(repository.opens, 2);
      expect(repository.confirms, 0);
      expect(repository.cancels, 0);
      expect(find.text('保存结果待核对'), findsOneWidget);
    },
  );
  testWidgets('discard only calls resolve false without entering editor', (
    tester,
  ) async {
    final repository = _Drafts();
    var edits = 0;
    await _mount(
      tester,
      repository,
      edit: (_) async {
        edits++;
      },
    );
    await _tap(tester, '放弃');
    expect(edits, 0);
    expect(repository.confirms, 0);
    expect(repository.cancels, 1);
    expect(repository.opens, 1);
    expect(find.text('已放弃'), findsOneWidget);
    expect(find.text('编辑并保存'), findsNothing);
  });
  testWidgets('edit failure keeps draft and hides provider details', (
    tester,
  ) async {
    final repository = _Drafts();
    await _mount(
      tester,
      repository,
      edit: (_) async {
        throw StateError('private-provider-url?secret=do-not-render');
      },
    );
    await _tap(tester, '编辑并保存');
    expect(find.text('待确认'), findsOneWidget);
    expect(find.text('编辑并保存'), findsOneWidget);
    expect(find.text('本地助手暂时无法完成操作，请重试。'), findsOneWidget);
    expect(find.textContaining('do-not-render'), findsNothing);
    expect(repository.opens, 1);
    expect(repository.confirms, 0);
  });
  testWidgets('refresh failure retains draft without falsely showing created', (
    tester,
  ) async {
    final repository = _Drafts()..failRefresh = true;
    await _mount(tester, repository, edit: (_) async {});
    await _tap(tester, '编辑并保存');
    expect(find.text('待确认'), findsOneWidget);
    expect(find.text('已创建'), findsNothing);
    expect(find.textContaining('do-not-render'), findsNothing);
    expect(repository.opens, 2);
    expect(repository.confirms, 0);
  });
  testWidgets('missing edit capability disables local create button', (
    tester,
  ) async {
    final repository = _Drafts();
    await _mount(tester, repository);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '编辑并保存'),
    );
    expect(button.onPressed, isNull);
    expect(repository.confirms, 0);
  });
  testWidgets('in-flight editor disables duplicate taps until actual return', (
    tester,
  ) async {
    final repository = _Drafts();
    final gate = Completer<void>();
    var edits = 0;
    await _mount(
      tester,
      repository,
      edit: (_) async {
        edits++;
        await gate.future;
      },
    );
    await _tap(tester, '编辑并保存');
    expect(edits, 1);
    expect(repository.opens, 1);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '处理中…'),
    );
    expect(button.onPressed, isNull);
    expect(repository.confirms, 0);
    gate.complete();
    await tester.pumpAndSettle();
    expect(repository.opens, 2);
    expect(find.text('编辑并保存'), findsOneWidget);
  });
  for (final status in ['pending', 'unknown']) {
    testWidgets('320dp 200 percent English keyboard $status remains usable', (
      tester,
    ) async {
      final repository = _Drafts()..status = status;
      var edits = 0;
      await _mount(
        tester,
        repository,
        small: true,
        edit: (_) async {
          edits++;
        },
      );
      expect(tester.takeException(), isNull);
      await _tap(
        tester,
        status == 'pending' ? 'Edit and save' : 'Review save result',
      );
      expect(edits, 1);
      expect(repository.confirms, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    });
  }
}
