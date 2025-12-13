// student_db_helper.dart - UPDATED VERSION
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class StudentDBHelper {
  static final StudentDBHelper _instance = StudentDBHelper._internal();
  factory StudentDBHelper() => _instance;
  StudentDBHelper._internal();

  static Database? _database;
  bool _isInitialized = false;

  // Database configuration
  static const String _dbName = 'students.db';
  static const int _dbVersion = 2; // Updated version
  
  // Table and column names
  static const String _tableStudents = 'students';
  static const String _columnRoll = 'roll';
  static const String _columnName = 'name';
  static const String _columnHostel = 'hostel';
  static const String _columnLastUpdated = 'last_updated';
  static const String _columnSyncedAt = 'synced_at';

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    print('🔍 DEBUG: Initializing student database...');
    String path = join(await getDatabasesPath(), _dbName);
    
    return await openDatabase(
      path,
      version: _dbVersion,
      onCreate: _createTables,
      onUpgrade: _upgradeDatabase,
    );
  }

  Future<void> _createTables(Database db, int version) async {
    print('🔍 DEBUG: Creating student table for version $version');
    
    await db.execute('''
      CREATE TABLE $_tableStudents(
        $_columnRoll TEXT PRIMARY KEY,
        $_columnName TEXT NOT NULL,
        $_columnHostel TEXT NOT NULL,
        $_columnLastUpdated INTEGER NOT NULL,
        $_columnSyncedAt INTEGER
      )
    ''');
    
    // Create indexes for faster queries
    await db.execute('''
      CREATE INDEX idx_hostel ON $_tableStudents($_columnHostel)
    ''');
    
    await db.execute('''
      CREATE INDEX idx_hostel_roll ON $_tableStudents($_columnHostel, $_columnRoll)
    ''');
    
    print('🔍 DEBUG: Student table created successfully');
  }

  Future<void> _upgradeDatabase(Database db, int oldVersion, int newVersion) async {
    print('🔍 DEBUG: Upgrading student database from $oldVersion to $newVersion');
    
    if (oldVersion < 2) {
      // Add synced_at column
      await db.execute('''
        ALTER TABLE $_tableStudents ADD COLUMN $_columnSyncedAt INTEGER
      ''');
      
      print('🔍 DEBUG: Added synced_at column to student table');
    }
  }

  // Save/update student data
  Future<void> saveStudent({
    required String roll,
    required String name,
    required String hostel,
  }) async {
    try {
      final db = await database;
      await db.insert(
        _tableStudents,
        {
          _columnRoll: roll,
          _columnName: name,
          _columnHostel: hostel,
          _columnLastUpdated: DateTime.now().millisecondsSinceEpoch,
          _columnSyncedAt: DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      print('🔍 DEBUG: Student saved/updated: $roll ($hostel)');
    } catch (e) {
      print('🔍 DEBUG: Error saving student: $e');
    }
  }

  // Save multiple students at once (for batch sync)
  Future<void> saveStudents(List<Map<String, dynamic>> students) async {
    try {
      final db = await database;
      final batch = db.batch();
      final now = DateTime.now().millisecondsSinceEpoch;
      
      for (final student in students) {
        final roll = student['roll_no'] ?? student['roll'];
        final name = student['name'] ?? '';
        final hostel = student['hostel'] ?? '';
        
        if (roll.isNotEmpty && name.isNotEmpty && hostel.isNotEmpty) {
          batch.insert(
            _tableStudents,
            {
              _columnRoll: roll,
              _columnName: name,
              _columnHostel: hostel,
              _columnLastUpdated: now,
              _columnSyncedAt: now,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
      
      await batch.commit();
      print('🔍 DEBUG: Saved ${students.length} students to local DB');
    } catch (e) {
      print('🔍 DEBUG: Error saving students batch: $e');
    }
  }

  // NEW: Clear students for a specific hostel (for refresh)
  Future<void> clearStudentsByHostel(String hostel) async {
    try {
      final db = await database;
      final deleted = await db.delete(
        _tableStudents,
        where: '$_columnHostel = ?',
        whereArgs: [hostel],
      );
      print('🔍 DEBUG: Cleared $deleted students for hostel $hostel');
    } catch (e) {
      print('🔍 DEBUG: Error clearing students by hostel: $e');
    }
  }

  // Get student by roll number
  Future<Map<String, dynamic>?> getStudent(String roll) async {
    try {
      final db = await database;
      final result = await db.query(
        _tableStudents,
        where: '$_columnRoll = ?',
        whereArgs: [roll],
        limit: 1,
      );
      
      if (result.isNotEmpty) {
        final student = result.first;
        return {
          'roll_no': student[_columnRoll],
          'name': student[_columnName],
          'hostel': student[_columnHostel],
          'from_local_db': true,
          'last_updated': DateTime.fromMillisecondsSinceEpoch(student[_columnLastUpdated] as int),
          'synced_at': student[_columnSyncedAt] != null 
              ? DateTime.fromMillisecondsSinceEpoch(student[_columnSyncedAt] as int)
              : null,
        };
      }
      return null;
    } catch (e) {
      print('🔍 DEBUG: Error getting student: $e');
      return null;
    }
  }

  // Get all students in a specific hostel
  Future<List<Map<String, dynamic>>> getStudentsByHostel(String hostel) async {
    try {
      final db = await database;
      final result = await db.query(
        _tableStudents,
        where: '$_columnHostel = ?',
        whereArgs: [hostel],
        orderBy: '$_columnRoll ASC',
      );
      
      return result.map((row) => {
        'roll_no': row[_columnRoll],
        'name': row[_columnName],
        'hostel': row[_columnHostel],
      }).toList();
    } catch (e) {
      print('🔍 DEBUG: Error getting students by hostel: $e');
      return [];
    }
  }

  // NEW: Get count of students in a specific hostel
  Future<int> getStudentCountByHostel(String hostel) async {
    try {
      final db = await database;
      final count = Sqflite.firstIntValue(
        await db.rawQuery(
          'SELECT COUNT(*) FROM $_tableStudents WHERE $_columnHostel = ?',
          [hostel]
        )
      ) ?? 0;
      
      print('🔍 DEBUG: Student count for hostel $hostel: $count');
      return count;
    } catch (e) {
      print('🔍 DEBUG: Error getting student count by hostel: $e');
      return 0;
    }
  }

  // Get count of all students in database
  Future<int> getStudentCount() async {
    try {
      final db = await database;
      final count = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM $_tableStudents')
      ) ?? 0;
      
      print('🔍 DEBUG: Total student count in local DB: $count');
      return count;
    } catch (e) {
      print('🔍 DEBUG: Error getting student count: $e');
      return 0;
    }
  }

  // Get last sync timestamp for a hostel
  Future<DateTime?> getLastSyncTimeByHostel(String hostel) async {
    try {
      final db = await database;
      final result = await db.rawQuery('''
        SELECT MAX($_columnSyncedAt) as last_sync FROM $_tableStudents 
        WHERE $_columnHostel = ?
      ''', [hostel]);
      
      if (result.isNotEmpty && result.first['last_sync'] != null) {
        final timestamp = result.first['last_sync'] as int;
        return DateTime.fromMillisecondsSinceEpoch(timestamp);
      }
      return null;
    } catch (e) {
      print('🔍 DEBUG: Error getting last sync time by hostel: $e');
      return null;
    }
  }

  // Get overall last sync timestamp
  Future<DateTime?> getLastSyncTime() async {
    try {
      final db = await database;
      final result = await db.rawQuery('''
        SELECT MAX($_columnSyncedAt) as last_sync FROM $_tableStudents
      ''');
      
      if (result.isNotEmpty && result.first['last_sync'] != null) {
        final timestamp = result.first['last_sync'] as int;
        return DateTime.fromMillisecondsSinceEpoch(timestamp);
      }
      return null;
    } catch (e) {
      print('🔍 DEBUG: Error getting last sync time: $e');
      return null;
    }
  }

  // Delete student by roll
  Future<void> deleteStudent(String roll) async {
    try {
      final db = await database;
      await db.delete(
        _tableStudents,
        where: '$_columnRoll = ?',
        whereArgs: [roll],
      );
      print('🔍 DEBUG: Deleted student: $roll');
    } catch (e) {
      print('🔍 DEBUG: Error deleting student: $e');
    }
  }

  // Clear all students (for testing/reset)
  Future<void> clearAllStudents() async {
    try {
      final db = await database;
      await db.delete(_tableStudents);
      print('🔍 DEBUG: All students cleared from local DB');
    } catch (e) {
      print('🔍 DEBUG: Error clearing students: $e');
    }
  }

  // Check if student exists
  Future<bool> studentExists(String roll) async {
    try {
      final db = await database;
      final result = await db.query(
        _tableStudents,
        where: '$_columnRoll = ?',
        whereArgs: [roll],
        columns: [_columnRoll],
        limit: 1,
      );
      return result.isNotEmpty;
    } catch (e) {
      print('🔍 DEBUG: Error checking student existence: $e');
      return false;
    }
  }

  // NEW: Check if hostel has any data
  Future<bool> hostelHasData(String hostel) async {
    try {
      final count = await getStudentCountByHostel(hostel);
      return count > 0;
    } catch (e) {
      print('🔍 DEBUG: Error checking hostel data: $e');
      return false;
    }
  }

  // NEW: Get all distinct hostels in database
  Future<List<String>> getAllHostels() async {
    try {
      final db = await database;
      final result = await db.rawQuery('''
        SELECT DISTINCT $_columnHostel FROM $_tableStudents ORDER BY $_columnHostel
      ''');
      
      return result
          .map((row) => row[_columnHostel] as String)
          .where((hostel) => hostel.isNotEmpty)
          .toList();
    } catch (e) {
      print('🔍 DEBUG: Error getting all hostels: $e');
      return [];
    }
  }

  // NEW: Get student statistics
  Future<Map<String, dynamic>> getStudentStats() async {
    try {
      final db = await database;
      
      // Total count
      final totalResult = await db.rawQuery('SELECT COUNT(*) as count FROM $_tableStudents');
      final total = totalResult.isNotEmpty ? totalResult.first['count'] as int? ?? 0 : 0;
      
      // Count by hostel
      final hostelResult = await db.rawQuery('''
        SELECT $_columnHostel, COUNT(*) as count 
        FROM $_tableStudents 
        GROUP BY $_columnHostel 
        ORDER BY $_columnHostel
      ''');
      
      final Map<String, int> byHostel = {};
      for (final row in hostelResult) {
        final hostel = row[_columnHostel] as String? ?? 'Unknown';
        final count = row['count'] as int? ?? 0;
        byHostel[hostel] = count;
      }
      
      // Last update
      final lastUpdateResult = await db.rawQuery('''
        SELECT MAX($_columnLastUpdated) as last_updated FROM $_tableStudents
      ''');
      
      DateTime? lastUpdated;
      if (lastUpdateResult.isNotEmpty && lastUpdateResult.first['last_updated'] != null) {
        final timestamp = lastUpdateResult.first['last_updated'] as int;
        lastUpdated = DateTime.fromMillisecondsSinceEpoch(timestamp);
      }
      
      return {
        'total_students': total,
        'by_hostel': byHostel,
        'last_updated': lastUpdated?.toIso8601String(),
        'hostels_with_data': byHostel.keys.toList(),
      };
    } catch (e) {
      print('🔍 DEBUG: Error getting student stats: $e');
      return {
        'total_students': 0,
        'by_hostel': {},
        'last_updated': null,
        'hostels_with_data': [],
      };
    }
  }


  Future<void> debugDatabaseContents() async {
    try {
      final db = await database;
      
      // Get all students
      final allStudents = await db.query(_tableStudents);
      
      print('🔍 🔍 🔍 DATABASE DEBUG 🔍 🔍 🔍');
      print('Total students in DB: ${allStudents.length}');
      
      // Group by hostel
      final Map<String, List<Map<String, dynamic>>> byHostel = {};
      for (final student in allStudents) {
        final hostel = student[_columnHostel] as String? ?? 'Unknown';
        if (!byHostel.containsKey(hostel)) {
          byHostel[hostel] = [];
        }
        byHostel[hostel]!.add({
          'roll': student[_columnRoll],
          'name': student[_columnName],
          'hostel': hostel,
        });
      }
      
      for (final hostel in byHostel.keys) {
        print('Hostel $hostel (${byHostel[hostel]!.length} students):');
        for (final student in byHostel[hostel]!) {
          print('  ${student['roll']} - ${student['name']}');
        }
      }
      
      print('🔍 🔍 🔍 END DEBUG 🔍 🔍 🔍');
    } catch (e) {
      print('🔍 DEBUG: Error debugging database: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getAllStudents() async {
    try {
      final db = await database;
      final result = await db.query(
        _tableStudents,
        orderBy: '$_columnHostel ASC, $_columnRoll ASC',
      );
      
      return result.map((row) => {
        'roll_no': row[_columnRoll],
        'name': row[_columnName],
        'hostel': row[_columnHostel],
      }).toList();
    } catch (e) {
      print('🔍 DEBUG: Error getting all students: $e');
      return [];
    }
  }

}
