import 'dart:math';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/widgets/pixel_button.dart';
import '../../../core/widgets/themed_snackbar.dart';
import '../../map_scanner/presentation/widgets/spider_mask_icon.dart';

class PairingScreen extends StatefulWidget {
  const PairingScreen({super.key});

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  final _codeController = TextEditingController();
  String? _myGeneratedCode;
  bool _isLoading = false;

  String _generateCode() {
    final rand = Random.secure();
    return List.generate(6, (_) => rand.nextInt(10)).join();
  }

  Future<void> _createInviteCode() async {
    setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser!;
      final code = _generateCode();

      final coupleRef = FirebaseFirestore.instance.collection('couples').doc();
      await coupleRef.set({
        'memberUids': [user.uid],
        'createdAt': FieldValue.serverTimestamp(),
      });

      await FirebaseFirestore.instance.collection('inviteCodes').doc(code).set({
        'coupleId': coupleRef.id,
        'createdBy': user.uid,
        'used': false,
        'createdAt': FieldValue.serverTimestamp(),
      });

      setState(() => _myGeneratedCode = code);
    } catch (e) {
      if (mounted) showThemedSnack(context, 'Failed to create code', tone: SnackTone.error);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _cancelGeneratedCode() async {
    setState(() => _myGeneratedCode = null);
  }

  Future<void> _joinWithCode() async {
    setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser!;
      final code = _codeController.text.trim();

      final codeRef = FirebaseFirestore.instance.collection('inviteCodes').doc(code);
      final codeSnap = await codeRef.get();

      if (!codeSnap.exists) {
        if (mounted) showThemedSnack(context, 'Invalid code', tone: SnackTone.error);
        return;
      }
      final codeData = codeSnap.data()!;
      if (codeData['used'] == true) {
        if (mounted) showThemedSnack(context, 'Code already used', tone: SnackTone.error);
        return;
      }
      if (codeData['createdBy'] == user.uid) {
        if (mounted) showThemedSnack(context, "Can't use your own code", tone: SnackTone.error);
        return;
      }

      final coupleId = codeData['coupleId'];
      final coupleRef = FirebaseFirestore.instance.collection('couples').doc(coupleId);

      await coupleRef.update({'memberUids': FieldValue.arrayUnion([user.uid])});
      await codeRef.update({'used': true});
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({'coupleId': coupleId});

      final otherUid = codeData['createdBy'];
      await FirebaseFirestore.instance.collection('users').doc(otherUid).update({'coupleId': coupleId});

      if (mounted) showThemedSnack(context, 'SPIDER LINK ESTABLISHED', tone: SnackTone.success);
    } catch (e) {
      if (mounted) showThemedSnack(context, 'Failed to join', tone: SnackTone.error);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A1128),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('PAIRING', style: GoogleFonts.pressStart2p(fontSize: 12, color: Colors.cyanAccent)),
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
                  'LINK WITH YOUR PARTNER',
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
                  child: _myGeneratedCode != null
                      ? Column(
                          children: [
                            Text(
                              'SHARE THIS CODE',
                              style: GoogleFonts.pressStart2p(fontSize: 9, color: Colors.white54),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _myGeneratedCode!,
                              style: GoogleFonts.pressStart2p(fontSize: 28, color: Colors.greenAccent),
                            ),
                            const SizedBox(height: 16),
                            const SizedBox(
                              width: 18, height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.cyanAccent),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'WAITING FOR LINK...',
                              style: GoogleFonts.pressStart2p(fontSize: 7, color: Colors.white38),
                            ),
                            const SizedBox(height: 20),
                            TextButton(
                              onPressed: _cancelGeneratedCode,
                              child: Text(
                                'CANCEL',
                                style: GoogleFonts.pressStart2p(fontSize: 7, color: Colors.redAccent),
                              ),
                            ),
                          ],
                        )
                      : Column(
                          children: [
                            _isLoading
                                ? const CircularProgressIndicator(color: Colors.cyanAccent)
                                : PixelButton(
                                    label: 'GENERATE CODE',
                                    fullWidth: true,
                                    onTap: _createInviteCode,
                                  ),
                            const SizedBox(height: 20),
                            Text('— OR —', style: GoogleFonts.pressStart2p(fontSize: 8, color: Colors.white24)),
                            const SizedBox(height: 20),
                            TextField(
                              controller: _codeController,
                              style: GoogleFonts.pressStart2p(fontSize: 18, color: Colors.white, letterSpacing: 4),
                              textAlign: TextAlign.center,
                              keyboardType: TextInputType.number,
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
                            PixelButton(label: 'JOIN', fullWidth: true, onTap: _joinWithCode),
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