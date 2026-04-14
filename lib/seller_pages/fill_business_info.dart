import 'package:flutter/material.dart';
import 'fill_profile.dart'; // Contains BusinessProfileScreen
import 'package:flutter/foundation.dart'
    show kIsWeb; // Needed for platform checks

// --- CONDITIONAL DEPENDENCIES for File Picking ---
// Use this pattern to prevent compilation errors on the web.
import 'dart:io' if (dart.library.html) 'dart:io';
import 'package:file_picker/file_picker.dart'
    if (dart.library.html) 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:path/path.dart';
// ----------------------------------------------

// Defined constants for consistent design
const Color kPrimaryBlue = Color(0xFF3455EB);
const Color kInactiveGrey = Color(0xFFE0E0E0);
const Color kTextGrey = Color(0xFF757575);
const int kTotalSteps = 6; // Now consistently 6

class FillBusinessInfoPage extends StatefulWidget {
  const FillBusinessInfoPage({super.key});

  @override
  State<FillBusinessInfoPage> createState() => _FillBusinessInfoPageState();
}

class _FillBusinessInfoPageState extends State<FillBusinessInfoPage> {
  // State variables for inputs
  String _selectedBusinessCategory = 'Retail Store';
  final TextEditingController _storeNameController = TextEditingController(
    text: '',
  );
  int _permitCount = 0;
  bool _hasBankAccount = false;
  String? _logoUrl;

  // 🎯 NEW: State for Steps 5 and 6 (Simulated/Placeholder)
  bool _productsAdded = false;
  bool _contactInfoSet = false;

  // Calculates the number of completed steps out of 6 total steps
  int get _completedSteps {
    int steps = 0;

    // Step 1: Store Information (Name & Category)
    if (_storeNameController.text.isNotEmpty) {
      steps++;
    }

    // Step 2: Bank Accounts
    if (_hasBankAccount) {
      steps++;
    }

    // Step 3: Permits
    if (_permitCount > 0) {
      steps++;
    }

    // Step 4: Logo Upload
    if (_logoUrl != null) {
      steps++;
    }

    // Step 5: Products/Services (NEW TRACKING)
    if (_productsAdded) {
      steps++;
    }

    // Step 6: Store Contact (NEW TRACKING)
    if (_contactInfoSet) {
      steps++;
    }

    return steps;
  }

