import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

const String kBaseUrl = "http://192.168.29.119:5000";

class AllowedTimeManagementScreen extends StatefulWidget {
  final String rollNo;
  final String studentName;

  const AllowedTimeManagementScreen({
    Key? key,
    required this.rollNo,
    this.studentName = 'Unknown',
  }) : super(key: key);

  @override
  _AllowedTimeManagementScreenState createState() => _AllowedTimeManagementScreenState();
}

class _AllowedTimeManagementScreenState extends State<AllowedTimeManagementScreen> {
  final TextEditingController _timeController = TextEditingController();
  Map<String, dynamic>? _studentData;
  Map<String, dynamic>? _currentTimeSettings;
  bool _isLoading = false;
  bool _isUpdating = false;

  @override
  void initState() {
    super.initState();
    _timeController.text = '480'; // Default value
    _loadStudentData(); // Auto-load student data when screen opens
  }

  Future<void> _loadStudentData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? token = prefs.getString('access_token');

      // Get student basic info
      final studentResponse = await http.get(
        Uri.parse('$kBaseUrl/api/student/${widget.rollNo}/admin'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (studentResponse.statusCode == 200) {
        final studentData = json.decode(studentResponse.body);
        
        // Get current allowed time settings
        final timeResponse = await http.get(
          Uri.parse('$kBaseUrl/api/admin/student/allowed-time/${widget.rollNo}'),
          headers: {
            'Authorization': 'Bearer $token',
          },
        );

        Map<String, dynamic> timeSettings = {};
        if (timeResponse.statusCode == 200) {
          timeSettings = json.decode(timeResponse.body);
        }

        setState(() {
          _studentData = studentData;
          _currentTimeSettings = timeSettings;
          _timeController.text = timeSettings['current_allowed_time']?.toString() ?? '480';
        });
      } else {
        _showSnackBar('Student not found');
        Navigator.of(context).pop(); // Go back if student not found
      }
    } catch (e) {
      _showSnackBar('Error loading student data: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _updateAllowedTime() async {
    if (_studentData == null || _timeController.text.isEmpty) {
      _showSnackBar('Student data not loaded');
      return;
    }

    final newTime = double.tryParse(_timeController.text);
    if (newTime == null || newTime <= 0) {
      _showSnackBar('Please enter a valid time in minutes');
      return;
    }

    setState(() {
      _isUpdating = true;
    });

    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? token = prefs.getString('access_token');

      final response = await http.post(
        Uri.parse('$kBaseUrl/api/admin/student/allowed-time/${widget.rollNo}'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'allowed_time_minutes': newTime,
        }),
      );

      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        _showSuccessDialog('Allowed time updated successfully!', result['message']);
        
        // Refresh current settings
        _loadStudentData();
      } else {
        final error = json.decode(response.body);
        _showSnackBar(error['message'] ?? 'Failed to update allowed time');
      }
    } catch (e) {
      _showSnackBar('Error updating allowed time: $e');
    } finally {
      setState(() {
        _isUpdating = false;
      });
    }
  }

  Future<void> _resetToDefault() async {
    if (_studentData == null) {
      _showSnackBar('Student data not loaded');
      return;
    }

    setState(() {
      _isUpdating = true;
    });

    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? token = prefs.getString('access_token');

      final response = await http.post(
        Uri.parse('$kBaseUrl/api/admin/student/allowed-time/${widget.rollNo}/reset'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        _showSuccessDialog('Time reset successful!', result['message']);
        
        // Refresh current settings
        _loadStudentData();
      } else {
        final error = json.decode(response.body);
        _showSnackBar(error['message'] ?? 'Failed to reset allowed time');
      }
    } catch (e) {
      _showSnackBar('Error resetting allowed time: $e');
    } finally {
      setState(() {
        _isUpdating = false;
      });
    }
  }

  void _showSuccessDialog(String title, String message) {
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
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.check_circle, color: Colors.green, size: 40),
                ),
                SizedBox(height: 20),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.green[800],
                  ),
                ),
                SizedBox(height: 12),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
                  ),
                ),
                SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text('OK'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Manage Allowed Time - ${widget.rollNo}'),
        backgroundColor: Colors.blue[700],
        elevation: 0,
      ),
      body: _isLoading 
          ? _buildLoadingIndicator()
          : SingleChildScrollView(
              padding: EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header Section
                  _buildHeaderSection(),
                  SizedBox(height: 24),
                  
                  // Student Info Section
                  if (_studentData != null) _buildStudentInfoSection(),
                  
                  // Time Management Section
                  if (_studentData != null) _buildTimeManagementSection(),
                  
                  // Show error if student data failed to load
                  if (_studentData == null && !_isLoading) _buildErrorSection(),
                ],
              ),
            ),
    );
  }

  Widget _buildLoadingIndicator() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(strokeWidth: 3),
          SizedBox(height: 16),
          Text(
            'Loading student data...',
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorSection() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: Colors.red),
          SizedBox(height: 16),
          Text(
            'Failed to load student data',
            style: TextStyle(fontSize: 18, color: Colors.red),
          ),
          SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loadStudentData,
            child: Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderSection() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.blue[700]!, Colors.blue[500]!],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.timer, color: Colors.white, size: 28),
              ),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Manage Allowed Time',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Student: ${widget.rollNo}',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withOpacity(0.9),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.info, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Default allowed time: 480 minutes (8 hours)',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStudentInfoSection() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: EdgeInsets.all(20),
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
            SizedBox(height: 16),
            Row(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [Colors.purple[500]!, Colors.purple[300]!],
                    ),
                  ),
                  child: Icon(Icons.person, color: Colors.white, size: 28),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _studentData!['name'] ?? 'Unknown',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Roll No: ${_studentData!['roll_no']}',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                      Text(
                        'Hostel: ${_studentData!['hostel']}',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                      if (_studentData!['room_no'] != null) 
                        Text(
                          'Room: ${_studentData!['room_no']}',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeManagementSection() {
    final isCustom = _currentTimeSettings?['is_custom'] == true;
    final currentTime = _currentTimeSettings?['current_allowed_time'] ?? 480;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Time Settings',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            SizedBox(height: 16),
            
            // Current Status
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isCustom ? Colors.blue[50] : Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isCustom ? Colors.blue[200]! : Colors.grey[300]!,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isCustom ? Icons.check_circle : Icons.schedule,
                    color: isCustom ? Colors.blue : Colors.grey,
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isCustom ? 'Custom Time Set' : 'Using Default Time',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isCustom ? Colors.blue[800] : Colors.grey[800],
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Current allowed time: $currentTime minutes',
                          style: TextStyle(
                            color: isCustom ? Colors.blue[600] : Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            SizedBox(height: 20),
            
            // Time Input
            TextField(
              controller: _timeController,
              decoration: InputDecoration(
                labelText: 'Allowed Time (minutes)',
                prefixIcon: Icon(Icons.timer),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                helperText: 'Enter time in minutes (e.g., 480 for 8 hours)',
              ),
              keyboardType: TextInputType.number,
            ),
            
            SizedBox(height: 20),
            
            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isUpdating ? null : _updateAllowedTime,
                    icon: _isUpdating 
                        ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : Icon(Icons.save),
                    label: Text(_isUpdating ? 'Updating...' : 'Update Time'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 12),
                if (isCustom)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isUpdating ? null : _resetToDefault,
                      icon: Icon(Icons.restore),
                      label: Text('Reset to Default'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.grey,
                        padding: EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            
            SizedBox(height: 16),
            
            // Information Box
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber, color: Colors.orange, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Disciplinary records will be generated if student exceeds this time limit',
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
        ),
      ),
    );
  }
}
