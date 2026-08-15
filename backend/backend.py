from flask import Flask, request, jsonify, make_response
from flask_jwt_extended import JWTManager, create_access_token, jwt_required, get_jwt_identity
from services.websocket_service import socketio
from bson import ObjectId
from functools import wraps
import os
import hashlib
from apscheduler.schedulers.background import BackgroundScheduler
import atexit
from collections import defaultdict, Counter
import json
import time
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address
from datetime import datetime, timezone, timedelta, date
import uuid
# NEW IMPORTS (required for Atlas + Render)
from pymongo import MongoClient
import certifi
from flask_jwt_extended import verify_jwt_in_request

# ============================================================
# NEW IMPORTS FOR MODULARITY - ADD THESE
# ============================================================
from services.movement_service import process_security_scan
from services.monitoring_service import monitor_active_checkouts, create_active_checkout
from utils.time_utils import INDIA_TZ, get_ist_now, normalize_datetime_to_ist
from utils.db_utils import set_db, set_client, get_db
# ============================================================
# ============================================================
# NEW IMPORTS FOR STUDENT & ANALYTICS SERVICES - ADD THESE
# ============================================================
from services.student_service import (
    get_student_with_role,
    search_students,
    get_students_by_hostel,
    validate_student_offline,
    get_student_allowed_time,
    update_student_allowed_time,
    reset_student_allowed_time,
    get_all_students_minimal,
    get_student_counts,
    get_active_students_outside,
    get_student_movement_history
)
from services.analytics_service import (
    get_unauthorized_visits_analytics,
    get_monthly_unauthorized_visits,
    get_late_arrivals_analytics,
    calculate_weekly_late_arrivals,
    get_visit_trends,
    get_predictive_insights as analytics_get_predictive_insights,
    _predict_next_week_visits as predict_next_week_visits,
    predict_unauthorized_visits,
    submit_weekly_canteen_report,
    _generate_ai_alerts as generate_ai_alerts,
    get_late_arrivals_reports
)

from services.notification_service import register_fcm_token

# Service-layer aliases used by thin Flask route wrappers.
from services.analytics_service import (
    get_monthly_unauthorized_visits as analytics_get_monthly_unauthorized_visits,
    calculate_weekly_late_arrivals as analytics_calculate_weekly_late_arrivals,
    get_unauthorized_visits_analytics as analytics_get_unauthorized_visits_analytics,
    get_late_arrivals_analytics as analytics_get_late_arrivals_analytics,
    get_visit_trends as analytics_get_visit_trends,
)
from services.alert_service import get_weekly_summary as alert_get_weekly_summary
from services.sync_service import (
    sync_security_scans as sync_security_scans_service,
    sync_canteen_visits as sync_canteen_visits_service,
)
# ============================================================

# India timezone (UTC+5:30)
INDIA_TZ = timezone(timedelta(hours=5, minutes=30))

# Custom JSON encoder to handle datetime and ObjectId serialization
class CustomJSONEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, (datetime, date)):
            # Convert to India timezone before serialization
            if obj.tzinfo is None:
                # If no timezone, assume it's UTC and convert to IST
                obj = obj.replace(tzinfo=timezone.utc)
            # Convert to IST for storage
            obj_ist = obj.astimezone(INDIA_TZ)
            return obj_ist.isoformat()
        elif isinstance(obj, ObjectId):
            return str(obj)
        return super().default(obj)

app = Flask(__name__)
app.config['JWT_SECRET_KEY'] = os.environ.get('JWT_SECRET_KEY', 'super-secret-key')
app.config['JWT_ACCESS_TOKEN_EXPIRES'] = timedelta(hours=8)
MONITORING_SECRET = os.environ.get("MONITORING_SECRET")
app.json_encoder = CustomJSONEncoder
socketio.init_app(app)

MONGO_URL = os.environ.get(
    "MONGO_URL",
    "mongodb://localhost:27017/student_management"
)

# Initialize db as None first
db = None
client = None

def initialize_mongodb_connection():
    global db, client
    try:
        print(f"🔗 Attempting MongoDB connection to: {MONGO_URL.split('@')[1].split('/')[0] if '@' in MONGO_URL else 'localhost'}")

        # Try connection with multiple SSL options
        connection_options = {
            'tls': True,
            'tlsCAFile': certifi.where(),
            'connectTimeoutMS': 10000,
            'socketTimeoutMS': 30000,
            'serverSelectionTimeoutMS': 15000,
            'retryWrites': True,
            'maxPoolSize': 50
        }

        client = MongoClient(MONGO_URL, **connection_options)

        # Test the connection
        client.admin.command('ping')
        db = client["student_management"]
        print("✅ MongoDB connected successfully!")
        return True

    except Exception as e:
        print(f"❌ MongoDB connection failed: {e}")
        print("🔄 Application will start without database connectivity")
        db = None
        client = None
        return False

# Initialize the connection
db_connected = initialize_mongodb_connection()

jwt = JWTManager(app)
@jwt.unauthorized_loader
def jwt_unauthorized_callback(reason):
    print(f"❌ JWT UNAUTHORIZED: {reason}")
    return jsonify({
        'message': 'JWT unauthorized',
        'reason': reason
    }), 401


@jwt.invalid_token_loader
def jwt_invalid_token_callback(reason):
    print(f"❌ JWT INVALID: {reason}")
    return jsonify({
        'message': 'JWT invalid',
        'reason': reason
    }), 401


@jwt.expired_token_loader
def jwt_expired_token_callback(jwt_header, jwt_payload):
    print(
        f"❌ JWT EXPIRED: "
        f"identity={jwt_payload.get('sub')}"
    )
    return jsonify({
        'message': 'JWT expired'
    }), 401

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


def cleanup_old_movement_records():
    try:
        if db is None:
            print("⚠️ Skipping cleanup - no database connection")
            return

        cutoff_time = datetime.now(INDIA_TZ) - timedelta(days=180)

        print(
            f"🧹 Cleaning up movement records older than: "
            f"{cutoff_time}"
        )

        result = db.movement_records.delete_many({
            'out_time': {'$lt': cutoff_time}
        })

        print(
            f"✅ Movement cleanup completed. "
            f"Deleted {result.deleted_count} movement records"
        )

    except Exception as e:
        print(f"❌ Error during movement cleanup: {e}")


