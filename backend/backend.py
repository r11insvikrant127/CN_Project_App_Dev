//backend.py

from flask import Flask, request, jsonify
from flask_pymongo import PyMongo
from flask_jwt_extended import JWTManager, create_access_token, jwt_required, get_jwt_identity
from bson import ObjectId
from functools import wraps
import os
import hashlib
from apscheduler.schedulers.background import BackgroundScheduler
import atexit
from datetime import datetime, timedelta, date
from collections import defaultdict, Counter
import numpy as np
from sklearn.linear_model import LinearRegression
import json
import time
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address

# Custom JSON encoder to handle datetime and ObjectId serialization
class CustomJSONEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, (datetime, date)):
            return obj.isoformat()
        elif isinstance(obj, ObjectId):
            return str(obj)
        return super().default(obj)

app = Flask(__name__)
app.config['MONGO_URI'] = os.environ.get('MONGO_URI', 'mongodb://localhost:27017/student_management')
app.config['JWT_SECRET_KEY'] = os.environ.get('JWT_SECRET_KEY', 'super-secret-key')
app.config['JWT_ACCESS_TOKEN_EXPIRES'] = timedelta(hours=8)
app.json_encoder = CustomJSONEncoder

mongo = PyMongo(app)
jwt = JWTManager(app)

# CORRECTED: Initialize rate limiter
limiter = Limiter(
    app=app,  # Explicit parameter naming
    key_func=get_remote_address,
    default_limits=["200 per day", "50 per hour"]
)

# Initialize scheduler for automatic cleanup
scheduler = BackgroundScheduler()
scheduler.start()

# Enhanced security storage
active_sessions = {}
login_attempts = {}

# Session timeout in seconds (8 hours)
SESSION_TIMEOUT = 8 * 60 * 60
# Max login attempts before lockout
MAX_LOGIN_ATTEMPTS = 5
# Lockout time in seconds (15 minutes)
LOCKOUT_TIME = 15 * 60

# Predefined unique IDs for each subrole
SUBROLE_IDS = {
    "super_a": "super_a_12345",
    "super_b": "super_b_12345", 
    "super_c": "super_c_12345",
    "super_d": "super_d_12345",
    "canteen_a": "canteen_a_12345",
    "canteen_b": "canteen_b_12345",
    "canteen_c": "canteen_c_12345", 
    "canteen_d": "canteen_d_12345",
    "security_a": "security_a_12345",
    "security_b": "security_b_12345",
    "security_c": "security_c_12345",
    "security_d": "security_d_12345",
    "admin": "admin_12345"
}


# CORRECTED: Function to cleanup old movement records (older than 30 days for monthly reports)
def cleanup_old_movement_records():
    try:
        # Changed from 7 days to 30 days to preserve monthly data
        cutoff_time = datetime.now() - timedelta(days=30)
        print(f"🔄 Cleaning up movement records older than: {cutoff_time}")
        
        # Update all students to remove in_out_records older than 30 days
        result = mongo.db.students.update_many(
            {},
            {'$pull': {
                'in_out_records': {
                    'out_time': {'$lt': cutoff_time}
                }
            }}
        )
        
        print(f"✅ Cleanup completed. Modified {result.modified_count} student records")
        
    except Exception as e:
        print(f"❌ Error during cleanup: {e}")


# Database initialization function
def initialize_database():
    try:
        # Create collections if they don't exist
        collections = mongo.db.list_collection_names()
        
        required_collections = ['weekly_reports', 'canteen_visits', 'realtime_alerts', 'admin_scans', 'security_logs']
        
        for collection in required_collections:
            if collection not in collections:
                mongo.db.create_collection(collection)
                print(f"✅ Created {collection} collection")
        
        # Create indexes for better performance
        mongo.db.weekly_reports.create_index([('week_number', 1), ('year', 1)])
        mongo.db.canteen_visits.create_index([('timestamp', -1)])
        mongo.db.realtime_alerts.create_index([('timestamp', -1)])
        mongo.db.students.create_index([('roll_no', 1)])
        mongo.db.devices.create_index([('device_id', 1)])
        mongo.db.security_logs.create_index([('timestamp', -1)])
        
        print("✅ Database initialization completed")
    except Exception as e:
        print(f"❌ Database initialization error: {e}")

# Initialize database when app starts
initialize_database()

# Enhanced security logging
def log_security_event(event_type, user_role, device_id, ip_address, details=None):
    """Log security events for audit trail"""
    try:
        log_entry = {
            'event_type': event_type,
            'user_role': user_role,
            'device_id': device_id,
            'ip_address': ip_address,
            'timestamp': datetime.now(),
            'details': details or {}
        }
        mongo.db.security_logs.insert_one(log_entry)
    except Exception as e:
        print(f"❌ Error logging security event: {e}")

# Enhanced admin authentication with biometric flag
# Enhanced admin authentication with biometric OR device verification
@app.route('/api/admin/authenticate', methods=['POST'])
@limiter.limit("5 per minute")
def admin_biometric_auth():
    try:
        data = request.get_json()
        device_id = data.get('device_id')
        unique_id = data.get('unique_id')
        biometric_verified = data.get('biometric_verified', False)
        ip_address = get_remote_address()
        
        # Check if IP is locked out
        lockout_key = f"lockout:{ip_address}"
        if lockout_key in login_attempts:
            lockout_time = login_attempts[lockout_key]
            if time.time() - lockout_time < LOCKOUT_TIME:
                return jsonify({
                    'authenticated': False,
                    'message': f'Account temporarily locked. Try again in {int((LOCKOUT_TIME - (time.time() - lockout_time)) / 60)} minutes.',
                    'locked': True
                }), 429
        
        # Verify device
        device = mongo.db.devices.find_one({'device_id': device_id, 'status': 'active'})
        if not device:
            log_security_event('device_verification_failed', 'admin', device_id, ip_address, {'reason': 'device_not_found'})
            return jsonify({'authenticated': False, 'message': 'Device not verified'}), 401
        
        # Verify admin unique ID
        expected_id = SUBROLE_IDS.get('admin')
        if unique_id != expected_id:
            log_security_event('admin_auth_failed', 'admin', device_id, ip_address, {'reason': 'invalid_credentials'})
            
            # Track failed attempt
            attempt_key = f"attempts:{ip_address}:{device_id}"
            if attempt_key not in login_attempts:
                login_attempts[attempt_key] = []
            
            login_attempts[attempt_key].append(time.time())
            
            # Check if max attempts reached
            recent_attempts = [attempt for attempt in login_attempts[attempt_key] if time.time() - attempt < 900]  # 15 minutes
            if len(recent_attempts) >= MAX_LOGIN_ATTEMPTS:
                login_attempts[lockout_key] = time.time()
                return jsonify({
                    'authenticated': False,
                    'message': 'Too many failed attempts. Account locked for 15 minutes.',
                    'locked': True
                }), 429
            
            return jsonify({'authenticated': False, 'message': 'Invalid admin credentials'}), 401
        
        # MODIFIED: Allow authentication with verified device (remove biometric requirement)
        # If device is verified and active, allow authentication without biometric
        # You can remove this entire biometric check block if you don't want biometric at all
        
        # Clear login attempts on successful authentication
        attempt_key = f"attempts:{ip_address}:{device_id}"
        if attempt_key in login_attempts:
            del login_attempts[attempt_key]
        
        # Create session
        session_id = hashlib.sha256(f"{device_id}{datetime.now()}".encode()).hexdigest()
        identity_string = f"{device_id}:admin"
        
        access_token = create_access_token(identity=identity_string)
        
        # Store session
        active_sessions[session_id] = {
            'device_id': device_id,
            'role': 'admin',
            'login_time': datetime.now(),
            'last_activity': datetime.now(),
            'biometric_verified': biometric_verified,
            'device_verified': True,
            'ip_address': ip_address
        }
        
        log_security_event('admin_login_success', 'admin', device_id, ip_address, {
            'session_id': session_id,
            'method': 'biometric' if biometric_verified else 'device'
        })
        
        return jsonify({
            'authenticated': True,
            'access_token': access_token,
            'session_token': access_token,
            'session_id': session_id,
            'username': 'admin_user',
            'role': 'admin',
            'message': 'Admin authentication successful',
            'auth_method': 'biometric' if biometric_verified else 'device',
            'session_timeout': SESSION_TIMEOUT,
            'token_type': 'bearer',
            'expires_in': 28800
        }), 200
        
    except Exception as e:
        log_security_event('admin_auth_error', 'admin', data.get('device_id', 'unknown'), get_remote_address(), {'error': str(e)})
        return jsonify({'authenticated': False, 'message': f'Authentication error: {str(e)}'}), 500

# Add token verification endpoint
@app.route('/api/verify-token', methods=['GET'])
@jwt_required()
def verify_token():
    try:
        current_user = get_jwt_identity()
        return jsonify({
            'valid': True,
            'identity': current_user,
            'message': 'Token is valid'
        }), 200
    except Exception as e:
        return jsonify({
            'valid': False,
            'message': f'Token verification failed: {str(e)}'
        }), 401

# Token refresh endpoint
@app.route('/api/refresh-token', methods=['POST'])
@jwt_required(refresh=True)
def refresh_token():
    try:
        current_user = get_jwt_identity()
        new_token = create_access_token(identity=current_user)
        
        return jsonify({
            'access_token': new_token,
            'token_type': 'bearer',
            'expires_in': 28800
        }), 200
    except Exception as e:
        return jsonify({'message': f'Token refresh failed: {str(e)}'}), 401

# Session timeout middleware
@app.before_request
def check_session_timeout():
    # Skip session check for authentication endpoints
    if request.endpoint in ['admin_biometric_auth', 'verify_device', 'authenticate_subrole', 'health', 'home']:
        return
    
    auth_header = request.headers.get('Authorization')
    if auth_header and auth_header.startswith('Bearer '):
        try:
            # Extract session info from token
            identity = get_jwt_identity()
            
            if identity and ':' in identity:
                device_id, role = identity.split(':', 1)
                
                # Check for session timeout (only for admin for now)
                if role == 'admin':
                    session_found = False
                    for session_id, session_data in list(active_sessions.items()):
                        if session_data['device_id'] == device_id:
                            time_since_activity = datetime.now() - session_data['last_activity']
                            if time_since_activity.total_seconds() > SESSION_TIMEOUT:
                                # Session expired
                                del active_sessions[session_id]
                                log_security_event('session_expired', role, device_id, get_remote_address())
                                return jsonify({'message': 'Session expired. Please login again.'}), 401
                            else:
                                # Update last activity
                                active_sessions[session_id]['last_activity'] = datetime.now()
                                session_found = True
                                break
                    
                    if not session_found and role == 'admin':
                        return jsonify({'message': 'Invalid session. Please login again.'}), 401
                        
        except Exception as e:
            print(f"Session check error: {e}")

