import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'fill_profile.dart'; // Contains BusinessProfileScreen
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/market_geo.dart';
import '../utils/marketplace_ui.dart' show AppearOnMount, staggerDelay;
import '../utils/page_transitions.dart';

// Defined constants for consistent design
const Color kPrimaryBlue = Color(0xFF2A4BA0);
const Color kPrimaryBlueDark = Color(0xFF132A63);
const Color kInactiveGrey = Color(0xFFE0E0E0);
const Color kTextGrey = Color(0xFF757575);
const int kTotalSteps = 4;

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
  final TextEditingController _storeAddressController = TextEditingController();
  final TextEditingController _marketSectionController = TextEditingController();
  LatLng? _pin;
  int _permitCount = 0;
  bool _hasBankAccount = false;
  String? _logoUrl;
  String? _bannerUrl;
  final List<String> _permitUrls = [];
  String? _idUrl;
  bool _isSubmitting = false;

  // Shop hours
  TimeOfDay _openingTime = const TimeOfDay(hour: 5, minute: 0);
  TimeOfDay _closingTime = const TimeOfDay(hour: 19, minute: 0);

  // Calculates the number of completed steps out of 3 total steps
  int get _completedSteps {
    int steps = 0;
    if (_hasBankAccount) steps++;
    if (_permitCount > 0) steps++;
    if (_logoUrl != null) steps++;
    if (_idUrl != null) steps++;
    return steps;
  }

  @override
  void dispose() {
    _storeNameController.dispose();
    _storeAddressController.dispose();
    _marketSectionController.dispose();
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

  // --- LOGO UPLOAD FUNCTION ---
  Future<void> _uploadLogo(BuildContext context) async {
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;

    if (userId == null) {
      _showActionSnackbar(context, "Error: User not logged in.", isError: true);
      return;
    }

    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true, // Required for web to get bytes
      );
    } catch (e) {
      if (!context.mounted) return;
      _showActionSnackbar(context, "File Picker Error: $e", isError: true);
      return;
    }

    if (!context.mounted) return;
    if (result == null || result.files.isEmpty) {
      _showActionSnackbar(context, "No file selected.");
      return;
    }

    final pickedFile = result.files.single;
    final Uint8List? fileBytes = pickedFile.bytes;

    if (fileBytes == null || fileBytes.isEmpty) {
      _showActionSnackbar(context, "Could not read file data.", isError: true);
      return;
    }

    final ext = pickedFile.extension ?? 'png';
    final uploadPath = '$userId/logo.$ext';

    _showActionSnackbar(context, "Uploading logo...");

    try {
      await supabase.storage.from('logos').uploadBinary(
        uploadPath,
        fileBytes,
        fileOptions: const FileOptions(cacheControl: '3600', upsert: true),
      );

      final publicUrl = supabase.storage.from('logos').getPublicUrl(uploadPath);

      if (!context.mounted) return;
      setState(() {
        _logoUrl = publicUrl;
      });
      _showActionSnackbar(context, "Logo uploaded successfully!");
    } on StorageException catch (e) {
      if (!context.mounted) return;
      _showActionSnackbar(context, "Upload Error: ${e.message}", isError: true);
    } catch (e) {
      if (!context.mounted) return;
      _showActionSnackbar(context, "Upload failed: $e", isError: true);
    }
  }

  // --- BANNER UPLOAD FUNCTION ---
  Future<void> _uploadBanner(BuildContext context) async {
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;

    if (userId == null) {
      _showActionSnackbar(context, "Error: User not logged in.", isError: true);
      return;
    }

    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true,
      );
    } catch (e) {
      if (!context.mounted) return;
      _showActionSnackbar(context, "File Picker Error: $e", isError: true);
      return;
    }

    if (!context.mounted) return;
    if (result == null || result.files.isEmpty) {
      _showActionSnackbar(context, "No file selected.");
      return;
    }

    final pickedFile = result.files.single;
    final Uint8List? fileBytes = pickedFile.bytes;

    if (fileBytes == null || fileBytes.isEmpty) {
      _showActionSnackbar(context, "Could not read file data.", isError: true);
      return;
    }

    final ext = pickedFile.extension ?? 'png';
    final uploadPath = '$userId/banner.$ext';

    _showActionSnackbar(context, "Uploading banner...");

    try {
      await supabase.storage.from('logos').uploadBinary(
        uploadPath,
        fileBytes,
        fileOptions: const FileOptions(cacheControl: '3600', upsert: true),
      );

      final publicUrl = supabase.storage.from('logos').getPublicUrl(uploadPath);

      if (!context.mounted) return;
      setState(() {
        _bannerUrl = publicUrl;
      });
      _showActionSnackbar(context, "Banner uploaded successfully!");
    } on StorageException catch (e) {
      if (!context.mounted) return;
      _showActionSnackbar(context, "Upload Error: ${e.message}", isError: true);
    } catch (e) {
      if (!context.mounted) return;
      _showActionSnackbar(context, "Upload failed: $e", isError: true);
    }
  }

  // --- PERMIT ATTACHMENT FUNCTION ---
  Future<void> _attachPermitPhoto(BuildContext context) async {
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;

    if (userId == null) {
      _showActionSnackbar(
        context,
        "Error: User not logged in.",
        isError: true,
      );
      return;
    }

    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true, // Required for web to get bytes
      );
    } catch (e) {
      if (!context.mounted) return;
      _showActionSnackbar(context, "File Picker Error: $e", isError: true);
      return;
    }

    if (!context.mounted) return;
    if (result == null || result.files.isEmpty) {
      _showActionSnackbar(context, "No file selected.");
      return;
    }

    final pickedFile = result.files.single;
    final Uint8List? fileBytes = pickedFile.bytes;

    if (fileBytes == null || fileBytes.isEmpty) {
      _showActionSnackbar(context, "Could not read file data.", isError: true);
      return;
    }

    final fileName = pickedFile.name;
    final uploadPath = '$userId/permits/$fileName';

    _showActionSnackbar(context, "Uploading $fileName...");

    try {
      await supabase.storage.from('Permits').uploadBinary(
        uploadPath,
        fileBytes,
        fileOptions: const FileOptions(cacheControl: '3600', upsert: true),
      );

      final permitPublicUrl = supabase.storage.from('Permits').getPublicUrl(uploadPath);

      if (!context.mounted) return;
      setState(() {
        _permitCount++;
        _permitUrls.add(permitPublicUrl);
      });
      _showActionSnackbar(
        context,
        "Permit photo uploaded successfully! Count: $_permitCount",
      );
    } on StorageException catch (e) {
      if (!context.mounted) return;
      _showActionSnackbar(context, "Upload Error: ${e.message}", isError: true);
    } catch (e) {
      if (!context.mounted) return;
      _showActionSnackbar(context, "Upload failed: $e", isError: true);
    }
  }

  // --- GOVERNMENT ID UPLOAD FUNCTION ---
  Future<void> _uploadIdPhoto(BuildContext context) async {
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;

    if (userId == null) {
      _showActionSnackbar(context, "Error: User not logged in.", isError: true);
      return;
    }

    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true,
      );
    } catch (e) {
      if (!context.mounted) return;
      _showActionSnackbar(context, "File Picker Error: $e", isError: true);
      return;
    }

    if (!context.mounted) return;
    if (result == null || result.files.isEmpty) {
      _showActionSnackbar(context, "No file selected.");
      return;
    }

    final pickedFile = result.files.single;
    final Uint8List? fileBytes = pickedFile.bytes;

    if (fileBytes == null || fileBytes.isEmpty) {
      _showActionSnackbar(context, "Could not read file data.", isError: true);
      return;
    }

    final ext = pickedFile.extension ?? 'jpg';
    final uploadPath = '$userId/id/government_id.$ext';

    _showActionSnackbar(context, "Uploading ID...");

    try {
      await supabase.storage.from('Permits').uploadBinary(
        uploadPath,
        fileBytes,
        fileOptions: const FileOptions(cacheControl: '3600', upsert: true),
      );

      final idPublicUrl = supabase.storage.from('Permits').getPublicUrl(uploadPath);

      if (!context.mounted) return;
      setState(() {
        _idUrl = idPublicUrl;
      });
      _showActionSnackbar(context, "Government ID uploaded successfully!");
    } on StorageException catch (e) {
      if (!context.mounted) return;
      _showActionSnackbar(context, "Upload Error: ${e.message}", isError: true);
    } catch (e) {
      if (!context.mounted) return;
      _showActionSnackbar(context, "Upload failed: $e", isError: true);
    }
  }

  // --- FINAL SUBMISSION LOGIC ---
  Future<void> _submitDataToSupabase(BuildContext context) async {
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

    if (_completedSteps < kTotalSteps) {
      _showActionSnackbar(
        context,
        "Please complete all $kTotalSteps steps before proceeding.",
        isError: true,
      );
      return;
    }

    setState(() => _isSubmitting = true);
    _showActionSnackbar(context, "Saving business data...", isError: false);

    try {
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

      final businessData = {
        'user_id': userId,
        'full_name': fullName,
        'store_name': _storeNameController.text,
        'category': _selectedBusinessCategory,
        'store_address': _storeAddressController.text.trim().isEmpty ? null : _storeAddressController.text.trim(),
        'stall_lat': _pin?.latitude,
        'stall_lng': _pin?.longitude,
        'market_section': _marketSectionController.text.trim().isEmpty ? null : _marketSectionController.text.trim(),
        'has_bank_account': _hasBankAccount,
        'permit_count': _permitCount,
        'permit_urls': _permitUrls,
        'logo_url': _logoUrl,
        // Persist the uploaded banner to both columns: banner_url drives the
        // home carousel, cover_url drives the public store profile header.
        'banner_url': _bannerUrl,
        if (_bannerUrl != null) 'cover_url': _bannerUrl,
        'id_url': _idUrl,
        'opening_time': '${_openingTime.hour.toString().padLeft(2, '0')}:${_openingTime.minute.toString().padLeft(2, '0')}',
        'closing_time': '${_closingTime.hour.toString().padLeft(2, '0')}:${_closingTime.minute.toString().padLeft(2, '0')}',
        'is_open': false,
        'is_info_complete': true,
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

      // Navigate to the final confirmation step, passing the values the
      // seller already entered so the screen can show them as a read-only
      // summary instead of asking for them a second time.
      Navigator.push(
        context,
        fadeSlideRoute(
          (context) => BusinessProfileScreen(
            initialStoreName: _storeNameController.text.trim(),
            initialStoreAddress: _storeAddressController.text.trim(),
          ),
        ),
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
      backgroundColor: const Color(0xFFF4F7FB),
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeroHeader(progress),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [

            // 1. Logo Upload Area
            AppearOnMount(
              delay: staggerDelay(0, step: 70),
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  width: 116,
                  height: 116,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: _logoUrl != null
                        ? null
                        : LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              kPrimaryBlue.withValues(alpha: 0.05),
                              kPrimaryBlue.withValues(alpha: 0.02),
                            ],
                          ),
                    border: Border.all(
                      color: _logoUrl != null
                          ? kPrimaryBlue
                          : kPrimaryBlue.withValues(alpha: 0.3),
                      width: _logoUrl != null ? 2.5 : 1.6,
                    ),
                    boxShadow: _logoUrl != null
                        ? [
                            BoxShadow(
                              color: kPrimaryBlue.withValues(alpha: 0.18),
                              blurRadius: 16,
                              offset: const Offset(0, 8),
                            ),
                          ]
                        : null,
                  ),
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                    child: InkWell(
                      onTap: () => _uploadLogo(context),
                      borderRadius: BorderRadius.circular(20),
                      child: _logoUrl != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(18),
                              child: Image.network(
                                _logoUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) =>
                                    _buildDefaultLogo(),
                              ),
                            )
                          : _buildDefaultLogo(),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 26),

            // Banner Upload Area
            AppearOnMount(
              delay: staggerDelay(1, step: 70),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Store Banner",
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    "This banner will appear on the marketplace homepage.",
                    style: TextStyle(color: kTextGrey, fontSize: 12.5),
                  ),
                  const SizedBox(height: 10),
                  Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      onTap: () => _uploadBanner(context),
                      borderRadius: BorderRadius.circular(16),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        width: double.infinity,
                        height: 150,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: _bannerUrl != null
                              ? null
                              : LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    kPrimaryBlue.withValues(alpha: 0.05),
                                    kPrimaryBlue.withValues(alpha: 0.02),
                                  ],
                                ),
                          border: Border.all(
                            color: _bannerUrl != null
                                ? kPrimaryBlue
                                : kPrimaryBlue.withValues(alpha: 0.3),
                            width: _bannerUrl != null ? 2.5 : 1.6,
                          ),
                          boxShadow: _bannerUrl != null
                              ? [
                                  BoxShadow(
                                    color: kPrimaryBlue.withValues(alpha: 0.18),
                                    blurRadius: 16,
                                    offset: const Offset(0, 8),
                                  ),
                                ]
                              : null,
                        ),
                        child: _bannerUrl != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: Image.network(
                                  _bannerUrl!,
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  errorBuilder:
                                      (context, error, stackTrace) =>
                                          _buildDefaultBanner(),
                                ),
                              )
                            : _buildDefaultBanner(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 26),

            // Shop Hours Section
            AppearOnMount(
              delay: staggerDelay(2, step: 70),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
            const Text(
              "Shop Hours",
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
            const SizedBox(height: 4),
            const Text(
              "Set your daily opening and closing hours. You can toggle open/closed manually from your dashboard.",
              style: TextStyle(color: kTextGrey, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: _openingTime,
                        helpText: 'Select opening time',
                      );
                      if (picked != null) setState(() => _openingTime = picked);
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.wb_sunny_outlined, color: Color(0xFF059669), size: 20),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Opens at', style: TextStyle(color: kTextGrey, fontSize: 11)),
                              const SizedBox(height: 2),
                              Text(
                                _openingTime.format(context),
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: _closingTime,
                        helpText: 'Select closing time',
                      );
                      if (picked != null) setState(() => _closingTime = picked);
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.nights_stay_outlined, color: Color(0xFFDC2626), size: 20),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Closes at', style: TextStyle(color: kTextGrey, fontSize: 11)),
                              const SizedBox(height: 2),
                              Text(
                                _closingTime.format(context),
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
                ],
              ),
            ),
            const SizedBox(height: 26),

            // 2. Business Category Dropdown
            AppearOnMount(
              delay: staggerDelay(3, step: 70),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
            const Text(
              "Business Category",
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
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
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 3. Store Name Text Field
            AppearOnMount(
              delay: staggerDelay(4, step: 60),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
            _buildInputField(
              label: "Store Name",
              controller: _storeNameController,
              hint: "Enter your store name",
              icon: Icons.storefront_outlined,
            ),

            // Store address (full)
            _buildInputField(
              label: "Store Address",
              controller: _storeAddressController,
              hint: "Street, barangay, city",
              icon: Icons.location_on_outlined,
            ),

            // Market section
            _buildInputField(
              label: "Market Section",
              controller: _marketSectionController,
              hint: "e.g. Wet Market, Dry Goods",
              icon: Icons.grid_view_rounded,
            ),
                ],
              ),
            ),

            // Pin location on map
            AppearOnMount(
              delay: staggerDelay(5, step: 60),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Pin Store Location",
                    style:
                        TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    "Drop a pin on the map so buyers can find you.",
                    style: TextStyle(color: kTextGrey, fontSize: 12.5),
                  ),
                  const SizedBox(height: 8),
                  _StorePinPickerField(
                    pin: _pin,
                    onPicked: (p) => setState(() => _pin = p),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            AppearOnMount(
              delay: staggerDelay(7, step: 60),
              child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE3EAF4)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
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
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: kPrimaryBlue.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '$_completedSteps/$kTotalSteps Complete',
                          style: const TextStyle(
                            color: kPrimaryBlue,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
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
                  // Step 1: Logo Upload
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

                  // Step 5: Government ID
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _ListItem(
                          title: 'Government ID',
                          subtitle: _idUrl != null
                              ? 'ID uploaded successfully.'
                              : 'Upload a valid government-issued ID (required)',
                          onTap: () => _uploadIdPhoto(context),
                          isCompleted: _idUrl != null,
                          showRightArrow: false,
                        ),
                        Padding(
                          padding: const EdgeInsets.only(
                            left: 32.0,
                            top: 4,
                            bottom: 8,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  _idUrl != null
                                      ? 'ID photo attached'
                                      : 'No ID uploaded yet',
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
                                  onPressed: () => _uploadIdPhoto(context),
                                  icon: const Icon(Icons.badge_outlined, size: 18),
                                  label: Text(
                                    _idUrl != null ? 'Re-upload ID' : 'Upload ID',
                                    style: const TextStyle(
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

                ],
              ),
              ),
            ),
                    const SizedBox(height: 32),
                    AppearOnMount(
                      delay: staggerDelay(8, step: 50),
                      child: _BusinessSubmitButton(
                        isReady: _completedSteps == kTotalSteps,
                        isLoading: _isSubmitting,
                        completed: _completedSteps,
                        total: kTotalSteps,
                        onPressed: () => _submitDataToSupabase(context),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Gradient hero header that replaces the old plain AppBar + setup-progress
  /// banner. It carries the back arrow, page title, live "x/y complete" badge,
  /// and an animated progress track — all in one polished block.
  Widget _buildHeroHeader(double progress) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 26),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [kPrimaryBlue, kPrimaryBlueDark],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
        boxShadow: [
          BoxShadow(
            color: Color(0x2624439B),
            blurRadius: 22,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Material(
                color: Colors.white.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => Navigator.pop(context),
                  child: const Padding(
                    padding: EdgeInsets.all(10),
                    child: Icon(
                      Icons.arrow_back_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.task_alt_rounded,
                      color: Colors.white,
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '$_completedSteps / $kTotalSteps',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Text(
            'Business setup',
            style: TextStyle(
              color: Color(0xFFC9D4F2),
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Fill your store details',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            progress >= 1
                ? 'Looks great — you can submit when you’re ready.'
                : 'Knock out each requirement below to unlock submission.',
            style: const TextStyle(
              color: Color(0xFFD8E1F8),
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: progress),
              duration: const Duration(milliseconds: 420),
              curve: Curves.easeOutCubic,
              builder: (_, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 8,
                backgroundColor: Colors.white.withValues(alpha: 0.18),
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
          ),
        ],
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

  Widget _buildDefaultBanner() {
    return const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.panorama_outlined, size: 40, color: kTextGrey),
        SizedBox(height: 4),
        Text("Tap to upload store banner",
            style: TextStyle(color: kTextGrey, fontSize: 13)),
        SizedBox(height: 2),
        Text("Recommended: 1200 × 400 px",
            style: TextStyle(color: kTextGrey, fontSize: 11)),
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

// Map pin picker field used by the seller application form.
class _StorePinPickerField extends StatefulWidget {
  const _StorePinPickerField({required this.pin, required this.onPicked});

  final LatLng? pin;
  final ValueChanged<LatLng> onPicked;

  @override
  State<_StorePinPickerField> createState() => _StorePinPickerFieldState();
}

class _StorePinPickerFieldState extends State<_StorePinPickerField> {
  final _mapController = MapController();
  bool _isLocating = false;

  LatLng get _effectivePin => widget.pin ?? kMarketPlaza;

  Future<void> _useCurrentLocation() async {
    setState(() => _isLocating = true);
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        _snack('Turn on device location to use GPS.');
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        _snack('Location permission denied.');
        return;
      }
      // Snap to the cached last-known fix first so the user sees a result
      // instantly, then upgrade with a high-accuracy reading.
      try {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null && mounted) {
          final approx = LatLng(last.latitude, last.longitude);
          widget.onPicked(approx);
          _mapController.move(approx, 18);
        }
      } catch (_) {}

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
      final next = LatLng(pos.latitude, pos.longitude);
      if (!mounted) return;
      widget.onPicked(next);
      _mapController.move(next, 18);
    } catch (e) {
      _snack('Could not get location: $e');
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final hasPin = widget.pin != null;
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      tween: Tween(begin: 0.97, end: 1),
      builder: (_, scale, child) =>
          Transform.scale(scale: scale, child: child),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: 220,
          child: Stack(
            children: [
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: _effectivePin,
                  initialZoom: 17,
                  minZoom: 5,
                  maxZoom: 19,
                  onTap: (_, latLng) => widget.onPicked(latLng),
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.example.caps_finals',
                    maxNativeZoom: 19,
                  ),
                  if (hasPin)
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: widget.pin!,
                          width: 48,
                          height: 48,
                          alignment: Alignment.topCenter,
                          child: const Icon(
                            Icons.location_on,
                            color: kPrimaryBlue,
                            size: 44,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              Positioned(
                left: 10,
                top: 10,
                right: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x22000000),
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.touch_app_rounded,
                          color: kPrimaryBlue, size: 16),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          hasPin
                              ? '${widget.pin!.latitude.toStringAsFixed(5)}, ${widget.pin!.longitude.toStringAsFixed(5)}'
                              : 'Tap the map to drop a pin',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                right: 12,
                bottom: 12,
                child: FloatingActionButton.small(
                  heroTag: 'apply-gps',
                  onPressed: _isLocating ? null : _useCurrentLocation,
                  backgroundColor: kPrimaryBlue,
                  foregroundColor: Colors.white,
                  child: _isLocating
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.my_location),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Modernised gradient submit button with loading + locked states. Matches
/// the [`_FinalizeButton`] used on the next screen so the flow feels coherent.
class _BusinessSubmitButton extends StatefulWidget {
  const _BusinessSubmitButton({
    required this.isReady,
    required this.isLoading,
    required this.completed,
    required this.total,
    required this.onPressed,
  });

  final bool isReady;
  final bool isLoading;
  final int completed;
  final int total;
  final VoidCallback onPressed;

  @override
  State<_BusinessSubmitButton> createState() => _BusinessSubmitButtonState();
}

class _BusinessSubmitButtonState extends State<_BusinessSubmitButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.isReady && !widget.isLoading;
    final lockedLabel =
        'Complete all steps (${widget.completed}/${widget.total})';

    return AnimatedScale(
      scale: _pressed && enabled ? 0.985 : 1,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: enabled ? widget.onPressed : null,
          onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
          onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
          onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            height: 58,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: enabled
                    ? const [kPrimaryBlue, kPrimaryBlueDark]
                    : const [Color(0xFFB5BCCB), Color(0xFF8892A8)],
              ),
              boxShadow: enabled
                  ? [
                      BoxShadow(
                        color: kPrimaryBlue.withValues(alpha: 0.32),
                        blurRadius: 22,
                        offset: const Offset(0, 12),
                      ),
                    ]
                  : const [],
            ),
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
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
                            'Saving…',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      )
                    : Row(
                        key: ValueKey(enabled ? 'ready' : 'locked'),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            enabled
                                ? Icons.arrow_forward_rounded
                                : Icons.lock_rounded,
                            color: Colors.white,
                            size: enabled ? 22 : 18,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            enabled ? 'Next: Complete Profile' : lockedLabel,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15.5,
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
