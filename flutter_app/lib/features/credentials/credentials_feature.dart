import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/api_tokens_repository.dart' hide ApiTokensPage;
import '../../core/webdav_password_repository.dart';
import 'api_tokens_page.dart';
import 'webdav_password_page.dart';

Future<void> openCredentials(
  BuildContext context, {
  required BookstarkClient client,
  required int memberId,
  bool english = false,
}) async {
  String t(String zh, String en) => english ? en : zh;
  final kind = await showModalBottomSheet<String>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (context) => ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .85,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              t('API与应用密码', 'API and app passwords'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.key_outlined),
              title: Text(t('API令牌', 'API tokens')),
              onTap: () => Navigator.pop(context, 'api'),
            ),
            ListTile(
              leading: const Icon(Icons.folder_copy_outlined),
              title: Text(t('WebDAV应用密码', 'WebDAV app password')),
              onTap: () => Navigator.pop(context, 'dav'),
            ),
          ],
        ),
      ),
    ),
  );
  if (kind == null || !context.mounted) {
    return;
  }
  await Navigator.push<void>(
    context,
    MaterialPageRoute(
      builder: (_) => kind == 'api'
          ? ApiTokensPage(
              repository: RemoteApiTokensRepository(client, memberId: memberId),
              english: english,
            )
          : WebdavPasswordPage(
              repository: RemoteWebdavPasswordRepository(
                client,
                memberId: memberId,
              ),
              english: english,
            ),
    ),
  );
}
