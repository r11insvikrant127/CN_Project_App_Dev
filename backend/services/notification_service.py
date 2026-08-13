# services/notification_service.py
"""
Firebase Cloud Messaging notification service.

Responsibilities:
1. Initialize Firebase Admin SDK.
2. Register/update FCM tokens for authenticated devices.
3. Find the supervisor responsible for a student's hostel.
4. Find that supervisor's registered device.
5. Send allowed-time violation notifications only to that device.

Admin users are intentionally excluded from violation notifications.
"""

import os

import firebase_admin
from firebase_admin import credentials, messaging

from dotenv import load_dotenv

from utils.db_utils import get_db


load_dotenv()


# ============================================================
# FIREBASE INITIALIZATION
# ============================================================

def initialize_firebase():
    """
    Initialize Firebase Admin SDK once.
    """

    if firebase_admin._apps:
        return

    credentials_path = os.getenv("FIREBASE_CREDENTIALS_PATH")

    if not credentials_path:
        raise RuntimeError(
            "FIREBASE_CREDENTIALS_PATH is not configured"
        )

    if not os.path.exists(credentials_path):
        raise FileNotFoundError(
            f"Firebase credentials file not found: {credentials_path}"
        )

    cred = credentials.Certificate(credentials_path)

    firebase_admin.initialize_app(cred)

    print("🔥 Firebase Admin SDK initialized successfully")


# ============================================================
# SUPERVISOR LOOKUP
# ============================================================

def get_supervisor_for_hostel(hostel):
    """
    Find the supervisor responsible for a hostel.

    Example:

        Hostel A → super_a
        Hostel B → super_b
        Hostel C → super_c
        Hostel D → super_d

    Returns the supervisor MongoDB document or None.
    """

    if not hostel:
        return None

    normalized_hostel = str(hostel).strip().upper()

    if normalized_hostel not in {"A", "B", "C", "D"}:
        print(
            f"⚠️ Invalid hostel for supervisor lookup: "
            f"{normalized_hostel}"
        )
        return None

    db = get_db()

    supervisor = db.users.find_one(
        {
            "role": "super",
            "hostel": normalized_hostel
        }
    )

    if not supervisor:
        print(
            f"⚠️ No supervisor found for Hostel "
            f"{normalized_hostel}"
        )
        return None

    return supervisor


# ============================================================
# DEVICE LOOKUP
# ============================================================

def get_supervisor_device(hostel):
    """
    Find the active device belonging to the supervisor
    responsible for the specified hostel.

    Returns the device MongoDB document or None.
    """

    supervisor = get_supervisor_for_hostel(hostel)

    if not supervisor:
        return None

    device_id = supervisor.get("device_id")

    if not device_id:
        print(
            f"⚠️ Supervisor {supervisor.get('username')} "
            f"has no device_id assigned"
        )
        return None

    db = get_db()

    device = db.devices.find_one(
        {
            "device_id": device_id,
            "status": "active"
        }
    )

    if not device:
        print(
            f"⚠️ Supervisor device not found or inactive | "
            f"Supervisor={supervisor.get('username')} | "
            f"Device={device_id}"
        )
        return None

    return device


# ============================================================
# FCM TOKEN REGISTRATION
# ============================================================

def register_fcm_token(device_id, fcm_token):
    """
    Store/update the FCM registration token for a registered device.

    The caller must already have authenticated the device.
    This function only updates the devices collection.
    """

    if not device_id:
        raise ValueError("device_id is required")

    if not fcm_token:
        raise ValueError("fcm_token is required")

    db = get_db()

    # Make sure the device exists and is active.
    device = db.devices.find_one(
        {
            "device_id": device_id,
            "status": "active"
        }
    )

    if not device:
        print(
            f"⚠️ Cannot register FCM token. "
            f"Device not found/inactive: {device_id}"
        )
        return False

    result = db.devices.update_one(
        {
            "device_id": device_id
        },
        {
            "$set": {
                "fcm_token": fcm_token
            }
        }
    )

    print(
        f"📱 FCM TOKEN REGISTERED | "
        f"Device={device_id} | "
        f"Modified={result.modified_count}"
    )

    return True


