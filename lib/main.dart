import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'bahay.dart'; 
import 'signup.dart'; 
import 'seller_pages/fill_business_info.dart'; 

// --- SUPABASE KEYS FOR WEB ENVIRONMENT ---
const String kSupabaseUrl = 'https://mnnnmdlvjvwyxhadeinc.supabase.co';
const String kSupabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1ubm5tZGx2anZ3eXhoYWRlaW5jIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjI5NzI1NTksImV4cCI6MjA3ODU0ODU1OX0.NxQDcEBhw4XrFbjKeiYQFtN9pvEuLOAi4XiHmzxcKgw';

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
    
    await Supabase.initialize(
      url: dotenv.env['SUPABASE_URL']!, 
      anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
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
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _agree = false;
  bool _isLoading = false;

  // Primary design color (Standard Blue for links/focus)
  static const Color kPrimaryBlue = Color(0xFF1E88E5); 
  // Darker Blue for the main button and branding
  static const Color kButtonBlue = Color(0xFF334D8C); 

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

  // Function to handle user sign-in using email and password
  Future<void> _signIn() async {
    if (!_agree) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please agree to the terms and policies before signing in.")),
      );
      return;
    }

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Email and password are required.")),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final AuthResponse res = await supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      // Check if a session was successfully created
      if (res.session != null) {
        if (!mounted) return;

        // Navigate to the correct Bahay screen on successful sign-in
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => const Bahay(), 
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Sign in failed. Check your credentials.")),
        );
      }
    } on AuthException catch (e) {
      // Catches errors specific to Supabase Auth (e.g., user not found, wrong password)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Login failed: ${e.message}")),
      );
    } catch (e) {
      // Catches general network or unexpected errors
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("An unexpected error occurred: $e")),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // 🎯 NEW: Function to navigate directly to the Seller Business Info Page
  void _navigateToSellerSignup() {
    print('Navigating to FillBusinessInfoPage for Seller');
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const FillBusinessInfoPage(), 
      ),
    );
  }

  // Function to navigate to the Buyer/Standard Signup Page
  void _navigateToBuyerSignup() {
    print('Navigating to SignupPage as Buyer');
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
              // 🚀 UPDATED: Button to sign up as Seller
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
  Widget _buildSocialButton(String imageUrl, VoidCallback onTap) {
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
              color: Colors.black.withOpacity(0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Image.network(
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
              
              // --- Email Field ---
              const Text(
                "Email Address",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  hintText: "Enter your email address",
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
                  hintText: "Enter your password",
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

              // Sign in button (Darker Blue)
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
                  onPressed: _isLoading ? null : _signIn,
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
                          "Sign in",
                          style: TextStyle(
                              fontSize: 18, 
                              fontWeight: FontWeight.bold,
                              color: Colors.white 
                            ),
                        ),
                ),
              ),
              
              const SizedBox(height: 32),

              // "other way to sign in" text divider
              const Center(
                child: Text(
                  "or sign in with",
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
              ),
              const SizedBox(height: 16),

              // Social Login Buttons (Google, Facebook)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildSocialButton(
                    'https://upload.wikimedia.org/wikipedia/commons/5/53/Google_%22G%22_Logo.svg',
                    () { /* Google Sign-in logic */ },
                  ),
                  const SizedBox(width: 24),
                  _buildSocialButton(
                    'https://upload.wikimedia.org/wikipedia/commons/b/b8/2021_Facebook_icon.svg',
                    () { /* Facebook Sign-in logic */ },
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Sign Up link 
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("Don't have an account?", style: TextStyle(color: Colors.black54)),
                  TextButton(
                    onPressed: _signUp, // Calls the role selection dialog
                    child: const Text("Sign Up", style: TextStyle(color: kPrimaryBlue, fontWeight: FontWeight.bold)),
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