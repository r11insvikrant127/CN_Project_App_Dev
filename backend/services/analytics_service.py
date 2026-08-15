# services/analytics_service.py
"""
Analytics Service - Handles all analytics and reporting
Extracted from backend.py for better maintainability
"""

from datetime import datetime, timedelta, timezone
from collections import defaultdict
import numpy as np
from sklearn.linear_model import LinearRegression
from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score

from utils.time_utils import INDIA_TZ, get_ist_now, normalize_datetime_to_ist
from utils.db_utils import get_db


def get_unauthorized_visits_analytics(days=30, hostel=None, user_role=None, db=None):
    """
    Get unauthorized visits analytics with role-based filtering
    
    Args:
        days: Number of days to analyze
        hostel: Filter by hostel (for super users)
        user_role: Role of the requesting user
        db: Database connection (optional)
    
    Returns:
        dict: Analytics data
    """
    if db is None:
        db = get_db()
    
    if db is None:
        return {'error': 'Database unavailable'}
    
    cutoff_date = get_ist_now() - timedelta(days=days)
    
    # Build match filter
    match_filter = {
        'timestamp': {'$gte': cutoff_date},
        'is_unauthorized': True
    }
    
    # If super user, filter by their hostel
    if user_role and user_role.startswith('super_') and hostel:
        match_filter['$or'] = [
            {'student_hostel': hostel},
            {'canteen_hostel': hostel}
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
    
    results = list(db.canteen_visits.aggregate(pipeline))
    
    # Process for charts
    hostel_analysis = defaultdict(lambda: defaultdict(int))
    hourly_analysis = defaultdict(int)
    daily_analysis = defaultdict(int)
    
    for result in results:
        student_hostel = result['_id']['student_hostel']
        canteen_hostel = result['_id']['canteen_hostel']
        hostel_analysis[student_hostel][canteen_hostel] += result['visit_count']
        
        hour = result['latest_visit'].hour
        hourly_analysis[hour] += result['visit_count']
        
        day = result['_id']['date'].strftime('%Y-%m-%d')
        daily_analysis[day] += result['visit_count']
    
    # Generate predictions
    predictions = predict_unauthorized_visits(daily_analysis)
    
    return {
        'summary': {
            'total_unauthorized_visits': sum(daily_analysis.values()),
            'analysis_period_days': days,
            'average_daily_visits': sum(daily_analysis.values()) / len(daily_analysis) if daily_analysis else 0,
            'filtered_by_hostel': hostel if user_role and user_role.startswith('super_') else 'ALL'
        },
        'hostel_analysis': dict(hostel_analysis),
        'hourly_analysis': dict(hourly_analysis),
        'daily_analysis': dict(daily_analysis),
        'predictions': predictions
    }


def get_monthly_unauthorized_visits(year=None, month=None, hostel=None, user_role=None, db=None):
    """
    Get monthly unauthorized visits analytics
    
    Args:
        year: Year to analyze
        month: Month to analyze (1-12)
        hostel: Filter by hostel (for super users)
        user_role: Role of the requesting user
        db: Database connection (optional)
    
    Returns:
        dict: Monthly analytics data
    """
    if db is None:
        db = get_db()
    
    if db is None:
        return {'error': 'Database unavailable'}
    
    now = get_ist_now()
    year = year or now.year
    month = month or now.month
    
    start_date = datetime(year, month, 1, tzinfo=INDIA_TZ)
    if month == 12:
        end_date = datetime(year + 1, 1, 1, tzinfo=INDIA_TZ)
    else:
        end_date = datetime(year, month + 1, 1, tzinfo=INDIA_TZ)
    
    # Build match filter
    match_filter = {
        'timestamp': {'$gte': start_date, '$lt': end_date},
        'is_unauthorized': True
    }
    
    # If super user, filter by their hostel
    if user_role and user_role.startswith('super_') and hostel:
        match_filter['$or'] = [
            {'student_hostel': hostel},
            {'canteen_hostel': hostel}
        ]
    
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
    
    results = list(db.canteen_visits.aggregate(pipeline))
    
    # Prepare data for pie charts
    hostel_breakdown = defaultdict(lambda: defaultdict(int))
    canteen_breakdown = defaultdict(int)
    
    for result in results:
        student_hostel = result.get('student_hostel', 'Unknown')
        canteen_hostel = result.get('canteen_hostel', 'Unknown')
        visit_count = result.get('visit_count', 0)
        
        hostel_breakdown[student_hostel][canteen_hostel] += visit_count
        canteen_breakdown[canteen_hostel] += visit_count
    
    return {
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
            'filtered_by_hostel': hostel if user_role and user_role.startswith('super_') else 'ALL'
        }
    }