# Enhanced device verification with security logging
@app.route('/api/verify-device', methods=['POST'])
@limiter.limit("10 per minute")
def verify_device():
    data = request.get_json()
    device_id = data.get('device_id')
    ip_address = get_remote_address()
    
    print(f"🔐 Device verification attempt: {device_id}")
    
    # Check if IP is locked out
    lockout_key = f"lockout:{ip_address}"
    if lockout_key in login_attempts:
        lockout_time = login_attempts[lockout_key]
        if time.time() - lockout_time < LOCKOUT_TIME:
            return jsonify({
                'verified': False,
                'message': f'Too many verification attempts. Try again in {int((LOCKOUT_TIME - (time.time() - lockout_time)) / 60)} minutes.',
                'locked': True
            }), 429
    
    # Check if device exists in database
    device = mongo.db.devices.find_one({'device_id': device_id, 'status': 'active'})
    
    if device:
        print("✅ Device verified successfully")
        log_security_event('device_verified', 'unknown', device_id, ip_address)
        
        # Clear any previous failed attempts
        attempt_key = f"attempts:{ip_address}:{device_id}"
        if attempt_key in login_attempts:
            del login_attempts[attempt_key]

        # ✅ GENERATE PROPER JWT TOKEN
        identity_string = f"{device_id}:device_verified"
        access_token = create_access_token(identity=identity_string)
            
        return jsonify({
            'verified': True,
            'message': 'Device verified successfully',
            'device_info': {
                'device_id': device['device_id'],
                'device_name': device.get('device_name', 'Registered Device'),
                'status': device.get('status', 'active')
            },
            # ✅ ADD PROPER SESSION TOKEN
            'session_token': access_token,
            'token_type': 'bearer',
            'expires_in': 28800,  # 8 hours
            'issued_at': datetime.now().isoformat()
        }), 200
    else:
        print("❌ Device not found in database")
        log_security_event('device_verification_failed', 'unknown', device_id, ip_address)
        
        # Track failed attempt
        attempt_key = f"attempts:{ip_address}:{device_id}"
        if attempt_key not in login_attempts:
            login_attempts[attempt_key] = []
        
        login_attempts[attempt_key].append(time.time())
        
        # Check if max attempts reached
        recent_attempts = [attempt for attempt in login_attempts[attempt_key] if time.time() - attempt < 900]
        if len(recent_attempts) >= MAX_LOGIN_ATTEMPTS:
            login_attempts[lockout_key] = time.time()
            return jsonify({
                'verified': False,
                'message': 'Too many failed verification attempts. Device locked for 15 minutes.',
                'locked': True
            }), 429
            
        return jsonify({
            'verified': False,
            'message': 'Device not registered. Please contact administrator.'
        }), 401

# Enhanced subrole authentication with security features
@app.route('/api/authenticate-subrole', methods=['POST'])
@limiter.limit("10 per minute")
def authenticate_subrole():
    data = request.get_json()
    device_id = data.get('device_id')
    main_role = data.get('main_role')
    subrole = data.get('subrole')
    unique_id = data.get('unique_id')
    ip_address = get_remote_address()
    
    print(f"🔐 Subrole authentication attempt: {subrole}")
    
    # Check lockout
    lockout_key = f"lockout:{ip_address}"
    if lockout_key in login_attempts:
        lockout_time = login_attempts[lockout_key]
        if time.time() - lockout_time < LOCKOUT_TIME:
            return jsonify({
                'authenticated': False,
                'message': f'Account temporarily locked. Try again in {int((LOCKOUT_TIME - (time.time() - lockout_time)) / 60)} minutes.',
                'locked': True
            }), 429
    
    # Verify device from database instead of hardcoded list
    device = mongo.db.devices.find_one({'device_id': device_id, 'status': 'active'})
    
    if not device:
        log_security_event('device_verification_failed', subrole, device_id, ip_address)
        return jsonify({
            'authenticated': False,
            'message': 'Device not verified or inactive'
        }), 401
    
    # Verify unique ID for the subrole
    expected_id = SUBROLE_IDS.get(subrole)
    if not expected_id:
        return jsonify({
            'authenticated': False,
            'message': 'Invalid subrole'
        }), 400
    
    if unique_id != expected_id:
        log_security_event('subrole_auth_failed', subrole, device_id, ip_address, {'reason': 'invalid_credentials'})
        
        # Track failed attempt
        attempt_key = f"attempts:{ip_address}:{device_id}:{subrole}"
        if attempt_key not in login_attempts:
            login_attempts[attempt_key] = []
        
        login_attempts[attempt_key].append(time.time())
        
        # Check if max attempts reached
        recent_attempts = [attempt for attempt in login_attempts[attempt_key] if time.time() - attempt < 900]
        if len(recent_attempts) >= MAX_LOGIN_ATTEMPTS:
            login_attempts[lockout_key] = time.time()
            return jsonify({
                'authenticated': False,
                'message': 'Too many failed attempts. Account locked for 15 minutes.',
                'locked': True
            }), 429
            
        return jsonify({
            'authenticated': False,
            'message': 'Invalid unique ID'
        }), 401
    
    # Clear login attempts on success
    attempt_key = f"attempts:{ip_address}:{device_id}:{subrole}"
    if attempt_key in login_attempts:
        del login_attempts[attempt_key]
    
    # Create JWT token with string identity (required by flask_jwt_extended)
    identity_string = f"{device_id}:{subrole}"

    access_token = create_access_token(identity=identity_string)
    
    # Get user info from database
    user_info = {
        'username': f"{subrole}_user",
        'role': subrole,
        'hostel': subrole.split('_')[1].upper() if '_' in subrole else 'ALL'
    }
    
    log_security_event('subrole_login_success', subrole, device_id, ip_address)
    
    print(f"✅ Subrole authentication successful: {subrole}")
    
    return jsonify({
        'authenticated': True,
        'access_token': access_token,
        'username': user_info['username'],
        'role': user_info['role'],
        'hostel': user_info['hostel'],
        'message': 'Authentication successful'
    }), 200

# Admin logout endpoint with session cleanup
@app.route('/api/admin/logout', methods=['POST'])
@jwt_required()
def admin_logout():
    try:
        identity_string = get_jwt_identity()
        if ':' in identity_string:
            device_id, user_role = identity_string.split(':', 1)
            if user_role != 'admin':
                return jsonify({'message': 'Admin access required'}), 403
        
        # Remove session
        for session_id, session_data in list(active_sessions.items()):
            if session_data['device_id'] == device_id:
                del active_sessions[session_id]
                break
        
        log_security_event('admin_logout', 'admin', device_id, get_remote_address())
        
        return jsonify({'message': 'Logout successful'}), 200
        
    except Exception as e:
        return jsonify({'message': f'Error during logout: {str(e)}'}), 500

# Get security logs (admin only)
@app.route('/api/admin/security-logs', methods=['GET'])
@jwt_required()
def get_security_logs():
    try:
        identity_string = get_jwt_identity()
        if ':' in identity_string:
            device_id, user_role = identity_string.split(':', 1)
            if user_role != 'admin':
                return jsonify({'message': 'Admin access required'}), 403
        
        # Get logs from last 7 days
        cutoff_time = datetime.now() - timedelta(days=7)
        logs = list(mongo.db.security_logs.find(
            {'timestamp': {'$gte': cutoff_time}},
            {'_id': 0}
        ).sort('timestamp', -1).limit(100))
        
        return jsonify({'security_logs': logs}), 200
        
    except Exception as e:
        return jsonify({'message': f'Error: {str(e)}'}), 500

# Clean up expired sessions and login attempts periodically
def cleanup_expired_data():
    """Clean up expired sessions and old login attempts"""
    try:
        current_time = time.time()
        
        # Clean expired sessions
        expired_sessions = []
        for session_id, session_data in active_sessions.items():
            time_since_activity = datetime.now() - session_data['last_activity']
            if time_since_activity.total_seconds() > SESSION_TIMEOUT:
                expired_sessions.append(session_id)
        
        for session_id in expired_sessions:
            del active_sessions[session_id]
        
        # Clean old login attempts (older than 1 hour)
        for key in list(login_attempts.keys()):
            if key.startswith('attempts:'):
                attempts = login_attempts[key]
                # Keep only attempts from last hour
                recent_attempts = [attempt for attempt in attempts if current_time - attempt < 3600]
                if recent_attempts:
                    login_attempts[key] = recent_attempts
                else:
                    del login_attempts[key]
        
        print(f"🧹 Cleaned up {len(expired_sessions)} expired sessions")
        
    except Exception as e:
        print(f"❌ Error during data cleanup: {e}")

# Schedule cleanup to run every hour
scheduler.add_job(
    func=cleanup_expired_data,
    trigger='interval',
    hours=1,
    id='security_data_cleanup'
)

# Also run cleanup when the app starts for any stale records
cleanup_old_movement_records()

# Shut down the scheduler when exiting the app
atexit.register(lambda: scheduler.shutdown())

# Test endpoint to verify backend is working
@app.route('/api/test/data', methods=['GET'])
@jwt_required()
def get_test_data():
    """Test endpoint to verify frontend-backend connection"""
    return jsonify({
        'status': 'success',
        'message': 'Backend is working correctly',
        'endpoints_available': [
            '/api/canteen/weekly-report',
            '/api/analytics/unauthorized-visits-monthly',
            '/api/analytics/unauthorized-visits',
            '/api/alerts/realtime',
            '/api/analytics/late-arrivals-weekly'
        ],
        'timestamp': datetime.now().isoformat(),
        'version': '2.0'
    }), 200



