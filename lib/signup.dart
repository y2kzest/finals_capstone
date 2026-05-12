import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'utils/helpers.dart';

// --- CONSTANTS ---
const Color kPrimaryBlue = Color(0xFF2A4BA0);
const Color kButtonBlue = Color(0xFF153075);

// Helper function to check if input is likely an email (contains '@' and '.')

// --- SIGNUP PAGE WIDGET ---
class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final supabase = Supabase.instance.client;
  final TextEditingController _emailOrPhoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;
  String? _lastOtpContact;

  @override
  void dispose() {
    _emailOrPhoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _showOtpDialog(String contact) async {
    final codeController = TextEditingController();
    bool isDialogLoading = false;
    final isEmailContact = isEmail(contact);

    Future<void> verifyOtp(StateSetter setDialogState) async {
      final token = codeController.text.trim();
      if (token.length != 8) {
        _showSnackBar("Please enter the 8-digit verification code.");
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
          Navigator.of(
            context,
          ).pushNamedAndRemoveUntil('/home', (Route<dynamic> route) => false);
          _showSnackBar("Verification successful! Welcome to QuickCart.");
        } else {
          _showSnackBar("Verification failed. Please check the code.");
        }
      } on AuthException catch (e) {
        _showSnackBar("Verification failed: ${e.message}");
      } catch (e) {
        _showSnackBar("An unexpected error occurred: $e");
      } finally {
        if (mounted) {
          setDialogState(() => isDialogLoading = false);
        }
      }
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: Text(isEmailContact ? 'Verify Email' : 'Verify Phone'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'We sent an 8-digit code to $contact',
                    style: TextStyle(color: Colors.grey[700]),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: codeController,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    textAlign: TextAlign.center,
                    maxLength: 8,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onSubmitted: (_) {
                      if (!isDialogLoading) {
                        verifyOtp(setDialogState);
                      }
                    },
                    decoration: InputDecoration(
                      hintText: "- - - - - - - -",
                      hintStyle: const TextStyle(letterSpacing: 6),
                      counterText: "",
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 16,
                        horizontal: 12,
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: kPrimaryBlue,
                          width: 1.5,
                        ),
                      ),
                    ),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 4,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isDialogLoading
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isDialogLoading
                      ? null
                      : () => verifyOtp(setDialogState),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kButtonBlue,
                  ),
                  child: isDialogLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Verify',
                          style: TextStyle(color: Colors.white),
                        ),
                ),
              ],
            );
          },
        );
      },
    );

    codeController.dispose();
  }

  // --- Core Signup Logic ---
  Future<void> _signUp() async {
    final input = _emailOrPhoneController.text.trim();
    final password = _passwordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();

    if (input.isEmpty || password.isEmpty || confirmPassword.isEmpty) {
      _showSnackBar("All fields are required.");
      return;
    }

    if (password.length < 6) {
      _showSnackBar("Password must be at least 6 characters.");
      return;
    }

    if (password != confirmPassword) {
      _showSnackBar("Passwords do not match.");
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (isEmail(input)) {
        // --- EMAIL SIGNUP ---
        await supabase.auth.signUp(
          email: input,
          password: password,
        );

        _lastOtpContact = input;
        _showSnackBar("Verification code sent! Please check your email.");
        if (mounted) {
          await _showOtpDialog(input);
        }
      } else {
        // --- PHONE SIGNUP (OTP) ---
        // 1. Send the OTP code
        await supabase.auth.signInWithOtp(phone: input);

        _lastOtpContact = input;
        _showSnackBar(
          "Verification code sent! Please verify your phone number.",
        );
        if (mounted) {
          await _showOtpDialog(input);
        }
      }
    } on AuthException catch (e) {
      final message = e.message.toLowerCase().contains('rate limit')
          ? 'Too many sign up attempts. Check your inbox for a previous email or wait a minute before trying again.'
          : "Sign Up Error: ${e.message}";
      _showSnackBar(message);
    } catch (e) {
      _showSnackBar("An unexpected error occurred: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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
        borderSide: BorderSide(color: Colors.grey.shade300),
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

  // --- WIDGET BUILD ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          'Create Account',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: kButtonBlue,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
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
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                                color: kButtonBlue,
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        "Create your account",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        "Use email or phone to get started",
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                      ),
                      const SizedBox(height: 24),
                      _sectionLabel("Email Address or Phone Number"),
                      TextField(
                        controller: _emailOrPhoneController,
                        keyboardType: TextInputType.text,
                        textInputAction: TextInputAction.next,
                        decoration: _fieldDecoration(
                          hintText:
                              "Enter email or phone number (e.g., +639123...)",
                          icon: Icons.person_outline,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _sectionLabel("Password"),
                      TextField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        textInputAction: TextInputAction.next,
                        decoration: _fieldDecoration(
                          hintText: "Enter your password (min 6 characters)",
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
                      const SizedBox(height: 16),
                      _sectionLabel("Confirm Password"),
                      TextField(
                        controller: _confirmPasswordController,
                        obscureText: _obscureConfirmPassword,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) {
                          if (!_isLoading) {
                            _signUp();
                          }
                        },
                        decoration: _fieldDecoration(
                          hintText: "Re-enter your password",
                          icon: Icons.lock_reset_outlined,
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureConfirmPassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              color: Colors.grey[600],
                            ),
                            onPressed: () {
                              setState(() {
                                _obscureConfirmPassword =
                                    !_obscureConfirmPassword;
                              });
                            },
                          ),
                        ),
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
                          onPressed: _isLoading ? null : _signUp,
                          child: _isLoading
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 3,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  "Sign Up",
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _isLoading
                            ? null
                            : () {
                                final enteredContact =
                                    _emailOrPhoneController.text.trim();
                                final contact = enteredContact.isNotEmpty
                                    ? enteredContact
                                    : _lastOtpContact;
                                if (contact == null || contact.isEmpty) {
                                  _showSnackBar(
                                    "Enter your email or phone first.",
                                  );
                                  return;
                                }
                                _showOtpDialog(contact);
                              },
                        child: const Text(
                          "Already have a code? Verify",
                          style: TextStyle(
                            color: kPrimaryBlue,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            "Already have an account?",
                            style: TextStyle(color: Colors.black54),
                          ),
                          TextButton(
                            onPressed: () {
                              Navigator.of(context).pop();
                            },
                            child: const Text(
                              "Back to Sign In",
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
