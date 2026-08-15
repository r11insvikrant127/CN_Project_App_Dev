# services/student_service.py
"""
Student Service - Handles all student-related operations
Extracted from backend.py for better maintainability
"""

from datetime import datetime, date, timedelta, timezone
from bson import ObjectId
from utils.time_utils import INDIA_TZ, get_ist_now, normalize_datetime_to_ist
from utils.db_utils import get_db

def _get_recent_movement_records(roll_no, days=30, db=None):
    """
    Get movement records for a student from the dedicated
    movement_records collection.
    """

    if db is None:
        db = get_db()

    if db is None:
        return []

    cutoff_time = get_ist_now() - timedelta(days=days)

    records = list(
        db.movement_records.find({
            'roll_no': roll_no,
            'out_time': {
                '$gte': cutoff_time
            }
        }).sort(
            'out_time',
            -1
        )
    )

    return records


def get_student_with_role(roll_no, user_role, requested_role, db=None):
    """
    Get student data with role-based filtering
    
    Args:
        roll_no: Student roll number
        user_role: Role of the requesting user
        requested_role: Role requested in the URL
        db: Database connection (optional)
    
    Returns:
        tuple: (student_data, status_code)
    """
    if db is None:
        db = get_db()
    
    if db is None:
        return {'message': 'Database unavailable'}, 500
    
    # Role mismatch check
    if user_role != requested_role:
        return {'message': 'Role mismatch'}, 403
    
    # Get student from database
    student = db.students.find_one({'roll_no': roll_no})
    
    if not student:
        return {'message': 'Student not found'}, 404
    
    # Get user's hostel from role
    user_hostel = user_role.split('_')[1].upper() if '_' in user_role else 'ALL'

    # Hostel access rules:
    # admin    -> all hostels
    # super_*  -> own hostel only
    # security_* -> own hostel only
    # canteen_* -> all hostels
    if user_role.startswith('super_') or user_role.startswith('security_'):
        if student.get('hostel') != user_hostel:
            return {
                'message': 'This student does not belong to your hostel',
                'student_hostel': student.get('hostel'),
                'user_hostel': user_hostel,
                'access_denied': True
            }, 403
    
    # Serialize dates to IST
    def serialize_dates(obj):
        if isinstance(obj, datetime):
            if obj.tzinfo is None:
                obj = obj.replace(tzinfo=timezone.utc)
            obj_ist = obj.astimezone(INDIA_TZ)
            return obj_ist.isoformat()

        elif isinstance(obj, date):
            return obj.isoformat()

        elif isinstance(obj, ObjectId):
            return str(obj)

        elif isinstance(obj, dict):
            return {
                key: serialize_dates(value)
                for key, value in obj.items()
            }

        elif isinstance(obj, list):
            return [
                serialize_dates(item)
                for item in obj
            ]

        return obj
    
    # Return data based on role
    if user_role == 'admin':
        return _format_admin_student_data(
            student,
            serialize_dates,
            db
        ), 200
    elif user_role.startswith('super_'):
        return _format_super_student_data(
            student,
            serialize_dates,
            db
        ), 200
    elif user_role.startswith('security_') or user_role.startswith('canteen_'):
        return _format_basic_student_data(student, user_hostel), 200
    else:
        return {'message': 'Invalid role'}, 400


def _format_admin_student_data(
    student,
    serialize_dates,
    db
):
    """Format student data for admin"""
    return {
        'roll_no': student['roll_no'],
        'name': student['name'],
        'hostel': student['hostel'],
        'room_no': student['room_no'],
        'course': student['course'],
        'academic_year': student['academic_year'],
        'branch': student['branch'],
        'contact_no': student['contact_no'],
        'email': student['email'],
        'guardian_name': student['guardian_name'],
        'guardian_phone': student['guardian_phone'],
        'home_address': student['home_address'],
        'fee_status': student['fee_status'],
        'admission_date': serialize_dates(student['admission_date']),
        'in_out_records': [
            serialize_dates(record)
            for record in _get_recent_movement_records(
                student['roll_no'],
                days=180,
                db=db
            )
        ],
        'disciplinary_records': [serialize_dates(record) for record in student.get('disciplinary_records', [])],
        'medical_info': student.get('medical_info', [])
    }


def _format_super_student_data(
    student,
    serialize_dates,
    db
):
    """Format student data for super"""
    return {
        'roll_no': student['roll_no'],
        'name': student['name'],
        'hostel': student['hostel'],
        'room_no': student['room_no'],
        'course': student['course'],
        'academic_year': student['academic_year'],
        'branch': student['branch'],
        'contact_no': student['contact_no'],
        'in_out_records': [
            serialize_dates(record)
            for record in _get_recent_movement_records(
                student['roll_no'],
                days=180,
                db=db
            )
        ],
        'medical_info': student.get('medical_info', []),
        'disciplinary_records': [serialize_dates(record) for record in student.get('disciplinary_records', [])]
    }