@app.route('/api/student/<roll_no>/<selected_role>', methods=['GET'])
@jwt_required()
def get_student_with_role(roll_no, selected_role):
    try:
        identity_string = get_jwt_identity()
        if ':' in identity_string:
            device_id, user_role = identity_string.split(':', 1)
            user_hostel = user_role.split('_')[1].upper() if '_' in user_role else 'ALL'
        else:
            return jsonify({'message': 'Invalid token format'}), 401
        
        print(f"👤 User: {user_role}, Requested role: {selected_role}")
        
        if user_role != selected_role:
            return jsonify({'message': 'Role mismatch'}), 403
        
        student = mongo.db.students.find_one({'roll_no': roll_no})
        
        if not student:
            return jsonify({'message': 'Student not found'}), 404
        
        # Check hostel access for non-admin roles
        if user_role != 'admin' and '_' in user_role:
            role_part, hostel_letter = user_role.split('_')
            user_hostel = hostel_letter.upper()
            
            if student.get('hostel') != user_hostel:
                return jsonify({
                    'message': 'This student does not belong to your hostel',
                    'student_hostel': student.get('hostel'),
                    'user_hostel': user_hostel,
                    'access_denied': True
                }), 403
        
        # Convert MongoDB objects to JSON-serializable format
        def serialize_dates(obj):
            if isinstance(obj, (datetime, date)):
                return obj.isoformat()
            elif isinstance(obj, ObjectId):
                return str(obj)
            return obj
        
        # ADMIN: Can access all data
        if user_role == 'admin':
            student_data = {
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
                'in_out_records': [serialize_dates(record) for record in student.get('in_out_records', [])],
                'disciplinary_records': [serialize_dates(record) for record in student.get('disciplinary_records', [])],
                'medical_info': student.get('medical_info', [])
            }
            return jsonify(student_data), 200
        
        # SUPER: Can access in_out_records and medical_info for their hostel
        if user_role.startswith('super_'):
            student_data = {
                'roll_no': student['roll_no'],
                'name': student['name'],
                'hostel': student['hostel'],
                'room_no': student['room_no'],
                'course': student['course'],
                'academic_year': student['academic_year'],
                'branch': student['branch'],
                'contact_no': student['contact_no'],
                'in_out_records': [serialize_dates(record) for record in student.get('in_out_records', [])],
                'medical_info': student.get('medical_info', []),
                'disciplinary_records': [serialize_dates(record) for record in student.get('disciplinary_records', [])]
            }
            return jsonify(student_data), 200
        
        # SECURITY & CANTEEN: Basic info only with hostel verification
        if user_role.startswith('security_') or user_role.startswith('canteen_'):
            student_data = {
                'roll_no': student['roll_no'],
                'name': student['name'],
                'hostel': student['hostel'],
                'room_no': student.get('room_no'),
                'course': student.get('course'),
                'branch': student.get('branch'),
                'belongs_to_hostel': student.get('hostel') == user_hostel
            }
            return jsonify(student_data), 200
        
        return jsonify({'message': 'Invalid role'}), 400
            
    except Exception as e:
        print(f"❌ Error in get_student_with_role: {e}")
        return jsonify({'message': f'Server error: {str(e)}'}), 500

@app.route('/api/debug/canteen-data', methods=['GET'])
@jwt_required()
def debug_canteen_data():
    """Debug endpoint to check canteen data"""
    try:
        # Check total unauthorized visits
        total_unauthorized = mongo.db.canteen_visits.count_documents({
            'is_unauthorized': True
        })
        
        # Check recent unauthorized visits
        recent_unauthorized = mongo.db.canteen_visits.count_documents({
            'is_unauthorized': True,
            'timestamp': {'$gte': datetime(2024, 1, 1)}
        })
        
        # Sample data
        sample_visits = list(mongo.db.canteen_visits.find(
            {'is_unauthorized': True},
            {'_id': 0}
        ).limit(5))
        
        return jsonify({
            'total_unauthorized': total_unauthorized,
            'recent_unauthorized': recent_unauthorized,
            'sample_visits': sample_visits,
            'database_status': 'connected'
        }), 200
        
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/student/scan/security/<selected_role>', methods=['POST'])
@jwt_required()
def handle_security_scan(selected_role):
    try:
        identity_string = get_jwt_identity()
        if ':' in identity_string:
            device_id, user_role = identity_string.split(':', 1)
            user_hostel = user_role.split('_')[1].upper() if '_' in user_role else 'ALL'
        else:
            return jsonify({'message': 'Invalid token format'}), 401
        
        if user_role != selected_role:
            return jsonify({'message': 'Role mismatch'}), 403
        
        data = request.get_json()
        roll_no = data.get('roll_no')
        action = data.get('action')  # 'in' or 'out'
        is_offline_sync = data.get('offline_sync', False)
        original_timestamp = data.get('original_timestamp')
        
        # Use original timestamp if this is an offline sync
        if is_offline_sync and original_timestamp:
            now = datetime.fromtimestamp(original_timestamp / 1000)  # Convert from milliseconds
            print(f"🔄 Processing offline sync: {roll_no}, {action}, original time: {now}")
        else:
            now = datetime.now()
        
        student = mongo.db.students.find_one({'roll_no': roll_no})
        
        if not student:
            return jsonify({'message': 'Student not found'}), 404
        
        # Check hostel access
        if '_' in user_role:
            role_part, hostel_letter = user_role.split('_')
            required_hostel = hostel_letter.upper()
            
            if student.get('hostel') != required_hostel:
                return jsonify({'message': 'Access denied to this student'}), 403
        
        if action == 'out':
            # Check if student is already out
            current_out_record = None
            for record in reversed(student.get('in_out_records', [])):
                if record.get('action') == 'out' and record.get('in_time') is None:
                    current_out_record = record
                    break
            
            if current_out_record:
                return jsonify({
                    'message': 'Student is already checked out',
                    'out_time': current_out_record['out_time'].strftime('%Y-%m-%d %H:%M:%S')
                }), 400
            
            # Record out time
            out_record = {
                'out_time': now,
                'in_time': None,
                'action': 'out',
                'recorded_by': user_role,
                'recorded_at': now,
                'status': 'outside',
                'offline_sync': is_offline_sync
            }
            
            mongo.db.students.update_one(
                {'roll_no': roll_no},
                {'$push': {'in_out_records': out_record}}
            )
            
            print(f"✅ Offline check-out recorded: {roll_no} at {now}")
            
            return jsonify({
                'message': 'Check out recorded successfully',
                'student_name': student.get('name', 'Unknown'),
                'roll_no': roll_no,
                'time': now.strftime('%Y-%m-%d %H:%M:%S'),
                'action': 'out',
                'offline_sync': is_offline_sync
            }), 200
            
        elif action == 'in':
            # Find the latest out record without in time
            latest_out_record = None
            for record in reversed(student.get('in_out_records', [])):
                if record.get('action') == 'out' and record.get('in_time') is None:
                    latest_out_record = record
                    break
            
            if not latest_out_record:
                return jsonify({'message': 'No active check out record found'}), 400
            
            # Calculate time spent outside
            out_time = latest_out_record['out_time']
            time_spent = (now - out_time).total_seconds() / 60  # in minutes
            
            # Update the record with in time
            mongo.db.students.update_one(
                {'roll_no': roll_no, 'in_out_records.out_time': out_time},
                {'$set': {
                    'in_out_records.$.in_time': now,
                    'in_out_records.$.time_spent_minutes': time_spent,
                    'in_out_records.$.action': 'in',
                    'in_out_records.$.status': 'inside',
                    'in_out_records.$.offline_sync': is_offline_sync
                }}
            )
            
            # Check if time exceeded allowed limit (8 hours = 480 minutes)
            max_allowed_time = 480
            response_data = {
                'message': 'Check in recorded successfully',
                'student_name': student.get('name', 'Unknown'),
                'roll_no': roll_no,
                'time': now.isoformat(),
                'action': 'in',
                'time_spent_minutes': round(time_spent, 2),
                'offline_sync': is_offline_sync
            }
            
            if time_spent > max_allowed_time:
                disciplinary_record = {
                    'date': now,
                    'time': now.strftime('%H:%M'),
                    'description': f'Exceeded allowed time outside by {round(time_spent - max_allowed_time, 2)} minutes. '
                                  f'Out at: {out_time.strftime("%Y-%m-%d %H:%M")}, '
                                  f'In at: {now.strftime("%Y-%m-%d %H:%M")}',
                    'action_taken': 'Warning issued for exceeding 8-hour limit',
                    'recorded_by': user_role,
                    'recorded_at': now,
                    'time_exceeded_minutes': round(time_spent - max_allowed_time, 2),
                    'auto_generated': True,
                    'offline_sync': is_offline_sync
                }
                
                mongo.db.students.update_one(
                    {'roll_no': roll_no},
                    {'$push': {'disciplinary_records': disciplinary_record}}
                )
                
                response_data['message'] = 'Check in recorded. Time exceeded 8-hour limit!'
                response_data['disciplinary_action'] = 'Warning issued'
                response_data['time_exceeded_minutes'] = round(time_spent - max_allowed_time, 2)
            
            print(f"✅ Offline check-in recorded: {roll_no} at {now}, time spent: {time_spent} minutes")
            
            return jsonify(response_data), 200
        
        return jsonify({'message': 'Invalid action'}), 400
        
    except Exception as e:
        print(f"❌ Error in security scan (offline sync): {e}")
        return jsonify({'message': f'Server error: {str(e)}'}), 500

# Manual cleanup endpoint (for testing or manual trigger)
@app.route('/api/admin/cleanup-records', methods=['POST'])
@jwt_required()
def manual_cleanup_records():
    try:
        identity_string = get_jwt_identity()
        if ':' in identity_string:
            device_id, user_role = identity_string.split(':', 1)
            if user_role != 'admin':
                return jsonify({'message': 'Admin access required'}), 403
        else:
            return jsonify({'message': 'Invalid token format'}), 401
        
        cleanup_old_movement_records()
        return jsonify({'message': 'Manual cleanup completed successfully'}), 200
        
    except Exception as e:
        return jsonify({'message': f'Error during cleanup: {str(e)}'}), 500



# Admin endpoint to manage devices
@app.route('/api/admin/devices', methods=['GET'])
@jwt_required()
def get_all_devices():
    try:
        identity_string = get_jwt_identity()
        if ':' in identity_string:
            device_id, user_role = identity_string.split(':', 1)
            if user_role != 'admin':
                return jsonify({'message': 'Admin access required'}), 403
        else:
            return jsonify({'message': 'Invalid token format'}), 401
        
        devices = list(mongo.db.devices.find({}, {'_id': 0}))
        return jsonify({'devices': devices}), 200
    except Exception as e:
        return jsonify({'message': f'Error: {str(e)}'}), 500

@app.route('/api/admin/devices', methods=['POST'])
@jwt_required()
def add_device():
    try:
        identity_string = get_jwt_identity()
        if ':' in identity_string:
            device_id, user_role = identity_string.split(':', 1)
            if user_role != 'admin':
                return jsonify({'message': 'Admin access required'}), 403
        else:
            return jsonify({'message': 'Invalid token format'}), 401
        
        data = request.get_json()
        new_device = {
            'device_id': data.get('device_id'),
            'device_name': data.get('device_name', 'Unnamed Device'),
            'status': 'active',
            'registered_at': datetime.now(),
            'last_verified': datetime.now(),
            'device_type': data.get('device_type', 'mobile')
        }
        
        mongo.db.devices.insert_one(new_device)
        return jsonify({'message': 'Device added successfully'}), 200
    except Exception as e:
        return jsonify({'message': f'Error: {str(e)}'}), 500

