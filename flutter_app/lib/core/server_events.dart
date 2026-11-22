import 'dart:convert';

class ServerEvent {
  const ServerEvent(this.type, this.data);
  final String type, data;
}

Stream<ServerEvent> decodeServerEvents(
  Stream<List<int>> bytes, {
  int maxEventBytes = 256 * 1024,
  int maxTotalBytes = 2 * 1024 * 1024,
}) async* {
  var total = 0;
  Stream<List<int>> bounded() async* {
    await for (final chunk in bytes) {
      total += chunk.length;
      if (total > maxTotalBytes) {
        throw const FormatException('SSE response exceeds total limit');
      }
      yield chunk;
    }
  }

  var type = 'message', size = 0;
  final data = <String>[];
  var firstLine = true;
  await for (var line
      in bounded().transform(utf8.decoder).transform(const LineSplitter())) {
    if (firstLine) {
      line = line.replaceFirst(RegExp('^\uFEFF'), '');
      firstLine = false;
    }
    if (line.isEmpty) {
      if (data.isNotEmpty) {
        yield ServerEvent(type.isEmpty ? 'message' : type, data.join('\n'));
      }
      type = 'message';
      data.clear();
      size = 0;
      continue;
    }
    size += utf8.encode(line).length + 1;
    if (size > maxEventBytes) {
      throw const FormatException('SSE event exceeds limit');
    }
    if (line.startsWith(':')) continue;
    final colon = line.indexOf(':');
    final field = colon < 0 ? line : line.substring(0, colon);
    var value = colon < 0 ? '' : line.substring(colon + 1);
    if (value.startsWith(' ')) value = value.substring(1);
    if (field == 'event') type = value;
    if (field == 'data') data.add(value);
  }
  // EOF does not dispatch a partial event; consumers require a complete done.
}
