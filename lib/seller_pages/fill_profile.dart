import 'package:flutter/material.dart';
import '../bahay.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/seller_approval_notifications.dart';

// Defined constants for consistent design
const Color kPrimaryBlue = Color(0xFF2A4BA0);
const Color kInactiveGrey = Color(0xFFE0E0E0);
const Color kTextGrey = Color(0xFF757575);

class BusinessProfileScreen extends StatefulWidget {
  const BusinessProfileScreen({super.key});

  @override
  State<BusinessProfileScreen> createState() => _BusinessProfileScreenState();
}

class _BusinessProfileScreenState extends State<BusinessProfileScreen> {
  // Controllers for input fields
  final TextEditingController _storeInfoController = TextEditingController(
    text: 'The Ultimate Bazaar',
  );
  final TextEditingController _storeAddressController = TextEditingController(
    text: '123 Market Street, Downtown Area',
  );
  final TextEditingController _contactEmailController = TextEditingController(
    text: 'official@ultimatebazaar.com',
  );

  @override
  void initState() {
    super.initState();
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

    if (_storeInfoController.text.isEmpty ||
        _storeAddressController.text.isEmpty ||
        contactEmail.isEmpty ||
        !_isValidEmail(contactEmail)) {
      _showActionSnackbar(
        context,
        "Please fill in all required fields and enter a valid contact email.",
        isError: true,
      );
      return;
    }

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
                  borderRadius: BorderRadius.circular(14),
                  color: kPrimaryBlue.withValues(alpha: 0.08),
                  border: Border.all(
                    color: kPrimaryBlue.withValues(alpha: 0.2),
                  ),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Business Profile",
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: kPrimaryBlue,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      "Complete your final seller details before dashboard activation.",
                      style: TextStyle(color: kTextGrey, fontSize: 13),
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
                  borderRadius: BorderRadius.circular(14),
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
                    const Text(
                      "General Information",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildTextField(
                      label: "Store Description / Information *",
                      controller: _storeInfoController,
                      hint:
                          "Provide a short description of your store or services",
                      maxLines: 3,
                    ),
                    const SizedBox(height: 20),
                    _buildTextField(
                      label: "Store/Office Address *",
                      controller: _storeAddressController,
                      hint: "Full operational address",
                    ),
                    const SizedBox(height: 20),
                    _buildTextField(
                      label: "Official Contact Email *",
                      controller: _contactEmailController,
                      hint: "e.g., contact@yourstore.com",
                      keyboardType: TextInputType.emailAddress,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 40),

              // Save button (Finalize Submission)
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimaryBlue,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 5,
                  ),
                  onPressed: () => _submitFinalProfileData(context),
                  child: const Text(
                    "Finalize & Register Profile",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
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
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
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
      ],
    );
  }
}
