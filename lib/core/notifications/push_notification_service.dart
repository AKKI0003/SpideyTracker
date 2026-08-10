import 'package:flutter/foundation.dart';
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

    // Bug fix: on iOS, FirebaseMessaging.getToken() throws
    // [firebase_messaging/apns-token-not-set] if called before Apple's
    // push service has actually handed the device its APNs token —
    // which can take a beat after requestPermission() above, and
    // wasn't being waited for at all. Since this whole init() call
    // wasn't wrapped in a try/catch and is awaited directly in main()
    // before runApp(), that exception was going fully unhandled and
    // crashing startup itself — the widget tree never got a chance to
    // mount, which is exactly what a permanent white screen with no UI
    // at all looks like. Waiting for the APNs token first (iOS only;
    // Android doesn't have this concept and getAPNSToken() would just
    // return null forever there) fixes it properly instead of papering
    // over it.
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      await _waitForApnsToken();
    }

    await _registerToken();
    _messaging.onTokenRefresh.listen((_) => _registerToken());

    FirebaseMessaging.onMessage.listen(_showForegroundNotification);
  }

  /// Polls for up to ~10s for Apple to deliver the APNs token. In
  /// practice this resolves in well under a second on a real device;
  /// the loop is just a safety margin for slower devices/cold starts.
  /// If it never arrives (e.g. push permission was denied, or this is
  /// running somewhere without real APNs like some CI/simulator
  /// setups), we give up gracefully — push notifications simply won't
  /// work this session, but that's not worth crashing app startup over.
  static Future<void> _waitForApnsToken() async {
    for (int i = 0; i < 20; i++) {
      final apnsToken = await _messaging.getAPNSToken();
      if (apnsToken != null) return;
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  static Future<void> _registerToken() async {
    final user = FirebaseAuth.instance.currentUser;
    // Any failure here (permission denied, APNs still genuinely
    // unavailable, no network, etc.) should never take down app
    // startup — push notifications not working is a degraded
    // experience, not a reason the whole app should show a white
    // screen. Every other feature works fine without a token.
    String? token;
    try {
      token = await _messaging.getToken();
    } catch (e) {
      debugPrint('[PushNotificationService] getToken() failed, continuing without push: $e');
      return;
    }
    if (user == null || token == null) return;

    await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
      'fcmTokens': FieldValue.arrayUnion([token]),
    });
  }

  /// Call on sign-out so a shared/borrowed device stops receiving this
  /// user's pushes.
  static Future<void> unregisterToken() async {
    final user = FirebaseAuth.instance.currentUser;
    String? token;
    try {
      token = await _messaging.getToken();
    } catch (e) {
      debugPrint('[PushNotificationService] getToken() failed during unregister, skipping: $e');
      return;
    }
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