//scan_screen.dart

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'local_db_helper.dart';
import 'network_service.dart';

const String kBaseUrl = "http://192.168.29.119:5000";
//const String kBaseUrl = "http://10.47.241.1:5000";

class ScanScreen extends StatefulWidget {
  final String role;
  final String hostel;
  final Function(Map<String, dynamic>)? onStudentScanned;

  ScanScreen({required this.role, required this.hostel, this.onStudentScanned});

  @override
  _ScanScreenState createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  MobileScannerController cameraController = MobileScannerController();
  bool _isScanning = false;
  String _lastScanned = '';
  bool _torchEnabled = false;
  Map<String, dynamic>? _scannedStudent;
  bool _showStudentInfo = false;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Scan QR Code - ${widget.role.toUpperCase()} ${widget.hostel.toUpperCase()}',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onPrimary,
          ),
        ),
        backgroundColor: _getRoleColor(widget.role.split('_')[0]),
        actions: [
          IconButton(
            icon: Icon(_torchEnabled ? Icons.flash_on : Icons.flash_off),
            onPressed: () {
              setState(() {
                _torchEnabled = !_torchEnabled;
              });
              cameraController.toggleTorch();
            },
          ),
        ],
      ),
      body: _showStudentInfo && _scannedStudent != null
          ? _buildStudentInfoView(isDark)
          : _buildScannerView(isDark),
    );
  }

  Widget _buildScannerView(bool isDark) {
    return Stack(
      children: [
        MobileScanner(
          controller: cameraController,
          onDetect: (capture) {
            final List<Barcode> barcodes = capture.barcodes;
            for (final barcode in barcodes) {
              if (barcode.rawValue != null && barcode.rawValue != _lastScanned) {
                setState(() {
                  _lastScanned = barcode.rawValue!;
                  _isScanning = true;
                });
                
                _processScan(barcode.rawValue!);
              }
            }
          },
        ),
        if (_isScanning)
          Center(
            child: Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(Colors.white)),
                  SizedBox(height: 16),
                  Text(
                    'Processing scan...',
                    style: TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildStudentNotFoundView(bool isDark) {
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
            color: isDark ? Colors.orange[900]!.withOpacity(0.3) : Colors.orange[50]!,
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
                _scannedStudent!['roll_no'] ?? 'Unknown',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.orange[900],
                  fontFamily: 'monospace',
                ),
              ),
              SizedBox(height: 12),
              Text(
                'Please check the QR code and try again',
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
            _resetScanAndGoBack();
          },
          icon: Icon(Icons.refresh),
          label: Text('Scan Again'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    ),
  );
  }

  Widget _buildStudentInfoView(bool isDark) {
    // Check if student not found
    if (_scannedStudent!['not_found'] == true) {
      return _buildStudentNotFoundView(isDark);
    }
    // Check if this is an access denied scenario
    bool isAccessDenied = _scannedStudent!['access_denied'] == true;

    if (isAccessDenied) {
      return _buildAccessDeniedView(isDark);
    }

    String roleType = widget.role.split('_')[0];

    // For canteen and security, show simplified verification view
    if((roleType == 'canteen' || roleType == 'security') && 
        _scannedStudent!['belongs_to_hostel'] == true) {
      return _buildSimpleVerificationView(isDark);
    }

    // Default detailed view for admin and super
    return SingleChildScrollView(
      padding: EdgeInsets.all(16.0),
      child: Column(
        children: [
          Card(
            elevation: 3,
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: _getRoleColor(widget.role.split('_')[0]),
                    child: Icon(Icons.person, color: Colors.white),
                    radius: 30,
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _scannedStudent!['name']?.toString() ?? 'Unknown',
                          style: TextStyle(
                            fontSize: 20, 
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Roll No: ${_scannedStudent!['roll_no']?.toString() ?? 'N/A'}',
                          style: TextStyle(
                            fontSize: 16, 
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          'Hostel: ${_scannedStudent!['hostel']?.toString() ?? 'N/A'}',
                          style: TextStyle(
                            fontSize: 14, 
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: 20),

          if (widget.role.startsWith('security'))
            _buildSecurityActions(isDark),

          _buildBasicInfoCard(isDark),

          SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    _resetScanAndGoBack();
                  },
                  icon: Icon(Icons.qr_code_scanner),
                  label: Text('Scan Another QR'),
                ),
              ),
              SizedBox(width: 10),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                },
                icon: Icon(Icons.arrow_back),
                label: Text('Back'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ADD THIS METHOD TO PROPERLY RESET SCAN STATE
  void _resetScanAndGoBack() {
    setState(() {
      _showStudentInfo = false;
      _scannedStudent = null;
      _lastScanned = '';
      _isScanning = false;
    });

    // Reinitialize camera controller
    cameraController = MobileScannerController();
  }

  // ADD SIMPLE VERIFICATION VIEW FOR CANTEEN & SECURITY
  Widget _buildSimpleVerificationView(bool isDark) {
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
              color: isDark ? Colors.green[900]!.withOpacity(0.3) : Colors.green[50],
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
                    color: Colors.green[800],
                  ),
                ),
                SizedBox(height: 12),
                Text(
                  'Access granted for ${widget.role.split('_')[0]} operations',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.green[700],
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),

          // Add security actions if security role
          if (widget.role.startsWith('security')) ...[
            SizedBox(height: 20),
            _buildSecurityActions(isDark),
          ],

          SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () {
              _resetScanAndGoBack();
            },
            icon: Icon(Icons.refresh),
            label: Text('Verify Another Student'),
          ),
        ],
      ),
    );
  }
  
  // ADD ACCESS DENIED VIEW FOR SCANNING
  Widget _buildAccessDeniedView(bool isDark) {
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
              color: isDark ? Colors.red[900]!.withOpacity(0.3) : Colors.red[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red[200]!),
            ),
            child: Column(
              children: [
                Icon(Icons.warning_amber, size: 40, color: Colors.red),
                SizedBox(height: 12),
                Text(
                  _scannedStudent!['message'] ?? 'Access denied',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.red[800]),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 8),
                if (_scannedStudent != null) ...[
                  Text(
                    'Student Hostel: ${_scannedStudent!['student_hostel'] ?? 'Unknown'}',
                    style: TextStyle(color: Colors.red[700]),
                  ),
                  Text(
                    'Your Hostel: ${_scannedStudent!['user_hostel'] ?? widget.hostel}',
                    style: TextStyle(color: Colors.red[700]),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () {
              _resetScanAndGoBack();
            },
            icon: Icon(Icons.refresh),
            label: Text('Scan Another QR'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSecurityActions(bool isDark) {
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

  Widget _buildBasicInfoCard(bool isDark) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Student Information',
              style: TextStyle(
                fontSize: 18, 
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            SizedBox(height: 12),
            _buildInfoRow('Room No', _scannedStudent!['room_no']?.toString()),
            _buildInfoRow('Course', _scannedStudent!['course']?.toString()),
            _buildInfoRow('Branch', _scannedStudent!['branch']?.toString()),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String? value) {
    if (value == null || value.isEmpty) return SizedBox.shrink();
    
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Text(
            '$label:', 
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _processScan(String qrData) async {
  try {
    final networkService = NetworkService();
    final isOnline = await networkService.isConnected();
  
    if (!isOnline) {
      // Show offline message but still process the scan
      setState(() {
        _isScanning = false;
      });
      
      _showScanResult(
        false, 
        'Offline Mode', 
        'Scanned: $qrData\n\nYou are offline. Some features may be limited.\nScans will be saved locally and synced later.'
      );
      return;
    }

    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString('access_token');
    String? deviceId = prefs.getString('device_id');

    // For all roles, first get student data
    final response = await http.get(
      Uri.parse('$kBaseUrl/api/student/$qrData/${widget.role}'),
      headers: {
        'Authorization': 'Bearer $token',
        'Device-Id': deviceId ?? '',
      },
    );

    if (response.statusCode == 200) {
      final studentData = json.decode(response.body);

      // Check if access was denied due to hostel mismatch - SHOW ACCESS DENIED VIEW
      if (studentData['access_denied'] == true) {
        setState(() {
          _scannedStudent = studentData;
          _showStudentInfo = true;
          _isScanning = false;
        });

        if (widget.onStudentScanned != null) {
          widget.onStudentScanned!(studentData);
        }
        return;
      }

      // Check for security/canteen hostel verification
      if (studentData['belongs_to_hostel'] != null) {
        bool belongsToHostel = studentData['belongs_to_hostel'] == true;
        String roleType = widget.role.split('_')[0];

        if (belongsToHostel && (roleType == 'security' || roleType == 'canteen')) {
          // For same-hostel students, show simplified view
          setState(() {
            _scannedStudent = studentData;
            _showStudentInfo = true;
            _isScanning = false;
          });

          if (widget.onStudentScanned != null) {
            widget.onStudentScanned!(studentData);
          }
          return;
        } else {
          // For different hostels, show access denied view
          setState(() {
            _scannedStudent = {...studentData, 'access_denied': true};
            _showStudentInfo = true;
            _isScanning = false;
          });

          if (widget.onStudentScanned != null) {
            widget.onStudentScanned!(studentData);
          }
          return;
        }
      }

      // For admin and super (or other cases)
      setState(() {
        _scannedStudent = studentData;
        _showStudentInfo = true;
        _isScanning = false;
      });

      if (widget.onStudentScanned != null) {
        widget.onStudentScanned!(studentData);
      }

    } else if (response.statusCode == 404) {
      // STUDENT NOT FOUND - Show proper UI instead of error dialog
      setState(() {
        _scannedStudent = {'not_found': true, 'roll_no': qrData};
        _showStudentInfo = true;
        _isScanning = false;
      });
    } else if (response.statusCode == 403) {
      // Handle access denied from backend
      final errorData = json.decode(response.body);
      setState(() {
        _scannedStudent = errorData;
        _showStudentInfo = true;
        _isScanning = false;
      });
    } else {
      // Handle other errors with proper UI
      final errorData = json.decode(response.body);
      setState(() {
        _scannedStudent = {'error': true, 'error_message': errorData['message'] ?? 'Unknown error'};
        _showStudentInfo = true;
        _isScanning = false;
      });
    }
  } catch (e) {
    // Handle network errors with proper UI
    setState(() {
      _scannedStudent = {'error': true, 'error_message': 'Network error: $e'};
      _showStudentInfo = true;
      _isScanning = false;
    });
  } finally {
    setState(() {
      _isScanning = false;
    });

    Future.delayed(Duration(seconds: 2), () {
      setState(() {
        _lastScanned = '';
      });
    });
  }
  }

  Future<void> _performSecurityAction(String action) async {
  try {
    final networkService = NetworkService();
    final isOnline = await networkService.isConnected();
    final localDB = LocalDBHelper();

    if (!isOnline) {
      // Save locally when offline
      await localDB.saveSecurityScan(
        rollNo: _scannedStudent!['roll_no'],
        action: action,
        role: widget.role,
        timestamp: DateTime.now(),
      );
      
      _showScanResult(
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
      Uri.parse('$kBaseUrl/api/student/scan/security/${widget.role}'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
        'Device-Id': deviceId ?? '',
      },
      body: json.encode({
        'roll_no': _scannedStudent!['roll_no'],
        'action': action,
      }),
    );

    if (response.statusCode == 200) {
      final result = json.decode(response.body);
      _showScanResult(
        true, 
        'Success', 
        '${action == 'out' ? 'Check out' : 'Check in'} successful!\n'
        'Time: ${_formatDateTimeForDisplay(result['time'])}\n'
        'Time spent: ${result['time_spent_minutes'] ?? 'N/A'} minutes'
      );
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
      await localDB.saveSecurityScan(
        rollNo: _scannedStudent!['roll_no'],
        action: action,
        role: widget.role,
        timestamp: DateTime.now(),
      );
      
      _showScanResult(
        true, 
        'Saved Offline', 
        'Network issue. Action saved locally.\nWill sync when online.\nError: $errorMessage'
      );
    }
  } catch (e) {
    // Any error - fallback to local save
    final localDB = LocalDBHelper();
    await localDB.saveSecurityScan(
      rollNo: _scannedStudent!['roll_no'],
      action: action,
      role: widget.role,
      timestamp: DateTime.now(),
    );
    
    _showScanResult(
      true, 
      'Saved Offline', 
      'Action saved locally due to error.\nWill sync when online.\nError: $e'
    );
  }
  }

  void _showScanResult(bool success, String title, String message) {
    // Show a beautiful dialog instead of snackbar for important messages
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: success ? Colors.green[50] : Colors.orange[50],
          icon: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: success ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              success ? Icons.check_circle : Icons.info,
              size: 40,
              color: success ? Colors.green : Colors.orange,
            ),
          ),
          title: Text(
            title,
            style: TextStyle(
              color: success ? Colors.green[800] : Colors.orange[800],
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            message,
            style: TextStyle(
              color: success ? Colors.green[700] : Colors.orange[700],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text(
                'OK',
                style: TextStyle(
                  color: success ? Colors.green[800] : Colors.orange[800],
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Color _getRoleColor(String role) {
    switch (role) {
      case 'admin': return Colors.purple;
      case 'super': return Colors.blue;
      case 'canteen': return Colors.green;
      case 'security': return Colors.orange;
      default: return Colors.blue;
    }
  }

  // ADD THE NEW METHOD RIGHT HERE, BEFORE THE dispose METHOD:
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


  @override
  void dispose() {
    cameraController.dispose();
    super.dispose();
  }
}
