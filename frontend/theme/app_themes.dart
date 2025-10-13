// app_themes.dart
import 'package:flutter/material.dart';

class AppThemes {
  // Light Theme
  static final ThemeData lightTheme = ThemeData(
    useMaterial3: false, // Set to false to avoid CardTheme issues
    brightness: Brightness.light,
    primaryColor: Color(0xFF1976D2),
    scaffoldBackgroundColor: Color(0xFFFAFAFA),
    appBarTheme: AppBarTheme(
      backgroundColor: Color(0xFF1976D2),
      foregroundColor: Colors.white,
      elevation: 2,
      centerTitle: true,
      iconTheme: IconThemeData(color: Colors.white),
      titleTextStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
    ),
    cardColor: Colors.white,
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey.shade400),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey.shade400),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Color(0xFF1976D2), width: 2),
      ),
      filled: true,
      fillColor: Colors.white,
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: Color(0xFF1976D2),
        foregroundColor: Colors.white,
        padding: EdgeInsets.symmetric(vertical: 14, horizontal: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        elevation: 2,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: Color(0xFF1976D2),
        padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: Color(0xFF1976D2),
      foregroundColor: Colors.white,
      elevation: 4,
    ),
    dividerTheme: DividerThemeData(
      color: Colors.grey.shade300,
      thickness: 1,
      space: 1,
    ),
  );

  // Dark Theme
  static final ThemeData darkTheme = ThemeData(
    useMaterial3: false, // Set to false to avoid CardTheme issues
    brightness: Brightness.dark,
    primaryColor: Color(0xFF90CAF9),
    scaffoldBackgroundColor: Color(0xFF121212),
    appBarTheme: AppBarTheme(
      backgroundColor: Color(0xFF1E1E1E),
      foregroundColor: Colors.white,
      elevation: 2,
      centerTitle: true,
      iconTheme: IconThemeData(color: Colors.white),
      titleTextStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
    ),
    cardColor: Color(0xFF1E1E1E),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey.shade600),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey.shade600),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Color(0xFF90CAF9), width: 2),
      ),
      filled: true,
      fillColor: Color(0xFF1E1E1E),
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: Color(0xFF0D47A1),
        foregroundColor: Colors.white,
        padding: EdgeInsets.symmetric(vertical: 14, horizontal: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        elevation: 2,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: Color(0xFF90CAF9),
        padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: Color(0xFF0D47A1),
      foregroundColor: Colors.white,
      elevation: 4,
    ),
    dividerTheme: DividerThemeData(
      color: Colors.grey.shade700,
      thickness: 1,
      space: 1,
    ),
  );

  // Role-based colors that work in both themes
  static Color getRoleColor(String role, BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    
    switch (role) {
      case 'admin':
        return isDark ? Color(0xFFBA68C8) : Color(0xFF9C27B0);
      case 'super':
        return isDark ? Color(0xFF64B5F6) : Color(0xFF2196F3);
      case 'canteen':
        return isDark ? Color(0xFF81C784) : Color(0xFF4CAF50);
      case 'security':
        return isDark ? Color(0xFFFFB74D) : Color(0xFFFF9800);
      default:
        return isDark ? Color(0xFF64B5F6) : Color(0xFF2196F3);
    }
  }

  // Hostel colors that work in both themes
  static Color getHostelColor(String hostel, BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    
    switch (hostel) {
      case 'A':
        return isDark ? Color(0xFFEF5350) : Color(0xFFF44336);
      case 'B':
        return isDark ? Color(0xFF64B5F6) : Color(0xFF2196F3);
      case 'C':
        return isDark ? Color(0xFF81C784) : Color(0xFF4CAF50);
      case 'D':
        return isDark ? Color(0xFFFFB74D) : Color(0xFFFF9800);
      case 'ALL':
        return isDark ? Color(0xFFBA68C8) : Color(0xFF9C27B0);
      default:
        return isDark ? Color(0xFF78909C) : Color(0xFF607D8B);
    }
  }
}
