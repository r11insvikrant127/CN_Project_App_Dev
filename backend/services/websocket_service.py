from flask import request
from flask_socketio import SocketIO, join_room
from flask_jwt_extended import verify_jwt_in_request, get_jwt_identity

socketio = SocketIO(
    cors_allowed_origins="*",
    async_mode="threading"
)

VALID_HOSTELS = {'A', 'B', 'C', 'D'}
ADMIN_ROOM = 'admin_all'


@socketio.on('join_hostel')
def handle_join_hostel(data):
    """
    Authenticate the Socket.IO connection using the JWT.

    Supervisor:
        super_a -> hostel_A
        super_b -> hostel_B
        super_c -> hostel_C
        super_d -> hostel_D

    Admin:
        admin -> admin_all

    The hostel supplied by the client is NOT trusted.
    The server derives the authorized room from the JWT role.
    """

    try:
        verify_jwt_in_request()

        identity_string = get_jwt_identity()

        if not identity_string or ':' not in identity_string:
            print(
                "❌ WebSocket join rejected: invalid JWT identity"
            )
            return

        device_id, user_role = identity_string.split(':', 1)

        user_role = user_role.strip().lower()

        print(
            f"🔐 WebSocket join request | "
            f"Role={user_role} | Device={device_id}"
        )

        # =========================================================
        # ADMIN
        # =========================================================
        if user_role == 'admin':
            join_room(ADMIN_ROOM)

            print(
                f"🔌 WEBSOCKET ADMIN ROOM JOINED | "
                f"Role=admin | "
                f"Device={device_id} | "
                f"Room={ADMIN_ROOM}"
            )

            return

        # =========================================================
        # SUPERVISORS
        # =========================================================
        if not user_role.startswith('super_'):
            print(
                f"🚫 WebSocket join rejected | "
                f"Role={user_role} is not authorized"
            )
            return

        role_parts = user_role.split('_')

        if len(role_parts) != 2:
            print(
                f"❌ WebSocket join rejected: "
                f"invalid supervisor role {user_role}"
            )
            return

        hostel = role_parts[1].strip().upper()

        if hostel not in VALID_HOSTELS:
            print(
                f"❌ WebSocket join rejected: "
                f"invalid hostel {hostel}"
            )
            return

        room = f"hostel_{hostel}"

        join_room(room)

        print(
            f"🔌 WEBSOCKET SUPERVISOR ROOM JOINED | "
            f"Role={user_role} | "
            f"Hostel={hostel} | "
            f"Room={room} | "
            f"Device={device_id}"
        )

    except Exception as e:
        print(
            f"❌ WebSocket hostel join failed: "
            f"{type(e).__name__}: {e}"
        )


def emit_violation_alert(alert_data):
    """
    Send violation WebSocket event to:

    1. The supervisor room belonging to the student's hostel.
    2. The admin_all room.

    FCM is handled separately and is NOT affected here.
    """

    try:
        hostel = str(
            alert_data.get('hostel', '')
        ).strip().upper()

        if hostel not in VALID_HOSTELS:
            print(
                "❌ WebSocket violation alert not sent: "
                f"invalid/missing hostel={hostel}"
            )
            return

        supervisor_room = f"hostel_{hostel}"

        # Supervisor of that hostel
        socketio.emit(
            'allowed_time_violation',
            alert_data,
            room=supervisor_room
        )

        # Admin
        socketio.emit(
            'allowed_time_violation',
            alert_data,
            room=ADMIN_ROOM
        )

        print(
            f"🔌 WEBSOCKET VIOLATION ALERT EMITTED | "
            f"Roll={alert_data.get('roll_no')} | "
            f"Hostel={hostel} | "
            f"SupervisorRoom={supervisor_room} | "
            f"AdminRoom={ADMIN_ROOM}"
        )

    except Exception as e:
        print(
            f"❌ WebSocket violation alert emission failed: "
            f"{type(e).__name__}: {e}"
        )


def emit_movement_update(movement_data):
    """
    Send student movement update to:

    1. Supervisor assigned to the student's hostel.
    2. Admin.

    Supervisors never receive another hostel's update.
    """

    try:
        hostel = str(
            movement_data.get('hostel', '')
        ).strip().upper()

        if hostel not in VALID_HOSTELS:
            print(
                "❌ WebSocket movement update not sent: "
                f"invalid/missing hostel={hostel}"
            )
            return

        supervisor_room = f"hostel_{hostel}"

        # Supervisor of student's hostel
        socketio.emit(
            'student_movement_updated',
            movement_data,
            room=supervisor_room
        )

        # Admin receives all hostel updates
        socketio.emit(
            'student_movement_updated',
            movement_data,
            room=ADMIN_ROOM
        )

        print(
            f"🔌 WEBSOCKET MOVEMENT UPDATE EMITTED | "
            f"Roll={movement_data.get('roll_no')} | "
            f"Action={movement_data.get('action')} | "
            f"Hostel={hostel} | "
            f"SupervisorRoom={supervisor_room} | "
            f"AdminRoom={ADMIN_ROOM}"
        )

    except Exception as e:
        print(
            f"❌ WebSocket movement update emission failed: "
            f"{type(e).__name__}: {e}"
        )