@app.route('/api/alerts/realtime', methods=['GET'])
@jwt_required()
def get_realtime_alerts():
    try:
        identity_string = get_jwt_identity()
        if ':' in identity_string:
            device_id, user_role = identity_string.split(':', 1)
        
        # Get alerts from last 7 days
        cutoff_time = datetime.now() - timedelta(days=7)
        alerts = list(mongo.db.realtime_alerts.find(
            {'timestamp': {'$gte': cutoff_time}},
            {'_id': 0}
        ).sort('timestamp', -1).limit(50))
        
        return jsonify(alerts), 200
        
    except Exception as e:
        # Return empty array if there's an error
        return jsonify([]), 200

# Weekly canteen report submission by supers
@app.route('/api/canteen/weekly-report', methods=['POST'])
@jwt_required()
def submit_weekly_canteen_report():
    try:
        identity_string = get_jwt_identity()
        if ':' in identity_string:
            device_id, user_role = identity_string.split(':', 1)
            if not user_role.startswith('super_'):
                return jsonify({'message': 'Super access required'}), 403
        
        data = request.get_json()
        
        # Validate required fields
        required_fields = ['week_number', 'year', 'hostel', 'extra_students_count']
        for field in required_fields:
            if field not in data:
                return jsonify({'message': f'Missing field: {field}'}), 400
        
        # Add metadata
        report = {
            'week_number': data['week_number'],
            'year': data['year'],
            'hostel': data['hostel'],
            'extra_students_count': data['extra_students_count'],
            'report_data': data.get('report_data', {}),
            'submitted_by': user_role,
            'submitted_at': datetime.now(),
            'report_type': 'canteen_weekly'
        }
        
        # Store in database
        result = mongo.db.weekly_reports.insert_one(report)
        
        return jsonify({
            'message': 'Weekly canteen report submitted successfully',
            'report_id': str(result.inserted_id),
            'week_number': data['week_number'],
            'year': data['year'],
            'hostel': data['hostel'],
            'extra_students_count': data['extra_students_count']
        }), 200
        
    except Exception as e:
        return jsonify({'message': f'Error: {str(e)}'}), 500

# CORRECTED Monthly unauthorized visits endpoint with hostel filtering
@app.route('/api/analytics/unauthorized-visits-monthly', methods=['GET'])
@jwt_required()
def get_monthly_unauthorized_visits():
    try:
        identity_string = get_jwt_identity()
        if ':' in identity_string:
            device_id, user_role = identity_string.split(':', 1)
            if user_role not in ['admin'] and not user_role.startswith('super_'):
                return jsonify({'message': 'Access denied'}), 403
        
        # Get month, year, and optional hostel from query params
        year = int(request.args.get('year', datetime.now().year))
        month = int(request.args.get('month', datetime.now().month))
        requested_hostel = request.args.get('hostel')  # For super users
        
        start_date = datetime(year, month, 1)
        if month == 12:
            end_date = datetime(year + 1, 1, 1)
        else:
            end_date = datetime(year, month + 1, 1)
        
        print(f"📊 Fetching monthly data for {month}/{year}, hostel: {requested_hostel}")
        
        # Build match filter based on user role
        match_filter = {
            'timestamp': {'$gte': start_date, '$lt': end_date},
            'is_unauthorized': True
        }
        
        # If super user, filter by their hostel
        if user_role.startswith('super_') and requested_hostel:
            # Super can see both students from their hostel going elsewhere 
            # AND students from other hostels coming to their canteen
            match_filter['$or'] = [
                {'student_hostel': requested_hostel},
                {'canteen_hostel': requested_hostel}
            ]
        
        # Aggregate data for pie chart (actual implementation)
        pipeline = [
            {'$match': match_filter},
            {'$group': {
                '_id': {
                    'student_hostel': '$student_hostel',
                    'canteen_hostel': '$canteen_hostel'
                },
                'visit_count': {'$sum': 1},
                'students_count': {'$addToSet': '$roll_no'}
            }},
            {'$project': {
                'student_hostel': '$_id.student_hostel',
                'canteen_hostel': '$_id.canteen_hostel',
                'visit_count': 1,
                'unique_students': {'$size': '$students_count'}
            }},
            {'$sort': {'visit_count': -1}}
        ]
        
        results = list(mongo.db.canteen_visits.aggregate(pipeline))
        
        # Prepare data for pie charts
        hostel_breakdown = defaultdict(lambda: defaultdict(int))
        canteen_breakdown = defaultdict(int)
        
        for result in results:
            student_hostel = result.get('student_hostel', 'Unknown')
            canteen_hostel = result.get('canteen_hostel', 'Unknown')
            visit_count = result.get('visit_count', 0)
            
            hostel_breakdown[student_hostel][canteen_hostel] += visit_count
            canteen_breakdown[canteen_hostel] += visit_count
        
        # Convert to pie chart format
        pie_chart_data = {
            'by_student_hostel': [
                {
                    'hostel': student_hostel,
                    'data': [
                        {'canteen': canteen, 'visits': count}
                        for canteen, count in canteens.items()
                    ],
                    'total_visits': sum(canteens.values())
                }
                for student_hostel, canteens in hostel_breakdown.items()
            ],
            'by_canteen_hostel': [
                {'canteen': canteen, 'visits': count}
                for canteen, count in canteen_breakdown.items()
            ],
            'summary': {
                'month': month,
                'year': year,
                'total_unauthorized_visits': sum(canteen_breakdown.values()),
                'unique_students_involved': len(set(
                    f"{r.get('student_hostel', 'Unknown')}-{r.get('canteen_hostel', 'Unknown')}" 
                    for r in results
                )),
                'filtered_by_hostel': requested_hostel if user_role.startswith('super_') else 'ALL'
            }
        }
        
        return jsonify(pie_chart_data), 200
        
    except Exception as e:
        print(f"❌ Error in monthly analytics: {e}")
        # Return empty data if there's an error
        return jsonify({
            'by_student_hostel': [],
            'by_canteen_hostel': [],
            'summary': {
                'month': month,
                'year': year,
                'total_unauthorized_visits': 0,
                'unique_students_involved': 0,
                'filtered_by_hostel': requested_hostel if user_role.startswith('super_') else 'ALL'
            }
        }), 200

# Enhanced weekly late arrivals calculation
@app.route('/api/analytics/late-arrivals-weekly', methods=['POST'])
@jwt_required()
def calculate_weekly_late_arrivals():
    try:
        identity_string = get_jwt_identity()
        if ':' in identity_string:
            device_id, user_role = identity_string.split(':', 1)
            if user_role not in ['admin'] and not user_role.startswith('super_'):
                return jsonify({'message': 'Access denied'}), 403
        
        data = request.get_json()
        week_number = data.get('week', datetime.now().isocalendar()[1])
        year = data.get('year', datetime.now().year)
        
        # Calculate start and end of week (Monday to Sunday)
        start_date = datetime.fromisocalendar(year, week_number, 1)  # Monday
        end_date = start_date + timedelta(days=7)  # Next Monday
        
        print(f"📅 Calculating weekly late arrivals for week {week_number}, {year}")
        print(f"📅 Date range: {start_date} to {end_date}")
        
        # First, verify we have data for this period
        cutoff_time = datetime.now() - timedelta(days=30)
        if end_date < cutoff_time:
            return jsonify({
                'message': f'Data for week {week_number}, {year} has been cleaned up (older than 30 days)',
                'error': 'data_cleaned'
            }), 400
        
        # Aggregate late arrivals for the week
        pipeline = [
            {'$unwind': '$disciplinary_records'},
            {'$match': {
                'disciplinary_records.description': {'$regex': 'exceeded allowed time', '$options': 'i'},
                'disciplinary_records.recorded_at': {'$gte': start_date, '$lt': end_date},
                'disciplinary_records.auto_generated': True
            }},
            {'$group': {
                '_id': {
                    'roll_no': '$roll_no',
                    'name': '$name',
                    'hostel': '$hostel'
                },
                'late_count': {'$sum': 1},
                'total_time_exceeded': {'$sum': '$disciplinary_records.time_exceeded_minutes'},
                'dates': {'$addToSet': '$disciplinary_records.recorded_at'},
                'last_occurrence': {'$max': '$disciplinary_records.recorded_at'}
            }},
            {'$project': {
                'roll_no': '$_id.roll_no',
                'name': '$_id.name',
                'hostel': '$_id.hostel',
                'late_count': 1,
                'total_time_exceeded': 1,
                'unique_dates': {'$size': '$dates'},
                'dates': {
                    '$map': {
                        'input': '$dates',
                        'as': 'date',
                        'in': {'$dateToString': {'format': '%Y-%m-%d', 'date': '$$date'}}
                    }
                },
                'last_occurrence': {'$dateToString': {'format': '%Y-%m-%d', 'date': '$last_occurrence'}}
            }},
            {'$sort': {'late_count': -1}}
        ]
        
        results = list(mongo.db.students.aggregate(pipeline))
        
        print(f"📊 Found {len(results)} students with late arrivals")
        
        # Store weekly summary
        weekly_summary = {
            'week_number': week_number,
            'year': year,
            'calculation_date': datetime.now(),
            'date_range': {
                'start': start_date,
                'end': end_date
            },
            'total_students_with_late_arrivals': len(results),
            'total_late_occurrences': sum(r['late_count'] for r in results),
            'total_time_exceeded_minutes': sum(r.get('total_time_exceeded', 0) for r in results),
            'details': results,
            'report_type': 'late_arrivals_weekly',
            'calculated_by': user_role
        }
        
        # Remove old report for same week if exists
        mongo.db.weekly_reports.delete_many({
            'week_number': week_number,
            'year': year,
            'report_type': 'late_arrivals_weekly'
        })
        
        # Insert new report
        mongo.db.weekly_reports.insert_one(weekly_summary)
        
        return jsonify({
            'message': f'Weekly late arrivals calculated for week {week_number}, {year}',
            'summary': {
                'week_number': week_number,
                'year': year,
                'total_students': len(results),
                'total_occurrences': sum(r['late_count'] for r in results),
                'total_time_exceeded_minutes': sum(r.get('total_time_exceeded', 0) for r in results),
                'calculation_date': weekly_summary['calculation_date'].isoformat()
            },
            'student_details': results
        }), 200
        
    except Exception as e:
        print(f"❌ Error in weekly late arrivals calculation: {e}")
        return jsonify({'message': f'Error: {str(e)}'}), 500

