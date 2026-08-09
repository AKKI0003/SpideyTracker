import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'features/auth/presentation/auth_gate.dart';

/// A short, cheap fade instead of Flutter's default platform slide
/// transition (which also carries elevation-shadow compositing that
/// adds real cost). Also crucially avoids exposing the theme's default
/// surface color mid-transition — the actual source of the white flash
/// between screens, since our theme never explicitly declared itself
/// dark before.
class _FastFadeTransitionsBuilder extends PageTransitionsBuilder {
  const _FastFadeTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
      child: child,
    );
  }
}

class SpiderTrackApp extends StatelessWidget {
  const SpiderTrackApp({super.key});

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF0A1128);

    return MaterialApp(
      title: 'SpideyTracker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        // brightness: Brightness.dark here is the actual fix for the
        // white flash — without it, ColorScheme.fromSeed silently
        // produces a LIGHT scheme regardless of the seed color, so the
        // app's true default background was near-white the whole time.
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.red,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: navy,
        canvasColor: navy,
        dialogBackgroundColor: navy,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        // Applies the fast fade to every push/pop across the whole
        // app — Map → Chat, Map → Journal, Chat → back, everywhere —
        // without needing to touch each individual Navigator.push call.
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: _FastFadeTransitionsBuilder(),
            TargetPlatform.iOS: _FastFadeTransitionsBuilder(),
          },
        ),
      ),
      home: const AuthGate(),
    );
  }
}