def comprehensive_data_cleanup():
    """Clean up all old data older than 6 months"""
    try:
        if db is None:
            print("⚠️ Skipping comprehensive cleanup - no database connection")
            return {'error': 'No database connection'}

        cutoff_time = datetime.now(INDIA_TZ) - timedelta(days=180)
        print(f"🧹 Starting comprehensive data cleanup for records older than: {cutoff_time}")

        cleanup_stats = {}

        # 1. Clean old movement records
        result_movement = db.movement_records.delete_many({
            'out_time': {'$lt': cutoff_time}
        })

        cleanup_stats['movement_records_deleted'] = (
            result_movement.deleted_count
        )

        # 2. Clean old canteen visits (keep for analytics but remove very old ones)
        result_canteen = db.canteen_visits.delete_many({
            'timestamp': {'$lt': cutoff_time}
        })
        cleanup_stats['canteen_visits_deleted'] = result_canteen.deleted_count

        # 3. Clean old security logs (keep only 6 months for audit)
        result_security = db.security_logs.delete_many({
            'timestamp': {'$lt': cutoff_time}
        })
        cleanup_stats['security_logs_deleted'] = result_security.deleted_count

        # 4. Clean old realtime alerts (keep only recent alerts)
        result_alerts = db.realtime_alerts.delete_many({
            'timestamp': {'$lt': cutoff_time}
        })
        cleanup_stats['alerts_deleted'] = result_alerts.deleted_count

        # 5. Clean old admin scans
        result_admin_scans = db.admin_scans.delete_many({
            'timestamp': {'$lt': cutoff_time}
        })
        cleanup_stats['admin_scans_deleted'] = result_admin_scans.deleted_count

        print(f"✅ Comprehensive cleanup completed: {cleanup_stats}")
        return cleanup_stats

    except Exception as e:
        print(f"❌ Error during comprehensive cleanup: {e}")
        return {'error': str(e)}



def initialize_database():
    try:
        # Check if database is connected
        if db is None:
            print("⚠️ Skipping database initialization - no MongoDB connection")
            return

        # Create collections if they don't exist
        collections = db.list_collection_names()

        required_collections = [
            'weekly_reports',
            'canteen_visits',
            'realtime_alerts',
            'admin_scans',
            'security_logs',
            'active_checkouts'
        ]
        for collection in required_collections:
            if collection not in collections:
                db.create_collection(collection)
                print(f"✅ Created {collection} collection")

        # Create indexes for better performance
        db.weekly_reports.create_index([('week_number', 1), ('year', 1)])
        db.canteen_visits.create_index([('timestamp', -1)])
        db.realtime_alerts.create_index([('timestamp', -1)])
        db.students.create_index([('roll_no', 1)], unique=True)
        db.devices.create_index([('device_id', 1)], unique=True)
        db.security_logs.create_index([('timestamp', -1)])
        db.movement_records.create_index(
            [('event_id', 1)],
            unique=True
        )
        # Indexes for proactive allowed-time monitoring
        db.active_checkouts.create_index(
            [('roll_no', 1)],
            unique=True
        )

        db.active_checkouts.create_index(
            [('status', 1), ('deadline', 1)]
        )

        db.active_checkouts.create_index(
            [('deadline', 1)]
        )

        print("✅ Database initialization completed")
    except Exception as e:
        print(f"❌ Database initialization error: {e}")

# ============================================================
# ADD THIS - Set db in utils after initialization
# ============================================================
# Initialize database when app starts ONLY if connected
if db_connected:
    set_db(db)
    set_client(client)
    initialize_database()
else:
    print("⚠️ Skipping database initialization - no connection")
# ============================================================

# ============================================================
# DELETE THESE FUNCTIONS (they're now in services/)
# - create_active_checkout()
# - monitor_active_checkouts()
# They have been moved to services/monitoring_service.py
# ============================================================

@app.route('/api/internal/monitor-active-checkouts', methods=['POST'])
@limiter.exempt
def trigger_active_checkout_monitor():

    provided_secret = request.headers.get("X-Monitoring-Secret")

    if not MONITORING_SECRET:
        print("❌ MONITORING_SECRET is not configured")

        return jsonify({
            "success": False,
            "message": "Monitoring service not configured"
        }), 500

    if provided_secret != MONITORING_SECRET:
        print("🚫 Unauthorized monitoring request")

        return jsonify({
            "success": False,
            "message": "Unauthorized"
        }), 401

    try:
        monitor_active_checkouts()

        return jsonify({
            "success": True,
            "message": "Active checkout monitoring completed"
        }), 200

    except Exception as e:
        print(
            f"❌ Monitoring endpoint error: "
            f"{type(e).__name__}: {e}"
        )

        return jsonify({
            "success": False,
            "message": "Monitoring failed"
        }), 500


