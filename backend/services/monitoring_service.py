# services/monitoring_service.py
"""
Monitoring Service - Proactive monitoring of student checkouts
"""

from datetime import datetime, timedelta, timezone
from bson import ObjectId
from services.notification_service import send_hostel_alert
from services.websocket_service import emit_violation_alert
from services.websocket_service import socketio

# Import utils
import sys
import os
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from utils.time_utils import INDIA_TZ, get_ist_now, normalize_datetime_to_ist
from utils.db_utils import get_db


def create_active_checkout(roll_no, student, out_time, user_role, offline_sync=False, db=None):
    """
    Create/update an active checkout record for proactive allowed-time monitoring.
    
    This does NOT replace students.in_out_records.
    It only stores currently active OUT sessions.
    """
    if db is None:
        db = get_db()
    
    if db is None:
        print("⚠️ Cannot create active checkout - database unavailable")
        return None
    
    try:
        # Get student's custom allowed time (default 480 minutes)
        allowed_minutes = float(student.get('custom_allowed_time_minutes', 480))
        
        # Normalize times to IST
        out_time = normalize_datetime_to_ist(out_time)
        deadline = out_time + timedelta(minutes=allowed_minutes)
        
        active_checkout = {
            'roll_no': roll_no,
            'student_name': student.get('name', 'Unknown'),
            'student_hostel': student.get('hostel', 'Unknown'),
            'out_time': out_time,
            'allowed_minutes': allowed_minutes,
            'deadline': deadline,
            'status': 'active',
            'alert_sent': False,
            'recorded_by': user_role,
            'offline_sync': offline_sync,
            'created_at': get_ist_now(),
            'updated_at': get_ist_now()
        }
        
        db.active_checkouts.update_one(
            {'roll_no': roll_no},
            {'$set': active_checkout},
            upsert=True
        )
        
        print(f"⏱️ ACTIVE CHECKOUT CREATED | Roll: {roll_no} | Deadline: {deadline}")
        return active_checkout
        
    except Exception as e:
        print(f"❌ Error creating active checkout for {roll_no}: {e}")
        return None


def monitor_active_checkouts(db=None):
    """
    Proactively monitor students who are currently outside.
    
    If the allowed deadline has passed:
    1. Mark the checkout as a violation.
    2. Create a disciplinary record.
    3. Create a realtime alert.
    4. Store the IDs in the active checkout for later finalization.
    """
    if db is None:
        db = get_db()
    
    if db is None:
        print("⚠️ Monitoring skipped - database unavailable")
        return
    
    try:
        print(f"🔄 ACTIVE CHECKOUT MONITOR RUNNING | {get_ist_now()}")
        
        # Use UTC for database comparison
        now_utc = datetime.now(timezone.utc).replace(tzinfo=None)
        print(f"🕒 MONITOR TIME | UTC={now_utc} | IST={get_ist_now()}")
        
        # Get all active checkouts
        active_checkouts = list(db.active_checkouts.find({'status': {'$in': ['active', 'violation']}}))
        print(f"📊 TOTAL ACTIVE CHECKOUTS: {len(active_checkouts)}")
        
        if not active_checkouts:
            print("ℹ️ No students currently outside.")
            return
        
        # Check each active checkout
        for checkout in active_checkouts:
            _check_single_checkout(checkout, now_utc, db)
            
    except Exception as e:
        print(f"❌ ERROR IN ACTIVE CHECKOUT MONITORING | {type(e).__name__}: {e}")


