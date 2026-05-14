import 'dart:async';

import 'package:flutter/foundation.dart'
  show debugPrint, defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../bahay.dart';
import '../signup.dart';
import '../utils/helpers.dart';
import '../utils/page_transitions.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final FocusNode _emailFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();

  bool _obscurePassword = true;
  bool _agree = false;
  bool _isLoading = false;
  bool _isOAuthLoading = false;
  bool _navigatedAfterAuth = false;
  late final StreamSubscription<AuthState> _authSub;

  late final AnimationController _entryCtrl;
  late final Animation<double> _entryFade;
  late final Animation<Offset> _entrySlide;

  static const Color kPrimary = Color(0xFF2A4BA0);
  static const Color kPrimaryDark = Color(0xFF153075);
  static const Color kSurface = Color(0xFFF7F8FC);
  static const Color kBorder = Color(0xFFE2E5EE);

  @override
  void initState() {
    super.initState();
    _authSub = supabase.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.passwordRecovery) {
        // User tapped the reset link in their email — let them set a new one.
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _showSetNewPasswordDialog(),
        );
        return;
      }
      if (data.event == AuthChangeEvent.signedIn && !_navigatedAfterAuth) {
        _navigatedAfterAuth = true;
        _navigateAfterSignIn();
      }
    });

    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    final curved = CurvedAnimation(
      parent: _entryCtrl,
      curve: Curves.easeOutCubic,
    );
    _entryFade = Tween<double>(begin: 0, end: 1).animate(curved);
    _entrySlide = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(curved);
    WidgetsBinding.instance.addPostFrameCallback((_) => _entryCtrl.forward());
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _entryCtrl.dispose();
    _authSub.cancel();
    super.dispose();
  }

  Future<void> _navigateAfterSignIn() async {
    if (!mounted) return;
    final currentUser = supabase.auth.currentUser;
    if (currentUser != null) {
      try {
        final profile = await supabase
            .from('profile')
            .select('status')
            .eq('user_id', currentUser.id)
            .maybeSingle();
        if (profile?['status'] == 'suspended') {
          await supabase.auth.signOut();
          _navigatedAfterAuth = false;
          _showSnack(
            'Your account has been suspended. Please contact the administrator.',
            isError: true,
          );
          return;
        }
      } catch (e) {
        debugPrint('Login profile status check failed: $e');
      }
    }
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      fadeSlideRoute((_) => const Bahay()),
    );
  }

  bool _isEmail(String input) => isEmail(input);

  bool _useNativePasswordResetRedirect() {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  String? _passwordResetRedirect() {
    if (!_useNativePasswordResetRedirect()) return null;
    return 'io.supabase.flutter://login-callback';
  }

  final String _userAgreementContent =
      "Welcome to QuickCart! By using our services, you agree to these terms:\n\n"
      "1. Acceptance of Terms: This agreement is a legal contract. By signing in or creating an account, you are agreeing to these terms.\n\n"
      "2. User Accounts: You must provide accurate and complete information. You are responsible for all activity under your account.\n\n"
      "3. Content and Conduct: You agree not to post harmful or illegal content. We reserve the right to remove content that violates these rules.\n\n"
      "4. Termination: We may terminate or suspend your access immediately, without prior notice or liability, for any reason whatsoever, including without limitation if you breach the Terms.";

  final String _privacyPolicyContent =
      "Your privacy is very important to us.\n\n"
      "1. Data Collection: We collect basic user data including your email, password (hashed), and device information for security purposes.\n\n"
      "2. Data Usage: Your data is used solely to provide and improve the QuickCart service, process transactions, and communicate with you.\n\n"
      "3. Data Sharing: We do not share your personal identification information with third parties for marketing purposes.\n\n"
      "4. Security: We employ industry-standard security measures to protect your information, but absolute security cannot be guaranteed.";

  void _showAgreementDialog(String title, String content) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: kPrimary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.shield_outlined,
                      color: kPrimary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                        color: kPrimaryDark,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: SingleChildScrollView(
                  child: Text(
                    content,
                    style: const TextStyle(
                      fontSize: 13.5,
                      height: 1.55,
                      color: Color(0xFF44485A),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(
                    foregroundColor: kPrimary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                  ),
                  child: const Text(
                    'Got it',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _signInWithEmailPassword() async {
    if (!_agree) {
      _showSnack(
        'Please agree to the Terms and Privacy Policy first.',
        isError: true,
      );
      return;
    }
    final input = _emailController.text.trim();
    final password = _passwordController.text.trim();
    if (input.isEmpty || password.isEmpty || !_isEmail(input)) {
      _showSnack(
        'Enter a valid email address and password.',
        isError: true,
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      final res = await supabase.auth.signInWithPassword(
        email: input,
        password: password,
      );
      if (res.session != null) {
        if (!mounted) return;
        _navigatedAfterAuth = true;
        _emailController.clear();
        _passwordController.clear();
        await _navigateAfterSignIn();
      } else {
        _showSnack('Sign in failed. Check your credentials.', isError: true);
      }
    } on AuthException catch (e) {
      _showSnack('Login failed: ${e.message}', isError: true);
    } catch (e) {
      _showSnack('An unexpected error occurred: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    if (!_agree) {
      _showSnack(
        'Please agree to the Terms and Privacy Policy first.',
        isError: true,
      );
      return;
    }

    setState(() => _isOAuthLoading = true);

    final redirectUrl = kIsWeb
        ? null
        : 'io.supabase.flutter://login-callback';

    try {
      final ok = await supabase.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: redirectUrl,
        authScreenLaunchMode: kIsWeb
            ? LaunchMode.platformDefault
            : LaunchMode.externalApplication,
      );
      if (!ok && mounted) {
        _showSnack(
          'Could not open Google sign-in. Please try again.',
          isError: true,
        );
      } else if (mounted) {
        _showSnack(
          'Complete sign-in in your browser. You will return automatically.',
        );
      }
    } on AuthException catch (e) {
      _showSnack('Google sign-in failed: ${e.message}', isError: true);
    } catch (e) {
      _showSnack('An unexpected error occurred: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isOAuthLoading = false);
    }
  }

  Future<void> _showForgotPasswordSheet() async {
    final ctrl = TextEditingController(text: _emailController.text.trim());
    bool sending = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) => Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 18,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
              ),
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: kPrimary.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.lock_reset_outlined,
                          color: kPrimary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Reset password',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    "Enter your email and we'll send you a link to reset your password.",
                    style: TextStyle(color: Color(0xFF6B7280), fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: ctrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: _decoration(
                      hint: 'your.email@example.com',
                      icon: Icons.mail_outline_rounded,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kPrimaryDark,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: sending
                          ? null
                          : () async {
                              final addr = ctrl.text.trim();
                              bool didClose = false;
                              if (!_isEmail(addr)) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  const SnackBar(
                                    content: Text('Enter a valid email.'),
                                  ),
                                );
                                return;
                              }
                              setSheet(() => sending = true);
                              try {
                                final redirectTo = _passwordResetRedirect();
                                await supabase.auth.resetPasswordForEmail(
                                  addr,
                                  redirectTo: redirectTo,
                                );
                                if (ctx.mounted) {
                                  didClose = true;
                                  Navigator.pop(ctx);
                                  if (mounted) {
                                    final message =
                                        _useNativePasswordResetRedirect()
                                            ? 'Password reset link sent to $addr. Open it on this device to set a new password.'
                                            : 'Password reset email sent to $addr. Open the link in your browser to finish.';
                                    _showSnack(message);
                                  }
                                }
                              } on AuthException catch (e) {
                                if (ctx.mounted) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    SnackBar(
                                      content: Text('Failed: ${e.message}'),
                                    ),
                                  );
                                }
                              } finally {
                                if (ctx.mounted && !didClose) {
                                  setSheet(() => sending = false);
                                }
                              }
                            },
                      child: sending
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Send reset link',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    ctrl.dispose();
  }

  Future<void> _showSetNewPasswordDialog() async {
    if (!mounted) return;
    final pwdCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    bool busy = false;
    bool obscure = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: kPrimary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.lock_reset_outlined, color: kPrimary),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Set new password',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Enter a new password for your account.',
                style: TextStyle(color: Color(0xFF6B7280), fontSize: 13),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: pwdCtrl,
                obscureText: obscure,
                decoration: _decoration(
                  hint: 'New password',
                  icon: Icons.lock_outline_rounded,
                  suffixIcon: IconButton(
                    splashRadius: 18,
                    icon: Icon(
                      obscure
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: Colors.grey[600],
                      size: 20,
                    ),
                    onPressed: () => setDialog(() => obscure = !obscure),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: confirmCtrl,
                obscureText: obscure,
                decoration: _decoration(
                  hint: 'Confirm password',
                  icon: Icons.lock_outline_rounded,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimaryDark,
                foregroundColor: Colors.white,
              ),
              onPressed: busy
                  ? null
                  : () async {
                      final pwd = pwdCtrl.text;
                      final confirm = confirmCtrl.text;
                      if (pwd.length < 6) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Password must be at least 6 characters.',
                            ),
                          ),
                        );
                        return;
                      }
                      if (pwd != confirm) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(
                            content: Text('Passwords do not match.'),
                          ),
                        );
                        return;
                      }
                      setDialog(() => busy = true);
                      try {
                        await supabase.auth.updateUser(
                          UserAttributes(password: pwd),
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) {
                          await supabase.auth.signOut();
                          _showSnack(
                            'Password updated. Sign in with your new password.',
                          );
                        }
                      } on AuthException catch (e) {
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(content: Text('Failed: ${e.message}')),
                          );
                        }
                      } finally {
                        if (ctx.mounted) setDialog(() => busy = false);
                      }
                    },
              child: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Update'),
            ),
          ],
        ),
      ),
    );
    pwdCtrl.dispose();
    confirmCtrl.dispose();
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                isError
                    ? Icons.error_outline_rounded
                    : Icons.check_circle_outline_rounded,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(message)),
            ],
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor:
              isError ? const Color(0xFFDC2626) : const Color(0xFF153075),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
  }

  void _signUp() {
    Navigator.push(context, fadeSlideRoute((_) => const SignupPage()));
  }

  InputDecoration _decoration({
    required String hint,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Icon(icon, color: kPrimary, size: 20),
      ),
      prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
      suffixIcon: suffixIcon,
      hintStyle: const TextStyle(color: Color(0xFFA0A6B5), fontSize: 14),
      contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
      filled: true,
      fillColor: kSurface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: kBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: kBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: kPrimary, width: 1.6),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 6),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: Color(0xFF374151),
            letterSpacing: 0.2,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final isEmailInput = _isEmail(_emailController.text.trim());
    final canSubmit = isEmailInput && _passwordController.text.isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        bottom: false,
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: Stack(
            children: [
              // Brand gradient hero
              Container(
                height: 220,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [kPrimary, kPrimaryDark],
                  ),
                ),
              ),
              // Decorative circles
              Positioned(
                top: -30,
                right: -30,
                child: Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
              ),
              Positioned(
                top: 110,
                left: -40,
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.06),
                  ),
                ),
              ),
              // Card content
              SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 26, 20, 28), // Increased top padding to push it downward slightly
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: FadeTransition(
                      opacity: _entryFade,
                      child: SlideTransition(
                        position: _entrySlide,
                        child: Column(
                          children: [
                            // Brand mark — logo only
                            SizedBox(
                              width: 150,
                              height: 130, // Reduced height to pull the card up
                              child: Transform.scale(
                                scale: 1.5,
                                child: Image.asset(
                                  'assets/quickcartwhitelogo.png',
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, _, _) => const Icon(
                                    Icons.shopping_bag_rounded,
                                    size: 52,
                                    color: kPrimary,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16), // Reduced gap
                            Container(
                              padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(24),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x1A1F2A57),
                                    blurRadius: 28,
                                    offset: Offset(0, 14),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const Text(
                                    'Welcome back',
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF111827),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Sign in to continue shopping or selling.',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                  const SizedBox(height: 22),
                                  _label('EMAIL ADDRESS'),
                                  TextField(
                                    controller: _emailController,
                                    focusNode: _emailFocus,
                                    keyboardType: TextInputType.emailAddress,
                                    textInputAction: TextInputAction.next,
                                    onChanged: (_) => setState(() {}),
                                    onSubmitted: (_) =>
                                        _passwordFocus.requestFocus(),
                                    decoration: _decoration(
                                      hint: 'your.email@example.com',
                                      icon: Icons.mail_outline_rounded,
                                      suffixIcon: isEmailInput
                                          ? const Padding(
                                              padding: EdgeInsets.only(
                                                right: 14,
                                              ),
                                              child: Icon(
                                                Icons.check_circle_rounded,
                                                color: Color(0xFF16A34A),
                                                size: 20,
                                              ),
                                            )
                                          : null,
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  _label('PASSWORD'),
                                  TextField(
                                    controller: _passwordController,
                                    focusNode: _passwordFocus,
                                    obscureText: _obscurePassword,
                                    textInputAction: TextInputAction.done,
                                    onChanged: (_) => setState(() {}),
                                    onSubmitted: (_) {
                                      if (!_isLoading && canSubmit) {
                                        _signInWithEmailPassword();
                                      }
                                    },
                                    decoration: _decoration(
                                      hint: 'Enter your password',
                                      icon: Icons.lock_outline_rounded,
                                      suffixIcon: IconButton(
                                        splashRadius: 18,
                                        icon: Icon(
                                          _obscurePassword
                                              ? Icons.visibility_off_outlined
                                              : Icons.visibility_outlined,
                                          color: Colors.grey[600],
                                          size: 20,
                                        ),
                                        onPressed: () => setState(
                                          () => _obscurePassword =
                                              !_obscurePassword,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton(
                                      onPressed: _showForgotPasswordSheet,
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 4,
                                        ),
                                        minimumSize: const Size(0, 0),
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      child: const Text(
                                        'Forgot password?',
                                        style: TextStyle(
                                          color: kPrimary,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  _agreementCheckbox(),
                                  const SizedBox(height: 18),
                                  // Sign in button
                                  AnimatedContainer(
                                    duration:
                                        const Duration(milliseconds: 220),
                                    height: 54,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(14),
                                      gradient: const LinearGradient(
                                        colors: [kPrimary, kPrimaryDark],
                                      ),
                                      boxShadow: canSubmit && !_isLoading
                                          ? const [
                                              BoxShadow(
                                                color: Color(0x402A4BA0),
                                                blurRadius: 18,
                                                offset: Offset(0, 8),
                                              ),
                                            ]
                                          : null,
                                    ),
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        borderRadius:
                                            BorderRadius.circular(14),
                                        onTap: (_isLoading || !canSubmit)
                                            ? null
                                            : _signInWithEmailPassword,
                                        child: Center(
                                          child: _isLoading
                                              ? const SizedBox(
                                                  width: 24,
                                                  height: 24,
                                                  child:
                                                      CircularProgressIndicator(
                                                    strokeWidth: 2.6,
                                                    color: Colors.white,
                                                  ),
                                                )
                                              : Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Text(
                                                      'Sign In',
                                                      style: TextStyle(
                                                        fontSize: 15.5,
                                                        fontWeight:
                                                            FontWeight.w800,
                                                        color: Colors.white
                                                            .withValues(
                                                                alpha: canSubmit
                                                                    ? 1
                                                                    : 0.7),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Icon(
                                                      Icons
                                                          .arrow_forward_rounded,
                                                      size: 18,
                                                      color: Colors.white
                                                          .withValues(
                                                              alpha: canSubmit
                                                                  ? 1
                                                                  : 0.7),
                                                    ),
                                                  ],
                                                ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 18),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Container(
                                          height: 1,
                                          color: const Color(0xFFE5E7EB),
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                        ),
                                        child: Text(
                                          'or continue with',
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            color: Colors.grey[600],
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: Container(
                                          height: 1,
                                          color: const Color(0xFFE5E7EB),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  _googleButton(),
                                ],
                              ),
                            ),
                            const SizedBox(height: 18),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  "Don't have an account?",
                                  style: TextStyle(
                                    color: Colors.grey[700],
                                    fontSize: 13.5,
                                  ),
                                ),
                                TextButton(
                                  onPressed: _signUp,
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    minimumSize: const Size(0, 0),
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: const Text(
                                    'Create one',
                                    style: TextStyle(
                                      color: kPrimary,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _agreementCheckbox() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _agree = !_agree),
          borderRadius: BorderRadius.circular(7),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 22,
            height: 22,
            margin: const EdgeInsets.only(right: 10, top: 2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(7),
              color: _agree ? kPrimary : Colors.white,
              border: Border.all(
                color: _agree ? kPrimary : const Color(0xFFCBD2DE),
                width: 1.6,
              ),
            ),
            child: _agree
                ? const Icon(Icons.check_rounded,
                    size: 15, color: Colors.white)
                : null,
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 1),
            child: RichText(
              text: TextSpan(
                style: const TextStyle(
                  color: Color(0xFF44485A),
                  fontSize: 12.5,
                  height: 1.45,
                ),
                children: [
                  const TextSpan(text: 'I agree to the '),
                  TextSpan(
                    text: 'Terms',
                    style: const TextStyle(
                      color: kPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                    recognizer: TapGestureRecognizer()
                      ..onTap = () => _showAgreementDialog(
                            'User Agreement',
                            _userAgreementContent,
                          ),
                  ),
                  const TextSpan(text: ' and '),
                  TextSpan(
                    text: 'Privacy Policy',
                    style: const TextStyle(
                      color: kPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                    recognizer: TapGestureRecognizer()
                      ..onTap = () => _showAgreementDialog(
                            'Privacy Policy',
                            _privacyPolicyContent,
                          ),
                  ),
                  const TextSpan(text: '.'),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _googleButton() {
    return SizedBox(
      height: 52,
      child: OutlinedButton(
        onPressed: _isOAuthLoading ? null : _signInWithGoogle,
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          side: const BorderSide(color: kBorder, width: 1.3),
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: _isOAuthLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: kPrimary,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset(
                    'assets/img/banner image/google-logo-png.png',
                    height: 20,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => Container(
                      width: 20,
                      height: 20,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFFEA4335),
                      ),
                      child: const Center(
                        child: Text(
                          'G',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Continue with Google',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1F2937),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
