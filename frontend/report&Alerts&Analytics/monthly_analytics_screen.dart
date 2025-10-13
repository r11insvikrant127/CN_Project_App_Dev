//monthly_analytics_screen.dart

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:async'; // For Stream and StreamBuilder
import 'package:intl/intl.dart';

const String kBaseUrl = "http://192.168.29.119:5000";
//const String kBaseUrl = "http://10.47.241.1:5000";

class MonthlyAnalyticsScreen extends StatefulWidget {
  final String userRole;
  final String userHostel;

  MonthlyAnalyticsScreen({required this.userRole, required this.userHostel});

  @override
  _MonthlyAnalyticsScreenState createState() => _MonthlyAnalyticsScreenState();
}

class _MonthlyAnalyticsScreenState extends State<MonthlyAnalyticsScreen> {
  Map<String, dynamic>? _analyticsData;
  Map<String, dynamic>? _lateArrivalsData;
  bool _isLoading = true;
  int _selectedYear = DateTime.now().year;
  int _selectedMonth = DateTime.now().month;
  List<int> _years = [2023, 2024, 2025];
  List<String> _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  Future<void> _loadAllData() async {
    setState(() {
      _isLoading = true;
    });
    
    await _loadAnalyticsData();
    await _loadLateArrivalsData();
    
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _loadLateArrivalsData() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? token = prefs.getString('access_token');

      print('🔍 Loading late arrivals data...');

      String url = '$kBaseUrl/api/analytics/late-arrivals';
    
      // Add hostel filter for super users
      if (widget.userRole.startsWith('super_')) {
        url += '?hostel=${widget.userHostel}';
      }

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );
      
