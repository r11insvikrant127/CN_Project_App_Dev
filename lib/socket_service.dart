import 'package:socket_io_client/socket_io_client.dart' as IO;

class SocketService {
  static IO.Socket? _socket;
  static String? _pendingHostel;
  static String? _accessToken;

  /// Connect to the backend WebSocket server.
  ///
  /// The JWT is sent as an Authorization header during
  /// the Socket.IO handshake so Flask-JWT-Extended can
  /// authenticate the connection.
  static void connect({
    String? hostel,
    String? accessToken,
  }) {
    _pendingHostel = hostel?.trim().toUpperCase();
    _accessToken = accessToken;

    if (_socket != null && _socket!.connected) {
      print('🔌 WebSocket already connected');

      if (_pendingHostel != null) {
        joinHostel(_pendingHostel!);
      }

      return;
    }

    if (_accessToken == null || _accessToken!.isEmpty) {
      print('❌ WebSocket connection rejected: JWT access token missing');
      return;
    }

    _socket = IO.io(
      'https://cn-project-app-dev.onrender.com',
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .setExtraHeaders({
            'Authorization': 'Bearer $_accessToken',
          })
          .disableAutoConnect()
          .enableReconnection()
          .setReconnectionAttempts(10)
          .setReconnectionDelay(2000)
          .build(),
    );

    _socket!.onConnect((_) {
      print('🟢 WebSocket CONNECTED');
      print('Socket ID: ${_socket!.id}');

      // The backend derives the hostel from the JWT.
      // The client hostel is only used as a local indication.
      if (_pendingHostel != null) {
        joinHostel(_pendingHostel!);
      }
    });

    _socket!.onDisconnect((reason) {
      print('🔴 WebSocket DISCONNECTED | Reason=$reason');
    });

    _socket!.onConnectError((error) {
      print('❌ WebSocket connection error: $error');
    });

    _socket!.onError((error) {
      print('❌ WebSocket error: $error');
    });

    _socket!.connect();
  }

  /// Request to join the supervisor's hostel room.
  ///
  /// IMPORTANT:
  /// The backend does NOT trust the hostel sent here.
  /// It derives the hostel from the authenticated JWT.
  static void joinHostel(String hostel) {
    if (_socket == null || !_socket!.connected) {
      print(
        '⚠️ Cannot join hostel room: '
        'WebSocket is not connected',
      );
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

  /// Listen for allowed-time violation alerts.
  static void listenForViolationAlerts(
    void Function(dynamic data) callback,
  ) {
    if (_socket == null) {
      print(
        '⚠️ Cannot listen: WebSocket is not initialized',
      );
      return;
    }

    _socket!.off('allowed_time_violation');
    _socket!.on(
      'allowed_time_violation',
      callback,
    );

    print(
      '👂 WebSocket violation listener registered',
    );
  }

  /// Disconnect the socket.
  static void disconnect() {
    _socket?.off('allowed_time_violation');
    _socket?.disconnect();

    _socket = null;
    _pendingHostel = null;
    _accessToken = null;

    print('🔌 WebSocket disconnected');
  }

  static IO.Socket? get socket => _socket;
}