// Isolated synthetic UI target. It never inspects a real archive, opens SQL,
// activates a generation or replaces production navigation.
// Web uses a visual-only window/unlocker; Android uses the real native guards
// and crypto channel with a public synthetic Go interoperability vector.
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path/path.dart' as paths;
import 'package:path_provider/path_provider.dart';
import 'package:bookstark_flutter/core/app_theme.dart';
import 'package:bookstark_flutter/core/attachments.dart';
import 'package:bookstark_flutter/core/local_legacy_format_selection.dart';
import 'package:bookstark_flutter/core/native_local_content_crypto.dart';
import 'package:bookstark_flutter/features/admin/admin_asset_secure_window.dart';
import 'package:bookstark_flutter/features/local_backup/legacy_format_ui.dart';
import 'package:bookstark_flutter/features/local_backup/local_legacy_format_page.dart';
import 'legacy_format_fixture_seed.dart';

class _VisualWindow implements AdminAssetWindowGuard {
  @override
  Future<void> acquire() async {}
  @override
  Future<void> close() async {}
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LegacyFormatFixtureApp());
}

class LegacyFormatFixtureApp extends StatefulWidget {
  const LegacyFormatFixtureApp({super.key});
  @override
  State<LegacyFormatFixtureApp> createState() => _LegacyFormatFixtureAppState();
}

class _LegacyFormatFixtureAppState extends State<LegacyFormatFixtureApp> {
  final _task = attachmentId();
  late final LegacyFormatSource source;
  late final bool english;
  late final double scale;
  late final LegacyFormatSelection? initial;
  LegacyFormatSelection? accepted;
  String t(String zh, String en) => english ? en : zh;
  @override
  void initState() {
    super.initState();
    final query = Uri.base.queryParameters;
    english = query['lang'] == 'en';
    scale = (double.tryParse(query['scale'] ?? '1') ?? 1)
        .clamp(1, 2)
        .toDouble();
    source = LegacyFormatSource(
      archiveSha256: 'a' * 64,
      scopeKey: 'b' * 32,
      items: const [
        LegacyFormatItem(
          id: 'note',
          title: '旅行手记',
          collection: 'note',
          originalBody: '\uFEFF# 旅行手记\r\n',
          passwordHash: '',
        ),
        LegacyFormatItem(
          id: 'article',
          title: '网页收藏',
          collection: 'article',
          originalBody: '<p>网页收藏</p>',
          passwordHash: '',
        ),
        LegacyFormatItem(
          id: 'protected',
          title: '会议纪要',
          collection: 'note',
          originalBody: fixtureEncryptedBody,
          passwordHash: fixturePasswordHash,
        ),
      ],
    );
    // Explicit preselected user choices for the screenshot case, not inference.
    initial = query['case'] == 'review'
        ? LegacyFormatSelection(
            source,
            choices: const {
              'note': LegacyContentFormat.markdown,
              'article': LegacyContentFormat.html,
              'protected': LegacyContentFormat.markdown,
            },
          )
        : null;
  }

  Future<void> _record(String name, Map<String, Object?> value) async {
    if (kIsWeb) return;
    final root = await getApplicationSupportDirectory();
    final directory = Directory(
      paths.join(root.path, 'legacy-format44-fixture', _task),
    );
    await directory.create(recursive: true);
    await File(paths.join(directory.path, '$name.json')).writeAsString(
      jsonEncode({'fixture_only': true, 'task': _task, ...value}),
      flush: true,
    );
  }

  Future<String> _unlock(
    LegacyFormatItem item,
    String password,
    AttachmentCancellation owner,
  ) async {
    if (kIsWeb) {
      owner.check();
      if (password != fixturePassword) {
        throw const LocalContentCryptoFailure(
          LocalContentCryptoReason.wrongPassword,
        );
      }
      return '# 项目记录\n\n这是正文预览。';
    }
    final body = await NativeLocalContentCrypto().unlock(
      password: password,
      passwordHash: item.passwordHash,
      body: item.originalBody,
      cancellation: owner,
    );
    owner.check();
    final bytes = utf8.encode(body);
    await _record('crypto', {
      'actual_native_channel': true,
      'matches_go_vector': body == fixturePlaintext,
      'body_sha256': sha256.convert(bytes).toString(),
      'body_bytes': bytes.length,
      'leading_bom': body.startsWith('\uFEFF'),
      'crlf': body.contains('\r\n'),
      'migration_executed': false,
    });
    owner.check();
    if (body != fixturePlaintext) {
      throw const LocalContentCryptoFailure(
        LocalContentCryptoReason.invalidContent,
      );
    }
    return body;
  }

  Future<void> _resolved(LegacyFormatSelection value) async {
    await _record('selection', {
      'recipe': value.toJson(),
      'recipe_sha256': value.digest,
      'migration_executed': false,
    });
    if (mounted) setState(() => accepted = value);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: bookstarkTheme(),
    locale: Locale(english ? 'en' : 'zh'),
    supportedLocales: const [Locale('zh'), Locale('en')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: accepted == null
        ? LocalLegacyFormatPage(
            source: source,
            initial: initial,
            english: english,
            isCurrentScope: () => mounted && accepted == null,
            unlocker: _unlock,
            windowGuardFactory: kIsWeb ? () => _VisualWindow() : null,
            onResolved: _resolved,
          )
        : LegacyFormatFrame(
            title: t('格式选择已保存', 'Format choices saved'),
            content: [
              LegacyFormatInfo(
                t(
                  '仅保存格式选择，尚未执行迁移',
                  'Only format choices were saved. Migration has not run.',
                ),
                checked: true,
              ),
              for (final item in source.items)
                ListTile(
                  title: Text(item.title),
                  subtitle: Text(
                    legacyFormatName(accepted!.choices[item.id]!, english),
                  ),
                ),
            ],
          ),
  );
}
