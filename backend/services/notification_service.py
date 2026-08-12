# services/notification_service.py
"""
Firebase Cloud Messaging notification service.

Routes notifications to the supervisor responsible
for the student's hostel.
"""

import os
import firebase_admin
from firebase_admin import credentials, messaging
from dotenv import load_dotenv
from utils.db_utils import get_db


load_dotenv()


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


def get_supervisor_topic(hostel):
    """
    Convert a student's hostel into the corresponding
    supervisor FCM topic.

    Hostel A → supervisor_hostel_a
    Hostel B → supervisor_hostel_b
    Hostel C → supervisor_hostel_c
    Hostel D → supervisor_hostel_d
    """

    if not hostel:
        return None

    hostel = str(hostel).strip().upper()

    topic_map = {
        "A": "supervisor_hostel_a",
        "B": "supervisor_hostel_b",
        "C": "supervisor_hostel_c",
        "D": "supervisor_hostel_d",
    }

    return topic_map.get(hostel)


def send_hostel_alert(
    hostel,
    roll_no,
    student_name,
    exceeded_minutes,
):
    """
    Send an allowed-time violation notification
    to the supervisor responsible for the student's hostel.
    """

    initialize_firebase()

    topic = get_supervisor_topic(hostel)

    if not topic:
        print(
            f"⚠️ No supervisor topic found for hostel: {hostel}"
        )
        return None

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
            "hostel": str(hostel),
            "exceeded_minutes": str(exceeded_minutes),
        },
        topic=topic,
    )

    response = messaging.send(message)

    print(
        f"📱 FCM NOTIFICATION SENT | "
        f"Hostel={hostel} | "
        f"Topic={topic} | "
        f"Roll={roll_no} | "
        f"MessageID={response}"
    )

    return response