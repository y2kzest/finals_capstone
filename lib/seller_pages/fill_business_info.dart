import 'package:flutter/material.dart';
import 'fill_profile.dart'; // Contains BusinessProfileScreen
import 'package:flutter/foundation.dart' show kIsWeb; // Needed for platform checks

// --- CONDITIONAL DEPENDENCIES for File Picking ---
// Use this pattern to prevent compilation errors on the web.
import 'dart:io' if (dart.library.html) 'dart:io'; 
import 'package:file_picker/file_picker.dart' if (dart.library.html) 'package:file_picker/file_picker.dart'; 
import 'package:supabase_flutter/supabase_flutter.dart'; 
import 'package:path/path.dart'; 
// ----------------------------------------------


// Defined constants for consistent design
const Color kPrimaryBlue = Color(0xFF3455EB);
const Color kInactiveGrey = Color(0xFFE0E0E0);
const Color kTextGrey = Color(0xFF757575);

class FillBusinessInfoPage extends StatefulWidget {
  const FillBusinessInfoPage({super.key});

  @override
  State<FillBusinessInfoPage> createState() => _FillBusinessInfoPageState();
}

class _FillBusinessInfoPageState extends State<FillBusinessInfoPage> {
  // State variables for inputs
  String _selectedBusinessCategory = 'Retail Store';
  final TextEditingController _storeNameController =
      TextEditingController(text: 'Aling Mirna Pork Shop');
  
  // State for tracking permit uploads
  int _permitCount = 0; 
  // State for tracking bank accounts
  bool _hasBankAccount = false; 

  // Calculates the number of completed steps out of 5 total steps
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

    // Step 3: Products/Services (Placeholder logic: assume incomplete)
    // steps += 0;

    // Step 4: Permits (Completed if at least one photo is attached)
    if (_permitCount > 0) {
      steps++;
    }

    // Step 5: Store Contact (Placeholder logic: assume incomplete)
    // steps += 0; 
    
