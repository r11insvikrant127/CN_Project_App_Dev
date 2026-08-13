# services/movement_service.py
"""
Movement Service - Handles all student check-in/check-out operations
Extracted from backend.py for better maintainability
"""

from datetime import datetime, timezone

# Import utils
import sys
import os
import uuid
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from utils.time_utils import INDIA_TZ,get_ist_now, normalize_datetime_to_ist, calculate_duration_minutes
from utils.db_utils import get_db

# Import monitoring service for active checkout
from services.monitoring_service import create_active_checkout


def process_security_scan(user_role, data, db=None):
    """
    Process a security scan (check-in or check-out)
    
    Args:
        user_role: The role of the user performing the scan (e.g., 'security_a')
        data: Request data containing roll_no, action, etc.
        db: Database connection (optional, will get from utils if None)
    
    Returns:
        tuple: (response_data, status_code)
    """
    if db is None:
        db = get_db()
    
    # Extract data
    roll_no = data.get('roll_no')
    action = data.get('action')  # 'in' or 'out'
    is_offline_sync = data.get('offline_sync', False)
    original_timestamp = data.get('original_timestamp')
    
    # Get user's hostel from role
    user_hostel = user_role.split('_')[1].upper() if '_' in user_role else 'ALL'
    
    # Validate required fields
    if not roll_no:
        return {'message': 'Roll number is required'}, 400
    
    if action not in ['in', 'out']:
        return {'message': 'Invalid action. Must be "in" or "out"'}, 400
    
    # Get student from database
    student = db.students.find_one({'roll_no': roll_no})
    
    if not student:
        return {'message': 'Student not found'}, 404
    
    # Check hostel access for IN scans (OUT scans allowed from any hostel)
    if action == 'in' and '_' in user_role and student.get('hostel') != user_hostel:
        return {
            'message': 'This student does not belong to your hostel',
            'student_hostel': student.get('hostel'),
            'user_hostel': user_hostel,
            'access_denied': True
        }, 403
    
    # Determine current time (handle offline sync)
    if is_offline_sync and original_timestamp:
        # Convert UTC timestamp to IST
        utc_time = datetime.fromtimestamp(original_timestamp / 1000, tz=timezone.utc)
        now = utc_time.astimezone(INDIA_TZ)
    else:
        now = get_ist_now()
    
    # Process based on action
    if action == 'out':
        return _process_check_out(student, roll_no, now, user_role, is_offline_sync, db)
    elif action == 'in':
        return _process_check_in(student, roll_no, now, user_role, is_offline_sync, db)
    
    return {'message': 'Invalid action'}, 400


def _process_check_out(student, roll_no, now, user_role, is_offline_sync, db):
    """Process a check-out operation using movement_records."""

    # Check whether the student already has an active checkout.
    active_checkout = db.active_checkouts.find_one({
        'roll_no': roll_no,
        'status': {'$in': ['active', 'violation']}
    })

    if active_checkout:
        existing_out_time = active_checkout.get('out_time')

        return {
            'message': 'Student is already checked out',
            'out_time': (
                existing_out_time.strftime('%Y-%m-%d %H:%M:%S')
                if existing_out_time
                else None
            )
        }, 400

    # Generate a unique movement ID.
    event_id = str(uuid.uuid4())

    # Create movement record.
    movement_record = {
        'event_id': event_id,
        'roll_no': roll_no,
        'action': 'out',
        'out_time': now,
        'in_time': None,
        'recorded_by': user_role,
        'recorded_at': now,
        'status': 'outside',
        'offline_sync': is_offline_sync,
        'created_at': now,
        'updated_at': now
    }

    # Insert into the new collection.
    result = db.movement_records.insert_one(movement_record)

    # Create active checkout for proactive monitoring.
    create_active_checkout(
        roll_no=roll_no,
        student=student,
        out_time=now,
        user_role=user_role,
        offline_sync=is_offline_sync,
        movement_id=event_id,
        db=db
    )

    print(
        f"OUT MOVEMENT CREATED | "
        f"Roll={roll_no} | "
        f"EventID={event_id} | "
        f"Time={now}"
    )

    return {
        'message': 'Check out recorded successfully',
        'student_name': student.get('name', 'Unknown'),
        'roll_no': roll_no,
        'time': now.strftime('%Y-%m-%d %H:%M:%S'),
        'action': 'out',
        'event_id': event_id,
        'offline_sync': is_offline_sync
    }, 200


