# services/alert_service.py
"""
Alert Service - Handles all alert creation and management
Extracted from backend.py for better maintainability
"""

from datetime import datetime, timedelta
from collections import defaultdict
from utils.time_utils import INDIA_TZ, get_ist_now
from utils.db_utils import get_db


def create_unauthorized_alert(visit_record, db=None):
    """
    Create a real-time alert for unauthorized canteen visit
    
    Args:
        visit_record: The visit record that triggered the alert
        db: Database connection (optional)
    
    Returns:
        dict: The created alert
    """
    if db is None:
        db = get_db()
    
    if db is None:
        print("⚠️ Cannot create alert - database unavailable")
        return None
    
    alert_message = {
        'type': 'unauthorized_visit',
        'message': f'🚨 Unauthorized canteen visit detected!',
        'details': {
            'student': visit_record.get('student_name', 'Unknown'),
            'student_hostel': visit_record.get('student_hostel', 'Unknown'),
            'canteen_hostel': visit_record.get('canteen_hostel', 'Unknown'),
            'roll_no': visit_record.get('roll_no', 'Unknown'),
            'time': visit_record.get('timestamp', get_ist_now()).strftime('%H:%M')
        },
        'timestamp': get_ist_now(),
        'priority': 'high',
        'auto_generated': True
    }
    
    result = db.realtime_alerts.insert_one(alert_message)
    print(f"📢 UNAUTHORIZED ALERT: {alert_message['message']}")
    
    return alert_message


def create_time_violation_alert(roll_no, checkout, out_time_utc, allowed_minutes, 
                                exceeded_minutes, now_utc, db=None):
    """
    Create a real-time alert for time violation
    
    Args:
        roll_no: Student roll number
        checkout: Active checkout record
        out_time_utc: Time student went out (UTC)
        allowed_minutes: Allowed time in minutes
        exceeded_minutes: Minutes exceeded
        now_utc: Current time (UTC)
        db: Database connection (optional)
    
    Returns:
        dict: The created alert
    """
    if db is None:
        db = get_db()
    
    if db is None:
        print("⚠️ Cannot create alert - database unavailable")
        return None
    
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
            'exceeded_minutes': exceeded_minutes
        },
        'timestamp': now_utc,
        'priority': 'high',
        'auto_generated': True,
        'proactive_monitoring': True
    }
    
    result = db.realtime_alerts.insert_one(alert_message)
    print(f"🔔 TIME VIOLATION ALERT | Roll={roll_no} | AlertID={result.inserted_id}")
    
    return alert_message


def get_recent_alerts(hours=24, limit=50, alert_type=None, db=None):
    """
    Get recent alerts
    
    Args:
        hours: Number of hours to look back
        limit: Maximum number of alerts to return
        alert_type: Filter by alert type (optional)
        db: Database connection (optional)
    
    Returns:
        list: List of alerts
    """
    if db is None:
        db = get_db()
    
    if db is None:
        return []
    
    cutoff_time = get_ist_now() - timedelta(hours=hours)
    
    query = {'timestamp': {'$gte': cutoff_time}}
    if alert_type:
        query['type'] = alert_type
    
    alerts = list(db.realtime_alerts.find(
        query,
        {'_id': 0}
    ).sort('timestamp', -1).limit(limit))
    
    return alerts


def get_weekly_summary(db=None):
    """
    Get weekly summary of unauthorized visits
    
    Args:
        db: Database connection (optional)
    
    Returns:
        dict: Weekly summary data
    """
    if db is None:
        db = get_db()
    
    if db is None:
        return {'weekly_summary': {}}
    
    week_start = get_ist_now() - timedelta(days=get_ist_now().weekday())
    week_start = week_start.replace(hour=0, minute=0, second=0, microsecond=0)
    
    # Get this week's unauthorized visits
    visits = list(db.canteen_visits.find({
        'timestamp': {'$gte': week_start},
        'is_unauthorized': True
    }))
    
    # Group by hostel
    hostel_summary = defaultdict(int)
    for visit in visits:
        student_hostel = visit.get('student_hostel', 'Unknown')
        hostel_summary[student_hostel] += 1
    
    return {
        'weekly_summary': {
            'total_visits': len(visits),
            'hostel_breakdown': dict(hostel_summary),
            'week_start': week_start.isoformat(),
            'days_remaining': 6 - get_ist_now().weekday()
        }
    }


def generate_analytics_alerts(hostel_analysis, daily_analysis, db=None):
    """
    Generate intelligent alerts based on analytics patterns
    
    Args:
        hostel_analysis: Hostel movement data
        daily_analysis: Daily visit data
        db: Database connection (optional)
    
    Returns:
        list: List of alerts
    """
    alerts = []
    
    # Peak hour detection
    recent_visits = {k: v for k, v in daily_analysis.items() 
                    if datetime.strptime(k, '%Y-%m-%d') > get_ist_now() - timedelta(days=7)}
    
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
    
    # Store alerts if db is available
    if db and alerts:
        for alert in alerts:
            alert['timestamp'] = get_ist_now()
            alert['auto_generated'] = True
            db.realtime_alerts.insert_one(alert)
    
    return alerts


