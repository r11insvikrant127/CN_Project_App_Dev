//sync_service.dart

import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'local_db_helper.dart';
import 'network_service.dart';

const String kBaseUrl = "http://192.168.29.119:5000";

class SyncService {
  final LocalDBHelper _localDB = LocalDBHelper();
  final NetworkService _networkService = NetworkService();
  
  Future<bool> syncPendingRecords() async {
    try {
      final isOnline = await _networkService.isConnected();
      if (!isOnline) {
        print('🔍 DEBUG: Offline - cannot sync');
        return false;
      }
      
      final prefs = await SharedPreferences.getInstance();
      final String? token = prefs.getString('access_token');
      final String? deviceId = prefs.getString('device_id');
      
      if (token == null) {
        print('🔍 DEBUG: No auth token available');
        return false;
      }
      
      bool allSynced = true;
      int syncedCount = 0;
      
      // Sync security scans
      final pendingScans = await _localDB.getPendingSecurityScans();
      print('🔍 DEBUG: Found ${pendingScans.length} pending security scans to sync');
      
      for (final scan in pendingScans) {
        final success = await _syncSecurityScan(scan, token, deviceId);
        if (success) {
          await _localDB.markSecurityScanAsSynced(scan['id'] as int);
          syncedCount++;
          print('🔍 DEBUG: Successfully synced scan ID: ${scan['id']}');
        } else {
          allSynced = false;
          print('🔍 DEBUG: Failed to sync scan ID: ${scan['id']}');
        }
      }
      
      // Sync canteen visits
      final pendingVisits = await _localDB.getPendingCanteenVisits();
      print('🔍 DEBUG: Found ${pendingVisits.length} pending canteen visits to sync');
      
      for (final visit in pendingVisits) {
        final success = await _syncCanteenVisit(visit, token, deviceId);
        if (success) {
          await _localDB.markCanteenVisitAsSynced(visit['id'] as int);
          syncedCount++;
          print('🔍 DEBUG: Successfully synced visit ID: ${visit['id']}');
        } else {
          allSynced = false;
          print('🔍 DEBUG: Failed to sync visit ID: ${visit['id']}');
        }
      }
      
      print('🔍 DEBUG: Sync completed. Total synced: $syncedCount, All successful: $allSynced');
      return allSynced;
    } catch (e) {
      print('🔍 DEBUG: Sync error: $e');
      return false;
    }
  }
  
  Future<bool> _syncSecurityScan(Map<String, dynamic> scan, String token, String? deviceId) async {
    try {
      print('🔍 DEBUG: Syncing security scan - Roll: ${scan['roll_no']}, Action: ${scan['action']}');
      
      final response = await http.post(
        Uri.parse('$kBaseUrl/api/student/scan/security/${scan['role']}'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
          'Device-Id': deviceId ?? '',
        },
        body: json.encode({
          'roll_no': scan['roll_no'],
          'action': scan['action'],
          'offline_sync': true,
          'original_timestamp': scan['timestamp'],
        }),
      ).timeout(Duration(seconds: 10));
      
      print('🔍 DEBUG: Sync response status: ${response.statusCode}');
      print('🔍 DEBUG: Sync response body: ${response.body}');
      
      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        print('🔍 DEBUG: Security scan sync successful: $result');
        return true;
      } else {
        print('🔍 DEBUG: Security scan sync failed: ${response.body}');
        return false;
      }
    } catch (e) {
      print('🔍 DEBUG: Security scan sync error: $e');
      return false;
    }
  }
  
  Future<bool> _syncCanteenVisit(Map<String, dynamic> visit, String token, String? deviceId) async {
    try {
      print('🔍 DEBUG: Syncing canteen visit - Roll: ${visit['roll_no']}');
      
      final response = await http.post(
        Uri.parse('$kBaseUrl/api/student/scan/canteen/${visit['role']}'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
          'Device-Id': deviceId ?? '',
        },
        body: json.encode({
          'roll_no': visit['roll_no'],
          'offline_sync': true,
          'original_timestamp': visit['timestamp'],
        }),
      ).timeout(Duration(seconds: 10));
      
      print('🔍 DEBUG: Canteen visit sync response status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        print('🔍 DEBUG: Canteen visit sync successful: $result');
        return true;
      } else {
        print('🔍 DEBUG: Canteen visit sync failed: ${response.body}');
        return false;
      }
    } catch (e) {
      print('🔍 DEBUG: Canteen visit sync error: $e');
      return false;
    }
  }

  // Manual sync trigger with callback
  Future<bool> syncWithFeedback() async {
    final success = await syncPendingRecords();
    
    if (success) {
      final pendingCount = await _localDB.getPendingRecordsCount();
      if (pendingCount == 0) {
        print('🔍 DEBUG: All records synced successfully!');
        return true;
      }
    }
    
    return false;
  }
}
