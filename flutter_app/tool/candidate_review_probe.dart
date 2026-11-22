// Synthetic Android entry only; production main never selects this target.
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:bookstark_flutter/core/local_legacy_zip_stage.dart';
import 'package:bookstark_flutter/core/local_legacy_go_export.dart';
import 'package:bookstark_flutter/core/local_legacy_format_selection.dart';
import 'package:bookstark_flutter/core/local_legacy_candidate_review.dart';
import 'package:bookstark_flutter/features/local_backup/local_legacy_candidate_review_page.dart';

const fixtureSHA =
    '24cae43e3349326f6aeae18ac4d6c89e565819951751b3021f930ca5bdde2fb8';
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Directory? root;
  try {
    final support = await getApplicationSupportDirectory();
    root = Directory('${support.path}/candidate-review-probe');
    final marker =
        jsonDecode(await File('${root.path}/owned.json').readAsString()) as Map;
    final nonce = marker['nonce'];
    if (marker.length != 3 ||
        marker['format'] != 1 ||
        marker['synthetic_only'] != true ||
        nonce is! String ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(nonce) ||
        await FileSystemEntity.type(root.path, followLinks: false) !=
            FileSystemEntityType.directory ||
        await root.resolveSymbolicLinks() !=
            '${await support.resolveSymbolicLinks()}/candidate-review-probe') {
      throw StateError('Expected owned synthetic marker');
    }
    final input = File('${root.path}/fixture.zip');
    if ((await sha256.bind(input.openRead()).first).toString() != fixtureSHA) {
      throw StateError('Expected immutable synthetic Go ZIP');
    }
    final stage = await LegacyZipStage.inspect(
      input,
      privateParent: root,
      expectedSha256: fixtureSHA,
      availableBytes: () async => 4 * 1024 * 1024 * 1024,
    );
    final inspection = await LegacyGoExport.inspect(stage);
    final formats = LegacyFormatSource.fromInspection(
      inspection,
      scopeKey: nonce,
    );
    final selection = LegacyFormatSelection(
      formats,
      choices: {
        for (final item in formats.items)
          item.id: item.title == '项目草稿'
              ? LegacyContentFormat.markdown
              : LegacyContentFormat.html,
      },
    );
    final review = await LegacyCandidateReviewSession.build(
      stage: stage,
      selection: selection,
      privateParent: root,
      availableBytes: () async => 4 * 1024 * 1024 * 1024,
      isCurrentScope: () => true,
    );
    final counts = await review.counts();
    if (counts.notes != 2 ||
        counts.articles != 1 ||
        counts.protectedItems != 1) {
      throw StateError('Synthetic counts differ');
    }
    await File('${root.path}/ready.json').writeAsString(
      jsonEncode({
        'passed': true,
        'nonce': nonce,
        'fixtureOnly': true,
        'schema': 15,
        'notes': counts.notes,
        'articles': counts.articles,
        'protected': counts.protectedItems,
        'realGoZIP': fixtureSHA,
        'productionActivation': false,
      }),
      flush: true,
    );
    runApp(MaterialApp(home: _Host(review, root)));
  } catch (_) {
    if (root != null) {
      await File(
        '${root.path}/failure.json',
      ).writeAsString('{"passed":false,"detailsOmitted":true}', flush: true);
    }
    runApp(
      const MaterialApp(
        home: Scaffold(body: Center(child: Text('FIXTURE FAILED'))),
      ),
    );
  }
}

class _Host extends StatefulWidget {
  const _Host(this.review, this.root);
  final LegacyCandidateReviewSession review;
  final Directory root;
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) =>
              LocalLegacyCandidateReviewPage(session: widget.review),
        ),
      );
      await widget.review.close();
      await File('${widget.root.path}/closed.json').writeAsString(
        '{"passed":true,"ownedViewsClosed":true,"copyClosed":true}',
        flush: true,
      );
    });
  }

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('REVIEW CLOSED')));
}
