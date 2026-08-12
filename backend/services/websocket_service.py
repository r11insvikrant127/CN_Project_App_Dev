from flask_socketio import SocketIO

socketio = SocketIO(
    cors_allowed_origins="*",
    async_mode="threading"
)


def emit_violation_alert(alert_data):
    """
    Broadcast a violation alert to all currently connected
    supervisor applications.
    """
    try:
        socketio.emit(
            'violation_alert',
            alert_data
        )

        print(
            f"🔌 WEBSOCKET VIOLATION ALERT EMITTED | "
            f"Roll={alert_data.get('roll_no')}"
        )

    except Exception as e:
        print(
            f"❌ WebSocket alert emission failed: "
            f"{type(e).__name__}: {e}"
        )