      print('📡 Late Arrivals Response Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('✅ Late Arrivals Data Parsed Successfully');
        
        // Process ALL late arrivals data with proper date filtering
        _processAllLateArrivalsWithFilter(data);
      } else {
        print('❌ Failed to load late arrivals: ${response.statusCode}');
        _setEmptyLateArrivalsData();
      }
    } catch (e) {
      print('💥 Error loading late arrivals: $e');
      _setEmptyLateArrivalsData();
    }
  }

  void _processAllLateArrivalsWithFilter(Map<String, dynamic> data) {
    final weeklyLateArrivals = data['weekly_late_arrivals'] ?? [];
    
    if (weeklyLateArrivals.isEmpty) {
      print('📭 No late arrivals data found');
      _setEmptyLateArrivalsData();
      return;
    }

    // Filter data for selected month and year
    Map<String, Map<String, dynamic>> studentMap = {};
    int totalOccurrences = 0;
    int foundRecords = 0;

    for (var arrival in weeklyLateArrivals) {
      try {
        String rollNo = arrival['_id']['roll_no'] ?? 'Unknown';
        String name = arrival['_id']['name'] ?? 'Unknown';
        String hostel = arrival['_id']['hostel'] ?? 'Unknown';
        int lateCount = arrival['late_count'] ?? 1;
        double totalTimeExceeded = (arrival['total_time_exceeded'] ?? 0.0).toDouble();
        
        // Extract date from last_occurrence and check if it matches selected month/year
        DateTime? arrivalDate = _parseArrivalDate(arrival['last_occurrence']);
        
        if (arrivalDate != null) {
          bool matchesSelection = arrivalDate.year == _selectedYear && 
                                 arrivalDate.month == _selectedMonth;
          
          print('📅 Checking: $name - Date: $arrivalDate - Matches: $matchesSelection');
          
          if (matchesSelection) {
            foundRecords++;
            
            // Count total occurrences (sum of all late_count values)
            totalOccurrences += lateCount;

            // Add or update student record
            if (!studentMap.containsKey(rollNo)) {
              studentMap[rollNo] = {
                'name': name,
                'roll_no': rollNo,
                'hostel': hostel,
                'total_time_exceeded': totalTimeExceeded,
                'date': _formatDisplayDate(arrivalDate),
                'occurrence_count': lateCount,
              };
            } else {
              studentMap[rollNo]!['total_time_exceeded'] = 
                  (studentMap[rollNo]!['total_time_exceeded'] as double) + totalTimeExceeded;
              studentMap[rollNo]!['occurrence_count'] = 
                  (studentMap[rollNo]!['occurrence_count'] as int) + lateCount;
            }

            print('✅ INCLUDED: $name, Roll: $rollNo, Late Count: $lateCount, Total Time: $totalTimeExceeded min');
          }
        }
      } catch (e) {
        print('⚠️ Error processing arrival: $e');
      }
    }

    print('🎯 Found $foundRecords records for $_selectedMonth/$_selectedYear');

    // Convert map to list and sort by time exceeded (descending)
    List<Map<String, dynamic>> filteredLateStudents = studentMap.values.toList();
    filteredLateStudents.sort((a, b) => (b['total_time_exceeded'] as double).compareTo(a['total_time_exceeded'] as double));

    // Count unique students
    int uniqueStudentsCount = studentMap.length;

    setState(() {
      _lateArrivalsData = {
        'student_details': filteredLateStudents,
        'summary': {
          'total_students_with_late_arrivals': uniqueStudentsCount,
          'total_late_occurrences': totalOccurrences,
        },
        'has_data': filteredLateStudents.isNotEmpty,
        'month_year': '$_selectedMonth/$_selectedYear',
        'records_found': foundRecords
      };
    });

    print('✅ Processed $uniqueStudentsCount unique students with $totalOccurrences total occurrences for $_selectedMonth/$_selectedYear');
  }

  DateTime? _parseArrivalDate(dynamic dateValue) {
    if (dateValue == null) return null;
    
    try {
      // Handle MongoDB date format: {"$date": "2025-09-26T00:00:00Z"}
      if (dateValue is Map<String, dynamic> && dateValue.containsKey('\$date')) {
        String dateString = dateValue['\$date'];
        return DateTime.parse(dateString);
      }
      
      // Handle regular string dates
      if (dateValue is String) {
        if (dateValue.contains('T')) {
          return DateTime.parse(dateValue);
        }
        // Try parsing as simple date string
        try {
          return DateTime.parse(dateValue);
        } catch (e) {
          return null;
        }
      }
      
      return null;
    } catch (e) {
      print('❌ Date parsing error: $e');
      return null;
    }
  }

  String _formatDisplayDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  void _setEmptyLateArrivalsData() {
    setState(() {
      _lateArrivalsData = {
        'student_details': [],
        'summary': {'total_students_with_late_arrivals': 0, 'total_late_occurrences': 0},
        'has_data': false,
        'month_year': '$_selectedMonth/$_selectedYear',
        'records_found': 0
      };
    });
  }

  Future<void> _loadAnalyticsData() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? token = prefs.getString('access_token');

      String url = '$kBaseUrl/api/analytics/unauthorized-visits-monthly?year=$_selectedYear&month=$_selectedMonth';

      // Add hostel filter for super users
      if (widget.userRole.startsWith('super_')) {
        url += '&hostel=${widget.userHostel}';
      }

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        setState(() {
          _analyticsData = json.decode(response.body);
        });
      } else {
        print('Error loading analytics: ${response.statusCode}');
        _analyticsData = {
          'by_student_hostel': [],
          'by_canteen_hostel': [],
          'summary': {
            'month': _selectedMonth,
            'year': _selectedYear,
            'total_unauthorized_visits': 0,
            'unique_students_involved': 0
          }
        };
      }
    } catch (e) {
      print('Error: $e');
      _analyticsData = {
        'by_student_hostel': [],
        'by_canteen_hostel': [],
        'summary': {
        'month': _selectedMonth,
          'year': _selectedYear,
          'total_unauthorized_visits': 0,
          'unique_students_involved': 0
        }
      };
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      appBar: AppBar(
        title: Text('Monthly Analytics',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18)),
        backgroundColor: Theme.of(context).colorScheme.primary,
        elevation: 0,
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: Theme.of(context).colorScheme.onPrimary),
            onPressed: _loadAllData,
            tooltip: 'Refresh Data',
          ),
        ],
      ),
      body: _isLoading ? _buildLoadingView() : _buildAnalyticsDashboard(isDark),
    );
  }

  Widget _buildLoadingView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).colorScheme.primary),
              strokeWidth: 3,
            ),
          ),
          SizedBox(height: 20),
          Text(
            'Loading Analytics Dashboard',
            style: TextStyle(
              fontSize: 16, 
              color: Theme.of(context).colorScheme.onSurfaceVariant, 
              fontWeight: FontWeight.w500
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalyticsDashboard(bool isDark) {
    final hasUnauthorizedData = _analyticsData != null && 
        (_analyticsData!['by_student_hostel']?.isNotEmpty == true || 
         _analyticsData!['by_canteen_hostel']?.isNotEmpty == true);
    
    final hasLateArrivalsData = _lateArrivalsData?['has_data'] == true;

    return SingleChildScrollView(
      child: Column(
        children: [
          // Header with Filters
          _buildDashboardHeader(isDark),
          SizedBox(height: 16),

          // Unauthorized Canteen Visits Section - Always show but with proper empty state
          _buildUnauthorizedVisitsSection(isDark),
          SizedBox(height: 16),

          // Late Arrivals Section - Always show but with proper empty state
          _buildLateArrivalsSection(isDark),
          
          SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildDashboardHeader(bool isDark) {
    final hasLateArrivalsData = _lateArrivalsData?['has_data'] == true;
    final hasUnauthorizedData = _analyticsData != null && 
        (_analyticsData!['by_student_hostel']?.isNotEmpty == true || 
         _analyticsData!['by_canteen_hostel']?.isNotEmpty == true);

    return Card(
      elevation: 2,
      margin: EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [Colors.purple[900]!.withOpacity(0.3), Colors.blue[900]!.withOpacity(0.3)]
                : [Colors.purple[50]!, Colors.blue[50]!],
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.analytics, color: Theme.of(context).colorScheme.primary, size: 24),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Monthly Analytics',
                          style: TextStyle(
                            fontSize: 18, 
                            fontWeight: FontWeight.bold, 
                            color: isDark ? Colors.purple[100] : Colors.purple[800]
                          ),
                        ),
                        // REPLACE the existing Text widget with _buildAnalyticsTime()
                        _buildAnalyticsTime(hasUnauthorizedData, hasLateArrivalsData, isDark),
                      ],
                    ),
                  ),
                  // ADD this right here - last updated indicator
                  _buildLastUpdatedIndicator(isDark),
                ],
              ),
              SizedBox(height: 16),
              _buildFilters(isDark),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAnalyticsTime(bool hasUnauthorizedData, bool hasLateArrivalsData, bool isDark) {
    return StreamBuilder(
      stream: Stream.periodic(Duration(seconds: 1)),
      builder: (context, snapshot) {
        final now = DateTime.now();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_months[_selectedMonth - 1]} $_selectedYear • ${DateFormat('HH:mm:ss').format(now)}',
              style: TextStyle(fontSize: 14, color: isDark ? Colors.purple[300] : Colors.purple[600]),
            ),
            SizedBox(height: 4),
            // Show data availability status
            _buildDataAvailabilityStatus(hasUnauthorizedData, hasLateArrivalsData, isDark),
          ],
        );
      },
    );
  }

  Widget _buildLastUpdatedIndicator(bool isDark) {
    return StreamBuilder(
      stream: Stream.periodic(Duration(seconds: 60)), // Update every minute
      builder: (context, snapshot) {
        final lastUpdate = DateTime.now();
        return Column(
          children: [
            Container(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isDark ? Colors.green[900]!.withOpacity(0.3) : Colors.green[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green[200]!),
              ),
              child: Text(
                'Updated',
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.green[700],
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            SizedBox(height: 4),
            Text(
              DateFormat('HH:mm').format(lastUpdate),
              style: TextStyle(
                fontSize: 10,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDataAvailabilityStatus(bool hasUnauthorizedData, bool hasLateArrivalsData, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: hasUnauthorizedData ? Colors.green : Colors.grey,
                shape: BoxShape.circle,
              ),
            ),
            SizedBox(width: 6),
            Text(
              'Canteen Visits: ${hasUnauthorizedData ? 'Data available' : 'No data'}',
              style: TextStyle(
                fontSize: 12,
                color: hasUnauthorizedData ? Colors.green[700] : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        SizedBox(height: 2),
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: hasLateArrivalsData ? Colors.orange : Colors.grey,
                shape: BoxShape.circle,
              ),
            ),
            SizedBox(width: 6),
            Text(
              'Late Arrivals: ${hasLateArrivalsData ? 'Data available' : 'No data'}',
              style: TextStyle(
                fontSize: 12,
                color: hasLateArrivalsData ? Colors.orange[700] : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFilters(bool isDark) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.05),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Year', 
                  style: TextStyle(
                    fontSize: 12, 
                    fontWeight: FontWeight.w500, 
                    color: Theme.of(context).colorScheme.onSurfaceVariant
                  )
                ),
                SizedBox(height: 6),
                Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      value: _selectedYear,
                      isExpanded: true,
                      icon: Icon(Icons.arrow_drop_down, color: Theme.of(context).colorScheme.primary),
                      items: _years.map((year) {
                        return DropdownMenuItem(
                          value: year,
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            child: Text(
                              year.toString(), 
                              style: TextStyle(
                                fontSize: 14,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedYear = value!;
                        });
                        _loadAllData();
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Month', 
                  style: TextStyle(
                    fontSize: 12, 
                    fontWeight: FontWeight.w500, 
                    color: Theme.of(context).colorScheme.onSurfaceVariant
                  )
                ),
                SizedBox(height: 6),
                Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      value: _selectedMonth,
                      isExpanded: true,
                      icon: Icon(Icons.arrow_drop_down, color: Theme.of(context).colorScheme.primary),
                      items: List.generate(12, (index) {
                        return DropdownMenuItem(
                          value: index + 1,
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            child: Text(
                              _months[index], 
                              style: TextStyle(
                                fontSize: 14,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ),
                        );
                      }),
                      onChanged: (value) {
                        setState(() {
                          _selectedMonth = value!;
                        });
                        _loadAllData();
                      },
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

  Widget _buildUnauthorizedVisitsSection(bool isDark) {
    final summary = _analyticsData!['summary'] ?? {};
    final byStudentHostel = _analyticsData!['by_student_hostel'] ?? [];
    final byCanteenHostel = _analyticsData!['by_canteen_hostel'] ?? [];

    final totalVisits = summary['total_unauthorized_visits'] ?? 0;
    final uniqueStudents = summary['unique_students_involved'] ?? 0;
    final hasData = byStudentHostel.isNotEmpty || byCanteenHostel.isNotEmpty;

    return Card(
      elevation: 2,
      margin: EdgeInsets.symmetric(horizontal: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section Header
            _buildSectionHeader(
              icon: Icons.restaurant,
              title: 'Unauthorized Canteen Visits',
              subtitle: 'Cross-hostel dining activity analysis',
              color: Colors.red,
              isDark: isDark,
            ),
            SizedBox(height: 16),

            if (hasData) ...[
              // Summary Cards
              Row(
                children: [
                  Expanded(child: _buildMetricCard(
                    value: '$totalVisits',
                    label: 'Total Visits',
                    icon: Icons.fastfood,
                    color: Colors.red,
                    isDark: isDark,
                  )),
                  SizedBox(width: 12),
                  Expanded(child: _buildMetricCard(
                    value: '$uniqueStudents',
                    label: 'Students Involved',
                    icon: Icons.people_alt,
                    color: Colors.blue,
                    isDark: isDark,
                  )),
                ],
              ),
              SizedBox(height: 20),

              // Visualizations
              if (byStudentHostel.isNotEmpty) 
                _buildStudentHostelPieChart(byStudentHostel, isDark),
              if (byCanteenHostel.isNotEmpty) SizedBox(height: 16),
              if (byCanteenHostel.isNotEmpty) 
                _buildCanteenHostelPieChart(byCanteenHostel, isDark),
              if (byStudentHostel.isNotEmpty) SizedBox(height: 16),
              if (byStudentHostel.isNotEmpty) 
                _buildDetailedBreakdown(byStudentHostel, isDark),
            ] else ...[
              _buildEmptyState(
                icon: Icons.restaurant_menu,
                title: 'No Unauthorized Visits',
                message: 'No unauthorized canteen visits recorded for ${_months[_selectedMonth - 1]} $_selectedYear',
                color: Colors.green,
                isDark: isDark,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLateArrivalsSection(bool isDark) {
    final details = _lateArrivalsData?['student_details'] ?? [];
    final summary = _lateArrivalsData?['summary'] ?? {};
    final hasData = _lateArrivalsData?['has_data'] == true;

    final totalStudents = summary['total_students_with_late_arrivals'] ?? 0;
    final totalOccurrences = summary['total_late_occurrences'] ?? 0;

    return Card(
      elevation: 2,
      margin: EdgeInsets.symmetric(horizontal: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            _buildSectionHeader(
              icon: Icons.schedule,
              title: 'Late Arrivals Monitoring',
              subtitle: 'Student punctuality and time management • ${_months[_selectedMonth - 1]} $_selectedYear',
              color: Colors.orange,
              isDark: isDark,
            ),
            SizedBox(height: 20),

            if (hasData) ...[
              // Statistics
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: isDark
                        ? [Colors.orange[900]!.withOpacity(0.3), Colors.red[900]!.withOpacity(0.3)]
                        : [Colors.orange[50]!, Colors.red[50]!],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatisticItem(
                      value: '$totalStudents',
                      label: 'Students Late',
                      color: Colors.orange[700]!,
                      description: 'Unique students',
                    ),
                    Container(width: 1, height: 40, color: Colors.orange[200]!),
                    _buildStatisticItem(
                      value: '$totalOccurrences',
                      label: 'Total Occurrences',
                      color: Colors.red[700]!,
                      description: 'All late arrivals',
                    ),
                  ],
                ),
              ),
              SizedBox(height: 20),

              if (details.isNotEmpty) ...[
                Text(
                  'Late Arrival Details', 
                  style: TextStyle(
                    fontSize: 16, 
                    fontWeight: FontWeight.bold, 
                    color: Theme.of(context).colorScheme.onSurface
                  )
                ),
                SizedBox(height: 12),
                ...details.map((student) => _buildStudentLateItem(student, isDark)).toList(),
              ],
            ] else ...[
              _buildEmptyState(
                icon: Icons.verified_user,
                title: 'Perfect Punctuality',
                message: 'No late arrivals recorded for ${_months[_selectedMonth - 1]} $_selectedYear. All students were on time!',
                color: Colors.green,
                isDark: isDark,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState({required IconData icon, required String title, required String message, required Color color, required bool isDark}) {
    return Container(
      padding: EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 48, color: color),
          SizedBox(height: 16),
          Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
          SizedBox(height: 8),
          Text(message, 
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _buildSectionHeader({required IconData icon, required String title, required String subtitle, required Color color, required bool isDark}) {
    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
              Text(subtitle, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMetricCard({required String value, required String label, required IconData icon, required Color color, required bool isDark}) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
                  Text(label, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatisticItem({required String value, required String label, required Color color, required String description}) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
        SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w500)),
        SizedBox(height: 2),
        Text(description, style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ],
    );
  }

  Widget _buildStudentLateItem(Map<String, dynamic> student, bool isDark) {
    return Container(
      margin: EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[800]!.withOpacity(0.3) : Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        children: [
          // Status Indicator
          Container(
            width: 8,
            height: 60,
            decoration: BoxDecoration(
              color: Colors.orange,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          SizedBox(width: 12),
          
          // Student Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        student['name'] ?? 'Unknown Student',
                        style: TextStyle(
                          fontSize: 16, 
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${student['occurrence_count']}x',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.orange),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _buildInfoChip(Icons.badge, 'Roll: ${student['roll_no']}', Colors.blue),
                    _buildInfoChip(Icons.home, 'Hostel ${student['hostel']}', Colors.green),
                    _buildInfoChip(Icons.timer, '${(student['total_time_exceeded'] ?? 0).toStringAsFixed(1)} min', Colors.orange),
                    _buildInfoChip(Icons.calendar_today, student['date'] ?? 'Unknown', Colors.purple),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String text, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          SizedBox(width: 4),
          Text(text, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  // Rest of the pie chart methods remain the same...
  Widget _buildStudentHostelPieChart(List<dynamic> data, bool isDark) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Visits by Student Hostel', 
              style: TextStyle(
                fontSize: 16, 
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            SizedBox(height: 16),
            Container(
              height: 200,
              child: PieChart(
                PieChartData(
                  sections: data.asMap().entries.map((entry) {
                    final index = entry.key;
                    final item = entry.value;
                    final value = (item['total_visits'] ?? item['visits'] ?? 0).toDouble();
                    return PieChartSectionData(
                      color: _getChartColor(index),
                      value: value,
                      title: '${value.toInt()}',
                      radius: 60,
                      titleStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                    );
                  }).toList(),
                  centerSpaceRadius: 40,
                ),
              ),
            ),
            SizedBox(height: 16),
            _buildLegend(data, isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildCanteenHostelPieChart(List<dynamic> data, bool isDark) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Visits by Canteen Hostel', 
              style: TextStyle(
                fontSize: 16, 
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            SizedBox(height: 16),
            Container(
              height: 200,
              child: PieChart(
                PieChartData(
                  sections: data.asMap().entries.map((entry) {
                    final index = entry.key;
                    final item = entry.value;
                    final value = (item['total_visits'] ?? item['visits'] ?? 0).toDouble();
                    return PieChartSectionData(
                      color: _getChartColor(index),
                      value: value,
                      title: '${value.toInt()}',
                      radius: 60,
                      titleStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                    );
                  }).toList(),
                  centerSpaceRadius: 40,
                ),
              ),
            ),
            SizedBox(height: 16),
            _buildCanteenLegend(data, isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildLegend(List<dynamic> data, bool isDark) {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: data.asMap().entries.map((entry) {
        final index = entry.key;
        final item = entry.value;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 12, height: 12, color: _getChartColor(index),),
            SizedBox(width: 6),
            Text(
              'Hostel ${item['hostel']}',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildCanteenLegend(List<dynamic> data, bool isDark) {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: data.asMap().entries.map((entry) {
        final index = entry.key;
        final item = entry.value;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 12, height: 12, color: _getChartColor(index),),
            SizedBox(width: 6),
            Text(
              'Canteen ${item['canteen']}',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildDetailedBreakdown(List<dynamic> data, bool isDark) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Detailed Visit Breakdown', 
              style: TextStyle(
                fontSize: 16, 
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            SizedBox(height: 16),
            ...data.map((hostelData) => _buildHostelBreakdown(hostelData, data.indexOf(hostelData), isDark)).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildHostelBreakdown(Map<String, dynamic> hostelData, int index, bool isDark) {
    return Container(
      margin: EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: CircleAvatar(
              backgroundColor: _getChartColor(index),
              child: Text(hostelData['hostel'], style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
            title: Text(
              'Hostel ${hostelData['hostel']}', 
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            trailing: Text(
              '${hostelData['total_visits']} visits', 
              style: TextStyle(
                fontWeight: FontWeight.bold, 
                color: _getChartColor(index)
              ),
            ),
          ),
          ...(hostelData['data'] as List).map((canteenData) => 
            Padding(
              padding: EdgeInsets.only(left: 16, bottom: 8),
              child: Row(
                children: [
                  Icon(Icons.arrow_forward_ios, size: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  SizedBox(width: 8),
                  Text(
                    'Canteen ${canteenData['canteen']}:',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  SizedBox(width: 8),
                  Text(
                    '${canteenData['visits']} visits', 
                    style: TextStyle(
                      fontWeight: FontWeight.bold, 
                      color: Colors.green
                    ),
                  ),
                ],
              ),
            ),
          ),
          Divider(),
        ],
      ),
    );
  }

  Color _getChartColor(int index) {
    final colors = [Colors.blue, Colors.green, Colors.orange, Colors.purple, Colors.red, Colors.teal, Colors.pink, Colors.indigo];
    return colors[index % colors.length];
  }
}
