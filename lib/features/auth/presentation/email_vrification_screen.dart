import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/widgets/pixel_button.dart';
import '../../../core/widgets/themed_snackbar.dart';
import '../../../core/services/otp_services.dart';
import '../../map_scanner/presentation/widgets/spider_mask_icon.dart';

class EmailVerificationScreen extends StatefulWidget {
  const EmailVerificationScreen({super.key});

  @override
  State<EmailVerificationScreen> createState() => _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  final _codeController = TextEditingController();
  bool _codeSent = false;
  bool _isLoading = false;
  int _cooldownSeconds = 0;

  Future<void> _sendCode() async {
    final email = FirebaseAuth.instance.currentUser?.email;
    if (email == null) return;

    setState(() => _isLoading = true);
    try {
      await OtpService.sendCode(email);
      setState(() {
        _codeSent = true;
        _cooldownSeconds = 60;
      });
      _startCooldown();
      if (mounted) showThemedSnack(context, 'CODE SENT — CHECK YOUR INBOX', tone: SnackTone.success);
    } catch (e) {
      if (mounted) showThemedSnack(context, '$e', tone: SnackTone.error);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _startCooldown() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      setState(() => _cooldownSeconds = (_cooldownSeconds - 1).clamp(0, 60));
      return _cooldownSeconds > 0;
    });
  }

  Future<void> _verify() async {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      showThemedSnack(context, 'ENTER THE 6-DIGIT CODE', tone: SnackTone.error);
      return;
    }

    setState(() => _isLoading = true);
    try {
      await OtpService.verifyCode(code);
      if (mounted) showThemedSnack(context, 'EMAIL VERIFIED', tone: SnackTone.success);
    } catch (e) {
      if (mounted) showThemedSnack(context, '$e', tone: SnackTone.error);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = FirebaseAuth.instance.currentUser?.email ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFF0A1128),
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
                  'VERIFY YOUR EMAIL',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.pressStart2p(fontSize: 11, color: Colors.cyanAccent),
                ),
                const SizedBox(height: 10),
                Text(
                  email,
                  style: GoogleFonts.pressStart2p(fontSize: 8, color: Colors.white54),
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
                  child: Column(
                    children: [
                      if (!_codeSent) ...[
                        Text(
                          'We\'ll send a 6-digit code to confirm this is really you.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.pressStart2p(fontSize: 7, color: Colors.white70, height: 1.8),
                        ),
                        const SizedBox(height: 20),
                        _isLoading
                            ? const CircularProgressIndicator(color: Colors.cyanAccent)
                            : PixelButton(label: 'SEND CODE', fullWidth: true, onTap: _sendCode),
                      ] else ...[
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
                        _isLoading
                            ? const CircularProgressIndicator(color: Colors.cyanAccent)
                            : PixelButton(label: 'VERIFY', fullWidth: true, onTap: _verify),
                        const SizedBox(height: 14),
                        TextButton(
                          onPressed: _cooldownSeconds > 0 ? null : _sendCode,
                          child: Text(
                            _cooldownSeconds > 0 ? 'RESEND IN ${_cooldownSeconds}S' : 'RESEND CODE',
                            style: GoogleFonts.pressStart2p(fontSize: 7, color: Colors.cyanAccent),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Verification is required to continue.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.pressStart2p(fontSize: 6, color: Colors.white24),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}