def _check_single_checkout(checkout, now_utc, db):
    """Check a single checkout for violation"""
    roll_no = checkout.get('roll_no')
    if checkout.get('status') == 'violation':
        print(
            f"   ⚠️ Already violated | Roll={roll_no} | "
            f"Waiting for check-in"
        )
        return
    deadline = checkout.get('deadline')
    out_time = checkout.get('out_time')
    allowed_minutes = float(checkout.get('allowed_minutes', 480))
    
    if deadline is None:
        print(f"⚠️ No deadline found for {roll_no}. Skipping.")
        return
    
    # Normalize deadline for comparison
    if deadline.tzinfo is not None:
        deadline_utc = deadline.astimezone(timezone.utc).replace(tzinfo=None)
    else:
        deadline_utc = deadline
    
    # Check if deadline has passed
    if now_utc < deadline_utc:
        remaining_seconds = (deadline_utc - now_utc).total_seconds()
        print(f"   ✅ Still within allowed time | Remaining={round(remaining_seconds, 1)} sec")
        return
    
    # ============================================================
    # DEADLINE EXCEEDED - Process violation
    # ============================================================
    print(f"🚨 DEADLINE EXCEEDED | Student={roll_no}")
    
    # Atomically claim the violation
    claim_result = db.active_checkouts.update_one(
        {
            '_id': checkout['_id'],
            'status': 'active',
            'alert_sent': False
        },
        {
            '$set': {
                'status': 'violation',
                'alert_sent': True,
                'alert_sent_at': now_utc,
                'updated_at': now_utc
            }
        }
    )
    
    if claim_result.modified_count != 1:
        print(f"⚠️ Violation already processed for {roll_no}. Skipping.")
        return
    
    # Calculate exceeded time
    if out_time is None:
        print(f"⚠️ No out_time found for {roll_no}. Skipping disciplinary calculation.")
        return
    
    # Normalize out_time
    if out_time.tzinfo is not None:
        out_time_utc = out_time.astimezone(timezone.utc).replace(tzinfo=None)
    else:
        out_time_utc = out_time
    
    actual_minutes = (now_utc - out_time_utc).total_seconds() / 60
    exceeded_minutes = max(0, round(actual_minutes - allowed_minutes, 2))
    
    print(f"⏰ TIME VIOLATION | Roll={roll_no} | Exceeded={exceeded_minutes} min")
    
    # ============================================================
    # CREATE DISCIPLINARY RECORD WITH ID
    # ============================================================
    disciplinary_record_id = _create_disciplinary_record(
        roll_no, out_time_utc, allowed_minutes, 
        exceeded_minutes, checkout, now_utc, db
    )
    
    # ============================================================
    # CREATE REALTIME ALERT WITH ID
    # ============================================================
    alert_id = _create_violation_alert(
        roll_no, checkout, out_time_utc, allowed_minutes, 
        exceeded_minutes, now_utc, db
    )

    # ============================================================
    # SEND REAL-TIME WEBSOCKET ALERT
    # ============================================================
    try:
        socketio.emit(
            'allowed_time_violation',
            {
                'type': 'allowed_time_violation',
                'roll_no': str(roll_no),
                'student_name': checkout.get('student_name', 'Unknown'),
                'hostel': checkout.get('student_hostel', 'Unknown'),
                'out_time': out_time_utc.isoformat(),
                'deadline': checkout.get('deadline').isoformat()
                    if checkout.get('deadline') else None,
                'allowed_minutes': allowed_minutes,
                'exceeded_minutes': exceeded_minutes,
                'alert_id': str(alert_id) if alert_id else None,
                'timestamp': now_utc.isoformat(),
            }
        )

        print(
            f"⚡ WEBSOCKET ALERT SENT | "
            f"Roll={roll_no} | "
            f"Event=allowed_time_violation"
        )

    except Exception as e:
        print(
            f"❌ WebSocket alert failed for {roll_no}: "
            f"{type(e).__name__}: {e}"
        )

    # ============================================================
    # SEND HOSTEL-SPECIFIC FCM NOTIFICATION
    # ============================================================
    try:
        send_hostel_alert(
            hostel=checkout.get('student_hostel'),
            roll_no=roll_no,
            student_name=checkout.get('student_name', 'Unknown'),
            exceeded_minutes=exceeded_minutes
        )
    except Exception as e:
        print(
            f"❌ FCM notification failed for {roll_no}: "
            f"{type(e).__name__}: {e}"
        )
        
    # ============================================================
    # SEND REAL-TIME WEBSOCKET ALERT
    # ============================================================
    try:
        emit_violation_alert({
            'type': 'allowed_time_violation',
            'roll_no': str(roll_no),
            'student_name': str(
                checkout.get('student_name', 'Unknown')
            ),
            'hostel': str(
                checkout.get('student_hostel', 'Unknown')
            ),
            'out_time': str(out_time_utc),
            'allowed_minutes': allowed_minutes,
            'deadline': str(checkout.get('deadline')),
            'exceeded_minutes': exceeded_minutes,
            'priority': 'high',
        })
    except Exception as e:
        print(
            f"❌ WebSocket notification failed for {roll_no}: "
            f"{type(e).__name__}: {e}"
        )


    # ============================================================
    # STORE IDs IN ACTIVE CHECKOUT FOR FINALIZATION
    # ============================================================
    if disciplinary_record_id or alert_id:
        update_data = {'updated_at': now_utc}
        if disciplinary_record_id:
            update_data['disciplinary_record_id'] = disciplinary_record_id
        if alert_id:
            update_data['alert_id'] = alert_id
        if exceeded_minutes>0:
            update_data['proactive_exceeded_minutes'] = exceeded_minutes
        
        db.active_checkouts.update_one(
            {'_id': checkout['_id']},
            {'$set': update_data}
        )
        
        print(
            f"💾 STORED IDs IN ACTIVE CHECKOUT | "
            f"Roll={roll_no} | "
            f"DisciplinaryID={disciplinary_record_id} | "
            f"AlertID={alert_id} | "
            f"Exceeded={exceeded_minutes:.2f}"
        )
    
    print(f"🚨 PROACTIVE VIOLATION COMPLETE | Student={roll_no} | Exceeded={exceeded_minutes} min")


