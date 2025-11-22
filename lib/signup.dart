import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'verification/otp.dart'; // Assuming you named your OTP file 'otp.dart'

// --- CONSTANTS ---
const Color kPrimaryBlue = Color(0xFF1E88E5);
const Color kButtonBlue = Color(0xFF334D8C);

// Helper function to check if input is likely an email (contains '@' and '.')
bool isEmail(String input) {
  return input.contains('@') && input.contains('.');
}

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
  final TextEditingController _confirmPasswordController = TextEditingController();
  
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailOrPhoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
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

    if (password != confirmPassword) {
      _showSnackBar("Passwords do not match.");
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (isEmail(input)) {
        // --- EMAIL SIGNUP ---
        final AuthResponse res = await supabase.auth.signUp(
          email: input,
          password: password,
        );

        if (res.session != null) {
          _showSnackBar("Sign up successful! Please check your email to verify your account.");
          if (mounted) {
            // Navigate back to login page
            Navigator.of(context).pop(); 
          }
        } else {
          // Fallback for failed signup
          _showSnackBar("Sign up failed. Please try again.");
        }
      } else {
        // --- PHONE SIGNUP (OTP) ---
        // 1. Send the OTP code
        await supabase.auth.signInWithOtp(
          phone: input,
        );

        // **CRITICAL FIX HERE: Declare the 'phone' variable locally**
        final phone = input; 

        _showSnackBar("Verification code sent! Please verify your phone number.");
        if (mounted) {
          // Navigate to the OTP screen
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => OtpVerificationPage(phoneNumber: phone), // 'phone' is now defined!
            ),
          );
        }
      }
    } on AuthException catch (e) {
      // Check for specific Supabase errors, e.g., 'Phone signups are disabled'
      _showSnackBar("Sign Up Error: ${e.message}");
    } catch (e) {
      _showSnackBar("An unexpected error occurred: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }


  // --- WIDGET BUILD ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Create Account', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: kButtonBlue,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // --- Logo/Branding Section ---
                Image.asset(
                  "assets/img/logo.png",
                  height: 150,
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
                const SizedBox(height: 32), 

                // --- Email/Phone Field ---
                const Text(
                  "Email Address or Phone Number",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _emailOrPhoneController,
                  keyboardType: TextInputType.text,
                  decoration: InputDecoration(
                    hintText: "Enter email or phone number (e.g., +639123...)",
                    contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: kPrimaryBlue, width: 1.5),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // --- Password Field ---
                const Text(
                  "Password",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    hintText: "Enter your password (min 6 characters)",
                    contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: kPrimaryBlue, width: 1.5),
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility_off : Icons.visibility,
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
                const SizedBox(height: 24),

                // --- Confirm Password Field ---
                const Text(
                  "Confirm Password",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _confirmPasswordController,
                  obscureText: _obscureConfirmPassword,
                  decoration: InputDecoration(
                    hintText: "Re-enter your password",
                    contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: kPrimaryBlue, width: 1.5),
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirmPassword ? Icons.visibility_off : Icons.visibility,
                        color: Colors.grey[600],
                      ),
                      onPressed: () {
                        setState(() {
                          _obscureConfirmPassword = !_obscureConfirmPassword;
                        });
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 40), 

                // --- Sign Up Button ---
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kButtonBlue,
                      padding: const EdgeInsets.symmetric(vertical: 18), 
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 8,
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
                                color: Colors.white 
                              ),
                          ),
                  ),
                ),
                
                const SizedBox(height: 20),

                // Back to Sign In Link
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text("Already have an account?", style: TextStyle(color: Colors.black54)),
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pop(); // Go back to Login Page
                      },
                      child: const Text("Back to Sign In", style: TextStyle(color: kPrimaryBlue, fontWeight: FontWeight.bold)),
                    ),
                  ],
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}