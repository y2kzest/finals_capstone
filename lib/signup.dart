import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Import necessary policy pages from main.dart's context
// import 'privacy_policy_page.dart';
// import 'user_agreement_page.dart';

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  // Global key for form validation
  final _formKey = GlobalKey<FormState>();

  final supabase = Supabase.instance.client;
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _agree = false;
  bool _isLoading = false;

  // Define colors used in main.dart for consistency
  static const Color kPrimaryBlue = Color(0xFF1E88E5);
  static const Color kButtonBlue = Color(0xFF334D8C);
  static const Color kDeepBlue = Color(0xFF1E3A8A); // The color used in this file

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _togglePasswordVisibility() {
    setState(() {
      _obscurePassword = !_obscurePassword;
    });
  }

  void _toggleConfirmPasswordVisibility() {
    setState(() {
      _obscureConfirmPassword = !_obscureConfirmPassword;
    });
  }

  Future<void> _signUp() async {
    // 1. Validate the form and agreement checkbox
    if (!_formKey.currentState!.validate() || !_agree) {
      if (!_agree) {
        _showSnackBar("Please agree to the User Agreement and Privacy Policy.");
      }
      return;
    }

    setState(() => _isLoading = true);
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    try {
      // Supabase Sign Up call
      final AuthResponse res = await supabase.auth.signUp(
        email: email,
        password: password,
      );

      // Check if signup was successful and if the user needs to confirm email
      if (res.user != null) {
        _showSnackBar("Sign Up successful! Please check your email to confirm your account.");
        // After successful signup, navigate back to the login page
        if (mounted) {
          Navigator.of(context).pop();
        }
      } else {
        // This case is unlikely with email confirmation flow, but kept as a fallback
        _showSnackBar("Sign Up failed. Please try again.");
      }
    } on AuthException catch (e) {
      _showSnackBar("Sign Up Error: ${e.message}");
    } catch (e) {
      _showSnackBar("An unexpected error occurred: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Added a simple AppBar for context and back navigation
      appBar: AppBar(
        title: const Text("Create Account"),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: kDeepBlue,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 18),
            // Wrapped inputs in a Form widget
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Logo/App Title Section
                  Center(
                    child: Image.asset(
                      "assets/img/logo.png",
                      height: 150, // Reduced height for better fit on small screens
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
                  const SizedBox(height: 30),

                  // Email Address Field
                  const Text("Email Address", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 8),
                  TextFormField( // Switched to TextFormField for validation
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter your email address.';
                      }
                      return null;
                    },
                    decoration: InputDecoration(
                      hintText: "Enter your email address",
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.grey[100],
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Password Field
                  const Text("Password", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 8),
                  TextFormField( // Switched to TextFormField for validation
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter a password.';
                      }
                      return null;
                    },
                    decoration: InputDecoration(
                      hintText: "Enter your password",
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.grey[100],
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword ? Icons.visibility_off : Icons.visibility,
                          color: Colors.grey,
                        ),
                        onPressed: _togglePasswordVisibility,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Confirm Password Field
                  const Text("Confirm Password", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 8),
                  TextFormField( // Switched to TextFormField for validation
                    controller: _confirmPasswordController,
                    obscureText: _obscureConfirmPassword,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please confirm your password.';
                      }
                      if (value != _passwordController.text) {
                        return 'Passwords do not match.';
                      }
                      return null;
                    },
                    decoration: InputDecoration(
                      hintText: "Enter your confirm password",
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.grey[100],
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureConfirmPassword ? Icons.visibility_off : Icons.visibility,
                          color: Colors.grey,
                        ),
                        onPressed: _toggleConfirmPasswordVisibility,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Agreement Checkbox and Text
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: Checkbox(
                          value: _agree,
                          onChanged: (value) {
                            setState(() {
                              _agree = value!;
                            });
                          },
                          activeColor: kDeepBlue,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Wrap(
                          alignment: WrapAlignment.start,
                          spacing: 0,
                          runSpacing: 0,
                          children: [
                            DefaultTextStyle.merge(
                              style: const TextStyle(fontSize: 14, color: Colors.black),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text("I've read and agreed to "),
                                  GestureDetector(
                                    onTap: () {
                                      // Navigator.push(context, MaterialPageRoute(builder: (context) => const UserAgreementPage()));
                                    },
                                    child: const Text(
                                      "User Agreement",
                                      style: TextStyle(
                                        color: kDeepBlue,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  const Text(" and "),
                                  GestureDetector(
                                    onTap: () {
                                      //Navigator.push(context, MaterialPageRoute(builder: (context) => const PrivacyPolicyPage()));
                                    },
                                    child: const Text(
                                      "Privacy Policy",
                                      style: TextStyle(
                                        color: kDeepBlue,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 30),

                  // Sign up Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kDeepBlue,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _isLoading ? null : _signUp,
                      child: _isLoading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              "Sign up",
                              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),

                  const SizedBox(height: 20),
                  const Center(
                    child: Text(
                      "other way to sign in",
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Social Login Buttons (Unchanged)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Google
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: const Padding(
                          padding: EdgeInsets.all(8.0),
                          child: Icon(Icons.g_mobiledata, size: 32, color: Colors.black54),
                        ),
                      ),
                      const SizedBox(width: 20),
                      // Facebook
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: const Padding(
                          padding: EdgeInsets.all(8.0),
                          child: Icon(Icons.facebook, size: 28, color: kDeepBlue),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 40),

                  // Back to Sign In Link (Unchanged)
                  Center(
                    child: GestureDetector(
                      onTap: () {
                        Navigator.of(context).pop();
                      },
                      child: RichText(
                        text: TextSpan(
                          style: DefaultTextStyle.of(context).style.copyWith(
                                fontSize: 14,
                                fontWeight: FontWeight.normal,
                              ),
                          children: const <TextSpan>[
                            TextSpan(
                              text: 'Already have an account? ',
                              style: TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.normal,
                                decoration: TextDecoration.none,
                              ),
                            ),
                            TextSpan(
                              text: 'Back to Sign In',
                              style: TextStyle(
                                color: kDeepBlue,
                                fontWeight: FontWeight.bold,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}