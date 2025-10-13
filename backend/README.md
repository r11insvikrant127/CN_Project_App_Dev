# Student Management System Backend

A comprehensive Flask-based backend system for managing student movements, canteen visits, and security operations with real-time analytics and predictive insights.

## Features

- **Multi-role Authentication** (Admin, Supervisors, Security, Canteen staff)
- **Student Movement Tracking** (Check-in/Check-out)
- **Canteen Visit Monitoring** with unauthorized access detection
- **Real-time Analytics & Predictive Insights** using ML
- **Weekly/Monthly Reporting**
- **Offline Sync Capability**
- **Security Logging & Rate Limiting**
- **JWT-based Authentication**

## Roles & Permissions

- **Admin**: Full system access, device management, security logs
- **Supervisors** (super_a, super_b, etc.): Hostel-specific oversight, weekly reports
- **Security** (security_a, security_b, etc.): Student movement tracking
- **Canteen** (canteen_a, canteen_b, etc.): Visit recording, unauthorized access alerts

## Complete API Endpoints (32+ Endpoints)

### 🔐 Authentication & Security
- `POST /api/verify-device` - Device verification
- `POST /api/authenticate-subrole` - Role-based authentication
- `POST /api/admin/authenticate` - Admin biometric/device auth
- `GET /api/verify-token` - Token validation
- `POST /api/refresh-token` - Token refresh
- `POST /api/admin/logout` - Admin logout
- `POST /api/secure-login` - Secure login with rate limiting
- `GET /api/admin/security-logs` - Get security logs (admin only)

### 👥 Student Operations
- `GET /api/student/<roll_no>/<selected_role>` - Get student details with role-based access
- `POST /api/student/scan/security/<selected_role>` - Security scans (in/out) with offline sync
- `POST /api/student/scan/canteen/<selected_role>` - Canteen visits with unauthorized detection
- `POST /api/student/scan/admin/<selected_role>` - Admin verification scans

### 📊 Analytics & Insights
- `GET /api/analytics/unauthorized-visits` - Unauthorized visit analytics (30-day default)
- `GET /api/analytics/unauthorized-visits-monthly` - Monthly pie charts with hostel filtering
- `GET /api/analytics/late-arrivals` - Late arrival analytics
- `POST /api/analytics/late-arrivals-weekly` - Weekly late arrivals calculation
- `GET /api/analytics/late-arrivals-reports` - Get weekly late arrival reports
- `GET /api/analytics/predictive-insights` - AI-powered insights with ML predictions
- `GET /api/analytics/visit-trends` - Visit trend analysis with predictions
- `POST /api/analytics/weekly-report` - Generate comprehensive weekly report

### 🚨 Alerts & Monitoring
- `GET /api/alerts/realtime` - Real-time alerts from database
- `GET /api/alerts/real-time` - Real-time alert system with timeframe
- `GET /api/alerts/weekly-summary` - Weekly summary for alerts

### 📋 Reports & Management
- `POST /api/canteen/weekly-report` - Submit weekly canteen report (supers)
- `GET /api/admin/devices` - Get all devices (admin only)
- `POST /api/admin/devices` - Add new device (admin only)
- `POST /api/admin/cleanup-records` - Manual cleanup of old records

### 🔄 Sync & Offline Support
- `POST /api/sync/security-scans` - Sync offline security scans
- `POST /api/sync/canteen-visits` - Sync offline canteen visits

### 🛠️ Debug & Utility
- `GET /api/test/data` - Test endpoint for backend verification
- `GET /api/debug/canteen-data` - Debug endpoint for canteen data inspection
- `GET /health` - Health check endpoint
- `GET /` - Home endpoint with API documentation

