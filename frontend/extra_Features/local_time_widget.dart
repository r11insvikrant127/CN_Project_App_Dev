//local_time_widget.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:async'; // Add this import for Timer

class LocalTimeWidget extends StatefulWidget {
  @override
  _LocalTimeWidgetState createState() => _LocalTimeWidgetState();
}

class _LocalTimeWidgetState extends State<LocalTimeWidget> {
  late String _currentTime;
  late String _currentDate;
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    _updateTime();
    // Update every second for real-time changes
    _timer = Timer.periodic(Duration(seconds: 1), (Timer t) => _updateTime());
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  void _updateTime() {
    final now = DateTime.now();
    if (mounted) {
      setState(() {
        _currentTime = DateFormat('HH:mm:ss').format(now); // 24-hour format with seconds
        _currentDate = DateFormat('EEEE, MMMM d, yyyy').format(now);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.access_time_filled, color: Colors.blue[600], size: 20),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _currentTime,
                    style: TextStyle(
                      fontSize: 18, 
                      fontWeight: FontWeight.bold, 
                      color: Colors.blue[800],
                      fontFamily: 'RobotoMono', // Monospace for better time display
                    ),
                  ),
                  Text(
                    _currentDate,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.blue[100],
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.blue[300]!),
              ),
              child: Text(
                'LIVE',
                style: TextStyle(
                  fontSize: 10, 
                  fontWeight: FontWeight.bold, 
                  color: Colors.blue[800],
                  letterSpacing: 1.0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
