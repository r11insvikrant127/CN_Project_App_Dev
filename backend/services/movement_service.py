# services/movement_service.py
"""
Movement Service - Handles all student check-in/check-out operations
Extracted from backend.py for better maintainability
"""

from datetime import datetime, timedelta, timezone
from bson import ObjectId
import time
from flask import jsonify

# Import utils
import sys
import os
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from utils.time_utils import get_ist_now, normalize_datetime_to_ist, calculate_duration_minutes
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
        now = utc_time.astimezone(INDIA_TZ)  # INDIA_TZ will be imported
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
    
    # Safety: Never allow IN time before OUT time
    if now < out_time:
        print(f"⚠️ INVALID OFFLINE TIMESTAMP | Roll={roll_no} | OUT={out_time} | IN={now}")
        # Use server time instead
        now = get_ist_now()
    
    # Calculate time spent
    time_spent_minutes = calculate_duration_minutes(out_time, now)
    
    # Validate time spent is not negative
    if time_spent_minutes < 0:
        return {
            'success': False,
            'message': 'Invalid scan time: IN time is earlier than OUT time.',
            'out_time': out_time.isoformat(),
            'in_time': now.isoformat(),
            'time_spent_minutes': round(time_spent_minutes, 2),
            'offline_sync': is_offline_sync
        }, 400
    
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
    
    # Remove from active checkout monitoring
    db.active_checkouts.delete_one({'roll_no': roll_no})
    print(f"✅ Active checkout removed after IN: {roll_no}")
    
    # Check if time exceeded allowed limit
    max_allowed_time = float(student.get('custom_allowed_time_minutes', 480))
    
    response_data = {
        'success': True,
        'message': 'Check in recorded successfully',
        'student_name': student.get('name', 'Unknown'),
        'roll_no': roll_no,
        'time': now.isoformat(),
        'action': 'in',
        'time_spent_minutes': round(time_spent_minutes, 2),
        'offline_sync': is_offline_sync
    }
    
    # Create disciplinary record if time exceeded
    if time_spent_minutes > max_allowed_time:
        exceeded_minutes = round(time_spent_minutes - max_allowed_time, 2)
        
        disciplinary_record = {
            'date': now,
            'time': now.strftime('%H:%M'),
            'description': (
                f'Exceeded allowed time outside by {exceeded_minutes} minutes. '
                f'Out at: {out_time.strftime("%Y-%m-%d %H:%M")}, '
                f'In at: {now.strftime("%Y-%m-%d %H:%M")}, '
                f'Allowed: {max_allowed_time} minutes'
            ),
            'action_taken': f'Warning issued for exceeding {max_allowed_time}-minute limit',
            'recorded_by': user_role,
            'recorded_at': now,
            'time_exceeded_minutes': exceeded_minutes,
            'auto_generated': True,
            'offline_sync': is_offline_sync,
            'allowed_time_limit': max_allowed_time
        }
        
        db.students.update_one(
            {'roll_no': roll_no},
            {'$push': {'disciplinary_records': disciplinary_record}}
        )
        
        response_data['message'] = 'Check in recorded. Time exceeded allowed limit!'
        response_data['disciplinary_action'] = 'Warning issued'
        response_data['time_exceeded_minutes'] = exceeded_minutes
    
    print(f"✅ CHECK-IN RECORDED | Roll={roll_no} | Duration={time_spent_minutes:.4f} min")
    
    return response_data, 200


# Keep the original function name for backward compatibility
def handle_security_scan(selected_role, data, db=None):
    """Legacy wrapper for backward compatibility"""
    return process_security_scan(selected_role, data, db)