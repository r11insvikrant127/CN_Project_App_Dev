import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'local_db_helper.dart';
import 'network_service.dart';
import 'student_db_helper.dart';
import 'sync_service.dart';
import 'package:uuid/uuid.dart';

const String kBaseUrl = "https://cn-project-app-dev.onrender.com";

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

  final StudentDBHelper _studentDB = StudentDBHelper();
  final NetworkService _networkService = NetworkService();
  final SyncService _syncService = SyncService();

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

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
          FutureBuilder<bool>(
            future: _networkService.isConnected(),
            builder: (context, snapshot) {
              final isOnline = snapshot.data ?? true;
              return Padding(
                padding: EdgeInsets.only(right: 8.0),
                child: Icon(
                  isOnline ? Icons.wifi : Icons.wifi_off,
                  color: isOnline ? Colors.white : Colors.yellow,
                  size: 20,
                ),
              );
            },
          ),
          // ✅ ADDED: Sync status indicator
          FutureBuilder<Map<String, dynamic>>(
            future: _syncService.getStudentDataStatus(),
            builder: (context, snapshot) {
              if (snapshot.hasData) {
                final status = snapshot.data!;
                final studentCount = status['total_student_count'] ?? 0;

                if (studentCount > 0) {
                  return Tooltip(
                    message: '📱 $studentCount students available offline',
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.green),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.storage, size: 14, color: Colors.green),
                          SizedBox(width: 4),
                          Text(
                            studentCount.toString(),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }
              }
              return SizedBox.shrink();
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

            // Ignore any new detection while the current scan is being processed.
            if (_isScanning) {
              print(
                  '🔒 DEBUG: Scan already in progress - ignoring duplicate scan');
              return;
            }

            for (final barcode in barcodes) {
              final qrData = barcode.rawValue;

              if (qrData == null || qrData.isEmpty) {
                continue;
              }

              if (qrData == _lastScanned) {
                print('🔒 DEBUG: Duplicate QR detected - ignoring: $qrData');
                continue;
              }

              if (!mounted) return;

              _safeSetState(() {
                _lastScanned = qrData;
                _isScanning = true;
              });

              _processScan(qrData);
              break;
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
                  CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation(Colors.white)),
                  SizedBox(height: 16),
                  Text(
                    'Processing scan...',
                    style: TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
        Positioned(
          top: 20,
          right: 20,
          child: FutureBuilder<bool>(
            future: _networkService.isConnected(),
            builder: (context, snapshot) {
              final isOnline = snapshot.data ?? true;
              if (isOnline) return SizedBox.shrink();

              return Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.wifi_off, size: 14, color: Colors.white),
                    SizedBox(width: 4),
                    Text(
                      'Offline Mode',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        // ✅ ADDED: Offline database status
        Positioned(
          bottom: 20,
          left: 20,
          right: 20,
          child: FutureBuilder<Map<String, dynamic>>(
            future: _syncService.getStudentDataStatus(),
            builder: (context, snapshot) {
              if (snapshot.hasData) {
                final status = snapshot.data!;
                final isOnline =
                    snapshot.connectionState != ConnectionState.waiting
                        ? true
                        : false;

                final studentCount = status['total_student_count'] ?? 0;
                final currentHostelCount = status['current_hostel_count'] ?? 0;
                final syncNeeded = status['sync_needed'] ?? false;

                if (!isOnline && studentCount > 0) {
                  return Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 8,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.white, size: 20),
                        SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '✅ Offline Ready',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              Text(
                                '$studentCount students available for offline scanning',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                              ),
                              if (currentHostelCount > 0)
                                Text(
                                  'Hostel ${widget.hostel}: $currentHostelCount students',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.9),
                                    fontSize: 11,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }
              }
              return SizedBox.shrink();
            },
          ),
        ),
      ],
    );
  }

  // ✅ UPDATED: Main scanning logic with smart online/offline detection
  Future<void> _processScan(String qrData) async {
    try {
      final isOnline = await _networkService.isConnected();

      print('🔍 DEBUG: Processing scan for $qrData');
      print('🔍 DEBUG: Online: $isOnline, Scanner hostel: ${widget.hostel}');

      if (!mounted) return;

      if (isOnline) {
        print('🔍 DEBUG: 🌐 ONLINE - fetching complete data from server...');
        await _fetchCompleteDataFromServer(qrData);
      } else {
        print('🔍 DEBUG: 📴 OFFLINE - checking local database...');
        await _checkLocalDatabaseOnly(qrData);
      }
    } catch (e) {
      print('🔍 DEBUG: ❌ Unexpected error in processScan: $e');

      _safeSetState(() {
        _scannedStudent = {
          'error': true,
          'error_message': 'Unexpected error: $e',
          'roll_no': qrData
        };
        _showStudentInfo = true;
        _isScanning = false;
      });
    } finally {
      Future.delayed(const Duration(seconds: 2), () {
        if (!mounted) return;

        _safeSetState(() {
          _lastScanned = '';
        });
      });
    }
  }

  // ✅ NEW: Fetch complete student data from server (for online mode)
  Future<void> _fetchCompleteDataFromServer(String rollNo) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? token = prefs.getString('access_token');
      final String? deviceId = prefs.getString('device_id');

      if (token == null) {
        throw Exception('No authentication token');
      }

      print('🔍 DEBUG: 📡 Fetching COMPLETE student data from server...');

      final response = await http.get(
        Uri.parse('$kBaseUrl/api/student/$rollNo/${widget.role}'),
        headers: {
          'Authorization': 'Bearer $token',
          'Device-Id': deviceId ?? '',
        },
      ).timeout(Duration(seconds: 10));

      if (response.statusCode == 200) {
        final studentData = json.decode(response.body);
        print('🔍 DEBUG: ✅ Server response successful: ${studentData['name']}');

        // ✅ CRITICAL: Save only basic info (3 fields) to local database for offline use
        if (studentData['name'] != null && studentData['hostel'] != null) {
          await _studentDB.saveStudent(
            roll: rollNo,
            name: studentData['name'],
            hostel: studentData['hostel'],
          );
          print(
              '🔍 DEBUG: 💾 Basic student info saved to local DB for offline use');
        }

        // Add metadata to identify source
        studentData['data_source'] = 'server_complete';
        studentData['offline_mode'] = false;
        studentData['timestamp'] = DateTime.now().toIso8601String();

        // Canteen visit: record successful scan
        if (widget.role.startsWith('canteen_')) {
          _scannedStudent = studentData;
          await _recordCanteenVisit();
        }

        // Process and display the student data
        _processAndDisplayStudentData(studentData);
      } else if (response.statusCode == 404) {
        // Student not found on server
        print('🔍 DEBUG: ❌ Student not found on server');
        _handleStudentNotFound(rollNo, 'Student not found on server');
      } else if (response.statusCode == 403) {
        // Access denied
        final errorData = json.decode(response.body);
        print('🔍 DEBUG: 🔒 Access denied: ${errorData['message']}');
        _showStudentScanResult(errorData as Map<String, dynamic>);
      } else {
        // Server error, fallback to local data
        print('🔍 DEBUG: ⚠️ Server error, trying local cache...');
        await _tryLocalCacheWithFallback(
            rollNo, 'Server error ${response.statusCode}');
      }
    } catch (e) {
      print('🔍 DEBUG: ❌ Network error, trying local cache: $e');
      await _tryLocalCacheWithFallback(rollNo, 'Network error: $e');
    } finally {
      _safeSetState(() {
        _isScanning = false;
      });
    }
  }

  // ✅ NEW: Check local database only (for offline mode)
  Future<void> _checkLocalDatabaseOnly(String rollNo) async {
    print('🔍 DEBUG: 🔎 Searching in local database (OFFLINE MODE)...');

    final localStudent = await _studentDB.getStudent(rollNo);

    if (localStudent != null) {
      print('🔍 DEBUG: ✅ Found student in local DB: ${localStudent['name']}');

      final Map<String, dynamic> studentData = {
        'roll_no': localStudent['roll_no'],
        'name': localStudent['name'],
        'hostel': localStudent['hostel'],
        'from_local_db': true,
        'offline_mode': true,
        'data_source': 'local_cache_offline',
        'limited_data': true,
        'message':
            '📱 Offline mode - showing cached data. Connect to internet for complete details.',
        'timestamp': DateTime.now().toIso8601String(),
      };

      // Canteen has no hostel restriction
      if (widget.role.startsWith('canteen_')) {
        _scannedStudent = studentData;
        await _recordCanteenVisit();
      }

      // Check hostel access
      _checkHostelAccessAndDisplay(studentData);
    } else {
      print('🔍 DEBUG: ❌ Student not found in local database (OFFLINE)');

      _handleStudentNotFound(rollNo, 'Student not found in offline database');
    }

    _safeSetState(() {
      _isScanning = false;
    });
  }

  // ✅ NEW: Try local cache when server fails (online but server error)
  Future<void> _tryLocalCacheWithFallback(
      String rollNo, String errorMessage) async {
    print('🔍 DEBUG: 🔄 Server failed, checking local cache as fallback...');

    final localStudent = await _studentDB.getStudent(rollNo);

    if (localStudent != null) {
      print('🔍 DEBUG: ✅ Found fallback data in local cache');

      final Map<String, dynamic> studentData = {
        'roll_no': localStudent['roll_no'],
        'name': localStudent['name'],
        'hostel': localStudent['hostel'],
        'from_local_db': true,
        'offline_mode': false, // We're online but using cached data
        'data_source': 'local_cache_fallback',
        'server_error': true,
        'error_message': errorMessage,
        'limited_data': true,
        'message': '⚠️ Using cached data due to server issue. $errorMessage',
        'timestamp': DateTime.now().toIso8601String(),
      };

      if (widget.role.startsWith('canteen_')) {
        _scannedStudent = studentData;
        await _recordCanteenVisit();
      }

      _checkHostelAccessAndDisplay(studentData);
    } else {
      print('🔍 DEBUG: ❌ No cached data available');

      _handleStudentNotFound(rollNo, 'Student not found. $errorMessage');
    }

    _safeSetState(() {
      _isScanning = false;
    });
  }

  // ✅ NEW: Process and display student data
  void _processAndDisplayStudentData(Map<String, dynamic> studentData) {
    // Check if access is denied
    if (studentData['access_denied'] == true) {
      _showStudentScanResult(studentData);
      return;
    }

    // Check hostel access for security and canteen roles
    if (widget.role.startsWith('security_')) {
      if (studentData['belongs_to_hostel'] != null) {
        if (studentData['belongs_to_hostel'] == true) {
          _showStudentScanResult(studentData);
        } else {
          final deniedData = {
            ...studentData,
            'access_denied': true,
            'message': 'Student belongs to different hostel',
            'student_hostel': studentData['hostel'],
            'user_hostel': widget.hostel,
          };
          _showStudentScanResult(deniedData);
        }
        return;
      }
    }

    _showStudentScanResult(studentData);
  }

  // ✅ NEW: Check hostel access and display
  void _checkHostelAccessAndDisplay(Map<String, dynamic> studentData) {
    // Check hostel access based on role
    if (widget.role.startsWith('security_')) {
      if (studentData['hostel'] == widget.hostel) {
        studentData['belongs_to_hostel'] = true;
        print(
            '🔍 DEBUG: ✅ Student belongs to scanner hostel (${widget.hostel})');
      } else {
        studentData['access_denied'] = true;
        studentData['message'] = 'Student belongs to different hostel';
        studentData['student_hostel'] = studentData['hostel'];
        studentData['user_hostel'] = widget.hostel;
        print(
            '🔍 DEBUG: ⚠️ Hostel mismatch: Student from ${studentData['hostel']}, Scanner from ${widget.hostel}');
      }
    } else if (widget.role == 'admin') {
      // Admin: Can access all
      studentData['belongs_to_hostel'] = true;
      print(
          '🔍 DEBUG: ✅ Admin access granted to student from ${studentData['hostel']}');
    }

    _showStudentScanResult(studentData);
  }

  // ✅ NEW: Handle student not found
  void _handleStudentNotFound(String rollNo, String reason) {
    _safeSetState(() {
      _scannedStudent = {
        'not_found': true,
        'roll_no': rollNo,
        'error_message': reason,
        'timestamp': DateTime.now().toIso8601String(),
      };

      // Add specific suggestions based on context
      if (reason.contains('offline')) {
        _scannedStudent!['suggestion'] =
            'Connect to internet and try again to fetch student data';
        _scannedStudent!['offline_mode'] = true;
      } else {
        _scannedStudent!['suggestion'] =
            'Please check the roll number and try again';
      }

      _showStudentInfo = true;
    });
  }

  // ✅ NEW: Show scan result (common method) - FOR STUDENT DATA
  void _showStudentScanResult(Map<String, dynamic> studentData) {
    _safeSetState(() {
      _scannedStudent = studentData;
      _showStudentInfo = true;
      _isScanning = false;
    });

    if (widget.onStudentScanned != null) {
      widget.onStudentScanned!(studentData);
    }
  }

  // ✅ NEW: Show security action result - FOR SECURITY ACTIONS
  void _showSecurityActionResult(bool success, String title, String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: success ? Colors.green[50] : Colors.orange[50],
          icon: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: success
                  ? Colors.green.withOpacity(0.1)
                  : Colors.orange.withOpacity(0.1),
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

  // ✅ UPDATED: Keep this method for manual refresh (when user clicks "Get Fresh Data")
  Future<void> _fetchStudentFromServer(String rollNo) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? token = prefs.getString('access_token');
      final String? deviceId = prefs.getString('device_id');

      if (token == null) {
        throw Exception('No authentication token');
      }

      print(
          '🔍 DEBUG: 🔄 Manual refresh - fetching student data from server...');

      final response = await http.get(
        Uri.parse('$kBaseUrl/api/student/$rollNo/${widget.role}'),
        headers: {
          'Authorization': 'Bearer $token',
          'Device-Id': deviceId ?? '',
        },
      ).timeout(Duration(seconds: 10));

      if (response.statusCode == 200) {
        final studentData = json.decode(response.body);
        print('🔍 DEBUG: ✅ Manual refresh successful: ${studentData['name']}');

        // Update local cache with basic info
        if (studentData['name'] != null && studentData['hostel'] != null) {
          await _studentDB.saveStudent(
            roll: rollNo,
            name: studentData['name'],
            hostel: studentData['hostel'],
          );
        }

        // Add metadata
        studentData['data_source'] = 'server_manual_refresh';
        studentData['offline_mode'] = false;
        studentData['timestamp'] = DateTime.now().toIso8601String();

        _processAndDisplayStudentData(studentData);
      } else {
        // Keep existing data but show error
        if (_scannedStudent != null) {
          _safeSetState(() {
            _scannedStudent!['refresh_error'] = true;
            _scannedStudent!['refresh_message'] =
                'Failed to refresh: ${response.statusCode}';
          });
        }
      }
    } catch (e) {
      print('🔍 DEBUG: ❌ Manual refresh error: $e');
      if (_scannedStudent != null) {
        _safeSetState(() {
          _scannedStudent!['refresh_error'] = true;
          _scannedStudent!['refresh_message'] = 'Refresh failed: $e';
        });
      }
    }
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
            style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.orange[800]),
          ),
          SizedBox(height: 16),
          Container(
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.orange[900]!.withOpacity(0.3)
                  : Colors.orange[50]!,
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
                  _scannedStudent!['error_message'] ??
                      'Please check the QR code and try again',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.orange[700],
                  ),
                  textAlign: TextAlign.center,
                ),

                // Show offline sync suggestion
                if (_scannedStudent!['offline_mode'] == true)
                  Container(
                    margin: EdgeInsets.only(top: 16),
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        Icon(Icons.sync_problem, color: Colors.blue, size: 24),
                        SizedBox(height: 8),
                        Text(
                          'Offline Database Issue',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue[800],
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Student not found in local database. Connect to internet and sync student data for offline use.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue[700],
                          ),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: 8),
                        ElevatedButton.icon(
                          onPressed: () async {
                            // Navigate to sync screen or trigger sync
                            final success = await _syncService
                                .checkAndSyncStudentData(forceSync: true);
                            if (success) {
                              _resetScanAndGoBack();
                            }
                          },
                          icon: Icon(Icons.sync),
                          label: Text('Sync Student Data Now'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
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
              ),
              SizedBox(width: 10),
              FutureBuilder<bool>(
                future: _networkService.isConnected(),
                builder: (context, snapshot) {
                  if (snapshot.data == true) {
                    return ElevatedButton.icon(
                      onPressed: () async {
                        final syncService = SyncService();
                        await syncService.manualSyncWithFeedback();
                        _resetScanAndGoBack();
                      },
                      icon: Icon(Icons.sync),
                      label: Text('Sync & Retry'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                    );
                  }
                  return SizedBox.shrink();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStudentInfoView(bool isDark) {
    if (_scannedStudent!['not_found'] == true) {
      return _buildStudentNotFoundView(isDark);
    }

    bool isAccessDenied = _scannedStudent!['access_denied'] == true;

    if (isAccessDenied) {
      return _buildAccessDeniedView(isDark);
    }

    String roleType = widget.role.split('_')[0];

    if (roleType == 'canteen') {
      return _buildSimpleVerificationView(isDark);
    }

    if (roleType == 'security' &&
        _scannedStudent!['belongs_to_hostel'] == true) {
      return _buildSimpleVerificationView(isDark);
    }

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
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          'Hostel: ${_scannedStudent!['hostel']?.toString() ?? 'N/A'}',
                          style: TextStyle(
                            fontSize: 14,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (_scannedStudent!['from_local_db'] == true) ...[
                          SizedBox(height: 4),
                          Container(
                            padding: EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.green[50],
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '📍 Data from local storage',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.green[700],
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: 20),

          if (widget.role.startsWith('security')) _buildSecurityActions(isDark),

          _buildBasicInfoCard(isDark),

          // ✅ UPDATED: Only show refresh button when using limited cached data while online
          if ((_scannedStudent!['data_source'] == 'local_cache_fallback' ||
                  (_scannedStudent!['limited_data'] == true &&
                      _scannedStudent!['offline_mode'] != true)) &&
              _scannedStudent!['refresh_error'] != true) ...[
            SizedBox(height: 16),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: ElevatedButton.icon(
                onPressed: () async {
                  if (!mounted) return;

                  _safeSetState(() {
                    _isScanning = true;
                  });

                  await _fetchStudentFromServer(_scannedStudent!['roll_no']);
                },
                icon: Icon(Icons.refresh),
                label: Text('Get Fresh Data from Server'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  minimumSize: Size(double.infinity, 50),
                ),
              ),
            ),
          ],

          // Show refresh error if any
          if (_scannedStudent!['refresh_error'] == true) ...[
            SizedBox(height: 8),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning, color: Colors.orange, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _scannedStudent!['refresh_message'] ?? 'Refresh failed',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange[800],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

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

  void _resetScanAndGoBack() {
    if (!mounted) return;

    _safeSetState(() {
      _showStudentInfo = false;
      _scannedStudent = null;
      _lastScanned = '';
      _isScanning = false;
    });
  }

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
            style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.green[800]),
          ),
          SizedBox(height: 16),
          Container(
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.green[900]!.withOpacity(0.3)
                  : Colors.green[50],
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
                  _scannedStudent!['name'] ?? 'Student',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.green[900],
                  ),
                ),
                Text(
                  'Roll No: ${_scannedStudent!['roll_no']}',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.green[700],
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Access granted for ${widget.role.split('_')[0]} operations',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.green[700],
                  ),
                  textAlign: TextAlign.center,
                ),
                if (_scannedStudent!['from_local_db'] == true) ...[
                  SizedBox(height: 12),
                  Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.storage, size: 14, color: Colors.blue),
                        SizedBox(width: 4),
                        Text(
                          'Data from local storage',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue[800],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
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
            style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.red[800]),
          ),
          SizedBox(height: 16),
          Container(
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              color:
                  isDark ? Colors.red[900]!.withOpacity(0.3) : Colors.red[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red[200]!),
            ),
            child: Column(
              children: [
                Icon(Icons.warning_amber, size: 40, color: Colors.red),
                SizedBox(height: 12),
                Text(
                  _scannedStudent!['message'] ?? 'Access denied',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.red[800]),
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
                if (_scannedStudent!['offline_mode'] == true ||
                    _scannedStudent!['from_local_db'] == true) ...[
                  SizedBox(height: 12),
                  Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.orange[50],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.info, size: 14, color: Colors.orange),
                        SizedBox(width: 4),
                        Text(
                          'Access check based on local data',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange[800],
                          ),
                        ),
                      ],
                    ),
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
                    label: Text('Check Out',
                        style: TextStyle(color: Colors.white)),
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
                    label:
                        Text('Check In', style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: EdgeInsets.symmetric(vertical: 15),
                    ),
                  ),
                ),
              ],
            ),
            FutureBuilder<bool>(
              future: _networkService.isConnected(),
              builder: (context, snapshot) {
                final isOnline = snapshot.data ?? true;
                if (isOnline) return SizedBox.shrink();

                return Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Row(
                    children: [
                      Icon(Icons.wifi_off, size: 16, color: Colors.orange),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Actions will be saved locally and synced when online',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange[700],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
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
            if (_scannedStudent!['limited_data'] == true &&
                _scannedStudent!['offline_mode'] == true) ...[
              SizedBox(height: 12),
              Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info, size: 16, color: Colors.blue),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Detailed information requires internet connection',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue[800],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
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

  Future<void> _recordCanteenVisit() async {
    if (!widget.role.startsWith('canteen_')) {
      return;
    }

    final eventId = const Uuid().v4();
    final rollNo = _scannedStudent?['roll_no']?.toString();

    if (rollNo == null || rollNo.isEmpty) {
      print('🔍 DEBUG: Cannot record canteen visit - no roll number');
      return;
    }

    final timestamp = DateTime.now();
    final localDB = LocalDBHelper();

    try {
      final isOnline = await _networkService.isConnected();

      // 📵 OFFLINE → save locally for later sync
      if (!isOnline) {
        await localDB.saveCanteenVisit(
          rollNo: rollNo,
          role: widget.role,
          timestamp: timestamp,
          eventId: eventId,
        );

        print(
          '🔍 DEBUG: 📴 Canteen visit saved offline - '
          'Roll: $rollNo, Event ID: $eventId',
        );

        return;
      }

      // 🌐 ONLINE → send directly to backend
      final prefs = await SharedPreferences.getInstance();
      final String? token = prefs.getString('access_token');
      final String? deviceId = prefs.getString('device_id');

      if (token == null) {
        throw Exception('No authentication token available');
      }

      final response = await http
          .post(
            Uri.parse('$kBaseUrl/api/student/scan/canteen/${widget.role}'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
              'Device-Id': deviceId ?? '',
            },
            body: json.encode({
              'roll_no': rollNo,
              'event_id': eventId,
            }),
          )
          .timeout(const Duration(seconds: 10));

      print(
        '🔍 DEBUG: Canteen visit response: '
        '${response.statusCode} ${response.body}',
      );

      if (response.statusCode == 200) {
        print(
          '🔍 DEBUG: ✅ Canteen visit recorded successfully '
          '- Roll: $rollNo',
        );
        return;
      }

      // Server rejected/failed → preserve locally
      await localDB.saveCanteenVisit(
        rollNo: rollNo,
        role: widget.role,
        timestamp: timestamp,
        eventId: eventId,
        syncError: 'Server returned ${response.statusCode}: ${response.body}',
      );

      print(
        '🔍 DEBUG: ⚠️ Canteen visit saved locally after server failure',
      );
    } catch (e) {
      // 🌐 Network/API error → save locally
      await localDB.saveCanteenVisit(
        rollNo: rollNo,
        role: widget.role,
        timestamp: timestamp,
        eventId: eventId,
        syncError: e.toString(),
      );

      print(
        '🔍 DEBUG: ⚠️ Canteen visit saved locally due to error: $e',
      );
    }
  }

  Future<void> _performSecurityAction(String action) async {
    final eventId = const Uuid().v4();
    try {
      final isOnline = await _networkService.isConnected();
      final localDB = LocalDBHelper();

      if (!isOnline) {
        await localDB.saveSecurityScan(
          rollNo: _scannedStudent!['roll_no'],
          action: action,
          role: widget.role,
          timestamp: DateTime.now(),
          eventId: eventId,
        );
        if (!mounted) return;
        _showSecurityActionResult(
            // ✅ FIXED: Changed to _showSecurityActionResult
            true,
            'Saved Offline',
            '${action == 'out' ? 'Check Out' : 'Check In'} saved locally.\nWill sync automatically when online.\nTime: ${_formatDateTimeForDisplay(DateTime.now())}');
        return;
      }

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
          'event_id': eventId,
        }),
      );

      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        if (!mounted) return;
        _showSecurityActionResult(
            // ✅ FIXED: Changed to _showSecurityActionResult
            true,
            'Success',
            '${action == 'out' ? 'Check out' : 'Check in'} successful!\n'
                'Time: ${_formatDateTimeForDisplay(result['time'])}\n'
                'Time spent: ${result['time_spent_minutes'] ?? 'N/A'} minutes');
      } else {
        final errorData = json.decode(response.body);
        String errorMessage = errorData['message'] ?? 'Action failed';

        if (errorMessage.contains('No active check out record found')) {
          errorMessage = 'Student is not checked out. Please check out first.';
        } else if (errorMessage.contains('already checked out')) {
          errorMessage = 'Student is already checked out.';
        } else if (errorMessage.contains('Access denied')) {
          errorMessage = 'Access denied to this student.';
        }

        await localDB.saveSecurityScan(
          rollNo: _scannedStudent!['roll_no'],
          action: action,
          role: widget.role,
          timestamp: DateTime.now(),
          eventId: eventId,
        );
        if (!mounted) return;
        _showSecurityActionResult(
            // ✅ FIXED: Changed to _showSecurityActionResult
            true,
            'Saved Offline',
            'Network issue. Action saved locally.\nWill sync when online.\nError: $errorMessage');
      }
    } catch (e) {
      final localDB = LocalDBHelper();
      await localDB.saveSecurityScan(
        rollNo: _scannedStudent!['roll_no'],
        action: action,
        role: widget.role,
        timestamp: DateTime.now(),
        eventId: eventId,
        syncError: e.toString(),
      );
      if (!mounted) return;
      _showSecurityActionResult(
          // ✅ FIXED: Changed to _showSecurityActionResult
          true,
          'Saved Offline',
          'Action saved locally due to error.\nWill sync when online.\nError: $e');
    }
  }

  Color _getRoleColor(String role) {
    switch (role) {
      case 'admin':
        return Colors.purple;
      case 'super':
        return Colors.blue;
      case 'canteen':
        return Colors.green;
      case 'security':
        return Colors.orange;
      default:
        return Colors.blue;
    }
  }

  String _formatDateTimeForDisplay(dynamic dateTime) {
    if (dateTime == null) return 'N/A';

    try {
      DateTime? parsedDate;

      if (dateTime is String) {
        parsedDate = DateTime.parse(dateTime).toLocal();
      } else if (dateTime is Map<String, dynamic> &&
          dateTime.containsKey('\$date')) {
        String dateString = dateTime['\$date'];
        parsedDate = DateTime.parse(dateString).toLocal();
      } else if (dateTime is DateTime) {
        parsedDate = dateTime.toLocal();
      }

      if (parsedDate != null) {
        return '${parsedDate.day.toString().padLeft(2, '0')}/${parsedDate.month.toString().padLeft(2, '0')}/${parsedDate.year} ${parsedDate.hour.toString().padLeft(2, '0')}:${parsedDate.minute.toString().padLeft(2, '0')} IST';
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
