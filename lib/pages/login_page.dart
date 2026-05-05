import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../bahay.dart';
import '../signup.dart';
import '../utils/helpers.dart';
import '../verification/otp.dart';

// --- LOGIN PAGE WIDGETS AND LOGIC ---
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final supabase = Supabase.instance.client;
  // Renamed controller to handle both email and phone input
  final TextEditingController _emailOrPhoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _agree = false;
  bool _isLoading = false;
  bool _isOAuthLoading = false;
  bool _navigatedAfterAuth = false;
  late final StreamSubscription<AuthState> _authSub;

  // Primary design color (Standard Blue for links/focus)
  static const Color kPrimaryBlue = Color(0xFF2A4BA0);
  // Darker Blue for the main button and branding
  static const Color kButtonBlue = Color(0xFF153075);

  @override
  void initState() {
    super.initState();
    _authSub = supabase.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.signedIn && !_navigatedAfterAuth) {
        _navigatedAfterAuth = true;
        _navigateAfterSignIn();
      }
    });
  }

  Future<void> _navigateAfterSignIn() async {
    if (!mounted) return;

    // Check if account is suspended (admin sets profiles.status = 'suspended')
    final currentUser = supabase.auth.currentUser;
    if (currentUser != null) {
      final profile = await supabase
          .from('profiles')
          .select('status')
          .eq('id', currentUser.id)
          .maybeSingle();
      if (profile?['status'] == 'suspended') {
        await supabase.auth.signOut();
        _navigatedAfterAuth = false;
        _showSnackBar(
          'Your account has been suspended. Please contact the administrator.',
        );
        return;
      }
    }

    // All users go to the buyer app — sellers access their dashboard from Profile
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const Bahay()),
    );
  }

  // Helper to check if input is likely an email (contains '@' and '.')
  bool _isEmail(String input) => isEmail(input);

  // --- Modal Content Definitions ---
  final String _userAgreementContent = """
    Welcome to QuickCart! By using our services, you agree to these terms:

    1. **Acceptance of Terms:** This agreement is a legal contract. By clicking 'Sign in' or 'Create an Account', you are agreeing to these terms.
    2. **User Accounts:** You must provide accurate and complete information. You are responsible for all activity under your account.
    3. **Content and Conduct:** You agree not to post harmful or illegal content. We reserve the right to remove content that violates these rules.
    4. **Termination:** We may terminate or suspend your access immediately, without prior notice or liability, for any reason whatsoever, including without limitation if you breach the Terms.

    For a full list of terms, please visit our website.
  """;

  final String _privacyPolicyContent = """
    Your privacy is very important to us.

    1. **Data Collection:** We collect basic user data including your email, password (hashed), and device information for security purposes.
    2. **Data Usage:** Your data is used solely to provide and improve the QuickCart service, process transactions, and communicate with you.
    3. **Data Sharing:** We do not share your personal identification information with third parties for marketing purposes. Data may be shared with trusted partners (e.g., payment processors) as necessary to run the service.
    4. **Security:** We employ industry-standard security measures to protect your information, but absolute security cannot be guaranteed.

    By continuing to use QuickCart, you consent to this Privacy Policy.
  """;

  // Function to show the modal dialog
  void _showAgreementDialog(String title, String content) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          title: Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: kPrimaryBlue,
            ),
          ),
          content: SingleChildScrollView(
            child: Text(
              // Clean up markdown formatting for display
              content.replaceAll("**", "").trim(),
              style: const TextStyle(
                fontSize: 14,
                height: 1.4,
                color: Colors.black87,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text(
                'Close',
                style: TextStyle(
                  color: kPrimaryBlue,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // --- Phone Sign-In Flow (OTP) ---
  Future<void> _signInWithPhoneOtp() async {
    // 1. Pre-validation checks
    if (!_agree) {
      _showSnackBar(
        "Please agree to the terms and policies before signing in.",
      );
      return;
    }

    final phone = _emailOrPhoneController.text.trim();
    // Supabase requires E.164 format (e.g., +12025550123). Add validation hint.
    if (phone.isEmpty || _isEmail(phone)) {
      _showSnackBar(
        "Please enter a valid phone number (e.g., +1234567890) for OTP login.",
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Step 1: Request OTP via Supabase passwordless sign-in
      // This sends an SMS code to the provided phone number.
      await supabase.auth.signInWithOtp(phone: phone);

      _showSnackBar("Verification code sent! Please verify your phone number.");

      if (mounted) {
        // Step 2: Navigate to the OTP verification page
        Navigator.push(
          context,
          MaterialPageRoute(
            // Use the OtpVerificationPage defined in otp.dart
            builder: (context) =>
                OtpVerificationPage(phoneNumber: phone), // <-- CALL IS CORRECT
          ),
        );
      }
    } on AuthException catch (e) {
      // The error message shows up here if Supabase rejects the phone number/request
      _showSnackBar("OTP Request failed: ${e.message}");
    } catch (e) {
      _showSnackBar("An unexpected error occurred: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Function to handle user sign-in using email and password
  Future<void> _signInWithEmailPassword() async {
    if (!_agree) {
      _showSnackBar(
        "Please agree to the terms and policies before signing in.",
      );
      return;
    }

    final input = _emailOrPhoneController.text.trim();
    final password = _passwordController.text.trim();

    if (input.isEmpty || password.isEmpty || !_isEmail(input)) {
      _showSnackBar("Please enter a valid email address and password.");
      return;
    }

    setState(() => _isLoading = true);

    try {
      final AuthResponse res = await supabase.auth.signInWithPassword(
        email: input,
        password: password,
      );

      // Check if a session was successfully created
      if (res.session != null) {
        if (!mounted) return;
        _navigatedAfterAuth = true;

        // Clear text fields on successful login
        _emailOrPhoneController.clear();
        _passwordController.clear();

        await _navigateAfterSignIn();
      } else {
        _showSnackBar("Sign in failed. Check your credentials.");
      }
    } on AuthException catch (e) {
      // The error message shows up here if Supabase rejects the email/password
      _showSnackBar("Login failed: ${e.message}");
    } catch (e) {
      _showSnackBar("An unexpected error occurred: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _signInWithGoogle() async {
    if (!_agree) {
      _showSnackBar(
        "Please agree to the terms and policies before signing in.",
      );
      return;
    }

    setState(() {
      _isOAuthLoading = true;
    });

    final redirectUrl = kIsWeb
        ? '${Uri.base.origin}/#/auth-callback'
        : 'io.supabase.flutter://login-callback';

    try {
      await supabase.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: redirectUrl,
      );

      _showSnackBar(
        "Complete Google sign-in in the browser; you'll return automatically.",
      );
    } on AuthException catch (e) {
      _showSnackBar("Google sign-in failed: ${e.message}");
    } catch (e) {
      _showSnackBar("An unexpected error occurred: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isOAuthLoading = false;
        });
      }
    }
  }

  // 🎯 Clean up controllers when the widget is disposed
  @override
  void dispose() {
    _emailOrPhoneController.dispose();
    _passwordController.dispose();
    _authSub.cancel();
    super.dispose();
  }

  // Function to navigate to the Buyer/Standard Signup Page
  void _signUp() {
    debugPrint('Navigating to SignupPage as Buyer');
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SignupPage()),
    );
  }

  // Widget to build social login buttons (Moved into State for context access)
  Widget _buildSocialButton(
    IconData iconData,
    Color iconColor,
    VoidCallback? onTap, {
    bool showSpinner = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          border: Border.all(color: Colors.grey.shade300, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: showSpinner
            ? const Padding(
                padding: EdgeInsets.all(12.0),
                child: CircularProgressIndicator(strokeWidth: 2.5),
              )
            : Icon(iconData, color: iconColor, size: 26),
      ),
    );
  }

  Widget _buildGoogleButton(
    VoidCallback? onTap, {
    bool showSpinner = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          border: Border.all(color: Colors.grey.shade300, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: showSpinner
            ? const Padding(
                padding: EdgeInsets.all(12.0),
                child: CircularProgressIndicator(strokeWidth: 2.5),
              )
            : Padding(
                padding: const EdgeInsets.all(12.0),
                child: Image.asset(
                  'assets/img/banner image/google-logo-png.png',
                  fit: BoxFit.contain,
                ),
              ),
      ),
    );
  }

  InputDecoration _fieldDecoration({
    required String hintText,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hintText,
      prefixIcon: Icon(icon, color: Colors.grey[600]),
      suffixIcon: suffixIcon,
      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300, width: 1.0),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kPrimaryBlue, width: 1.5),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: Colors.black87,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final input = _emailOrPhoneController.text.trim();
    final isEmailInput = _isEmail(input);

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: SafeArea(
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x22000000),
                        blurRadius: 24,
                        offset: Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 80),
                        child: Image.asset(
                          "assets/img/logo.png",
                          height: 90,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) {
                            return const Text(
                              "QUICKCART",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.w900,
                                color: kButtonBlue,
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        "Welcome back",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        "Sign in using your email or phone number",
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                      ),
                      const SizedBox(height: 24),
                      _sectionLabel("Email Address or Phone Number"),
                      TextField(
                        controller: _emailOrPhoneController,
                        keyboardType: TextInputType.text,
                        textInputAction: TextInputAction.next,
                        onChanged: (_) => setState(() {}),
                        decoration: _fieldDecoration(
                          hintText:
                              "Enter email (for password login) or phone (for OTP)",
                          icon: Icons.person_outline,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _sectionLabel("Password"),
                      TextField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) {
                          if (!_isLoading && isEmailInput) {
                            _signInWithEmailPassword();
                          }
                        },
                        decoration: _fieldDecoration(
                          hintText: "Enter your password (for email login)",
                          icon: Icons.lock_outline,
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              color: Colors.grey[600],
                            ),
                            onPressed: () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                              });
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () {
                            /* TODO: Implement password reset flow */
                          },
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 0),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text(
                            "Forgot password?",
                            style: TextStyle(color: kPrimaryBlue, fontSize: 14),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          InkWell(
                            onTap: () => setState(() => _agree = !_agree),
                            borderRadius: BorderRadius.circular(999),
                            child: Container(
                              width: 24,
                              height: 24,
                              margin: const EdgeInsets.only(right: 8, top: 2),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _agree ? kPrimaryBlue : Colors.white,
                                border: Border.all(
                                  color: _agree
                                      ? kPrimaryBlue
                                      : Colors.grey.shade400,
                                  width: 1.5,
                                ),
                              ),
                              child: _agree
                                  ? const Icon(
                                      Icons.check,
                                      size: 16,
                                      color: Colors.white,
                                    )
                                  : null,
                            ),
                          ),
                          Expanded(
                            child: RichText(
                              text: TextSpan(
                                style: const TextStyle(
                                  color: Colors.black87,
                                  fontSize: 14,
                                  height: 1.4,
                                ),
                                children: [
                                  const TextSpan(
                                    text: "I've read and agreed to ",
                                  ),
                                  TextSpan(
                                    text: "User Agreement",
                                    style: const TextStyle(
                                      color: kPrimaryBlue,
                                      decoration: TextDecoration.underline,
                                    ),
                                    recognizer: TapGestureRecognizer()
                                      ..onTap = () {
                                        _showAgreementDialog(
                                          "User Agreement",
                                          _userAgreementContent,
                                        );
                                      },
                                  ),
                                  const TextSpan(text: " and the "),
                                  TextSpan(
                                    text: "Privacy Policy",
                                    style: const TextStyle(
                                      color: kPrimaryBlue,
                                      decoration: TextDecoration.underline,
                                    ),
                                    recognizer: TapGestureRecognizer()
                                      ..onTap = () {
                                        _showAgreementDialog(
                                          "Privacy Policy",
                                          _privacyPolicyContent,
                                        );
                                      },
                                  ),
                                  const TextSpan(text: "."),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kButtonBlue,
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 4,
                          ),
                          onPressed: _isLoading || !isEmailInput
                              ? null
                              : _signInWithEmailPassword,
                          child: _isLoading && isEmailInput
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 3,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  "Sign in (Email)",
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kPrimaryBlue,
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 2,
                          ),
                          onPressed: _isLoading || isEmailInput
                              ? null
                              : _signInWithPhoneOtp,
                          child: _isLoading && !isEmailInput
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 3,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  "Login with Phone (OTP)",
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          const Expanded(child: Divider(color: Colors.grey)),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14.0,
                            ),
                            child: Text(
                              "Or continue with",
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 14,
                              ),
                            ),
                          ),
                          const Expanded(child: Divider(color: Colors.grey)),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildGoogleButton(
                            _isOAuthLoading ? null : _signInWithGoogle,
                            showSpinner: _isOAuthLoading,
                          ),
                          const SizedBox(width: 24),
                          _buildSocialButton(
                            Icons.facebook_rounded,
                            const Color(0xFF1877F2),
                            () {
                              _showSnackBar("Facebook Sign-in not wired yet.");
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            "Don't have an account?",
                            style: TextStyle(color: Colors.black54),
                          ),
                          TextButton(
                            onPressed: _signUp,
                            child: const Text(
                              "Sign Up",
                              style: TextStyle(
                                color: kPrimaryBlue,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
