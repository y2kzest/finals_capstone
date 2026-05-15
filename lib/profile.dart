import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'pages/login_page.dart';
import 'pages/orders_page.dart';
import 'pages/addresses_page.dart';
import 'pages/buyer_messages_page.dart';
import 'pages/wishlist_page.dart';
import 'pages/market_map_page.dart';
import 'seller_pages/dashboard_screen.dart';
import 'seller_pages/activate.dart';
import 'utils/page_transitions.dart';

const Color kDeepBlue = Color(0xFF153075);

class Profile extends StatefulWidget {
  const Profile({super.key});

  @override
  State<Profile> createState() => _ProfileState();
}

class _ProfileState extends State<Profile> {
  // Initialize Supabase Client
  final SupabaseClient supabase = Supabase.instance.client;

  Map<String, dynamic>? _profileData;
  String _userEmail = '';
  bool _isLoading = true;
  bool _isUploadingAvatar = false;
  String _sellerStatus = ''; // '', 'pending', 'approved', 'rejected'
  bool _isSeller = false;
  int _orderCount = 0;
  int _activeOrderCount = 0; // orders with status pending/accepted/ready
  int _wishlistCount = 0;

  @override
  void initState() {
    super.initState();
    _fetchUserProfile();
  }

  // --- Supabase Data Fetching & Creation ---

