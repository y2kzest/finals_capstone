import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'verification/otp.dart'; // Corrected import
import 'bahay.dart'; 
import 'signup.dart'; 
import 'seller_pages/activate.dart';

// ====================================================================
// !!! CRITICAL ACTION REQUIRED !!!
// Replace these placeholder values with the EXACT Supabase URL and Anon Key
// from your Supabase Dashboard -> Project Settings -> API.
// ====================================================================
const String kSupabaseUrl = 'https://mnnnmdlvjvwyxhadeinc.supabase.co'; // REPLACE THIS WITH YOUR REAL PROJECT URL
const String kSupabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1ubm5tZGx2anZ3eXhoYWRlaW5jIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjI5NzI1NTksImV4cCI6MjA3ODU0ODU1OX0.NxQDcEBhw4XrFbjKeiYQFtN9pvEuLOAi4XiHmzxcKgw'; // REPLACE THIS WITH YOUR REAL ANON KEY
// ====================================================================


// --- MAIN FUNCTION ---
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (kIsWeb) {
    // Web environment: use hardcoded constants
    await Supabase.initialize(
      url: kSupabaseUrl,
      anonKey: kSupabaseAnonKey,
    );
  } else {
    // Mobile and Desktop: load .env file
    await dotenv.load(fileName: ".env");

    final envUrl = dotenv.env['SUPABASE_URL'];
    final envAnon = dotenv.env['SUPABASE_ANON_KEY'];

    // Guard against missing/empty env values to avoid a runtime crash before UI shows
    if (envUrl == null || envUrl.isEmpty || envAnon == null || envAnon.isEmpty) {
      throw StateError('Missing SUPABASE_URL or SUPABASE_ANON_KEY in .env');
    }

    await Supabase.initialize(
      url: envUrl,
      anonKey: envAnon,
    );
  }

  runApp(const MyApp());
}

