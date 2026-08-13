# services/sync_service.py
"""
Sync Service - Handles offline synchronization
Extracted from backend.py for better maintainability
"""
from datetime import datetime, timezone

from utils.time_utils import INDIA_TZ, get_ist_now
from utils.db_utils import get_db
from services.movement_service import process_security_scan
from services.alert_service import create_unauthorized_alert


def sync_security_scans(scans, user_role, db=None):
    """
    Sync offline security scans using the same movement service
    as normal online security scans.

    This ensures both online and offline scans use:
        movement_records
        active_checkouts
        proactive monitoring
    """

    if db is None:
        db = get_db()

    if db is None:
        return [{
            'success': False,
            'error': 'Database unavailable'
        }]

    results = []

    for scan in scans:

        if not isinstance(scan, dict):
            results.append({
                'success': False,
                'error': 'Invalid scan format'
            })
            continue

        # Copy scan so we do not modify the original object.
        scan_data = dict(scan)

        # All records entering this function came from offline sync.
        scan_data['offline_sync'] = True

        try:
            response_data, status_code = process_security_scan(
                user_role=user_role,
                data=scan_data,
                db=db
            )

            result = dict(response_data)

            result['status_code'] = status_code
            result['success'] = (
                200 <= status_code < 300
            )

            results.append(result)

        except Exception as e:
            results.append({
                'success': False,
                'roll_no': scan.get('roll_no'),
                'error': str(e)
            })

    return results



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