# Enhanced security logging
def log_security_event(event_type, user_role, device_id, ip_address, details=None):
    """Log security events for audit trail"""
    try:
        if db is None:
            print(f"⚠️ Security log skipped (no DB): {event_type} - {user_role} - {device_id}")
            return

        log_entry = {
            'event_type': event_type,
            'user_role': user_role,
            'device_id': device_id,
            'ip_address': ip_address,
            'timestamp': datetime.now(INDIA_TZ),
            'details': details or {}
        }
        db.security_logs.insert_one(log_entry)
    except Exception as e:
        print(f"❌ Error logging security event: {e}")

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
        device = db.devices.find_one({'device_id': device_id, 'status': 'active'})
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
        session_id = hashlib.sha256(f"{device_id}{datetime.now(INDIA_TZ)}".encode()).hexdigest()
        identity_string = f"{device_id}:admin"

        access_token = create_access_token(identity=identity_string)

        # Store session
        active_sessions[session_id] = {
            'device_id': device_id,
            'role': 'admin',
            'login_time': datetime.now(INDIA_TZ),
            'last_activity': datetime.now(INDIA_TZ),
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
            # Verify the JWT before accessing its identity.
            verify_jwt_in_request()

            # Extract session info from the verified token.
            identity = get_jwt_identity()

            if identity and ':' in identity:
                device_id, role = identity.split(':', 1)

                # Check for session timeout for admin
                if role == 'admin':
                    session_found = False

                    for session_id, session_data in list(active_sessions.items()):
                        if session_data['device_id'] == device_id:

                            time_since_activity = (
                                datetime.now(INDIA_TZ) -
                                session_data['last_activity']
                            )

                            if time_since_activity.total_seconds() > SESSION_TIMEOUT:
                                del active_sessions[session_id]

                                log_security_event(
                                    'session_expired',
                                    role,
                                    device_id,
                                    get_remote_address()
                                )

                                return jsonify({
                                    'message': 'Session expired. Please login again.'
                                }), 401

                            # Session is valid
                            session_data['last_activity'] = datetime.now(INDIA_TZ)
                            session_found = True
                            break

                    # IMPORTANT:
                    # Do NOT reject the request merely because the in-memory
                    # session is missing. JWT authentication has already succeeded.
                    if not session_found:
                        print(
                            f"⚠️ Admin JWT valid but in-memory session not found "
                            f"for device {device_id}. Continuing with JWT authentication."
                        )

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
    device = db.devices.find_one({'device_id': device_id, 'status': 'active'})

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
            'issued_at': datetime.now(INDIA_TZ).isoformat()
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
    biometric_verified = data.get('biometric_verified', False)
    ip_address = get_remote_address()

    print(f"🔐 Subrole authentication attempt: {subrole}, biometric: {biometric_verified}")

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

    # Verify device from database
    device = db.devices.find_one({'device_id': device_id, 'status': 'active'})

    if not device:
        log_security_event('device_verification_failed', subrole, device_id, ip_address)
        return jsonify({
            'authenticated': False,
            'message': 'Device not verified or inactive'
        }), 401

    # If biometric verified, skip unique ID check
    if biometric_verified:
        print(f"✅ Biometric authentication verified for {subrole}")
        # You might want to add additional biometric-specific validation here
        # For now, we'll trust the biometric verification
        pass
    else:
        # Verify unique ID for the subrole (existing logic)
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

    # Create JWT token
    identity_string = f"{device_id}:{subrole}"
    access_token = create_access_token(identity=identity_string)

    # Get user info from database
    user_info = {
        'username': f"{subrole}_user",
        'role': subrole,
        'hostel': subrole.split('_')[1].upper() if '_' in subrole else 'ALL'
    }

    auth_method = 'biometric' if biometric_verified else 'unique_id'
    log_security_event('subrole_login_success', subrole, device_id, ip_address, {'method': auth_method})

    print(f"✅ Subrole authentication successful: {subrole} via {auth_method}")

    return jsonify({
        'authenticated': True,
        'access_token': access_token,
        'username': user_info['username'],
        'role': user_info['role'],
        'hostel': user_info['hostel'],
        'message': 'Authentication successful',
        'auth_method': auth_method
    }), 200

# ============================================================
# REGISTER FCM TOKEN FOR AUTHENTICATED SUPERVISOR DEVICE
# ============================================================
@app.route('/api/register-fcm-token', methods=['POST'])
@jwt_required()
def register_fcm_token_endpoint():
    try:
        identity_string = get_jwt_identity()

        if not identity_string or ':' not in identity_string:
            return jsonify({
                'success': False,
                'message': 'Invalid authentication identity'
            }), 401

        device_id, user_role = identity_string.split(':', 1)

        # Only hostel supervisors should register for
        # allowed-time violation notifications.
        if not user_role.startswith('super_'):
            return jsonify({
                'success': False,
                'message': 'Only hostel supervisors can register FCM tokens'
            }), 403

        data = request.get_json() or {}
        fcm_token = data.get('fcm_token')

        if not fcm_token:
            return jsonify({
                'success': False,
                'message': 'FCM token is required'
            }), 400

        success = register_fcm_token(
            device_id=device_id,
            fcm_token=fcm_token
        )

        if not success:
            return jsonify({
                'success': False,
                'message': 'Device not found or inactive'
            }), 404

        print(
            f"📱 FCM TOKEN API SUCCESS | "
            f"Supervisor={user_role} | "
            f"Device={device_id}"
        )

        return jsonify({
            'success': True,
            'message': 'FCM token registered successfully'
        }), 200

    except Exception as e:
        print(
            f"❌ FCM token API error: "
            f"{type(e).__name__}: {e}"
        )

        return jsonify({
            'success': False,
            'message': 'Internal server error'
        }), 500

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
        cutoff_time = datetime.now(INDIA_TZ) - timedelta(days=7)
        logs = list(db.security_logs.find(
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
            time_since_activity = datetime.now(INDIA_TZ) - session_data['last_activity']
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

# Schedule comprehensive cleanup to run monthly instead of the current cleanup
scheduler.add_job(
    func=comprehensive_data_cleanup,
    trigger='cron',  # Use cron trigger for monthly scheduling
    day=1,  # 1st day of every month
    hour=2,  # 2 AM
    minute=0,
    id='monthly_data_cleanup'
)


# Also run cleanup when the app starts for any stale records
cleanup_old_movement_records()

# Shut down the scheduler when exiting the app
atexit.register(lambda: scheduler.shutdown())

# Manual cleanup endpoint with 6 months parameter
@app.route('/api/admin/cleanup-data', methods=['POST'])
@jwt_required()
def manual_cleanup_data():
    try:
        identity_string = get_jwt_identity()
        if ':' in identity_string:
            device_id, user_role = identity_string.split(':', 1)
            if user_role != 'admin':
                return jsonify({'message': 'Admin access required'}), 403

        data = request.get_json() or {}
        months = data.get('months', 6)  # Default to 6 months

        # Calculate cutoff time based on months parameter
        cutoff_time = datetime.now(INDIA_TZ) - timedelta(days=months*30)

        print(f"🧹 Manual cleanup requested for data older than {months} months ({cutoff_time})")

        # Perform comprehensive cleanup with custom cutoff
        cleanup_stats = comprehensive_data_cleanup_custom(cutoff_time)

        # Log the cleanup event
        log_security_event(
            'manual_data_cleanup',
            'admin',
            device_id,
            get_remote_address(),
            {'months': months, 'cutoff_time': cutoff_time, 'stats': cleanup_stats}
        )

        return jsonify({
            'message': f'Data cleanup completed for records older than {months} months',
            'cutoff_time': cutoff_time.isoformat(),
            'cleanup_stats': cleanup_stats
        }), 200

    except Exception as e:
        return jsonify({'message': f'Error during cleanup: {str(e)}'}), 500

def comprehensive_data_cleanup_custom(cutoff_time):
    """Clean up all old data older than specified cutoff time"""
    try:
        print(f"🧹 Custom cleanup for records older than: {cutoff_time}")

        cleanup_stats = {}

        # Clean all collections with the custom cutoff time
        result_movement = db.movement_records.delete_many({
            'out_time': {'$lt': cutoff_time}
        })

        cleanup_stats['movement_records_deleted'] = (
            result_movement.deleted_count
        )

        result_canteen = db.canteen_visits.delete_many({
            'timestamp': {'$lt': cutoff_time}
        })
        cleanup_stats['canteen_visits_deleted'] = result_canteen.deleted_count

        result_security = db.security_logs.delete_many({
            'timestamp': {'$lt': cutoff_time}
        })
        cleanup_stats['security_logs_deleted'] = result_security.deleted_count

        result_alerts = db.realtime_alerts.delete_many({
            'timestamp': {'$lt': cutoff_time}
        })
        cleanup_stats['alerts_deleted'] = result_alerts.deleted_count

        result_admin_scans = db.admin_scans.delete_many({
            'timestamp': {'$lt': cutoff_time}
        })
        cleanup_stats['admin_scans_deleted'] = result_admin_scans.deleted_count

        print(f"✅ Custom cleanup completed: {cleanup_stats}")
        return cleanup_stats

    except Exception as e:
        print(f"❌ Error during custom cleanup: {e}")
        return {'error': str(e)}

# Get cleanup statistics
@app.route('/api/admin/cleanup-stats', methods=['GET'])
@jwt_required()
def get_cleanup_stats():
    try:
        identity_string = get_jwt_identity()
        if ':' in identity_string:
            device_id, user_role = identity_string.split(':', 1)
            if user_role != 'admin':
                return jsonify({'message': 'Admin access required'}), 403

        # Calculate data statistics
        six_months_ago = datetime.now(INDIA_TZ) - timedelta(days=180)

        stats = {
            'data_older_than_6_months': {
                'canteen_visits': db.canteen_visits.count_documents({
                    'timestamp': {'$lt': six_months_ago}
                }),
                'security_logs': db.security_logs.count_documents({
                    'timestamp': {'$lt': six_months_ago}
                }),
                'realtime_alerts': db.realtime_alerts.count_documents({
                    'timestamp': {'$lt': six_months_ago}
                }),
                'admin_scans': db.admin_scans.count_documents({
                    'timestamp': {'$lt': six_months_ago}
                })
            },
            'next_scheduled_cleanup': '1st of every month at 2:00 AM',
            'cleanup_cutoff_days': 180,
            'current_time': datetime.now(INDIA_TZ).isoformat(),
            'cutoff_time': six_months_ago.isoformat()
        }

        return jsonify(stats), 200

    except Exception as e:
        return jsonify({'message': f'Error getting cleanup stats: {str(e)}'}), 500

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
        'timestamp': datetime.now(INDIA_TZ).isoformat(),
        'version': '2.0'
    }), 200



@app.route('/api/student/<roll_no>/<selected_role>', methods=['GET'])
@jwt_required()
def get_student_with_role_endpoint(roll_no, selected_role):
    try:
        identity_string = get_jwt_identity()
        if ':' in identity_string:
            device_id, user_role = identity_string.split(':', 1)
        else:
            return jsonify({'message': 'Invalid token format'}), 401

        # Use the student service
        result, status_code = get_student_with_role(roll_no, user_role, selected_role)
        return jsonify(result), status_code

    except Exception as e:
        print(f"❌ Error in get_student_with_role: {e}")
        return jsonify({'message': f'Server error: {str(e)}'}), 500

# ============================================================
# REPLACED: Simplified security scan endpoint using service
# ============================================================
@app.route('/api/student/scan/security/<selected_role>', methods=['POST'])
@jwt_required()
def handle_security_scan(selected_role):
    try:
        identity_string = get_jwt_identity()
        if ':' not in identity_string:
            return jsonify({'message': 'Invalid token format'}), 401

        device_id, user_role = identity_string.split(':', 1)

        if user_role != selected_role:
            return jsonify({'message': 'Role mismatch'}), 403

        data = request.get_json(silent=True) or {}

        response_data, status_code = process_security_scan(
            user_role=user_role,
            data=data,
            db=get_db()
        )

        return jsonify(response_data), status_code

    except Exception as e:
        print(f"Error in handle_security_scan: {e}")
        return jsonify({'message': f'Server error: {str(e)}'}), 500
# ============================================================

# Update the existing manual cleanup endpoint to use 6 months
@app.route('/api/admin/cleanup-records', methods=['POST'])
@jwt_required()
def manual_cleanup_records():
    try:
        identity_string = get_jwt_identity()
        if ':' in identity_string:
            device_id, user_role = identity_string.split(':', 1)
            if user_role != 'admin':
                return jsonify({'message': 'Admin access required'}), 403

        # Use the comprehensive cleanup with 6 months default
        cleanup_stats = comprehensive_data_cleanup()

        return jsonify({
            'message': 'Manual cleanup completed successfully (6 months data retention)',
            'cleanup_stats': cleanup_stats
        }), 200

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

        devices = list(db.devices.find({}, {'_id': 0}))
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
            'registered_at': datetime.now(INDIA_TZ),
            'last_verified': datetime.now(INDIA_TZ),
            'device_type': data.get('device_type', 'mobile')
        }

        db.devices.insert_one(new_device)
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
        cutoff_time = datetime.now(INDIA_TZ) - timedelta(days=7)
        alerts = list(db.realtime_alerts.find(
            {'timestamp': {'$gte': cutoff_time}},
            {'_id': 0}
        ).sort('timestamp', -1).limit(50))

        return jsonify(alerts), 200

    except Exception as e:
        # Return empty array if there's an error
        return jsonify([]), 200

