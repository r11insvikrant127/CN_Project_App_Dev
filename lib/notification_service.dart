// notification_service.dart
// Firebase Cloud Messaging

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

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

  /// Subscribe this device to the notification topic
  /// corresponding to the supervisor's hostel.
  ///
  /// Hostel A → supervisor_hostel_a
  /// Hostel B → supervisor_hostel_b
  /// Hostel C → supervisor_hostel_c
  /// Hostel D → supervisor_hostel_d
  static Future<void> subscribeToSupervisorHostel(
    String hostel,
  ) async {
    final String normalizedHostel =
        hostel.trim().toUpperCase();

    const Map<String, String> topicMap = {
      'A': 'supervisor_hostel_a',
      'B': 'supervisor_hostel_b',
      'C': 'supervisor_hostel_c',
      'D': 'supervisor_hostel_d',
    };

    final String? topic = topicMap[normalizedHostel];

    if (topic == null) {
      throw ArgumentError(
        'Invalid hostel for supervisor notification: $hostel',
      );
    }

    await _messaging.subscribeToTopic(topic);

    print(
      '📢 Subscribed to supervisor topic: $topic',
    );
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