def _format_basic_student_data(student, user_hostel):
    """Format basic student data for security/canteen"""
    return {
        'roll_no': student['roll_no'],
        'name': student['name'],
        'hostel': student['hostel'],
        'room_no': student.get('room_no'),
        'course': student.get('course'),
        'branch': student.get('branch'),
        'belongs_to_hostel': student.get('hostel') == user_hostel
    }


def search_students(query, hostel=None, limit=20, db=None):
    """
    Search for students by name or roll number
    
    Args:
        query: Search query string
        hostel: Filter by hostel (optional)
        limit: Maximum results to return
        db: Database connection (optional)
    
    Returns:
        list: List of matching students
    """
    if db is None:
        db = get_db()
    
    if db is None:
        return []
    
    search_filter = {
        '$or': [
            {'name': {'$regex': query, '$options': 'i'}},
            {'roll_no': {'$regex': query, '$options': 'i'}}
        ]
    }
    
    if hostel:
        search_filter['hostel'] = hostel
    
    students = list(db.students.find(
        search_filter,
        {'_id': 0, 'roll_no': 1, 'name': 1, 'hostel': 1, 'room_no': 1}
    ).limit(limit))
    
    return students


def get_students_by_hostel(hostel, page=1, page_size=100, db=None):
    """
    Get all students for a specific hostel (for offline caching)
    
    Args:
        hostel: Hostel name (A, B, C, D, or ALL)
        page: Page number (1-indexed)
        page_size: Number of records per page
        db: Database connection (optional)
    
    Returns:
        dict: Students with pagination metadata
    """
    if db is None:
        db = get_db()
    
    if db is None:
        return {'students': [], 'total_count': 0}
    
    # Build query
    if hostel == 'ALL':
        query = {'hostel': {'$in': ['A', 'B', 'C', 'D']}}
    else:
        query = {'hostel': hostel}
    
    # Only return minimal fields for offline use
    projection = {
        '_id': 0,
        'roll_no': 1,
        'name': 1,
        'hostel': 1
    }
    
    # Get total count
    total_count = db.students.count_documents(query)
    
    # Apply pagination
    skip = (page - 1) * page_size if page_size > 0 else 0
    limit = page_size if page_size > 0 else 0
    
    # Execute query with sorting
    find_query = db.students.find(query, projection).sort([('hostel', 1), ('roll_no', 1)])
    
    if skip > 0:
        find_query = find_query.skip(skip)
    if limit > 0:
        find_query = find_query.limit(limit)
    
    students = list(find_query)
    
    return {
        'students': students,
        'total_count': total_count,
        'page': page,
        'page_size': page_size if page_size > 0 else 'ALL',
        'total_pages': (total_count + page_size - 1) // page_size if page_size > 0 else 1
    }


def get_student_allowed_time(roll_no, db=None):
    """
    Get a student's custom allowed time
    
    Args:
        roll_no: Student roll number
        db: Database connection (optional)
    
    Returns:
        dict: Student allowed time info
    """
    if db is None:
        db = get_db()
    
    if db is None:
        return {'error': 'Database unavailable'}
    
    student = db.students.find_one(
        {'roll_no': roll_no},
        {'roll_no': 1, 'name': 1, 'custom_allowed_time_minutes': 1}
    )
    
    if not student:
        return {'error': 'Student not found'}
    
    allowed_time = student.get('custom_allowed_time_minutes', 480)
    
    return {
        'roll_no': roll_no,
        'name': student.get('name', 'Unknown'),
        'current_allowed_time': allowed_time,
        'is_custom': 'custom_allowed_time_minutes' in student,
        'default_time': 480
    }


