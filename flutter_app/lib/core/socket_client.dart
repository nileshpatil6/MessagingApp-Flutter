import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'constants.dart';

class SocketClient {
  static SocketClient? _instance;
  IO.Socket? _socket;

  SocketClient._();

  static SocketClient get instance {
    _instance ??= SocketClient._();
    return _instance!;
  }

  IO.Socket get socket {
    _socket ??= IO.io(
      AppConstants.serverUrl,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .build(),
    );
    return _socket!;
  }

  void connect() {
    if (!socket.connected) {
      socket.connect();
    }
  }

  void disconnect() {
    socket.disconnect();
  }

  bool get isConnected => socket.connected;

  void emit(String event, dynamic data) {
    socket.emit(event, data);
  }

  void on(String event, Function(dynamic) handler) {
    socket.on(event, handler);
  }

  void off(String event, [void Function(dynamic)? handler]) {
    if (handler != null) {
      socket.off(event, handler);
    } else {
      socket.off(event);
    }
  }
}
