import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'admin_terminal_protocol.dart';
import 'admin_terminal_transport.dart';

TerminalTransport createTerminalTransport() => IoTerminalTransport();

/// One dedicated client and one socket, with an explicit no-redirect handshake.
/// Account client/cookies are never passed to the terminal WebView.
class IoTerminalTransport implements TerminalTransport {
  IoTerminalTransport({HttpClient Function()? clientFactory})
    : _clientFactory = clientFactory ?? HttpClient.new;
  final HttpClient Function() _clientFactory;
  HttpClient? _client;
  Socket? _raw;
  WebSocket? _socket;
  bool _aborted = false, _started = false;
  @override
  Future<Stream<Object?>> connect(Uri endpoint, String token) async {
    if (_started || _aborted) {
      throw const TerminalException(TerminalFailure.closed);
    }
    _started = true;
    if (!{'ws', 'wss'}.contains(endpoint.scheme) ||
        endpoint.host.isEmpty ||
        endpoint.userInfo.isNotEmpty ||
        endpoint.hasQuery ||
        endpoint.hasFragment ||
        token.isEmpty ||
        !RegExp(r'^[\x21-\x2b\x2d-\x3a\x3c-\x7e]+$').hasMatch(token)) {
      throw const TerminalException(TerminalFailure.protocol);
    }
    final httpUri = endpoint.replace(
      scheme: endpoint.scheme == 'wss' ? 'https' : 'http',
    );
    final client = _clientFactory();
    _client = client;
    client.connectionTimeout = const Duration(seconds: 15);
    client.findProxy = (_) => 'DIRECT';
    final nonce = base64.encode(
      List.generate(16, (_) => Random.secure().nextInt(256)),
    );
    try {
      final request = await client
          .openUrl('GET', httpUri)
          .timeout(const Duration(seconds: 15));
      _check();
      request.followRedirects = false;
      request.maxRedirects = 0;
      request.headers
        ..set(HttpHeaders.connectionHeader, 'Upgrade')
        ..set(HttpHeaders.upgradeHeader, 'websocket')
        ..set('Sec-WebSocket-Version', '13')
        ..set('Sec-WebSocket-Key', nonce)
        ..set('origin', httpUri.origin)
        ..set(HttpHeaders.cookieHeader, 'token=$token');
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      _check();
      if (response.statusCode != HttpStatus.switchingProtocols) {
        throw TerminalException(
          {401, 403}.contains(response.statusCode)
              ? TerminalFailure.unauthorized
              : TerminalFailure.network,
        );
      }
      final accept = base64.encode(
        sha1
            .convert(
              utf8.encode('${nonce}258EAFA5-E914-47DA-95CA-C5AB0DC85B11'),
            )
            .bytes,
      );
      final connections =
          response.headers[HttpHeaders.connectionHeader]
              ?.join(',')
              .toLowerCase()
              .split(',')
              .map((v) => v.trim()) ??
          <String>[];
      if (response.headers.value(HttpHeaders.upgradeHeader)?.toLowerCase() !=
              'websocket' ||
          !connections.contains('upgrade') ||
          response.headers.value('Sec-WebSocket-Accept') != accept ||
          response.headers['Sec-WebSocket-Protocol'] != null ||
          response.headers['Sec-WebSocket-Extensions'] != null) {
        throw const TerminalException(TerminalFailure.protocol);
      }
      final raw = await response
          .detachSocket()
          .then((socket) {
            if (_aborted) {
              socket.destroy();
              throw const TerminalException(TerminalFailure.closed);
            }
            return socket;
          })
          .timeout(const Duration(seconds: 5));
      // A background transition could happen while detachSocket completes.
      if (_aborted) {
        raw.destroy();
        throw const TerminalException(TerminalFailure.closed);
      }
      _raw = raw;
      final socket = WebSocket.fromUpgradedSocket(
        raw,
        serverSide: false,
        compression: CompressionOptions.compressionOff,
        maxPayloadLength: terminalMaxMessageBytes,
      );
      _socket = socket;
      return socket;
    } catch (error) {
      abort();
      if (error is TerminalException) rethrow;
      throw const TerminalException(TerminalFailure.network);
    }
  }

  void _check() {
    if (_aborted) throw const TerminalException(TerminalFailure.closed);
  }

  @override
  void send(String frame) {
    _check();
    final socket = _socket;
    if (socket == null || socket.readyState != WebSocket.open) {
      throw const TerminalException(TerminalFailure.closed);
    }
    socket.add(frame);
  }

  @override
  void abort() {
    if (_aborted) return;
    _aborted = true;
    // Destroy rather than drain a close future: pending commands must not leak.
    _raw?.destroy();
    _raw = null;
    _socket = null;
    _client?.close(force: true);
    _client = null;
  }
}
