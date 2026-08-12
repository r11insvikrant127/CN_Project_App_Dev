# services/sync_service.py
"""
Sync Service - Handles offline synchronization
Extracted from backend.py for better maintainability
"""

from datetime import datetime, timezone
from collections import defaultdict
from utils.time_utils import INDIA_TZ, get_ist_now, normalize_datetime_to_ist, calculate_duration_minutes
from utils.db_utils import get_db
from services.movement_service import process_security_scan
from services.alert_service import create_unauthorized_alert


def sync_security_scans(scans, user_role, db=None):
    """
    Sync offline security scans from mobile devices
    
    Args:
        scans: List of scan records from device
        user_role: Role of the user performing sync
        db: Database connection (optional)
    
    Returns:
        list: Results for each scan
    """
    if db is None:
        db = get_db()
    
    if db is None:
        return [{'success': False, 'error': 'Database unavailable'}]
    
    results = []
    
    for scan in scans:
        roll_no = scan.get('roll_no')
        action = scan.get('action')
        original_timestamp = scan.get('original_timestamp')
        
        # Use original timestamp from offline scan
        if original_timestamp:
            utc_time = datetime.fromtimestamp(original_timestamp / 1000, tz=timezone.utc)
            now = utc_time.astimezone(INDIA_TZ)
        else:
            now = get_ist_now()
        
        student = db.students.find_one({'roll_no': roll_no})
        
        if not student:
            results.append({'success': False, 'roll_no': roll_no, 'error': 'Student not found'})
            continue
        
        # Process check in/out using the movement service
        if action == 'out':
            result = _sync_check_out(student, roll_no, now, user_role, db)
            results.append(result)
        elif action == 'in':
            result = _sync_check_in(student, roll_no, now, user_role, db)
            results.append(result)
        else:
            results.append({'success': False, 'roll_no': roll_no, 'error': 'Invalid action'})
    
    return results


def _sync_check_out(student, roll_no, now, user_role, db):
    """Sync a check-out operation"""
    # Check if student is already out
    current_out_record = None
    for record in reversed(student.get('in_out_records', [])):
        if record.get('action') == 'out' and record.get('in_time') is None:
            current_out_record = record
            break
    
    if current_out_record:
        return {'success': False, 'roll_no': roll_no, 'error': 'Already checked out'}
    
    # Record out time
    out_record = {
        'out_time': now,
        'in_time': None,
        'action': 'out',
        'recorded_by': user_role,
        'recorded_at': now,
        'status': 'outside',
        'offline_sync': True
    }
    
    db.students.update_one(
        {'roll_no': roll_no},
        {'$push': {'in_out_records': out_record}}
    )
    
    # Create active checkout
    from services.monitoring_service import create_active_checkout
    create_active_checkout(
        roll_no=roll_no,
        student=student,
        out_time=now,
        user_role=user_role,
        offline_sync=True,
        db=db
    )
    
    return {'success': True, 'roll_no': roll_no, 'action': 'out'}


def _sync_check_in(student, roll_no, now, user_role, db):
    """Sync a check-in operation"""
    # Find the latest out record without in time
    latest_out_record = None
    for record in reversed(student.get('in_out_records', [])):
        if record.get('action') == 'out' and record.get('in_time') is None:
            latest_out_record = record
            break
    
    if not latest_out_record:
        return {'success': False, 'roll_no': roll_no, 'error': 'No active check out'}
    
    # Normalize out time
    raw_out_time = latest_out_record['out_time']
    try:
        out_time = normalize_datetime_to_ist(raw_out_time)
    except Exception as e:
        return {'success': False, 'roll_no': roll_no, 'error': f'Invalid timestamp: {str(e)}'}
    
    # Safety: Never allow IN time before OUT time
    if now < out_time:
        print(f"⚠️ Invalid offline timestamp | Roll={roll_no} | OUT={out_time} | IN={now}")
        now = get_ist_now()
    
    # Calculate time spent
    time_spent_minutes = calculate_duration_minutes(out_time, now)
    
    if time_spent_minutes < 0:
        return {
            'success': False,
            'roll_no': roll_no,
            'error': 'Invalid server timestamp: IN is earlier than OUT'
        }
    
    # Update the exact out record
    db.students.update_one(
        {
            'roll_no': roll_no,
            'in_out_records.out_time': raw_out_time
        },
        {
            '$set': {
                'in_out_records.$.in_time': now,
                'in_out_records.$.time_spent_minutes': round(time_spent_minutes, 4),
                'in_out_records.$.action': 'in',
                'in_out_records.$.status': 'inside',
                'in_out_records.$.offline_sync': True
            }
        }
    )
    
    # Remove active checkout
    db.active_checkouts.delete_one({'roll_no': roll_no})
    
    # Check allowed time
    max_allowed_time = float(student.get('custom_allowed_time_minutes', 480))
    
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
            'offline_sync': True,
            'allowed_time_limit': max_allowed_time
        }
        
        db.students.update_one(
            {'roll_no': roll_no},
            {'$push': {'disciplinary_records': disciplinary_record}}
        )
        
        return {
            'success': True,
            'roll_no': roll_no,
            'action': 'in',
            'warning': f'Time exceeded limit by {exceeded_minutes} minutes',
            'time_spent_minutes': round(time_spent_minutes, 2)
        }
    
    return {
        'success': True,
        'roll_no': roll_no,
        'action': 'in',
        'time_spent_minutes': round(time_spent_minutes, 2)
    }


