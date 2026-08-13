from flask import request
from flask_socketio import SocketIO, join_room
from flask_jwt_extended import verify_jwt_in_request, get_jwt_identity

socketio = SocketIO(
    cors_allowed_origins="*",
    async_mode="threading"
)


@socketio.on('join_hostel')
def handle_join_hostel(data):
    """
    Join the Socket.IO room corresponding to the
    authenticated supervisor's hostel.

    The hostel supplied by the client is NOT trusted.
    The server derives the hostel from the authenticated
    supervisor identity.
    """

    try:
        # Verify JWT from the Socket.IO handshake headers.
        verify_jwt_in_request()

        identity_string = get_jwt_identity()

        if not identity_string or ':' not in identity_string:
            print("❌ WebSocket join rejected: invalid JWT identity")
            return

        device_id, user_role = identity_string.split(':', 1)

        print(
            f"🔐 WebSocket join request | "
            f"Role={user_role} | Device={device_id}"
        )

        # Only supervisors are allowed to receive hostel violation alerts.
        if not user_role.startswith('super_'):
            print(
                f"🚫 WebSocket join rejected | "
                f"Role={user_role} is not a supervisor"
            )
            return

        # Expected roles:
        # super_a
        # super_b
        # super_c
        # super_d

        role_parts = user_role.split('_')

        if len(role_parts) != 2:
            print(
                f"❌ WebSocket join rejected: invalid supervisor role "
                f"{user_role}"
            )
            return

        hostel = role_parts[1].strip().upper()

        if hostel not in {'A', 'B', 'C', 'D'}:
            print(
                f"❌ WebSocket join rejected: invalid hostel {hostel}"
            )
            return

        room = f"hostel_{hostel}"

        join_room(room)

        print(
            f"🔌 WEBSOCKET ROOM JOINED | "
            f"Role={user_role} | "
            f"Hostel={hostel} | "
            f"Room={room}"
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