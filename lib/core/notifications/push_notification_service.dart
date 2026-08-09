import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Handles the client side of push notifications: registering this
/// device's FCM token against the signed-in user, and displaying a
/// local notification when a push arrives while the app is in the
/// foreground (FCM notification payloads don't auto-display while
/// foregrounded on Android — this fills that gap).
///
/// The actual "send a push when a pin/message is created" logic lives
/// server-side in functions/index.js, since sending FCM pushes requires
/// the Admin SDK's server key — no client can (or should) do that
/// directly.
class PushNotificationService {
  static final _messaging = FirebaseMessaging.instance;
  static final _localNotifications = FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    await _messaging.requestPermission(alert: true, badge: true, sound: true);

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    await _localNotifications.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
    );

    const channel = AndroidNotificationChannel(
      'spidertrack_default',
      'SpiderTrack Alerts',
      description: 'Pin drops and party chat messages',
      importance: Importance.high,
    );
    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    await _registerToken();
    _messaging.onTokenRefresh.listen((_) => _registerToken());

    FirebaseMessaging.onMessage.listen(_showForegroundNotification);
  }

  static Future<void> _registerToken() async {
    final user = FirebaseAuth.instance.currentUser;
    final token = await _messaging.getToken();
    if (user == null || token == null) return;

    await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
      'fcmTokens': FieldValue.arrayUnion([token]),
    });
  }

  /// Call on sign-out so a shared/borrowed device stops receiving this
  /// user's pushes.
  static Future<void> unregisterToken() async {
    final user = FirebaseAuth.instance.currentUser;
    final token = await _messaging.getToken();
    if (user == null || token == null) return;

    await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
      'fcmTokens': FieldValue.arrayRemove([token]),
    });
  }

  static void _showForegroundNotification(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;

    _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'spidertrack_default',
          'SpiderTrack Alerts',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }
}

/// Must be a top-level function (not a class method) — register it in
/// main.dart with:
///   FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
/// before runApp(). This is what lets a push still show up when the app
/// is fully killed, not just backgrounded.
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // No work needed here for notification-type messages — the OS
  // displays them automatically when the app isn't in the foreground.
  // Kept as a named top-level function in case you need to react to
  // data-only payloads later.
}
