import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/widgets/pixel_button.dart';
import '../../../core/widgets/themed_snackbar.dart';
import '../../map_scanner/presentation/widgets/spider_mask_icon.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLogin = true;
  bool _isLoading = false;

  Future<void> _submit() async {
    setState(() => _isLoading = true);
    try {
      if (_isLogin) {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
      } else {
        await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        showThemedSnack(context, e.message ?? 'Something went wrong', tone: SnackTone.error);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  InputDecoration _fieldDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white54),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A1128),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SpiderMaskIcon(size: 64),
                const SizedBox(height: 12),
                Text(
                  'SPIDEYTRACKER',
                  style: GoogleFonts.pressStart2p(fontSize: 18, color: Colors.cyanAccent),
                ),
                const SizedBox(height: 4),
                Text(
                  _isLogin ? 'ACCESS TERMINAL' : 'NEW AGENT SIGNUP',
                  style: GoogleFonts.pressStart2p(fontSize: 9, color: Colors.white38),
                ),
                const SizedBox(height: 32),
                Container(
                  padding: const EdgeInsets.all(16),
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
                      TextField(
                        controller: _emailController,
                        style: const TextStyle(color: Colors.white),
                        decoration: _fieldDecoration('Email'),
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _passwordController,
                        style: const TextStyle(color: Colors.white),
                        decoration: _fieldDecoration('Password'),
                        obscureText: true,
                      ),
                      const SizedBox(height: 22),
                      _isLoading
                          ? const CircularProgressIndicator(color: Colors.cyanAccent)
                          : PixelButton(
                              label: _isLogin ? 'LOG IN' : 'SIGN UP',
                              fullWidth: true,
                              onTap: _submit,
                            ),
                      const SizedBox(height: 14),
                      TextButton(
                        onPressed: () => setState(() => _isLogin = !_isLogin),
                        child: Text(
                          _isLogin ? "NO ACCOUNT? SIGN UP" : "HAVE AN ACCOUNT? LOG IN",
                          style: GoogleFonts.pressStart2p(fontSize: 7, color: Colors.cyanAccent),
                        ),
                      ),
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