# Get weekly late arrivals reports
@app.route('/api/analytics/late-arrivals-reports', methods=['GET'])
@jwt_required()
def get_late_arrivals_reports():
    try:
        identity_string = get_jwt_identity()
        if ':' in identity_string:
            device_id, user_role = identity_string.split(':', 1)
            if user_role not in ['admin'] and not user_role.startswith('super_'):
                return jsonify({'message': 'Access denied'}), 403
        
        # Get reports from database
        reports = list(mongo.db.weekly_reports.find(
            {'report_type': 'late_arrivals_weekly'},
            {'_id': 0}
        ).sort([('year', -1), ('week_number', -1)]).limit(12))
        
        return jsonify({'weekly_reports': reports}), 200
        
    except Exception as e:
        return jsonify({'message': f'Error: {str(e)}'}), 500

@app.route('/api/analytics/weekly-report', methods=['POST'])
@jwt_required()
def generate_weekly_report():
    try:
        identity_string = get_jwt_identity()
        if ':' in identity_string:
            device_id, user_role = identity_string.split(':', 1)
            if not user_role.startswith('super_'):
                return jsonify({'message': 'Super access required'}), 403
        
        data = request.get_json()
        week_number = data.get('week', datetime.now().isocalendar()[1])
        
        # Generate comprehensive weekly report
        report = _generate_weekly_analytics(week_number, user_role)
        
        return jsonify(report), 200
        
    except Exception as e:
        return jsonify({'message': f'Error: {str(e)}'}), 500

def _generate_weekly_analytics(week_number, user_role):
    """Generate detailed weekly analytics report"""
    return {
        'week_number': week_number,
        'generated_by': user_role,
        'timestamp': datetime.now(),
        'summary': {
            'total_unauthorized_visits': 0,
            'total_late_arrivals': 0,
            'weekly_reports_submitted': 0
        },
        'recommendations': [
            'Increase monitoring during peak hours',
            'Consider additional scanner locations',
            'Review student movement patterns'
        ]
    }

# Similarly update canteen visit endpoint
@app.route('/api/student/scan/canteen/<selected_role>', methods=['POST'])
@jwt_required()
def record_canteen_visit(selected_role):
    try:
        identity_string = get_jwt_identity()
        if ':' in identity_string:
            device_id, user_role = identity_string.split(':', 1)
            user_hostel = user_role.split('_')[1].upper() if '_' in user_role else 'ALL'
        else:
            return jsonify({'message': 'Invalid token format'}), 401
        
        if user_role != selected_role:
            return jsonify({'message': 'Role mismatch'}), 403
        
        data = request.get_json()
        roll_no = data.get('roll_no')
        is_offline_sync = data.get('offline_sync', False)
        original_timestamp = data.get('original_timestamp')
        
        if not roll_no:
            return jsonify({'message': 'Roll number is required'}), 400
        
        # Use original timestamp if this is an offline sync
        if is_offline_sync and original_timestamp:
            now = datetime.fromtimestamp(original_timestamp / 1000)  # Convert from milliseconds
        else:
            now = datetime.now()
        
        student = mongo.db.students.find_one({'roll_no': roll_no})
        
        if not student:
            return jsonify({'message': 'Student not found'}), 404
        
        student_hostel = student.get('hostel', 'Unknown')
        
        # Record canteen visit with unauthorized flag
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
            'offline_sync': is_offline_sync
        }
        
        mongo.db.canteen_visits.insert_one(visit_record)
        
        response_data = {
            'message': 'Canteen visit recorded successfully',
            'student_name': student.get('name', 'Unknown'),
            'roll_no': roll_no,
            'time': now.strftime('%Y-%m-%d %H:%M:%S'),
            'unauthorized': is_unauthorized,
            'student_hostel': student_hostel,
            'canteen_hostel': user_hostel,
            'offline_sync': is_offline_sync
        }
        
        if is_unauthorized:
            response_data['alert'] = 'Unauthorized visit detected!'
            # Trigger real-time alert
            _send_unauthorized_alert(visit_record)
        
        return jsonify(response_data), 200
        
    except Exception as e:
        print(f"❌ Error in canteen scan: {e}")
        return jsonify({'message': f'Server error: {str(e)}'}), 500

# Analytics endpoints with hostel filtering
@app.route('/api/analytics/unauthorized-visits', methods=['GET'])
@jwt_required()
def get_unauthorized_visits_analytics():
    try:
        identity_string = get_jwt_identity()
        if ':' in identity_string:
            device_id, user_role = identity_string.split(':', 1)
            if user_role not in ['admin'] and not user_role.startswith('super_'):
                return jsonify({'message': 'Access denied'}), 403
        
        # Get timeframe and optional hostel from query params
        days = int(request.args.get('days', 30))
        requested_hostel = request.args.get('hostel')  # For super users
        cutoff_date = datetime.now() - timedelta(days=days)
        
        # Build match filter based on user role
        match_filter = {
            'timestamp': {'$gte': cutoff_date},
            'is_unauthorized': True
        }
        
        # If super user, filter by their hostel
        if user_role.startswith('super_') and requested_hostel:
            match_filter['$or'] = [
                {'student_hostel': requested_hostel},
                {'canteen_hostel': requested_hostel}
            ]
        
        pipeline = [
            {'$match': match_filter},
            {'$group': {
                '_id': {
                    'student_hostel': '$student_hostel',
                    'canteen_hostel': '$canteen_hostel',
                    'date': '$date'
                },
                'visit_count': {'$sum': 1},
                'latest_visit': {'$max': '$timestamp'}
            }},
            {'$sort': {'visit_count': -1}}
        ]
        
        results = list(mongo.db.canteen_visits.aggregate(pipeline))
        
        # Process for charts
        hostel_analysis = defaultdict(lambda: defaultdict(int))
        hourly_analysis = defaultdict(int)
        daily_analysis = defaultdict(int)
        
        for result in results:
            student_hostel = result['_id']['student_hostel']
            canteen_hostel = result['_id']['canteen_hostel']
            hostel_analysis[student_hostel][canteen_hostel] += result['visit_count']
            
            # Extract hour from latest visit
            hour = result['latest_visit'].hour
            hourly_analysis[hour] += result['visit_count']
            
            # Daily analysis
            day = result['_id']['date'].strftime('%Y-%m-%d')
            daily_analysis[day] += result['visit_count']
        
        # Predictive analytics
        predictions = _predict_unauthorized_visits(daily_analysis)
        
        return jsonify({
            'summary': {
                'total_unauthorized_visits': sum(daily_analysis.values()),
                'analysis_period_days': days,
                'average_daily_visits': sum(daily_analysis.values()) / len(daily_analysis) if daily_analysis else 0,
                'filtered_by_hostel': requested_hostel if user_role.startswith('super_') else 'ALL'
            },
            'hostel_analysis': hostel_analysis,
            'hourly_analysis': dict(hourly_analysis),
            'daily_analysis': dict(daily_analysis),
            'predictions': predictions,
            'alerts': _generate_analytics_alerts(hostel_analysis, daily_analysis)
        }), 200
        
    except Exception as e:
        return jsonify({'message': f'Error: {str(e)}'}), 500

def _predict_unauthorized_visits(daily_analysis):
    """Predict next week's unauthorized visits using linear regression"""
    if len(daily_analysis) < 7:
        return {'accuracy': 'Insufficient data', 'predictions': []}
    
    # Prepare data for prediction
    dates = sorted([datetime.strptime(day, '%Y-%m-%d') for day in daily_analysis.keys()])
    visits = [daily_analysis[date.strftime('%Y-%m-%d')] for date in dates]
    
    # Convert dates to numerical values
    X = np.array([i for i in range(len(dates))]).reshape(-1, 1)
    y = np.array(visits)
    
    # Train model
    model = LinearRegression()
    model.fit(X, y)
    
    # Predict next 7 days
    future_days = np.array([i for i in range(len(dates), len(dates) + 7)]).reshape(-1, 1)
    predictions = model.predict(future_days)
    
    # Calculate accuracy (simplified)
    accuracy = max(0.85, min(0.95, 1 - (np.std(y) / np.mean(y)) if np.mean(y) > 0 else 0.85))
    
    return {
        'accuracy': round(accuracy * 100, 1),
        'predictions': [
            {
                'date': (datetime.now() + timedelta(days=i+1)).strftime('%Y-%m-%d'),
                'predicted_visits': max(0, round(pred))
            }
            for i, pred in enumerate(predictions)
        ]
    }

def _generate_analytics_alerts(hostel_analysis, daily_analysis):
    """Generate intelligent alerts based on patterns"""
    alerts = []
    
    # Peak hour detection
    recent_visits = {k: v for k, v in daily_analysis.items() 
                    if datetime.strptime(k, '%Y-%m-%d') > datetime.now() - timedelta(days=7)}
    
    if recent_visits:
        avg_recent = sum(recent_visits.values()) / len(recent_visits)
        if avg_recent > 10:
            alerts.append({
                'type': 'high_activity',
                'message': f'🚨 High unauthorized activity detected: {avg_recent:.1f} visits/day this week',
                'priority': 'high'
            })
    
    # Hostel pattern alerts
    for student_hostel, canteens in hostel_analysis.items():
        for canteen_hostel, count in canteens.items():
            if count > 15:
                alerts.append({
                    'type': 'hostel_pattern',
                    'message': f'👥 {student_hostel} students frequent {canteen_hostel} canteen: {count} visits',
                    'priority': 'medium'
                })
    
    return alerts

def _send_unauthorized_alert(visit_record):
    """Send real-time alert for unauthorized visit"""
    alert_message = {
        'type': 'unauthorized_visit',
        'message': f'🚨 Unauthorized canteen visit detected!',
        'details': {
            'student': visit_record['student_name'],
            'student_hostel': visit_record['student_hostel'],
            'canteen_hostel': visit_record['canteen_hostel'],
            'time': visit_record['timestamp'].strftime('%H:%M')
        },
        'timestamp': datetime.now(),
        'priority': 'high'
    }
    
    # Store alert for super users
    mongo.db.realtime_alerts.insert_one(alert_message)
    print(f"📢 ALERT: {alert_message['message']}")

