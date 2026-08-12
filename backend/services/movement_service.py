# services/movement_service.py
"""
Movement Service - Handles all student check-in/check-out operations
Extracted from backend.py for better maintainability
"""

from datetime import datetime, timezone

# Import utils
import sys
import os
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
    """Process a check-out operation"""
    
    # Check if student is already out
    current_out_record = None
    for record in reversed(student.get('in_out_records', [])):
        if record.get('action') == 'out' and record.get('in_time') is None:
            current_out_record = record
            break
    
    if current_out_record:
        return {
            'message': 'Student is already checked out',
            'out_time': current_out_record['out_time'].strftime('%Y-%m-%d %H:%M:%S')
        }, 400
    
    # Create OUT record
    out_record = {
        'out_time': now,
        'in_time': None,
        'action': 'out',
        'recorded_by': user_role,
        'recorded_at': now,
        'status': 'outside',
        'offline_sync': is_offline_sync
    }
    
    # Update database
    db.students.update_one(
        {'roll_no': roll_no},
        {'$push': {'in_out_records': out_record}}
    )
    
    # Create active checkout for proactive monitoring
    create_active_checkout(
        roll_no=roll_no,
        student=student,
        out_time=now,
        user_role=user_role,
        offline_sync=is_offline_sync,
        db=db
    )
    
    print(f"✅ OUT record created: {roll_no} at {now}")
    
    return {
        'message': 'Check out recorded successfully',
        'student_name': student.get('name', 'Unknown'),
        'roll_no': roll_no,
        'time': now.strftime('%Y-%m-%d %H:%M:%S'),
        'action': 'out',
        'offline_sync': is_offline_sync
    }, 200


