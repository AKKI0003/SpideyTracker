import 'package:flutter/material.dart';
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
  await PushNotificationService.init();

  runApp(const ProviderScope(child: SpiderTrackApp()));
}