def sync_canteen_visits(visits, user_role, db=None):
    """
    Sync offline canteen visits from mobile devices
    
    Args:
        visits: List of canteen visit records from device
        user_role: Role of the user performing sync
        db: Database connection (optional)
    
    Returns:
        list: Results for each visit
    """
    if db is None:
        db = get_db()
    
    if db is None:
        return [{'success': False, 'error': 'Database unavailable'}]
    
    user_hostel = user_role.split('_')[1].upper() if '_' in user_role else 'ALL'
    results = []
    
    for visit in visits:
        roll_no = visit.get('roll_no')
        original_timestamp = visit.get('original_timestamp')
        
        if original_timestamp:
            utc_time = datetime.fromtimestamp(original_timestamp / 1000, tz=timezone.utc)
            now = utc_time.astimezone(INDIA_TZ)
        else:
            now = get_ist_now()
        
        student = db.students.find_one({'roll_no': roll_no})
        
        if not student:
            results.append({'success': False, 'roll_no': roll_no, 'error': 'Student not found'})
            continue
        
        student_hostel = student.get('hostel', 'Unknown')
        is_unauthorized = student_hostel != user_hostel
        
        visit_record = {
            'roll_no': roll_no,
            'student_hostel': student_hostel,
            'canteen_hostel': user_hostel,
            'role': user_role,
            'timestamp': now,
            'student_name': student.get('name', 'Unknown'),
            'type': 'canteen',
            'is_unauthorized': is_unauthorized,
            'date': now.date(),
            'hour': now.hour,
            'day_of_week': now.strftime('%A'),
            'offline_sync': True
        }
        
        db.canteen_visits.insert_one(visit_record)
        results.append({'success': True, 'roll_no': roll_no})
        
        if is_unauthorized:
            create_unauthorized_alert(visit_record, db)
    
    return results


def get_students_for_sync(hostel=None, limit=10000, db=None):
    """
    Get minimal student data for offline sync
    
    Args:
        hostel: Filter by hostel (optional)
        limit: Maximum number of students
        db: Database connection (optional)
    
    Returns:
        list: List of students with minimal fields
    """
    if db is None:
        db = get_db()
    
    if db is None:
        return []
    
    query = {}
    if hostel and hostel != 'ALL':
        query['hostel'] = hostel
    
    projection = {
        '_id': 0,
        'roll_no': 1,
        'name': 1,
        'hostel': 1
    }
    
    students = list(db.students.find(
        query,
        projection
    ).sort([('hostel', 1), ('roll_no', 1)]).limit(limit))
    
    # Compress data for efficient transfer
    compressed_students = []
    for student in students:
        compressed_students.append({
            'roll_no': student.get('roll_no', ''),
            'name': student.get('name', ''),
            'hostel': student.get('hostel', '')
        })
    
    return compressed_students


def validate_student_offline(roll_no, db=None):
    """
    Validate a student for offline scanning
    
    Args:
        roll_no: Student roll number
        db: Database connection (optional)
    
    Returns:
        dict: Student info or None
    """
    if db is None:
        db = get_db()
    
    if db is None:
        return None
    
    student = db.students.find_one(
        {'roll_no': roll_no},
        {'roll_no': 1, 'name': 1, 'hostel': 1, '_id': 0}
    )
    
    if student:
        return {
            'valid': True,
            'student': {
                'roll_no': student.get('roll_no'),
                'name': student.get('name'),
                'hostel': student.get('hostel')
            }
        }
    
    return {'valid': False, 'message': 'Student not found'}