def predict_unauthorized_visits(daily_analysis):
    """
    Predict next week's unauthorized visits using
    scikit-learn LinearRegression.

    Evaluation:
    - Chronological 80% training / 20% testing split.
    - No random shuffle because this is time-series data.

    Final model:
    - Retrained on all available historical data.
    - Used to predict the next 7 days.
    """

    if not daily_analysis:
        return {
            'accuracy': 'Insufficient data',
            'predictions': [],
            'metrics': {}
        }

    # ---------------------------------------------------------
    # Sort dates chronologically
    # ---------------------------------------------------------
    dates = sorted(
        datetime.strptime(day, '%Y-%m-%d')
        for day in daily_analysis.keys()
    )

    # ---------------------------------------------------------
    # Create contiguous daily data.
    # Missing days are represented as 0 visits.
    # ---------------------------------------------------------
    start_date = dates[0]
    end_date = dates[-1]

    all_dates = []
    current_date = start_date

    while current_date <= end_date:
        all_dates.append(current_date)
        current_date += timedelta(days=1)

    visits = np.array([
        daily_analysis.get(
            date.strftime('%Y-%m-%d'),
            0
        )
        for date in all_dates
    ], dtype=float)

    # Need enough data for train/test evaluation.
    if len(all_dates) < 10:
        return {
            'accuracy': 'Insufficient data',
            'predictions': [],
            'metrics': {
                'message': 'At least 10 daily observations are required',
                'historical_days': len(all_dates)
            }
        }

    # ---------------------------------------------------------
    # Prepare ML data
    # X = day index
    # y = unauthorized visit count
    # ---------------------------------------------------------
    X = np.arange(
        len(visits),
        dtype=float
    ).reshape(-1, 1)

    y = visits

    # ---------------------------------------------------------
    # Chronological 80/20 train-test split
    # ---------------------------------------------------------
    split_index = max(
        1,
        int(len(X) * 0.8)
    )

    if split_index >= len(X):
        split_index = len(X) - 1

    X_train = X[:split_index]
    y_train = y[:split_index]

    X_test = X[split_index:]
    y_test = y[split_index:]

    # ---------------------------------------------------------
    # TRAIN ML MODEL
    # ---------------------------------------------------------
    model = LinearRegression()
    model.fit(X_train, y_train)

    # ---------------------------------------------------------
    # TEST MODEL ON UNSEEN DATA
    # ---------------------------------------------------------
    test_predictions = model.predict(X_test)

    # Visit counts cannot be negative.
    test_predictions = np.maximum(
        0,
        test_predictions
    )

    # ---------------------------------------------------------
    # Evaluation metrics
    # ---------------------------------------------------------
    mae = float(
        mean_absolute_error(
            y_test,
            test_predictions
        )
    )

    rmse = float(
        np.sqrt(
            mean_squared_error(
                y_test,
                test_predictions
            )
        )
    )

    r2 = float(
        r2_score(
            y_test,
            test_predictions
        )
    )

    # ---------------------------------------------------------
    # FINAL MODEL
    # Train on ALL historical data
    # ---------------------------------------------------------
    final_model = LinearRegression()
    final_model.fit(X, y)

    # ---------------------------------------------------------
    # Predict next 7 days
    # ---------------------------------------------------------
    future_X = np.arange(
        len(X),
        len(X) + 7,
        dtype=float
    ).reshape(-1, 1)

    future_predictions = final_model.predict(
        future_X
    )

    future_predictions = np.maximum(
        0,
        future_predictions
    )

    # ---------------------------------------------------------
    # Build prediction dates
    # ---------------------------------------------------------
    last_date = all_dates[-1]

    final_predictions = []

    for i, prediction in enumerate(
        future_predictions
    ):
        prediction_date = (
            last_date + timedelta(days=i + 1)
        )

        rounded_prediction = max(
            0,
            int(round(float(prediction)))
        )

        final_predictions.append({
            'date': prediction_date.strftime('%Y-%m-%d'),
            'predicted_visits': rounded_prediction,
            'raw_prediction': round(
                float(prediction),
                2
            )
        })

    # ---------------------------------------------------------
    # Confidence
    # ---------------------------------------------------------
    mean_test_visits = float(
        np.mean(y_test)
    )

    if mean_test_visits > 0:
        relative_error = mae / mean_test_visits

        confidence = max(
            0.0,
            min(
                1.0,
                1.0 - relative_error
            )
        )
    else:
        confidence = 0.0

    return {
        'accuracy': f'{max(0.0, r2) * 100:.1f}%',
        'confidence': round(
            confidence * 100,
            1
        ),

        'metrics': {
            'mae': round(mae, 3),
            'rmse': round(rmse, 3),
            'r2': round(r2, 3),
            'training_samples': len(X_train),
            'testing_samples': len(X_test),
            'total_historical_days': len(X),
            'evaluation_method': (
                'chronological_80_20_split'
            ),
            'model': 'sklearn.linear_model.LinearRegression'
        },

        'predictions': final_predictions
    }

