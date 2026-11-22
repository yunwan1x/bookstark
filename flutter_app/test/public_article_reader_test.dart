import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/owned_preview_controller.dart';
import 'package:bookstark_flutter/core/public_share_models.dart';
import 'package:bookstark_flutter/core/public_share_attachments.dart';
import 'package:bookstark_flutter/core/public_shares_repository.dart';
import 'package:bookstark_flutter/features/public_shares/share_reader_page.dart';
import 'package:bookstark_flutter/features/public_shares/share_article_unlock_dialog.dart';
import 'package:bookstark_flutter/widgets/bookstark_markdown.dart';

// Owned Flutter body/lease fake, never Android or browser execution evidence.
final _server = Uri.parse('https://example.invalid/bookstark');
PublicShareReference _ref(String id) => PublicShareReference(_server, id);
PublicShareDetail _detail(
  String id, {
  String? collection = 'article',
  bool locked = false,
}) => PublicShareDetail.fromJson(_ref(id), {
  'share_type': 'blog',
  'share_id': -3,
  'target_id': 3,
  'share_identify': id,
  'has_password': locked,
  'doc_type': 'markdown',
  'blog_type': collection,
  'title': '实际公开标题',
  'author': '实际作者',
  'content': '# Exact public body',
  'labels': ['opaque,label'],
});

class _Repo implements PublicSharesRepository {
  String? collection = 'article';
  bool locked = false, fail = false;
  int loads = 0;
  final events = <String>[], passwords = <String>[];
  final pending = <String, Completer<PublicShareDetail>>{};
  Completer<PublicShareDetail>? unlockPending;
  bool unlockAborted = false;
  @override
  Future<PublicShareDetail> load(
    PublicShareReference ref, {
    Future<void>? abortTrigger,
  }) async {
    loads++;
    events.add('load:${ref.identify}');
    if (fail) throw StateError('revoked');
    return pending[ref.identify]?.future ??
        _detail(ref.identify, collection: collection, locked: locked);
  }

  @override
  Future<PublicShareDetail> unlock(
    PublicShareDetail detail,
    String password, {
    Future<void>? abortTrigger,
  }) async {
    passwords.add(password);
    abortTrigger?.then((_) {
      unlockAborted = true;
    });
    if (unlockPending != null) return unlockPending!.future;
    if (password != ' exact password ') throw const ApiFailure(400, '密码不正确');
    return detail.unlockMarkdown('# Unlocked exact body');
  }

  @override
  Future<PublicShareChapter> chapter(
    PublicShareDetail book,
    String id, {
    Future<void>? abortTrigger,
  }) => throw UnimplementedError();
}

class _Views {
  final states = <_BodyState>[], events = <String>[];
  Completer<void>? closeGate;
  Widget build(
    BuildContext context, {
    required Key key,
    required PublicShareDetail detail,
    required OwnedPreviewController retirementController,
    required Future<void> Function() onReload,
    required Future<void> Function(Uri) onExternalLink,
    required bool english,
  }) => _Body(
    key: key,
    owner: this,
    detail: detail,
    lease: retirementController,
    reload: onReload,
  );
}

class _Body extends StatefulWidget {
  const _Body({
    super.key,
    required this.owner,
    required this.detail,
    required this.lease,
    required this.reload,
  });
  final _Views owner;
  final PublicShareDetail detail;
  final OwnedPreviewController lease;
  final Future<void> Function() reload;
  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  @override
  void initState() {
    super.initState();
    widget.owner.states.add(this);
    widget.lease.bind(this, () async {
      widget.owner.events.add('retire-start');
      await widget.owner.closeGate?.future;
      widget.owner.events.add('retire-end');
    });
  }

  @override
  void dispose() {
    widget.lease.unbind(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(widget.detail.content),
      TextButton(
        onPressed: () => unawaited(widget.reload()),
        child: const Text('owned reload'),
      ),
    ],
  );
}