@app.route('/api/alerts/real-time', methods=['GET'])
@jwt_required()
def get_ai_realtime_alerts():
    try:
        identity_string = get_jwt_identity()

        if ':' not in identity_string:
            return jsonify({'message': 'Invalid token format'}), 401

        device_id, user_role = identity_string.split(':', 1)

        # Only admin and hostel supervisors can access AI security alerts
        if user_role != 'admin' and not user_role.startswith('super_'):
            return jsonify({'message': 'Access denied'}), 403

        hours = request.args.get('hours', default=2, type=int)
        hours = max(1, min(hours, 168))

        cutoff_time = datetime.now(INDIA_TZ) - timedelta(hours=hours)

        # Fetch actual security alerts from MongoDB
        query = {
            'timestamp': {'$gte': cutoff_time}
        }

        alerts = list(
            db.realtime_alerts.find(
                query,
                {'_id': 0}
            ).sort('timestamp', -1).limit(50)
        )

        # Hostel-based filtering for supervisors
        if user_role.startswith('super_'):
            supervisor_hostel = user_role.split('_', 1)[1].upper()

            filtered_alerts = []

            for alert in alerts:
                details = alert.get('details', {})

                student_hostel = details.get(
                    'student_hostel',
                    alert.get('student_hostel')
                )

                canteen_hostel = details.get(
                    'canteen_hostel',
                    alert.get('canteen_hostel')
                )

                if (
                    student_hostel == supervisor_hostel
                    or canteen_hostel == supervisor_hostel
                ):
                    filtered_alerts.append(alert)

            alerts = filtered_alerts

        return jsonify({
            'alerts': alerts,
            'total_alerts': len(alerts),
            'timeframe_hours': hours
        }), 200

    except Exception as e:
        print(f"❌ Error loading real-time alerts: {e}")
        return jsonify({
            'message': f'Error: {str(e)}'
        }), 500


@app.route('/api/canteen/weekly-report', methods=['POST'])
@jwt_required()
def submit_weekly_canteen_report_endpoint():
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

        result = submit_weekly_canteen_report(
            week_number=data['week_number'],
            year=data['year'],
            hostel=data['hostel'],
            extra_students_count=data['extra_students_count'],
            report_data=data.get('report_data', {}),
            user_role=user_role
        )

        if 'error' in result:
            return jsonify({'message': result['error']}), 500

        return jsonify(result), 200

    except Exception as e:
        print(f"❌ Error in submit_weekly_canteen_report: {e}")
        return jsonify({'message': f'Error: {str(e)}'}), 500

# CORRECTED Monthly unauthorized visits endpoint with hostel filtering
@app.route('/api/analytics/unauthorized-visits-monthly', methods=['GET'])
@jwt_required()
def get_monthly_unauthorized_visits():
    try:
        identity_string = get_jwt_identity()
        if ':' not in identity_string:
            return jsonify({'message': 'Invalid token format'}), 401

        device_id, user_role = identity_string.split(':', 1)

        if user_role not in ['admin'] and not user_role.startswith('super_'):
            return jsonify({'message': 'Access denied'}), 403

        year = request.args.get('year', type=int)
        month = request.args.get('month', type=int)
        hostel = request.args.get('hostel')

        if user_role.startswith('super_'):
            hostel = user_role.split('_', 1)[1].upper()

        result = analytics_get_monthly_unauthorized_visits(
            year=year,
            month=month,
            hostel=hostel,
            user_role=user_role,
            db=get_db()
        )

        if isinstance(result, dict) and result.get('error'):
            return jsonify(result), 500

        return jsonify(result), 200

    except Exception as e:
        print(f"Error in get_monthly_unauthorized_visits: {e}")
        return jsonify({'message': f'Server error: {str(e)}'}), 500

