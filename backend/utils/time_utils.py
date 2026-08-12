# utils/time_utils.py
"""
Time Utilities - Centralized timezone handling
Prevents timezone bugs across the application
"""

from datetime import datetime, timedelta, timezone
import time

# India timezone (UTC+5:30)
INDIA_TZ = timezone(timedelta(hours=5, minutes=30))


def get_ist_now():
    """Get current time in IST (India Standard Time)"""
    return datetime.now(INDIA_TZ)


def get_utc_now():
    """Get current time in UTC"""
    return datetime.now(timezone.utc)


def normalize_datetime_to_ist(dt):
    """
    Convert any datetime to IST (India Standard Time)
    
    Args:
        dt: datetime object (can be naive or with timezone)
    
    Returns:
        datetime: Timezone-aware datetime in IST
    """
    if dt is None:
        return None
    
    # If it's a string, try to parse it
    if isinstance(dt, str):
        try:
            dt = datetime.fromisoformat(dt.replace('Z', '+00:00'))
        except Exception as e:
            raise ValueError(f"Invalid datetime string: {dt}") from e
    
    # If naive, assume UTC
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    
    # Convert to IST
    return dt.astimezone(INDIA_TZ)


def calculate_duration_minutes(start_time, end_time):
    """
    Calculate duration in minutes between two datetimes
    
    Args:
        start_time: Start datetime (will be normalized to IST)
        end_time: End datetime (will be normalized to IST)
    
    Returns:
        float: Duration in minutes (can be negative if end_time < start_time)
    """
    start = normalize_datetime_to_ist(start_time)
    end = normalize_datetime_to_ist(end_time)
    
    if start is None or end is None:
        return 0
    
    duration_seconds = (end - start).total_seconds()
    return duration_seconds / 60


def format_datetime_ist(dt, format_str='%Y-%m-%d %H:%M:%S'):
    """Format datetime in IST"""
    if dt is None:
        return None
    normalized = normalize_datetime_to_ist(dt)
    return normalized.strftime(format_str)


def is_within_time_limit(start_time, end_time, limit_minutes):
    """
    Check if duration between two times is within limit
    
    Returns:
        tuple: (is_within_limit, duration_minutes, exceeded_minutes)
    """
    duration = calculate_duration_minutes(start_time, end_time)
    exceeded = max(0, duration - limit_minutes)
    return (duration <= limit_minutes, duration, exceeded)