  @override
  void dispose() {
    _storeNameController.dispose();
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

  // 🎯 NEW: Simulation for Products/Services Step
  void _simulateProductsAdded(BuildContext context) async {
    _showActionSnackbar(
      context,
      "Simulating product listing and inventory setup...",
    );
    await Future.delayed(const Duration(milliseconds: 500));
    if (!context.mounted) return;
    setState(() {
      _productsAdded = true;
    });
    _showActionSnackbar(
      context,
      "Products/Services marked as complete!",
      isError: false,
    );
  }

  // 🎯 NEW: Simulation for Contact Info Step
  void _simulateContactSet(BuildContext context) async {
    _showActionSnackbar(
      context,
      "Simulating setting up store contact details...",
    );
    await Future.delayed(const Duration(milliseconds: 500));
    if (!context.mounted) return;
    setState(() {
      _contactInfoSet = true;
    });
    _showActionSnackbar(
      context,
      "Contact Information marked as complete!",
      isError: false,
    );
  }

  // --- LOGO UPLOAD FUNCTION (SIMULATED) ---
  Future<void> _uploadLogo(BuildContext context) async {
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;

    if (userId == null) {
      _showActionSnackbar(context, "Error: User not logged in.", isError: true);
      return;
    }

    if (kIsWeb) {
      // Simulate successful file pick and upload on Web
      _showActionSnackbar(context, "Web Platform: Logo upload simulated.");
      await Future.delayed(const Duration(milliseconds: 500));
      if (!context.mounted) return;
      setState(() {
        // Simulate a successful upload by setting a placeholder URL
        _logoUrl = "https://placehold.co/100x100/3455EB/FFFFFF/png?text=LOGO";
      });
      _showActionSnackbar(
        context,
        "Logo simulated uploaded successfully!",
        isError: false,
      );
      return;
    }

    // --- REAL LOGIC (Mobile/Desktop) ---
    // Note: Actual logic would involve FilePicker, upload, and getting the public URL.
    _showActionSnackbar(
      context,
      "Mobile/Desktop: Logo upload functionality placeholder.",
    );

    // Fallback simulation for non-web environments without file access
    await Future.delayed(const Duration(milliseconds: 500));
    if (!context.mounted) return;
    setState(() {
      _logoUrl = "https://placehold.co/100x100/3455EB/FFFFFF/png?text=LOGO";
    });
    _showActionSnackbar(
      context,
      "Logo simulated uploaded successfully!",
      isError: false,
    );
  }

  // --- PERMIT ATTACHMENT FUNCTION (REAL FILE PICKER LOGIC) ---
  Future<void> _attachPermitPhoto(BuildContext context) async {
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;

    if (userId == null) {
      _showActionSnackbar(
        context,
        "Error: User not logged in. Please ensure Supabase auth is set up.",
        isError: true,
      );
      return;
    }

    if (kIsWeb) {
      _showActionSnackbar(
        context,
        "Web Platform detected: File uploading is simulated.",
      );
      await Future.delayed(const Duration(milliseconds: 500));
      if (!context.mounted) return;
      setState(() {
        _permitCount++;
      });
      _showActionSnackbar(
        context,
        "Permit photo simulated uploaded successfully! Count: $_permitCount",
        isError: false,
      );
      return;
    }

    // --- REAL LOGIC (Mobile/Desktop) ---
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
    } catch (e) {
      if (!context.mounted) return;
      _showActionSnackbar(
        context,
        "File Picker Error. Check platform configurations.",
        isError: true,
      );
      return;
    }

    if (!context.mounted) return;

    if (result == null || result.files.single.path == null) {
      _showActionSnackbar(context, "No file selected.");
      return;
    }

    final file = result.files.single;
    final filePath = file.path!;
    final fileName = basename(filePath);

    _showActionSnackbar(context, "Uploading $fileName...");

    try {
      final fileBytes = await File(filePath).readAsBytes();
      if (!context.mounted) return;
      final uploadPath = '$userId/permits/$fileName';

      await supabase.storage
          .from('Permits')
          .uploadBinary(
            uploadPath,
            fileBytes,
            fileOptions: const FileOptions(cacheControl: '3600', upsert: true),
          );

      if (!context.mounted) return;
      setState(() {
        _permitCount++;
      });
      _showActionSnackbar(
        context,
        "Permit photo uploaded successfully! Count: $_permitCount",
        isError: false,
      );
    } on StorageException catch (e) {
      if (!context.mounted) return;
      _showActionSnackbar(
        context,
        "Supabase Upload Error: ${e.message}",
        isError: true,
      );
    } catch (e) {
      if (!context.mounted) return;
      _showActionSnackbar(context, "Upload failed: $e", isError: true);
    }
  }

