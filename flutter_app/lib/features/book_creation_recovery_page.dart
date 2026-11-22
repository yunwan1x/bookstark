import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/book_creation_attempt.dart';
import '../core/book_creation_controller.dart';

/// Recovery only. Does not replace existing-ID editor/list or initiate POST.
class BookCreationRecoveryPage extends StatefulWidget {
  const BookCreationRecoveryPage({
    super.key,
    required this.controller,
    this.english = false,
    this.onOpenReadOnly,
  });
  final BookCreationController controller;
  final bool english;
  final Future<void> Function(int id)? onOpenReadOnly;
  @override
  State<BookCreationRecoveryPage> createState() =>
      _BookCreationRecoveryPageState();
}

class _BookCreationRecoveryPageState extends State<BookCreationRecoveryPage> {
  final _id = TextEditingController();
  bool _confirm = false, _reviewing = false;
  String? _lastReview, _localError;
  BookCreationController get c => widget.controller;
  String t(String zh, String en) => widget.english ? en : zh;
  @override
  void initState() {
    super.initState();
    c.addListener(_changed);
  }

  void _changed() {
    if (!mounted) return;
    final next = c.review?.fingerprint;
    if (next != _lastReview) {
      _lastReview = next;
      _confirm = false;
    }
    if (c.attempt?.state != BookAttemptState.submittedUnknown) {
      _reviewing = false;
    }
    setState(() {});
  }

