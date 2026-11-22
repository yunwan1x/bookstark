import 'admin_terminal_controller.dart';
import 'admin_terminal_transport.dart';

abstract interface class AdminTerminalSessionAccess {
  int get scrollbackLines;
  AdminTerminalController create({
    TerminalTransport Function()? transportFactory,
  });
  void dispose();
}
