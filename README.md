Student Management System - Secure Role-Based Mobile Application
Project Overview
This project implements a comprehensive, secure role-based student management system with a Flutter mobile frontend and Flask backend, utilizing MongoDB Atlas for data storage. The system enables efficient student tracking through QR code scanning and manual roll number entry while maintaining strict access controls based on user roles and device authorization.

Core Functionality:
The application provides two primary methods for student lookup: QR code scanning and manual roll number entry. Upon successful identification, the system returns student information tailored to the user's role permissions, ensuring data privacy and security through robust access control mechanisms.

Role-Based Access Control:
The system implements a hierarchical role structure with distinct permission levels. The Admin role possesses full access to all student data fields. Four Superintendent roles (Super_A through Super_D) are limited to viewing specific student information for their assigned hostel only, including name, roll number, room assignment, disciplinary records, medical information, in/out times, and weekly lateness summaries. Four Canteen staff roles (Canteen_A through Canteen_D) and four Security staff roles (Security_A through Security_D) can view only name, roll number, and hostel information for students belonging to their assigned hostel. Security staff additionally record student entry and exit times during scanning operations.

Authentication and Device Security:
The application implements a sophisticated device-binding security model. Upon startup, the app detects the device ID using the device_info_plus package and only proceeds if the device is pre-registered and authorized in the system. After successful device verification, users select their primary role (admin, superintendent, canteen, or security) followed by a sub-role (A, B, C, D) corresponding to their assigned hostel. The backend rigorously enforces the device-to-role and device-to-hostel mapping to prevent unauthorized access.

The system supports device-bound multi-user authentication where users authenticate using unique identifiers instead of traditional passwords. The backend issues JSON Web Tokens (JWTs) containing role and assigned hostel claims. Additional security features include biometric unlock functionality for local device access and optional OTP-based or admin-initiated rebinding workflows for device changes.

Data Architecture:
The MongoDB Atlas data model comprehensively captures student information including personal details (name, roll number, hostel assignment covering four hostels plus guest house, room number), academic information (course, academic year, branch), contact details (student phone/email, guardian name/phone, home address), and administrative records. The model also tracks disciplinary records as timestamped entries with descriptions and actions, medical information history, fee payment status, admission date, and real-time in/out timestamps.

Business Logic and Automation:
The system implements automated business rules to maintain operational integrity. Security scans automatically update student entry and exit times while forwarding relevant details to administrators and superintendents. The system monitors cumulative student time and automatically adds disciplinary records when thresholds are exceeded. Superintendents track unauthorized canteen visits across hostels, with the system issuing formal notices when students from other hostels repeatedly use unauthorized canteens beyond the seven-day threshold.

Analytics and Reporting:
Comprehensive analytics capabilities include weekly aggregation of unauthorized eating incidents per student and hostel, supplemented by monthly visualizations through pie charts and other graphical representations. Predictive analytics identify patterns in hostel-to-canteen visitation, detect peak unauthorized hours, forecast upcoming week unauthorized visits with approximately 85% accuracy targets, and flag suspicious behavioral patterns for further investigation.

Real-Time Alerts and User Experience:
The system provides real-time push notifications to superintendents for various threshold events including hourly activity spikes, peak hour alerts, and weekly report reminders. The canteen staff interface includes role selection with sub-role options and features an attractive menu button displaying a comprehensive seven-day Indian menu organized by breakfast, lunch, snack, and dinner categories.

Security and Additional Features:
Enterprise-grade security measures include login attempt rate limiting, configurable session timeouts, secure JWT storage implementation, and comprehensive logging of blocked access attempts. The application supports optional biometric hardware integration, localized date and time display, voice command functionality for silent operation, dark/light theme toggling, and robust offline synchronization capabilities.

Deliverables:
The complete project delivery includes the full Flutter application source code and Flask backend implementation, comprehensive MongoDB Atlas collection schemas with example documents, detailed deployment instructions, sample datasets with mock scripts for analytics demonstration, and UI screenshots or application previews.