// --- APP WIDGET ---
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'QuickCart',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: _LoginPageState.kPrimaryBlue, 
        fontFamily: 'Inter',
      ),
      home: const LoginPage(),
      // Define named route for '/home' used in OTP verification for navigation
      routes: {
        '/home': (context) => const Bahay(), 
      },
    );
  }
}

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
  static const Color kPrimaryBlue = Color(0xFF1E88E5); 
  // Darker Blue for the main button and branding
  static const Color kButtonBlue = Color(0xFF334D8C); 

  @override
  void initState() {
    super.initState();
    _authSub = supabase.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.signedIn && !_navigatedAfterAuth) {
        _navigatedAfterAuth = true;
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const Bahay()),
        );
      }
    });
  }

  // Helper to check if input is likely an email (contains '@' and '.')
  bool _isEmail(String input) {
    return input.contains('@') && input.contains('.');
  }

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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: kPrimaryBlue)),
          content: SingleChildScrollView(
            child: Text(
              // Clean up markdown formatting for display
              content.replaceAll("**", "").trim(), 
              style: const TextStyle(fontSize: 14, height: 1.4, color: Colors.black87),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Close', style: TextStyle(color: kPrimaryBlue, fontWeight: FontWeight.bold)),
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
      _showSnackBar("Please agree to the terms and policies before signing in.");
      return;
    }

    final phone = _emailOrPhoneController.text.trim();
    // Supabase requires E.164 format (e.g., +12025550123). Add validation hint.
    if (phone.isEmpty || _isEmail(phone)) {
      _showSnackBar("Please enter a valid phone number (e.g., +1234567890) for OTP login.");
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Step 1: Request OTP via Supabase passwordless sign-in
      // This sends an SMS code to the provided phone number.
      await supabase.auth.signInWithOtp(
        phone: phone,
      );

      _showSnackBar("Verification code sent! Please verify your phone number.");
      
      if (mounted) {
        // Step 2: Navigate to the OTP verification page
        Navigator.push(
          context,
          MaterialPageRoute(
            // Use the OtpVerificationPage defined in otp.dart
            builder: (context) => OtpVerificationPage(phoneNumber: phone), // <-- CALL IS CORRECT
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
      _showSnackBar("Please agree to the terms and policies before signing in.");
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

        // Navigate to the correct Bahay screen on successful sign-in
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => const Bahay(), 
          ),
        );
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  Future<void> _signInWithGoogle() async {
    if (!_agree) {
      _showSnackBar("Please agree to the terms and policies before signing in.");
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

      _showSnackBar("Complete Google sign-in in the browser; you'll return automatically.");
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

  // Function to navigate directly to the Seller Business Info Page
  void _navigateToSellerSignup() {
    debugPrint('Navigating to FillBusinessInfoPage for Seller');
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const Activate(), 
      ),
    );
  }

  // Function to navigate to the Buyer/Standard Signup Page
  void _navigateToBuyerSignup() {
    debugPrint('Navigating to SignupPage as Buyer');
    // Note: Since SignupPage is now in lib/signup_page.dart, we need to import it properly
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const SignupPage(), 
      ),
    );
  }


  // Function to show a role selection dialog on sign up
  void _signUp() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text(
            "Choose Account Type",
            style: TextStyle(fontWeight: FontWeight.bold, color: kButtonBlue),
            textAlign: TextAlign.center,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Button to sign up as Seller
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop(); // Close the dialog
                  _navigateToSellerSignup(); // Navigate to seller form
                },
                icon: const Icon(Icons.store, color: Colors.white),
                label: const Text("Sign up as Seller", style: TextStyle(fontSize: 16, color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2A4BA0), 
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 4,
                ),
              ),
              const SizedBox(height: 16),
              // Button to sign up as Buyer
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop(); // Close the dialog
                  _navigateToBuyerSignup(); // Navigate to buyer/standard signup
                },
                icon: const Icon(Icons.shopping_cart, color: Colors.white),
                label: const Text("Sign up as Buyer", style: TextStyle(fontSize: 16, color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2A4BA0),
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 4,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
            ),
          ],
        );
      },
    );
  }


  // Widget to build social login buttons (Moved into State for context access)
  Widget _buildSocialButton(String imageUrl, VoidCallback? onTap, {bool showSpinner = false}) {
    return InkWell(
      onTap: onTap,
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
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: showSpinner
              ? const CircularProgressIndicator(strokeWidth: 2.5)
              : Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  // Fallback icon if image fails to load
                  errorBuilder: (context, error, stackTrace) => const Icon(Icons.person, color: Colors.grey),
                ),
        ),
      ),
    );
  }

