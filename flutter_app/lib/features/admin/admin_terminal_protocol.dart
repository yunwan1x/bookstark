import 'dart:collection';
import 'dart:convert';

const terminalMaxInputBytes = 64 * 1024;
const terminalMaxMessageBytes = 1024 * 1024;

/// Errors never retain a remote frame, command, URL or credential.
enum TerminalFailure { protocol, network, unauthorized, targetChanged, closed }

class TerminalException implements Exception {
  const TerminalException(this.kind);
  final TerminalFailure kind;
  @override
  String toString() => 'TerminalException(${kind.name})';
}

bool terminalValidUnicode(String text) {
  for (var i = 0; i < text.length; i++) {
    final c = text.codeUnitAt(i);
    if (c >= 0xd800 && c <= 0xdbff) {
      if (++i >= text.length) return false;
      final low = text.codeUnitAt(i);
      if (low < 0xdc00 || low > 0xdfff) return false;
    } else if (c >= 0xdc00 && c <= 0xdfff) {
      return false;
    }
  }
  return true;
}

bool terminalInputAllowed(String text) =>
    text.isNotEmpty &&
    terminalValidUnicode(text) &&
    text.length <= terminalMaxInputBytes &&
    utf8.encode(text).length <= terminalMaxInputBytes;

/// Paste is stricter than keyboard control sequences. Never silently transform.
bool terminalPasteAllowed(String text) =>
    terminalInputAllowed(text) &&
    text.runes.every(
      (r) =>
          r == 9 ||
          r == 10 ||
          r == 13 ||
          (r >= 32 && r != 127 && !(r >= 128 && r <= 159)),
    );

Uri terminalEndpoint(Uri base, int hostId) {
  if (!{'http', 'https'}.contains(base.scheme) ||
      base.host.isEmpty ||
      base.userInfo.isNotEmpty ||
      base.hasQuery ||
      base.hasFragment ||
      hostId < 1 ||
      hostId > 9007199254740991) {
    throw const TerminalException(TerminalFailure.protocol);
  }
  final prefix = base.path.replaceFirst(RegExp(r'/+$'), '');
  return base.replace(
    scheme: base.scheme == 'https' ? 'wss' : 'ws',
    path: '$prefix/api/admin/assets/ssh-hosts/$hostId/terminal',
  );
}

enum TerminalEventKind { ready, output, error, closed }

class TerminalEvent {
  const TerminalEvent(this.kind, [this.output = '']);
  final TerminalEventKind kind;
  final String output;
  static TerminalEvent parse(Object? frame) {
    try {
      if (frame is! String ||
          frame.length > terminalMaxMessageBytes ||
          !terminalValidUnicode(frame) ||
          utf8.encode(frame).length > terminalMaxMessageBytes) {
        throw const TerminalException(TerminalFailure.protocol);
      }
      final json = jsonDecode(frame);
      if (json is! Map<String, dynamic> ||
          json['type'] is! String ||
          (json['data'] != null && json['data'] is! String)) {
        throw const TerminalException(TerminalFailure.protocol);
      }
      final data = (json['data'] as String?) ?? '';
      if (!terminalValidUnicode(data)) {
        throw const TerminalException(TerminalFailure.protocol);
      }
      return switch (json['type']) {
        'ready' => const TerminalEvent(TerminalEventKind.ready),
        'output' => TerminalEvent(TerminalEventKind.output, data),
        // Raw server errors can contain SSH addresses or remote output.
        'error' => const TerminalEvent(TerminalEventKind.error),
        'closed' => const TerminalEvent(TerminalEventKind.closed),
        _ => throw const TerminalException(TerminalFailure.protocol),
      };
    } catch (_) {
      throw const TerminalException(TerminalFailure.protocol);
    }
  }

  @override
  String toString() => 'TerminalEvent(${kind.name})';
}

String terminalInputFrame(String text) {
  if (!terminalInputAllowed(text)) {
    throw const TerminalException(TerminalFailure.protocol);
  }
  return jsonEncode({'type': 'input', 'data': text});
}

String terminalResizeFrame(int cols, int rows) {
  if (cols < 1 || cols > 500 || rows < 1 || rows > 300) {
    throw const TerminalException(TerminalFailure.protocol);
  }
  return jsonEncode({'type': 'resize', 'cols': cols, 'rows': rows});
}

/// Pending presentation only; never used for replay or persistence.
class TerminalOutputQueue {
  TerminalOutputQueue({
    this.capacity = terminalMaxMessageBytes,
    this.frameBytes = terminalMaxInputBytes,
  }) : assert(capacity >= 4),
       assert(frameBytes >= 4),
       assert(frameBytes <= capacity);
  final int capacity, frameBytes;
  final Queue<(String, int)> _chunks = Queue();
  int _bytes = 0;
  bool _truncated = false;
  int get pendingBytes => _bytes;
  bool get hasPending => _truncated || _chunks.isNotEmpty;
  void add(String text) {
    if (!terminalValidUnicode(text)) {
      throw const TerminalException(TerminalFailure.protocol);
    }
    // Split without cutting UTF-16 pairs or retaining a giant original string.
    var chunk = StringBuffer();
    var size = 0;
    for (final rune in text.runes) {
      final width = rune <= 0x7f
          ? 1
          : rune <= 0x7ff
          ? 2
          : rune <= 0xffff
          ? 3
          : 4;
      if (size + width > frameBytes) {
        _append(chunk.toString(), size);
        chunk = StringBuffer();
        size = 0;
      }
      chunk.writeCharCode(rune);
      size += width;
    }
    if (size > 0) _append(chunk.toString(), size);
  }

  void _append(String text, int size) {
    while (_bytes + size > capacity && _chunks.isNotEmpty) {
      _bytes -= _chunks.removeFirst().$2;
      _truncated = true;
    }
    _chunks.add((text, size));
    _bytes += size;
  }

  String? take() {
    if (_truncated) {
      _truncated = false;
      return '\r\n[output truncated]\r\n';
    }
    if (_chunks.isEmpty) return null;
    final chunk = _chunks.removeFirst();
    _bytes -= chunk.$2;
    return chunk.$1;
  }

  void clear() {
    _chunks.clear();
    _bytes = 0;
    _truncated = false;
  }
}
