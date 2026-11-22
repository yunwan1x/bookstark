import 'dart:convert';
import 'notes_repository.dart';

String _escape(String text) => text.replaceAllMapped(
  RegExp(r'[\\`*_{}\[\]()#+\-.!|<>]'),
  (match) => '\\${match[0]}',
);

Note documentExcerpt({
  required String quote,
  required String name,
  required String path,
  required String bookIdentify,
  required int documentId,
  Uri? server,
  bool english = false,
}) {
  if (quote.trim().isEmpty || utf8.encode(quote).length > 128 * 1024) {
    throw const FormatException('请选择较短的摘录文字 / Select a shorter passage');
  }
  final prefix = english ? 'Excerpt · ' : '摘录 · ';
  final title = StringBuffer(prefix);
  var length = utf8.encode(prefix).length;
  for (final rune in name.runes) {
    final part = String.fromCharCode(rune);
    if (length + utf8.encode(part).length > 197) {
      title.write('…');
      break;
    }
    title.write(part);
    length += utf8.encode(part).length;
  }
  final quoted = quote
      .split('\n')
      .map((line) => '> ${_escape(line)}')
      .join('\n');
  final source =
      '${_escape(path)} / ${_escape(name)} · ${english ? 'Document' : '文档'} #$documentId';
  final String attribution;
  if (server != null) {
    if (!{'http', 'https'}.contains(server.scheme) ||
        server.host.isEmpty ||
        server.userInfo.isNotEmpty ||
        server.hasQuery ||
        server.hasFragment) {
      throw const FormatException('Invalid source server');
    }
    final uri = Uri(
      scheme: server.scheme,
      host: server.host,
      port: server.hasPort ? server.port : null,
      pathSegments: [
        ...server.pathSegments.where((part) => part.isNotEmpty),
        'books',
        bookIdentify,
        'edit',
      ],
      queryParameters: {'doc': '$documentId'},
    );
    attribution = '[$source](<$uri>)';
  } else {
    attribution = source;
  }
  return Note(
    title: title.toString(),
    content: '$quoted\n\n${english ? 'Source' : '来源'}：$attribution\n\n',
  );
}
