import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'scan_screen.dart';
import 'monthly_analytics_screen.dart';
import 'weekly_report_screen.dart';  
import 'predictive_analytics_screen.dart';
import 'package:provider/provider.dart';
import 'theme_toggle_widget.dart';
import 'app_themes.dart'; 
import 'voice_command_mixin.dart';
import 'local_db_helper.dart';
import 'network_service.dart';
import 'sync_service.dart';
import 'pdf_report_service.dart';
import 'package:printing/printing.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:open_filex/open_filex.dart';
import 'allowed_time_management_screen.dart';
import 'profile_photo_service.dart';
import 'profile_photo_dialog.dart';
import '../main.dart'; // to access notificationPlugin


const String kBaseUrl = "http://192.168.29.119:5000";
//const String kBaseUrl = "http://10.20.55.59:5000";

class StudentLookupScreen extends StatefulWidget {
  final String selectedRole;
  final String selectedHostel;

  StudentLookupScreen({required this.selectedRole, required this.selectedHostel});

  @override
  _StudentLookupScreenState createState() => _StudentLookupScreenState();
}

class _StudentLookupScreenState extends State<StudentLookupScreen> with VoiceCommandMixin {
  final TextEditingController _rollNoController = TextEditingController();
  Map<String, dynamic>? _studentData;
  bool _isLoading = false;
  String _username = '';
  bool _accessDenied = false;
  String _deniedMessage = '';
  final LocalDBHelper _localDB = LocalDBHelper();
  final SyncService _syncService = SyncService();

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
    _setupAutoSync();
  }

  void _setupAutoSync() {
  // Auto-sync when connection is restored
  NetworkService().onConnectionChange.listen((isOnline) async {
    if (isOnline && mounted) {
      print('🔍 DEBUG: Connection restored, triggering auto-sync');
      final success = await _syncService.syncWithFeedback();
      
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ All offline records synced successfully!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
        
        // Only refresh student data if we're currently viewing a student
        if (_studentData != null && _rollNoController.text.isNotEmpty) {
          _getStudentData(); // Reload student data to show updated movement records
        }
        // Don't refresh if no student is being viewed - this prevents the "Please enter roll number" message
      }
    }
  });
  }



  @override
  Map<String, VoidCallback> getVoiceCommands() {
    Map<String, VoidCallback> commands = {
      'search student': _getStudentData,
      'find student': _getStudentData,
      'lookup student': _getStudentData,
      'scan qr': _scanQRCode,
      'scan code': _scanQRCode,
      'scan': _scanQRCode,
      'analytics': _navigateToAnalytics,
      'view analytics': _navigateToAnalytics,
      'ai analytics': _navigateToAIAnalytics,
      'ai insights': _navigateToAIAnalytics,
      'predictive analytics': _navigateToAIAnalytics,
      'logout': _logout,
      'sign out': _logout,
      'go back': () => Navigator.of(context).pop(),
      'help': _showVoiceHelpDialog,
      'clear': _clearSearch,
      'sync records': _manualSync,
      'generate pdf': _generateMovementLogsPDF,
      'export logs': _generateMovementLogsPDF,
      'create report': _generateMovementLogsPDF,
      'download movements': _generateMovementLogsPDF,
      'change profile photo': _showProfilePhotoDialog,
      'update profile': _showProfilePhotoDialog,
      'edit profile photo': _showProfilePhotoDialog,
    };

    if (widget.selectedRole.startsWith('super_')) {
      commands['weekly report'] = _navigateToWeeklyReport;
      commands['view report'] = _navigateToWeeklyReport;
    }

    if (widget.selectedRole == 'admin' && _studentData != null) {
      commands['manage time'] = _navigateToAllowedTimeManagement;
      commands['set allowed time'] = _navigateToAllowedTimeManagement;
      commands['edit time limit'] = _navigateToAllowedTimeManagement;
    }

    // Security specific commands
    if (widget.selectedRole.startsWith('security_')) {
      commands['check out'] = () => _performSecurityAction('out');
      commands['check in'] = () => _performSecurityAction('in');
      commands['student out'] = () => _performSecurityAction('out');
      commands['student in'] = () => _performSecurityAction('in');
    }

    return commands;
  }

  void _showVoiceHelpDialog() {
    showVoiceHelp();
  }

  void _manualSync() async {
  final success = await _syncService.syncWithFeedback();
  
  if (mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success ? 
          '✅ All records synced successfully!' : 
          '❌ Sync failed. Some records may still be pending.'),
        backgroundColor: success ? Colors.green : Colors.orange,
        duration: Duration(seconds: 3),
      ),
    );
    
    // Only refresh student data if we're currently viewing a student
    if (_studentData != null && _rollNoController.text.isNotEmpty) {
      _getStudentData();
    }
    // Don't refresh if no student is being viewed
  }
  }

  Future<void> _generateMovementLogsPDF() async {
    if (_studentData == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please search for a student first')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final movementRecords = _studentData!['in_out_records'] ?? [];

      if (movementRecords.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No movement records found for this student')),
        );
        return;
      }

      print('📊 Generating PDF for ${movementRecords.length} records...');

      // Generate PDF
      final pdfService = PDFReportService();
      final filePath = await pdfService.generateMovementLogsPDF(
        movementRecords: movementRecords,
        studentName: _studentData!['name'] ?? 'Unknown',
        rollNo: _studentData!['roll_no'] ?? 'N/A',
        hostel: _studentData!['hostel'] ?? 'N/A',
      );

      print('✅ PDF generated at: $filePath');

      // Show success dialog with options
      _showPDFSuccessDialog(filePath);

    } catch (e) {
      print('❌ PDF Generation Error: $e');
      
      // Show error dialog
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Row(
              children: [
                Icon(Icons.error, color: Colors.red),
                SizedBox(width: 10),
                Text('PDF Generation Failed'),
              ],
            ),
            content: Text('Error: $e\n\nPlease try again.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('OK'),
              ),
            ],
          );
        },
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> showDownloadCompleteNotification(String fileName, String path) async {
    final androidDetails = AndroidNotificationDetails(
      'download_channel',
      'Downloads',
      channelDescription: 'Notifies when a PDF file is saved',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      ticker: 'Download complete',
    );

    final notificationDetails =
        NotificationDetails(android: androidDetails);

    await notificationPlugin.show(
      0,
      'Download complete',
      fileName,
      notificationDetails,
      payload: path,
    );
  }



  Future<void> _downloadPDF(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('PDF not found');
      }

      // Downloads folder
      final downloadsDir = Directory('/storage/emulated/0/Download');
      if (!await downloadsDir.exists()) {
        await downloadsDir.create(recursive: true);
      }

      final fileName =
          'Student_Movement_${_studentData!['roll_no']}_${DateTime.now().millisecondsSinceEpoch}.pdf';

      final savedPath = '${downloadsDir.path}/$fileName';

      await file.copy(savedPath);

      // 🔔 Show notification
      await showDownloadCompleteNotification(fileName, savedPath);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('PDF saved to Downloads'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      print('❌ Download error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to download file'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }




  void _showPermissionDeniedDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.warning, color: Colors.orange),
              SizedBox(width: 10),
              Text('Permission Required'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Storage permission is required to download PDF files.'),
              SizedBox(height: 10),
              Text('Please grant the permission in app settings to enable downloads.'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                openAppSettings(); // Open app settings so user can grant permission
              },
              child: Text('Open Settings'),
            ),
          ],
        );
      },
    );
  }

  void _showPDFSuccessDialog(String filePath) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: EdgeInsets.all(20),
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 20,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Success Icon
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.green, width: 2),
                    ),
                    child: Icon(
                      Icons.check_circle,
                      color: Colors.green,
                      size: 40,
                    ),
                  ),
                  
                  SizedBox(height: 20),
                  
                  // Title
                  Text(
                    'PDF Generated Successfully!',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  
                  SizedBox(height: 12),
                  
                  // Description
                  Text(
                    'Your movement logs PDF has been generated and is ready to use.',
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  
                  SizedBox(height: 24),
                  
                  // Action Buttons - Fixed overflow by using Wrap or Column
                  LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth > 400) {
                        // Horizontal layout for wider screens
                        return Row(
                          children: [
                            Expanded(
                              child: _buildDialogButton(
                                icon: Icons.share,
                                text: 'Share',
                                color: Colors.blue,
                                onPressed: () {
                                  Navigator.of(context).pop();
                                  _sharePDF(filePath);
                                },
                              ),
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: _buildDialogButton(
                                icon: Icons.visibility,
                                text: 'View',
                                color: Colors.purple,
                                onPressed: () {
                                  Navigator.of(context).pop();
                                  _viewPDF(filePath);
                                },
                              ),
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: _buildDialogButton(
                                icon: Icons.download,
                                text: 'Download',
                                color: Colors.green,
                                onPressed: () {
                                  Navigator.of(context).pop();
                                  _downloadPDF(filePath);
                                },
                              ),
                            ),
                          ],
                        );
                      } else {
                        // Vertical layout for narrow screens
                        return Column(
                          children: [
                            _buildDialogButton(
                              icon: Icons.share,
                              text: 'Share PDF',
                              color: Colors.blue,
                              onPressed: () {
                                Navigator.of(context).pop();
                                _sharePDF(filePath);
                              },
                            ),
                            SizedBox(height: 12),
                            _buildDialogButton(
                              icon: Icons.visibility,
                              text: 'View PDF',
                              color: Colors.purple,
                              onPressed: () {
                                Navigator.of(context).pop();
                                _viewPDF(filePath);
                              },
                            ),
                            SizedBox(height: 12),
                            _buildDialogButton(
                              icon: Icons.download,
                              text: 'Download PDF',
                              color: Colors.green,
                              onPressed: () {
                                Navigator.of(context).pop();
                                _downloadPDF(filePath);
                              },
                            ),
                          ],
                        );
                      }
                    },
                  ),
                  
                  SizedBox(height: 16),
                  
                  // Close Button
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      'Close',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // Helper method for beautiful buttons
  Widget _buildDialogButton({
    required IconData icon,
    required String text,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        elevation: 2,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 20),
          SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _sharePDF(String filePath) async {
    try {
      final pdfService = PDFReportService();
      await pdfService.sharePDF(filePath);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error sharing PDF: $e')),
      );
    }
  }

  Future<void> _viewPDF(String filePath) async {
    try {
      final file = File(filePath);
      final bytes = await file.readAsBytes();
      
      await Printing.layoutPdf(
        onLayout: (format) async => bytes,
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error viewing PDF: $e')),
      );
    }
  }

  void _scanQRCode() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ScanScreen(
          role: widget.selectedRole,
          hostel: widget.selectedHostel,
          onStudentScanned: (studentData) {
            setState(() {
              _studentData = studentData;
              _accessDenied = false;
            });
          },
        ),
      ),
    );

    if (result == 'reset') {
      setState(() {
        _studentData = null;
        _rollNoController.clear();
      });
    }
  }

  void _clearSearch() {
    setState(() {
      _studentData = null;
      _rollNoController.clear();
      _accessDenied = false;
    });
  }

  void _showVoiceHelp() {
    String commands = 'Available commands: "search student", "scan qr", "analytics", "ai analytics", "logout", "go back", "help", "clear", "sync records", "generate pdf", "dark theme", "light theme", "toggle theme"';
    
    if (widget.selectedRole.startsWith('super_')) {
      commands += ', "weekly report"';
    }

    if (widget.selectedRole.startsWith('security_')) {
      commands += ', "check in", "check out"';
    }
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(commands),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  Future<void> _loadUserInfo() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _username = prefs.getString('username') ?? '';
    });
  }

  Future<void> _getStudentData() async {
    if (_rollNoController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please enter roll number')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _studentData = null;
      _accessDenied = false;
      _deniedMessage = '';
    });

    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? token = prefs.getString('access_token');
      String? deviceId = prefs.getString('device_id');

      final response = await http.get(
        Uri.parse('$kBaseUrl/api/student/${_rollNoController.text}/${widget.selectedRole}'),
        headers: {
          'Authorization': 'Bearer $token',
          'Device-Id': deviceId ?? '',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _studentData = data;
          _accessDenied = false;
        });
      } else if (response.statusCode == 404) {
        // Student not found - show beautiful UI
        setState(() {
          _studentData = {'not_found': true, 'roll_no': _rollNoController.text};
        });
      } else if (response.statusCode == 403) {
        final errorData = json.decode(response.body);
        setState(() {
          _accessDenied = true;
          _deniedMessage = errorData['message'] ?? 'Access denied';
          _studentData = errorData;
        });
      } else {
        // Handle other errors with proper UI
        if (response.statusCode == 404) {
          setState(() {
            _studentData = {'not_found': true, 'roll_no': _rollNoController.text};
          });
        } else {
          String errorMessage = 'Unknown error';
          try {
            final errorData = json.decode(response.body);
            errorMessage = errorData['message'] ?? errorData['msg'] ?? 'Request failed';
          } catch (e) {
            errorMessage = 'Failed to load student data';
          }
          
          // Show error in the UI instead of snackbar
          setState(() {
            _studentData = {'error': true, 'error_message': errorMessage};
          });
        }
      }
    } catch (e) {
      // Show error in the UI instead of snackbar
      setState(() {
        _studentData = {'error': true, 'error_message': 'Network error: $e'};
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return buildVoiceCommandUI(
      Scaffold(
        appBar: AppBar(
          title: Text('${widget.selectedRole.toUpperCase()} - Hostel ${widget.selectedHostel}'),
          backgroundColor: AppThemes.getRoleColor(widget.selectedRole.split('_')[0], context),
          actions: [
            // Voice command button
            buildVoiceCommandButton(),

            // Sync button
            IconButton(
              icon: Icon(Icons.sync),
              onPressed: _manualSync,
              tooltip: 'Sync Offline Records',
            ),

            // Theme toggle
            ThemeToggleWidget(),

            // Keep only the most important icon visible, put others in menu
            if (widget.selectedRole == 'admin' || widget.selectedRole.startsWith('super_'))
              IconButton(
                icon: Icon(Icons.analytics),
                onPressed: _navigateToAnalytics,
                tooltip: 'View Analytics',
              ),

            // Overflow menu for additional options
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert),
              onSelected: (value) {
                _handleMenuSelection(value);
              },
              itemBuilder: (BuildContext context) => _buildPopupMenuItems(),
            ),
          ],
        ),
        body: Column(
          children: [
            _buildHeaderSection(),
            Expanded(
              child: _buildContentSection(),
            ),
          ],
        ),
      ),
    );
  }

  List<PopupMenuEntry<String>> _buildPopupMenuItems() {
    final List<PopupMenuEntry<String>> menuItems = [];

    // In _buildPopupMenuItems method, add this for admin only:
    if (widget.selectedRole == 'admin' && _studentData != null) {
      menuItems.add(PopupMenuItem<String>(
        value: 'manage_allowed_time',
        child: Row(
          children: [
            Icon(Icons.timer, color: Colors.blue),
            SizedBox(width: 8),
            Text('Manage Allowed Time'),
          ],
        ),
      ));
      menuItems.add(PopupMenuDivider());
    }

    // PDF Generation option
    if ((widget.selectedRole == 'admin' || widget.selectedRole.startsWith('super_')) && 
        _studentData != null && 
        _studentData!['in_out_records'] != null && 
        _studentData!['in_out_records'].length > 0) {
      menuItems.add(PopupMenuItem<String>(
        value: 'generate_pdf',
        child: Row(
          children: [
            Icon(Icons.picture_as_pdf, color: Colors.red),
            SizedBox(width: 8),
            Text('Generate PDF Report'),
          ],
        ),
      ));
    }

    // AI Analytics for admin/super  
    if (widget.selectedRole == 'admin' || widget.selectedRole.startsWith('super_')) {
      menuItems.add(PopupMenuItem<String>(
        value: 'ai_analytics',
        child: Row(
          children: [
            Icon(Icons.psychology, color: Colors.purple),
            SizedBox(width: 8),
            Text('AI Insights'),
          ],
        ),
      ));
    }

    // Weekly Report for super
    if (widget.selectedRole.startsWith('super_')) {
      menuItems.add(PopupMenuItem<String>(
        value: 'weekly_report',
        child: Row(
          children: [
            Icon(Icons.report, color: Colors.orange),
            SizedBox(width: 8),
            Text('Weekly Report'),
          ],
        ),
      ));
    }

    // Add divider before logout if there are other items
    if (menuItems.isNotEmpty) {
      menuItems.add(PopupMenuDivider());
    }

    // Logout button
    menuItems.add(PopupMenuItem<String>(
      value: 'logout',
      child: Row(
        children: [
          Icon(Icons.logout, color: Colors.red),
          SizedBox(width: 8),
          Text('Logout'),
        ],
      ),
    ));

    return menuItems;
  }

  void _handleMenuSelection(String value) {
    switch (value) {
      case 'generate_pdf':
        _generateMovementLogsPDF();
        break;
      case 'ai_analytics':
        _navigateToAIAnalytics();
        break;
      case 'manage_allowed_time': 
        _navigateToAllowedTimeManagement();
        break;
      case 'weekly_report':
        _navigateToWeeklyReport();
        break;
      case 'logout':
        _logout();
        break;
    }
  }

  // Database debug methods
  void _resetDatabase() async {
    await _localDB.resetDatabase();
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Database reset successfully'),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _debugDatabaseContents() async {
    final pendingScans = await _localDB.getPendingSecurityScans();
    final pendingVisits = await _localDB.getPendingCanteenVisits();
    final totalPending = await _localDB.getPendingRecordsCount();
    
    print('🔍 DEBUG: Database Contents:');
    print('🔍 DEBUG: Total pending records: $totalPending');
    print('🔍 DEBUG: Pending scans: ${pendingScans.length}');
    
    for (var scan in pendingScans) {
      print('  - ID: ${scan['id']}, Roll: ${scan['roll_no']}, Action: ${scan['action']}, Synced: ${scan['is_synced']}');
    }
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('DB Check: $totalPending pending records'),
        duration: Duration(seconds: 3),
      ),
    );
  }

  void _navigateToAnalytics() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => MonthlyAnalyticsScreen(
        userRole: widget.selectedRole,
        userHostel: widget.selectedHostel,
      )),
    );
  }

  void _navigateToAIAnalytics() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => PredictiveAnalyticsScreen(
        userRole: widget.selectedRole,
        userHostel: widget.selectedHostel,
      )),
    );
  }

  void _navigateToWeeklyReport() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => WeeklyReportScreen()),
    );
  }

  void _navigateToAllowedTimeManagement() {
    if (_studentData == null) return;
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AllowedTimeManagementScreen(
          rollNo: _studentData!['roll_no'], // Pass the current student's roll number
          studentName: _studentData!['name'] ?? 'Unknown', // Optional: pass name for better UX
        ),
      ),
    );
  }


  void _showProfilePhotoDialog() {
    showDialog(
      context: context,
      builder: (context) => ProfilePhotoDialog(
        userRole: widget.selectedRole, // Pass the current role
        onPhotoUpdated: () {
          // Trigger UI refresh
          setState(() {});
        },
      ),
    );
  }

  Widget _buildHeaderSection() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.blue[700]!, Colors.blue[500]!],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Profile Photo - Always Visible with StreamBuilder
                GestureDetector(
                  onTap: _showProfilePhotoDialog,
                  child: StreamBuilder<Widget>(
                    stream: ProfilePhotoService().getProfilePhotoWidgetStream(
                      role: widget.selectedRole,
                      size: 50,
                      backgroundColor: Colors.white.withOpacity(0.3),
                    ),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.3),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: Center(
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          ),
                        );
                      }

                      if (snapshot.hasError) {
                        return _buildDefaultHeaderPhoto();
                      }

                      return Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black26,
                              blurRadius: 6,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: snapshot.data ?? _buildDefaultHeaderPhoto(),
                        ),
                      );
                    },
                  ),
                ),

                SizedBox(width: 12),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Logged in as: $_username',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        '${widget.selectedRole.toUpperCase()} • Hostel ${widget.selectedHostel.toUpperCase()}',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            SizedBox(height: 20),

            // Search + QR Code Section
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _rollNoController,
                            decoration: InputDecoration(
                              labelText: 'Enter Roll Number',
                              prefixIcon: Icon(Icons.search, color: Colors.blue),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide.none,
                              ),
                              filled: true,
                              fillColor: Theme.of(context).colorScheme.surface,
                              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              labelStyle: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                              ),
                            ),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ),
                        SizedBox(width: 12),
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Colors.green[500]!, Colors.green[400]!],
                            ),
                            borderRadius: BorderRadius.circular(50),
                          ),
                          child: IconButton(
                            onPressed: _getStudentData,
                            icon: Icon(Icons.search, color: Colors.white, size: 24),
                            padding: EdgeInsets.all(12),
                          ),
                        ),
                      ],
                    ),

                    SizedBox(height: 12),

                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.purple[500]!, Colors.purple[400]!],
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: TextButton.icon(
                        onPressed: _scanQRCode,
                        icon: Icon(Icons.qr_code_scanner, color: Colors.white),
                        label: Text(
                          'Scan QR Code',
                          style: TextStyle(color: Colors.white, fontSize: 16),
                        ),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }


  // Add this helper method (only one version)
  Widget _buildDefaultHeaderPhoto() {
    // Show role-specific default icon
    IconData icon;
    Color iconColor;
    
    switch (widget.selectedRole.toLowerCase()) {
      case 'admin':
        icon = Icons.admin_panel_settings;
        iconColor = Colors.red;
        break;
      case 'super_a':
      case 'super_b':
      case 'super_c':
      case 'super_d':
        icon = Icons.supervisor_account;
        iconColor = Colors.orange;
        break;
      case 'security_a':
      case 'security_b':
      case 'security_c':
      case 'security_d':
        icon = Icons.security;
        iconColor = Colors.blue;
        break;
      case 'canteen_a':
      case 'canteen_b':
      case 'canteen_c':
      case 'canteen_d':
        icon = Icons.restaurant;
        iconColor = Colors.green;
        break;
      default:
        icon = Icons.person;
        iconColor = Colors.white;
    }
    
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.3),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Icon(
          icon,
          color: iconColor,
          size: 28,
        ),
      ),
    );
  }



  Widget _buildContentSection() {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(strokeWidth: 3, valueColor: AlwaysStoppedAnimation(Colors.blue)),
            SizedBox(height: 16),
            Text('Loading student data...', 
                 style: TextStyle(fontSize: 16, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7))),
          ],
        ),
      );
    }

    if (_studentData != null && _studentData!['not_found'] == true) {
      return _buildStudentNotFoundView();
    }

    if (_studentData != null && _studentData!['error'] == true) {
      return _buildErrorView();
    }

    if (_accessDenied) {
      return _buildAccessDeniedView();
    }

    if (_studentData == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_search, size: 80, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3)),
            SizedBox(height: 16),
            Text(
              'Enter roll number to search student',
              style: TextStyle(
                fontSize: 18, 
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7), 
                fontWeight: FontWeight.w500
              ),
            ),
            SizedBox(height: 8),
            Text(
              'or use QR code scanner',
              style: TextStyle(
                fontSize: 14, 
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5)
              ),
            ),
          ],
        ),
      );
    }

    String mainRole = widget.selectedRole.split('_')[0];

    // For Security and Canteen roles with same-hostel students, show simplified view
    if ((mainRole == 'security' || mainRole == 'canteen') && 
        _studentData!['belongs_to_hostel'] == true) {
      return _buildSimpleVerificationView();
    }

    // For access denied or different hostel
    if ((mainRole == 'security' || mainRole == 'canteen') && 
        _studentData!['belongs_to_hostel'] == false) {
      return _buildAccessDeniedView();
    }

    // For admin, super, and other cases - show detailed view
    return SingleChildScrollView(
      padding: EdgeInsets.all(20.0),
      child: Column(
        children: [
          _buildStudentBasicInfo(),
          SizedBox(height: 20),
          ..._buildStudentDetailsList(),
        ],
      ),
    );
  } 

  Widget _buildStudentNotFoundView() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.person_off, size: 60, color: Colors.orange),
          ),
          SizedBox(height: 24),
          Text(
            'Student Not Found',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.orange[800]),
          ),
          SizedBox(height: 16),
          Container(
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.orange[50]!,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange[200]!),
            ),
            child: Column(
              children: [
                Icon(Icons.search_off, size: 48, color: Colors.orange),
                SizedBox(height: 16),
                Text(
                  'No student found with Roll Number:',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.orange[800],
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  _rollNoController.text,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange[900],
                    fontFamily: 'monospace',
                  ),
                ),
                SizedBox(height: 12),
                Text(
                  'Please check the roll number and try again',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.orange[700],
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () {
              setState(() {
                _studentData = null;
                _rollNoController.clear();
              });
            },
            icon: Icon(Icons.refresh),
            label: Text('Search Again'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.error_outline, size: 60, color: Colors.red),
          ),
          SizedBox(height: 24),
          Text(
            'Unable to Load Data',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.red[800]),
          ),
          SizedBox(height: 16),
          Container(
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.red[50]!,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red[200]!),
            ),
            child: Column(
              children: [
                Icon(Icons.warning_amber, size: 48, color: Colors.red),
                SizedBox(height: 16),
                Text(
                  _studentData!['error_message'] ?? 'An error occurred while loading student data',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.red[800],
                  ),
                ),
                SizedBox(height: 12),
                Text(
                  'Please check the roll number and try again',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.red[700],
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () {
              setState(() {
                _studentData = null;
                _rollNoController.clear();
              });
            },
            icon: Icon(Icons.refresh),
            label: Text('Try Again'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSimpleVerificationView() {
    String mainRole = widget.selectedRole.split('_')[0];

    return SingleChildScrollView(
      padding: EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.verified, size: 60, color: Colors.green),
          ),
          SizedBox(height: 24),
          Text(
            'Student Verified',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.green[800]),
          ),
          SizedBox(height: 16),
          Container(
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green[200]!),
            ),
            child: Column(
              children: [
                Icon(Icons.check_circle, size: 48, color: Colors.green),
                SizedBox(height: 16),
                Text(
                  'This student belongs to your hostel',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                SizedBox(height: 12),
                Text(
                  'Access granted for ${mainRole} operations',
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 16),
                Divider(),
                SizedBox(height: 16),
                // Show minimal essential info - FIXED TEXT COLORS
                Text(
                  'Student: ${_studentData!['name'] ?? 'Unknown'}',
                  style: TextStyle(
                    fontSize: 16, 
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Roll No: ${_studentData!['roll_no'] ?? 'N/A'}',
                  style: TextStyle(
                    fontSize: 14, 
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7)
                  ),
                ),
                Text(
                  'Hostel: ${_studentData!['hostel'] ?? 'N/A'}',
                  style: TextStyle(
                    fontSize: 14, 
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7)
                  ),
                ),
              ],
            ),
          ),

          // Add security actions if security role
          if (mainRole == 'security') ...[
            SizedBox(height: 20),
            _buildSecurityActions(),
          ],

          SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () {
              setState(() {
                _studentData = null;
                _rollNoController.clear();
              });
            },
            icon: Icon(Icons.refresh),
            label: Text('Check Another Student'),
          ),
        ],
      ),
    );
  }

  Widget _buildAccessDeniedView() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.block, size: 50, color: Colors.red),
          ),
          SizedBox(height: 24),
          Text(
            'Access Denied',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.red[800]),
          ),
          SizedBox(height: 16),
          Container(
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.red[50]!,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red[200]!),
            ),
            child: Column(
              children: [
                Icon(Icons.warning_amber, size: 40, color: Colors.red),
                SizedBox(height: 12),
                Text(
                  _deniedMessage,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.red[800]),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 8),
                if (_studentData != null) ...[
                  Text(
                    'Student Hostel: ${_studentData!['student_hostel'] ?? 'Unknown'}',
                    style: TextStyle(color: Colors.red[700]),
                  ),
                  Text(
                    'Your Hostel: ${_studentData!['user_hostel'] ?? widget.selectedHostel}',
                    style: TextStyle(color: Colors.red[700]),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () {
              setState(() {
                _studentData = null;
                _accessDenied = false;
                _rollNoController.clear();
              });
            },
            icon: Icon(Icons.refresh),
            label: Text('Search Another Student'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
          ),
          SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildSecurityActions() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text(
              'Security Actions',
              style: TextStyle(
                fontSize: 18, 
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _performSecurityAction('out'),
                    icon: Icon(Icons.exit_to_app, color: Colors.white),
                    label: Text('Check Out', style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      padding: EdgeInsets.symmetric(vertical: 15),
                    ),
                  ),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _performSecurityAction('in'),
                    icon: Icon(Icons.login, color: Colors.white),
                    label: Text('Check In', style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: EdgeInsets.symmetric(vertical: 15),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // UPDATED SECURITY ACTION METHOD WITH OFFLINE SYNC
  Future<void> _performSecurityAction(String action) async {
    try {
      final networkService = NetworkService();
      final isOnline = await networkService.isConnected();

      if (!isOnline) {
        // Save locally when offline
        await _localDB.saveSecurityScan(
          rollNo: _studentData!['roll_no'],
          action: action,
          role: widget.selectedRole,
          timestamp: DateTime.now(),
        );
        
        _showActionResultDialog(
          true, 
          'Saved Offline', 
          '${action == 'out' ? 'Check Out' : 'Check In'} saved locally.\nWill sync automatically when online.'
        );
        return;
      }

      // Online logic
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? token = prefs.getString('access_token');
      String? deviceId = prefs.getString('device_id');

      final response = await http.post(
        Uri.parse('$kBaseUrl/api/student/scan/security/${widget.selectedRole}'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
          'Device-Id': deviceId ?? '',
        },
        body: json.encode({
          'roll_no': _studentData!['roll_no'],
          'action': action,
        }),
      );

      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        _showActionResultDialog(
          true,
          'Success',
          '${action == 'out' ? 'Check out' : 'Check in'} successful!\n'
          'Time: ${_formatDateTimeForDisplay(result['time'])}\n'
          'Time spent: ${_formatDuration(result['time_spent_minutes'] ?? 'N/A')}',
        );
        
        // Refresh student data to show updated movement records
        _getStudentData();
      } else {
        // Network error - fallback to local save
        final errorData = json.decode(response.body);
        String errorMessage = errorData['message'] ?? 'Action failed';

        // Improved error messages for specific cases
        if (errorMessage.contains('No active check out record found')) {
          errorMessage = 'Student is not checked out. Please check out first.';
        } else if (errorMessage.contains('already checked out')) {
          errorMessage = 'Student is already checked out.';
        } else if (errorMessage.contains('Access denied')) {
          errorMessage = 'Access denied to this student.';
        }

        // Save locally as fallback
        await _localDB.saveSecurityScan(
          rollNo: _studentData!['roll_no'],
          action: action,
          role: widget.selectedRole,
          timestamp: DateTime.now(),
        );
        
        _showActionResultDialog(
          true, 
          'Saved Offline', 
          'Network issue. Action saved locally.\nWill sync when online.\nError: $errorMessage'
        );
      }
    } catch (e) {
      // Any error - fallback to local save
      await _localDB.saveSecurityScan(
        rollNo: _studentData!['roll_no'],
        action: action,
        role: widget.selectedRole,
        timestamp: DateTime.now(),
      );
      
      _showActionResultDialog(
        true, 
        'Saved Offline', 
        'Action saved locally due to error.\nWill sync when online.\nError: $e'
      );
    }
  }

  void _showActionResultDialog(bool success, String title, String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Icon Container
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: success ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    success ? Icons.check_circle : Icons.warning_amber,
                    size: 40,
                    color: success ? Colors.green : Colors.orange,
                  ),
                ),
                
                SizedBox(height: 20),
                
                // Title
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: success ? Colors.green[800] : Colors.orange[800],
                  ),
                ),
                
                SizedBox(height: 12),
                
                // Message
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
                  ),
                ),
                
                SizedBox(height: 20),
                
                // Action Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: success ? Colors.green : Colors.orange,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(
                      'OK',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStudentBasicInfo() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Theme.of(context).colorScheme.primary.withOpacity(0.1),
            Theme.of(context).colorScheme.secondary.withOpacity(0.1)
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(24.0),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [Colors.blue[500]!, Colors.purple[500]!],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(Icons.person, color: Colors.white, size: 32),
                ),
                SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _studentData!['name']?.toString() ?? 'Unknown',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      SizedBox(height: 6),
                      _buildInfoChip(Icons.badge, 'Roll No: ${_studentData!['roll_no']?.toString() ?? 'N/A'}', Colors.blue),
                      SizedBox(height: 4),
                      _buildInfoChip(Icons.home, 'Hostel: ${_studentData!['hostel']?.toString() ?? 'N/A'}', Colors.green),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String text, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: color),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildStudentDetailsList() {
    List<Widget> widgets = [];
    String mainRole = widget.selectedRole.split('_')[0];
    
    widgets.add(_buildSectionCard(
      title: 'Basic Information',
      icon: Icons.info_outline,
      iconColor: Colors.blue,
      children: [
        _buildInfoItemWithIcon(Icons.meeting_room, 'Room Number', _studentData!['room_no']?.toString()),
        _buildInfoItemWithIcon(Icons.school, 'Course', _studentData!['course']?.toString()),
        _buildInfoItemWithIcon(Icons.calendar_today, 'Academic Year', _studentData!['academic_year']?.toString()),
        _buildInfoItemWithIcon(Icons.business_center, 'Branch', _studentData!['branch']?.toString()),
      ],
    ));
    
    if (mainRole == 'super' || mainRole == 'admin') {
      widgets.add(_buildSectionCard(
        title: 'Contact Information',
        icon: Icons.contact_phone,
        iconColor: Colors.green,
        children: [
          _buildInfoItemWithIcon(Icons.phone, 'Contact Number', _studentData!['contact_no']?.toString()),
          if (mainRole == 'admin') ...[
            _buildInfoItemWithIcon(Icons.email, 'Email Address', _studentData!['email']?.toString()),
            _buildInfoItemWithIcon(Icons.family_restroom, 'Guardian Name', _studentData!['guardian_name']?.toString()),
            _buildInfoItemWithIcon(Icons.phone_android, 'Guardian Phone', _studentData!['guardian_phone']?.toString()),
          ],
        ],
      ));
    }
    
    if (mainRole == 'admin') {
      widgets.add(_buildSectionCard(
        title: 'Administrative Information',
        icon: Icons.admin_panel_settings,
        iconColor: Colors.purple,
        children: [
          _buildInfoItemWithIcon(Icons.home_work, 'Home Address', _studentData!['home_address']?.toString()),
          _buildInfoItemWithIcon(Icons.payment, 'Fee Status', _studentData!['fee_status']?.toString()),
          // In the _buildStudentDetailsList method, update the admission date line:
          _buildInfoItemWithIcon(Icons.date_range, 'Admission Date',_formatDate(_studentData!['admission_date'])?.toString()),
        ],
      ));
    }
    
    if ((mainRole == 'admin' || mainRole == 'super') && 
        _studentData!['in_out_records'] != null && 
        _studentData!['in_out_records'].length > 0) {
      widgets.add(_buildInOutRecordsSection());
    }
    
    if ((mainRole == 'admin' || mainRole == 'super') && 
        _studentData!['disciplinary_records'] != null && 
        _studentData!['disciplinary_records'].length > 0) {
      widgets.add(_buildDisciplinaryRecordsSection());
    }
    
    if ((mainRole == 'admin' || mainRole == 'super') && 
        _studentData!['medical_info'] != null && 
        _studentData!['medical_info'].length > 0) {
      widgets.add(_buildMedicalInformationSection());
    }
    
    return widgets;
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required Color iconColor,
    required List<Widget> children,
  }) {
    return Container(
      margin: EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [iconColor.withOpacity(0.8), iconColor],
              ),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: Colors.white, size: 24),
                ),
                SizedBox(width: 12),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.all(20),
            child: Column(children: children),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItemWithIcon(IconData icon, String label, String? value) {
    if (value == null || value.isEmpty) return SizedBox.shrink();
    
    return Container(
      margin: EdgeInsets.only(bottom: 16),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.blue, size: 20),
          ),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                    letterSpacing: 0.5,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInOutRecordsSection() {
    List<dynamic> records = _studentData!['in_out_records'];
    
    return _buildSectionCard(
      title: 'Movement Records',
      icon: Icons.directions_walk,
      iconColor: Colors.orange,
      children: [
        ...records.reversed.take(5).map<Widget>((record) => _buildInOutRecordItem(record)).toList(),
      ],
    );
  }

  Widget _buildInOutRecordItem(Map<String, dynamic> record) {
    bool isCheckedOut = record['action'] == 'out';
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      margin: EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isCheckedOut 
              ? [
                  isDark ? Colors.orange[900]!.withOpacity(0.3) : Colors.orange[50]!,
                  isDark ? Colors.orange[800]!.withOpacity(0.2) : Colors.orange[100]!,
                ]
              : [
                  isDark ? Colors.green[900]!.withOpacity(0.3) : Colors.green[50]!,
                  isDark ? Colors.green[800]!.withOpacity(0.2) : Colors.green[100]!,
                ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCheckedOut 
              ? (isDark ? Colors.orange[700]! : Colors.orange[200]!)
              : (isDark ? Colors.green[700]! : Colors.green[200]!),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isCheckedOut ? Colors.orange : Colors.green,
              shape: BoxShape.circle,
            ),
            child: Icon(
              isCheckedOut ? Icons.exit_to_app : Icons.login,
              color: Colors.white,
              size: 18,
            ),
          ),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isCheckedOut ? 'CHECKED OUT' : 'CHECKED IN',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isCheckedOut 
                        ? (isDark ? Colors.orange[300]! : Colors.orange[800])
                        : (isDark ? Colors.green[300]! : Colors.green[800]),
                    letterSpacing: 0.5,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Out: ${_formatDateTime(record['out_time'])}',
                  style: TextStyle(
                    fontSize: 14, 
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7)
                  ),
                ),
                if (record['in_time'] != null)
                  Text(
                    'In: ${_formatDateTime(record['in_time'])}',
                    style: TextStyle(
                      fontSize: 14, 
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7)
                    ),
                  ),
                if (record['time_spent_minutes'] != null)
                  Text(
                    'Duration: ${_formatDuration(record['time_spent_minutes'])}',
                    style: TextStyle(
                      fontSize: 14, 
                      fontWeight: FontWeight.bold, 
                      color: isDark ? Colors.blue[300]! : Colors.blue[700]
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDisciplinaryRecordsSection() {
    List<dynamic> records = _studentData!['disciplinary_records'];
    
    return _buildSectionCard(
      title: 'Disciplinary Records',
      icon: Icons.warning_amber,
      iconColor: Colors.red,
      children: [
        Text(
          'Total Records: ${records.length}',
          style: TextStyle(
            fontSize: 14, 
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6), 
            fontStyle: FontStyle.italic
          ),
        ),
        SizedBox(height: 16),
        ...records.map<Widget>((record) => _buildDisciplinaryRecordItem(record)).toList(),
      ],
    );
  }

  Widget _buildDisciplinaryRecordItem(Map<String, dynamic> record) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      margin: EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isDark ? Colors.red[900]!.withOpacity(0.2) : Colors.red[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? Colors.red[700]! : Colors.red[200]!),
      ),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // FIXED: Use Column instead of Row to prevent overflow
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.calendar_today, size: 16, color: isDark ? Colors.red[300]! : Colors.red[600]),
                    SizedBox(width: 8),
                    Text(
                      _formatDate(record['date']) ?? 'Unknown Date',
                      style: TextStyle(
                        fontWeight: FontWeight.bold, 
                        color: isDark ? Colors.red[300]! : Colors.red[800]
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.access_time, size: 16, color: isDark ? Colors.red[300]! : Colors.red[600]),
                    SizedBox(width: 4),
                    Text(
                      record['time']?.toString() ?? 'Unknown Time',
                      style: TextStyle(
                        color: isDark ? Colors.red[300]! : Colors.red[700], 
                        fontSize: 12
                      ),
                    ),
                  ],
                ),
              ],
            ),
            SizedBox(height: 12),

            // Description with flexible text
            _buildRecordDetailItem(
              Icons.description,
              'Description',
              record['description'] ?? 'No description provided',
              isDark ? Colors.red[300]! : Colors.red[600]!,
            ),

            // Action Taken
            if (record['action_taken'] != null)
              _buildRecordDetailItem(
                Icons.gavel,
                'Action Taken',
                record['action_taken']!,
                isDark ? Colors.orange[300]! : Colors.orange[600]!,
              ),

            // Recorded By
            if (record['recorded_by'] != null)
              _buildRecordDetailItem(
                Icons.person,
                'Recorded By',
                record['recorded_by']!,
                isDark ? Colors.blue[300]! : Colors.blue[600]!,
              ),

            // Time Exceeded (if applicable)
            if (record['time_exceeded_minutes'] != null)
              _buildRecordDetailItem(
                Icons.timer,
                'Time Exceeded',
                '${_formatDuration(record['time_exceeded_minutes'])}',
                isDark ? Colors.purple[300]! : Colors.purple[600]!,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMedicalInformationSection() {
    List<dynamic> medicalInfo = _studentData!['medical_info'];
    
    return _buildSectionCard(
      title: 'Medical Information',
      icon: Icons.medical_services,
      iconColor: Colors.teal,
      children: [
        Text(
          'Medical Records: ${medicalInfo.length}',
          style: TextStyle(
            fontSize: 14, 
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6), 
            fontStyle: FontStyle.italic
          ),
        ),
        SizedBox(height: 16),
        ...medicalInfo.map<Widget>((info) => _buildMedicalInfoItem(info)).toList(),
      ],
    );
  }

  Widget _buildMedicalInfoItem(Map<String, dynamic> info) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      margin: EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isDark ? Colors.teal[900]!.withOpacity(0.2) : Colors.teal[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? Colors.teal[700]! : Colors.teal[200]!),
      ),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.medical_services, size: 20, color: isDark ? Colors.teal[300]! : Colors.teal[600]),
                SizedBox(width: 8),
                Text(
                  'Medical Record',
                  style: TextStyle(
                    fontSize: 16, 
                    fontWeight: FontWeight.bold, 
                    color: isDark ? Colors.teal[300]! : Colors.teal[800]
                  ),
                ),
              ],
            ),
            SizedBox(height: 12),
            if (info['allergies'] != null && info['allergies'].isNotEmpty)
              _buildMedicalDetailItem(
                Icons.warning,
                'Allergies & Conditions',
                info['allergies']!,
                isDark ? Colors.red[300]! : Colors.red[400]!,
              ),
            if (info['medication'] != null && info['medication'].isNotEmpty)
              _buildMedicalDetailItem(
                Icons.medication,
                'Current Medication',
                info['medication']!,
                isDark ? Colors.blue[300]! : Colors.blue[400]!,
              ),
            if (info['emergency_contact'] != null && info['emergency_contact'].isNotEmpty)
              _buildMedicalDetailItem(
                Icons.emergency,
                'Emergency Contact',
                info['emergency_contact']!,
                isDark ? Colors.orange[300]! : Colors.orange[400]!,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordDetailItem(IconData icon, String label, String value, Color color) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: color,
                    letterSpacing: 0.5,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14, 
                    color: Theme.of(context).colorScheme.onSurface
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMedicalDetailItem(IconData icon, String label, String value, Color color) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      margin: EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.black.withOpacity(0.3) : Colors.white.withOpacity(0.7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withOpacity(isDark ? 0.2 : 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14, 
                    color: Theme.of(context).colorScheme.onSurface
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(dynamic dateTime) {
    if (dateTime == null) return 'N/A';

    try {
      // Handle MongoDB date format: {"$date": "2024-01-15T00:00:00Z"}
      if (dateTime is Map<String, dynamic> && dateTime.containsKey('\$date')) {
        String dateString = dateTime['\$date'];
        DateTime date = DateTime.parse(dateString);
        return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
      }

      // Handle string dates
      if (dateTime is String) {
        if (dateTime.contains('T')) {
          DateTime date = DateTime.parse(dateTime);
          return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
        }
        return dateTime; // Return as-is if it's already formatted
      }

      // Handle DateTime objects
      if (dateTime is DateTime) {
        return '${dateTime.day.toString().padLeft(2, '0')}/${dateTime.month.toString().padLeft(2, '0')}/${dateTime.year} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
      }

      return dateTime.toString();
    } catch (e) {
      return dateTime.toString();
    }
  }

  // ADD THE NEW METHOD RIGHT AFTER THE EXISTING _formatDateTime METHOD:
  String _formatDateTimeForDisplay(dynamic dateTime) {
  if (dateTime == null) return 'N/A';

  try {
    // Handle string dates like "2025-10-11T10:53:39.228533"
    if (dateTime is String) {
      DateTime date = DateTime.parse(dateTime);
      return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    }

    // Handle MongoDB date format
    if (dateTime is Map<String, dynamic> && dateTime.containsKey('\$date')) {
      String dateString = dateTime['\$date'];
      DateTime date = DateTime.parse(dateString);
      return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    }

    // Handle DateTime objects
    if (dateTime is DateTime) {
      return '${dateTime.day.toString().padLeft(2, '0')}/${dateTime.month.toString().padLeft(2, '0')}/${dateTime.year} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    }

    return dateTime.toString();
  } catch (e) {
    return 'Invalid Date';
  }
  }

  String _formatDate(dynamic dateValue) {
    if (dateValue == null) return 'N/A';

    try {
      // Handle MongoDB date format: {"$date": "2024-01-15T00:00:00Z"}
      if (dateValue is Map<String, dynamic> && dateValue.containsKey('\$date')) {
        String dateString = dateValue['\$date'];
        DateTime date = DateTime.parse(dateString);
        return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
      }

      // Handle string dates
      if (dateValue is String) {
        if (dateValue.contains('T')) {
          DateTime date = DateTime.parse(dateValue);
          return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
        }
        // If it's already just a date string, return as-is
        return dateValue.length > 10 ? dateValue.substring(0, 10) : dateValue;
      }

      // Handle DateTime objects
      if (dateValue is DateTime) {
        return '${dateValue.day.toString().padLeft(2, '0')}/${dateValue.month.toString().padLeft(2, '0')}/${dateValue.year}';
      }

      return dateValue.toString();
    } catch (e) {
      return dateValue.toString();
    }
  }

  String _formatDuration(dynamic duration) {
    if (duration == null) return 'N/A';

    try {
      double minutes = duration is double ? duration : double.tryParse(duration.toString()) ?? 0.0;

      // Format to 4 decimal places
      String formatted = minutes.toStringAsFixed(4);

      // Remove trailing zeros and decimal point if not needed
      if (formatted.contains('.')) {
        formatted = formatted.replaceAll(RegExp(r'0*$'), ''); // Remove trailing zeros
        if (formatted.endsWith('.')) {
          formatted = formatted.substring(0, formatted.length - 1); // Remove trailing decimal
        }
      }

      return '$formatted minutes';
    } catch (e) {
      return duration.toString();
    }
  }

  Future<void> _logout() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
    await prefs.remove('current_role');
    await prefs.remove('current_hostel');
    await prefs.remove('username');
    
    Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
  }

  @override
  Map<String, String> getVoiceCommandDescriptions() {
    Map<String, String> descriptions = {
      'search student': 'Search for student by roll number',
      'find student': 'Search for student by roll number',
      'lookup student': 'Search for student by roll number',
      'scan qr': 'Open QR code scanner',
      'scan code': 'Open QR code scanner',
      'scan': 'Open QR code scanner',
      'analytics': 'View monthly analytics (Admin/Super only)',
      'view analytics': 'View monthly analytics (Admin/Super only)',
      'ai analytics': 'View AI predictive analytics (Admin/Super only)',
      'ai insights': 'View AI predictive analytics (Admin/Super only)',
      'predictive analytics': 'View AI predictive analytics (Admin/Super only)',
      'logout': 'Log out of the application',
      'sign out': 'Log out of the application',
      'go back': 'Return to previous screen',
      'help': 'Show this help dialog',
      'clear': 'Clear current search results',
      'sync records': 'Sync offline records with server',
      'generate pdf': 'Generate PDF report of movement logs',
      'export logs': 'Export movement logs as PDF',
      'create report': 'Create PDF report of student movements',
      'download movements': 'Download movement records as PDF',
      'dark': 'Switch to dark theme',
      'dark theme': 'Switch to dark theme',
      'light': 'Switch to light theme',
      'light theme': 'Switch to light theme',
      'switch theme': 'Toggle between dark and light themes',
      'toggle theme': 'Toggle between dark and light themes',
      'change profile photo': 'Open profile photo editor',
      'update profile': 'Update your profile photo',
      'edit profile photo': 'Edit your profile picture',
    };

    if (widget.selectedRole == 'admin') {
      descriptions['manage time'] = 'Manage allowed time for current student';
      descriptions['set allowed time'] = 'Set custom time limit for student';
      descriptions['edit time limit'] = 'Edit time limit for student';
    }

    if (widget.selectedRole.startsWith('super_')) {
      descriptions['weekly report'] = 'View weekly report';
      descriptions['view report'] = 'View weekly report';
    }

    if (widget.selectedRole.startsWith('security_')) {
      descriptions['check out'] = 'Check student out (when viewing student)';
      descriptions['check in'] = 'Check student in (when viewing student)';
      descriptions['student out'] = 'Check student out';
      descriptions['student in'] = 'Check student in';
    }

    return descriptions;
  }
}
