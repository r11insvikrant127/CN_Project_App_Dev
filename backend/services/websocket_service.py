from flask_socketio import SocketIO, join_room

socketio = SocketIO(
    cors_allowed_origins="*",
    async_mode="threading"
)


@socketio.on('join_hostel')
def handle_join_hostel(data):
    """
    Join the Socket.IO room corresponding to the
    authenticated supervisor's hostel.
    """
    try:
        hostel = str(data.get('hostel', '')).strip().upper()

        if not hostel:
            print("❌ WebSocket hostel join failed: hostel missing")
            return

        room = f"hostel_{hostel}"

        join_room(room)

        print(
            f"🔌 WEBSOCKET ROOM JOINED | "
            f"Hostel={hostel} | Room={room}"
        )

    except Exception as e:
        print(
            f"❌ WebSocket hostel join failed: "
            f"{type(e).__name__}: {e}"
        )


def emit_violation_alert(alert_data):
    """
    Send a violation alert only to supervisors
    belonging to the student's hostel.
    """
    try:
        hostel = str(
            alert_data.get('hostel', '')
        ).strip().upper()

        if not hostel:
            print(
                "❌ WebSocket alert not sent: "
                "student hostel missing"
            )
            return

        room = f"hostel_{hostel}"

        socketio.emit(
            'allowed_time_violation',
            alert_data,
            room=room
        )

        print(
            f"🔌 WEBSOCKET VIOLATION ALERT EMITTED | "
            f"Roll={alert_data.get('roll_no')} | "
            f"Hostel={hostel} | "
            f"Room={room}"
        )

    except Exception as e:
        print(
            f"❌ WebSocket alert emission failed: "
            f"{type(e).__name__}: {e}"
        )