def get_late_arrivals_analytics(hostel=None, user_role=None, db=None):
    """
    Get late arrivals analytics
    
    Args:
        hostel: Filter by hostel (for super users)
        user_role: Role of the requesting user
        db: Database connection (optional)
    
    Returns:
        dict: Late arrivals analytics
    """
    if db is None:
        db = get_db()
    
    if db is None:
        return {'error': 'Database unavailable'}
    
    # Build match filter
    match_filter = {
        'disciplinary_records.description': {'$regex': 'exceeded allowed time', '$options': 'i'}
    }
    
    # If super user, filter by their hostel
    if user_role and user_role.startswith('super_') and hostel:
        match_filter['hostel'] = hostel
    
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
    
    results = list(db.students.aggregate(pipeline))
    
    return {
        'weekly_late_arrivals': results,
        'summary': {
            'total_students_with_late_arrivals': len(set(r['_id']['roll_no'] for r in results)),
            'total_late_occurrences': sum(r['late_count'] for r in results),
            'filtered_by_hostel': hostel if user_role and user_role.startswith('super_') else 'ALL'
        }
    }


def calculate_weekly_late_arrivals(week_number=None, year=None, user_role=None, db=None):
    """
    Calculate weekly late arrivals for a specific week
    
    Args:
        week_number: Week number (1-53)
        year: Year
        user_role: Role of the requesting user
        db: Database connection (optional)
    
    Returns:
        dict: Weekly late arrivals report
    """
    if db is None:
        db = get_db()
    
    if db is None:
        return {'error': 'Database unavailable'}
    
    now = get_ist_now()
    week_number = week_number or now.isocalendar()[1]
    year = year or now.year
    
    # Calculate start and end of week (Monday to Sunday)
    start_date = datetime.fromisocalendar(year, week_number, 1).replace(tzinfo=INDIA_TZ)
    end_date = start_date + timedelta(days=7)
    
    # Check if data is still available
    cutoff_time = get_ist_now() - timedelta(days=30)
    if end_date < cutoff_time:
        return {
            'error': 'data_cleaned',
            'message': f'Data for week {week_number}, {year} has been cleaned up (older than 30 days)'
        }
    
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
    
    results = list(db.students.aggregate(pipeline))
    
    # Store weekly summary
    weekly_summary = {
        'week_number': week_number,
        'year': year,
        'calculation_date': get_ist_now(),
        'date_range': {
            'start': start_date.isoformat(),
            'end': end_date.isoformat()
        },
        'total_students_with_late_arrivals': len(results),
        'total_late_occurrences': sum(r['late_count'] for r in results),
        'total_time_exceeded_minutes': sum(r.get('total_time_exceeded', 0) for r in results),
        'details': results,
        'report_type': 'late_arrivals_weekly',
        'calculated_by': user_role
    }
    
    # Remove old report for same week if exists
    db.weekly_reports.delete_many({
        'week_number': week_number,
        'year': year,
        'report_type': 'late_arrivals_weekly'
    })
    
    # Insert new report
    db.weekly_reports.insert_one(weekly_summary)
    
    return {
        'message': f'Weekly late arrivals calculated for week {week_number}, {year}',
        'summary': {
            'week_number': week_number,
            'year': year,
            'total_students': len(results),
            'total_occurrences': sum(r['late_count'] for r in results),
            'total_time_exceeded_minutes': sum(r.get('total_time_exceeded', 0) for r in results)
        },
        'student_details': results
    }


