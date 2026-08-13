// notification_service.dart
// Firebase Cloud Messaging

import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;

class NotificationService {
  static final FirebaseMessaging _messaging =
      FirebaseMessaging.instance;
  /// Initialize Firebase Cloud Messaging.
  static Future<void> initialize(
    FlutterLocalNotificationsPlugin localNotifications,
  ) async {
    // Android 13+ requires notification permission.
    final NotificationSettings settings =
        await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      announcement: false,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
    );

    print(
      '🔔 FCM notification permission: '
      '${settings.authorizationStatus}',
    );

    // Get the FCM registration token.
    final String? token = await _messaging.getToken();

    print('📱 FCM TOKEN: $token');

    // Listen for token changes.
    _messaging.onTokenRefresh.listen((newToken) {
      print('🔄 FCM TOKEN REFRESHED: $newToken');
    });

    // Foreground messages.
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      print('📩 FCM foreground message received');

      print('Title: ${message.notification?.title}');
      print('Body: ${message.notification?.body}');
      print('Data: ${message.data}');

      final notification = message.notification;

      if (notification != null) {
        const AndroidNotificationDetails androidDetails =
            AndroidNotificationDetails(
          'fcm_alerts',
          'FCM Alerts',
          channelDescription:
              'Push notifications for student management alerts',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
        );

        const NotificationDetails notificationDetails =
            NotificationDetails(
          android: androidDetails,
        );

        await localNotifications.show(
          message.hashCode,
          notification.title ?? 'Student Management Alert',
          notification.body ?? 'New alert received',
          notificationDetails,
        );
      }
    });

    // Background message handler.
    FirebaseMessaging.onBackgroundMessage(
      firebaseMessagingBackgroundHandler,
    );

    // Message received when app is opened from background
    // by tapping an FCM notification.
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('👆 FCM notification tapped');
      print('Data: ${message.data}');
    });

    // Message that opened the app from a terminated state.
    final RemoteMessage? initialMessage =
        await _messaging.getInitialMessage();

    if (initialMessage != null) {
      print('🚀 App opened from FCM notification');
      print('Data: ${initialMessage.data}');
    }
  }

  /// Register the current Firebase FCM token with the backend.
  ///
  /// The backend determines the device_id from the authenticated JWT.
  /// Flutter only sends the FCM token.
  static Future<bool> registerFcmToken(String accessToken) async {
    try {
      final String? token = await _messaging.getToken();

      if (token == null || token.isEmpty) {
        print('⚠️ FCM token is null/empty');
        return false;
      }

      print('📱 Registering FCM token with backend...');
      print('📱 FCM TOKEN: $token');

      final response = await http.post(
        Uri.parse(
          'https://cn-project-app-dev.onrender.com/api/register-fcm-token',
        ),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode({
          'fcm_token': token,
        }),
      );

      print(
        '📱 FCM TOKEN REGISTRATION STATUS: '
        '${response.statusCode}',
      );

      print(
        '📱 FCM TOKEN REGISTRATION RESPONSE: '
        '${response.body}',
      );

      if (response.statusCode == 200) {
        print('✅ FCM token registered successfully');
        return true;
      }

      print('❌ FCM token registration failed');
      return false;
    } catch (e) {
      print(
        '❌ FCM token registration error: '
        '$e',
      );
      return false;
    }
  }
}

/// Must be a top-level function for Android background handling.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(
  RemoteMessage message,
) async {
  print('📩 FCM background message received');
  print('Title: ${message.notification?.title}');
  print('Body: ${message.notification?.body}');
  print('Data: ${message.data}');
}