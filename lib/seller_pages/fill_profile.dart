import 'package:flutter/material.dart';
import '../bahay.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/seller_approval_notifications.dart';

// Defined constants for consistent design
const Color kPrimaryBlue = Color(0xFF2A4BA0);
const Color kPrimaryBlueDark = Color(0xFF132A63);
const Color kInactiveGrey = Color(0xFFE0E0E0);
const Color kTextGrey = Color(0xFF757575);

class BusinessProfileScreen extends StatefulWidget {
  const BusinessProfileScreen({
    super.key,
    this.initialStoreName,
    this.initialStoreAddress,
  });

  /// Values carried over from the previous "Fill business information" step
  /// so the seller can confirm what they already entered rather than re-type.
  final String? initialStoreName;
  final String? initialStoreAddress;

  @override
  State<BusinessProfileScreen> createState() => _BusinessProfileScreenState();
}

class _BusinessProfileScreenState extends State<BusinessProfileScreen> {
  // Controllers for input fields
  late final TextEditingController _storeInfoController;
  late final TextEditingController _storeAddressController;
  final TextEditingController _contactEmailController = TextEditingController();

  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _storeInfoController = TextEditingController(
      text: widget.initialStoreName?.trim() ?? '',
    );
    _storeAddressController = TextEditingController(
      text: widget.initialStoreAddress?.trim() ?? '',
    );
    final userEmail = Supabase.instance.client.auth.currentUser?.email;
    if (userEmail != null && userEmail.isNotEmpty) {
      _contactEmailController.text = userEmail;
    }
  }

  bool _isValidEmail(String email) {
    return RegExp(r'^[\w.-]+@[\w.-]+\.\w{2,}$').hasMatch(email);
  }

  @override
  void dispose() {
    _storeInfoController.dispose();
    _storeAddressController.dispose();
    _contactEmailController.dispose();
    super.dispose();
  }

  void _showActionSnackbar(
    BuildContext context,
    String action, {
    bool isError = false,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(action),
        duration: const Duration(milliseconds: 2000),
        backgroundColor: isError ? Colors.red.shade700 : kPrimaryBlue,
      ),
    );
  }

  // Function to handle the final submission to Supabase
  Future<void> _submitFinalProfileData(BuildContext context) async {
    if (_isSubmitting) return;
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;

    if (userId == null) {
      _showActionSnackbar(
        context,
        "Authentication Error. Please log in again.",
        isError: true,
      );
      return;
    }

    final contactEmail = _contactEmailController.text.trim();

    if (_storeInfoController.text.trim().isEmpty ||
        _storeAddressController.text.trim().isEmpty ||
        contactEmail.isEmpty ||
        !_isValidEmail(contactEmail)) {
      _showActionSnackbar(
        context,
        "Please fill in all required fields and enter a valid contact email.",
        isError: true,
      );
      return;
    }

    setState(() => _isSubmitting = true);
    _showActionSnackbar(
      context,
      "Finalizing profile submission...",
      isError: false,
    );

    try {
      // Fetch the user's name to satisfy not-null columns if row is new
      String? fullName;
      try {
        final profile = await supabase
            .from('profile')
            .select('name')
            .eq('user_id', userId)
            .maybeSingle();
        fullName = profile?['name']?.toString();
      } catch (_) {}
      fullName ??= supabase.auth.currentUser?.email?.split('@')[0] ?? 'Seller';

      // Collect the remaining profile data
      final finalProfileData = {
        'user_id': userId, // Key for upsert matching
        'full_name': fullName,
        'store_name': _storeInfoController.text,
        'store_information_final': _storeInfoController.text,
        'store_address': _storeAddressController.text,
        'official_contact_email': contactEmail,
        'is_profile_finalized':
            true, // Mark the entire profile creation as complete
        'approval_status': 'pending',
        'approval_email_sent_at': null,
      };

      // Update the existing seller profile record with the final details
      // It uses the same table 'seller_profiles' from fill_business_info.dart
      await supabase
          .from('seller_profiles')
          .upsert(finalProfileData, onConflict: 'user_id');

      // Best effort bridge: mirror pending seller data to common vendor tables
      // used by an existing external admin web panel.
      try {
        final syncResult = await SellerApprovalNotifications()
            .syncExternalAdmin(
              userId: userId,
              storeName: _storeInfoController.text.trim(),
              stallNo: '',
              businessType: 'Retail Store',
              contactEmail: contactEmail,
            );
        debugPrint('syncExternalAdmin result: $syncResult');

        final syncedTables = (syncResult['syncedTables'] as List?)
            ?.map((e) => e.toString())
            .toList(growable: false);
        final ok = syncResult['ok'] == true;

        if (!ok && context.mounted) {
          _showActionSnackbar(
            context,
            'Admin sync warning: no matching vendor table mapping found yet.',
            isError: true,
          );
        } else if (syncedTables != null &&
            syncedTables.isNotEmpty &&
            context.mounted) {
          _showActionSnackbar(
            context,
            'Synced to admin table(s): ${syncedTables.join(', ')}',
          );
        }
      } catch (_) {
        // Do not block seller flow if external admin table mapping is not present.
        debugPrint('syncExternalAdmin threw an exception.');
      }

      // Best effort: trigger a submission-received email via Edge Function.
      // Approval emails are triggered later by server-side approval checks.
      try {
        final emailResult = await SellerApprovalNotifications()
            .sendSubmissionReceivedEmail(
              email: contactEmail,
              storeName: _storeInfoController.text.trim(),
            );
        debugPrint('sendSubmissionReceivedEmail result: $emailResult');

        final emailOk = emailResult['ok'] == true;
        if (context.mounted && !emailOk) {
          _showActionSnackbar(
            context,
            emailResult['message']?.toString() ??
                'Email notification was not sent. Please verify email service setup.',
            isError: true,
          );
        } else if (context.mounted) {
          _showActionSnackbar(
            context,
            'Submission email sent to $contactEmail',
          );
        }
      } catch (e) {
        // Keep seller flow successful even if notification infra is unavailable.
        debugPrint('sendSubmissionReceivedEmail threw: $e');
        if (context.mounted) {
          _showActionSnackbar(
            context,
            'Email function error: $e',
            isError: true,
          );
        }
      }

      if (!context.mounted) return;
      _showActionSnackbar(
        context,
        "Application submitted. Status: Pending review. Approval notice is currently shown in-app.",
        isError: false,
      );

      // Navigate to the buyer app — seller dashboard is accessed from Profile once approved
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const Bahay()),
        (route) => false,
      );
    } on PostgrestException catch (e) {
      if (!context.mounted) return;
      _showActionSnackbar(
        context,
        "Database Error: ${e.message}",
        isError: true,
      );
    } catch (e) {
      if (!context.mounted) return;
      _showActionSnackbar(
        context,
        "An unexpected error occurred: $e",
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Back icon (using an AppBar-like structure for better alignment)
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back, color: Colors.black),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Complete Final Details',
                    style: TextStyle(color: Colors.black, fontSize: 16),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [kPrimaryBlue, kPrimaryBlueDark],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: kPrimaryBlue.withValues(alpha: 0.25),
                      blurRadius: 18,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: const Row(
                  children: [
                    Icon(Icons.verified_user_rounded,
                        color: Colors.white, size: 26),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Business Profile",
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            "Confirm your details before dashboard activation.",
                            style: TextStyle(
                              color: Color(0xFFE3EAFB),
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          "Confirm Your Details",
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: Colors.black87,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE7EEFF),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text(
                            'FROM PREVIOUS STEP',
                            style: TextStyle(
                              fontSize: 9,
                              letterSpacing: 0.6,
                              fontWeight: FontWeight.w800,
                              color: kPrimaryBlue,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'These were taken from the previous step. Tap to edit if anything looks off.',
                      style: TextStyle(color: kTextGrey, fontSize: 12),
                    ),
                    const SizedBox(height: 16),
                    _buildTextField(
                      label: "Store Name *",
                      controller: _storeInfoController,
                      hint: "Your registered store name",
                      icon: Icons.storefront_rounded,
                    ),
                    const SizedBox(height: 20),
                    _buildTextField(
                      label: "Store Address *",
                      controller: _storeAddressController,
                      hint: "Street, barangay, city",
                      icon: Icons.location_on_rounded,
                    ),
                    const SizedBox(height: 20),
                    _buildTextField(
                      label: "Official Contact Email *",
                      controller: _contactEmailController,
                      hint: "e.g., contact@yourstore.com",
                      keyboardType: TextInputType.emailAddress,
                      icon: Icons.mail_rounded,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // Finalize submission button (modernised CTA with gradient + loading state)
              _FinalizeButton(
                isLoading: _isSubmitting,
                onPressed: () => _submitFinalProfileData(context),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  // Custom text field helper widget
  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    String hint = '',
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
    IconData? icon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            color: Colors.black,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboardType,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: kTextGrey.withValues(alpha: 0.7)),
            prefixIcon: icon != null
                ? Icon(icon, color: kPrimaryBlue, size: 20)
                : null,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
            filled: true,
            fillColor: const Color(0xFFF7F9FD),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300, width: 1.0),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: kPrimaryBlue, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}

/// Modernised submit CTA — gradient fill, soft elevation, built-in loading
/// state so the button itself communicates progress without a separate
/// indicator beside it.
class _FinalizeButton extends StatefulWidget {
  const _FinalizeButton({required this.isLoading, required this.onPressed});

  final bool isLoading;
  final VoidCallback onPressed;

  @override
  State<_FinalizeButton> createState() => _FinalizeButtonState();
}

class _FinalizeButtonState extends State<_FinalizeButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final disabled = widget.isLoading;
    return AnimatedScale(
      scale: _pressed ? 0.985 : 1,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: disabled ? null : widget.onPressed,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            height: 58,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: disabled
                    ? const [Color(0xFF9CA3AF), Color(0xFF6B7280)]
                    : const [kPrimaryBlue, kPrimaryBlueDark],
              ),
              boxShadow: disabled
                  ? const []
                  : [
                      BoxShadow(
                        color: kPrimaryBlue.withValues(alpha: 0.32),
                        blurRadius: 22,
                        offset: const Offset(0, 12),
                      ),
                    ],
            ),
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: widget.isLoading
                    ? const Row(
                        key: ValueKey('loading'),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.4,
                            ),
                          ),
                          SizedBox(width: 12),
                          Text(
                            'Submitting…',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      )
                    : const Row(
                        key: ValueKey('idle'),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle_rounded,
                              color: Colors.white, size: 22),
                          SizedBox(width: 10),
                          Text(
                            'Finalize & Register Profile',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