def update_student_allowed_time(roll_no, new_allowed_time, admin_user, db=None):
    """
    Update a student's custom allowed time
    
    Args:
        roll_no: Student roll number
        new_allowed_time: New allowed time in minutes
        admin_user: Admin user info (device_id)
        db: Database connection (optional)
    
    Returns:
        dict: Update result
    """
    if db is None:
        db = get_db()
    
    if db is None:
        return {'error': 'Database unavailable'}
    
    if not new_allowed_time or not isinstance(new_allowed_time, (int, float)) or new_allowed_time <= 0:
        return {'error': 'Valid allowed time in minutes is required'}
    
    student = db.students.find_one({'roll_no': roll_no})
    
    if not student:
        return {'error': 'Student not found'}
    
    # Update student with custom allowed time
    update_data = {
        'custom_allowed_time_minutes': float(new_allowed_time),
        'allowed_time_updated_at': get_ist_now(),
        'allowed_time_updated_by': 'admin'
    }
    
    db.students.update_one(
        {'roll_no': roll_no},
        {'$set': update_data}
    )
    
    return {
        'success': True,
        'message': f'Allowed time updated successfully to {new_allowed_time} minutes',
        'roll_no': roll_no,
        'student_name': student.get('name', 'Unknown'),
        'new_allowed_time': new_allowed_time,
        'old_time': student.get('custom_allowed_time_minutes', 480)
    }


def reset_student_allowed_time(roll_no, admin_user, db=None):
    """
    Reset a student's allowed time to default (480 minutes)
    
    Args:
        roll_no: Student roll number
        admin_user: Admin user info (device_id)
        db: Database connection (optional)
    
    Returns:
        dict: Reset result
    """
    if db is None:
        db = get_db()
    
    if db is None:
        return {'error': 'Database unavailable'}
    
    student = db.students.find_one({'roll_no': roll_no})
    
    if not student:
        return {'error': 'Student not found'}
    
    # Remove custom allowed time to use default
    db.students.update_one(
        {'roll_no': roll_no},
        {'$unset': {
            'custom_allowed_time_minutes': "",
            'allowed_time_updated_at': "",
            'allowed_time_updated_by': ""
        }}
    )
    
    return {
        'success': True,
        'message': 'Allowed time reset to default (480 minutes)',
        'roll_no': roll_no,
        'student_name': student.get('name', 'Unknown'),
        'current_allowed_time': 480,
        'previous_time': student.get('custom_allowed_time_minutes', 480)
    }


def validate_student_offline(roll_no, db=None):
    """
    Validate a student for offline scanning
    
    Args:
        roll_no: Student roll number
        db: Database connection (optional)
    
    Returns:
        dict: Student validation result
    """
    if db is None:
        db = get_db()
    
    if db is None:
        return {'valid': False, 'error': 'Database unavailable'}
    
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


def get_student_counts(db=None):
    """
    Get student counts by hostel
    
    Args:
        db: Database connection (optional)
    
    Returns:
        dict: Student counts by hostel
    """
    if db is None:
        db = get_db()
    
    if db is None:
        return {'error': 'Database unavailable'}
    
    counts = {}
    total = 0
    
    for hostel in ['A', 'B', 'C', 'D']:
        count = db.students.count_documents({'hostel': hostel})
        counts[hostel] = count
        total += count
    
    return {
        'success': True,
        'total_students': total,
        'by_hostel': counts,
        'average_per_hostel': total / 4 if total > 0 else 0
    }


def get_all_students_minimal(db=None):
    """
    Get ALL students with minimal fields (roll_no, name, hostel only)
    Perfect for offline storage
    
    Args:
        db: Database connection (optional)
    
    Returns:
        list: List of students with minimal fields
    """
    if db is None:
        db = get_db()
    
    if db is None:
        return []
    
    projection = {
        '_id': 0,
        'roll_no': 1,
        'name': 1,
        'hostel': 1
    }
    
    students = list(db.students.find(
        {'hostel': {'$in': ['A', 'B', 'C', 'D']}},
        projection
    ).sort([('hostel', 1), ('roll_no', 1)]))
    
    return students


def get_active_students_outside(db=None):
    """
    Get all students currently outside
    
    Args:
        db: Database connection (optional)
    
    Returns:
        list: List of students currently outside
    """
    if db is None:
        db = get_db()
    
    if db is None:
        return []
    
    # Get all active checkouts
    active_checkouts = list(db.active_checkouts.find(
        {'status': 'active'},
        {'_id': 0, 'roll_no': 1, 'student_name': 1, 'student_hostel': 1, 
         'out_time': 1, 'deadline': 1, 'allowed_minutes': 1}
    ))
    
    return active_checkouts


def get_student_movement_history(roll_no, days=30, db=None):
    """
    Get a student's movement history from movement_records.
    """

    if db is None:
        db = get_db()

    if db is None:
        return []

    # Verify student exists.
    student = db.students.find_one(
        {'roll_no': roll_no},
        {'_id': 1}
    )

    if not student:
        return []

    cutoff_time = get_ist_now() - timedelta(days=days)

    records = list(
        db.movement_records.find({
            'roll_no': roll_no,
            'out_time': {
                '$gte': cutoff_time
            }
        }).sort(
            'out_time',
            -1
        )
    )

    return records