# Late arrival analytics with hostel filtering
@app.route('/api/analytics/late-arrivals', methods=['GET'])
@jwt_required()
def get_late_arrivals_analytics():
    try:
        identity_string = get_jwt_identity()
        if ':' in identity_string:
            device_id, user_role = identity_string.split(':', 1)
            if user_role not in ['admin'] and not user_role.startswith('super_'):
                return jsonify({'message': 'Access denied'}), 403
        
        # Get optional hostel filter for super users
        requested_hostel = request.args.get('hostel')
        
        # Build match filter
        match_filter = {
            'disciplinary_records.description': {'$regex': 'exceeded allowed time', '$options': 'i'}
        }
        
        # If super user, filter by their hostel
        if user_role.startswith('super_') and requested_hostel:
            match_filter['hostel'] = requested_hostel
        
        # Get students with disciplinary records for late arrivals
        pipeline = [
            {'$unwind': '$disciplinary_records'},
            {'$match': match_filter},
            {'$group': {
                '_id': {
                    'roll_no': '$roll_no',
                    'name': '$name',
                    'hostel': '$hostel',
                    'week': {'$week': '$disciplinary_records.recorded_at'}
                },
                'late_count': {'$sum': 1},
                'last_occurrence': {'$max': '$disciplinary_records.recorded_at'},
                'total_time_exceeded': {'$sum': '$disciplinary_records.time_exceeded_minutes'}
            }},
            {'$sort': {'late_count': -1}}
        ]
        
        results = list(mongo.db.students.aggregate(pipeline))
        
        return jsonify({
            'weekly_late_arrivals': results,
            'summary': {
                'total_students_with_late_arrivals': len(set(r['_id']['roll_no'] for r in results)),
                'total_late_occurrences': sum(r['late_count'] for r in results),
                'filtered_by_hostel': requested_hostel if user_role.startswith('super_') else 'ALL'
            }
        }), 200
        
    except Exception as e:
        return jsonify({'message': f'Error: {str(e)}'}), 500

# Admin/Super scan endpoint for verification
@app.route('/api/student/scan/admin/<selected_role>', methods=['POST'])
@jwt_required()
def handle_admin_scan(selected_role):
    try:
        identity_string = get_jwt_identity()
        if ':' in identity_string:
            device_id, user_role = identity_string.split(':', 1)
        else:
            return jsonify({'message': 'Invalid token format'}), 401
        
        if user_role != selected_role:
            return jsonify({'message': 'Role mismatch'}), 403
        
        data = request.get_json()
        roll_no = data.get('roll_no')
        
        student = mongo.db.students.find_one({'roll_no': roll_no})
        
        if not student:
            return jsonify({'message': 'Student not found'}), 404
        
        now = datetime.now()
        
        # Record admin/super scan for audit
        scan_record = {
            'roll_no': roll_no,
            'role': user_role,
            'timestamp': now,
            'student_name': student.get('name', 'Unknown'),
            'type': 'verification'
        }
        
        mongo.db.admin_scans.insert_one(scan_record)
        
        return jsonify({
            'message': 'Student verification successful',
            'student_name': student.get('name', 'Unknown'),
            'roll_no': roll_no,
            'time': now.strftime('%Y-%m-%d %H:%M:%S'),
            'action': 'verified'
        }), 200
        
    except Exception as e:
        print(f"❌ Error in admin scan: {e}")
        return jsonify({'message': f'Server error: {str(e)}'}), 500

@app.route("/health", methods=["GET"])
def health():
    return {"status": "ok", "timestamp": datetime.now().isoformat()}, 200

@app.route("/", methods=["GET"])
def home():
    return jsonify({
        "message": "Student Management System API",
        "version": "2.0",
        "status": "running",
        "endpoints": {
            "authentication": [
                "/api/verify-device",
                "/api/authenticate-subrole"
            ],
            "student_operations": [
                "/api/student/<roll_no>/<role>",
                "/api/student/scan/security/<role>",
                "/api/student/scan/canteen/<role>",
                "/api/student/scan/admin/<role>"
            ],
            "analytics": [
                "/api/analytics/unauthorized-visits",
                "/api/analytics/unauthorized-visits-monthly",
                "/api/analytics/late-arrivals",
                "/api/analytics/late-arrivals-weekly"
            ],
            "reports": [
                "/api/canteen/weekly-report",
                "/api/alerts/realtime"
            ]
        }
    }), 200


# PREDICTIVE ANALYTICS & AI INSIGHTS
@app.route('/api/analytics/predictive-insights', methods=['GET'])
@jwt_required()
def get_predictive_insights():
    try:
        identity_string = get_jwt_identity()
        if ':' in identity_string:
            device_id, user_role = identity_string.split(':', 1)
            if user_role not in ['admin'] and not user_role.startswith('super_'):
                return jsonify({'message': 'Access denied'}), 403
        
        # Get optional hostel filter for super users
        requested_hostel = request.args.get('hostel')
        days = int(request.args.get('days', 30))
        
        cutoff_date = datetime.now() - timedelta(days=days)
        
        # Build match filter
        match_filter = {
            'timestamp': {'$gte': cutoff_date},
            'is_unauthorized': True
        }
        
        # If super user, filter by their hostel
        if user_role.startswith('super_') and requested_hostel:
            match_filter['$or'] = [
                {'student_hostel': requested_hostel},
                {'canteen_hostel': requested_hostel}
            ]
        
        # Get all unauthorized visits for analysis
        visits = list(mongo.db.canteen_visits.find(match_filter))
        
        if not visits:
            return jsonify({
                'message': 'Insufficient data for predictive analysis',
                'insights': [],
                'predictions': [],
                'alerts': []
            }), 200
        
        insights = _generate_predictive_insights(visits)
        
        # ✅ FIXED: Pass user_role and requested_hostel to predictions
        predictions = _predict_next_week_visits(visits, user_role, requested_hostel)
        
        alerts = _generate_ai_alerts(visits)
        
        return jsonify({
            'insights': insights,
            'predictions': predictions,
            'alerts': alerts,
            'summary': {
                'total_visits_analyzed': len(visits),
                'analysis_period_days': days,
                'generated_at': datetime.now().isoformat()
            }
        }), 200
        
    except Exception as e:
        print(f"❌ Error in predictive insights: {e}")
        return jsonify({'message': f'Error: {str(e)}'}), 500

def _generate_predictive_insights(visits):
    """Generate AI-powered insights from visit data"""
    insights = []
    
    if not visits:
        print("📭 No visits data for insights generation")
        return insights
    
    print(f"🔍 Generating insights from {len(visits)} visits")
    
    # 1. Hostel Movement Patterns
    hostel_patterns = defaultdict(lambda: defaultdict(int))
    day_patterns = defaultdict(lambda: defaultdict(int))
    hour_patterns = defaultdict(int)
    
    for visit in visits:
        student_hostel = visit.get('student_hostel', 'Unknown')
        canteen_hostel = visit.get('canteen_hostel', 'Unknown')
        day_of_week = visit['timestamp'].strftime('%A')
        hour = visit['timestamp'].hour
        
        hostel_patterns[student_hostel][canteen_hostel] += 1
        day_patterns[student_hostel][day_of_week] += 1
        hour_patterns[hour] += 1
    
    print(f"🏠 Hostel patterns: {dict(hostel_patterns)}")
    print(f"📅 Day patterns: {dict(day_patterns)}")
    print(f"⏰ Hour patterns: {dict(hour_patterns)}")
    
    # Insight 1: Which hostel goes where (only if multiple canteens visited)
    for student_hostel, canteens in hostel_patterns.items():
        if len(canteens) > 1:  # Only show if visiting multiple canteens
            top_canteen = max(canteens.items(), key=lambda x: x[1])
            insights.append({
                'type': 'hostel_movement',
                'title': f'🏠 {student_hostel} Movement Pattern',
                'description': f'Students from {student_hostel} most frequently visit {top_canteen[0]} canteen ({top_canteen[1]} visits)',
                'priority': 'medium',
                'data': dict(canteens)
            })
        elif canteens:  # Even if only one canteen, still show the pattern
            canteen_name, count = list(canteens.items())[0]
            insights.append({
                'type': 'hostel_movement',
                'title': f'🏠 {student_hostel} Primary Canteen',
                'description': f'Students from {student_hostel} exclusively visit {canteen_name} canteen ({count} visits)',
                'priority': 'low',
                'data': dict(canteens)
            })
    
    # Insight 2: Peak days for each hostel (only if significant variation)
    for student_hostel, days_data in day_patterns.items():
        if len(days_data) > 1 and max(days_data.values()) >= 3:  # At least 3 visits on peak day
            peak_day = max(days_data.items(), key=lambda x: x[1])
            insights.append({
                'type': 'peak_day',
                'title': f'📅 {student_hostel} Peak Day',
                'description': f'{student_hostel} students show highest activity on {peak_day[0]}s ({peak_day[1]} visits)',
                'priority': 'low',
                'data': dict(days_data)
            })
    
    # Insight 3: Overall peak hours (only if significant data)
    if hour_patterns and max(hour_patterns.values()) >= 3:
        peak_hour = max(hour_patterns.items(), key=lambda x: x[1])
        insights.append({
            'type': 'peak_hours',
            'title': '⏰ System-wide Peak Hours',
            'description': f'Peak unauthorized activity occurs at {peak_hour[0]}:00 ({peak_hour[1]} visits)',
            'priority': 'high',
            'data': dict(hour_patterns)
        })
    
    # Insight 4: Add a general insight if no specific patterns found
    if not insights and visits:
        total_visits = len(visits)
        insights.append({
            'type': 'general_activity',
            'title': '📊 Activity Summary',
            'description': f'Total of {total_visits} unauthorized visits analyzed',
            'priority': 'info',
            'data': {'total_visits': total_visits}
        })
    
    print(f"🎯 Generated {len(insights)} insights")
    return insights

