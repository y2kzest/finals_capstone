import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// This page is responsible for accepting the 6-digit code sent via SMS
class OtpVerificationPage extends StatefulWidget {
  // CRITICAL FIX: Ensure 'phoneNumber' is defined as a final field 
  // and is REQUIRED in the constructor.
  final String phoneNumber; 

  // The constructor must use the named parameter syntax
  const OtpVerificationPage({super.key, required this.phoneNumber}); // <--- THIS LINE IS THE FIX

  @override
  State<OtpVerificationPage> createState() => _OtpVerificationPageState();
}

class _OtpVerificationPageState extends State<OtpVerificationPage> {
  final supabase = Supabase.instance.client;
  final TextEditingController _otpController = TextEditingController();
  bool _isLoading = false;

  static const Color kPrimaryBlue = Color(0xFF1E88E5);
  static const Color kButtonBlue = Color(0xFF334D8C);

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  // --- Core OTP Verification Logic ---
  Future<void> _verifyOtp() async {
    final token = _otpController.text.trim();
    if (token.length != 6) {
      _showSnackBar("Please enter the 6-digit verification code.");
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Verify the OTP using the phone number and the received token
      final AuthResponse res = await supabase.auth.verifyOTP(
        type: OtpType.sms,
        phone: widget.phoneNumber, // Access the passed parameter via widget.
        token: token,
      );

      if (res.session != null) {
        _showSnackBar("Login Successful! Welcome to QuickCart.");
        if (!mounted) return;
        
        _otpController.clear();
        // Navigate to the home screen
        Navigator.of(context).pushNamedAndRemoveUntil('/home', (Route<dynamic> route) => false);

      } else {
        _showSnackBar("Verification failed. Please check the code.");
      }
    } on AuthException catch (e) {
      _showSnackBar("Verification failed: ${e.message}");
    } catch (e) {
      _showSnackBar("An unexpected error occurred: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Verify Phone Number'),
        backgroundColor: kButtonBlue,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.lock_open, size: 80, color: kPrimaryBlue),
              const SizedBox(height: 16),
              Text(
                "Enter the 6-digit code sent to ${widget.phoneNumber}",
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, color: Colors.black87),
              ),
              const SizedBox(height: 32),

              // OTP Input Field
              TextField(
                controller: _otpController,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: 6,
                decoration: InputDecoration(
                  hintText: "— — — — — —",
                  hintStyle: const TextStyle(letterSpacing: 10),
                  contentPadding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 32),

              // Verify Button
              ElevatedButton(
                onPressed: _isLoading ? null : _verifyOtp,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kButtonBlue,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 5,
                ),
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
                        "Verify Code and Log In",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
              ),
              const SizedBox(height: 16),
              
              // Resend Code Button
              TextButton(
                onPressed: () {
                  // TODO: Implement resend logic (call signInWithOtp again)
                  _showSnackBar("Resend feature not yet implemented.");
                },
                child: const Text("Resend Code", style: TextStyle(color: kPrimaryBlue, fontWeight: FontWeight.w600)),
              )
            ],
          ),
        ),
      ),
    );
  }
}