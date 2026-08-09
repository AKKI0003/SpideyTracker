import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'login_screen.dart';
import 'username_screen.dart';
import 'home_placeholder_screen.dart';
import 'email_vrification_screen.dart';


final authStateProvider = StreamProvider<User?>((ref) {
  return FirebaseAuth.instance.authStateChanges();
});

final userDocProvider = StreamProvider<DocumentSnapshot<Map<String, dynamic>>?>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.when(
    data: (user) {
      if (user == null) return Stream.value(null);
      return FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots();
    },
    loading: () => Stream.value(null),
    error: (_, __) => Stream.value(null),
  );
});

class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  /// 'coupleId' is gone from new user docs — replaced by 'partyIds'
  /// (list) and 'activePartyId'. Existing users with the old field are
  /// simply ignored; PartyShell treats an empty partyIds list the same
  /// way regardless of any leftover coupleId value.
  Future<void> _ensureUserDoc(User user) async {
    final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);
    final snap = await ref.get();
    if (!snap.exists) {
      await ref.set({
        'displayName': user.email?.split('@').first ?? 'User',
        'email': user.email,
        'partyIds': <String>[],
        'activePartyId': null,
        'usernameSet': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);

    return authState.when(
      data: (user) {
        if (user == null) {
          return const LoginScreen();
        }

        _ensureUserDoc(user);

        final userDoc = ref.watch(userDocProvider);

        return userDoc.when(
          data: (doc) {
            if (doc == null || !doc.exists) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            final data = doc.data();
            final needsUsername = data?['usernameSet'] != true;
            if (needsUsername) {
              return const UsernameScreen();
            }
            final needsEmailVerification = data?['emailVerified'] != true;
            if (needsEmailVerification) {
              return const EmailVerificationScreen();
            }
            // Routing to onboarding-vs-map now happens inside
            // HomePlaceholderScreen -> PartyShell, since it needs to
            // watch the live 'parties' collection (arrayContains query),
            // not just this single user doc.
            return const HomePlaceholderScreen();
          },
          loading: () => const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          ),
          error: (err, _) => Scaffold(
            body: Center(child: Text('Error: $err')),
          ),
        );
      },
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (err, stack) =>
          Scaffold(body: Center(child: Text('Error: $err'))),
    );
  }
}
