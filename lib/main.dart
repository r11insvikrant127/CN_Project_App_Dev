// main.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'device_verification_screen.dart';
import 'biometric_auth_service.dart';
import 'theme_provider.dart';
import 'app_themes.dart';
import 'sync_service.dart'; // ⭐ ADD THIS IMPORT

// Firebase
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'notification_service.dart';

// Notifications
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:open_filex/open_filex.dart';

// Global notification plugin instance
final FlutterLocalNotificationsPlugin notificationPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 🔥 Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  const AndroidInitializationSettings androidInit =
    AndroidInitializationSettings('@mipmap/launcher_icon');

  const InitializationSettings initSettings =
      InitializationSettings(android: androidInit);

  await notificationPlugin.initialize(
    initSettings,
    onDidReceiveNotificationResponse: (NotificationResponse response) async {
      final filePath = response.payload;
      if (filePath != null) {
        OpenFilex.open(filePath); // Open PDF on notification tap
      }
    },
  );

  // 🔥 Initialize Firebase Cloud Messaging
  await NotificationService.initialize(notificationPlugin);
  
  await BiometricAuthService.init();

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // ⭐ CORRECT: Stop sync when ENTIRE APP closes
    final syncService = SyncService();
    syncService.stopPeriodicSync();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    // ⭐ HANDLE APP BACKGROUND/FOREGROUND
    final syncService = SyncService();
    
    if (state == AppLifecycleState.paused || 
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      // App going to background or closing
      syncService.stopPeriodicSync();
      print('🔍 DEBUG: App backgrounded - sync stopped');
    }
    // Note: Sync will automatically restart when app comes to foreground
    // because the timer continues running
  }

  // Global navigator key
  static final GlobalKey<NavigatorState> _navigatorKey =
      GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return MaterialApp(
            title: 'Student Management System',
            navigatorKey: _navigatorKey,
            theme: AppThemes.lightTheme,
            darkTheme: AppThemes.darkTheme,
            themeMode: themeProvider.themeMode,
            home: DeviceVerificationScreen(),
            debugShowCheckedModeBanner: false,
          );
        },
      ),
    );
  }
}