  // --- FINAL SUBMISSION LOGIC ---
  Future<void> _submitDataToSupabase(BuildContext context) async {
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

    if (_completedSteps < kTotalSteps) {
      // Check that ALL 6 steps are done
      _showActionSnackbar(
        context,
        "Please complete all $kTotalSteps steps before proceeding.",
        isError: true,
      );
      return;
    }

    _showActionSnackbar(context, "Saving business data...", isError: false);

    try {
      // 🎯 Collect all business information into a map
      final businessData = {
        'user_id': userId, // Ensure we link it to the current user
        'store_name': _storeNameController.text,
        'category': _selectedBusinessCategory,
        'has_bank_account': _hasBankAccount,
        'permit_count': _permitCount,
        'logo_url': _logoUrl,
        'products_added': _productsAdded, // NEW FIELD
        'contact_info_set': _contactInfoSet, // NEW FIELD
        'is_info_complete': true, // Mark this stage as complete
        'created_at': DateTime.now().toIso8601String(),
      };

      // Upsert (Insert or Update) the seller profile data in a hypothetical 'seller_profiles' table
      await supabase
          .from('seller_profiles')
          .upsert(
            businessData,
            onConflict: 'user_id', // Conflict resolution based on user_id
          );

      if (!context.mounted) return;
      _showActionSnackbar(
        context,
        "Business information saved successfully!",
        isError: false,
      );

      // Navigate to the next stage
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const BusinessProfileScreen()),
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

  // Helper widget for the Input Field to keep the UI clean
  Widget _buildInputField({
    required String label,
    required TextEditingController controller,
    String hint = '',
    IconData? icon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: hint,
            contentPadding: const EdgeInsets.symmetric(
              vertical: 16,
              horizontal: 16,
            ),
            filled: true,
            fillColor: Colors.white,
            prefixIcon: icon != null ? Icon(icon, color: kTextGrey) : null,
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
          onChanged: (text) {
            // Force UI update on text change to reflect in the Progress Box
            setState(() {});
          },
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  // --- Bank Account Modal (Unchanged) ---
  void _addBankAccount(BuildContext context) {
    final TextEditingController accountNameController = TextEditingController();
    final TextEditingController accountNumberController =
        TextEditingController();

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text(
            'Add Bank Account',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                const Text(
                  'Account Name',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: accountNameController,
                  decoration: InputDecoration(
                    hintText: "e.g., Juan Dela Cruz",
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Account Number',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: accountNumberController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: "1234567890",
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Note: This is simulated for the preview.',
                  style: TextStyle(fontSize: 12, color: kTextGrey),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel', style: TextStyle(color: kTextGrey)),
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimaryBlue,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                if (accountNameController.text.isNotEmpty &&
                    accountNumberController.text.length >= 8) {
                  setState(() {
                    _hasBankAccount = true; // Set state to completed
                  });
                  Navigator.of(dialogContext).pop();
                  _showActionSnackbar(
                    context,
                    'Bank Account added successfully!',
                    isError: false,
                  );
                } else {
                  _showActionSnackbar(
                    context,
                    'Please enter valid account details.',
                    isError: true,
                  );
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final double progress = _completedSteps / kTotalSteps;
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Fill your business information',
          style: TextStyle(color: Colors.black, fontSize: 16),
        ),
        centerTitle: false,
        // 🎯 NEW: Add a visual progress bar beneath the AppBar
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4.0),
          child: LinearProgressIndicator(
            value: progress,
            backgroundColor: kInactiveGrey,
            valueColor: const AlwaysStoppedAnimation<Color>(kPrimaryBlue),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: kPrimaryBlue.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: kPrimaryBlue.withValues(alpha: 0.15)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.storefront_rounded,
                      color: kPrimaryBlue,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Business Setup Progress',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: kPrimaryBlue,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Complete all requirements to continue to profile completion.',
                          style: TextStyle(
                            color: Colors.black.withValues(alpha: 0.7),
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 1. Logo Upload Area
            InkWell(
              onTap: () => _uploadLogo(context),
              child: Center(
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: _logoUrl != null ? kPrimaryBlue : kInactiveGrey,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.grey.shade50,
                  ),
                  child: _logoUrl != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(
                            _logoUrl!,
                            fit: BoxFit.cover,
                            // Added an error builder just in case the placeholder fails to load
                            errorBuilder: (context, error, stackTrace) =>
                                _buildDefaultLogo(),
                          ),
                        )
                      : _buildDefaultLogo(),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // 2. Business Category Dropdown
            const Text(
              "Business Category",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: _selectedBusinessCategory,
                  style: const TextStyle(color: Colors.black, fontSize: 16),
                  items: const [
                    DropdownMenuItem(
                      value: 'Retail Store',
                      child: Text('Retail Store'),
                    ),
                    DropdownMenuItem(
                      value: 'Service Provider',
                      child: Text('Service Provider'),
                    ),
                    DropdownMenuItem(
                      value: 'Food & Beverage',
                      child: Text('Food & Beverage'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _selectedBusinessCategory = value;
                      });
                      _showActionSnackbar(
                        context,
                        "Category changed to $value.",
                      );
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 20),

            // 3. Store Name Text Field
            _buildInputField(
              label: "Store Name",
              controller: _storeNameController,
              hint: "Enter your store name",
              icon: Icons.storefront_outlined,
            ),

            // 4. Progress indicator box
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withValues(alpha: 0.1),
                    spreadRadius: 1,
                    blurRadius: 5,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Your Store Setup Checklist',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        '$_completedSteps/$kTotalSteps Complete',
                        style: TextStyle(
                          color: kPrimaryBlue,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 7,
                      backgroundColor: kInactiveGrey,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        kPrimaryBlue,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Store Name Display
                  Text(
                    _storeNameController.text.isNotEmpty
                        ? _storeNameController.text
                        : 'Store Name Not Set',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  const Divider(height: 20, thickness: 1, color: kInactiveGrey),

                  // List items
                  // Step 1: Store Information
                  _ListItem(
                    title: 'Store Information (Name & Category)',
                    subtitle: 'Fill in basic store information',
                    onTap: () => _showActionSnackbar(
                      context,
                      'Store Information fields are above this progress box.',
                    ),
                    isCompleted: _storeNameController.text.isNotEmpty,
                  ),
                  // Step 2: Logo Upload
                  _ListItem(
                    title: 'Business Logo',
                    subtitle: _logoUrl != null
                        ? 'Logo uploaded successfully.'
                        : 'Upload your official business logo.',
                    onTap: () => _uploadLogo(context),
                    isCompleted: _logoUrl != null,
                    showRightArrow: true,
                  ),
                  // Step 3: Bank Accounts
                  _ListItem(
                    title: 'Bank Accounts',
                    subtitle: _hasBankAccount
                        ? 'Account registered.'
                        : 'Register your bank account to receive earnings',
                    onTap: () => _addBankAccount(context),
                    isCompleted: _hasBankAccount,
                  ),

                  // Step 4: Permits Section (Original complex layout)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _ListItem(
                          title: 'Permits',
                          subtitle:
                              'Photos of your business permits (required)',
                          onTap: () => _attachPermitPhoto(context),
                          isCompleted: _permitCount > 0,
                          showRightArrow:
                              false, // Hide arrow to make space for button
                        ),
                        Padding(
                          padding: const EdgeInsets.only(
                            left: 32.0,
                            top: 8,
                            bottom: 8,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  'Attached: $_permitCount photos',
                                  style: const TextStyle(
                                    color: kTextGrey,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                height: 32,
                                child: OutlinedButton.icon(
                                  onPressed: () => _attachPermitPhoto(context),
                                  icon: const Icon(Icons.upload_file, size: 18),
                                  label: const Text(
                                    'Upload Permit',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: kPrimaryBlue,
                                    side: const BorderSide(color: kPrimaryBlue),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Step 5: Products/Services (NEW)
                  _ListItem(
                    title: 'Products/Services Listing',
                    subtitle: _productsAdded
                        ? 'Product list simulated.'
                        : 'Add your first products or services.',
                    onTap: () => _simulateProductsAdded(context),
                    isCompleted: _productsAdded,
                  ),

                  // Step 6: Store Contact (NEW)
                  _ListItem(
                    title: 'Store Contact Information',
                    subtitle: _contactInfoSet
                        ? 'Contact details simulated.'
                        : 'Set up your customer support contact details.',
                    onTap: () => _simulateContactSet(context),
                    isCompleted: _contactInfoSet,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 48),

            // 5. Submit Button (Enabled only when all steps are complete)
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
                onPressed: _completedSteps == kTotalSteps
                    ? () => _submitDataToSupabase(context)
                    : null, // Disable button if not all steps are complete
                child: Text(
                  _completedSteps == kTotalSteps
                      ? 'Next: Complete Profile'
                      : 'Complete All Steps ($_completedSteps/$kTotalSteps)',
                  style: const TextStyle(
                    fontSize: 18,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Helper widget for the default logo placeholder
  Widget _buildDefaultLogo() {
    return const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.add_a_photo_outlined, size: 36, color: kTextGrey),
        Text("Add Logo", style: TextStyle(color: kTextGrey, fontSize: 12)),
      ],
    );
  }
}

// Refactored ListItem to be reusable (Unchanged)
class _ListItem extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool isCompleted;
  final bool showRightArrow;

  const _ListItem({
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.isCompleted,
    this.showRightArrow = true,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            Icon(
              isCompleted ? Icons.check_circle : Icons.radio_button_unchecked,
              color: isCompleted ? kPrimaryBlue : kTextGrey,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: isCompleted ? Colors.black : kTextGrey,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(color: kTextGrey, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (showRightArrow) // Conditionally show arrow
              const Icon(Icons.chevron_right, color: kTextGrey, size: 20),
          ],
        ),
      ),
    );
  }
}
