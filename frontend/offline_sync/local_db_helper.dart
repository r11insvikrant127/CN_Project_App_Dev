//local_db_helper.dart

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class LocalDBHelper {
  static final LocalDBHelper _instance = LocalDBHelper._internal();
  factory LocalDBHelper() => _instance;
  LocalDBHelper._internal();

  static Database? _database;
  bool _isInitialized = false;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    print('🔍 DEBUG: Initializing database...');
    String path = join(await getDatabasesPath(), 'student_scans.db');
    
    // Delete existing database to force recreation (remove this after testing)
    // await deleteDatabase(path);
    
    return await openDatabase(
      path,
      version: 2, // INCREASE VERSION NUMBER
      onCreate: _createTables,
      onUpgrade: _upgradeDatabase,
    );
  }

  Future<void> _createTables(Database db, int version) async {
    print('🔍 DEBUG: Creating tables for version $version');
    
    await db.execute('''
      CREATE TABLE pending_scans(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        roll_no TEXT NOT NULL,
        action TEXT NOT NULL,
        role TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        is_synced INTEGER DEFAULT 0,
        sync_timestamp INTEGER,
        created_at INTEGER DEFAULT (strftime('%s', 'now'))
      )
    ''');

    await db.execute('''
      CREATE TABLE canteen_visits(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        roll_no TEXT NOT NULL,
        student_hostel TEXT,
        canteen_hostel TEXT,
        role TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        is_unauthorized INTEGER DEFAULT 0,
        is_synced INTEGER DEFAULT 0,
        sync_timestamp INTEGER,
        created_at INTEGER DEFAULT (strftime('%s', 'now'))
      )
    ''');
    
    print('🔍 DEBUG: Tables created successfully');
  }

  Future<void> _upgradeDatabase(Database db, int oldVersion, int newVersion) async {
    print('🔍 DEBUG: Upgrading database from $oldVersion to $newVersion');
    
    if (oldVersion < 2) {
      // Drop old tables and recreate
      await db.execute('DROP TABLE IF EXISTS pending_scans');
      await db.execute('DROP TABLE IF EXISTS canteen_visits');
      await _createTables(db, newVersion);
    }
  }

  // Security scan methods
  Future<int> saveSecurityScan({
    required String rollNo,
    required String action,
    required String role,
    required DateTime timestamp,
  }) async {
    try {
      print('🔍 DEBUG: Saving security scan for $rollNo, action: $action');
      final db = await database;
      final result = await db.insert('pending_scans', {
        'roll_no': rollNo,
        'action': action,
        'role': role,
        'timestamp': timestamp.millisecondsSinceEpoch,
        'is_synced': 0,
      });
      print('🔍 DEBUG: Security scan saved with ID: $result');
      return result;
    } catch (e) {
      print('🔍 DEBUG: Error saving security scan: $e');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getPendingSecurityScans() async {
    try {
      final db = await database;
      final result = await db.query(
        'pending_scans',
        where: 'is_synced = ?',
        whereArgs: [0],
      );
      print('🔍 DEBUG: Found ${result.length} pending security scans');
      return result;
    } catch (e) {
      print('🔍 DEBUG: Error getting pending scans: $e');
      return [];
    }
  }

  Future<void> markSecurityScanAsSynced(int id) async {
    try {
      final db = await database;
      await db.update(
        'pending_scans',
        {
          'is_synced': 1,
          'sync_timestamp': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      print('🔍 DEBUG: Marked scan $id as synced');
    } catch (e) {
      print('🔍 DEBUG: Error marking scan as synced: $e');
    }
  }

  // Canteen visit methods
  Future<int> saveCanteenVisit({
    required String rollNo,
    required String studentHostel,
    required String canteenHostel,
    required String role,
    required DateTime timestamp,
    required bool isUnauthorized,
  }) async {
    try {
      print('🔍 DEBUG: Saving canteen visit for $rollNo');
      final db = await database;
      final result = await db.insert('canteen_visits', {
        'roll_no': rollNo,
        'student_hostel': studentHostel,
        'canteen_hostel': canteenHostel,
        'role': role,
        'timestamp': timestamp.millisecondsSinceEpoch,
        'is_unauthorized': isUnauthorized ? 1 : 0,
        'is_synced': 0,
      });
      print('🔍 DEBUG: Canteen visit saved with ID: $result');
      return result;
    } catch (e) {
      print('🔍 DEBUG: Error saving canteen visit: $e');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getPendingCanteenVisits() async {
    try {
      final db = await database;
      final result = await db.query(
        'canteen_visits',
        where: 'is_synced = ?',
        whereArgs: [0],
      );
      print('🔍 DEBUG: Found ${result.length} pending canteen visits');
      return result;
    } catch (e) {
      print('🔍 DEBUG: Error getting pending visits: $e');
      return [];
    }
  }

  Future<void> markCanteenVisitAsSynced(int id) async {
    try {
      final db = await database;
      await db.update(
        'canteen_visits',
        {
          'is_synced': 1,
          'sync_timestamp': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      print('🔍 DEBUG: Marked visit $id as synced');
    } catch (e) {
      print('🔍 DEBUG: Error marking visit as synced: $e');
    }
  }

  Future<int> getPendingRecordsCount() async {
    try {
      final db = await database;
      
      // Check if tables exist
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND (name='pending_scans' OR name='canteen_visits')"
      );
      
      if (tables.length < 2) {
        print('🔍 DEBUG: Tables not found, recreating...');
        await _createTables(db, 2);
        return 0;
      }
      
      final securityCount = Sqflite.firstIntValue(await db.rawQuery(
        'SELECT COUNT(*) FROM pending_scans WHERE is_synced = 0'
      )) ?? 0;
      
      final canteenCount = Sqflite.firstIntValue(await db.rawQuery(
        'SELECT COUNT(*) FROM canteen_visits WHERE is_synced = 0'
      )) ?? 0;
      
      print('🔍 DEBUG: Pending records - Security: $securityCount, Canteen: $canteenCount');
      return securityCount + canteenCount;
    } catch (e) {
      print('🔍 DEBUG: Error getting pending count: $e');
      return 0;
    }
  }

  // Method to reset database (for testing)
  Future<void> resetDatabase() async {
    try {
      final db = await database;
      await db.execute('DROP TABLE IF EXISTS pending_scans');
      await db.execute('DROP TABLE IF EXISTS canteen_visits');
      await _createTables(db, 2);
      print('🔍 DEBUG: Database reset successfully');
    } catch (e) {
      print('🔍 DEBUG: Error resetting database: $e');
    }
  }
}
