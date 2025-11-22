import 'package:flutter/material.dart';
import 'dashboard_screen.dart'; // Import the final destination
import 'package:supabase_flutter/supabase_flutter.dart';

// Defined constants for consistent design
const Color kPrimaryBlue = Color(0xFF3455EB);
const Color kInactiveGrey = Color(0xFFE0E0E0);
const Color kTextGrey = Color(0xFF757575);

class BusinessProfileScreen extends StatefulWidget {
  const BusinessProfileScreen({super.key});

  @override
  State<BusinessProfileScreen> createState() => _BusinessProfileScreenState();
}

class _BusinessProfileScreenState extends State<BusinessProfileScreen> {
  // Controllers for input fields
  final TextEditingController _storeInfoController =
      TextEditingController(text: 'The Ultimate Bazaar');
  final TextEditingController _stallNumberController =
      TextEditingController(text: 'Stall 4A');
  final TextEditingController _storeAddressController =
      TextEditingController(text: '123 Market Street, Downtown Area');
  final TextEditingController _contactEmailController =
      TextEditingController(text: 'official@ultimatebazaar.com');

  @override
  void dispose() {
    _storeInfoController.dispose();
    _stallNumberController.dispose();
    _storeAddressController.dispose();
    _contactEmailController.dispose();
    super.dispose();
  }

  void _showActionSnackbar(BuildContext context, String action, {bool isError = false}) {
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
      _showActionSnackbar(context, "Authentication Error. Please log in again.", isError: true);
      return;
    }

    if (_storeInfoController.text.isEmpty || _storeAddressController.text.isEmpty) {
      _showActionSnackbar(context, "Please fill in all required fields (*).", isError: true);
      return;
    }

    _showActionSnackbar(context, "Finalizing profile submission...", isError: false);

    try {
      // Collect the remaining profile data
      final finalProfileData = {
        'user_id': userId, // Key for upsert matching
        'store_information_final': _storeInfoController.text,
        'stall_number': _stallNumberController.text,
        'store_address': _storeAddressController.text,
        'official_contact_email': _contactEmailController.text,
        'is_profile_finalized': true, // Mark the entire profile creation as complete
      };

      // Update the existing seller profile record with the final details
      // It uses the same table 'seller_profiles' from fill_business_info.dart
      await supabase.from('seller_profiles').upsert(
            finalProfileData,
            onConflict: 'user_id',
          );

      _showActionSnackbar(context, "Profile submitted successfully!", isError: false);

      // Navigate to the final Seller Dashboard (SellerHomePage) and clear navigation history
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const ShopDashboardScreen()),
        );
      }
    } on PostgrestException catch (e) {
      _showActionSnackbar(context, "Database Error: ${e.message}", isError: true);
    } catch (e) {
      _showActionSnackbar(context, "An unexpected error occurred: $e", isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
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

              // Title
              const Text(
                "Business Profile",
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: kPrimaryBlue,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                "Complete the store and business information that will be registered.",
                style: TextStyle(color: kTextGrey, fontSize: 14),
              ),

              const SizedBox(height: 32),

              // Section header
              const Text(
                "General Information",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.black87
                ),
              ),

              const SizedBox(height: 16),

              // Store name input
              _buildTextField(
                label: "Store Description / Information *",
                controller: _storeInfoController,
                hint: "Provide a short description of your store or services",
                maxLines: 3,
              ),

              const SizedBox(height: 20),

              _buildTextField(
                label: "Stall Number",
                controller: _stallNumberController,
                hint: "e.g., Kiosk 2B or Stall 4A",
              ),

              const SizedBox(height: 20),

              // Store address section
              _buildTextField(
                label: "Store/Office Address *",
                controller: _storeAddressController,
                hint: "Full operational address",
              ),
              
              const SizedBox(height: 20),

              // Official Contact Email
              _buildTextField(
                label: "Official Contact Email *",
                controller: _contactEmailController,
                hint: "e.g., contact@yourstore.com",
                keyboardType: TextInputType.emailAddress,
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
          style: const TextStyle(fontSize: 14, color: Colors.black, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboardType,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: kTextGrey.withOpacity(0.7)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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