# ============================================================
# SEND HOSTEL-SPECIFIC FCM NOTIFICATION
# ============================================================

def send_hostel_alert(
    hostel,
    roll_no,
    student_name,
    exceeded_minutes,
):
    """
    Send an allowed-time violation notification ONLY to the
    supervisor responsible for the student's hostel.

    Routing:

        Student Hostel
              ↓
        users collection
              ↓
        supervisor
              ↓
        device_id
              ↓
        devices collection
              ↓
        fcm_token
              ↓
        FCM device notification

    Admin users are never selected by this function.
    """

    initialize_firebase()

    normalized_hostel = (
        str(hostel).strip().upper()
        if hostel
        else ""
    )

    if normalized_hostel not in {"A", "B", "C", "D"}:
        print(
            f"⚠️ FCM notification skipped. "
            f"Invalid hostel: {hostel}"
        )
        return None

    # --------------------------------------------------------
    # Find responsible supervisor
    # --------------------------------------------------------

    supervisor = get_supervisor_for_hostel(
        normalized_hostel
    )

    if not supervisor:
        print(
            f"⚠️ FCM notification skipped. "
            f"No supervisor for Hostel {normalized_hostel}"
        )
        return None

    # Explicit safety check:
    # only role=super is allowed here.
    if supervisor.get("role") != "super":
        print(
            f"🚫 FCM notification blocked. "
            f"Selected user is not a supervisor: "
            f"{supervisor.get('username')}"
        )
        return None

    # --------------------------------------------------------
    # Find supervisor's active device
    # --------------------------------------------------------

    device_id = supervisor.get("device_id")

    if not device_id:
        print(
            f"⚠️ FCM notification skipped | "
            f"Supervisor={supervisor.get('username')} | "
            f"Hostel={normalized_hostel} | "
            f"No device_id assigned"
        )
        return None

    db = get_db()

    device = db.devices.find_one(
        {
            "device_id": device_id,
            "status": "active"
        }
    )

    if not device:
        print(
            f"⚠️ FCM notification skipped | "
            f"Supervisor={supervisor.get('username')} | "
            f"Device={device_id} | "
            f"Device not found/inactive"
        )
        return None

    # --------------------------------------------------------
    # Get FCM token
    # --------------------------------------------------------

    fcm_token = device.get("fcm_token")

    if not fcm_token:
        print(
            f"⚠️ FCM notification skipped | "
            f"Supervisor={supervisor.get('username')} | "
            f"Hostel={normalized_hostel} | "
            f"Device={device_id} | "
            f"No FCM token registered"
        )
        return None

    # --------------------------------------------------------
    # Build notification
    # --------------------------------------------------------

    title = "🚨 Allowed Time Exceeded"

    body = (
        f"Student {student_name} ({roll_no}) "
        f"has exceeded the allowed time outside "
        f"by {exceeded_minutes:.2f} minutes."
    )

    message = messaging.Message(
        notification=messaging.Notification(
            title=title,
            body=body,
        ),
        data={
            "type": "allowed_time_violation",
            "roll_no": str(roll_no),
            "student_name": str(student_name),
            "hostel": normalized_hostel,
            "exceeded_minutes": str(exceeded_minutes),
            "supervisor": str(
                supervisor.get("username", "")
            ),
        },
        token=fcm_token,
    )

    # --------------------------------------------------------
    # Send directly to supervisor's device
    # --------------------------------------------------------

    response = messaging.send(message)

    print(
        f"📱 FCM NOTIFICATION SENT | "
        f"Hostel={normalized_hostel} | "
        f"Supervisor={supervisor.get('username')} | "
        f"Device={device_id} | "
        f"Roll={roll_no} | "
        f"MessageID={response}"
    )

    return response