import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../data/party_repository.dart';
import '../domain/party_model.dart';
import 'party_onboarding_screen.dart';
import 'party_switcher_sheet.dart';
import '../../map_scanner/presentation/map_scanner_screen.dart';

final _partyRepoProvider = Provider((ref) => PartyRepository());

/// Replaces HomePlaceholderScreen. Watches the signed-in user's party
/// list and active party, then renders either the onboarding flow (zero
/// parties) or the map scoped to whichever party is active. A small
/// floating control lets the user open the switcher and change which
/// party is active at any time — switching never touches membership,
/// only which party's data is currently rendered.
class PartyShell extends ConsumerWidget {
  const PartyShell({super.key});

  void _openSwitcher(BuildContext context, List<PartyModel> parties, String activePartyId) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => PartySwitcherSheet(
        parties: parties,
        activePartyId: activePartyId,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox.shrink();

    final partyRepo = ref.watch(_partyRepoProvider);

    return StreamBuilder<List<PartyModel>>(
      stream: partyRepo.watchUserParties(user.uid),
      builder: (context, partiesSnap) {
        if (partiesSnap.hasError) {
          return Scaffold(
            backgroundColor: const Color(0xFF0A1128),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Could not load parties:\n${partiesSnap.error}',
                  style: const TextStyle(color: Colors.redAccent),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }
        if (!partiesSnap.hasData) {
          return const Scaffold(
            backgroundColor: Color(0xFF0A1128),
            body: Center(child: CircularProgressIndicator(color: Colors.cyanAccent)),
          );
        }

        final parties = partiesSnap.data!;
        if (parties.isEmpty) {
          return const PartyOnboardingScreen();
        }

        final user = FirebaseAuth.instance.currentUser;
        if (user == null) return const SizedBox.shrink();
        debugPrint('DEBUG uid querying parties with: "${user.uid}"');

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
          builder: (context, userSnap) {
            if (userSnap.hasError) {
              return Scaffold(
                backgroundColor: const Color(0xFF0A1128),
                body: Center(
                  child: Text('Could not load user data:\n${userSnap.error}',
                      style: const TextStyle(color: Colors.redAccent), textAlign: TextAlign.center),
                ),
              );
            }
            final activePartyId = userSnap.data?.data()?['activePartyId'] as String?;

            final resolvedActiveId = (activePartyId != null &&
                    parties.any((p) => p.id == activePartyId))
                ? activePartyId
                : parties.first.id;

            // Self-heal: if activePartyId is stale (party left/deleted)
            // or was never set, point it at a valid party instead of
            // leaving the user stuck on a blank screen.
            if (activePartyId != resolvedActiveId) {
              partyRepo.setActiveParty(uid: user.uid, partyId: resolvedActiveId);
            }

            return Stack(
              children: [
                MapScannerScreen(
                  key: ValueKey(resolvedActiveId),
                  partyId: resolvedActiveId,
                  onSwitchParty: () => _openSwitcher(context, parties, resolvedActiveId),
                ),
                Positioned(
                  top: 48,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: GestureDetector(
                      onTap: () => _openSwitcher(context, parties, resolvedActiveId),

                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.cyanAccent.withOpacity(0.4)),
                        ),
                        child: const Icon(Icons.swap_horiz, color: Colors.cyanAccent, size: 16),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
