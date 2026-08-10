import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';
import 'app.dart';
import 'core/chat/local_chat_store.dart';
import 'core/notifications/push_notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Must be registered before runApp() — this is what lets a push
  // notification still show up when the app is fully killed, not just
  // backgrounded.
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // Sets up the encrypted-at-rest local chat database. Must finish
  // before any screen tries to read/write chat history.
  await LocalChatStore.init();

  // Registers this device's FCM token so Cloud Functions can push to
  // it; safe to call even if the user isn't signed in yet (it's a
  // no-op until they are — see PushNotificationService._registerToken).
  //
  // Wrapped defensively: push notifications are a nice-to-have, not
  // something the rest of the app depends on. An unhandled exception
  // here previously ran before runApp() and crashed the whole startup
  // with a permanent white screen (see push_notification_service.dart
  // for the actual root cause + fix) — this try/catch is a second
  // layer of protection so no future failure in this subsystem can
  // ever take the whole app down with it again.
  try {
    await PushNotificationService.init();
  } catch (e, st) {
    debugPrint('PushNotificationService.init() failed, continuing without push notifications: $e\n$st');
  }

  runApp(const ProviderScope(child: SpiderTrackApp()));
}