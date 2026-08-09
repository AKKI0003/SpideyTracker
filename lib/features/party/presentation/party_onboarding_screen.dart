import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/widgets/pixel_button.dart';
import '../../../core/widgets/themed_snackbar.dart';
import '../../map_scanner/presentation/widgets/spider_mask_icon.dart';
import '../data/party_repository.dart';

/// Replaces the old single-purpose PairingScreen. Shown whenever the
/// user belongs to zero parties — either brand new, or after leaving
/// their last one. Functionally equivalent to the old pairing flow
/// (generate code / enter code) but creates or joins a PartyModel
/// instead of a couple, and lets the user name their party.
class PartyOnboardingScreen extends StatefulWidget {
  const PartyOnboardingScreen({super.key});

  @override
  State<PartyOnboardingScreen> createState() => _PartyOnboardingScreenState();
}

class _PartyOnboardingScreenState extends State<PartyOnboardingScreen> {
  final _partyRepo = PartyRepository();
  final _nameController = TextEditingController();
  final _codeController = TextEditingController();
  bool _isCreating = false;
  bool _isJoining = false;
  bool _showCreateForm = false;

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _createParty() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      showThemedSnack(context, 'Give your party a name', tone: SnackTone.error);
      return;
    }
    setState(() => _isCreating = true);
    try {
      final user = FirebaseAuth.instance.currentUser!;
      await _partyRepo.createParty(uid: user.uid, name: name);
      if (mounted) showThemedSnack(context, 'PARTY CREATED', tone: SnackTone.success);
    } catch (e) {
      if (mounted) showThemedSnack(context, 'Failed to create party', tone: SnackTone.error);
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  Future<void> _joinParty() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      showThemedSnack(context, 'Enter an invite code', tone: SnackTone.error);
      return;
    }
    setState(() => _isJoining = true);
    try {
      final user = FirebaseAuth.instance.currentUser!;
      await _partyRepo.joinWithCode(uid: user.uid, rawCode: code);
      if (mounted) showThemedSnack(context, 'SPIDER LINK ESTABLISHED', tone: SnackTone.success);
    } catch (e) {
      if (mounted) {
        showThemedSnack(context, e is PartyException ? e.message : 'Failed to join', tone: SnackTone.error);
      }
    } finally {
      if (mounted) setState(() => _isJoining = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A1128),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('PARTIES', style: GoogleFonts.pressStart2p(fontSize: 12, color: Colors.cyanAccent)),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.cyanAccent),
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SpiderMaskIcon(size: 56),
                const SizedBox(height: 16),
                Text(
                  'JOIN OR START A PARTY',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.pressStart2p(fontSize: 11, color: Colors.cyanAccent),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.35),
                    border: Border.all(color: Colors.blueAccent, width: 3),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(color: Colors.blueAccent.withOpacity(0.3), blurRadius: 16),
                    ],
                  ),
                  child: _showCreateForm
                      ? Column(
                          children: [
                            Text('NAME YOUR PARTY',
                                style: GoogleFonts.pressStart2p(fontSize: 9, color: Colors.white54)),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _nameController,
                              style: const TextStyle(color: Colors.white),
                              textAlign: TextAlign.center,
                              maxLength: 30,
                              decoration: InputDecoration(
                                counterText: '',
                                hintText: 'e.g. Me & Akki',
                                hintStyle: const TextStyle(color: Colors.white24),
                                enabledBorder: OutlineInputBorder(
                                  borderSide: const BorderSide(color: Colors.blueAccent, width: 2),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderSide: const BorderSide(color: Colors.cyanAccent, width: 2),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                filled: true,
                                fillColor: Colors.black.withOpacity(0.4),
                              ),
                            ),
                            const SizedBox(height: 16),
                            _isCreating
                                ? const CircularProgressIndicator(color: Colors.cyanAccent)
                                : PixelButton(label: 'CREATE PARTY', fullWidth: true, onTap: _createParty),
                            const SizedBox(height: 10),
                            TextButton(
                              onPressed: () => setState(() => _showCreateForm = false),
                              child: Text('BACK', style: GoogleFonts.pressStart2p(fontSize: 7, color: Colors.white38)),
                            ),
                          ],
                        )
                      : Column(
                          children: [
                            PixelButton(
                              label: 'CREATE A PARTY',
                              fullWidth: true,
                              onTap: () => setState(() => _showCreateForm = true),
                            ),
                            const SizedBox(height: 20),
                            Text('— OR —', style: GoogleFonts.pressStart2p(fontSize: 8, color: Colors.white24)),
                            const SizedBox(height: 20),
                            TextField(
                              controller: _codeController,
                              style: GoogleFonts.pressStart2p(fontSize: 18, color: Colors.white, letterSpacing: 4),
                              textAlign: TextAlign.center,
                              textCapitalization: TextCapitalization.characters,
                              maxLength: 6,
                              decoration: InputDecoration(
                                counterText: '',
                                hintText: '000000',
                                hintStyle: GoogleFonts.pressStart2p(fontSize: 18, color: Colors.white12),
                                enabledBorder: OutlineInputBorder(
                                  borderSide: const BorderSide(color: Colors.blueAccent, width: 2),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderSide: const BorderSide(color: Colors.cyanAccent, width: 2),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                filled: true,
                                fillColor: Colors.black.withOpacity(0.4),
                              ),
                            ),
                            const SizedBox(height: 16),
                            _isJoining
                                ? const CircularProgressIndicator(color: Colors.cyanAccent)
                                : PixelButton(label: 'JOIN WITH CODE', fullWidth: true, onTap: _joinParty),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
