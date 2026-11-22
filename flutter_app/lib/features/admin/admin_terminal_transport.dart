import 'dart:async';
import 'admin_terminal_transport_stub.dart'
    if (dart.library.io) 'admin_terminal_transport_io.dart'
    as platform;

abstract interface class TerminalTransport {
  Future<Stream<Object?>> connect(Uri endpoint, String token);
  void send(String frame);

  /// Irreversible; aborts pending handshakes and queued input as well as reads.
  void abort();
}

TerminalTransport newTerminalTransport() => platform.createTerminalTransport();
