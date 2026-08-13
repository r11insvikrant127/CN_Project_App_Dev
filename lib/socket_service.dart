import 'package:socket_io_client/socket_io_client.dart' as IO;

class SocketService {
  static IO.Socket? _socket;

  /// Connect to the backend WebSocket server.
  static void connect() {
    if (_socket != null && _socket!.connected) {
      print('🔌 WebSocket already connected');
      return;
    }

    _socket = IO.io(
      'https://cn-project-app-dev.onrender.com',
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .enableReconnection()
          .setReconnectionAttempts(10)
          .setReconnectionDelay(2000)
          .build(),
    );

    _socket!.onConnect((_) {
      print('🟢 WebSocket CONNECTED');
      print('Socket ID: ${_socket!.id}');
    });

    _socket!.onDisconnect((_) {
      print('🔴 WebSocket DISCONNECTED');
    });

    _socket!.onConnectError((error) {
      print('❌ WebSocket connection error: $error');
    });

    _socket!.onError((error) {
      print('❌ WebSocket error: $error');
    });

    _socket!.connect();
  }

  /// Listen for violation alerts.
  static void listenForViolationAlerts(
    void Function(dynamic data) callback,
  ) {
    if (_socket == null) {
      print('⚠️ Cannot listen: WebSocket is not initialized');
      return;
    }

    // Prevent duplicate listeners.
    _socket!.off('allowed_time_violation');

    // Register exactly one listener.
    _socket!.on('allowed_time_violation', callback);

    print('👂 WebSocket violation listener registered');
  }

  /// Disconnect the socket.
  static void disconnect() {
    _socket?.off('allowed_time_violation');
    _socket?.disconnect();
    _socket = null;

    print('🔌 WebSocket disconnected');
  }

  static IO.Socket? get socket => _socket;
}