void main() {
  late _Repo repo;
  late _Views views;
  late PublicShareAttachments attachments;
  setUp(() {
    repo = _Repo();
    views = _Views();
    attachments = PublicShareAttachments(
      _server,
      publicTransport: MockClient((_) async => http.Response('', 404)),
    );
  });
  tearDown(() => attachments.close());
  Future<void> mount(
    WidgetTester t, {
    String id = 'article',
    Future<void> Function(String, String, String)? speak,
  }) async {
    await t.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: const [Locale('zh'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: ShareReaderPage(
          reference: _ref(id),
          repository: repo,
          attachments: attachments,
          articleBodyBuilder: views.build,
          onSpeak: speak,
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  Future<void> clear(WidgetTester t) async {
    final gate = views.closeGate;
    if (gate != null && !gate.isCompleted) gate.complete();
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
  }

  testWidgets(
    'article and unknown share use owned body; explicit note stays native',
    (t) async {
      for (final collection in ['article', null, 'note']) {
        repo.collection = collection;
        views = _Views();
        await mount(t);
        if (collection == 'note') {
          expect(views.states, isEmpty);
          expect(find.byType(BookstarkMarkdown), findsOneWidget);
        } else {
          expect(views.states, hasLength(1));
          expect(find.byType(BookstarkMarkdown), findsNothing);
          expect(
            find.text(collection == null ? '分享阅读 · 兼容' : '公开文章'),
            findsOneWidget,
          );
          if (collection == null) {
            expect(find.text('服务器未提供内容分类，以只读模式打开。'), findsOneWidget);
          }
        }
        await clear(t);
      }
    },
  );
  testWidgets(
    'reload waits close and revoked share clears plaintext and metadata',
    (t) async {
      await mount(t);
      final old = views.states.single;
      final gate = views.closeGate = Completer<void>();
      repo.fail = true;
      await t.tap(find.text('owned reload'));
      await t.pump();
      expect(views.events, contains('retire-start'));
      expect(repo.loads, 1);
      expect(find.text('# Exact public body'), findsNothing);
      expect(find.text('实际作者'), findsNothing);
      gate.complete();
      await t.pumpAndSettle();
      expect(views.events.last, 'retire-end');
      expect(repo.loads, 2);
      expect(find.text('分享暂不可用'), findsOneWidget);
      expect(views.states, hasLength(1));
      expect(old.mounted, isFalse);
      expect(t.takeException(), isNull);
      await clear(t);
    },
  );
  testWidgets('listen keeps current body generation and exact source context', (
    t,
  ) async {
    final speaking = Completer<void>();
    final values = <String>[];
    await mount(
      t,
      speak: (body, title, context) async {
        values.addAll([body, title, context]);
        await speaking.future;
      },
    );
    await t.ensureVisible(find.text('听文章'));
    await t.tap(find.text('听文章'));
    await t.pump();
    expect(values.take(2), ['# Exact public body', '实际公开标题']);
    expect(views.states, hasLength(1));
    expect(views.events, isEmpty);
    speaking.complete();
    await t.pumpAndSettle();
    expect(views.states, hasLength(1));
    expect(t.takeException(), isNull);
    await clear(t);
  });
  testWidgets(
    'locked article masks password and mounts only verified unlocked body',
    (t) async {
      repo.locked = true;
      await mount(t);
      expect(views.states, isEmpty);
      expect(find.text('# Exact public body'), findsNothing);
      await t.tap(find.text('解锁阅读'));
      await t.pumpAndSettle();
      expect(find.byType(ShareArticleUnlockDialog), findsOneWidget);
      expect(t.widget<TextField>(find.byType(TextField)).obscureText, isTrue);
      await t.enterText(find.byType(TextField), 'wrong');
      await t.tap(find.text('解锁'));
      await t.pumpAndSettle();
      expect(find.text('密码不正确，请重试。'), findsOneWidget);
      expect(views.states, isEmpty);
      await t.enterText(find.byType(TextField), ' exact password ');
      await t.tap(find.text('解锁'));
      await t.pumpAndSettle();
      expect(repo.passwords, ['wrong', ' exact password ']);
      expect(find.text('已解锁'), findsOneWidget);
      expect(find.text('# Unlocked exact body'), findsOneWidget);
      expect(views.states, hasLength(1));
      expect(t.takeException(), isNull);
      await clear(t);
    },
  );
  testWidgets('cancel aborts unlock and ignores late success', (t) async {
    repo.locked = true;
    repo.unlockPending = Completer<PublicShareDetail>();
    await mount(t);
    await t.tap(find.text('解锁阅读'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), ' exact password ');
    await t.tap(find.text('解锁'));
    await t.pump();
    await t.tap(find.text('取消'));
    await t.pumpAndSettle();
    expect(repo.unlockAborted, isTrue);
    repo.unlockPending!.complete(
      _detail('article', locked: true).unlockMarkdown('# Late private body'),
    );
    await t.pumpAndSettle();
    expect(views.states, isEmpty);
    expect(find.text('# Late private body'), findsNothing);
    expect(t.takeException(), isNull);
    await clear(t);
  });
  testWidgets('late old reference cannot replace current share', (t) async {
    repo.pending['old'] = Completer<PublicShareDetail>();
    await t.pumpWidget(
      MaterialApp(
        home: ShareReaderPage(
          reference: _ref('old'),
          repository: repo,
          attachments: attachments,
          articleBodyBuilder: views.build,
        ),
      ),
    );
    await t.pump();
    await mount(t, id: 'new');
    repo.pending['old']!.complete(_detail('old'));
    await t.pumpAndSettle();
    expect(views.states, hasLength(1));
    expect(views.states.single.widget.detail.reference.identify, 'new');
    expect(t.takeException(), isNull);
    await clear(t);
  });
}
