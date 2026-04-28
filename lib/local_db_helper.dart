// local_db_helper.dart
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class LocalDBHelper {
  static final LocalDBHelper _instance = LocalDBHelper._internal();
  factory LocalDBHelper() => _instance;
  LocalDBHelper._internal();

  static Database? _database;
  bool _isInitialized = false;

  // Database configuration
  static const String _dbName = 'offline_records.db';
  static const int _dbVersion = 3;
  
  // Table names
  static const String _tableSecurityScans = 'security_scans';
  static const String _tableCanteenVisits = 'canteen_visits';
  
  // Common column names
  static const String _columnId = 'id';
  static const String _columnRollNo = 'roll_no';
  static const String _columnRole = 'role';
  static const String _columnTimestamp = 'timestamp';
  static const String _columnIsSynced = 'is_synced';
  static const String _columnSyncError = 'sync_error';
  
  // Security scans specific columns
  static const String _columnAction = 'action';
  static const String _columnActionType = 'action_type';
  
  // Canteen visits specific columns
  static const String _columnVisitType = 'visit_type';
  
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    print('🔍 DEBUG: Initializing database...');
    String path = join(await getDatabasesPath(), _dbName);
    
    return await openDatabase(
      path,
      version: _dbVersion,
      onCreate: _createTables,
      onUpgrade: _upgradeDatabase,
    );
  }

  Future<void> _createTables(Database db, int version) async {
    print('🔍 DEBUG: Creating tables for version $version');
    
    // Security Scans Table
    await db.execute('''
      CREATE TABLE $_tableSecurityScans(
        $_columnId INTEGER PRIMARY KEY AUTOINCREMENT,
        $_columnRollNo TEXT NOT NULL,
        $_columnAction TEXT NOT NULL,
        $_columnRole TEXT NOT NULL,
        $_columnTimestamp INTEGER NOT NULL,
        $_columnIsSynced INTEGER DEFAULT 0,
        $_columnSyncError TEXT,
        $_columnActionType TEXT DEFAULT 'security'
      )
    ''');
    
    // Canteen Visits Table
    await db.execute('''
      CREATE TABLE $_tableCanteenVisits(
        $_columnId INTEGER PRIMARY KEY AUTOINCREMENT,
        $_columnRollNo TEXT NOT NULL,
        $_columnRole TEXT NOT NULL,
        $_columnTimestamp INTEGER NOT NULL,
        $_columnIsSynced INTEGER DEFAULT 0,
        $_columnSyncError TEXT,
        $_columnVisitType TEXT DEFAULT 'canteen'
      )
    ''');
    
    // Create indexes for faster queries
    await db.execute('''
      CREATE INDEX idx_security_sync ON $_tableSecurityScans($_columnIsSynced, $_columnTimestamp)
    ''');
    
    await db.execute('''
      CREATE INDEX idx_canteen_sync ON $_tableCanteenVisits($_columnIsSynced, $_columnTimestamp)
    ''');
    
    print('🔍 DEBUG: Tables created successfully');
  }

  Future<void> _upgradeDatabase(Database db, int oldVersion, int newVersion) async {
    print('🔍 DEBUG: Upgrading database from $oldVersion to $newVersion');
    
    if (oldVersion < 2) {
      // Add action_type column for version 2
      await db.execute('''
        ALTER TABLE $_tableSecurityScans ADD COLUMN $_columnActionType TEXT DEFAULT 'security'
      ''');
      
      await db.execute('''
        ALTER TABLE $_tableCanteenVisits ADD COLUMN $_columnVisitType TEXT DEFAULT 'canteen'
      ''');
    }
    
    if (oldVersion < 3) {
      // Add sync_error column for version 3
      await db.execute('''
        ALTER TABLE $_tableSecurityScans ADD COLUMN $_columnSyncError TEXT
      ''');
      
      await db.execute('''
        ALTER TABLE $_tableCanteenVisits ADD COLUMN $_columnSyncError TEXT
      ''');
    }
  }

  // Save security scan (check in/out)
  Future<int> saveSecurityScan({
    required String rollNo,
    required String action,
    required String role,
    required DateTime timestamp,
    String? syncError,
  }) async {
    try {
      final db = await database;
      final id = await db.insert(
        _tableSecurityScans,
        {
          _columnRollNo: rollNo,
          _columnAction: action,
          _columnRole: role,
          _columnTimestamp: timestamp.millisecondsSinceEpoch,
          _columnIsSynced: 0,
          _columnSyncError: syncError,
          _columnActionType: 'security',
        },
      );
      
      print('🔍 DEBUG: Saved security scan - Roll: $rollNo, Action: $action, ID: $id');
      return id;
    } catch (e) {
      print('🔍 DEBUG: Error saving security scan: $e');
      rethrow;
    }
  }

  // Save canteen visit
  Future<int> saveCanteenVisit({
    required String rollNo,
    required String role,
    required DateTime timestamp,
    String? syncError,
  }) async {
    try {
      final db = await database;
      final id = await db.insert(
        _tableCanteenVisits,
        {
          _columnRollNo: rollNo,
          _columnRole: role,
          _columnTimestamp: timestamp.millisecondsSinceEpoch,
          _columnIsSynced: 0,
          _columnSyncError: syncError,
          _columnVisitType: 'canteen',
        },
      );
      
      print('🔍 DEBUG: Saved canteen visit - Roll: $rollNo, ID: $id');
      return id;
    } catch (e) {
      print('🔍 DEBUG: Error saving canteen visit: $e');
      rethrow;
    }
  }

  // Get all pending security scans
  Future<List<Map<String, dynamic>>> getPendingSecurityScans() async {
    try {
      final db = await database;
      final result = await db.query(
        _tableSecurityScans,
        where: '$_columnIsSynced = 0',
        orderBy: '$_columnTimestamp ASC',
      );
      
      return result.map((row) => _mapSecurityScanRow(row)).toList();
    } catch (e) {
      print('🔍 DEBUG: Error getting pending security scans: $e');
      return [];
    }
  }

  // Get recent security scans
  Future<List<Map<String, dynamic>>> getRecentSecurityScans({int limit = 10}) async {
    try {
      final db = await database;
      final result = await db.query(
        _tableSecurityScans,
        orderBy: '$_columnTimestamp DESC',
        limit: limit,
      );
      
      return result.map((row) => _mapSecurityScanRow(row)).toList();
    } catch (e) {
      print('🔍 DEBUG: Error getting recent security scans: $e');
      return [];
    }
  }

  // Get all pending canteen visits
  Future<List<Map<String, dynamic>>> getPendingCanteenVisits() async {
    try {
      final db = await database;
      final result = await db.query(
        _tableCanteenVisits,
        where: '$_columnIsSynced = 0',
        orderBy: '$_columnTimestamp ASC',
      );
      
      return result.map((row) => _mapCanteenVisitRow(row)).toList();
    } catch (e) {
      print('🔍 DEBUG: Error getting pending canteen visits: $e');
      return [];
    }
  }

  // Get total count of pending records
  Future<int> getPendingRecordsCount() async {
    try {
      final db = await database;
      
      final securityCount = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM $_tableSecurityScans WHERE $_columnIsSynced = 0')
      ) ?? 0;
      
      final canteenCount = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM $_tableCanteenVisits WHERE $_columnIsSynced = 0')
      ) ?? 0;
      
      final total = securityCount + canteenCount;
      print('🔍 DEBUG: Pending records - Security: $securityCount, Canteen: $canteenCount');
      return total;
    } catch (e) {
      print('🔍 DEBUG: Error getting pending records count: $e');
      return 0;
    }
  }

  // Mark security scan as synced
  Future<void> markSecurityScanAsSynced(int id) async {
    try {
      final db = await database;
      await db.update(
        _tableSecurityScans,
        {_columnIsSynced: 1, _columnSyncError: null},
        where: '$_columnId = ?',
        whereArgs: [id],
      );
      
      print('🔍 DEBUG: Marked security scan $id as synced');
    } catch (e) {
      print('🔍 DEBUG: Error marking security scan as synced: $e');
    }
  }

  // Mark canteen visit as synced
  Future<void> markCanteenVisitAsSynced(int id) async {
    try {
      final db = await database;
      await db.update(
        _tableCanteenVisits,
        {_columnIsSynced: 1, _columnSyncError: null},
        where: '$_columnId = ?',
        whereArgs: [id],
      );
      
      print('🔍 DEBUG: Marked canteen visit $id as synced');
    } catch (e) {
      print('🔍 DEBUG: Error marking canteen visit as synced: $e');
    }
  }

  // Update sync error for security scan
  Future<void> updateSecurityScanError(int id, String error) async {
    try {
      final db = await database;
      await db.update(
        _tableSecurityScans,
        {_columnSyncError: error},
        where: '$_columnId = ?',
        whereArgs: [id],
      );
      
      print('🔍 DEBUG: Updated security scan $id error: $error');
    } catch (e) {
      print('🔍 DEBUG: Error updating security scan error: $e');
    }
  }

  // Update sync error for canteen visit
  Future<void> updateCanteenVisitError(int id, String error) async {
    try {
      final db = await database;
      await db.update(
        _tableCanteenVisits,
        {_columnSyncError: error},
        where: '$_columnId = ?',
        whereArgs: [id],
      );
      
      print('🔍 DEBUG: Updated canteen visit $id error: $error');
    } catch (e) {
      print('🔍 DEBUG: Error updating canteen visit error: $e');
    }
  }

  // Delete security scan
  Future<void> deleteSecurityScan(int id) async {
    try {
      final db = await database;
      await db.delete(
        _tableSecurityScans,
        where: '$_columnId = ?',
        whereArgs: [id],
      );
      
      print('🔍 DEBUG: Deleted security scan $id');
    } catch (e) {
      print('🔍 DEBUG: Error deleting security scan: $e');
    }
  }

  // Delete canteen visit
  Future<void> deleteCanteenVisit(int id) async {
    try {
      final db = await database;
      await db.delete(
        _tableCanteenVisits,
        where: '$_columnId = ?',
        whereArgs: [id],
      );
      
      print('🔍 DEBUG: Deleted canteen visit $id');
    } catch (e) {
      print('🔍 DEBUG: Error deleting canteen visit: $e');
    }
  }

  // Clear all pending scans (for manual cleanup)
  Future<void> clearAllPendingScans() async {
    try {
      final db = await database;
      await db.delete(_tableSecurityScans, where: '$_columnIsSynced = 0');
      await db.delete(_tableCanteenVisits, where: '$_columnIsSynced = 0');
      
      print('🔍 DEBUG: Cleared all pending scans');
    } catch (e) {
      print('🔍 DEBUG: Error clearing pending scans: $e');
    }
  }

  // Reset database (for testing)
  Future<void> resetDatabase() async {
    try {
      final db = await database;
      await db.delete(_tableSecurityScans);
      await db.delete(_tableCanteenVisits);
      
      print('🔍 DEBUG: Database reset successfully');
    } catch (e) {
      print('🔍 DEBUG: Error resetting database: $e');
    }
  }

  // Get sync status summary
  Future<Map<String, dynamic>> getSyncStatus() async {
    try {
      final db = await database;
      
      final pendingSecurity = await getPendingSecurityScans();
      final pendingCanteen = await getPendingCanteenVisits();
      
      final totalSecurity = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM $_tableSecurityScans')
      ) ?? 0;
      
      final totalCanteen = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM $_tableCanteenVisits')
      ) ?? 0;
      
      return {
        'pending_security': pendingSecurity.length,
        'pending_canteen': pendingCanteen.length,
        'total_pending': pendingSecurity.length + pendingCanteen.length,
        'total_security': totalSecurity,
        'total_canteen': totalCanteen,
        'total_all': totalSecurity + totalCanteen,
      };
    } catch (e) {
      print('🔍 DEBUG: Error getting sync status: $e');
      return {
        'pending_security': 0,
        'pending_canteen': 0,
        'total_pending': 0,
        'total_security': 0,
        'total_canteen': 0,
        'total_all': 0,
      };
    }
  }

  // Helper method to map security scan row
  Map<String, dynamic> _mapSecurityScanRow(Map<String, dynamic> row) {
    return {
      'id': row[_columnId],
      'roll_no': row[_columnRollNo],
      'action': row[_columnAction],
      'role': row[_columnRole],
      'timestamp': DateTime.fromMillisecondsSinceEpoch(row[_columnTimestamp] as int),
      'is_synced': row[_columnIsSynced] == 1,
      'sync_error': row[_columnSyncError],
      'action_type': row[_columnActionType],
    };
  }

  // Helper method to map canteen visit row
  Map<String, dynamic> _mapCanteenVisitRow(Map<String, dynamic> row) {
    return {
      'id': row[_columnId],
      'roll_no': row[_columnRollNo],
      'role': row[_columnRole],
      'timestamp': DateTime.fromMillisecondsSinceEpoch(row[_columnTimestamp] as int),
      'is_synced': row[_columnIsSynced] == 1,
      'sync_error': row[_columnSyncError],
      'visit_type': row[_columnVisitType],
    };
  }

  // Get all synced records (for debugging)
  Future<List<Map<String, dynamic>>> getSyncedSecurityScans() async {
    try {
      final db = await database;
      final result = await db.query(
        _tableSecurityScans,
        where: '$_columnIsSynced = 1',
        orderBy: '$_columnTimestamp DESC',
        limit: 50,
      );
      
      return result.map((row) => _mapSecurityScanRow(row)).toList();
    } catch (e) {
      print('🔍 DEBUG: Error getting synced security scans: $e');
      return [];
    }
  }

  // Get all synced canteen visits
  Future<List<Map<String, dynamic>>> getSyncedCanteenVisits() async {
    try {
      final db = await database;
      final result = await db.query(
        _tableCanteenVisits,
        where: '$_columnIsSynced = 1',
        orderBy: '$_columnTimestamp DESC',
        limit: 50,
      );
      
      return result.map((row) => _mapCanteenVisitRow(row)).toList();
    } catch (e) {
      print('🔍 DEBUG: Error getting synced canteen visits: $e');
      return [];
    }
  }

  // Get record by ID
  Future<Map<String, dynamic>?> getSecurityScanById(int id) async {
    try {
      final db = await database;
      final result = await db.query(
        _tableSecurityScans,
        where: '$_columnId = ?',
        whereArgs: [id],
        limit: 1,
      );
      
      if (result.isNotEmpty) {
        return _mapSecurityScanRow(result.first);
      }
      return null;
    } catch (e) {
      print('🔍 DEBUG: Error getting security scan by ID: $e');
      return null;
    }
  }

  // Check if record exists
  Future<bool> securityScanExists(String rollNo, String action, DateTime timestamp) async {
    try {
      final db = await database;
      final result = await db.query(
        _tableSecurityScans,
        where: '$_columnRollNo = ? AND $_columnAction = ? AND $_columnTimestamp = ?',
        whereArgs: [rollNo, action, timestamp.millisecondsSinceEpoch],
        limit: 1,
      );
      
      return result.isNotEmpty;
    } catch (e) {
      print('🔍 DEBUG: Error checking if scan exists: $e');
      return false;
    }
  }
}