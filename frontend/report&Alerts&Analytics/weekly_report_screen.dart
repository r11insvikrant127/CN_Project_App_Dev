//weekly_report_screen.dart

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

const String kBaseUrl = "http://192.168.29.119:5000";
//const String kBaseUrl = "http://10.47.241.1:5000";

class WeeklyReportScreen extends StatefulWidget {
  @override
  _WeeklyReportScreenState createState() => _WeeklyReportScreenState();
}

class _WeeklyReportScreenState extends State<WeeklyReportScreen> {
  final TextEditingController _extraStudentsController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  bool _isSubmitting = false;
  String _currentHostel = '';
  String _currentRole = '';
  int _currentWeek = 0;
  int _currentYear = 0;

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
    _calculateCurrentWeek();
  }

  void _calculateCurrentWeek() {
    final now = DateTime.now();
    setState(() {
      _currentWeek = _getWeekNumber(now);
      _currentYear = now.year;
    });
  }

  int _getWeekNumber(DateTime date) {
    final firstDay = DateTime(date.year, 1, 1);
    final daysDiff = date.difference(firstDay).inDays;
    return ((daysDiff + firstDay.weekday - 1) / 7).floor() + 1;
  }

  Future<void> _loadUserInfo() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _currentRole = prefs.getString('current_role') ?? '';
      _currentHostel = prefs.getString('current_hostel') ?? '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      appBar: AppBar(
        title: Text('Weekly Canteen Report'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        elevation: 0,
      ),
      body: _buildContent(isDark),
    );
  }

  Widget _buildContent(bool isDark) {
    return Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Card
          Card(
            elevation: 4,
            color: isDark ? Colors.blue[900]!.withOpacity(0.3) : Colors.blue[50],
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(Icons.restaurant_menu, size: 40, color: Theme.of(context).colorScheme.primary),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Weekly Canteen Report',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.blue[100] : Colors.blue[800],
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Hostel ${_currentHostel.toUpperCase()} • Week $_currentWeek, $_currentYear',
                              style: TextStyle(
                                color: isDark ? Colors.blue[200] : Colors.blue[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Track unauthorized eating incidents and extra students',
                    style: TextStyle(
                      color: isDark ? Colors.blue[300] : Colors.blue[700],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),

          SizedBox(height: 24),

          // Report Form
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Report Details',
                    style: TextStyle(
                      fontSize: 18, 
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  SizedBox(height: 16),

                  // Extra Students Count
                  Card(
                    elevation: 2,
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.group_add, color: Colors.orange),
                              SizedBox(width: 8),
                              Text(
                                'Extra Students Count',
                                style: TextStyle(
                                  fontSize: 16, 
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 12),
                          Text(
                            'Number of students who ate in your canteen without proper authorization this week:',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                          SizedBox(height: 12),
                          TextField(
                            controller: _extraStudentsController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'Enter number of extra students',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.people_alt),
                              hintText: 'e.g., 5, 12, 20',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  SizedBox(height: 16),

                  // Additional Notes
                  Card(
                    elevation: 2,
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.note_add, color: Colors.green),
                              SizedBox(width: 8),
                              Text(
                                'Additional Notes',
                                style: TextStyle(
                                  fontSize: 16, 
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 12),
                          Text(
                            'Any observations or specific incidents worth noting:',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                          SizedBox(height: 12),
                          TextField(
                            controller: _notesController,
                            maxLines: 4,
                            decoration: InputDecoration(
                              labelText: 'Enter notes (optional)',
                              border: OutlineInputBorder(),
                              alignLabelWithHint: true,
                              hintText: 'e.g., Students from Hostel A frequently avoiding scanner...',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  SizedBox(height: 24),

                  // Weekly Summary
                  Card(
                    elevation: 2,
                    color: isDark ? Colors.grey[800]!.withOpacity(0.3) : Colors.grey[50],
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Week $_currentWeek, $_currentYear Summary',
                            style: TextStyle(
                              fontSize: 16, 
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Hostel:', 
                                style: TextStyle(
                                  fontWeight: FontWeight.w500,
                                  color: Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                              Text(
                                _currentHostel.toUpperCase(), 
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Reporting Role:', 
                                style: TextStyle(
                                  fontWeight: FontWeight.w500,
                                  color: Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                              Text(
                                _currentRole.replaceAll('_', ' ').toUpperCase(), 
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Report Date:', 
                                style: TextStyle(
                                  fontWeight: FontWeight.w500,
                                  color: Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                              Text(
                                DateFormat('MMM dd, yyyy').format(DateTime.now()), 
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  SizedBox(height: 32),

                  // Submit Button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _submitWeeklyReport,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Theme.of(context).colorScheme.onPrimary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: _isSubmitting
                          ? SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation(Theme.of(context).colorScheme.onPrimary),
                              ),
                            )
                          : Text(
                              'Submit Weekly Report',
                              style: TextStyle(
                                fontSize: 16, 
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),

                  SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submitWeeklyReport() async {
    if (_extraStudentsController.text.isEmpty) {
      _showErrorDialog('Please enter the number of extra students');
      return;
    }

    final extraStudents = int.tryParse(_extraStudentsController.text);
    if (extraStudents == null || extraStudents < 0) {
      _showErrorDialog('Please enter a valid number of students');
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? token = prefs.getString('access_token');

      final response = await http.post(
        Uri.parse('$kBaseUrl/api/canteen/weekly-report'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'week_number': _currentWeek,
          'year': _currentYear,
          'hostel': _currentHostel,
          'extra_students_count': extraStudents,
          'report_data': {
            'notes': _notesController.text,
            'submission_date': DateTime.now().toIso8601String(),
            'reported_by': _currentRole,
          }
        }),
      );

      if (response.statusCode == 200) {
        _showSuccessDialog();
      } else {
        final errorData = json.decode(response.body);
        _showErrorDialog(errorData['message'] ?? 'Failed to submit report');
      }
    } catch (e) {
      _showErrorDialog('Network error: $e');
    } finally {
      setState(() {
        _isSubmitting = false;
      });
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green),
            SizedBox(width: 8),
            Text('Report Submitted'),
          ],
        ),
        content: Text('Weekly canteen report has been submitted successfully.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context); // Go back to previous screen
            },
            child: Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.error, color: Colors.red),
            SizedBox(width: 8),
            Text('Submission Failed'),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK'),
          ),
        ],
      ),
    );
  }
}
