// sync_service.dart - COMPLETE VERSION WITH FULL STUDENT SYNC
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'local_db_helper.dart';
import 'network_service.dart';
import 'student_db_helper.dart';
import 'dart:async';

int min(int a, int b) => a < b ? a : b;

const String kBaseUrl = "https://cn-project-app-dev.onrender.com";

class SyncService {
  final LocalDBHelper _localDB = LocalDBHelper();
  final NetworkService _networkService = NetworkService();
  final StudentDBHelper _studentDB = StudentDBHelper();
  
  // ✅ NEW: Get ALL students from ALL hostels (for complete offline capability)
  Future<bool> syncAllStudentsComplete() async {
    try {
      final isOnline = await _networkService.isConnected();
      if (!isOnline) {
        print('🔍 DEBUG: Cannot sync - offline');
        return false;
      }
      
      final prefs = await SharedPreferences.getInstance();
      final String? token = prefs.getString('access_token');
      
      if (token == null) {
        print('🔍 DEBUG: No auth token for student sync');
        return false;
      }
      
      print('🔍 DEBUG: ⭐⭐⭐ STARTING COMPLETE STUDENT SYNC FOR ALL HOSTELS ⭐⭐⭐');
      
      // ✅ CRITICAL: Get ALL students from ALL hostels
      final response = await http.get(
        Uri.parse('$kBaseUrl/api/students/hostel/ALL'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      ).timeout(Duration(seconds: 45)); // Longer timeout for large dataset
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final List<dynamic> students = List<dynamic>.from(data['students'] ?? []);
          
          print('🔍 DEBUG: Received ${students.length} students from ALL hostels');
          
          if (students.isNotEmpty) {
            // ✅ FIXED: Convert to proper format
            final List<Map<String, dynamic>> studentMaps = students.map((student) {
              return {
                'roll_no': student['roll_no']?.toString() ?? '',
                'name': student['name']?.toString() ?? '',
                'hostel': student['hostel']?.toString() ?? '',
              };
            }).toList();
            
            // ✅ FIXED: Save all students (upsert - doesn't delete existing)
            await _studentDB.saveStudents(studentMaps);
            
            // Save sync timestamp
            await prefs.setString('last_complete_sync', DateTime.now().toIso8601String());
            await prefs.setBool('has_complete_sync', true);
            
            // Get final count for verification
            final totalCount = await _studentDB.getStudentCount();
            final byHostel = await _studentDB.getStudentStats();
            
            print('🔍 DEBUG: ⭐⭐⭐ COMPLETE SYNC SUCCESSFUL ⭐⭐⭐');
            print('🔍 DEBUG: Total students in local DB: $totalCount');
            print('🔍 DEBUG: By hostel: ${byHostel['by_hostel']}');
            print('🔍 DEBUG: Estimated storage: ~${(studentMaps.length * 31 / 1024).toStringAsFixed(1)}KB');
            
            return true;
          } else {
            print('🔍 DEBUG: ⚠️ No students returned from server');
            return false;
          }
        } else {
          print('🔍 DEBUG: ❌ API returned error: ${data['message']}');
          return false;
        }
      } else {
        print('🔍 DEBUG: ❌ Failed to fetch ALL students: ${response.statusCode}');
        print('🔍 DEBUG: Response: ${response.body}');
        return false;
      }
    } catch (e) {
      print('🔍 DEBUG: ❌ Error in complete sync: $e');
      return false;
    }
  }
  
  // ✅ NEW: Enhanced checkAndSyncStudentData with complete sync
  Future<bool> checkAndSyncStudentData({bool forceSync = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? userHostel = prefs.getString('hostel');
      final String? currentRole = prefs.getString('current_role');
      
      // Check if we need student data (only for security and canteen roles)
      final roleType = currentRole?.split('_')[0] ?? '';
      if (roleType != 'security' && roleType != 'canteen') {
        print('🔍 DEBUG: Role $roleType does not need student data sync');
        return true;
      }
      
      final studentCount = await _studentDB.getStudentCount();
      final lastSyncPref = prefs.getString('last_complete_sync');
      final hasCompleteSync = prefs.getBool('has_complete_sync') ?? false;
      
      DateTime? lastSyncTime;
      if (lastSyncPref != null) {
        lastSyncTime = DateTime.parse(lastSyncPref);
      }
      
      // ✅ FIXED: Check if we need to sync (24 hours OR no complete sync yet)
      final bool shouldSync = forceSync || 
                            !hasCompleteSync || 
                            studentCount == 0 || 
                            lastSyncTime == null ||
                            DateTime.now().difference(lastSyncTime) > Duration(hours: 24);
      
      if (!shouldSync) {
        print('🔍 DEBUG: ✅ Student data is up to date ($studentCount total students from ALL hostels)');
        
        // Still verify we have data for current hostel
        if (userHostel != null) {
          final hostelCount = await _studentDB.getStudentCountByHostel(userHostel);
          print('🔍 DEBUG: Hostel $userHostel has $hostelCount students locally');
        }
        
        return true;
      }
      
      final isOnline = await _networkService.isConnected();
      if (!isOnline) {
        print('🔍 DEBUG: 📴 Offline - using cached data');
        // Check if we have ANY data to use
        final cachedCount = await _studentDB.getStudentCount();
        final stats = await _studentDB.getStudentStats();
        print('🔍 DEBUG: Using cached data ($cachedCount total students from hostels: ${stats['hostels_with_data']})');
        return cachedCount > 0;
      }
      
      // ✅ Perform COMPLETE sync (ALL hostels)
      print('🔍 DEBUG: 🔄 Starting COMPLETE student data sync for ALL hostels...');
      
      // Show progress to user
      _showSyncProgress('Downloading student data for offline use...');
      
      final success = await syncAllStudentsComplete();
      
      if (success) {
        final updatedCount = await _studentDB.getStudentCount();
        final stats = await _studentDB.getStudentStats();
        
        print('🔍 DEBUG: ✅ COMPLETE student data sync successful!');
        print('🔍 DEBUG: Total students: $updatedCount');
        print('🔍 DEBUG: By hostel: ${stats['by_hostel']}');
        
        _showSyncProgress('✅ Downloaded $updatedCount students for offline use');
        
        // Verify current hostel has data
        if (userHostel != null) {
          final hostelCount = await _studentDB.getStudentCountByHostel(userHostel);
          print('🔍 DEBUG: Hostel $userHostel now has $hostelCount students');
        }
      } else {
        print('🔍 DEBUG: ⚠️ Complete student data sync failed');
        _showSyncProgress('⚠️ Failed to download student data');
        
        // Check what we have locally
        final cachedCount = await _studentDB.getStudentCount();
        if (cachedCount > 0) {
          print('🔍 DEBUG: Using existing cached data ($cachedCount students)');
          _showSyncProgress('Using cached data ($cachedCount students)');
        }
      }
      
      return success;
    } catch (e) {
      print('🔍 DEBUG: ❌ Error checking student data sync: $e');
      _showSyncProgress('❌ Sync error: ${e.toString()}');
      return false;
    }
  }
  
  // ✅ NEW: Optimized sync for current hostel only (if needed)
  Future<bool> syncCurrentHostelOnly(String hostel) async {
    try {
      final isOnline = await _networkService.isConnected();
      if (!isOnline) return false;
      
      final prefs = await SharedPreferences.getInstance();
      final String? token = prefs.getString('access_token');
      
      if (token == null) return false;
      
      print('🔍 DEBUG: Syncing only Hostel $hostel (optimized)');
      
      final response = await http.get(
        Uri.parse('$kBaseUrl/api/students/hostel/$hostel'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      ).timeout(Duration(seconds: 30));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final List<dynamic> students = List<dynamic>.from(data['students'] ?? []);
          
          if (students.isNotEmpty) {
            final List<Map<String, dynamic>> studentMaps = students.map((student) {
              return {
                'roll_no': student['roll_no']?.toString() ?? '',
                'name': student['name']?.toString() ?? '',
                'hostel': student['hostel']?.toString() ?? '',
              };
            }).toList();
            
            // Save only these students (will update existing, add new)
            await _studentDB.saveStudents(studentMaps);
            
            await prefs.setString('last_hostel_sync_$hostel', DateTime.now().toIso8601String());
            
            print('🔍 DEBUG: ✅ Synced ${students.length} students for Hostel $hostel');
            return true;
          }
        }
      }
      return false;
    } catch (e) {
      print('🔍 DEBUG: Error syncing hostel $hostel: $e');
      return false;
    }
  }
  
  // ✅ NEW: Get student data status (enhanced)
  Future<Map<String, dynamic>> getStudentDataStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? userHostel = prefs.getString('hostel');
      final String? currentRole = prefs.getString('current_role');
      
      final studentCount = await _studentDB.getStudentCount();
      final lastSyncPref = prefs.getString('last_complete_sync');
      final hasCompleteSync = prefs.getBool('has_complete_sync') ?? false;
      
      DateTime? lastSyncTime;
      if (lastSyncPref != null) {
        try {
          lastSyncTime = DateTime.parse(lastSyncPref);
        } catch (e) {
          print('🔍 DEBUG: Error parsing last sync time: $e');
        }
      }
      
      // Get stats by hostel
      final stats = await _studentDB.getStudentStats();
      final byHostel = stats['by_hostel'] as Map<String, int>;
      
      // Check if data is stale (24+ hours old)
      final bool isStale = !hasCompleteSync || 
                          lastSyncTime == null || 
                          DateTime.now().difference(lastSyncTime) > Duration(hours: 24);
      
      // Check if current hostel has data (for security/canteen)
      bool currentHostelHasData = true;
      int currentHostelCount = 0;
      
      if (userHostel != null && byHostel.containsKey(userHostel)) {
        currentHostelCount = byHostel[userHostel] ?? 0;
        currentHostelHasData = currentHostelCount > 0;
      } else if (userHostel != null) {
        currentHostelHasData = false;
      }
      
      return {
        'has_complete_sync': hasCompleteSync,
        'total_student_count': studentCount,
        'by_hostel': byHostel,
        'current_hostel': userHostel,
        'current_hostel_count': currentHostelCount,
        'current_hostel_has_data': currentHostelHasData,
        'last_sync': lastSyncTime?.toIso8601String(),
        'last_sync_formatted': lastSyncTime != null 
            ? '${lastSyncTime.day}/${lastSyncTime.month}/${lastSyncTime.year} ${lastSyncTime.hour}:${lastSyncTime.minute}'
            : 'Never',
        'is_stale': isStale,
        'sync_needed': isStale || studentCount == 0 || !hasCompleteSync,
        'role': currentRole?.toString(),
        'message': studentCount > 0 
            ? '✅ $studentCount students from ${byHostel.length} hostels available offline'
            : '❌ No student data available for offline use',
        'estimated_storage_kb': (studentCount * 31 / 1024).toStringAsFixed(1),
      };
    } catch (e) {
      print('🔍 DEBUG: Error getting student data status: $e');
      return {
        'has_complete_sync': false,
        'total_student_count': 0,
        'by_hostel': {},
        'sync_needed': true,
        'message': 'Error: $e'
      };
    }
  }
  
  // ✅ NEW: Manual sync with user feedback
  Future<Map<String, dynamic>> manualSyncWithFeedback() async {
    try {
      final isOnline = await _networkService.isConnected();
      if (!isOnline) {
        return {
          'success': false,
          'message': '📴 You are offline. Cannot sync without internet connection.',
          'type': 'manual'
        };
      }
      
      print('🔍 DEBUG: ⚡ Starting manual sync...');
      
      final statusBefore = await getStudentDataStatus();
      final prefs = await SharedPreferences.getInstance();
      final String? currentRole = prefs.getString('current_role');
      
      // Determine what to sync based on role
      final roleType = currentRole?.split('_')[0] ?? '';
      
      bool syncSuccess = false;
      String syncMessage = '';
      
      if (roleType == 'security' || roleType == 'canteen') {
        // Security/Canteen: Sync ALL students
        _showSyncProgress('📥 Downloading student data for offline use...');
        syncSuccess = await syncAllStudentsComplete();
        
        if (syncSuccess) {
          final count = await _studentDB.getStudentCount();
          syncMessage = '✅ Downloaded $count students for offline scanning';
        } else {
          syncMessage = '❌ Failed to download student data';
        }
      } else if (roleType == 'admin' || roleType == 'super') {
        // Admin/Super: Only sync pending records
        syncSuccess = await enhancedSync();
        syncMessage = syncSuccess 
            ? '✅ Pending records synced successfully'
            : '❌ Failed to sync pending records';
      }
      
      // Also sync pending records if any
      final pendingCount = await _localDB.getPendingRecordsCount();
      if (pendingCount > 0) {
        _showSyncProgress('📤 Syncing pending records...');
        final recordsSynced = await enhancedSync();
        if (recordsSynced) {
          syncMessage += '\n📤 $pendingCount pending records synced';
        }
      }
      
      final statusAfter = await getStudentDataStatus();
      
      return {
        'success': syncSuccess,
        'message': syncMessage,
        'type': 'manual',
        'status_before': statusBefore,
        'status_after': statusAfter,
        'timestamp': DateTime.now().toIso8601String(),
        'pending_records_synced': pendingCount > 0,
        'student_data_synced': roleType == 'security' || roleType == 'canteen',
      };
    } catch (e) {
      print('🔍 DEBUG: Manual sync error: $e');
      return {
        'success': false,
        'message': '❌ Sync failed: ${e.toString()}',
        'type': 'manual'
      };
    }
  }
  
  // ✅ NEW: Force complete sync (for testing/debugging)
  Future<Map<String, dynamic>> forceCompleteSync() async {
    try {
      final isOnline = await _networkService.isConnected();
      if (!isOnline) {
        return {
          'success': false,
          'message': '📴 Offline - cannot sync',
          'online': false
        };
      }
      
      print('🔍 DEBUG: 💥 FORCE COMPLETE SYNC INITIATED');
      
      // Clear old sync flags to force fresh sync
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('last_complete_sync');
      await prefs.remove('has_complete_sync');
      
      _showSyncProgress('🔄 Force syncing ALL student data...');
      
      final success = await syncAllStudentsComplete();
      
      if (success) {
        final count = await _studentDB.getStudentCount();
        final stats = await _studentDB.getStudentStats();
        
        return {
          'success': true,
          'message': '✅ Force sync completed successfully',
          'student_count': count,
          'by_hostel': stats['by_hostel'],
          'estimated_storage_kb': (count * 31 / 1024).toStringAsFixed(1),
          'timestamp': DateTime.now().toIso8601String()
        };
      } else {
        return {
          'success': false,
          'message': '❌ Force sync failed',
          'timestamp': DateTime.now().toIso8601String()
        };
      }
    } catch (e) {
      print('🔍 DEBUG: Force sync error: $e');
      return {
        'success': false,
        'message': '❌ Error: ${e.toString()}',
        'timestamp': DateTime.now().toIso8601String()
      };
    }
  }
  
  // ✅ NEW: Check if student exists in ANY hostel (for offline scanning)
  Future<Map<String, dynamic>?> findStudentAnywhere(String rollNo) async {
    try {
      print('🔍 DEBUG: Searching for student $rollNo in ALL hostels...');
      
      // First check local database (search ANY hostel)
      final localStudent = await _studentDB.getStudent(rollNo);
      
      if (localStudent != null) {
        print('🔍 DEBUG: ✅ Found student in local DB: ${localStudent['name']} (${localStudent['hostel']})');
        return {
          'roll_no': localStudent['roll_no'],
          'name': localStudent['name'],
          'hostel': localStudent['hostel'],
          'from_local_db': true,
          'found_in_hostel': localStudent['hostel'],
          'source': 'local_cache'
        };
      }
      
      // If not found locally and online, try server
      final isOnline = await _networkService.isConnected();
      if (isOnline) {
        print('🔍 DEBUG: Student not in local cache, checking server...');
        
        final prefs = await SharedPreferences.getInstance();
        final token = prefs.getString('access_token');
        
        if (token != null) {
          // Try lightweight validation endpoint first
          final validationResponse = await http.post(
            Uri.parse('$kBaseUrl/api/student/validate-offline'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: json.encode({'roll_no': rollNo}),
          ).timeout(Duration(seconds: 5));
          
          if (validationResponse.statusCode == 200) {
            final data = json.decode(validationResponse.body);
            if (data['valid'] == true && data['student'] != null) {
              final student = data['student'];
              print('🔍 DEBUG: ✅ Found student on server: ${student['name']}');
              
              // Save to local DB for future offline use
              await _studentDB.saveStudent(
                roll: student['roll_no'],
                name: student['name'],
                hostel: student['hostel'],
              );
              
              return {
                'roll_no': student['roll_no'],
                'name': student['name'],
                'hostel': student['hostel'],
                'from_server': true,
                'cached_for_offline': true,
                'source': 'server_validation'
              };
            }
          }
        }
      }
      
      print('🔍 DEBUG: ❌ Student $rollNo not found anywhere');
      return null;
      
    } catch (e) {
      print('🔍 DEBUG: Error finding student: $e');
      return null;
    }
  }
  
  // ✅ NEW: Debug database contents
  Future<void> debugDatabaseContents() async {
    try {
      print('🔍 🔍 🔍 DATABASE DEBUG - COMPLETE STATUS 🔍 🔍 🔍');
      
      final studentCount = await _studentDB.getStudentCount();
      final stats = await _studentDB.getStudentStats();
      final prefs = await SharedPreferences.getInstance();
      final lastSync = prefs.getString('last_complete_sync');
      final hasCompleteSync = prefs.getBool('has_complete_sync') ?? false;
      final userHostel = prefs.getString('hostel');
      final currentRole = prefs.getString('current_role');
      
      print('📊 STUDENT DATABASE:');
      print('   Total students: $studentCount');
      print('   By hostel: ${stats['by_hostel']}');
      print('   Has complete sync: $hasCompleteSync');
      print('   Last sync: $lastSync');
      
      if (userHostel != null) {
        final hostelCount = await _studentDB.getStudentCountByHostel(userHostel);
        print('   Your hostel ($userHostel): $hostelCount students');
      }
      
      print('👤 USER INFO:');
      print('   Role: $currentRole');
      print('   Hostel: $userHostel');
      
      print('💾 STORAGE ESTIMATE:');
      print('   ~${(studentCount * 31 / 1024).toStringAsFixed(1)}KB for $studentCount students');
      
      // Show sample data
      if (studentCount > 0) {
        final sampleStudents = await _studentDB.getAllStudents();
        print('📋 SAMPLE STUDENTS (first 3):');
        for (int i = 0; i < min(3, sampleStudents.length); i++) {
          final student = sampleStudents[i];
          print('   ${student['roll_no']} - ${student['name']} (${student['hostel']})');
        }
      }
      
      print('🔍 🔍 🔍 END DEBUG 🔍 🔍 🔍');
    } catch (e) {
      print('🔍 DEBUG: Error debugging database: $e');
    }
  }
  
  // ✅ NEW: Clear and resync (for testing)
  Future<Map<String, dynamic>> clearAndResync() async {
    try {
      print('🔍 DEBUG: 🧹 Clearing and re-syncing student data...');
      
      // Clear student database
      await _studentDB.clearAllStudents();
      
      // Clear sync flags
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('last_complete_sync');
      await prefs.remove('has_complete_sync');
      
      print('🔍 DEBUG: ✅ Database cleared, starting fresh sync...');
      
      // Perform fresh sync
      final syncResult = await forceCompleteSync();
      
      return {
        'success': syncResult['success'] ?? false,
        'message': syncResult['message'] ?? 'Unknown result',
        'action': 'clear_and_resync',
        'details': syncResult
      };
    } catch (e) {
      print('🔍 DEBUG: Clear and resync error: $e');
      return {
        'success': false,
        'message': '❌ Error: ${e.toString()}',
        'action': 'clear_and_resync'
      };
    }
  }
  
  // ✅ NEW: Show sync progress (helper method)
  void _showSyncProgress(String message) {
    print('🔄 SYNC PROGRESS: $message');
    // You could integrate with a progress dialog here
  }
  
  // Sync pending records (existing method - keep it)
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
  
  // Existing helper methods (keep them)
  Future<bool> _syncSecurityScan(Map<String, dynamic> scan, String token, String? deviceId) async {
    try {
      print('🔍 DEBUG: Syncing security scan - Roll: ${scan['roll_no']}, Action: ${scan['action']}');
      
      DateTime timestamp;
      if (scan['timestamp'] is String) {
        timestamp = DateTime.parse(scan['timestamp']);
      } else if (scan['timestamp'] is DateTime) {
        timestamp = scan['timestamp'];
      } else {
        timestamp = DateTime.now();
      }
      
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
          'original_timestamp': timestamp.millisecondsSinceEpoch,
        }),
      ).timeout(Duration(seconds: 10));
      
      print('🔍 DEBUG: Sync response status: ${response.statusCode}');
      print('🔍 DEBUG: Sync response body: ${response.body}');
      
      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        print('🔍 DEBUG: Security scan sync successful: $result');
        await _localDB.markSecurityScanAsSynced(scan['id'] as int);
        return true;
      } else if (response.statusCode == 404) {
        print('🔍 DEBUG: Student not found, deleting scan ID: ${scan['id']}');
        await _localDB.deleteSecurityScan(scan['id'] as int);
        return true;
      } else if (response.statusCode == 403) {
        print('🔍 DEBUG: Role mismatch, deleting scan ID: ${scan['id']}');
        await _localDB.deleteSecurityScan(scan['id'] as int);
        return true;
      } else if (response.statusCode == 400) {
        final errorResponse = json.decode(response.body);
        print('🔍 DEBUG: Removing failed scan: ${errorResponse['message']}');
        await _localDB.deleteSecurityScan(scan['id'] as int);
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
      
      DateTime timestamp;
      if (visit['timestamp'] is String) {
        timestamp = DateTime.parse(visit['timestamp']);
      } else if (visit['timestamp'] is DateTime) {
        timestamp = visit['timestamp'];
      } else {
        timestamp = DateTime.now();
      }
      
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
          'original_timestamp': timestamp.millisecondsSinceEpoch,
        }),
      ).timeout(Duration(seconds: 10));
      
      print('🔍 DEBUG: Canteen visit sync response status: ${response.statusCode}');
      print('🔍 DEBUG: Canteen visit sync response body: ${response.body}');
      
      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        print('🔍 DEBUG: Canteen visit sync successful: $result');
        await _localDB.markCanteenVisitAsSynced(visit['id'] as int);
        return true;
      } else if (response.statusCode == 404) {
        print('🔍 DEBUG: Student not found, deleting visit ID: ${visit['id']}');
        await _localDB.deleteCanteenVisit(visit['id'] as int);
        return true;
      } else if (response.statusCode == 403) {
        print('🔍 DEBUG: Role mismatch, deleting visit ID: ${visit['id']}');
        await _localDB.deleteCanteenVisit(visit['id'] as int);
        return true;
      } else if (response.statusCode == 400) {
        final errorResponse = json.decode(response.body);
        print('🔍 DEBUG: Removing failed visit: ${errorResponse['message']}');
        await _localDB.deleteCanteenVisit(visit['id'] as int);
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

  // NEW: Enhanced sync that includes student data sync
  Future<bool> enhancedSync() async {
    try {
      print('🔍 DEBUG: Starting enhanced sync...');
      
      final isOnline = await _networkService.isConnected();
      if (!isOnline) {
        print('🔍 DEBUG: Offline - cannot sync');
        return false;
      }
      
      // 1. First sync student data if needed (for security/canteen only)
      final studentSyncStatus = await getStudentDataStatus();
      if (studentSyncStatus['sync_needed'] == true && 
          (studentSyncStatus['role']?.toString().startsWith('security') == true ||
           studentSyncStatus['role']?.toString().startsWith('canteen') == true)) {
        print('🔍 DEBUG: Syncing student data first...');
        final studentSyncSuccess = await checkAndSyncStudentData(forceSync: true);
        if (!studentSyncSuccess) {
          print('🔍 DEBUG: ⚠️ Student data sync failed');
        }
      }
      
      // 2. Try batch sync first (more efficient)
      final batchSuccess = await batchSyncSecurityScans();
      
      // 3. Then sync remaining individual records
      final individualSuccess = await syncPendingRecords();
      
      final totalSuccess = batchSuccess && individualSuccess;
      
      // Check final status
      final pendingCount = await _localDB.getPendingRecordsCount();
      if (pendingCount == 0) {
        print('🔍 DEBUG: ✅ All records synced successfully!');
        return true;
      } else {
        print('🔍 DEBUG: ⚠️ Some records still pending: $pendingCount');
        return totalSuccess;
      }
    } catch (e) {
      print('🔍 DEBUG: Enhanced sync error: $e');
      return false;
    }
  }

  // Batch sync method (existing - keep it)
  Future<bool> batchSyncSecurityScans() async {
    try {
      final isOnline = await _networkService.isConnected();
      if (!isOnline) return false;
      
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token');
      
      if (token == null) return false;
      
      final pendingScans = await _localDB.getPendingSecurityScans();
      if (pendingScans.isEmpty) return true;
      
      print('🔍 DEBUG: Batch syncing ${pendingScans.length} security scans');
      
      final scansToSync = pendingScans.map((scan) {
        DateTime timestamp;
        if (scan['timestamp'] is String) {
          timestamp = DateTime.parse(scan['timestamp']);
        } else if (scan['timestamp'] is DateTime) {
          timestamp = scan['timestamp'];
        } else {
          timestamp = DateTime.now();
        }
        
        return {
          'roll_no': scan['roll_no'],
          'action': scan['action'],
          'original_timestamp': timestamp.millisecondsSinceEpoch,
        };
      }).toList();
      
      final response = await http.post(
        Uri.parse('$kBaseUrl/api/sync/security-scans'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({'scans': scansToSync}),
      ).timeout(Duration(seconds: 30));
      
      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        final results = result['results'] as List;
        
        int successCount = 0;
        for (int i = 0; i < results.length; i++) {
          final scanResult = results[i];
          if (scanResult['success'] == true) {
            await _localDB.markSecurityScanAsSynced(pendingScans[i]['id'] as int);
            successCount++;
          } else {
            await _localDB.deleteSecurityScan(pendingScans[i]['id'] as int);
          }
        }
        
        print('🔍 DEBUG: Batch sync completed. Success: $successCount/${pendingScans.length}');
        return successCount == pendingScans.length;
      }
      
      return false;
    } catch (e) {
      print('🔍 DEBUG: Batch sync error: $e');
      return false;
    }
  }

  // Timer for periodic sync
  static Timer? _syncTimer;

  void startPeriodicSync() {
    stopPeriodicSync();
    
    // Sync immediately
    backgroundSync();
    
    // Then sync every 5 minutes
    _syncTimer = Timer.periodic(Duration(minutes: 5), (timer) async {
      print('🔍 DEBUG: Periodic sync triggered');
      await backgroundSync();
    });
    
    print('🔍 DEBUG: Started periodic sync (every 5 minutes)');
  }

  void stopPeriodicSync() {
    _syncTimer?.cancel();
    _syncTimer = null;
    print('🔍 DEBUG: Stopped periodic sync');
  }

  Future<Map<String, dynamic>> fullSync() async {
    try {
      final isOnline = await _networkService.isConnected();
      if (!isOnline) {
        return {
          'success': false,
          'message': 'Offline - cannot sync',
          'details': {
            'student_data_synced': false,
            'pending_records_synced': false,
          }
        };
      }
      
      print('🔍 DEBUG: Starting full sync...');
      
      // 1. First sync student data for security/canteen roles
      final studentStatus = await getStudentDataStatus();
      final studentSyncSuccess = (studentStatus['sync_needed'] == true && 
                                 (studentStatus['role']?.toString().startsWith('security') == true ||
                                  studentStatus['role']?.toString().startsWith('canteen') == true))
          ? await checkAndSyncStudentData(forceSync: true)
          : true;
      
      // 2. Then sync pending records
      final pendingCount = await _localDB.getPendingRecordsCount();
      final pendingSyncSuccess = pendingCount > 0 ? await enhancedSync() : true;
      
      // Get counts for reporting
      final remainingPending = await _localDB.getPendingRecordsCount();
      final studentDataStatus = await getStudentDataStatus();
      
      final result = {
        'success': studentSyncSuccess && pendingSyncSuccess,
        'message': (studentSyncSuccess && pendingSyncSuccess && remainingPending == 0)
            ? 'Sync completed successfully' 
            : 'Sync completed with some issues',
        'details': {
          'student_data_synced': studentSyncSuccess,
          'student_data_available': studentDataStatus['has_data'],
          'student_count': studentDataStatus['student_count'],
          'pending_records_synced': pendingSyncSuccess,
          'pending_records_remaining': remainingPending,
        }
      };
      
      print('🔍 DEBUG: Full sync result: $result');
      return result;
    } catch (e) {
      print('🔍 DEBUG: Full sync error: $e');
      return {
        'success': false,
        'message': 'Sync failed: $e',
        'details': {
          'student_data_synced': false,
          'pending_records_synced': false,
        }
      };
    }
  }

  // Existing methods (keep them)
  Future<void> debugSyncStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token');
      final hostel = prefs.getString('hostel');
      final lastSync = prefs.getString('last_student_sync');
      final currentRole = prefs.getString('current_role');
      final currentHostelPref = prefs.getString('current_hostel');
      
      final pendingCount = await _localDB.getPendingRecordsCount();
      final isOnline = await _networkService.isConnected();
      
      // Get student data status
      final studentStatus = await getStudentDataStatus();
      
      print('🔍 🔍 🔍 DEBUG SYNC STATUS 🔍 🔍 🔍');
      print('Token exists: ${token != null}');
      if (token != null && token.length > 10) {
        print('Token (first 10 chars): ${token.substring(0, 10)}');
      } else if (token != null) {
        print('Token: $token');
      } else {
        print('Token (first 10 chars): null');
      }
      print('Hostel (from hostel key): $hostel');
      print('Hostel (from current_hostel key): $currentHostelPref');
      print('Current Role: $currentRole');
      print('Last student sync: $lastSync');
      print('Pending records: $pendingCount');
      print('Online: $isOnline');
      print('--- Student Data Status ---');
      print('Has student data: ${studentStatus['has_data']}');
      print('Student count: ${studentStatus['student_count']}');
      print('Sync needed: ${studentStatus['sync_needed']}');
      print('Synced hostel: ${studentStatus['synced_hostel']}');
      print('🔍 🔍 🔍 END DEBUG 🔍 🔍 🔍');
    } catch (e) {
      print('🔍 DEBUG: Error in debugSyncStatus: $e');
    }
  }

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

  Future<void> clearAllPendingScans() async {
    try {
      final pendingScans = await _localDB.getPendingSecurityScans();
      final pendingVisits = await _localDB.getPendingCanteenVisits();
      
      print('🔍 DEBUG: Clearing ${pendingScans.length} security scans and ${pendingVisits.length} canteen visits');
      
      for (final scan in pendingScans) {
        await _localDB.deleteSecurityScan(scan['id'] as int);
      }
      
      for (final visit in pendingVisits) {
        await _localDB.deleteCanteenVisit(visit['id'] as int);
      }
      
      print('🔍 DEBUG: All pending scans cleared successfully');
    } catch (e) {
      print('🔍 DEBUG: Error clearing pending scans: $e');
    }
  }

  Future<Map<String, dynamic>> getSyncStatus() async {
    try {
      final pendingCount = await _localDB.getPendingRecordsCount();
      final isOnline = await _networkService.isConnected();
      
      final prefs = await SharedPreferences.getInstance();
      final String? lastSyncPref = prefs.getString('last_student_sync');
      DateTime? lastSyncTime;
      
      if (lastSyncPref != null) {
        lastSyncTime = DateTime.parse(lastSyncPref);
      }
      
      // Get student data status
      final studentStatus = await getStudentDataStatus();
      
      return {
        'is_online': isOnline,
        'pending_records': pendingCount,
        'has_student_data': studentStatus['has_data'],
        'student_count': studentStatus['student_count'],
        'last_student_sync': lastSyncTime?.toIso8601String(),
        'last_student_sync_formatted': lastSyncTime != null 
            ? '${lastSyncTime.day}/${lastSyncTime.month}/${lastSyncTime.year} ${lastSyncTime.hour}:${lastSyncTime.minute}'
            : 'Never',
        'sync_needed': studentStatus['sync_needed'] || pendingCount > 0,
        'student_data_status': studentStatus,
      };
    } catch (e) {
      print('🔍 DEBUG: Error getting sync status: $e');
      return {
        'is_online': false,
        'pending_records': 0,
        'has_student_data': false,
        'student_count': 0,
        'last_student_sync': null,
        'last_student_sync_formatted': 'Error',
        'sync_needed': false,
        'student_data_status': {'has_data': false, 'error': e.toString()},
      };
    }
  }

  Future<void> clearStudentCache() async {
    try {
      print('🔍 DEBUG: Clearing student cache...');
      await _studentDB.clearAllStudents();
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('last_student_sync');
      await prefs.remove('synced_hostel');
      
      print('🔍 DEBUG: Student cache cleared successfully');
    } catch (e) {
      print('🔍 DEBUG: Error clearing student cache: $e');
    }
  }

  Future<Map<String, dynamic>?> getLocalStudent(String roll) async {
    try {
      return await _studentDB.getStudent(roll);
    } catch (e) {
      print('🔍 DEBUG: Error getting local student: $e');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getLocalStudentsByHostel(String hostel) async {
    try {
      return await _studentDB.getStudentsByHostel(hostel);
    } catch (e) {
      print('🔍 DEBUG: Error getting local students by hostel: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> manualSync() async {
    try {
      final isOnline = await _networkService.isConnected();
      if (!isOnline) {
        return {
          'success': false,
          'message': 'You are offline. Please connect to the internet and try again.',
          'type': 'manual'
        };
      }
      
      print('🔍 DEBUG: Starting manual sync...');
      
      final statusBefore = await getSyncStatus();
      
      final result = await fullSync();
      
      final statusAfter = await getSyncStatus();
      
      return {
        ...result,
        'type': 'manual',
        'status_before': statusBefore,
        'status_after': statusAfter,
        'timestamp': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      print('🔍 DEBUG: Manual sync error: $e');
      return {
        'success': false,
        'message': 'Manual sync failed: $e',
        'type': 'manual'
      };
    }
  }

  Future<void> backgroundSync() async {
    try {
      final isOnline = await _networkService.isConnected();
      if (!isOnline) {
        print('🔍 DEBUG: Offline - skipping background sync');
        return;
      }
      
      print('🔍 DEBUG: Starting background sync...');
      
      // Sync student data if needed (for security/canteen only)
      final studentStatus = await getStudentDataStatus();
      if (studentStatus['sync_needed'] == true && 
          (studentStatus['role']?.toString().startsWith('security') == true ||
           studentStatus['role']?.toString().startsWith('canteen') == true)) {
        await checkAndSyncStudentData();
      }
      
      // Sync pending records
      final pendingCount = await _localDB.getPendingRecordsCount();
      if (pendingCount > 0) {
        await enhancedSync();
      }
      
      print('🔍 DEBUG: Background sync completed');
    } catch (e) {
      print('🔍 DEBUG: Background sync error: $e');
    }
  }

  Future<bool> testSync() async {
    try {
      print('🔍 DEBUG: === TESTING SYNC ===');
      
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token');
      
      print('🔍 DEBUG: Test - Token exists: ${token != null}');
      
      if (token == null) {
        print('🔍 DEBUG: ❌ Test failed - missing token');
        return false;
      }
      
      // Test the offline validation endpoint
      final response = await http.post(
        Uri.parse('$kBaseUrl/api/student/validate-offline'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({'roll_no': 'TEST123'}),
      ).timeout(Duration(seconds: 10));
      
      print('🔍 DEBUG: Test API Status: ${response.statusCode}');
      print('🔍 DEBUG: Test API Response: ${response.body}');
      
      // 404 is acceptable (student not found)
      return response.statusCode == 200 || response.statusCode == 404;
    } catch (e) {
      print('🔍 DEBUG: Test sync error: $e');
      return false;
    }
  }
  
  // NEW: Force sync student data for current hostel
  Future<Map<String, dynamic>> forceSyncStudentData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? hostel = prefs.getString('hostel');
      final String? currentRole = prefs.getString('current_role');
      
      if (hostel == null) {
        return {
          'success': false,
          'message': 'No hostel information available'
        };
      }
      
      // Only allow for security and canteen roles
      final roleType = currentRole?.split('_')[0] ?? '';
      if (roleType != 'security' && roleType != 'canteen') {
        return {
          'success': false,
          'message': 'Student data sync is only available for security and canteen staff'
        };
      }
      
      print('🔍 DEBUG: Force syncing student data for Hostel $hostel...');
      
      final success = await syncAllStudentsComplete();
      
      if (success) {
        final count = await _studentDB.getStudentCountByHostel(hostel);
        return {
          'success': true,
          'message': 'Student data synced successfully',
          'hostel': hostel,
          'student_count': count,
          'timestamp': DateTime.now().toIso8601String()
        };
      } else {
        return {
          'success': false,
          'message': 'Failed to sync student data',
          'hostel': hostel
        };
      }
    } catch (e) {
      print('🔍 DEBUG: Error force syncing student data: $e');
      return {
        'success': false,
        'message': 'Error: $e'
      };
    }
  }
}