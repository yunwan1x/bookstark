import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/public_edit_link.dart';
import 'package:bookstark_flutter/core/public_edit_snapshot.dart';
import 'package:bookstark_flutter/core/public_edit_repository.dart';
import 'package:bookstark_flutter/core/public_edit_controller.dart';
import 'package:bookstark_flutter/core/public_share_models.dart';
import 'public_shares.dart';

class PublicEditFixture implements PublicEditRepository {
  PublicEditFixture({this.protected = false, this.loseReceipt = false});
  final bool protected, loseReceipt;
  static final link = PublicEditLink.parse(
    PublicSharesFixture.server,
    'https://fixture.invalid/shares/editor?token=${List.filled(64, 'f').join()}',
  );
  String content = PublicSharesFixture.body;
  int revision = 0, writes = 0;
  Future<PublicEditController> controller({bool conflict = false}) async {
    final controller = PublicEditController(this, link);
    await controller.initialize();
    if (conflict) {
      content = '# 新的阅读计划\n\n每周回顾并调整。';
      revision++;
    }
    return controller;
  }

  @override
  Future<PublicEditSnapshot> read(
    PublicEditLink supplied, {
    String? password,
    Future<void>? abortTrigger,
  }) async {
    if (supplied != link) {
      throw const ApiFailure(403, 'Invalid fixture capability');
    }
    var detail = PublicShareDetail.fromJson(link.reference, {
      'share_type': 'blog',
      'blog_type': 'note',
      'share_id': 8,
      'target_id': 7,
      'share_identify': 'editor',
      'has_password': protected,
      'title': protected ? '我的年度复盘' : '选择适合自己的书',
      'doc_type': 'markdown',
      'content': content,
    });
    if (protected && password != null) {
      if (password != 'fixture-only') {
        throw const ApiFailure(400, 'Wrong fixture password');
      }
      detail = detail.unlockMarkdown(content);
    }
    return PublicEditSnapshot.parse(detail, {
      'editable': true,
      'share_type': 'blog',
      'blog_type': 'note',
      'has_password': protected,
      'title': detail.title,
      'doc_type': 'markdown',
      'content': protected ? '' : content,
      'modify_time': '2026-11-05 12:00:${revision.toString().padLeft(2, '0')}',
    });
  }

  @override
  Future<PublicEditReceipt> save(
    PublicEditLink supplied,
    PublicEditSnapshot baseline,
    String value, {
    String? password,
  }) async {
    if (supplied != link || protected && password != 'fixture-only') {
      throw const ApiFailure(403, 'Invalid fixture permission');
    }
    validateSharedMarkdown(value);
    writes++;
    content = value;
    revision++;
    if (loseReceipt) throw StateError('Fixture receipt lost after write');
    return PublicEditReceipt(
      link.reference,
      '2026-11-05 12:00:${revision.toString().padLeft(2, '0')}',
    );
  }
}