# Enhanced weekly late arrivals calculation
@app.route('/api/analytics/late-arrivals-weekly', methods=['POST'])
@jwt_required()
def calculate_weekly_late_arrivals():
    try:
        identity_string = get_jwt_identity()
        if ':' not in identity_string:
            return jsonify({'message': 'Invalid token format'}), 401

        device_id, user_role = identity_string.split(':', 1)

        if user_role not in ['admin'] and not user_role.startswith('super_'):
            return jsonify({'message': 'Access denied'}), 403

        data = request.get_json(silent=True) or {}

        result = analytics_calculate_weekly_late_arrivals(
            week_number=data.get('week_number'),
            year=data.get('year'),
            user_role=user_role,
            db=get_db()
        )

        if isinstance(result, dict) and result.get('error'):
            return jsonify(result), 400

        return jsonify(result), 200

    except Exception as e:
        print(f"Error in calculate_weekly_late_arrivals: {e}")
        return jsonify({'message': f'Server error: {str(e)}'}), 500

@app.route('/api/analytics/late-arrivals-reports', methods=['GET'])
@jwt_required()
def get_late_arrivals_reports_endpoint():
    try:
        identity_string = get_jwt_identity()
        if ':' in identity_string:
            device_id, user_role = identity_string.split(':', 1)
            if user_role not in ['admin'] and not user_role.startswith('super_'):
                return jsonify({'message': 'Access denied'}), 403

        limit = int(request.args.get('limit', 12))
        reports = get_late_arrivals_reports(limit)

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
        week_number = data.get('week', datetime.now(INDIA_TZ).isocalendar()[1])

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
        'timestamp': datetime.now(INDIA_TZ),
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
        # FIXED:
        if is_offline_sync and original_timestamp:
            # Convert UTC timestamp to IST properly
            utc_time = datetime.fromtimestamp(original_timestamp / 1000, tz=timezone.utc)
            now = utc_time.astimezone(INDIA_TZ)
        else:
            now = datetime.now(INDIA_TZ)

        student = db.students.find_one({'roll_no': roll_no})

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
            'date': datetime(now.year, now.month, now.day, tzinfo=INDIA_TZ),
            'hour': now.hour,
            'day_of_week': now.strftime('%A'),
            'offline_sync': is_offline_sync
        }

        db.canteen_visits.insert_one(visit_record)

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
        if ':' not in identity_string:
            return jsonify({'message': 'Invalid token format'}), 401

        device_id, user_role = identity_string.split(':', 1)

        if user_role not in ['admin'] and not user_role.startswith('super_'):
            return jsonify({'message': 'Access denied'}), 403

        days = request.args.get('days', default=30, type=int)
        hostel = request.args.get('hostel')

        if user_role.startswith('super_'):
            hostel = user_role.split('_', 1)[1].upper()

        result = analytics_get_unauthorized_visits_analytics(
            days=days,
            hostel=hostel,
            user_role=user_role,
            db=get_db()
        )

        if isinstance(result, dict) and result.get('error'):
            return jsonify(result), 500

        return jsonify(result), 200

    except Exception as e:
        print(f"Error in get_unauthorized_visits_analytics: {e}")
        return jsonify({'message': f'Server error: {str(e)}'}), 500


def _generate_analytics_alerts(hostel_analysis, daily_analysis):
    """Generate intelligent alerts based on patterns"""
    alerts = []

    # Peak hour detection
    recent_visits = {k: v for k, v in daily_analysis.items()
                    if datetime.strptime(k, '%Y-%m-%d') > datetime.now(INDIA_TZ) - timedelta(days=7)}

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
        'timestamp': datetime.now(INDIA_TZ),
        'priority': 'high'
    }

    # Store alert for super users
    db.realtime_alerts.insert_one(alert_message)
    print(f"📢 ALERT: {alert_message['message']}")

