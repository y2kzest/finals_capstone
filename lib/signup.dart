import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'utils/helpers.dart';

const Color kPrimary = Color(0xFF2A4BA0);
const Color kPrimaryDark = Color(0xFF153075);
const Color kSurface = Color(0xFFF7F8FC);
const Color kBorder = Color(0xFFE2E5EE);

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  final FocusNode _emailFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();
  final FocusNode _confirmFocus = FocusNode();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;
  String? _lastOtpContact;

  late final AnimationController _entryCtrl;
  late final Animation<double> _entryFade;
  late final Animation<Offset> _entrySlide;

  @override
  void initState() {
    super.initState();
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
    _confirmPasswordController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _confirmFocus.dispose();
    _entryCtrl.dispose();
    super.dispose();
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
              isError ? const Color(0xFFDC2626) : kPrimaryDark,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
  }

  int _passwordStrength(String pw) {
    int score = 0;
    if (pw.length >= 8) score++;
    if (pw.contains(RegExp(r'[A-Z]'))) score++;
    if (pw.contains(RegExp(r'[0-9]'))) score++;
    if (pw.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>_\-\[\]]'))) score++;
    return score; // 0..4
  }

  Color _strengthColor(int s) {
    if (s <= 1) return const Color(0xFFDC2626);
    if (s == 2) return const Color(0xFFF59E0B);
    if (s == 3) return const Color(0xFF2A4BA0);
    return const Color(0xFF059669);
  }

  String _strengthLabel(int s) {
    switch (s) {
      case 0:
        return 'Enter a password';
      case 1:
        return 'Weak';
      case 2:
        return 'Fair';
      case 3:
        return 'Good';
      default:
        return 'Strong';
    }
  }

  Future<void> _showOtpDialog(String contact) async {
    final codeController = TextEditingController();
    bool isDialogLoading = false;
    final isEmailContact = isEmail(contact);

    Future<void> verifyOtp(StateSetter setDialogState) async {
      final token = codeController.text.trim();
      if (token.length != 8) {
        _showSnack('Please enter the 8-digit verification code.', isError: true);
        return;
      }
      setDialogState(() => isDialogLoading = true);
      try {
        final AuthResponse res;
        if (isEmailContact) {
          res = await supabase.auth.verifyOTP(
            type: OtpType.signup,
            email: contact,
            token: token,
          );
        } else {
          res = await supabase.auth.verifyOTP(
            type: OtpType.sms,
            phone: contact,
            token: token,
          );
        }
        if (res.session != null) {
          try {
            await supabase.from('user_roles').upsert({
              'user_id': res.user!.id,
              'role': 'buyer',
            });
          } catch (_) {}
          if (!mounted) return;
          Navigator.of(context, rootNavigator: true).pop();
          Navigator.of(context).pushNamedAndRemoveUntil(
            '/home',
            (Route<dynamic> route) => false,
          );
          _showSnack('Welcome to QuickCart!');
        } else {
          _showSnack('Verification failed. Please check the code.',
              isError: true);
        }
      } on AuthException catch (e) {
        _showSnack('Verification failed: ${e.message}', isError: true);
      } catch (e) {
        _showSnack('An unexpected error occurred: $e', isError: true);
      } finally {
        if (mounted) setDialogState(() => isDialogLoading = false);
      }
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return Dialog(
              insetPadding: const EdgeInsets.symmetric(horizontal: 22),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: kPrimary.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Icon(
                          isEmailContact
                              ? Icons.mark_email_unread_rounded
                              : Icons.sms_outlined,
                          color: kPrimary,
                          size: 32,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      isEmailContact ? 'Verify your email' : 'Verify your phone',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'We sent an 8-digit code to\n$contact',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: codeController,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      textAlign: TextAlign.center,
                      maxLength: 8,
                      autofocus: true,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onSubmitted: (_) {
                        if (!isDialogLoading) verifyOtp(setDialogState);
                      },
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 6,
                        color: kPrimaryDark,
                      ),
                      decoration: InputDecoration(
                        hintText: '— — — — — — — —',
                        hintStyle: const TextStyle(
                          letterSpacing: 6,
                          color: Color(0xFFCBD2DE),
                        ),
                        counterText: '',
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 16,
                          horizontal: 12,
                        ),
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
                          borderSide: const BorderSide(
                            color: kPrimary,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kPrimaryDark,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: isDialogLoading
                            ? null
                            : () => verifyOtp(setDialogState),
                        child: isDialogLoading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Verify code',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                ),
                              ),
                      ),
                    ),
                    TextButton(
                      onPressed: isDialogLoading
                          ? null
                          : () => Navigator.of(dialogContext).pop(),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          color: Color(0xFF6B7280),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    codeController.dispose();
  }

  Future<void> _signUp() async {
    final input = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();

    if (input.isEmpty || password.isEmpty || confirmPassword.isEmpty) {
      _showSnack('All fields are required.', isError: true);
      return;
    }
    if (password.length < 6) {
      _showSnack('Password must be at least 6 characters.', isError: true);
      return;
    }
    if (password != confirmPassword) {
      _showSnack('Passwords do not match.', isError: true);
      return;
    }

    setState(() => _isLoading = true);
    try {
      if (isEmail(input)) {
        await supabase.auth.signUp(email: input, password: password);
        _lastOtpContact = input;
        _showSnack('We sent a verification code to your email.');
        if (mounted) await _showOtpDialog(input);
      } else {
        await supabase.auth.signInWithOtp(phone: input);
        _lastOtpContact = input;
        _showSnack('We sent a verification code to your phone.');
        if (mounted) await _showOtpDialog(input);
      }
    } on AuthException catch (e) {
      final message = e.message.toLowerCase().contains('rate limit')
          ? 'Too many sign-up attempts. Check your inbox for a previous email or wait a minute.'
          : 'Sign-up error: ${e.message}';
      _showSnack(message, isError: true);
    } catch (e) {
      _showSnack('An unexpected error occurred: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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
    final password = _passwordController.text;
    final strength = _passwordStrength(password);
    final confirmsMatch = password.isNotEmpty &&
        password == _confirmPasswordController.text;
    final isContactValid = _emailController.text.trim().isNotEmpty;
    final canSubmit = isContactValid &&
        password.length >= 6 &&
        confirmsMatch;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        bottom: false,
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: Stack(
            children: [
              Container(
                height: 200,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [kPrimary, kPrimaryDark],
                  ),
                ),
              ),
              Positioned(
                top: -30,
                left: -30,
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
                top: 100,
                right: -40,
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.06),
                  ),
                ),
              ),
              SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 56, 20, 28),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: FadeTransition(
                      opacity: _entryFade,
                      child: SlideTransition(
                        position: _entrySlide,
                        child: Column(
                          children: [
                            const Text(
                              'Create your account',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Join QuickCart in less than a minute',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.86),
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 28),
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
                                  _label('EMAIL OR PHONE'),
                                  TextField(
                                    controller: _emailController,
                                    focusNode: _emailFocus,
                                    textInputAction: TextInputAction.next,
                                    onChanged: (_) => setState(() {}),
                                    onSubmitted: (_) =>
                                        _passwordFocus.requestFocus(),
                                    decoration: _decoration(
                                      hint: 'you@example.com or +63 9...',
                                      icon: Icons.person_outline_rounded,
                                      suffixIcon: isContactValid
                                          ? Padding(
                                              padding: const EdgeInsets.only(
                                                  right: 14),
                                              child: Icon(
                                                isEmail(_emailController.text
                                                        .trim())
                                                    ? Icons.mail_rounded
                                                    : Icons.phone_iphone_rounded,
                                                color: const Color(0xFF16A34A),
                                                size: 18,
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
                                    textInputAction: TextInputAction.next,
                                    onChanged: (_) => setState(() {}),
                                    onSubmitted: (_) =>
                                        _confirmFocus.requestFocus(),
                                    decoration: _decoration(
                                      hint: 'At least 6 characters',
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
                                  const SizedBox(height: 10),
                                  _strengthBar(strength, password.isNotEmpty),
                                  const SizedBox(height: 14),
                                  _label('CONFIRM PASSWORD'),
                                  TextField(
                                    controller: _confirmPasswordController,
                                    focusNode: _confirmFocus,
                                    obscureText: _obscureConfirmPassword,
                                    textInputAction: TextInputAction.done,
                                    onChanged: (_) => setState(() {}),
                                    onSubmitted: (_) {
                                      if (!_isLoading && canSubmit) _signUp();
                                    },
                                    decoration: _decoration(
                                      hint: 'Re-enter your password',
                                      icon: Icons.shield_outlined,
                                      suffixIcon: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (_confirmPasswordController
                                              .text.isNotEmpty)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                  right: 4),
                                              child: Icon(
                                                confirmsMatch
                                                    ? Icons
                                                        .check_circle_rounded
                                                    : Icons.cancel_rounded,
                                                color: confirmsMatch
                                                    ? const Color(0xFF16A34A)
                                                    : const Color(0xFFDC2626),
                                                size: 18,
                                              ),
                                            ),
                                          IconButton(
                                            splashRadius: 18,
                                            icon: Icon(
                                              _obscureConfirmPassword
                                                  ? Icons
                                                      .visibility_off_outlined
                                                  : Icons.visibility_outlined,
                                              color: Colors.grey[600],
                                              size: 20,
                                            ),
                                            onPressed: () => setState(
                                              () => _obscureConfirmPassword =
                                                  !_obscureConfirmPassword,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 22),
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
                                            : _signUp,
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
                                                      'Create account',
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
                                  const SizedBox(height: 10),
                                  Center(
                                    child: TextButton(
                                      onPressed: _isLoading
                                          ? null
                                          : () {
                                              final enteredContact =
                                                  _emailController.text
                                                      .trim();
                                              final contact =
                                                  enteredContact.isNotEmpty
                                                      ? enteredContact
                                                      : _lastOtpContact;
                                              if (contact == null ||
                                                  contact.isEmpty) {
                                                _showSnack(
                                                  'Enter your email or phone first.',
                                                  isError: true,
                                                );
                                                return;
                                              }
                                              _showOtpDialog(contact);
                                            },
                                      child: const Text(
                                        'Already received a code? Verify',
                                        style: TextStyle(
                                          color: kPrimary,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13.5,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 18),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'Already have an account?',
                                  style: TextStyle(
                                    color: Colors.grey[700],
                                    fontSize: 13.5,
                                  ),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.of(context).pop(),
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
                                    'Sign in',
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
              // Back button overlay
              Positioned(
                top: 4,
                left: 8,
                child: IconButton(
                  onPressed: () => Navigator.maybePop(context),
                  icon: const Icon(
                    Icons.arrow_back_rounded,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _strengthBar(int strength, bool show) {
    final color = _strengthColor(strength);
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: show ? 1 : 0.4,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: List.generate(4, (i) {
              final filled = i < strength;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: i < 3 ? 6 : 0),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    height: 5,
                    decoration: BoxDecoration(
                      color: filled ? color : const Color(0xFFE5E7EB),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 6),
          Text(
            _strengthLabel(strength),
            style: TextStyle(
              fontSize: 11.5,
              color: show ? color : const Color(0xFF9CA3AF),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