def _process_check_in(student, roll_no, now, user_role, is_offline_sync, db):
    """Process a check-in operation"""
    
    # Find the latest active OUT record
    records = student.get('in_out_records', [])
    latest_out_record = None
    latest_out_index = None
    
    for i in range(len(records) - 1, -1, -1):
        record = records[i]
        if record.get('action') == 'out' and record.get('in_time') is None:
            latest_out_record = record
            latest_out_index = i
            break
    
    if latest_out_record is None:
        return {'message': 'No active check out record found'}, 400
    
    # Normalize OUT time
    raw_out_time = latest_out_record.get('out_time')
    if raw_out_time is None:
        return {'message': 'Invalid OUT record: out_time is missing'}, 500
    
    try:
        out_time = normalize_datetime_to_ist(raw_out_time)
    except Exception as e:
        print(f"❌ Error normalizing OUT time: {e}")
        return {'message': 'Invalid OUT timestamp'}, 500
    
    # ============================================================
    # FIX: Calculate duration FIRST, then validate
    # ============================================================
    # Calculate time spent
    time_spent_minutes = calculate_duration_minutes(out_time, now)
    
    # Safety: Never allow negative duration
    if time_spent_minutes < 0:
        print(f"⚠️ INVALID TIMESTAMP | Roll={roll_no} | OUT={out_time} | IN={now}")
        # Use server time instead
        now = get_ist_now()
        time_spent_minutes = calculate_duration_minutes(out_time, now)
        
        # If still negative, reject the scan
        if time_spent_minutes < 0:
            return {
                'success': False,
                'message': 'Invalid scan time: IN time is earlier than OUT time.',
                'out_time': out_time.isoformat(),
                'in_time': now.isoformat(),
                'time_spent_minutes': round(time_spent_minutes, 2),
                'offline_sync': is_offline_sync
            }, 400
    # ============================================================
    
    # Update the exact OUT record with IN time
    update_result = db.students.update_one(
        {'roll_no': roll_no},
        {
            '$set': {
                f'in_out_records.{latest_out_index}.in_time': now,
                f'in_out_records.{latest_out_index}.time_spent_minutes': round(time_spent_minutes, 4),
                f'in_out_records.{latest_out_index}.action': 'in',
                f'in_out_records.{latest_out_index}.status': 'inside',
                f'in_out_records.{latest_out_index}.offline_sync': is_offline_sync
            }
        }
    )
    
    if update_result.modified_count != 1:
        print(f"❌ Failed to update movement record for {roll_no}")
        return {'message': 'Failed to update check-in record'}, 500
    
    # Get the active checkout BEFORE deleting it.
    # It may contain the proactive violation information.
    active_checkout = db.active_checkouts.find_one(
        {'roll_no': roll_no}
    )

    # Check if time exceeded allowed limit
    max_allowed_time = float(
        student.get('custom_allowed_time_minutes', 480)
    )

    # Final exceeded time after actual check-in
    final_exceeded_minutes = round(
        max(0, time_spent_minutes - max_allowed_time),
        2
    )

    # ============================================================
    # FINALIZE EXISTING PROACTIVE VIOLATION
    # ============================================================
    if (
        active_checkout
        and active_checkout.get('status') == 'violation'
    ):
        # Get the IDs saved by monitoring_service.py
        disciplinary_record_id = active_checkout.get(
            'disciplinary_record_id'
        )
        alert_id = active_checkout.get('alert_id')
        proactive_exceeded = active_checkout.get(
            'proactive_exceeded_minutes', 0
        )

        print(
            f"🔍 PROACTIVE VIOLATION FOUND | "
            f"Roll={roll_no} | "
            f"ProactiveExceeded={proactive_exceeded:.2f} | "
            f"FinalExceeded={final_exceeded_minutes:.2f} | "
            f"DisciplinaryID={disciplinary_record_id} | "
            f"AlertID={alert_id}"
        )

        # Update the SAME disciplinary record if ID exists
        if disciplinary_record_id:
            # Convert to ObjectId if it's a string
            from bson import ObjectId
            if isinstance(disciplinary_record_id, str):
                disciplinary_record_id = ObjectId(disciplinary_record_id)
            
            update_doc = {
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
                        proactive_exceeded
                }
            }
            
            # Also add final note if not already there
            final_note = (
                f"Proactive detection: {proactive_exceeded:.2f} min exceeded. "
                f"Final: {final_exceeded_minutes:.2f} min exceeded. "
                f"Actual duration: {time_spent_minutes:.2f} min."
            )
            update_doc['$set']['disciplinary_records.$.final_note'] = final_note
            
            db.students.update_one(
                {
                    'roll_no': roll_no,
                    'disciplinary_records._id': disciplinary_record_id
                },
                update_doc
            )

            print(
                f"✅ PROACTIVE VIOLATION FINALIZED | "
                f"Roll={roll_no} | "
                f"Proactive={proactive_exceeded:.2f} | "
                f"Final={final_exceeded_minutes:.2f} | "
                f"Duration={time_spent_minutes:.2f} min"
            )
        else:
            print(
                f"⚠️ PROACTIVE VIOLATION FOUND BUT NO ID | "
                f"Roll={roll_no} | "
                f"Creating fallback record"
            )
            # Create fallback if no ID was saved
            _create_fallback_disciplinary_record(
                roll_no, out_time, now, max_allowed_time, 
                time_spent_minutes, final_exceeded_minutes, 
                user_role, is_offline_sync, db
            )

        # Update the realtime alert with final information if ID exists
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
                        
                        'finalized_at': now,
                        
                        'final_note': (
                            f"Proactive: {proactive_exceeded:.2f} min. "
                            f"Final: {final_exceeded_minutes:.2f} min."
                        )
                    }
                }
            )
            
            print(f"✅ ALERT UPDATED | AlertID={alert_id}")

    # ============================================================
    # STUDENT WAS WITHIN TIME LIMIT
    # ============================================================
    elif final_exceeded_minutes <= 0:
        print(
            f"✅ CHECK-IN WITHIN ALLOWED TIME | "
            f"Roll={roll_no} | "
            f"Duration={time_spent_minutes:.4f} min"
        )

    # ============================================================
    # FALLBACK VIOLATION (Monitor didn't catch it)
    # ============================================================
    elif final_exceeded_minutes > 0:
        print(
            f"⚠️ FALLBACK VIOLATION | "
            f"Roll={roll_no} | "
            f"FinalExceeded={final_exceeded_minutes:.2f} min"
        )
        _create_fallback_disciplinary_record(
            roll_no, out_time, now, max_allowed_time,
            time_spent_minutes, final_exceeded_minutes,
            user_role, is_offline_sync, db
        )

    # ============================================================
    # NOW remove from active monitoring
    # ============================================================
    db.active_checkouts.delete_one(
        {'roll_no': roll_no}
    )

    print(
        f"✅ Active checkout removed after IN: {roll_no}"
    )
    
    response_data = {
        'success': True,
        'message': 'Check in recorded successfully',
        'student_name': student.get('name', 'Unknown'),
        'roll_no': roll_no,
        'time': now.isoformat(),
        'action': 'in',
        'time_spent_minutes': round(time_spent_minutes, 2),
        'offline_sync': is_offline_sync,
        'allowed_time_minutes': max_allowed_time,
        'time_exceeded_minutes': final_exceeded_minutes
    }
    
    print(f"✅ CHECK-IN RECORDED | Roll={roll_no} | Duration={time_spent_minutes:.4f} min")
    
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