  @override
  void didUpdateWidget(covariant BookCreationRecoveryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, c)) {
      oldWidget.controller.removeListener(_changed);
      c.addListener(_changed);
      _confirm = false;
      _reviewing = false;
      _lastReview = null;
      _id.clear();
    }
  }

  @override
  void dispose() {
    c.removeListener(_changed);
    _id.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _localError = null);
    try {
      await action();
    } catch (_) {
      if (mounted) {
        setState(
          () => _localError = t(
            '当前操作未完成，原记录已保留。',
            'Action incomplete. Original record retained.',
          ),
        );
      }
    }
  }

  Future<void> _read() async {
    final id = int.tryParse(_id.text);
    if (id == null || id <= 0 || id > 9007199254740991) {
      setState(
        () =>
            _localError = t('请输入有效的已有书籍ID。', 'Enter a valid existing book ID.'),
      );
      return;
    }
    await _run(() => c.inspectExisting(id));
  }

  Widget _card(String title, List<Widget> children) => Card(
    color: Colors.white,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    ),
  );
  Widget _draft(BookCreationInput input) =>
      _card(t('本次新建草稿（已冻结）', 'Frozen creation draft'), [
        Text('${t('书名', 'Name')}: ${input.name}'),
        Text('${t('说明', 'Description')}: ${input.description}'),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: input.labels
              .map((label) => Chip(label: Text(label)))
              .toList(),
        ),
      ]);
  @override
  Widget build(BuildContext context) {
    final record = c.attempt;
    final known = record?.state == BookAttemptState.knownID;
    final storageBlocked = c.phase == BookCreationPhase.storageUnconfirmed;
    final canLeave = !c.busy && !(known && !c.knownDurable);
    final review = c.review;
    return PopScope(
      canPop: canLeave && !_reviewing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && canLeave && _reviewing) {
          setState(() {
            _reviewing = false;
            _confirm = false;
          });
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xfff4f6fa),
        appBar: AppBar(
          title: Text(
            known
                ? t('已获得书籍ID', 'Known book ID')
                : _reviewing
                ? t('核对已有书籍', 'Review existing book')
                : t('新建书籍', 'New book'),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: t('返回', 'Back'),
            onPressed: canLeave
                ? () {
                    if (_reviewing) {
                      setState(() {
                        _reviewing = false;
                        _confirm = false;
                      });
                    } else {
                      Navigator.maybePop(context);
                    }
                  }
                : null,
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (record != null && !known && !_reviewing) _draft(record.input),
              if (c.safeError != null)
                Semantics(liveRegion: true, child: Text(c.safeError!)),
              if (_localError != null)
                Semantics(liveRegion: true, child: Text(_localError!)),
              const SizedBox(height: 16),
              if (record?.state == BookAttemptState.submittedUnknown) ...[
                if (!_reviewing) ...[
                  _card(t('提交结果未知', 'Submission result unknown'), [
                    Text(
                      t(
                        '上次请求可能已创建书籍及首篇文档。请勿重复新建。',
                        'The prior request may have created a book and its first document. Do not resend.',
                      ),
                    ),
                  ]),
                  FilledButton(
                    onPressed: null,
                    child: Text(t('新建已暂停', 'Creation paused')),
                  ),
                  OutlinedButton(
                    onPressed: c.busy
                        ? null
                        : () => setState(() {
                            _reviewing = true;
                            _confirm = false;
                          }),
                    child: Text(t('输入已有书籍ID核对', 'Review an existing book ID')),
                  ),
                ],
                if (_reviewing) ...[
                  TextField(
                    controller: _id,
                    keyboardType: TextInputType.number,
                    enabled: !c.busy,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    maxLength: 16,
                    decoration: InputDecoration(
                      labelText: t('已有书籍ID', 'Existing book ID'),
                    ),
                  ),
                  OutlinedButton(
                    onPressed: c.canReview ? _read : null,
                    child: Text(t('只读读取', 'Read without writing')),
                  ),
                  if (review != null) ...[
                    _card('${t('已有书籍', 'Existing book')} #${review.book.id}', [
                      Text(review.book.name),
                      Text('${t('标识', 'Identify')}: ${review.book.identify}'),
                      Text(review.book.description),
                      Wrap(
                        spacing: 8,
                        children: review.book.labels
                            .map((label) => Chip(label: Text(label)))
                            .toList(),
                      ),
                      Text(
                        '${t('文档', 'Documents')}: ${review.book.documentCount}',
                      ),
                      if (review.book.modifiedAt != null)
                        Text('${review.book.modifiedAt}'),
                    ]),
                    _draft(record!.input),
                    Text(
                      t(
                        '名称相同不代表由上次请求创建。关联不会创建或修改书籍。',
                        'A matching name does not prove creation by the prior request. Linking creates or updates nothing.',
                      ),
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        t(
                          '我已核对资料，并选择关联这个已有ID',
                          'I reviewed the details and choose to link this existing ID',
                        ),
                      ),
                      value: _confirm,
                      onChanged: c.busy
                          ? null
                          : (value) => setState(() => _confirm = value == true),
                    ),
                    FilledButton(
                      onPressed: _confirm && c.canReview
                          ? () => _run(
                              () => c.adoptExisting(
                                review,
                                explicitlyConfirmed: true,
                              ),
                            )
                          : null,
                      child: Text(
                        t('确认关联已有书籍', 'Confirm link to existing book'),
                      ),
                    ),
                  ],
                ],
              ],
              if (known) ...[
                _card(t('已获得书籍ID', 'Known book ID'), [
                  SelectableText('#${record!.knownID}'),
                  Text(
                    record.origin == BookIDOrigin.manualExisting
                        ? t(
                            '你已明确关联现有ID；这不是本次请求创建的证明。',
                            'You linked an existing ID. This is not proof of creation by this attempt.',
                          )
                        : t(
                            '已收到真实正ID，不会再次发送新建请求。',
                            'A positive ID was received. Creation will not be resent.',
                          ),
                  ),
                  if (record.labelsNeedReview)
                    Text(
                      t(
                        '标签状态待核对，请稍后在既有书籍设置中检查。',
                        'Review labels later in the existing book settings.',
                      ),
                    ),
                ]),
                if (!c.knownDurable)
                  Text(
                    t(
                      '本机记录尚未保存成功，请先重试本机存储。',
                      'Device record is not confirmed. Retry storage before leaving.',
                    ),
                  ),
                OutlinedButton(
                  onPressed: c.busy || widget.onOpenReadOnly == null
                      ? null
                      : () =>
                            _run(() => widget.onOpenReadOnly!(record.knownID!)),
                  child: Text(t('查看书籍（只读）', 'View book (read only)')),
                ),
              ],
              if (storageBlocked)
                FilledButton(
                  onPressed: c.busy ? null : () => _run(c.retryStorage),
                  child: Text(t('仅重试保存本机记录', 'Retry device storage only')),
                ),
              if (record?.state == BookAttemptState.pending && !storageBlocked)
                Text(
                  t(
                    '尚未发送。修复连接后，可从原表单明确重交同一草稿。',
                    'Not sent. Fix the connection, then explicitly submit this same draft from the original form.',
                  ),
                ),
              if (c.busy) const LinearProgressIndicator(),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: canLeave ? () => Navigator.maybePop(context) : null,
                child: Text(t('保留记录并返回', 'Return and retain record')),
              ),
              Text(
                t(
                  '此页不会自动新建、修改、补写标签或删除书籍。',
                  'This page never automatically creates, updates, adds labels to, or deletes a book.',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
