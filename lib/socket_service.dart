import 'package:socket_io_client/socket_io_client.dart' as IO;

class SocketService {
  static IO.Socket? _socket;
  static String? _pendingHostel;

  /// Connect to the backend WebSocket server.
  static void connect({String? hostel,String? accessToken,}) {
    _pendingHostel = hostel?.trim().toUpperCase();

    if (_socket != null && _socket!.connected) {
      print('🔌 WebSocket already connected');

      if (_pendingHostel != null) {
        joinHostel(_pendingHostel!);
      }

      return;
    }
    final Map<String, String> headers = {};

    if (accessToken != null && accessToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $accessToken';
    }
    _socket = IO.io(
      'https://cn-project-app-dev.onrender.com',
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .setExtraHeaders(headers)
          .disableAutoConnect()
          .enableReconnection()
          .setReconnectionAttempts(10)
          .setReconnectionDelay(2000)
          .build(),
    );

    _socket!.onConnect((_) {
      print('🟢 WebSocket CONNECTED');
      print('Socket ID: ${_socket!.id}');

      // Join the authenticated supervisor's hostel room.
      if (_pendingHostel != null) {
        joinHostel(_pendingHostel!);
      }
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

  /// Join the WebSocket room for the supervisor's hostel.
  static void joinHostel(String hostel) {
    if (_socket == null || !_socket!.connected) {
      print('⚠️ Cannot join hostel room: WebSocket is not connected');
      return;
    }

    final normalizedHostel = hostel.trim().toUpperCase();

    _socket!.emit('join_hostel', {
      'hostel': normalizedHostel,
    });

    print(
      '🔌 Requested WebSocket hostel room: '
      'hostel_$normalizedHostel',
    );
  }

  /// Listen for violation alerts.
  static void listenForViolationAlerts(
    void Function(dynamic data) callback,
  ) {
    if (_socket == null) {
      print('⚠️ Cannot listen: WebSocket is not initialized');
      return;
    }

    _socket!.off('allowed_time_violation');
    _socket!.on('allowed_time_violation', callback);

    print('👂 WebSocket violation listener registered');
  }

  /// Disconnect the socket.
  static void disconnect() {
    _socket?.off('allowed_time_violation');
    _socket?.disconnect();
    _socket = null;
    _pendingHostel = null;

    print('🔌 WebSocket disconnected');
  }

  static IO.Socket? get socket => _socket;
}