def generate_ai_alerts(visits, db=None):
    """
    Generate AI-powered alerts for suspicious patterns
    
    Args:
        visits: List of visit records
        db: Database connection (optional)
    
    Returns:
        list: List of alerts
    """
    alerts = []
    
    if not visits:
        return alerts
    
    if db is None:
        db = get_db()
    
    # Group visits by hour and hostel
    hourly_activity = defaultdict(lambda: defaultdict(int))
    hostel_activity = defaultdict(int)
    recent_activity = defaultdict(int)
    
    cutoff_24h = get_ist_now() - timedelta(hours=24)
    cutoff_2h = get_ist_now() - timedelta(hours=2)
    
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
            if recent_activity[student_hostel] >= 5:
                alerts.append({
                    'type': 'high_activity_short_term',
                    'title': '🚨 High Activity Alert',
                    'message': f'{student_hostel} students showing unusual activity: {recent_activity[student_hostel]} visits in 2 hours',
                    'priority': 'high',
                    'hostel': student_hostel,
                    'count': recent_activity[student_hostel],
                    'timeframe': '2 hours',
                    'timestamp': get_ist_now()
                })
    
    # Alert for overall high activity hostels
    avg_activity = np.mean(list(hostel_activity.values())) if hostel_activity else 0
    for hostel, count in hostel_activity.items():
        if count > avg_activity * 2 and count >= 5:
            alerts.append({
                'type': 'high_activity_hostel',
                'title': '👥 Suspicious Pattern Detected',
                'message': f'{hostel} students showing increased activity: {count} visits vs average {avg_activity:.1f}',
                'priority': 'medium',
                'hostel': hostel,
                'count': count,
                'average': round(avg_activity, 1),
                'timestamp': get_ist_now()
            })
    
    # Remove duplicates
    unique_alerts = []
    seen_messages = set()
    for alert in alerts:
        if alert['message'] not in seen_messages:
            unique_alerts.append(alert)
            seen_messages.add(alert['message'])
    
    # Store alerts if db is available
    if db and unique_alerts:
        for alert in unique_alerts:
            if 'timestamp' not in alert:
                alert['timestamp'] = get_ist_now()
            db.realtime_alerts.insert_one(alert)
    
    return unique_alerts


def generate_real_time_alerts(visits, timeframe_hours, db=None):
    """
    Generate real-time alerts for supervisors
    
    Args:
        visits: List of visits in the timeframe
        timeframe_hours: Number of hours to analyze
        db: Database connection (optional)
    
    Returns:
        list: List of alerts
    """
    alerts = []
    
    if not visits:
        alerts.append({
            'type': 'no_activity',
            'title': '✅ All Clear',
            'message': f'No unauthorized visits detected in the last {timeframe_hours} hours',
            'priority': 'info',
            'icon': 'check_circle',
            'timestamp': get_ist_now()
        })
        return alerts
    
    if db is None:
        db = get_db()
    
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
            'timeframe': f'{timeframe_hours} hours',
            'timestamp': get_ist_now()
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
                'count': count,
                'timestamp': get_ist_now()
            })
    
    # Alert 3: Peak hour detection
    if hourly_breakdown:
        peak_hour = max(hourly_breakdown.items(), key=lambda x: x[1])
        if peak_hour[1] >= 3:
            current_hour = get_ist_now().hour
            if abs(peak_hour[0] - current_hour) <= 2:
                alerts.append({
                    'type': 'peak_hour_alert',
                    'title': '⏰ Peak Hour Alert',
                    'message': f'Peak activity at {peak_hour[0]}:00 - {peak_hour[1]} visits. Increased vigilance recommended.',
                    'priority': 'medium',
                    'peak_hour': peak_hour[0],
                    'visit_count': peak_hour[1],
                    'timestamp': get_ist_now()
                })
    
    # Alert 4: Weekly report reminder (for supers)
    if timeframe_hours >= 24:
        today = get_ist_now()
        if today.weekday() == 6:
            weekly_visits = len(list(db.canteen_visits.find({
                'timestamp': {'$gte': today - timedelta(days=7)},
                'is_unauthorized': True
            })))
            
            alerts.append({
                'type': 'weekly_report_reminder',
                'title': '📋 Weekly Report Due',
                'message': f'Weekly report due tomorrow - {weekly_visits} unauthorized visits recorded this week',
                'priority': 'info',
                'weekly_visits': weekly_visits,
                'timestamp': get_ist_now()
            })
    
    return alerts