def _process_check_in(student, roll_no, now, user_role, is_offline_sync, db):
    """Process a check-in operation using movement_records."""

    # Find the active checkout.
    active_checkout = db.active_checkouts.find_one({
        'roll_no': roll_no,
        'status': {'$in': ['active', 'violation']}
    })

    if active_checkout is None:
        return {'message': 'No active check out record found'}, 400

    # Get movement ID associated with this checkout.
    movement_id = active_checkout.get('movement_id')

    if not movement_id:
        return {
            'message': 'Active checkout is missing movement ID'
        }, 500

    # Find the corresponding movement record.
    movement_record = db.movement_records.find_one({
        'event_id': movement_id,
        'roll_no': roll_no
    })

    if movement_record is None:
        return {
            'message': 'Movement record not found'
        }, 500

    # Make sure this movement is actually still outside.
    if movement_record.get('in_time') is not None:
        return {
            'message': 'Movement record is already checked in'
        }, 400

    # Normalize OUT time.
    raw_out_time = movement_record.get('out_time')

    if raw_out_time is None:
        return {
            'message': 'Invalid movement record: out_time is missing'
        }, 500

    try:
        out_time = normalize_datetime_to_ist(raw_out_time)
    except Exception as e:
        print(f"Error normalizing OUT time: {e}")
        return {'message': 'Invalid OUT timestamp'}, 500

    # Calculate duration.
    time_spent_minutes = calculate_duration_minutes(
        out_time,
        now
    )

    # Safety: never allow negative duration.
    if time_spent_minutes < 0:
        print(
            f"INVALID TIMESTAMP | "
            f"Roll={roll_no} | "
            f"OUT={out_time} | "
            f"IN={now}"
        )

        now = get_ist_now()

        time_spent_minutes = calculate_duration_minutes(
            out_time,
            now
        )

        if time_spent_minutes < 0:
            return {
                'success': False,
                'message': 'Invalid scan time: IN time is earlier than OUT time.',
                'out_time': out_time.isoformat(),
                'in_time': now.isoformat(),
                'time_spent_minutes': round(time_spent_minutes, 2),
                'offline_sync': is_offline_sync
            }, 400

    # Update movement record.
    update_result = db.movement_records.update_one(
        {
            'event_id': movement_id,
            'roll_no': roll_no,
            'in_time': None
        },
        {
            '$set': {
                'in_time': now,
                'time_spent_minutes': round(time_spent_minutes, 4),
                'action': 'in',
                'status': 'inside',
                'offline_sync': is_offline_sync,
                'updated_at': now
            }
        }
    )

    if update_result.modified_count != 1:
        print(
            f"Failed to update movement record for {roll_no}"
        )
        return {
            'message': 'Failed to update check-in record'
        }, 500

    # Get allowed time.
    max_allowed_time = float(
        student.get('custom_allowed_time_minutes', 480)
    )

    final_exceeded_minutes = round(
        max(0, time_spent_minutes - max_allowed_time),
        2
    )

    # ============================================================
    # FINALIZE EXISTING PROACTIVE VIOLATION
    # ============================================================

    if active_checkout.get('status') == 'violation':

        disciplinary_record_id = active_checkout.get(
            'disciplinary_record_id'
        )

        alert_id = active_checkout.get('alert_id')

        proactive_exceeded = active_checkout.get(
            'proactive_exceeded_minutes',
            0
        )

        print(
            f"PROACTIVE VIOLATION FOUND | "
            f"Roll={roll_no} | "
            f"ProactiveExceeded={proactive_exceeded:.2f} | "
            f"FinalExceeded={final_exceeded_minutes:.2f}"
        )

        if disciplinary_record_id:

            from bson import ObjectId

            if isinstance(disciplinary_record_id, str):
                disciplinary_record_id = ObjectId(
                    disciplinary_record_id
                )

            final_note = (
                f"Proactive detection: "
                f"{proactive_exceeded:.2f} min exceeded. "
                f"Final: "
                f"{final_exceeded_minutes:.2f} min exceeded. "
                f"Actual duration: "
                f"{time_spent_minutes:.2f} min."
            )

            db.students.update_one(
                {
                    'roll_no': roll_no,
                    'disciplinary_records._id':
                        disciplinary_record_id
                },
                {
                    '$set': {
                        'disciplinary_records.$.actual_duration_minutes':
                            round(time_spent_minutes, 4),
                        'disciplinary_records.$.final_exceeded_minutes':
                            final_exceeded_minutes,
                        'disciplinary_records.$.time_exceeded_minutes':
                            final_exceeded_minutes,
                        'disciplinary_records.$.violation_status':
                            'confirmed',
                        'disciplinary_records.$.in_time':
                            now,
                        'disciplinary_records.$.finalized_at':
                            now,
                        'disciplinary_records.$.proactive_exceeded_minutes':
                            proactive_exceeded,
                        'disciplinary_records.$.final_note':
                            final_note
                    }
                }
            )

        else:
            _create_fallback_disciplinary_record(
                roll_no,
                out_time,
                now,
                max_allowed_time,
                time_spent_minutes,
                final_exceeded_minutes,
                user_role,
                is_offline_sync,
                db
            )

        if alert_id:

            from bson import ObjectId

            if isinstance(alert_id, str):
                alert_id = ObjectId(alert_id)

            db.realtime_alerts.update_one(
                {'_id': alert_id},
                {
                    '$set': {
                        'details.actual_duration_minutes':
                            round(time_spent_minutes, 4),
                        'details.final_exceeded_minutes':
                            final_exceeded_minutes,
                        'details.violation_status':
                            'confirmed',
                        'details.in_time':
                            now,
                        'details.proactive_exceeded_minutes':
                            proactive_exceeded,
                        'finalized_at':
                            now,
                        'final_note':
                            (
                                f"Proactive: "
                                f"{proactive_exceeded:.2f} min. "
                                f"Final: "
                                f"{final_exceeded_minutes:.2f} min."
                            )
                    }
                }
            )

    elif final_exceeded_minutes <= 0:

        print(
            f"CHECK-IN WITHIN ALLOWED TIME | "
            f"Roll={roll_no} | "
            f"Duration={time_spent_minutes:.2f} min"
        )

    else:

        print(
            f"FALLBACK VIOLATION | "
            f"Roll={roll_no} | "
            f"Exceeded={final_exceeded_minutes:.2f} min"
        )

        _create_fallback_disciplinary_record(
            roll_no,
            out_time,
            now,
            max_allowed_time,
            time_spent_minutes,
            final_exceeded_minutes,
            user_role,
            is_offline_sync,
            db
        )

    # Remove from active monitoring.
    db.active_checkouts.delete_one({
        '_id': active_checkout['_id']
    })

    print(
        f"Active checkout removed after IN: {roll_no}"
    )

    response_data = {
        'success': True,
        'message': 'Check in recorded successfully',
        'student_name': student.get('name', 'Unknown'),
        'roll_no': roll_no,
        'time': now.isoformat(),
        'action': 'in',
        'event_id': movement_id,
        'time_spent_minutes': round(time_spent_minutes, 2),
        'offline_sync': is_offline_sync,
        'allowed_time_minutes': max_allowed_time,
        'time_exceeded_minutes': final_exceeded_minutes
    }

    return response_data, 200


