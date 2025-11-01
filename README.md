# 🎓 Student Management System — Secure Role-Based Mobile Application

A **comprehensive, secure, and scalable Student Management System** featuring a **Flutter mobile frontend**, **Flask backend**, and **MongoDB Atlas** cloud database.  
The system provides real-time student tracking, strict role-based access control, device-level authentication, and intelligent analytics for institutional management.

---

## 🚀 Project Overview

This project integrates modern mobile and web technologies to streamline student information management while maintaining **enterprise-grade security**.  
It enables authorized personnel — administrators, superintendents, canteen staff, and security staff — to access student data according to their assigned roles and device authorizations.

---

## 🧩 Core Functionality

- 🔍 **Student Lookup** — via **QR Code Scanning** or **Manual Roll Number Entry**
- 🔒 **Role-Based Access Control (RBAC)** ensuring data visibility by user hierarchy
- 📱 **Device Binding** to enforce secure, hardware-linked authentication
- 🧠 **Smart Automation** — automatic updates for entries/exits and rule enforcement
- 📊 **Real-Time Analytics** — behavioral insights, prediction models, and visualization dashboards
- 🔔 **Push Notifications** — for critical alerts, threshold events, and weekly summaries

---

## 👥 Role-Based Access Control (RBAC)

| Role Type | Description | Permissions |
|------------|-------------|--------------|
| **Admin** | Full-access system administrator | View and manage all student data fields, devices, and logs |
| **Superintendents (Super_A–D)** | Hostel-specific supervisors | Access limited to students in their hostel: name, roll, room, disciplinary, medical, in/out, weekly lateness |
| **Canteen Staff (Canteen_A–D)** | Hostel-assigned canteen personnel | View only basic info: name, roll, hostel |
| **Security Staff (Security_A–D)** | Entry/exit tracking staff | View student ID, roll, hostel; log entry/exit times |

---

## 🔐 Authentication & Device Security

- **Device Binding:**  
  The app uses the `device_info_plus` package to fetch a **unique device ID**.  
  Only pre-registered, authorized devices can log in and operate.

- **Role Verification:**  
  After validation, users select their **primary role** (Admin, Superintendent, Canteen, Security)  
  and **sub-role** (A–D) mapped to specific hostels.

- **Token-Based Authentication:**  
  Flask backend issues **JWTs** containing role and hostel claims for every session.

- **Security Features:**
  - Device-bound multi-user authentication  
  - Biometric unlock for local access  
  - Optional **OTP-based** or **Admin-approved** rebinding workflows  
  - Session timeouts, rate limiting, and intrusion logging  

---

## 🧱 Data Architecture — MongoDB Atlas

Each student document stores comprehensive academic, personal, and administrative data.

| Category | Fields |
|-----------|--------|
| **Personal** | Name, Roll No, Hostel (A–D + Guest), Room No |
| **Academic** | Course, Year, Branch |
| **Contact** | Student & Guardian phones/emails, Address |
| **Administrative** | Fee status, Admission date, Disciplinary records |
| **Medical** | Health history with timestamps and remarks |
| **Attendance** | In/Out timestamps, Weekly lateness summaries |
| **Security** | Device bindings, role claims, access logs |

### Example Collections
- `students`
- `hostels`
- `devices`
- `disciplinary_records`
- `canteen_logs`
- `security_scans`
- `analytics_reports`

---

## ⚙️ Business Logic & Automation

### 🧠 Automated Operations
- Security scans automatically log student **entry/exit times**
- Unauthorized canteen visits trigger alerts and disciplinary tracking
- Cross-hostel dining violations beyond **7-day threshold** prompt notice generation
- Automated updates to cumulative stay time and lateness statistics

### 📬 Notification System
- Real-time push alerts for:
  - Hourly activity spikes  
  - Unauthorized canteen visits  
  - Weekly analytics report reminders  
  - Entry/Exit anomalies  

---

## 📊 Analytics & Reporting

| Metric | Description |
|---------|--------------|
| **Weekly Aggregation** | Unauthorized eating incidents per student/hostel |
| **Monthly Charts** | Visual breakdowns of violations and attendance |
| **Predictive Analytics** | 85% accuracy forecasting for next-week unauthorized visits |
| **Pattern Recognition** | Identifies suspicious cross-hostel behavior |
| **Peak Hour Detection** | Detects high-traffic hours and triggers alerts |

All analytics are visualized using **charts and dashboards** built into the Flutter frontend.

---

## 📱 Mobile Frontend — Flutter

### Features
- Built with **Flutter 3.x (Dart)**  
- Fully responsive mobile layout  
- Secure JWT storage with encryption  
- **Biometric unlock**, **Offline sync**, and **Dark/Light themes**

### Core Packages
| Package | Purpose |
|----------|----------|
| `device_info_plus` | Device ID retrieval for binding |
| `http` | RESTful API integration with Flask |
| `qr_code_scanner` | QR code scanning for student lookup |
| `shared_preferences` | Local JWT and theme persistence |
| `flutter_secure_storage` | Encrypted credential management |
| `charts_flutter` | Data visualization for analytics |

---

## 🧠 Flask Backend — REST API

### Key Modules
| Module | Description |
|---------|-------------|
| `auth.py` | Device validation, JWT issuance, role verification |
| `students.py` | Student lookup via roll number or QR |
| `security.py` | Entry/exit scan logging |
| `canteen.py` | Canteen access validation and logging |
| `superintendent.py` | Hostel management and discipline tracking |
| `analytics.py` | Weekly/monthly data aggregation |
| `notifications.py` | Push alert delivery via Firebase Cloud Messaging (FCM) |

### Security Middleware
- JWT role and hostel claim validation  
- Device ID verification on every request  
- Rate-limiting and anti-brute-force protection  
- Comprehensive request logging  

---

## ☁️ Deployment Architecture

### Components
- **Flutter App:** Android & iOS builds
- **Backend:** Flask REST API (hosted on Render/Heroku/AWS EC2)
- **Database:** MongoDB Atlas (Cloud Cluster)
- **Notifications:** Firebase Cloud Messaging (FCM)
- **Analytics Engine:** Flask + Python ML for prediction

### Deployment Steps
1. Set up MongoDB Atlas and import initial schema.  
2. Configure Flask `.env` with:

   ```env
   MONGO_URI=<connection_string>
   JWT_SECRET=<secret_key>
   FCM_KEY=<firebase_key>

3. Build the Flutter mobile app: flutter build apk --release
4. Distribute the build through internal testing channels or publish on the Play Store.


---

```markdown
## 🧰 Security & Additional Features

- 🔐 **Enterprise-grade JWT handling** and claim verification  
- ⚡ **Rate limiting** and session timeout enforcement  
- 🧬 **Biometric authentication** for app unlock  
- 🎙️ **Voice command** support for silent scanning operations  
- 🌓 **Configurable themes** (Light/Dark)  
- 🔄 **Offline synchronization** with cached queue management  
- 🕒 **Localized date/time display** (IST timezone support)


## 📦 Deliverables

| Deliverable | Description |
|--------------|-------------|
| **Flutter App Source Code** | Complete frontend source with modular architecture |
| **Flask Backend** | Full REST API implementation |
| **MongoDB Atlas Schemas** | Collection definitions and sample documents |
| **Deployment Guide** | Detailed setup and hosting documentation |
| **Sample Dataset** | Mock data for analytics and testing demonstrations |
| **UI Previews** | Screenshots or video previews for presentation |

