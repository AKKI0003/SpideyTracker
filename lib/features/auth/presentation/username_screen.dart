import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/widgets/pixel_button.dart';
import '../../../core/widgets/themed_snackbar.dart';
import '../../map_scanner/presentation/widgets/spider_mask_icon.dart';

class UsernameScreen extends StatefulWidget {
  const UsernameScreen({super.key});

  @override
  State<UsernameScreen> createState() => _UsernameScreenState();
}

class _UsernameScreenState extends State<UsernameScreen> {
  final _controller = TextEditingController();
  bool _isLoading = false;

  Future<void> _save() async {
    final name = _controller.text.trim();
    if (name.isEmpty) {
      showThemedSnack(context, 'Enter a codename first', tone: SnackTone.error);
      return;
    }
    setState(() => _isLoading = true);
    final user = FirebaseAuth.instance.currentUser!;
    await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
      'displayName': name,
      'usernameSet': true,
    });
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A1128),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SpiderMaskIcon(size: 56),
                const SizedBox(height: 16),
                Text('CHOOSE YOUR CODENAME',
                    style: GoogleFonts.pressStart2p(fontSize: 11, color: Colors.cyanAccent),
                    textAlign: TextAlign.center),
                const SizedBox(height: 24),
                TextField(
                  controller: _controller,
                  style: const TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    hintText: 'e.g. Akki',
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
                const SizedBox(height: 20),
                _isLoading
                    ? const CircularProgressIndicator(color: Colors.cyanAccent)
                    : PixelButton(label: 'CONFIRM', fullWidth: true, onTap: _save),
              ],
            ),
          ),
        ),
      ),
    );
  }
}