def _create_fallback_disciplinary_record(roll_no, out_time, now, max_allowed_time,
                                         time_spent_minutes, final_exceeded_minutes,
                                         user_role, is_offline_sync, db):
    """
    Create a fallback disciplinary record when proactive monitoring didn't catch it
    """
    from bson import ObjectId
    
    disciplinary_record_id = ObjectId()
    
    disciplinary_record = {
        '_id': disciplinary_record_id,
        'date': now,
        'time': now.strftime('%H:%M'),
        'description': (
            f'Exceeded allowed time outside by '
            f'{final_exceeded_minutes} minutes. '
            f'Out at: {out_time.strftime("%Y-%m-%d %H:%M")}, '
            f'In at: {now.strftime("%Y-%m-%d %H:%M")}, '
            f'Allowed: {max_allowed_time} minutes'
        ),
        'action_taken': (
            f'Warning issued for exceeding '
            f'{max_allowed_time}-minute limit'
        ),
        'recorded_by': user_role,
        'recorded_at': now,
        'time_exceeded_minutes': final_exceeded_minutes,
        'final_exceeded_minutes': final_exceeded_minutes,
        'actual_duration_minutes': round(time_spent_minutes, 4),
        'violation_status': 'confirmed',
        'auto_generated': True,
        'offline_sync': is_offline_sync,
        'allowed_time_limit': max_allowed_time,
        'finalized_at': now,
        'detection_method': 'fallback_on_checkin'
    }
    
    db.students.update_one(
        {'roll_no': roll_no},
        {'$push': {'disciplinary_records': disciplinary_record}}
    )


# Keep the original function name for backward compatibility
def handle_security_scan(selected_role, data, db=None):
    """Legacy wrapper for backward compatibility"""
    return process_security_scan(selected_role, data, db)