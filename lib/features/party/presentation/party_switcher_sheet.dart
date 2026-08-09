import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/widgets/pixel_button.dart';
import '../../../core/widgets/themed_dialog.dart';
import '../../../core/widgets/themed_snackbar.dart';
import '../domain/party_model.dart';
import '../data/party_repository.dart';

/// Functional first pass at the multi-party switcher: a scrollable list
/// of every party the user belongs to, with create/join/rename/leave
/// controls. This intentionally does NOT yet implement the
/// Discord/Instagram-style animated tab transitions described in the
/// Phase X visual spec (Feature 2) — that's a follow-up UI pass once
/// reference assets are available. This sheet is the functional
/// foundation it will sit on top of.
class PartySwitcherSheet extends StatelessWidget {
  final List<PartyModel> parties;
  final String? activePartyId;

  const PartySwitcherSheet({
    super.key,
    required this.parties,
    required this.activePartyId,
  });

  @override
  Widget build(BuildContext context) {
    final partyRepo = PartyRepository();
    final user = FirebaseAuth.instance.currentUser!;

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1128),
        border: const Border(
          top: BorderSide(color: Colors.blueAccent, width: 4),
          left: BorderSide(color: Colors.blueAccent, width: 4),
          right: BorderSide(color: Colors.blueAccent, width: 4),
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
        boxShadow: [BoxShadow(color: Colors.blueAccent.withOpacity(0.4), blurRadius: 20)],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('YOUR PARTIES', style: GoogleFonts.pressStart2p(fontSize: 12, color: Colors.cyanAccent)),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: parties.length,
                itemBuilder: (context, i) {
                  final party = parties[i];
                  final isActive = party.id == activePartyId;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: isActive ? Colors.blueAccent.withOpacity(0.15) : Colors.transparent,
                      border: Border.all(color: isActive ? Colors.cyanAccent : Colors.white24),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: InkWell(
                      onTap: () async {
                        await partyRepo.setActiveParty(uid: user.uid, partyId: party.id);
                        if (context.mounted) Navigator.pop(context);
                      },
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  party.name.toUpperCase(),
                                  style: GoogleFonts.pressStart2p(
                                    fontSize: 9,
                                    color: isActive ? Colors.cyanAccent : Colors.white70,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${party.memberUids.length}/${PartyModel.maxMembers} MEMBERS',
                                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                          PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert, color: Colors.white54, size: 18),
                            color: const Color(0xFF0A1128),
                            onSelected: (action) => _handleAction(context, action, party, partyRepo, user.uid),
                            itemBuilder: (context) => [
                              const PopupMenuItem(value: 'invite', child: Text('Show Invite Code', style: TextStyle(color: Colors.white))),
                              const PopupMenuItem(value: 'rename', child: Text('Rename', style: TextStyle(color: Colors.white))),
                              if (party.ownerUid == user.uid)
                                const PopupMenuItem(value: 'delete', child: Text('Delete Party', style: TextStyle(color: Colors.redAccent)))
                              else
                                const PopupMenuItem(value: 'leave', child: Text('Leave Party', style: TextStyle(color: Colors.redAccent))),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: PixelButton(
                    label: 'NEW PARTY',
                    fullWidth: true,
                    onTap: () async {
                      Navigator.pop(context);
                      final name = await showThemedTextInputDialog(
                        context,
                        title: 'NAME YOUR PARTY',
                        hint: 'e.g. Friend Group',
                        confirmLabel: 'CREATE',
                      );
                      if (name != null && name.isNotEmpty) {
                        await partyRepo.createParty(uid: user.uid, name: name);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: PixelButton(
                    label: 'JOIN CODE',
                    fullWidth: true,
                    onTap: () async {
                      Navigator.pop(context);
                      final code = await showThemedTextInputDialog(
                        context,
                        title: 'INVITE CODE',
                        hint: '6-character code',
                        confirmLabel: 'JOIN',
                      );
                      if (code != null && code.isNotEmpty) {
                        try {
                          await partyRepo.joinWithCode(uid: user.uid, rawCode: code);
                        } catch (e) {
                          if (context.mounted) {
                            showThemedSnack(context, e is PartyException ? e.message : 'Failed to join', tone: SnackTone.error);
                          }
                        }
                      }
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleAction(
    BuildContext context,
    String action,
    PartyModel party,
    PartyRepository partyRepo,
    String uid,
  ) async {
    switch (action) {
      case 'invite':
        showThemedInfoDialog(context, title: 'INVITE CODE', message: party.inviteCode);
        break;
      case 'rename':
        final newName = await showThemedTextInputDialog(
          context,
          title: 'RENAME PARTY',
          hint: party.name,
          confirmLabel: 'SAVE',
        );
        if (newName != null && newName.isNotEmpty) {
          await partyRepo.renameParty(partyId: party.id, newName: newName);
        }
        break;
      case 'leave':
        final confirmed = await showThemedConfirmDialog(
          context,
          title: 'LEAVE PARTY?',
          message: "You'll need a new invite code to rejoin ${party.name}.",
          confirmLabel: 'LEAVE',
        );
        if (confirmed) {
          try {
            await partyRepo.leaveParty(uid: uid, partyId: party.id);
          } catch (e) {
            if (context.mounted) {
              showThemedSnack(context, e is PartyException ? e.message : 'Failed to leave', tone: SnackTone.error);
            }
          }
        }
        break;
      case 'delete':
        final confirmed = await showThemedConfirmDialog(
          context,
          title: 'DELETE PARTY?',
          message: "This removes ${party.name} for every member. This can't be undone.",
          confirmLabel: 'DELETE',
        );
        if (confirmed) {
          try {
            await partyRepo.deleteParty(uid: uid, partyId: party.id);
          } catch (e) {
            if (context.mounted) {
              showThemedSnack(context, e is PartyException ? e.message : 'Failed to delete', tone: SnackTone.error);
            }
          }
        }
        break;
    }
  }
}
