import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'edit_stall_location.dart';

const Color _kPrimary = Color(0xFF2A4BA0);
const Color _kSurface = Color(0xFFF5F6FB);

class EditStoreInfoPage extends StatefulWidget {
  const EditStoreInfoPage({super.key});

  @override
  State<EditStoreInfoPage> createState() => _EditStoreInfoPageState();
}

class _EditStoreInfoPageState extends State<EditStoreInfoPage> {
  final _supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  final _storeNameCtrl = TextEditingController();
  final _storeAddressCtrl = TextEditingController();
  final _contactEmailCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();

  TimeOfDay _openingTime = const TimeOfDay(hour: 5, minute: 0);
  TimeOfDay _closingTime = const TimeOfDay(hour: 19, minute: 0);
  bool _isOpen = false;
  bool _isLoading = true;
  bool _isSaving = false;

  // Logo
  String? _currentLogoUrl;
  XFile? _pickedLogo;
  Uint8List? _pickedLogoBytes;

  // Cover photo
  String? _currentCoverUrl;
  XFile? _pickedCover;
  Uint8List? _pickedCoverBytes;

  @override
  void initState() {
    super.initState();
    _loadStoreInfo();
  }

  @override
  void dispose() {
    _storeNameCtrl.dispose();
    _storeAddressCtrl.dispose();
    _contactEmailCtrl.dispose();
    _descriptionCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickLogo() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (file == null || !mounted) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _pickedLogo = file;
      _pickedLogoBytes = bytes;
    });
  }

  Future<void> _pickCover() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      maxHeight: 600,
      imageQuality: 85,
    );
    if (file == null || !mounted) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _pickedCover = file;
      _pickedCoverBytes = bytes;
    });
  }

  Future<String?> _uploadCover() async {
    if (_pickedCover == null || _pickedCoverBytes == null) return null;
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return null;
    try {
      final ext = _pickedCover!.name.split('.').last.toLowerCase();
      final fileName =
          'cover_${userId}_${DateTime.now().millisecondsSinceEpoch}.$ext';
      await _supabase.storage.from('logos').uploadBinary(
            fileName,
            _pickedCoverBytes!,
            fileOptions: FileOptions(
              contentType: 'image/$ext',
              upsert: true,
            ),
          );
      return _supabase.storage.from('logos').getPublicUrl(fileName);
    } catch (e) {
      debugPrint('Cover upload error: $e');
      return null;
    }
  }

  Future<String?> _uploadLogo() async {
    if (_pickedLogo == null || _pickedLogoBytes == null) return null;
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return null;
    try {
      final ext = _pickedLogo!.name.split('.').last.toLowerCase();
      final fileName = 'logo_${userId}_${DateTime.now().millisecondsSinceEpoch}.$ext';
      await _supabase.storage.from('logos').uploadBinary(
        fileName,
        _pickedLogoBytes!,
        fileOptions: FileOptions(
          contentType: 'image/$ext',
          upsert: true,
        ),
      );
      return _supabase.storage.from('logos').getPublicUrl(fileName);
    } catch (e) {
      debugPrint('Logo upload error: $e');
      return null;
    }
  }

  Future<void> _loadStoreInfo() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      setState(() => _isLoading = false);
      return;
    }
    try {
      final data = await _supabase
          .from('seller_profiles')
          .select(
              'store_name, store_address, official_contact_email, opening_time, closing_time, is_open, logo_url, cover_url, description')
          .eq('user_id', userId)
          .maybeSingle();

      if (data != null && mounted) {
        _storeNameCtrl.text = data['store_name']?.toString() ?? '';
        _storeAddressCtrl.text = data['store_address']?.toString() ?? '';
        _contactEmailCtrl.text =
            data['official_contact_email']?.toString() ?? '';
        _descriptionCtrl.text = data['description']?.toString() ?? '';
        _isOpen = data['is_open'] == true;
        _openingTime = _parseTime(data['opening_time']?.toString() ?? '05:00');
        _closingTime = _parseTime(data['closing_time']?.toString() ?? '19:00');
        _currentLogoUrl = data['logo_url']?.toString();
        _currentCoverUrl = data['cover_url']?.toString();
      }
    } catch (e) {
      debugPrint('Load store info error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  TimeOfDay _parseTime(String t) {
    try {
      final parts = t.split(':');
      return TimeOfDay(
          hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    } catch (_) {
      return const TimeOfDay(hour: 5, minute: 0);
    }
  }

  String _formatTimeOfDay(TimeOfDay t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _displayTime(TimeOfDay t) {
    final period = t.hour >= 12 ? 'PM' : 'AM';
    int h = t.hour > 12 ? t.hour - 12 : t.hour;
    if (h == 0) h = 12;
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m $period';
  }

  Future<void> _pickTime(bool isOpening) async {
    final initial = isOpening ? _openingTime : _closingTime;
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked != null && mounted) {
      setState(() {
        if (isOpening) {
          _openingTime = picked;
        } else {
          _closingTime = picked;
        }
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    setState(() => _isSaving = true);
    try {
      String? newLogoUrl;
      if (_pickedLogo != null) {
        newLogoUrl = await _uploadLogo();
        if (newLogoUrl == null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Logo upload failed. Other changes will still be saved.')),
          );
        }
      }

      String? newCoverUrl;
      if (_pickedCover != null) {
        newCoverUrl = await _uploadCover();
        if (newCoverUrl == null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Cover upload failed. Other changes will still be saved.')),
          );
        }
      }

      final updates = <String, dynamic>{
        'store_name': _storeNameCtrl.text.trim(),
        'store_information_final': _storeNameCtrl.text.trim(),
        'store_address': _storeAddressCtrl.text.trim(),
        'official_contact_email': _contactEmailCtrl.text.trim(),
        'description': _descriptionCtrl.text.trim(),
        'opening_time': _formatTimeOfDay(_openingTime),
        'closing_time': _formatTimeOfDay(_closingTime),
        'is_open': _isOpen,
        if (newLogoUrl != null) 'logo_url': newLogoUrl,
        if (newCoverUrl != null) 'cover_url': newCoverUrl,
      };
      await _supabase.from('seller_profiles').update(updates).eq('user_id', userId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Store information updated!'),
            backgroundColor: _kPrimary,
          ),
        );
        Navigator.pop(context, true);
      }
    } on PostgrestException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.message}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kSurface,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _kPrimary,
        elevation: 0,
        title: const Text('Edit Store Info',
            style: TextStyle(fontWeight: FontWeight.w700, color: Colors.black87)),
        actions: [
          if (!_isLoading)
            TextButton(
              onPressed: _isSaving ? null : _save,
              child: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save',
                      style: TextStyle(
                          color: _kPrimary, fontWeight: FontWeight.w700)),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  // Cover photo picker
                  _buildCoverPicker(),
                  const SizedBox(height: 16),

                  // Logo picker
                  _buildLogoPicker(),
                  const SizedBox(height: 20),

                  // Open/Closed toggle at top
                  _card(
                    child: Row(
                      children: [
                        const Icon(Icons.storefront_rounded,
                            color: _kPrimary, size: 22),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Shop Status',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15)),
                              Text(
                                _isOpen ? 'Currently Open' : 'Currently Closed',
                                style: TextStyle(
                                    color: _isOpen
                                        ? Colors.green.shade700
                                        : Colors.red.shade600,
                                    fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: _isOpen,
                          activeColor: _kPrimary,
                          onChanged: (v) => setState(() => _isOpen = v),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Store name
                  _label('Store Name'),
                  _textField(
                    controller: _storeNameCtrl,
                    hint: 'e.g. Fresh Catch Store',
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 14),

                  // Address
                  _label('Store Address'),
                  _textField(
                    controller: _storeAddressCtrl,
                    hint: 'e.g. 123 Market Street, Downtown',
                    maxLines: 2,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 14),

                  // Stall location on map
                  _label('Stall Location on Map'),
                  _card(
                    child: InkWell(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const EditStallLocationPage(),
                        ),
                      ),
                      borderRadius: BorderRadius.circular(10),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: _kPrimary.withAlpha(26),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.map_outlined,
                              color: _kPrimary,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Pin Your Stall',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Tap to place a pin or use GPS so buyers can find you.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF6B7280),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right_rounded,
                            color: Color(0xFFADB5BD),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Contact email
                  _label('Contact Email'),
                  _textField(
                    controller: _contactEmailCtrl,
                    hint: 'e.g. store@email.com',
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Required';
                      if (!RegExp(r'^[\w.-]+@[\w.-]+\.\w{2,}$')
                          .hasMatch(v.trim())) {
                        return 'Enter a valid email';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),

                  // Store description
                  _label('Store Description'),
                  _textField(
                    controller: _descriptionCtrl,
                    hint:
                        'Tell buyers about your store — what you sell, your specialties, etc.',
                    maxLines: 4,
                  ),
                  const SizedBox(height: 20),

                  // Operating hours
                  _label('Operating Hours'),
                  _card(
                    child: Column(
                      children: [
                        _timeTile(
                          label: 'Opening Time',
                          time: _displayTime(_openingTime),
                          icon: Icons.wb_sunny_rounded,
                          color: Colors.orange.shade600,
                          onTap: () => _pickTime(true),
                        ),
                        const Divider(height: 1),
                        _timeTile(
                          label: 'Closing Time',
                          time: _displayTime(_closingTime),
                          icon: Icons.nights_stay_rounded,
                          color: Colors.indigo.shade400,
                          onTap: () => _pickTime(false),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Save button at bottom
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kPrimary,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                          : const Text('Save Changes',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildCoverPicker() {
    final hasNew = _pickedCoverBytes != null;
    final hasCurrent = _currentCoverUrl != null && _currentCoverUrl!.isNotEmpty;
    final hasAny = hasNew || hasCurrent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Cover Photo'),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: _pickCover,
          child: Container(
            height: 160,
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFFEEF2FF),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: _kPrimary.withAlpha(60), width: 1.5),
              image: hasNew
                  ? DecorationImage(
                      image: MemoryImage(_pickedCoverBytes!),
                      fit: BoxFit.cover,
                    )
                  : hasCurrent
                      ? DecorationImage(
                          image: NetworkImage(_currentCoverUrl!),
                          fit: BoxFit.cover,
                        )
                      : null,
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (!hasAny)
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.add_photo_alternate_rounded,
                          size: 36, color: _kPrimary),
                      SizedBox(height: 8),
                      Text('Tap to upload cover photo',
                          style: TextStyle(
                              color: _kPrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: 13)),
                    ],
                  )
                else
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(100),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.edit_rounded,
                              color: Colors.white, size: 28),
                          SizedBox(height: 6),
                          Text('Change Cover',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
                if (hasNew)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green.shade600,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text('New',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLogoPicker() {
    final hasNewLogo = _pickedLogoBytes != null;
    final hasCurrentLogo =
        _currentLogoUrl != null && _currentLogoUrl!.isNotEmpty;
    final hasAnyLogo = hasNewLogo || hasCurrentLogo;

    return Column(
      children: [
        _label('Store Logo'),
        const SizedBox(height: 10),
        _card(
          child: Row(
            children: [
              // Avatar
              GestureDetector(
                onTap: _pickLogo,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFFEEF2FF),
                        border:
                            Border.all(color: _kPrimary.withAlpha(60), width: 2),
                        image: hasNewLogo
                            ? DecorationImage(
                                image: MemoryImage(_pickedLogoBytes!),
                                fit: BoxFit.cover,
                              )
                            : hasCurrentLogo
                                ? DecorationImage(
                                    image: NetworkImage(_currentLogoUrl!),
                                    fit: BoxFit.cover,
                                  )
                                : null,
                      ),
                      child: !hasAnyLogo
                          ? const Icon(Icons.storefront_rounded,
                              size: 36, color: _kPrimary)
                          : null,
                    ),
                    // Dark overlay with camera icon when image exists
                    if (hasAnyLogo)
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black.withAlpha(100),
                        ),
                        child: const Icon(Icons.camera_alt_rounded,
                            color: Colors.white, size: 26),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              // Text + button
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasNewLogo
                          ? 'New logo ready to save'
                          : hasCurrentLogo
                              ? 'Logo uploaded'
                              : 'No logo yet',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: hasNewLogo
                            ? Colors.green.shade700
                            : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hasNewLogo
                          ? _pickedLogo!.name
                          : 'Tap to upload a store logo',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF9CA3AF)),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 36,
                      child: ElevatedButton.icon(
                        onPressed: _pickLogo,
                        icon: const Icon(Icons.upload_rounded, size: 16),
                        label: Text(
                          hasAnyLogo ? 'Change Logo' : 'Upload Logo',
                          style: const TextStyle(fontSize: 13),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kPrimary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
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
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: Color(0xFF374151))),
      );

  Widget _textField({
    required TextEditingController controller,
    String? hint,
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) =>
      TextFormField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        validator: validator,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Color(0xFFADB5BD)),
          filled: true,
          fillColor: Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _kPrimary, width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.red.shade400),
          ),
        ),
      );

  Widget _card({required Widget child}) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withAlpha(13),
                blurRadius: 8,
                offset: const Offset(0, 2)),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: child,
      );

  Widget _timeTile({
    required String label,
    required String time,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withAlpha(26),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                  child: Text(label,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w500))),
              Text(time,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _kPrimary)),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded,
                  color: Color(0xFFADB5BD), size: 20),
            ],
          ),
        ),
      );
}