    return steps; 
  }

  @override
  void dispose() {
    _storeNameController.dispose();
    super.dispose();
  }

  // --- FIX APPLIED: Ensure context is available when calling this function ---
  void _showActionSnackbar(BuildContext context, String action, {bool isError = false}) {
    // Linter/Compiler often prefers this explicit form when in a state class
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(action),
        duration: const Duration(milliseconds: 2000),
        backgroundColor: isError ? Colors.red.shade700 : kPrimaryBlue,
      ),
    );
  }

  // --- Bank Account Modal ---
  void _addBankAccount(BuildContext context) {
    final TextEditingController accountNameController = TextEditingController();
    final TextEditingController accountNumberController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) { // Use dialogContext for the inner scope
        return AlertDialog(
          title: const Text('Add Bank Account', style: TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                const Text('Account Name', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 8),
                TextField(
                  controller: accountNameController,
                  decoration: InputDecoration(
                    hintText: "e.g., Juan Dela Cruz",
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Account Number', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 8),
                TextField(
                  controller: accountNumberController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: "1234567890",
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                ),
                const SizedBox(height: 8),
                const Text('Note: This is simulated for the preview.', style: TextStyle(fontSize: 12, color: kTextGrey)),
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
                if (accountNameController.text.isNotEmpty && accountNumberController.text.length >= 8) {
                  setState(() {
                    _hasBankAccount = true; // Set state to completed
                  });
                  Navigator.of(dialogContext).pop();
                  // Passing the context from the outer state's build method
                  _showActionSnackbar(context, 'Bank Account added successfully!', isError: false); 
                } else {
                  _showActionSnackbar(context, 'Please enter valid account details.', isError: true);
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }


  // --- PERMIT ATTACHMENT FUNCTION (REAL FILE PICKER LOGIC) ---

  Future<void> _attachPermitPhoto(BuildContext context) async {
    // Requires Supabase to be initialized globally in your Flutter app
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;

    if (userId == null) {
      _showActionSnackbar(context, "Error: User not logged in. Please ensure Supabase auth is set up.", isError: true);
      return;
    }

    if (kIsWeb) {
      // Fallback/Placeholder for Web, as FilePicker and dart:io behave differently/fail on web preview.
      _showActionSnackbar(context, "Web Platform detected: File uploading is simulated.");
      // Simulate successful file pick and upload
      await Future.delayed(const Duration(milliseconds: 500));
       if (mounted) {
        setState(() {
          _permitCount++;
        });
        _showActionSnackbar(context, "Permit photo simulated uploaded successfully! Count: $_permitCount", isError: false);
      }
      return;
    }
    
    // --- REAL LOGIC (Mobile/Desktop) ---
    FilePickerResult? result;
    try {
      // 1. Launch File Picker to select an image
      result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
    } catch (e) {
      _showActionSnackbar(context, "File Picker Error. Check platform configurations.", isError: true);
      return;
    }

    if (result == null || result.files.single.path == null) {
      _showActionSnackbar(context, "No file selected.");
      return;
    }

    final file = result.files.single;
    final filePath = file.path!;
    final fileName = basename(filePath); 

    _showActionSnackbar(context, "Uploading $fileName...");

    try {
      // Use dart:io.File only when not on web
      final fileBytes = await File(filePath).readAsBytes(); 
      final uploadPath = '$userId/permits/$fileName'; 
      
      // 2. Upload file to Supabase Storage (assuming a bucket named 'permits' exists)
      await supabase.storage.from('permits').uploadBinary(
        uploadPath,
        fileBytes,
        fileOptions: const FileOptions(
          cacheControl: '3600',
          upsert: true,
        ),
      );

      if (mounted) {
        setState(() {
          _permitCount++;
        });
        _showActionSnackbar(context, "Permit photo uploaded successfully! Count: $_permitCount", isError: false);
      }

    } on StorageException catch (e) {
      _showActionSnackbar(context, "Supabase Upload Error: ${e.message}", isError: true);
    } catch (e) {
      _showActionSnackbar(context, "Upload failed: $e", isError: true);
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
            contentPadding:
                const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
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

  @override
  Widget build(BuildContext context) { // This context is safe to use below
    return Scaffold(
      backgroundColor: Colors.white,
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
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Logo Placeholder
            InkWell(
              onTap: () => _showActionSnackbar(context, "Logo Upload functionality placeholder."),
              child: Center(
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    border: Border.all(color: kInactiveGrey, width: 2),
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.grey.shade50,
                  ),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_a_photo_outlined, size: 36, color: kTextGrey),
                      Text("Add Logo", style: TextStyle(color: kTextGrey, fontSize: 12)),
                    ],
                  ),
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
                    DropdownMenuItem(value: 'Retail Store', child: Text('Retail Store')),
                    DropdownMenuItem(value: 'Service Provider', child: Text('Service Provider')),
                    DropdownMenuItem(value: 'Food & Beverage', child: Text('Food & Beverage')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _selectedBusinessCategory = value;
                        _showActionSnackbar(context, "Category changed to $value functionality placeholder.");
                      });
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
              hint: "e.g., Aling Mirna Pork Shop",
              icon: Icons.storefront_outlined,
            ),

            // 4. Progress indicator box (Using state data)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.1),
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
                        'Your Store Setup',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      Text(
                        '$_completedSteps/5 Complete', // Uses dynamic completion
                        style: TextStyle(color: kPrimaryBlue, fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  
                  // Store Name Display
                  Text(
                    _storeNameController.text.isNotEmpty ? _storeNameController.text : 'Store Name Not Set',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                  
                  // Action buttons
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => _showActionSnackbar(context, 'Setting Store Contact functionality placeholder.'),
                        child: const Text('Set Store Contact',
                            style: TextStyle(color: kPrimaryBlue, fontSize: 13, decoration: TextDecoration.underline)),
                      ),
                      const SizedBox(width: 16),
                      GestureDetector(
                        onTap: () => _showActionSnackbar(context, 'Editing Store Details functionality placeholder.'),
                        child: const Text('Edit Details',
                            style: TextStyle(color: kPrimaryBlue, fontSize: 13, decoration: TextDecoration.underline)),
                      ),
                    ],
                  ),
                  const Divider(height: 24, thickness: 1, color: kInactiveGrey),

                  // List items (using generic list item for non-photo steps)
                  _ListItem(
                    title: 'Store Information (Name & Category)',
                    subtitle: 'Fill in basic store information',
                    onTap: () => _showActionSnackbar(context, 'Store Information tapped functionality placeholder.'),
                    isCompleted: true, 
                  ),
                  // Bank Accounts
                  _ListItem(
                    title: 'Bank Accounts',
                    subtitle: _hasBankAccount ? 'Account registered.' : 'Register your bank account to receive earnings',
                    onTap: () => _addBankAccount(context), // Pass context here
                    isCompleted: _hasBankAccount,
                  ),
                  _ListItem(
                    title: 'Products/Services',
                    subtitle: 'Photos of your products you want to sell',
                    onTap: () => _showActionSnackbar(context, 'Products/Services tapped functionality placeholder.'),
                    isCompleted: false,
                  ),
                  
                  // Permits Section (New Interactive Block)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _ListItem(
                          title: 'Permits',
                          subtitle: 'Photos of your business permits (required)',
                          onTap: () => _attachPermitPhoto(context), // Pass context here
                          isCompleted: _permitCount > 0,
                          showRightArrow: false, // Hide arrow to make space for button
                        ),
                        Padding(
                          padding: const EdgeInsets.only(left: 32.0, top: 8, bottom: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Attached: $_permitCount photos',
                                style: const TextStyle(color: kTextGrey, fontSize: 13, fontWeight: FontWeight.w500),
                              ),
                              SizedBox(
                                height: 32,
                                child: OutlinedButton.icon(
                                  onPressed: () => _attachPermitPhoto(context), // Pass context here
                                  icon: const Icon(Icons.upload_file, size: 18),
                                  label: const Text('Upload Permit', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: kPrimaryBlue,
                                    side: const BorderSide(color: kPrimaryBlue),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                ],
              ),
            ),
            const SizedBox(height: 48),

            // 5. Submit Button (Working navigation)
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
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const BusinessProfileScreen(),
                    ),
                  );
                },
                child: const Text(
                  'Next: Complete Profile',
                  style: TextStyle(
                      fontSize: 18,
                      color: Colors.white,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Refactored ListItem to be reusable
class _ListItem extends StatelessWidget {
  final String title;
  final String subtitle;
  // VoidCallback is used here, so the calling code needs to ensure context is passed
  final VoidCallback onTap; 
  final bool isCompleted;
  final bool showRightArrow; // New property for flexibility

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
                  Text(title,
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: isCompleted ? Colors.black : kTextGrey)),
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