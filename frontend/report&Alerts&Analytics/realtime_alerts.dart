//realtime_alerts.dart

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class RealtimeAlertsScreen extends StatefulWidget {
  @override
  _RealtimeAlertsScreenState createState() => _RealtimeAlertsScreenState();
}

class _RealtimeAlertsScreenState extends State<RealtimeAlertsScreen> {
  List<dynamic> _alerts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAlerts();
    // Set up periodic refresh
    _setupAlertRefresh();
  }

  void _setupAlertRefresh() {
    // Refresh every 30 seconds for real-time updates
    Future.delayed(Duration(seconds: 30), () {
      if (mounted) {
        _loadAlerts();
        _setupAlertRefresh();
      }
    });
  }

  Future<void> _loadAlerts() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? token = prefs.getString('access_token');

      final response = await http.get(
        Uri.parse('$kBaseUrl/api/alerts/realtime'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        setState(() {
          _alerts = json.decode(response.body);
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading alerts: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Real-time Alerts'),
        backgroundColor: Colors.orange,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _loadAlerts,
          ),
        ],
      ),
      body: _isLoading ? _buildLoadingView() : _buildAlertsList(),
    );
  }

  Widget _buildLoadingView() {
    return Center(child: CircularProgressIndicator());
  }

  Widget _buildAlertsList() {
    if (_alerts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.notifications_off, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('No alerts currently', style: TextStyle(fontSize: 18)),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _alerts.length,
      itemBuilder: (context, index) {
        return _buildAlertCard(_alerts[index]);
      },
    );
  }

  Widget _buildAlertCard(Map<String, dynamic> alert) {
    Color color = _getAlertColor(alert['priority']);
    IconData icon = _getAlertIcon(alert['type']);

    return Card(
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 3,
      child: ListTile(
        leading: Container(
          padding: EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.2),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color),
        ),
        title: Text(alert['message'], style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (alert['details'] != null) 
              Text('${alert['details']}'),
            SizedBox(height: 4),
            Text(_formatTimestamp(alert['timestamp']), 
                 style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        trailing: Icon(Icons.arrow_forward_ios, size: 16),
        onTap: () => _showAlertDetails(alert),
      ),
    );
  }

  Color _getAlertColor(String priority) {
    switch (priority) {
      case 'high': return Colors.red;
      case 'medium': return Colors.orange;
      default: return Colors.blue;
    }
  }

  IconData _getAlertIcon(String type) {
    switch (type) {
      case 'unauthorized_visit': return Icons.warning;
      case 'high_activity': return Icons.trending_up;
      case 'hostel_pattern': return Icons.group;
      default: return Icons.notifications;
    }
  }

  void _showAlertDetails(Map<String, dynamic> alert) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Alert Details'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(alert['message'], style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 16),
            if (alert['details'] != null)
              Text('Details: ${alert['details']}'),
            SizedBox(height: 8),
            Text('Priority: ${alert['priority']}'),
            Text('Time: ${_formatTimestamp(alert['timestamp'])}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close'),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(String timestamp) {
    // Format timestamp for display
    return timestamp;
  }
}
