import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import '../../firebase_options.dart';

/// Top-level background message handler invoked by Firebase Messaging when
/// the application is in the background or terminated.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint('[FCM Background] Message ID: ${message.messageId}');
    debugPrint('[FCM Background] Title: ${message.notification?.title}');
    debugPrint('[FCM Background] Body: ${message.notification?.body}');
    debugPrint('[FCM Background] Data: ${message.data}');
  } catch (e) {
    debugPrint('[FCM Background] Error handling background message: $e');
  }
}

/// Service managing Firebase Cloud Messaging (push notifications) for Hishobkr.
class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  FirebaseMessaging? _messaging;
  String? _fcmToken;
  String? get fcmToken => _fcmToken;

  final _messageController = StreamController<RemoteMessage>.broadcast();
  Stream<RemoteMessage> get onMessage => _messageController.stream;

  final _notificationOpenController = StreamController<RemoteMessage>.broadcast();
  Stream<RemoteMessage> get onNotificationOpened => _notificationOpenController.stream;

  bool _initialized = false;

  /// Initialize Firebase Messaging on supported platforms (Android, iOS, Web).
  Future<void> initialize() async {
    if (_initialized) return;

    // Push notifications via FCM are supported on Android, iOS, and Web.
    final isSupported = kIsWeb ||
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;

    if (!isSupported) {
      debugPrint('[FCM] Push notifications not supported on ${defaultTargetPlatform.name}');
      return;
    }

    try {
      _messaging = FirebaseMessaging.instance;

      // Register the background message handler
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      // Request notification permissions
      final settings = await _messaging!.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      debugPrint('[FCM] Permission status: ${settings.authorizationStatus}');

      // Enable foreground notification presentation (banners, sound, badge)
      await _messaging!.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      // Retrieve device registration token
      _fcmToken = await _messaging!.getToken();
      debugPrint('[FCM] Device Token: $_fcmToken');

      // Listen for token refreshes
      _messaging!.onTokenRefresh.listen((newToken) {
        _fcmToken = newToken;
        debugPrint('[FCM] Token refreshed: $newToken');
      });

      // Subscribe to default restaurant topics
      await subscribeToTopic('hishobkr_orders');

      // Foreground message listener
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('[FCM Foreground] Received: ${message.notification?.title} - ${message.notification?.body}');
        _messageController.add(message);
      });

      // Notification opened from background
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint('[FCM Opened] User tapped notification: ${message.data}');
        _notificationOpenController.add(message);
      });

      // Check if app was opened from terminated state via notification click
      final initialMessage = await _messaging!.getInitialMessage();
      if (initialMessage != null) {
        debugPrint('[FCM Initial] App opened from terminated message: ${initialMessage.data}');
        _notificationOpenController.add(initialMessage);
      }

      _initialized = true;
      debugPrint('[FCM] Push Notification Service initialized successfully.');
    } catch (e) {
      debugPrint('[FCM] Initialization warning: $e');
    }
  }

  /// Subscribe to a specific topic (e.g. outlet-specific alerts).
  Future<void> subscribeToTopic(String topic) async {
    if (_messaging == null || kIsWeb) return;
    try {
      await _messaging!.subscribeToTopic(topic);
      debugPrint('[FCM] Subscribed to topic: $topic');
    } catch (e) {
      debugPrint('[FCM] Failed to subscribe to topic $topic: $e');
    }
  }

  /// Unsubscribe from a topic.
  Future<void> unsubscribeFromTopic(String topic) async {
    if (_messaging == null || kIsWeb) return;
    try {
      await _messaging!.unsubscribeFromTopic(topic);
      debugPrint('[FCM] Unsubscribed from topic: $topic');
    } catch (e) {
      debugPrint('[FCM] Failed to unsubscribe from topic $topic: $e');
    }
  }

  void dispose() {
    _messageController.close();
    _notificationOpenController.close();
  }
}
