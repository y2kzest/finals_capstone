import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'fill_business_info.dart'; // Assuming this page exists for navigation

class SellerSignInPage extends StatefulWidget {
  const SellerSignInPage({super.key});

  @override
  State<SellerSignInPage> createState() => _SellerSignInPageState();
}

class _SellerSignInPageState extends State<SellerSignInPage> {
  // 2. Create the Supabase Client instance
  // NOTE: Ensure Supabase.initialize has been called in your main.dart
  final supabase = Supabase.instance.client;

  // 3. Create Controllers to capture user input
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _agreedToTerms = false;
  bool _isLoading = false; // To show a loading spinner
  bool _isOAuthLoading = false;
  bool _navigatedAfterAuth = false;
  late final StreamSubscription<AuthState> _authSub;

  @override
  void initState() {
    super.initState();
    _authSub = supabase.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.signedIn && !_navigatedAfterAuth) {
        _navigatedAfterAuth = true;
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const FillBusinessInfoPage()),
        );
      }
    });
  }

  // 4. The Function to Register the Seller - WITH ADDED DEBUG LOGGING
  Future<void> _signUpSeller() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();

    // Basic Validation
    if (email.isEmpty || password.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please fill in all fields")));
      return;
    }
    if (password != confirmPassword) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Passwords do not match")));
      return;
    }
    if (!_agreedToTerms) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("You must agree to the terms")));
      return;
    }

    setState(() => _isLoading = true);

    try {
      // --- SUPABASE SIGN UP ---
      final AuthResponse res = await supabase.auth.signUp(
        email: email,
        password: password,
      );

      // --- NEW LOGIC FOR HANDLING SUCCESSFUL SIGNUP ---
      if (res.session != null && res.user != null) {
          // Case 1: Sign up successful AND user is immediately logged in (Email confirmation OFF)
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("Sign up successful!"),
                  backgroundColor: Color(0xFF25509E),
                )
            );
            _navigatedAfterAuth = true;
            // Navigate to the next step
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const FillBusinessInfoPage(),
              ),
            );
          }
      } else if (res.user != null && res.session == null) {
          // Case 2: Sign up successful, but email confirmation is REQUIRED (Session is null)
          if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Success! Please check your email for a confirmation link to activate your account and log in."),
                    backgroundColor: Colors.orange,
                  )
              );
          }
          // The user is not logged in, so we stay on the sign-up page or navigate to a login page.
          // Since they are not authenticated, they cannot proceed to FillBusinessInfoPage.
          
      } else {
        // Fallback for unexpected successful response without user or session
         if (mounted) {
             ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Sign up succeeded, but status is unclear. Check your email or try logging in."),
                    backgroundColor: Colors.orange,
                  )
              );
          }
      }
      
    } on AuthException catch (e) {
      // This catches specific Supabase Auth errors (e.g., duplicate user, weak password)
      debugPrint("SUPABASE AUTH ERROR: ${e.statusCode} | ${e.message}"); 
      if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text("Error: ${e.message}"),
              backgroundColor: Colors.red.shade700,
          ));
      }
    } catch (e) {
      // This catches unexpected errors (e.g., network issues, initialization problems)
      debugPrint("UNEXPECTED ERROR DURING SIGNUP: $e"); 
      if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              // Using the message you reported
              content: Text("Sign up failed. Please try again."), 
              backgroundColor: Colors.red,
          ));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    if (!_agreedToTerms) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("You must agree to the terms")));
      }
      return;
    }

    setState(() => _isOAuthLoading = true);

    final redirectUrl = kIsWeb
        ? '${Uri.base.origin}/#/auth-callback'
        : 'io.supabase.flutter://login-callback';

    try {
      await supabase.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: redirectUrl,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Complete Google sign-in in the browser; you'll return automatically.")),
        );
      }
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Google sign-in failed: ${e.message}")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Unexpected error: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _isOAuthLoading = false);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _authSub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                
                // --- Logo/Branding Section ---
                Image.asset(
                  "assets/img/logo.png",
                  height: 200,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return const Text(
                      "QUICKCART",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 32, 
                        fontWeight: FontWeight.w900, 
                        color: Color(0xFF6A7185),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 48), 

                // Email Field
                _buildLabel("Email Address"),
                const SizedBox(height: 8),
                _buildTextField(
                  controller: _emailController, // Connect Controller
                  hint: "Enter your email address",
                  inputType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 20),

                // Password Field
                _buildLabel("Password"),
                const SizedBox(height: 8),
                _buildTextField(
                  controller: _passwordController, // Connect Controller
                  hint: "Enter your password",
                  isPassword: true,
                  obscureText: _obscurePassword,
                  onVisibilityToggle: () {
                    setState(() {
                      _obscurePassword = !_obscurePassword;
                    });
                  },
                ),
                const SizedBox(height: 20),

                // Confirm Password Field
                _buildLabel("Confirm Password"),
                const SizedBox(height: 8),
                _buildTextField(
                  controller: _confirmPasswordController, // Connect Controller
                  hint: "Enter your confirm password",
                  isPassword: true,
                  obscureText: _obscureConfirmPassword,
                  onVisibilityToggle: () {
                    setState(() {
                      _obscureConfirmPassword = !_obscureConfirmPassword;
                    });
                  },
                ),
                const SizedBox(height: 24),

                // Terms and Agreement Radio/Checkbox
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _agreedToTerms = !_agreedToTerms;
                        });
                      },
                      child: Container(
                        margin: const EdgeInsets.only(top: 2),
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _agreedToTerms ? const Color(0xFF25509E) : const Color(0xFFF5F6FA),
                          border: Border.all(
                            color: _agreedToTerms ? const Color(0xFF25509E) : Colors.grey.shade300,
                          ),
                        ),
                        child: _agreedToTerms
                            ? const Icon(Icons.check, size: 14, color: Colors.white)
                            : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: RichText(
                        text: TextSpan(
                          style: const TextStyle(
                            color: Color(0xFF757575), 
                            fontSize: 14,
                            fontFamily: 'Roboto', 
                          ),
                          children: [
                            const TextSpan(text: "I've read and agreed to "),
                            TextSpan(
                              text: "User Agreement",
                              style: const TextStyle(
                                color: Color(0xFF0F3C5A),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const TextSpan(text: " and "),
                            TextSpan(
                              text: "Privacy Policy",
                              style: const TextStyle(
                                color: Color(0xFF0F3C5A), 
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),

                // --- NEXT BUTTON ---
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _signUpSeller, // Call the sign up function
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF25509E),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    child: _isLoading 
                      ? const CircularProgressIndicator(color: Colors.white) 
                      : const Text(
                        "Next",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ),
                ),
                const SizedBox(height: 30),

                // "other way to sign in" divider
                Center(
                  child: Text(
                    "other way to sign in",
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Social Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildSocialButton(
                      imageUrl: "https://upload.wikimedia.org/wikipedia/commons/thumb/5/53/Google_%22G%22_Logo.svg/512px-Google_%22G%22_Logo.svg.png",
                      fallbackIcon: Icons.g_mobiledata,
                      onTap: _isOAuthLoading ? null : _signInWithGoogle,
                      showSpinner: _isOAuthLoading,
                    ),
                    const SizedBox(width: 20),
                    _buildSocialButton(
                      imageUrl: "https://upload.wikimedia.org/wikipedia/commons/thumb/b/b8/2021_Facebook_icon.svg/2048px-2021_Facebook_icon.svg.png",
                      fallbackIcon: Icons.facebook,
                      isFacebook: true,
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Facebook sign-in not wired yet.")),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 40),

                // Back to Sign In
                Center(
                  child: GestureDetector(
                    onTap: () {
                      Navigator.pop(context); 
                    },
                    child: RichText(
                      text: TextSpan(
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 14,
                        ),
                        children: [
                          const TextSpan(text: "Already have an account? "),
                          TextSpan(
                            text: "Back to Sign In",
                            style: const TextStyle(
                              color: Color(0xFF0F3C5A),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Helper Widgets (Unchanged)
  Widget _buildLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: 15,
        color: Colors.black87,
      ),
    );
  }

  Widget _buildTextField({
    required String hint,
    required TextEditingController controller,
    bool isPassword = false,
    bool obscureText = false,
    TextInputType? inputType,
    VoidCallback? onVisibilityToggle,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: inputType,
      style: const TextStyle(fontSize: 15),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          color: Colors.grey.shade400, 
          fontSize: 15,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF25509E)),
        ),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(
                  obscureText ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  color: Colors.grey.shade500,
                ),
                onPressed: onVisibilityToggle,
              )
            : null,
      ),
    );
  }

  Widget _buildSocialButton({
    required String imageUrl,
    required IconData fallbackIcon,
    bool isFacebook = false,
    VoidCallback? onTap,
    bool showSpinner = false,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.grey.shade300),
          color: Colors.white,
        ),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: showSpinner
              ? const CircularProgressIndicator(strokeWidth: 2.5)
              : Image.network(
                  imageUrl,
                  errorBuilder: (context, error, stackTrace) => Icon(
                    fallbackIcon, 
                    color: isFacebook ? Colors.blue : Colors.grey,
                    size: 28,
                  ),
                ),
        ),
      ),
    );
  }
}