# Late arrival analytics with hostel filtering
@app.route('/api/analytics/late-arrivals', methods=['GET'])
@jwt_required()
def get_late_arrivals_analytics():
    try:
        identity_string = get_jwt_identity()
        if ':' not in identity_string:
            return jsonify({'message': 'Invalid token format'}), 401

        device_id, user_role = identity_string.split(':', 1)

        if user_role not in ['admin'] and not user_role.startswith('super_'):
            return jsonify({'message': 'Access denied'}), 403

        hostel = request.args.get('hostel')

        if user_role.startswith('super_'):
            hostel = user_role.split('_', 1)[1].upper()

        result = analytics_get_late_arrivals_analytics(
            hostel=hostel,
            user_role=user_role,
            db=get_db()
        )

        if isinstance(result, dict) and result.get('error'):
            return jsonify(result), 500

        return jsonify(result), 200

    except Exception as e:
        print(f"Error in get_late_arrivals_analytics: {e}")
        return jsonify({'message': f'Server error: {str(e)}'}), 500

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

        student = db.students.find_one({'roll_no': roll_no})

        if not student:
            return jsonify({'message': 'Student not found'}), 404

        now = datetime.now(INDIA_TZ)

        # Record admin/super scan for audit
        scan_record = {
            'roll_no': roll_no,
            'role': user_role,
            'timestamp': now,
            'student_name': student.get('name', 'Unknown'),
            'type': 'verification'
        }

        db.admin_scans.insert_one(scan_record)

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
    return {"status": "ok", "timestamp": datetime.now(INDIA_TZ).isoformat()}, 200

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
        if ':' not in identity_string:
            return jsonify({'message': 'Invalid token format'}), 401

        device_id, user_role = identity_string.split(':', 1)

        if user_role not in ['admin'] and not user_role.startswith('super_'):
            return jsonify({'message': 'Access denied'}), 403

        days = request.args.get('days', default=30, type=int)
        hostel = request.args.get('hostel')

        if user_role.startswith('super_'):
            hostel = user_role.split('_', 1)[1].upper()

        result = analytics_get_predictive_insights(
            days=days,
            hostel=hostel,
            user_role=user_role,
            db=get_db()
        )

        if isinstance(result, dict) and result.get('error'):
            return jsonify(result), 500

        return jsonify(result), 200

    except Exception as e:
        print(f"Error in get_predictive_insights: {e}")
        return jsonify({'message': f'Server error: {str(e)}'}), 500


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
            current_hour = datetime.now(INDIA_TZ).hour
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
        today = datetime.now(INDIA_TZ)
        if today.weekday() == 6:  # Sunday - reminder for weekly report
            weekly_visits = len(list(db.canteen_visits.find({
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
        if ':' not in identity_string:
            return jsonify({'message': 'Invalid token format'}), 401

        device_id, user_role = identity_string.split(':', 1)

        if user_role not in ['admin'] and not user_role.startswith('super_'):
            return jsonify({'message': 'Access denied'}), 403

        days = request.args.get('days', default=7, type=int)
        hostel = request.args.get('hostel')

        if user_role.startswith('super_'):
            hostel = user_role.split('_', 1)[1].upper()

        result = analytics_get_visit_trends(
            days=days,
            hostel=hostel,
            user_role=user_role,
            db=get_db()
        )

        if isinstance(result, dict) and result.get('error'):
            return jsonify(result), 500

        return jsonify(result), 200

    except Exception as e:
        print(f"Error in get_visit_trends: {e}")
        return jsonify({'message': f'Server error: {str(e)}'}), 500


# WEEKLY SUMMARY FOR ALERTS
@app.route('/api/alerts/weekly-summary', methods=['GET'])
@jwt_required()
def get_weekly_summary():
    try:
        identity_string = get_jwt_identity()
        if ':' not in identity_string:
            return jsonify({'message': 'Invalid token format'}), 401

        device_id, user_role = identity_string.split(':', 1)

        if user_role not in ['admin'] and not user_role.startswith('super_'):
            return jsonify({'message': 'Access denied'}), 403

        result = alert_get_weekly_summary(db=get_db())

        if isinstance(result, dict) and result.get('error'):
            return jsonify(result), 500

        return jsonify(result), 200

    except Exception as e:
        print(f"Error in get_weekly_summary: {e}")
        return jsonify({'message': f'Server error: {str(e)}'}), 500


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
        if ':' not in identity_string:
            return jsonify({'message': 'Invalid token format'}), 401

        device_id, user_role = identity_string.split(':', 1)

        data = request.get_json(silent=True) or {}
        scans = data.get('scans', [])

        if not isinstance(scans, list):
            return jsonify({'message': 'scans must be a list'}), 400

        results = sync_security_scans_service(
            scans=scans,
            user_role=user_role,
            db=get_db()
        )

        return jsonify(results), 200

    except Exception as e:
        print(f"Error in sync_security_scans: {e}")
        return jsonify({'message': f'Server error: {str(e)}'}), 500


@app.route('/api/admin/student/allowed-time/<roll_no>', methods=['GET', 'POST'])
@jwt_required()
def manage_student_allowed_time_endpoint(roll_no):
    try:
        identity_string = get_jwt_identity()
        if ':' in identity_string:
            device_id, user_role = identity_string.split(':', 1)
            if user_role != 'admin':
                return jsonify({'message': 'Admin access required'}), 403
        else:
            return jsonify({'message': 'Invalid token format'}), 401

        if request.method == 'GET':
            result = get_student_allowed_time(roll_no)
            if 'error' in result:
                return jsonify({'message': result['error']}), 404
            return jsonify(result), 200

        elif request.method == 'POST':
            data = request.get_json()
            new_allowed_time = data.get('allowed_time_minutes')

            result = update_student_allowed_time(roll_no, new_allowed_time, device_id)
            if 'error' in result:
                return jsonify({'message': result['error']}), 400

            # Log the change
            log_security_event(
                'allowed_time_updated',
                'admin',
                device_id,
                get_remote_address(),
                {
                    'roll_no': roll_no,
                    'student_name': result.get('student_name', 'Unknown'),
                    'old_time': result.get('old_time', 480),
                    'new_time': result.get('new_allowed_time')
                }
            )

            return jsonify({
                'message': result['message'],
                'roll_no': roll_no,
                'student_name': result.get('student_name', 'Unknown'),
                'new_allowed_time': result.get('new_allowed_time'),
                'updated_at': get_ist_now().isoformat()
            }), 200

    except Exception as e:
        print(f"❌ Error in manage_student_allowed_time: {e}")
        return jsonify({'message': f'Server error: {str(e)}'}), 500

@app.route('/api/admin/student/allowed-time/<roll_no>/reset', methods=['POST'])
@jwt_required()
def reset_student_allowed_time_endpoint(roll_no):
    try:
        identity_string = get_jwt_identity()
        if ':' in identity_string:
            device_id, user_role = identity_string.split(':', 1)
            if user_role != 'admin':
                return jsonify({'message': 'Admin access required'}), 403

        result = reset_student_allowed_time(roll_no, device_id)
        if 'error' in result:
            return jsonify({'message': result['error']}), 404

        # Log the reset
        log_security_event(
            'allowed_time_reset',
            'admin',
            device_id,
            get_remote_address(),
            {
                'roll_no': roll_no,
                'student_name': result.get('student_name', 'Unknown'),
                'previous_time': result.get('previous_time', 480)
            }
        )

        return jsonify({
            'message': result['message'],
            'roll_no': roll_no,
            'student_name': result.get('student_name', 'Unknown'),
            'current_allowed_time': 480,
            'reset_at': get_ist_now().isoformat()
        }), 200

    except Exception as e:
        print(f"❌ Error in reset_student_allowed_time: {e}")
        return jsonify({'message': f'Server error: {str(e)}'}), 500


@app.route('/api/sync/canteen-visits', methods=['POST'])
@jwt_required()
def sync_canteen_visits():
    try:
        identity_string = get_jwt_identity()
        if ':' not in identity_string:
            return jsonify({'message': 'Invalid token format'}), 401

        device_id, user_role = identity_string.split(':', 1)

        data = request.get_json(silent=True) or {}
        visits = data.get('visits', [])

        if not isinstance(visits, list):
            return jsonify({'message': 'visits must be a list'}), 400

        results = sync_canteen_visits_service(
            visits=visits,
            user_role=user_role,
            db=get_db()
        )

        return jsonify(results), 200

    except Exception as e:
        print(f"Error in sync_canteen_visits: {e}")
        return jsonify({'message': f'Server error: {str(e)}'}), 500

@app.route('/api/sync/students', methods=['GET'])
@jwt_required()
def sync_students():
    """Sync students to local device database - minimal data only"""
    try:
        identity_string = get_jwt_identity()
        if ':' in identity_string:
            device_id, user_role = identity_string.split(':', 1)

        # Get query parameters
        hostel = request.args.get('hostel')
        limit = int(request.args.get('limit', 10000))
        fields = request.args.get('fields', 'roll_no,name,hostel')

        # Build query based on role
        query = {}

        # Filter by hostel if specified and user has hostel-specific role
        if hostel and '_' in user_role:
            query['hostel'] = hostel
        elif user_role.startswith('super_') or user_role.startswith('security_') or user_role.startswith('canteen_'):
            # Filter by user's hostel for non-admin roles
            if '_' in user_role:
                user_hostel = user_role.split('_')[1].upper()
                query['hostel'] = user_hostel

        # Get only essential fields
        projection = {
            'roll_no': 1,
            'name': 1,
            'hostel': 1,
            '_id': 0
        }

        # Get students from database
        students = list(db.students.find(query, projection).limit(limit))

        # Compress data for efficient transfer
        compressed_students = []
        for student in students:
            compressed_students.append({
                'roll_no': student.get('roll_no', ''),
                'name': student.get('name', ''),
                'hostel': student.get('hostel', '')
            })

        print(f"📱 Student sync: Sending {len(compressed_students)} students to device {device_id}")

        return jsonify({
            'success': True,
            'count': len(compressed_students),
            'students': compressed_students,
            'query': query,
            'hostel_filter': hostel if hostel else 'ALL',
            'timestamp': datetime.now(INDIA_TZ).isoformat()
        }), 200

    except Exception as e:
        print(f"❌ Error in student sync: {e}")
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500

@app.route('/api/student/validate-offline', methods=['POST'])
@jwt_required()
def validate_offline_scan():
    """Validate student scan when offline - lightweight endpoint"""
    try:
        data = request.get_json()
        roll_no = data.get('roll_no')

        result = validate_student_offline(roll_no)

        if result and result.get('valid'):
            return jsonify(result), 200
        else:
            return jsonify(result or {'valid': False, 'message': 'Student not found'}), 404

    except Exception as e:
        print(f"❌ Error in offline validation: {e}")
        return jsonify({'valid': False, 'error': str(e)}), 500

@app.route('/api/feedback/submit', methods=['POST'])
@jwt_required()
def submit_feedback():
    try:
        data = request.get_json()

        # Validate required fields
        required_fields = ['feedback', 'rating', 'category']
        for field in required_fields:
            if field not in data:
                return jsonify({'message': f'Missing required field: {field}'}), 400

        # Get user info from token
        identity_string = get_jwt_identity()
        user_info = {}
        if ':' in identity_string:
            device_id, user_role = identity_string.split(':', 1)
            user_info = {
                'device_id': device_id,
                'role': user_role
            }

        # Create feedback record
        feedback_record = {
            'feedback_id': str(uuid.uuid4()),
            'feedback_text': data['feedback'],
            'rating': int(data['rating']),
            'category': data['category'],
            'email': data.get('email'),
            'user_info': user_info,
            'timestamp': datetime.now(INDIA_TZ),
            'platform': data.get('platform', 'unknown'),
            'app_version': data.get('app_version', '2.0'),
            'status': 'pending_review'
        }

        # Store in database (create feedback collection if it doesn't exist)
        if 'feedback' not in db.list_collection_names():
            db.create_collection('feedback')
            db.feedback.create_index([('timestamp', -1)])
            db.feedback.create_index([('category', 1)])
            db.feedback.create_index([('rating', 1)])

        result = db.feedback.insert_one(feedback_record)

        # Log the feedback submission
        log_security_event(
            'feedback_submitted',
            user_info.get('role', 'unknown'),
            user_info.get('device_id', 'unknown'),
            get_remote_address(),
            {'feedback_id': feedback_record['feedback_id'], 'category': data['category']}
        )

        return jsonify({
            'message': 'Feedback submitted successfully',
            'feedback_id': feedback_record['feedback_id'],
            'submitted_at': feedback_record['timestamp'].isoformat()
        }), 200

    except Exception as e:
        print(f"❌ Error submitting feedback: {e}")
        return jsonify({'message': f'Error submitting feedback: {str(e)}'}), 500

# Admin endpoint to view feedback
@app.route('/api/admin/feedback', methods=['GET'])
@jwt_required()
def get_feedback():
    try:
        identity_string = get_jwt_identity()
        if ':' in identity_string:
            device_id, user_role = identity_string.split(':', 1)
            if user_role != 'admin':
                return jsonify({'message': 'Admin access required'}), 403

        # Get query parameters
        category = request.args.get('category')
        min_rating = request.args.get('min_rating', type=int)
        days = request.args.get('days', 30, type=int)
        limit = request.args.get('limit', 50, type=int)

        # Build query
        query = {}
        if category:
            query['category'] = category
        if min_rating:
            query['rating'] = {'$gte': min_rating}

        cutoff_date = datetime.now(INDIA_TZ) - timedelta(days=days)
        query['timestamp'] = {'$gte': cutoff_date}

        # Get feedback with pagination
        feedback = list(db.feedback.find(
            query,
            {'_id': 0}
        ).sort('timestamp', -1).limit(limit))

        # Get statistics
        stats = {
            'total_feedback': db.feedback.count_documents(query),
            'average_rating': 0,
            'by_category': {},
            'by_rating': {1: 0, 2: 0, 3: 0, 4: 0, 5: 0}
        }

        if feedback:
            total_rating = sum(f['rating'] for f in feedback)
            stats['average_rating'] = round(total_rating / len(feedback), 1)

            # Count by category
            for f in feedback:
                category = f.get('category', 'Unknown')
                stats['by_category'][category] = stats['by_category'].get(category, 0) + 1
                rating = f.get('rating', 0)
                if 1 <= rating <= 5:
                    stats['by_rating'][rating] = stats['by_rating'].get(rating, 0) + 1

        return jsonify({
            'feedback': feedback,
            'statistics': stats,
            'query_parameters': {
                'category': category,
                'min_rating': min_rating,
                'days': days,
                'limit': limit
            }
        }), 200

    except Exception as e:
        return jsonify({'message': f'Error retrieving feedback: {str(e)}'}), 500

@app.route('/api/students/hostel/<hostel>', methods=['GET'])
@jwt_required()
def get_students_by_hostel_endpoint(hostel):
    """
    Get all students for a specific hostel (for offline caching by security/canteen staff)
    Returns minimal data: roll_no, name, hostel only
    """
    try:
        identity_string = get_jwt_identity()
        if ':' in identity_string:
            device_id, user_role = identity_string.split(':', 1)

            # Only allow security and canteen roles to access this endpoint
            if not (user_role.startswith('security_') or user_role.startswith('canteen_')):
                return jsonify({
                    'success': False,
                    'message': 'This endpoint is only for security and canteen staff',
                    'allowed_roles': ['security_*', 'canteen_*'],
                    'your_role': user_role,
                    'suggested_endpoint': '/api/sync/students' if user_role == 'admin' else 'Contact admin'
                }), 403

            print(f"📱 Student sync request: Hostel {hostel} by {user_role}")

        # Get query parameters
        page = int(request.args.get('page', 1))
        page_size = int(request.args.get('page_size', 0))
        compress = request.args.get('compress', 'false').lower() == 'true'

        # Validate hostel parameter
        valid_hostels = ['A', 'B', 'C', 'D', 'ALL']
        if hostel not in valid_hostels:
            return jsonify({
                'success': False,
                'message': 'Invalid hostel. Must be A, B, C, D, or ALL',
                'valid_hostels': valid_hostels,
                'received_hostel': hostel
            }), 400

        # Get students using service
        result = get_students_by_hostel(hostel, page, page_size)

        # Prepare base response
        base_response = {
            'success': True,
            'purpose': 'offline_caching',
            'count': len(result['students']),
            'total_count': result['total_count'],
            'hostel': hostel,
            'hostel_display': 'ALL (A, B, C, D)' if hostel == 'ALL' else hostel,
            'fields_included': ['roll_no', 'name', 'hostel'],
            'note': 'Only minimal fields included to reduce storage. Additional data available via /api/student/<roll_no>/<role>',
            'pagination': {
                'page': result['page'],
                'page_size': result['page_size'],
                'total_pages': result['total_pages'],
                'has_more': result['page'] < result['total_pages'],
                'showing': f"{((result['page']-1) * (result['page_size'] if isinstance(result['page_size'], int) else 0)) + 1}-{((result['page']-1) * (result['page_size'] if isinstance(result['page_size'], int) else 0)) + len(result['students'])} of {result['total_count']}" if isinstance(result['page_size'], int) and result['page_size'] > 0 else f"ALL {result['total_count']}"
            },
            'estimated_size_kb': (len(json.dumps(result['students'])) / 1024) if result['students'] else 0,
            'timestamp': get_ist_now().isoformat()
        }

        # Handle compression if requested
        if compress and result['students']:
            try:
                import gzip
                import io

                full_response = {**base_response, 'students': result['students']}
                students_json = json.dumps(full_response, cls=CustomJSONEncoder)
                original_size = len(students_json)
                compressed = gzip.compress(students_json.encode('utf-8'))
                compressed_size = len(compressed)
                compression_ratio = 100 - (compressed_size * 100 / original_size) if original_size > 0 else 0

                print(f"📦 Compression: {original_size/1024:.1f}KB → {compressed_size/1024:.1f}KB ({compression_ratio:.1f}% saved)")

                base_response.update({
                    'compression_applied': True,
                    'original_size_kb': round(original_size / 1024, 2),
                    'compressed_size_kb': round(compressed_size / 1024, 2),
                    'compression_ratio': f"{compression_ratio:.1f}%"
                })

                response = make_response(compressed)
                response.headers['Content-Type'] = 'application/gzip'
                response.headers['Content-Encoding'] = 'gzip'
                response.headers['X-Metadata'] = json.dumps(base_response)
                response.headers['X-Student-Count'] = str(len(result['students']))

                return response

            except Exception as compression_error:
                print(f"⚠️ Compression failed, falling back to JSON: {compression_error}")
                base_response['compression_failed'] = True

        # Regular JSON response
        response_data = {**base_response, 'students': result['students']}
        return jsonify(response_data), 200

    except Exception as e:
        print(f"❌ Error in get_students_by_hostel: {e}")
        import traceback
        traceback.print_exc()

        return jsonify({
            'success': False,
            'message': f'Server error: {str(e)}',
            'endpoint': '/api/students/hostel/<hostel>',
            'valid_hostels': ['A', 'B', 'C', 'D', 'ALL'],
            'timestamp': get_ist_now().isoformat()
        }), 500


@app.route('/api/sync/check-student-data/<hostel>', methods=['GET'])
@jwt_required()
def check_student_data_availability(hostel):
    """Check if student data exists for offline use (security/canteen only)"""
    try:
        identity_string = get_jwt_identity()
        if ':' in identity_string:
            device_id, user_role = identity_string.split(':', 1)

            # Only for security and canteen
            if not (user_role.startswith('security_') or user_role.startswith('canteen_')):
                return jsonify({
                    'available': False,
                    'message': 'Offline sync is only available for security and canteen staff'
                }), 403

        # Simple count of students in hostel
        student_count = db.students.count_documents({'hostel': hostel})

        return jsonify({
            'available': True,
            'count': student_count,
            'hostel': hostel,
            'timestamp': datetime.now(INDIA_TZ).isoformat(),
            'ready_for_offline': student_count > 0,
            'message': f'Hostel {hostel} has {student_count} students available for offline scanning'
        }), 200

    except Exception as e:
        print(f"❌ Error checking student data: {e}")
        return jsonify({
            'available': False,
            'count': 0,
            'error': str(e)
        }), 200


@app.route('/api/students/all-minimal', methods=['GET'])
@jwt_required()
def get_all_students_minimal_endpoint():
    """
    Get ALL students from ALL hostels with MINIMAL data only
    Perfect for offline storage: roll_no, name, hostel only
    """
    try:
        identity_string = get_jwt_identity()
        if ':' in identity_string:
            device_id, user_role = identity_string.split(':', 1)

            # Only security and canteen need offline data
            if not (user_role.startswith('security_') or user_role.startswith('canteen_')):
                return jsonify({
                    'message': 'Offline student data is only for security and canteen staff'
                }), 403

        students = get_all_students_minimal()

        # Calculate approximate data size
        import sys
        sample_size = len(json.dumps(students[0])) if students else 0
        estimated_size_kb = (len(students) * sample_size) / 1024 if students else 0

        response = {
            'success': True,
            'purpose': 'offline_caching_minimal',
            'count': len(students),
            'fields_included': ['roll_no', 'name', 'hostel'],
            'fields_excluded': ['room_no', 'course', 'branch', 'contact_no', 'email',
                               'guardian_name', 'guardian_phone', 'home_address',
                               'fee_status', 'admission_date', 'in_out_records',
                               'disciplinary_records', 'medical_info'],
            'students': students,
            'estimated_size_kb': round(estimated_size_kb, 2),
            'timestamp': get_ist_now().isoformat()
        }

        print(f"✅ MINIMAL offline sync: {len(students)} students, ~{estimated_size_kb:.1f}KB")

        return jsonify(response), 200

    except Exception as e:
        print(f"❌ Error in get_all_students_minimal: {e}")
        return jsonify({
            'success': False,
            'message': f'Server error: {str(e)}'
        }), 500

@app.route('/api/students/count', methods=['GET'])
@jwt_required()
def get_student_counts_endpoint():
    """Get student counts for sync planning"""
    try:
        result = get_student_counts()
        result['timestamp'] = get_ist_now().isoformat()
        return jsonify(result), 200

    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500

if __name__ == "__main__":
    # Also run cleanup when the app starts for any stale records
    print("🚀 Starting Student Management System API Server...")
    print("📊 Version 2.0 - With Enhanced Analytics and Reporting")
    print("🔗 Available at: http://0.0.0.0:5000")
    print(f"🕒 DEBUG STARTUP - Server starting at UTC: {datetime.now(timezone.utc)}, IST: {datetime.now(INDIA_TZ)}")

    print("🧹 Initializing data cleanup for records older than 6 months...")

    # Run initial cleanup ONLY if database is connected
    if db_connected:
        try:
            cleanup_stats = comprehensive_data_cleanup()
            print(f"✅ Initial cleanup completed: {cleanup_stats}")
        except Exception as e:
            print(f"⚠️ Initial cleanup warning: {e}")
    else:
        print("⚠️ Skipping initial cleanup - no database connection")

    socketio.run(app, host="0.0.0.0", port=5000, debug=True)