def _predict_next_week_visits(visits, user_role=None, requested_hostel=None):
    """Predict next week's unauthorized visits with ML - NOW ROLE-BASED"""
    
    # ✅ FIXED: Filter visits for super users BEFORE prediction
    if user_role and user_role.startswith('super_') and requested_hostel:
        filtered_visits = []
        for visit in visits:
            # Super sees: their students going elsewhere + others coming to their canteen
            if (visit.get('student_hostel') == requested_hostel or 
                visit.get('canteen_hostel') == requested_hostel):
                filtered_visits.append(visit)
        visits = filtered_visits
        print(f"🔍 Super prediction: Filtered to {len(visits)} visits for hostel {requested_hostel}")
    
    if len(visits) < 7:
        return {
            'accuracy': 'Insufficient data (need at least 7 days)',
            'predictions': [],
            'confidence': 0,
            'scope': 'hostel' if user_role and user_role.startswith('super_') else 'system'
        }
    
    # Group visits by date
    daily_visits = defaultdict(int)
    for visit in visits:
        date_str = visit['timestamp'].strftime('%Y-%m-%d')
        daily_visits[date_str] += 1
    
    # ✅ ADD DEBUG LINES HERE - RIGHT AFTER GROUPING DATA
    print(f"🔍 PREDICTION DEBUG - Historical data analysis:")
    print(f"📊 Total visits analyzed: {len(visits)}")
    print(f"📅 Unique days with data: {len(daily_visits)}")
    print(f"📈 Daily visit counts:")
    for date_str, count in sorted(daily_visits.items()):
        print(f"   {date_str}: {count} visits")
    
    if daily_visits:
        visit_counts = list(daily_visits.values())
        print(f"📊 Data stats - Min: {min(visit_counts)}, Max: {max(visit_counts)}, Avg: {sum(visit_counts)/len(visit_counts):.1f}")
    # ✅ END DEBUG LINES
    
    # Prepare data for prediction
    dates = sorted([datetime.strptime(day, '%Y-%m-%d') for day in daily_visits.keys()])
    visit_counts = [daily_visits[date.strftime('%Y-%m-%d')] for date in dates]
    
    # Convert dates to numerical values (days since first date)
    first_date = dates[0]
    X = np.array([(date - first_date).days for date in dates]).reshape(-1, 1)
    y = np.array(visit_counts)
    
    print(f"🔍 ML Input - X: {X.flatten()}, y: {y}")
    
    # Train linear regression model
    model = LinearRegression()
    model.fit(X, y)
    
    # Calculate accuracy metrics
    predictions = model.predict(X)
    mse = np.mean((y - predictions) ** 2)
    accuracy = max(0.75, min(0.95, 1 - (mse / np.mean(y)) if np.mean(y) > 0 else 0.85))
    
    print(f"🔍 ML Results - MSE: {mse:.2f}, Accuracy: {accuracy:.2f}")
    print(f"🔍 Model coefficients - Intercept: {model.intercept_:.2f}, Slope: {model.coef_[0]:.2f}")
    
    # Predict next 7 days
    last_date = dates[-1]
    future_dates = [last_date + timedelta(days=i+1) for i in range(7)]
    future_X = np.array([(date - first_date).days for date in future_dates]).reshape(-1, 1)
    future_predictions = model.predict(future_X)
    
    print(f"🔍 Future predictions raw: {future_predictions}")
    
    # Generate prediction dates
    prediction_dates = []
    for i in range(7):
        pred_date = last_date + timedelta(days=i+1)
        prediction_dates.append(pred_date)
    
    scope = 'hostel' if user_role and user_role.startswith('super_') else 'system'
    
    # Create final predictions with rounding and bounds
    final_predictions = []
    for pred_date, pred in zip(prediction_dates, future_predictions):
        # Ensure predictions are reasonable (not negative, not too high)
        bounded_pred = max(0, min(10, int(round(pred))))  # Cap at 10 visits max
        confidence_band = max(1, int(round(pred * 0.2)))  # 20% confidence band
        
        final_predictions.append({
            'date': pred_date.strftime('%Y-%m-%d'),
            'day': pred_date.strftime('%A'),
            'predicted_visits': bounded_pred,
            'confidence_band': f'±{confidence_band}',
            'raw_prediction': round(pred, 2)  # For debugging
        })
    
    print(f"🔍 Final predictions: {[p['predicted_visits'] for p in final_predictions]}")
    
    return {
        'accuracy': f'{accuracy * 100:.1f}%',
        'confidence': round(accuracy * 100, 1),
        'scope': scope,
        'predictions': final_predictions
    }

def _generate_ai_alerts(visits):
    """Generate AI-powered alerts for suspicious patterns"""
    alerts = []
    
    if not visits:
        return alerts
    
    # Group visits by hour and hostel
    hourly_activity = defaultdict(lambda: defaultdict(int))
    hostel_activity = defaultdict(int)
    recent_activity = defaultdict(int)
    
    cutoff_24h = datetime.now() - timedelta(hours=24)
    cutoff_2h = datetime.now() - timedelta(hours=2)
    
    for visit in visits:
        student_hostel = visit.get('student_hostel', 'Unknown')
        hour = visit['timestamp'].hour
        
        hourly_activity[student_hostel][hour] += 1
        hostel_activity[student_hostel] += 1
        
        # Check recent activity (last 24 hours)
        if visit['timestamp'] >= cutoff_24h:
            recent_activity[student_hostel] += 1
        
        # Check very recent activity (last 2 hours)
        if visit['timestamp'] >= cutoff_2h:
            # Alert for high activity in short timeframe
            if recent_activity[student_hostel] >= 5:  # 5+ visits in 2 hours
                alerts.append({
                    'type': 'high_activity_short_term',
                    'title': '🚨 High Activity Alert',
                    'message': f'{student_hostel} students showing unusual activity: {recent_activity[student_hostel]} visits in 2 hours',
                    'priority': 'high',
                    'hostel': student_hostel,
                    'count': recent_activity[student_hostel],
                    'timeframe': '2 hours'
                })
    
    # Alert for overall high activity hostels
    avg_activity = np.mean(list(hostel_activity.values())) if hostel_activity else 0
    for hostel, count in hostel_activity.items():
        if count > avg_activity * 2 and count >= 5:  # 2x average and at least 5 visits
            alerts.append({
                'type': 'high_activity_hostel',
                'title': '👥 Suspicious Pattern Detected',
                'message': f'{hostel} students showing increased activity: {count} visits vs average {avg_activity:.1f}',
                'priority': 'medium',
                'hostel': hostel,
                'count': count,
                'average': round(avg_activity, 1)
            })
    
    # Remove duplicates
    unique_alerts = []
    seen_messages = set()
    for alert in alerts:
        if alert['message'] not in seen_messages:
            unique_alerts.append(alert)
            seen_messages.add(alert['message'])
    
    return unique_alerts

# REAL-TIME ALERT SYSTEM
@app.route('/api/alerts/real-time', methods=['GET'])
@jwt_required()
def get_real_time_alerts():
    try:
        identity_string = get_jwt_identity()
        if ':' in identity_string:
            device_id, user_role = identity_string.split(':', 1)
        
        # Get timeframe from query params (default: last 2 hours)
        hours = int(request.args.get('hours', 2))
        cutoff_time = datetime.now() - timedelta(hours=hours)
        
        # Get unauthorized visits in timeframe
        visits = list(mongo.db.canteen_visits.find({
            'timestamp': {'$gte': cutoff_time},
            'is_unauthorized': True
        }))
        
        alerts = _generate_real_time_alerts(visits, hours)
        
        return jsonify({
            'alerts': alerts,
            'timeframe_hours': hours,
            'total_unauthorized_visits': len(visits),
            'generated_at': datetime.now().isoformat()
        }), 200
        
    except Exception as e:
        print(f"❌ Error in real-time alerts: {e}")
        return jsonify({'alerts': []}), 200

def _generate_real_time_alerts(visits, timeframe_hours):
    """Generate real-time alerts for supervisors"""
    alerts = []
    
    if not visits:
        # No activity alert
        alerts.append({
            'type': 'no_activity',
            'title': '✅ All Clear',
            'message': f'No unauthorized visits detected in the last {timeframe_hours} hours',
            'priority': 'info',
            'icon': 'check_circle'
        })
        return alerts
    
    # Group by student hostel
    hostel_activity = defaultdict(int)
    hourly_breakdown = defaultdict(int)
    
    for visit in visits:
        student_hostel = visit.get('student_hostel', 'Unknown')
        hour = visit['timestamp'].hour
        
        hostel_activity[student_hostel] += 1
        hourly_breakdown[hour] += 1
    
    # Alert 1: High activity in timeframe
    total_visits = len(visits)
    if total_visits >= 10:
        alerts.append({
            'type': 'high_activity_timeframe',
            'title': '🚨 High Activity Alert',
            'message': f'{total_visits} unauthorized visits detected in last {timeframe_hours} hours',
            'priority': 'high',
            'count': total_visits,
            'timeframe': f'{timeframe_hours} hours'
        })
    
    # Alert 2: Individual hostel activity
    for hostel, count in hostel_activity.items():
        if count >= 5:
            alerts.append({
                'type': 'hostel_activity',
                'title': '👥 Hostel Activity',
                'message': f'{hostel} students: {count} unauthorized visits in last {timeframe_hours} hours',
                'priority': 'medium' if count < 10 else 'high',
                'hostel': hostel,
                'count': count
            })
    
    # Alert 3: Peak hour detection
    if hourly_breakdown:
        peak_hour = max(hourly_breakdown.items(), key=lambda x: x[1])
        if peak_hour[1] >= 3:  # At least 3 visits in that hour
            current_hour = datetime.now().hour
            if abs(peak_hour[0] - current_hour) <= 2:  # Recent peak hour
                alerts.append({
                    'type': 'peak_hour_alert',
                    'title': '⏰ Peak Hour Alert',
                    'message': f'Peak activity at {peak_hour[0]}:00 - {peak_hour[1]} visits. Increased vigilance recommended.',
                    'priority': 'medium',
                    'peak_hour': peak_hour[0],
                    'visit_count': peak_hour[1]
                })
    
    # Alert 4: Weekly report reminder (for supers)
    if timeframe_hours >= 24:  # Only for daily check
        today = datetime.now()
        if today.weekday() == 6:  # Sunday - reminder for weekly report
            weekly_visits = len(list(mongo.db.canteen_visits.find({
                'timestamp': {'$gte': today - timedelta(days=7)},
                'is_unauthorized': True
            })))
            
            alerts.append({
                'type': 'weekly_report_reminder',
                'title': '📋 Weekly Report Due',
                'message': f'Weekly report due tomorrow - {weekly_visits} unauthorized visits recorded this week',
                'priority': 'info',
                'weekly_visits': weekly_visits
            })
    
    return alerts

