import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/helpers.dart';

// This page is responsible for accepting the 6-digit code sent via SMS or Email
class OtpVerificationPage extends StatefulWidget {
  final String contact;

  // The constructor must use the named parameter syntax
  const OtpVerificationPage({
    super.key,
    required this.contact,
  }); 

  @override
  State<OtpVerificationPage> createState() => _OtpVerificationPageState();
}

class _OtpVerificationPageState extends State<OtpVerificationPage> {
  final supabase = Supabase.instance.client;
  final TextEditingController _otpController = TextEditingController();
  bool _isLoading = false;
  bool _isResending = false;

  // Cooldown so a successful resend disables the button for a beat —
  // matches Supabase's own server-side rate limit and keeps the user from
  // burning through OTP requests on a slow network.
  int _resendSeconds = 0;
  Timer? _resendTimer;

  static const Color kPrimaryBlue = Color(0xFF2A4BA0);
  static const Color kButtonBlue = Color(0xFF153075);

  bool get _isEmailContact => isEmail(widget.contact);

  @override
  void dispose() {
    _otpController.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  void _startResendCooldown([int seconds = 45]) {
    _resendTimer?.cancel();
    if (!mounted) return;
    setState(() => _resendSeconds = seconds);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _resendSeconds = _resendSeconds - 1;
        if (_resendSeconds <= 0) {
          _resendSeconds = 0;
          timer.cancel();
        }
      });
    });
  }

  Future<void> _resendOtp() async {
    if (_isResending || _resendSeconds > 0) return;
    setState(() => _isResending = true);
    try {
      if (_isEmailContact) {
        await supabase.auth.resend(
          type: OtpType.signup,
          email: widget.contact,
        );
      } else {
        await supabase.auth.resend(
          type: OtpType.sms,
          phone: widget.contact,
        );
      }
      if (!mounted) return;
      _showSnackBar('A new code was sent to ${widget.contact}.');
      _startResendCooldown();
    } on AuthException catch (e) {
      // Supabase returns the remaining seconds in the message body when the
      // server-side rate limit kicks in (e.g. "For security purposes, you
      // can only request this after 28 seconds."). Parse it so the cooldown
      // shows the real value instead of our default 45s guess.
      final message = e.message;
      final match = RegExp(r'(\d+)\s*seconds').firstMatch(message);
      if (match != null) {
        final remaining = int.tryParse(match.group(1) ?? '') ?? 45;
        _startResendCooldown(remaining);
        _showSnackBar(
          'Please wait $remaining seconds before requesting another code.',
        );
      } else {
        _showSnackBar('Resend failed: $message');
      }
    } catch (e) {
      _showSnackBar('Could not resend code: $e');
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  // --- Core OTP Verification Logic ---
  Future<void> _verifyOtp() async {
    final token = _otpController.text.trim();
    if (token.length != 8) {
      _showSnackBar("Please enter the 8-digit verification code.");
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Verify the OTP using the contact (email or phone) and the received token
      final AuthResponse res;
      if (_isEmailContact) {
        res = await supabase.auth.verifyOTP(
          type: OtpType.signup, // 'signup' is specifically for new email registrations
          email: widget.contact,
          token: token,
        );
      } else {
        res = await supabase.auth.verifyOTP(
          type: OtpType.sms,
          phone: widget.contact,
          token: token,
        );
      }

      if (res.session != null) {
        _showSnackBar("Verification Successful! Welcome to QuickCart.");
        if (!mounted) return;

        _otpController.clear();
        
        // Ensure user has the buyer role before going to home
        try {
          await supabase.from('user_roles').upsert({
            'user_id': res.user!.id,
            'role': 'buyer',
          });
        } catch (_) {}

        if (!mounted) return;
        // Navigate to the home screen
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil('/home', (Route<dynamic> route) => false);
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
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(_isEmailContact ? 'Verify Email' : 'Verify Phone Number'),
        backgroundColor: kButtonBlue,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
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
                      const Icon(
                        Icons.lock_open,
                        size: 70,
                        color: kPrimaryBlue,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        "Enter Verification Code",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "We sent an 8-digit code to ${widget.contact}",
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                      ),
                      const SizedBox(height: 22),
                      TextField(
                        controller: _otpController,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        textAlign: TextAlign.center,
                        maxLength: 8,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        onSubmitted: (_) {
                          if (!_isLoading) {
                            _verifyOtp();
                          }
                        },
                        decoration: InputDecoration(
                          hintText: "- - - - - - - -",
                          hintStyle: const TextStyle(letterSpacing: 6),
                          counterText: "",
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 20,
                            horizontal: 16,
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
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 4,
                        ),
                      ),
                      const SizedBox(height: 22),
                      ElevatedButton(
                        onPressed: _isLoading ? null : _verifyOtp,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kButtonBlue,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 4,
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
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: (_isResending || _resendSeconds > 0)
                            ? null
                            : _resendOtp,
                        child: _isResending
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: kPrimaryBlue,
                                ),
                              )
                            : Text(
                                _resendSeconds > 0
                                    ? 'Resend code in ${_resendSeconds}s'
                                    : 'Resend Code',
                                style: TextStyle(
                                  color: _resendSeconds > 0
                                      ? Colors.grey
                                      : kPrimaryBlue,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
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
