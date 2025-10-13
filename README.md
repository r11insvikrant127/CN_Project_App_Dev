Design and implement a secure, role-based mobile + backend system (Flutter frontend + Flask backend + MongoDB Atlas) that scans QR codes or accepts manual roll numbers to return student information with strict role-based views and device-bound authentication. 
Requirements:
	• Functionality: QR scan + manual roll entry.
	• Roles & access:
		○ 1 admin: full access to all student fields.
		○ 4 superintendents (Super_A…Super_D): can view limited student info for their assigned hostel only (name, roll, room, disciplinary records, medical info, in/out times, weekly lateness summary, etc.).
		○ 4 canteen staff (Canteen_A…D) and 4 security staff (Security_A…D): can view name, roll, hostel only for students of their hostel; security also records in-time/out-time on scan.
	• Authentication & device policy:
		○ On app start, detect device_id (via device_info_plus) and only allow the app to proceed if the device is registered/authorized.
		○ After device is accepted show role selection (admin, super, canteen, security) and then a sub-role (A/B/C/D) matching the hostel. Backend must enforce device→role/hostel mapping.
		○ Support device-bound multi-user login (Model 2): users authenticate with a unique ID (instead of password), backend issues JWTs with role+assigned_hostel claims. Also support biometric unlock (local-only) and optional OTP/admin rebind flow for device changes.
	• Data model (MongoDB Atlas) for students must include: name, roll, hostel (4 hostels + guest house), room no, course, academic year, branch, student phone/email, guardian name/phone, home address, disciplinary_records (list of {date,time,desc,action}), medical_info (list), fee status, admission date, in_time/out_time.
	• Business rules:
		○ Security scans update in/out and forward details to admin & superintendent. If student’s cumulative time > allowed threshold, auto-add disciplinary_record.
		○ Supers track unauthorized canteen visits (students from other hostels). If an unauthorized student eats in a different hostel’s canteen >7 days, a notice is issued.
	• Analytics & reporting:
		○ Weekly aggregation of unauthorised-eating counts per student/hostel; monthly visualizations (pie charts).
		○ Predictive analytics to (i) identify which hostel’s students visit which canteen, (ii) detect peak unauthorized hours, (iii) forecast next week’s unauthorized visits (target ~85% accuracy), (iv) flag suspicious patterns.
	• Real-time alerts & UX:
		○ Push notifications to supers for thresholds (hourly spikes, peak hour alerts, weekly report reminders).
		○ Canteen UI: when Canteen role is selected show subroles + a Menu button displaying 7-day Indian menu (Breakfast/Lunch/Snack/Dinner) in an attractive UI.
	• Extra requirements:
		○ Login attempt limiting, session timeouts, secure JWT storage, logging of blocked attempts.
		○ Support biometric device integration (optional hardware), localized date/time display, voice commands for silent command execution, and dark/light theme toggle, offline sync.
Deliverables required: a) complete Flutter app and Flask backend source code, b) MongoDB Atlas collection schemas / example documents, c) instructions to deploy, d) sample data and mock scripts for analytics, e) UI screenshots or preview.