def _create_disciplinary_record(roll_no, out_time_utc, allowed_minutes, 
                                exceeded_minutes, checkout, now_utc, db):
    """
    Create a disciplinary record for time violation.
    Returns the ObjectId of the created record.
    """
    # ============================================================
    # FIX: Create ID explicitly before inserting
    # ============================================================
    disciplinary_record_id = ObjectId()
    
    disciplinary_record = {
        '_id': disciplinary_record_id,  # Explicit ID
        'date': now_utc,
        'time': get_ist_now().strftime('%H:%M'),
        'description': (
            f'Exceeded allowed time outside by {exceeded_minutes} minutes. '
            f'Out at: {out_time_utc.strftime("%Y-%m-%d %H:%M")}, '
            f'Allowed: {allowed_minutes} minutes'
        ),
        'action_taken': f'Warning issued for exceeding {allowed_minutes}-minute limit',
        'recorded_by': 'system_monitor',
        'recorded_at': now_utc,
        'time_exceeded_minutes': exceeded_minutes,
        'proactive_exceeded_minutes': exceeded_minutes,  # Store initial value
        'final_exceeded_minutes': exceeded_minutes,  # Will be updated on check-in
        'actual_duration_minutes': None,  # Will be updated on check-in
        'auto_generated': True,
        'proactive_monitoring': True,
        'allowed_time_limit': allowed_minutes,
        'violation_status': 'pending_confirmation',  # Critical for tracking
        'detection_method': 'proactive_monitoring',
        'out_time': out_time_utc,
        'in_time': None,  # Will be set on check-in
        'finalized_at': None  # Will be set on check-in
    }
    
    db.students.update_one(
        {'roll_no': roll_no},
        {'$push': {'disciplinary_records': disciplinary_record}}
    )
    
    print(
        f"📝 DISCIPLINARY RECORD CREATED | "
        f"Roll={roll_no} | "
        f"ID={disciplinary_record_id} | "
        f"Exceeded={exceeded_minutes:.2f} min"
    )
    
    return disciplinary_record_id


def _create_violation_alert(roll_no, checkout, out_time_utc, allowed_minutes, 
                            exceeded_minutes, now_utc, db):
    """
    Create a realtime alert for time violation.
    Returns the ObjectId of the created alert.
    """
    alert_message = {
        'type': 'allowed_time_violation',
        'message': f'🚨 Student {roll_no} exceeded allowed time outside',
        'details': {
            'roll_no': roll_no,
            'student_name': checkout.get('student_name', 'Unknown'),
            'student_hostel': checkout.get('student_hostel', 'Unknown'),
            'out_time': out_time_utc,
            'allowed_minutes': allowed_minutes,
            'deadline': checkout.get('deadline'),
            'exceeded_minutes': exceeded_minutes,
            'proactive_exceeded_minutes': exceeded_minutes,
            'final_exceeded_minutes': None,  # Will be updated on check-in
            'actual_duration_minutes': None,  # Will be updated on check-in
            'violation_status': 'pending_confirmation',
            'in_time': None
        },
        'timestamp': now_utc,
        'priority': 'high',
        'auto_generated': True,
        'proactive_monitoring': True,
        'finalized_at': None
    }
    
    result = db.realtime_alerts.insert_one(alert_message)
    alert_id = result.inserted_id
    
    print(
        f"🔔 REALTIME ALERT CREATED | "
        f"Roll={roll_no} | "
        f"AlertID={alert_id}"
    )
    
    return alert_id


def cleanup_stale_checkouts(hours=24, db=None):
    """
    Clean up stale active checkouts that are older than specified hours
    """
    if db is None:
        db = get_db()
    
    if db is None:
        return
    
    cutoff_time = get_ist_now() - timedelta(hours=hours)
    
    result = db.active_checkouts.delete_many({
        'created_at': {'$lt': cutoff_time},
        'status': 'active'
    })
    
    if result.deleted_count > 0:
        print(f"🧹 Cleaned up {result.deleted_count} stale checkouts")
    
    return result.deleted_count