  Future<void> _fetchUserProfile() async {
    final user = supabase.auth.currentUser;

    if (user == null) {
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const LoginPage()),
          (route) => false,
        );
        setState(() {
          _isLoading = false;
        });
      }
      return;
    }

    try {
      final accountProfile = await supabase
          .from('profiles')
          .select('status')
          .eq('id', user.id)
          .maybeSingle();
      if (accountProfile?['status'] == 'suspended') {
        await supabase.auth.signOut();
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const LoginPage()),
          (route) => false,
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Your account has been suspended. Please contact the administrator.',
            ),
            backgroundColor: Color(0xFFDC2626),
          ),
        );
        return;
      }
    } catch (_) {
      // Non-critical — if check fails, fall through and load profile normally
    }

    final userEmail = user.email ?? 'N/A';

    if (mounted) {
      setState(() {
        _userEmail = userEmail;
      });
    }

    // Check if user has a seller application (seller_profiles row)
    try {
      final sellerProfile = await supabase
          .from('seller_profiles')
          .select('approval_status')
          .eq('user_id', user.id)
          .maybeSingle();
      if (sellerProfile != null) {
        _isSeller = true;
        _sellerStatus =
            sellerProfile['approval_status']?.toString().toLowerCase() ??
            'pending';
      }
    } catch (_) {
      // Non-critical — leave defaults
    }

    // Fetch order count
    try {
      final orderRes = await supabase
          .from('orders')
          .select('id')
          .eq('buyer_id', user.id);
      if (mounted) setState(() => _orderCount = (orderRes as List).length);
    } catch (_) {}

    // Fetch wishlist count
    try {
      final wishlistRes = await supabase
          .from('wishlist')
          .select('id')
          .eq('user_id', user.id);
      if (mounted) {
        setState(() => _wishlistCount = (wishlistRes as List).length);
      }
    } catch (_) {}
    try {
      final activeRes = await supabase
          .from('orders')
          .select('id')
          .eq('buyer_id', user.id)
          .inFilter('status', ['pending', 'accepted', 'ready']);
      if (mounted) {
        setState(() => _activeOrderCount = (activeRes as List).length);
      }
    } catch (_) {}

    try {
      final response = await supabase
          .from('profile')
          .select()
          .eq('user_id', user.id)
          .maybeSingle(); // returns null instead of throwing

      if (response != null) {
        if (mounted) {
          setState(() {
            _profileData = response;
            _isLoading = false;
          });
        }
      } else {
        // No profile found — create one
        final defaultName = userEmail.split('@')[0];
        final newProfile = {
          'user_id': user.id,
          'email': userEmail,
          'name': defaultName,
        };

        try {
          await supabase.from('profile').insert(newProfile);
          if (mounted) {
            setState(() {
              _profileData = newProfile;
              _isLoading = false;
            });
            _showSnackBar("Profile created!");
          }
        } on PostgrestException catch (e) {
          if (mounted) {
            _showSnackBar("Error creating profile: ${e.message}");
            setState(() => _isLoading = false);
          }
        }
      }
    } on PostgrestException catch (e) {
      debugPrint(
        'Profile fetch failed: ${e.message}. Attempting to create profile.',
      );

      final defaultName = userEmail.split('@')[0];

      final newProfile = {
        'user_id': user.id,
        'email': userEmail,
        'name': defaultName,
      };

      try {
        await supabase.from('profile').insert(newProfile).select().single();

        if (mounted) {
          setState(() {
            _profileData = newProfile;
            _isLoading = false;
          });
          _showSnackBar("New profile created successfully!");
        }
      } on PostgrestException catch (e) {
        if (mounted) {
          String message = "Error creating profile: ${e.message}";

          if (e.message.contains('violates row-level security policy')) {
            debugPrint(
              '⚠️ REMINDER: Check INSERT RLS policy on the profile table in Supabase!',
            );
            message =
                "Profile creation failed due to security policy. (Check Supabase RLS)";
          }

          _showSnackBar(message);
          setState(() {
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar("An unexpected error occurred.");
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // --- Avatar Upload ---
  Future<void> _pickAndUploadAvatar() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    final picker = ImagePicker();
    XFile? pickedFile;
    try {
      pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
    } catch (e) {
      _showSnackBar('Could not open image picker: $e');
      return;
    }
    if (pickedFile == null) return;

    Uint8List bytes;
    try {
      bytes = await pickedFile.readAsBytes();
    } catch (e) {
      _showSnackBar('Could not read image: $e');
      return;
    }

    final ext = pickedFile.name.split('.').last.toLowerCase();
    final uploadPath = '$userId/avatar.$ext';

    if (mounted) setState(() => _isUploadingAvatar = true);
    try {
      await supabase.storage
          .from('avatars')
          .uploadBinary(
            uploadPath,
            bytes,
            fileOptions: const FileOptions(cacheControl: '3600', upsert: true),
          );

      // Append cache-bust timestamp so the widget re-renders with the new image
      final publicUrl =
          '${supabase.storage.from('avatars').getPublicUrl(uploadPath)}?t=${DateTime.now().millisecondsSinceEpoch}';

      await supabase
          .from('profile')
          .update({'avatar_url': publicUrl})
          .eq('user_id', userId);

      if (mounted) {
        setState(() {
          _profileData = {...?_profileData, 'avatar_url': publicUrl};
          _isUploadingAvatar = false;
        });
        _showSnackBar('Profile picture updated!');
      }
    } on StorageException catch (e) {
      if (mounted) {
        setState(() => _isUploadingAvatar = false);
        _showSnackBar('Upload failed: ${e.message}');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUploadingAvatar = false);
        _showSnackBar('Upload failed: $e');
      }
    }
  }

  void _showGenderPicker(String key) {
    final selectedGender = _profileData?['gender']?.toString();

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Select Gender',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              for (final option in ['Male', 'Female', 'Prefer not to say'])
                ListTile(
                  title: Text(option),
                  leading: Icon(
                    selectedGender == option
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: selectedGender == option ? kDeepBlue : Colors.grey,
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _updateProfileField(key, option);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  // --- Supabase Data Update Function ---
  Future<void> _updateProfileField(String key, dynamic newValue) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      _showSnackBar("Authentication error. Please log in again.");
      return;
    }

    final currentValue = _profileData?[key];
    if (newValue.toString() == (currentValue?.toString() ?? '') &&
        newValue.toString().isNotEmpty) {
      _showSnackBar("$key is already set.");
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final dynamic dbValue = newValue is DateTime
        ? newValue.toIso8601String().split('T')[0]
        : newValue;

    try {
      await supabase.from('profile').upsert({
        'user_id': userId,
        'email': _userEmail,
        key: dbValue,
      }, onConflict: 'user_id');

      if (mounted) {
        setState(() {
          _profileData = _profileData ?? {};
          _profileData![key] = dbValue;
          _isLoading = false;
        });
        _showSnackBar("Profile updated!");
      }
    } on PostgrestException catch (e) {
      if (mounted) {
        _showSnackBar("Error updating profile: ${e.message}");
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar("An unexpected error occurred: $e");
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // --- Dialog for Editing Text Fields ---
  void _showEditDialog(String label, String key, String? currentValue) {
    final controller = TextEditingController(text: currentValue);

    if (key == 'email') {
      _showSnackBar('Email cannot be changed from the profile screen.');
      return;
    }

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Edit $label'),
          content: TextField(
            controller: controller,
            maxLines: key == 'bio' ? 3 : 1,
            decoration: InputDecoration(
              labelText: label,
              border: const OutlineInputBorder(),
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: Text('Save', style: TextStyle(color: kDeepBlue)),
              onPressed: () {
                Navigator.of(context).pop();
                _updateProfileField(key, controller.text.trim());
              },
            ),
          ],
        );
      },
    );
  }

  // --- Dialog for Editing Date (Birthday) ---
  void _showDateEditDialog(
    String label,
    String key,
    String? currentValue,
  ) async {
    DateTime initialDate = DateTime.now().subtract(
      const Duration(days: 365 * 20),
    );
    try {
      if (currentValue != null && currentValue.isNotEmpty) {
        initialDate = DateTime.parse(currentValue);
      }
    } catch (e) {
      // If parsing fails, use the default
    }

    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      helpText: 'Select your $label',
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: ColorScheme.light(
              primary: kDeepBlue,
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
            dialogTheme: DialogThemeData(backgroundColor: Colors.white),
          ),
          child: child!,
        );
      },
    );

    if (pickedDate != null) {
      _updateProfileField(key, pickedDate);
    }
  }

  // --- Supabase Logout Function ---
  Future<void> _signOut() async {
    try {
      await supabase.auth.signOut();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const LoginPage()),
          (route) => false,
        );
      }
    } catch (e) {
      _showSnackBar('Logout failed: $e');
    }
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  // --- UI Builder Methods ---

  IconData _fieldIcon(String key) {
    switch (key) {
      case 'name':
        return Icons.badge_outlined;
      case 'bio':
        return Icons.notes_rounded;
      case 'gender':
        return Icons.wc_rounded;
      case 'birthday':
        return Icons.cake_outlined;
      case 'phone':
        return Icons.phone_outlined;
      case 'email':
        return Icons.alternate_email_rounded;
      default:
        return Icons.info_outline_rounded;
    }
  }

  /// Opens a chat with the admin support account.
  Future<void> _contactAdmin() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please log in first.')));
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          const Center(child: CircularProgressIndicator(color: kDeepBlue)),
    );

    try {
      String? adminId;
      String adminName = 'Admin Support';
      String? adminAvatar;

      // Try looking up admin from user_roles table.
      try {
        final rolesRes = await supabase
            .from('user_roles')
            .select('user_id')
            .eq('role', 'admin')
            .limit(1);
        if ((rolesRes as List).isNotEmpty) {
          adminId = rolesRes.first['user_id']?.toString();
        }
      } catch (_) {}

      // Fetch admin's profile for display name & avatar.
      if (adminId != null) {
        try {
          final p = await supabase
              .from('profile')
              .select('name, avatar_url')
              .eq('user_id', adminId)
              .maybeSingle();
          if (p != null) {
            final n = p['name']?.toString().trim() ?? '';
            if (n.isNotEmpty) adminName = n;
            adminAvatar = p['avatar_url']?.toString();
          }
        } catch (_) {}
      } else {
        // Fallback: look up admin profile by known admin email.
        try {
          final p = await supabase
              .from('profile')
              .select('user_id, name, avatar_url')
              .eq('email', 'maicasulla13@gmail.com')
              .maybeSingle();
          if (p != null) {
            adminId = p['user_id']?.toString();
            final n = p['name']?.toString().trim() ?? '';
            if (n.isNotEmpty) adminName = n;
            adminAvatar = p['avatar_url']?.toString();
          }
        } catch (_) {}
      }

      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();

      if (adminId == null || adminId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Support is currently unavailable. Try again later.'),
          ),
        );
        return;
      }

      await openOrCreateConversation(
        context,
        sellerId: adminId,
        sellerName: adminName,
        sellerAvatarUrl: adminAvatar,
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open support chat: $e')),
      );
    }
  }

  Widget _buildQuickActionTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    int badge = 0,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Ink(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: const [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 12,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(icon, color: kDeepBlue, size: 24),
                if (badge > 0)
                  Positioned(
                    right: -8,
                    top: -6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDC2626),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                      child: Text(
                        badge > 99 ? '99+' : '$badge',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileHeader() {
    final String defaultName = _userEmail.split('@')[0];
    final String name = _profileData?['name'] ?? defaultName;
    final String emailDisplay = _userEmail;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [kDeepBlue, Color(0xFF2A4BA0)],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2.5),
                    ),
                    child: Builder(
                      builder: (_) {
                        final avatarUrl = _profileData?['avatar_url']
                            ?.toString();
                        return CircleAvatar(
                          radius: 34,
                          backgroundColor: Colors.white24,
                          backgroundImage:
                              avatarUrl != null && avatarUrl.isNotEmpty
                              ? NetworkImage(avatarUrl)
                              : null,
                          child: avatarUrl == null || avatarUrl.isEmpty
                              ? const Icon(
                                  Icons.person,
                                  size: 42,
                                  color: Colors.white,
                                )
                              : null,
                        );
                      },
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: GestureDetector(
                      onTap: _isUploadingAvatar ? null : _pickAndUploadAvatar,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white70),
                        ),
                        child: _isUploadingAvatar
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: kDeepBlue,
                                ),
                              )
                            : const Icon(
                                Icons.camera_alt,
                                size: 14,
                                color: kDeepBlue,
                              ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        'BUYER PROFILE',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      emailDisplay,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: () {
                  _showEditDialog('Name', 'name', _profileData?['name']);
                },
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.white.withValues(alpha: 0.18),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                icon: const Icon(Icons.edit, size: 16),
                label: const Text(
                  'Edit',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _ProfileStatTile(
                    icon: Icons.receipt_long_rounded,
                    value: '$_orderCount',
                    label: 'Orders',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const OrdersPage()),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ProfileStatTile(
                    icon: Icons.favorite_border_rounded,
                    value: '$_wishlistCount',
                    label: 'Wishlist',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const WishlistPage()),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ProfileStatTile(
                    icon: Icons.local_offer_outlined,
                    value: '0',
                    label: 'Vouchers',
                    onTap: null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileRow(
    String label,
    String key,
    String? value, {
    bool isEditable = false,
    Function()? onTap,
  }) {
    String displayValue = value ?? 'N/A';

    // Check if the value is a date string and format it for display (optional)
    if (key == 'birthday' && value != null && value.isNotEmpty) {
      try {
        final date = DateTime.parse(value);
        // Format as YYYY-MM-DD
        displayValue =
            '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      } catch (_) {
        displayValue = value; // Use original if parsing fails
      }
    }

    if (key == 'bio' && (value == null || value.isEmpty)) {
      displayValue = 'Set Now';
      isEditable = true;
    }

    if (key == 'email') {
      isEditable = false;
      displayValue = _userEmail;
    }

    // Determine the action when the row is tapped
    Function()? rowOnTap;
    if (key == 'birthday') {
      rowOnTap = () => _showDateEditDialog(label, key, value);
    } else if (isEditable || key == 'bio') {
      rowOnTap = () => _showEditDialog(label, key, value);
    } else {
      rowOnTap = onTap;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: rowOnTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: kDeepBlue.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(_fieldIcon(key), color: kDeepBlue, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    color: Colors.black87,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        displayValue,
                        textAlign: TextAlign.end,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: displayValue == 'Set Now'
                              ? kDeepBlue
                              : Colors.black54,
                        ),
                      ),
                    ),
                    if (rowOnTap != null)
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: Colors.grey,
                        size: 20,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSellerSection() {
    // Approved seller → show dashboard button
    if (_isSeller && _sellerStatus == 'approved') {
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ShopDashboardScreen()),
            );
          },
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF153075), Color(0xFF2A4BA0)],
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x22000000),
                  blurRadius: 12,
                  offset: Offset(0, 5),
                ),
              ],
            ),
            child: const Row(
              children: [
                Icon(Icons.storefront_rounded, color: Colors.white, size: 28),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Seller Dashboard',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Manage your store, orders & products',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_ios, color: Colors.white70, size: 16),
              ],
            ),
          ),
        ),
      );
    }

    // Pending seller → show status
    if (_isSeller && _sellerStatus == 'pending') {
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF7E8),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFFFD180)),
          ),
          child: const Row(
            children: [
              Icon(
                Icons.hourglass_top_rounded,
                color: Color(0xFF7A4A00),
                size: 24,
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Seller Application Pending',
                      style: TextStyle(
                        color: Color(0xFF7A4A00),
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Your store is under review. You\'ll get access once approved.',
                      style: TextStyle(color: Color(0xFF7A4A00), fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Suspended seller → show suspended message
    if (_isSeller && _sellerStatus == 'suspended') {
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFFEF2F2),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFFCA5A5)),
          ),
          child: const Row(
            children: [
              Icon(
                Icons.block_rounded,
                color: Color(0xFFDC2626),
                size: 24,
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Seller Account Suspended',
                      style: TextStyle(
                        color: Color(0xFFDC2626),
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Your seller account has been suspended. Please contact the administrator.',
                      style: TextStyle(color: Color(0xFF991B1B), fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Not a seller → show "Start Selling" button
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            fadeSlideRoute((_) => const ActivateQuickcartScreen()),
          );
        },
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 12,
                offset: Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: kDeepBlue.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.storefront_outlined,
                  color: kDeepBlue,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Start Selling',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: Colors.black87,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Set up your store and start earning',
                      style: TextStyle(color: Colors.black54, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios, color: Colors.grey, size: 16),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: kDeepBlue)),
      );
    }

    final profile = _profileData;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: SafeArea(
        child: RefreshIndicator(
          color: kDeepBlue,
          onRefresh: _fetchUserProfile,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
            children: [
              Row(
                children: [
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'My Profile',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildProfileHeader(),
              const SizedBox(height: 14),
              _buildSellerSection(),
              const Text(
                'Quick Actions',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _buildQuickActionTile(
                      icon: Icons.receipt_long_rounded,
                      label: 'My Orders',
                      badge: _activeOrderCount,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const OrdersPage()),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildQuickActionTile(
                      icon: Icons.location_on_outlined,
                      label: 'Addresses',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AddressesPage(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildQuickActionTile(
                      icon: Icons.map_outlined,
                      label: 'Market Map',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const MarketMapPage(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildQuickActionTile(
                      icon: Icons.support_agent_rounded,
                      label: 'Help',
                      onTap: _contactAdmin,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x14000000),
                      blurRadius: 12,
                      offset: Offset(0, 5),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    _buildProfileRow(
                      'Name',
                      'name',
                      profile?['name'],
                      isEditable: true,
                    ),
                    Divider(height: 0, color: Colors.grey.shade200),
                    _buildProfileRow('Bio', 'bio', profile?['bio']),
                    Divider(height: 0, color: Colors.grey.shade200),
                    _buildProfileRow(
                      'Gender',
                      'gender',
                      profile?['gender'],
                      onTap: () => _showGenderPicker('gender'), // ← add this
                    ),
                    Divider(height: 0, color: Colors.grey.shade200),
                    _buildProfileRow(
                      'Birthday',
                      'birthday',
                      profile?['birthday'],
                      isEditable: true,
                    ),
                    Divider(height: 0, color: Colors.grey.shade200),
                    _buildProfileRow(
                      'Phone',
                      'phone',
                      profile?['phone'],
                      isEditable: true,
                    ),
                    Divider(height: 0, color: Colors.grey.shade200),
                    _buildProfileRow('Email', 'email', _userEmail),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _signOut,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kDeepBlue,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.logout_rounded),
                label: const Text(
                  'Log Out',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileStatTile extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final VoidCallback? onTap;

  const _ProfileStatTile({
    required this.icon,
    required this.value,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
          ),
          child: Column(
            children: [
              Icon(icon, color: Colors.white, size: 16),
              const SizedBox(height: 6),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