@override
Widget build(BuildContext context) {
  return Scaffold(
    // Set the background color for a cleaner look if the background is slightly off-white
    backgroundColor: Colors.grey[50], 
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
                // Placeholder text if logo asset is missing
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
              const SizedBox(height: 48), // Space between logo and fields
              
              // --- Email/Phone Field ---
              const Text(
                "Email Address or Phone Number", // <-- UPDATED LABEL
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _emailOrPhoneController, // <-- UPDATED CONTROLLER
                keyboardType: TextInputType.text, // Keep generic for both email and phone
                decoration: InputDecoration(
                  hintText: "Enter email (for password login) or phone number (for OTP login)", // <-- UPDATED HINT
                  contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey.shade300, width: 1.0),
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
                  hintText: "Enter your password (Required for Email Login)",
                  contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey.shade300, width: 1.0),
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
              const SizedBox(height: 8),

              // Forgot password (Right aligned)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () { /* TODO: Implement password reset flow */ },
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
              const SizedBox(height: 16),

              // Checkbox and agreement text
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Custom checkbox style using InkWell for better touch target
                  InkWell(
                    onTap: () => setState(() => _agree = !_agree),
                    child: Container(
                      width: 24,
                      height: 24,
                      margin: const EdgeInsets.only(right: 8, top: 2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _agree ? kPrimaryBlue : Colors.white,
                        border: Border.all(
                            color: _agree ? kPrimaryBlue : Colors.grey.shade400,
                            width: 1.5),
                      ),
                      child: _agree
                          ? const Icon(Icons.check, size: 16, color: Colors.white)
                          : null,
                    ),
                  ),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        style: const TextStyle(color: Colors.black87, fontSize: 14, height: 1.4),
                        children: [
                          const TextSpan(text: "I've read and agreed to "),
                          TextSpan(
                            text: "User Agreement",
                            style: const TextStyle(
                                color: kPrimaryBlue, 
                                decoration: TextDecoration.underline),
                            recognizer: TapGestureRecognizer()
                              ..onTap = () {
                                _showAgreementDialog("User Agreement", _userAgreementContent);
                              },
                          ),
                          const TextSpan(text: " and the "),
                          TextSpan(
                            text: "Privacy Policy",
                            style: const TextStyle(
                                color: kPrimaryBlue, 
                                decoration: TextDecoration.underline),
                            recognizer: TapGestureRecognizer()
                              ..onTap = () {
                                _showAgreementDialog("Privacy Policy", _privacyPolicyContent);
                              },
                          ),
                          const TextSpan(text: "."),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32), 

              // Sign in button (Email/Password)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kButtonBlue, // Darker blue button
                    padding: const EdgeInsets.symmetric(vertical: 18), 
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 8,
                  ),
                  // Only allow sign-in with email/password if the input looks like an email
                  onPressed: _isLoading || !_isEmail(_emailOrPhoneController.text.trim())
                      ? null
                      : _signInWithEmailPassword, 
                  child: _isLoading && _isEmail(_emailOrPhoneController.text.trim())
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
                              color: Colors.white 
                            ),
                        ),
                ),
              ),

              const SizedBox(height: 16),

              // --- Phone Login Button (OTP) ---
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimaryBlue, // Lighter blue for phone login
                    padding: const EdgeInsets.symmetric(vertical: 18), 
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 4,
                  ),
                  // Only allow phone login if the input does NOT look like an email
                  onPressed: _isLoading || _isEmail(_emailOrPhoneController.text.trim())
                      ? null
                      : _signInWithPhoneOtp,
                  child: _isLoading && !_isEmail(_emailOrPhoneController.text.trim())
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
                              color: Colors.white 
                            ),
                        ),
                ),
              ),
              
              const SizedBox(height: 32),

              // --- Divider for Social Login ---
              Row(
                children: [
                  const Expanded(child: Divider(color: Colors.grey)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Text(
                      "Or continue with",
                      style: TextStyle(color: Colors.grey[600], fontSize: 14),
                    ),
                  ),
                  const Expanded(child: Divider(color: Colors.grey)),
                ],
              ),
              const SizedBox(height: 32),

              // --- Social Login Buttons ---
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildSocialButton(
                    'https://upload.wikimedia.org/wikipedia/commons/thumb/c/c1/Google_%22G%22_logo.svg/1024px-Google_%22G%22_logo.svg.png',
                    _isOAuthLoading ? null : _signInWithGoogle,
                    showSpinner: _isOAuthLoading,
                  ),
                  const SizedBox(width: 24),
                  _buildSocialButton(
                    'https://upload.wikimedia.org/wikipedia/commons/thumb/0/05/Facebook_Logo_%282019%29.png/1024px-Facebook_Logo_%282019%29.png',
                    () {
                      _showSnackBar("Facebook Sign-in not wired yet.");
                    },
                  ),
                ],
              ),

              const SizedBox(height: 32),

              // Sign Up link 
              // ...
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("Don't have an account?", style: TextStyle(color: Colors.black54)),
                  TextButton(
                    // ▼▼▼ THE FIXED LINE ▼▼▼
                    onPressed: _signUp, // Now calls the dialog popup function
                    // ▲▲▲ THE FIXED LINE ▲▲▲
                    child: const Text("Sign Up", style: TextStyle(color: kPrimaryBlue, fontWeight: FontWeight.bold)),
                  ),
                ],
              )
// ...
            ],
          ),
        ),
      ),
    ),
  );
}
}