def get_visit_trends(days=7, hostel=None, user_role=None, db=None):
    """
    Get visit trends with predictions
    
    Args:
        days: Number of days to analyze
        hostel: Filter by hostel (for super users)
        user_role: Role of the requesting user
        db: Database connection (optional)
    
    Returns:
        dict: Visit trends with predictions
    """
    if db is None:
        db = get_db()
    
    if db is None:
        return {'error': 'Database unavailable'}
    
    cutoff_date = get_ist_now() - timedelta(days=days)
    
    # Build match filter
    match_filter = {
        'timestamp': {'$gte': cutoff_date},
        'is_unauthorized': True
    }
    
    if user_role and user_role.startswith('super_') and hostel:
        match_filter['$or'] = [
            {'student_hostel': hostel},
            {'canteen_hostel': hostel}
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
    
    results = list(db.canteen_visits.aggregate(pipeline))
    
    # Generate predictions for the trend data
    trends_with_predictions = _generate_trend_predictions(results)
    
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
    
    return {
        'trends': trends_with_predictions,
        'summary': {
            'total_visits': total_visits,
            'average_daily': round(avg_daily, 1),
            'trend_direction': trend_direction,
            'trend_percentage': round(abs(trend_percentage), 1),
            'analysis_period_days': days,
            'scope': 'hostel' if user_role and user_role.startswith('super_') and hostel else 'system'
        }
    }


def _generate_trend_predictions(results):
    """Generate predictions for trend data using simple moving average"""
    if not results or len(results) < 2:
        return results
    
    # Ensure we have whole numbers for visits
    for item in results:
        if 'actual' in item:
            item['actual'] = int(round(item['actual']))
    
    # Use simple moving average for predictions
    visit_data = [item['actual'] for item in results]
    predictions = []
    
    for i in range(len(visit_data)):
        if i < 1:
            predictions.append(visit_data[i])
        else:
            pred = sum(visit_data[max(0, i-1):i+1]) / min(2, i+1)
            predictions.append(int(round(pred)))
    
    for i, item in enumerate(results):
        item['predicted'] = predictions[i]
    
    return results


def get_predictive_insights(days=30, hostel=None, user_role=None, db=None):
    """
    Get AI-powered predictive insights
    
    Args:
        days: Number of days to analyze
        hostel: Filter by hostel (for super users)
        user_role: Role of the requesting user
        db: Database connection (optional)
    
    Returns:
        dict: Predictive insights with alerts
    """
    if db is None:
        db = get_db()
    
    if db is None:
        return {'error': 'Database unavailable'}
    
    cutoff_date = get_ist_now() - timedelta(days=days)
    
    # Build match filter
    match_filter = {
        'timestamp': {'$gte': cutoff_date},
        'is_unauthorized': True
    }
    
    if user_role and user_role.startswith('super_') and hostel:
        match_filter['$or'] = [
            {'student_hostel': hostel},
            {'canteen_hostel': hostel}
        ]
    
    # Get all unauthorized visits for analysis
    visits = list(db.canteen_visits.find(match_filter))
    
    if not visits:
        return {
            'message': 'Insufficient data for predictive analysis',
            'insights': [],
            'predictions': [],
            'alerts': []
        }
    
    insights = _generate_predictive_insights(visits)
    predictions = _predict_next_week_visits(visits, user_role, hostel)
    alerts = _generate_ai_alerts(visits, db)
    
    return {
        'insights': insights,
        'predictions': predictions,
        'alerts': alerts,
        'summary': {
            'total_visits_analyzed': len(visits),
            'analysis_period_days': days,
            'generated_at': get_ist_now().isoformat()
        }
    }


def _generate_predictive_insights(visits):
    """Generate AI-powered insights from visit data"""
    insights = []
    
    if not visits:
        return insights
    
    # Hostel Movement Patterns
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
    
    # Insight 1: Hostel movement patterns
    for student_hostel, canteens in hostel_patterns.items():
        if len(canteens) > 1:
            top_canteen = max(canteens.items(), key=lambda x: x[1])
            insights.append({
                'type': 'hostel_movement',
                'title': f'🏠 {student_hostel} Movement Pattern',
                'description': f'Students from {student_hostel} most frequently visit {top_canteen[0]} canteen ({top_canteen[1]} visits)',
                'priority': 'medium',
                'data': dict(canteens)
            })
        elif canteens:
            canteen_name, count = list(canteens.items())[0]
            insights.append({
                'type': 'hostel_movement',
                'title': f'🏠 {student_hostel} Primary Canteen',
                'description': f'Students from {student_hostel} exclusively visit {canteen_name} canteen ({count} visits)',
                'priority': 'low',
                'data': dict(canteens)
            })
    
    # Insight 2: Peak days
    for student_hostel, days_data in day_patterns.items():
        if len(days_data) > 1 and max(days_data.values()) >= 3:
            peak_day = max(days_data.items(), key=lambda x: x[1])
            insights.append({
                'type': 'peak_day',
                'title': f'📅 {student_hostel} Peak Day',
                'description': f'{student_hostel} students show highest activity on {peak_day[0]}s ({peak_day[1]} visits)',
                'priority': 'low',
                'data': dict(days_data)
            })
    
    # Insight 3: Peak hours
    if hour_patterns and max(hour_patterns.values()) >= 3:
        peak_hour = max(hour_patterns.items(), key=lambda x: x[1])
        insights.append({
            'type': 'peak_hours',
            'title': '⏰ System-wide Peak Hours',
            'description': f'Peak unauthorized activity occurs at {peak_hour[0]}:00 ({peak_hour[1]} visits)',
            'priority': 'high',
            'data': dict(hour_patterns)
        })
    
    # Insight 4: General activity
    if not insights and visits:
        insights.append({
            'type': 'general_activity',
            'title': '📊 Activity Summary',
            'description': f'Total of {len(visits)} unauthorized visits analyzed',
            'priority': 'info',
            'data': {'total_visits': len(visits)}
        })
    
    return insights


def _predict_next_week_visits(
    visits,
    user_role=None,
    requested_hostel=None
):
    """
    Predict next week's unauthorized visits using
    scikit-learn LinearRegression.

    Model evaluation:
        Chronological 80/20 train-test split.

    Final prediction:
        Model is retrained on all historical observations
        and predicts the next 7 days.
    """

    # ---------------------------------------------------------
    # Apply hostel filtering for super users
    # ---------------------------------------------------------
    if (
        user_role
        and user_role.startswith('super_')
        and requested_hostel
    ):
        visits = [
            visit
            for visit in visits
            if (
                visit.get('student_hostel') == requested_hostel
                or
                visit.get('canteen_hostel') == requested_hostel
            )
        ]

    scope = (
        'hostel'
        if user_role and user_role.startswith('super_')
        else 'system'
    )

    if not visits:
        return {
            'accuracy': 'Insufficient data',
            'predictions': [],
            'confidence': 0,
            'scope': scope
        }

    # ---------------------------------------------------------
    # Aggregate unauthorized visits by calendar date
    # ---------------------------------------------------------
    daily_visits = defaultdict(int)

    for visit in visits:
        timestamp = visit.get('timestamp')

        if not timestamp:
            continue

        date_str = timestamp.strftime('%Y-%m-%d')
        daily_visits[date_str] += 1

    if not daily_visits:
        return {
            'accuracy': 'Insufficient data',
            'predictions': [],
            'confidence': 0,
            'scope': scope
        }

    # ---------------------------------------------------------
    # Create contiguous daily time series
    # ---------------------------------------------------------
    dates = sorted(
        datetime.strptime(
            day,
            '%Y-%m-%d'
        )
        for day in daily_visits.keys()
    )

    first_date = dates[0]
    last_date = dates[-1]

    all_dates = []
    current_date = first_date

    while current_date <= last_date:
        all_dates.append(current_date)
        current_date += timedelta(days=1)

    visit_counts = np.array([
        daily_visits.get(
            date.strftime('%Y-%m-%d'),
            0
        )
        for date in all_dates
    ], dtype=float)

    # ---------------------------------------------------------
    # Minimum data requirement
    # ---------------------------------------------------------
    if len(all_dates) < 10:
        return {
            'accuracy': 'Insufficient data',
            'predictions': [],
            'confidence': 0,
            'scope': scope,
            'metrics': {
                'message': (
                    'At least 10 daily observations are required '
                    'for train/test evaluation'
                ),
                'historical_days': len(all_dates)
            }
        }

    # ---------------------------------------------------------
    # Prepare ML data
    # ---------------------------------------------------------
    X = np.arange(
        len(visit_counts),
        dtype=float
    ).reshape(-1, 1)

    y = visit_counts

    # ---------------------------------------------------------
    # Chronological 80/20 split
    # ---------------------------------------------------------
    split_index = max(
        1,
        int(len(X) * 0.8)
    )

    if split_index >= len(X):
        split_index = len(X) - 1

    X_train = X[:split_index]
    y_train = y[:split_index]

    X_test = X[split_index:]
    y_test = y[split_index:]

    # ---------------------------------------------------------
    # TRAIN ML MODEL
    # ---------------------------------------------------------
    model = LinearRegression()
    model.fit(
        X_train,
        y_train
    )

    # ---------------------------------------------------------
    # TEST MODEL ON UNSEEN DATA
    # ---------------------------------------------------------
    test_predictions = model.predict(
        X_test
    )

    test_predictions = np.maximum(
        0,
        test_predictions
    )

    # ---------------------------------------------------------
    # Evaluation metrics
    # ---------------------------------------------------------
    mae = float(
        mean_absolute_error(
            y_test,
            test_predictions
        )
    )

    rmse = float(
        np.sqrt(
            mean_squared_error(
                y_test,
                test_predictions
            )
        )
    )

    r2 = float(
        r2_score(
            y_test,
            test_predictions
        )
    )

    # ---------------------------------------------------------
    # FINAL MODEL
    # Train on ALL historical data
    # ---------------------------------------------------------
    final_model = LinearRegression()
    final_model.fit(
        X,
        y
    )

    # ---------------------------------------------------------
    # Predict next 7 days
    # ---------------------------------------------------------
    future_dates = [
        last_date + timedelta(days=i)
        for i in range(1, 8)
    ]

    future_X = np.array([
        (date - first_date).days
        for date in future_dates
    ], dtype=float).reshape(-1, 1)

    future_predictions = final_model.predict(
        future_X
    )

    future_predictions = np.maximum(
        0,
        future_predictions
    )

    # ---------------------------------------------------------
    # Confidence
    # ---------------------------------------------------------
    mean_test_visits = float(
        np.mean(y_test)
    )

    if mean_test_visits > 0:
        relative_error = mae / mean_test_visits

        confidence = max(
            0.0,
            min(
                1.0,
                1.0 - relative_error
            )
        )
    else:
        confidence = 0.0

    # ---------------------------------------------------------
    # Build predictions
    # ---------------------------------------------------------
    final_predictions = []

    for pred_date, prediction in zip(
        future_dates,
        future_predictions
    ):
        raw_prediction = float(
            prediction
        )

        bounded_prediction = max(
            0,
            int(round(raw_prediction))
        )

        confidence_band = max(
            1,
            int(round(rmse))
        )

        final_predictions.append({
            'date': pred_date.strftime(
                '%Y-%m-%d'
            ),
            'day': pred_date.strftime(
                '%A'
            ),
            'predicted_visits': bounded_prediction,
            'confidence_band': (
                f'±{confidence_band}'
            ),
            'raw_prediction': round(
                raw_prediction,
                2
            )
        })

    return {
        'accuracy': f'{max(0.0, r2) * 100:.1f}%',
        'confidence': round(
            confidence * 100,
            1
        ),
        'scope': scope,

        'metrics': {
            'mae': round(mae, 3),
            'rmse': round(rmse, 3),
            'r2': round(r2, 3),
            'training_samples': len(X_train),
            'testing_samples': len(X_test),
            'total_historical_days': len(X),
            'evaluation_method': (
                'chronological_80_20_split'
            ),
            'model': 'sklearn.linear_model.LinearRegression'
        },

        'predictions': final_predictions
    }

def _generate_ai_alerts(visits, db=None):
    """Generate AI-powered alerts for suspicious patterns"""
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
        
        if visit['timestamp'] >= cutoff_24h:
            recent_activity[student_hostel] += 1
        
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
    
    # Store alerts
    if db and unique_alerts:
        for alert in unique_alerts:
            if 'timestamp' not in alert:
                alert['timestamp'] = get_ist_now()
            db.realtime_alerts.insert_one(alert)
    
    return unique_alerts


def submit_weekly_canteen_report(week_number, year, hostel, extra_students_count, 
                                  report_data, user_role, db=None):
    """
    Submit a weekly canteen report
    
    Args:
        week_number: Week number
        year: Year
        hostel: Hostel name
        extra_students_count: Number of extra students
        report_data: Report data dict
        user_role: Role of the submitter
        db: Database connection (optional)
    
    Returns:
        dict: Report submission result
    """
    if db is None:
        db = get_db()
    
    if db is None:
        return {'error': 'Database unavailable'}
    
    report = {
        'week_number': week_number,
        'year': year,
        'hostel': hostel,
        'extra_students_count': extra_students_count,
        'report_data': report_data or {},
        'submitted_by': user_role,
        'submitted_at': get_ist_now(),
        'report_type': 'canteen_weekly'
    }
    
    result = db.weekly_reports.insert_one(report)
    
    return {
        'message': 'Weekly canteen report submitted successfully',
        'report_id': str(result.inserted_id),
        'week_number': week_number,
        'year': year,
        'hostel': hostel,
        'extra_students_count': extra_students_count
    }


def get_late_arrivals_reports(limit=12, db=None):
    """
    Get late arrivals reports
    
    Args:
        limit: Maximum number of reports to return
        db: Database connection (optional)
    
    Returns:
        list: List of reports
    """
    if db is None:
        db = get_db()
    
    if db is None:
        return []
    
    reports = list(db.weekly_reports.find(
        {'report_type': 'late_arrivals_weekly'},
        {'_id': 0}
    ).sort([('year', -1), ('week_number', -1)]).limit(limit))
    
    return reports