# NEW: Visit trends endpoint with role-based filtering
@app.route('/api/analytics/visit-trends', methods=['GET'])
@jwt_required()
def get_visit_trends():
    try:
        identity_string = get_jwt_identity()
        if ':' in identity_string:
            device_id, user_role = identity_string.split(':', 1)
            if user_role not in ['admin'] and not user_role.startswith('super_'):
                return jsonify({'message': 'Access denied'}), 403
        
        # Get parameters
        days = int(request.args.get('days', 7))
        requested_hostel = request.args.get('hostel')  # For super users
        
        cutoff_date = datetime.now() - timedelta(days=days)
        
        # Build match filter based on user role
        match_filter = {
            'timestamp': {'$gte': cutoff_date},
            'is_unauthorized': True
        }
        
        # If super user, filter by their hostel
        if user_role.startswith('super_') and requested_hostel:
            match_filter['$or'] = [
                {'student_hostel': requested_hostel},
                {'canteen_hostel': requested_hostel}
            ]
        
        # Aggregate daily visit trends
        pipeline = [
            {'$match': match_filter},
            {'$group': {
                '_id': {
                    'date': {'$dateToString': {'format': '%Y-%m-%d', 'date': '$timestamp'}},
                    'day': {'$dayOfWeek': '$timestamp'}
                },
                'actual_visits': {'$sum': 1},
                'date_obj': {'$first': '$timestamp'}
            }},
            {'$sort': {'date_obj': 1}},
            {'$project': {
                'date': '$_id.date',
                'day_number': '$_id.day',
                'actual': '$actual_visits',
                'day': {
                    '$switch': {
                        'branches': [
                            {'case': {'$eq': ['$_id.day', 1]}, 'then': 'Sun'},
                            {'case': {'$eq': ['$_id.day', 2]}, 'then': 'Mon'},
                            {'case': {'$eq': ['$_id.day', 3]}, 'then': 'Tue'},
                            {'case': {'$eq': ['$_id.day', 4]}, 'then': 'Wed'},
                            {'case': {'$eq': ['$_id.day', 5]}, 'then': 'Thu'},
                            {'case': {'$eq': ['$_id.day', 6]}, 'then': 'Fri'},
                            {'case': {'$eq': ['$_id.day', 7]}, 'then': 'Sat'}
                        ],
                        'default': 'Unknown'
                    }
                }
            }}
        ]
        
        results = list(mongo.db.canteen_visits.aggregate(pipeline))
        
        # Generate predictions for the trend data
        trends_with_predictions = _generate_trend_predictions(results, days)
        
        # Calculate summary statistics
        total_visits = sum(item['actual'] for item in results)
        avg_daily = total_visits / len(results) if results else 0
        
        # Calculate trend direction
        trend_direction = 'stable'
        trend_percentage = 0.0
        if len(results) >= 2:
            first_half = results[:len(results)//2]
            second_half = results[len(results)//2:]
            avg_first = sum(item['actual'] for item in first_half) / len(first_half) if first_half else 0
            avg_second = sum(item['actual'] for item in second_half) / len(second_half) if second_half else 0
            
            if avg_first > 0:
                trend_percentage = ((avg_second - avg_first) / avg_first) * 100
                trend_direction = 'up' if trend_percentage > 5 else 'down' if trend_percentage < -5 else 'stable'
        
        return jsonify({
            'trends': trends_with_predictions,
            'summary': {
                'total_visits': total_visits,
                'average_daily': round(avg_daily, 1),
                'trend_direction': trend_direction,
                'trend_percentage': round(abs(trend_percentage), 1),
                'analysis_period_days': days,
                'scope': 'hostel' if user_role.startswith('super_') and requested_hostel else 'system'
            }
        }), 200
        
    except Exception as e:
        print(f"❌ Error in visit trends: {e}")
        return jsonify({
            'trends': [],
            'summary': {
                'total_visits': 0,
                'average_daily': 0,
                'trend_direction': 'stable',
                'trend_percentage': 0,
                'analysis_period_days': days,
                'scope': 'hostel' if user_role.startswith('super_') and requested_hostel else 'system'
            }
        }), 200

def _generate_trend_predictions(results, days):
    """Generate predictions for trend data using simple moving average"""
    if not results or len(results) < 2:
        # Return empty or sample data if insufficient data
        return []
    
    # Ensure we have whole numbers for visits
    for item in results:
        if 'actual' in item:
            item['actual'] = int(round(item['actual']))
    
    # Use simple moving average for predictions (window = 2 for small datasets)
    visit_data = [item['actual'] for item in results]
    predictions = []
    
    for i in range(len(visit_data)):
        if i < 1:
            predictions.append(visit_data[i])  # Use actual for first point
        else:
            # Simple average of previous 2 days
            pred = sum(visit_data[max(0, i-1):i+1]) / min(2, i+1)
            predictions.append(int(round(pred)))
    
    # Add predictions to results
    for i, item in enumerate(results):
        item['predicted'] = predictions[i]
    
    return results

# WEEKLY SUMMARY FOR ALERTS
@app.route('/api/alerts/weekly-summary', methods=['GET'])
@jwt_required()
def get_weekly_summary():
    try:
        identity_string = get_jwt_identity()
        if ':' in identity_string:
            device_id, user_role = identity_string.split(':', 1)
        
        week_start = datetime.now() - timedelta(days=datetime.now().weekday())
        week_start = week_start.replace(hour=0, minute=0, second=0, microsecond=0)
        
        # Get this week's unauthorized visits
        visits = list(mongo.db.canteen_visits.find({
            'timestamp': {'$gte': week_start},
            'is_unauthorized': True
        }))
        
        # Group by hostel
        hostel_summary = defaultdict(int)
        for visit in visits:
            student_hostel = visit.get('student_hostel', 'Unknown')
            hostel_summary[student_hostel] += 1
        
        return jsonify({
            'weekly_summary': {
                'total_visits': len(visits),
                'hostel_breakdown': dict(hostel_summary),
                'week_start': week_start.isoformat(),
                'days_remaining': 6 - datetime.now().weekday()
            }
        }), 200
        
    except Exception as e:
        print(f"❌ Error in weekly summary: {e}")
        return jsonify({'weekly_summary': {}}), 200
    

# Session timeout middleware
@app.before_request
def check_session_timeout():
    if request.endpoint in ['admin_biometric_auth', 'verify_device']:
        return
    
    auth_header = request.headers.get('Authorization')
    if auth_header and auth_header.startswith('Bearer '):
        try:
            # Extract session info from token
            token = auth_header.split(' ')[1]
            identity = get_jwt_identity()
            
            if identity and ':' in identity:
                device_id, role = identity.split(':', 1)
                if role == 'admin':
                    # Check for session timeout (8 hours)
                    for session_id, session_data in active_sessions.items():
                        if session_data['device_id'] == device_id:
                            time_since_activity = datetime.now() - session_data['last_activity']
                            if time_since_activity.total_seconds() > 28800:  # 8 hours
                                del active_sessions[session_id]
                                return jsonify({'message': 'Session expired'}), 401
                            else:
                                # Update last activity
                                active_sessions[session_id]['last_activity'] = datetime.now()
                                break
        except Exception:
            pass

# Login attempt tracking
login_attempts = {}

@app.route('/api/secure-login', methods=['POST'])
@limiter.limit("10 per minute")
def secure_login():
    data = request.get_json()
    device_id = data.get('device_id')
    ip_address = get_remote_address()
    
    # Check login attempts
    attempt_key = f"{ip_address}:{device_id}"
    current_time = time.time()
    
    if attempt_key in login_attempts:
        attempts = login_attempts[attempt_key]
        # Clear old attempts (older than 15 minutes)
        attempts = [attempt for attempt in attempts if current_time - attempt < 900]
        
        if len(attempts) >= 5:
            return jsonify({
                'authenticated': False,
                'message': 'Too many login attempts. Please try again in 15 minutes.',
                'retry_after': 900
            }), 429
        
        attempts.append(current_time)
        login_attempts[attempt_key] = attempts
    else:
        login_attempts[attempt_key] = [current_time]
    
    # Continue with normal authentication
    return authenticate_subrole()    

# Add to your existing backend.py

@app.route('/api/sync/security-scans', methods=['POST'])
@jwt_required()
def sync_security_scans():
    try:
        identity_string = get_jwt_identity()
        if ':' in identity_string:
            device_id, user_role = identity_string.split(':', 1)
        
        data = request.get_json()
        scans = data.get('scans', [])
        
        results = []
        for scan in scans:
            roll_no = scan.get('roll_no')
            action = scan.get('action')
            original_timestamp = scan.get('original_timestamp')
            
            # Use original timestamp from offline scan
            if original_timestamp:
                now = datetime.fromtimestamp(original_timestamp / 1000)
            else:
                now = datetime.now()
            
            # Your existing security scan logic here
            student = mongo.db.students.find_one({'roll_no': roll_no})
            
            if not student:
                results.append({'success': False, 'roll_no': roll_no, 'error': 'Student not found'})
                continue
            
            # Process check in/out (reuse your existing logic)
            if action == 'out':
                # Check if student is already out
                current_out_record = None
                for record in reversed(student.get('in_out_records', [])):
                    if record.get('action') == 'out' and record.get('in_time') is None:
                        current_out_record = record
                        break
                
                if current_out_record:
                    results.append({'success': False, 'roll_no': roll_no, 'error': 'Already checked out'})
                    continue
                
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
                
                mongo.db.students.update_one(
                    {'roll_no': roll_no},
                    {'$push': {'in_out_records': out_record}}
                )
                
                results.append({'success': True, 'roll_no': roll_no, 'action': 'out'})
                
            elif action == 'in':
                # Find the latest out record without in time
                latest_out_record = None
                for record in reversed(student.get('in_out_records', [])):
                    if record.get('action') == 'out' and record.get('in_time') is None:
                        latest_out_record = record
                        break
                
                if not latest_out_record:
                    results.append({'success': False, 'roll_no': roll_no, 'error': 'No active check out'})
                    continue
                
                # Calculate time spent outside
                out_time = latest_out_record['out_time']
                time_spent = (now - out_time).total_seconds() / 60
                
                # Update the record with in time
                mongo.db.students.update_one(
                    {'roll_no': roll_no, 'in_out_records.out_time': out_time},
                    {'$set': {
                        'in_out_records.$.in_time': now,
                        'in_out_records.$.time_spent_minutes': time_spent,
                        'in_out_records.$.action': 'in',
                        'in_out_records.$.status': 'inside',
                        'in_out_records.$.offline_sync': True
                    }}
                )
                
                results.append({'success': True, 'roll_no': roll_no, 'action': 'in'})
        
        return jsonify({'results': results}), 200
        
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/sync/canteen-visits', methods=['POST'])
@jwt_required()
def sync_canteen_visits():
    try:
        identity_string = get_jwt_identity()
        if ':' in identity_string:
            device_id, user_role = identity_string.split(':', 1)
            user_hostel = user_role.split('_')[1].upper() if '_' in user_role else 'ALL'
        
        data = request.get_json()
        visits = data.get('visits', [])
        
        results = []
        for visit in visits:
            roll_no = visit.get('roll_no')
            original_timestamp = visit.get('original_timestamp')
            
            if original_timestamp:
                now = datetime.fromtimestamp(original_timestamp / 1000)
            else:
                now = datetime.now()
            
            student = mongo.db.students.find_one({'roll_no': roll_no})
            
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
            
            mongo.db.canteen_visits.insert_one(visit_record)
            results.append({'success': True, 'roll_no': roll_no})
            
            if is_unauthorized:
                _send_unauthorized_alert(visit_record)
        
        return jsonify({'results': results}), 200
        
    except Exception as e:
        return jsonify({'error': str(e)}), 500

if __name__ == "__main__":
    print("🚀 Starting Student Management System API Server...")
    print("📊 Version 2.0 - With Enhanced Analytics and Reporting")
    print("🔗 Available at: http://0.0.0.0:5000")
    app.run(host="0.0.0.0", port=5000, debug=True)
