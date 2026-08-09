# These rules exist purely as a safety net for release shrinking
# (isMinifyEnabled/isShrinkResources in build.gradle.kts). Most modern
# plugin AARs (Firebase, flutter_local_notifications, geolocator) ship
# their own consumer-proguard-rules.txt that R8 picks up automatically,
# so a lot of this is belt-and-suspenders — but the goal here is "don't
# break anything", so every plugin in pubspec.yaml that touches
# reflection, JNI, or JSON (de)serialization gets an explicit keep rule
# rather than trusting that alone.

# ---- Flutter's Play Store "deferred components" hooks ----
# Flutter's embedding always references com.google.android.play.core.*
# for optional dynamic-feature-module support, whether or not the app
# actually uses deferred components. This project doesn't, so those
# classes are absent from the build entirely — R8 flags that as
# "missing classes" by default. This isn't a real problem, just R8
# being unaware the reference is optional, so we tell it to stop
# treating it as an error instead of pulling in the whole Play Core
# library just to satisfy an unused code path.
-dontwarn com.google.android.play.core.**

# ---- Flutter engine plumbing ----
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# ---- Firebase (firebase_core, firebase_auth, cloud_firestore, firebase_messaging) ----
# Firestore in particular deserializes documents into POJOs via
# reflection — anything under com.google.firebase / com.google.android.gms
# needs to survive shrinking with its member names intact.
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# ---- flutter_local_notifications ----
-keep class com.dexterous.** { *; }

# ---- geolocator ----
-keep class com.baseflow.geolocator.** { *; }

# ---- flutter_secure_storage (relies on AndroidX Security / Keystore) ----
-keep class androidx.security.crypto.** { *; }

# ---- cryptography plugin (JNI + reflection-based cipher lookups) ----
-keep class com.github.dart_lang.**  { *; }
-keepclassmembers class * {
    native <methods>;
}

# ---- hive / hive_flutter (reflection-free, but keep type adapters safe) ----
-keep class * extends com.tekartik.**  { *; }

# ---- General: keep anything with a no-arg constructor referenced via
# reflection (covers Gson-style models some plugins use internally for
# platform channel payloads) ----
-keepclassmembers class * {
    public <init>();
}

# ---- Keep annotations & generic signatures — several plugins (Firebase
# especially) need these preserved to deserialize correctly. ----
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes InnerClasses
-keepattributes EnclosingMethod