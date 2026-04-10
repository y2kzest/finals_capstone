import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'main.dart';

const Color kDeepBlue = Color(0xFF1E3A8A);

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

    final userEmail = user.email ?? 'N/A';

    if (mounted) {
      setState(() {
        _userEmail = userEmail;
      });
    }

    try {
      final response = await supabase
          .from('profile')
          .select()
          .eq('user_id', user.id)
          .limit(1)
          .single();

      if (mounted) {
        setState(() {
          _profileData = response;
          _isLoading = false;
        });
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

    try {
      await supabase
          .from('profile')
          .update({key: newValue})
          .eq('user_id', userId);

      if (mounted) {
        setState(() {
          _profileData = _profileData ?? {};

          if (newValue is DateTime) {
            _profileData?[key] = newValue.toIso8601String().split('T')[0];
          } else {
            _profileData?[key] = newValue;
          }

          _isLoading = false;
        });
        _showSnackBar("$key updated successfully!");
      }
    } on PostgrestException catch (e) {
      if (mounted) {
        _showSnackBar("Error updating $key: ${e.message}");
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar("An unexpected error occurred during update: $e");
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

  Widget _buildQuickActionTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
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
            Icon(icon, color: kDeepBlue, size: 24),
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
                    child: const CircleAvatar(
                      radius: 34,
                      backgroundColor: Colors.white24,
                      child: Icon(Icons.person, size: 42, color: Colors.white),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: GestureDetector(
                      onTap: () => _showSnackBar("Change profile picture TBD."),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white70),
                        ),
                        child: const Icon(
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
                  backgroundColor: Colors.white24,
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
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => _showSnackBar('Orders feature coming soon.'),
                    child: const Column(
                      children: [
                        Text(
                          '12',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Orders',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
                Container(width: 1, height: 28, color: Colors.white24),
                Expanded(
                  child: InkWell(
                    onTap: () => _showSnackBar('Wishlist feature coming soon.'),
                    child: const Column(
                      children: [
                        Text(
                          '8',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Wishlist',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
                Container(width: 1, height: 28, color: Colors.white24),
                Expanded(
                  child: InkWell(
                    onTap: () => _showSnackBar('Vouchers feature coming soon.'),
                    child: const Column(
                      children: [
                        Text(
                          '3',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Vouchers',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
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
                  IconButton(
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black87,
                    ),
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
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
                  IconButton(
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: kDeepBlue,
                    ),
                    onPressed: () {
                      _showSnackBar('Settings feature coming soon.');
                    },
                    icon: const Icon(Icons.settings_outlined),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildProfileHeader(),
              const SizedBox(height: 14),
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
                      onTap: () {
                        _showSnackBar('Orders feature coming soon.');
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildQuickActionTile(
                      icon: Icons.location_on_outlined,
                      label: 'Addresses',
                      onTap: () {
                        _showSnackBar('Address book feature coming soon.');
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildQuickActionTile(
                      icon: Icons.discount_outlined,
                      label: 'Vouchers',
                      onTap: () {
                        _showSnackBar('Vouchers feature coming soon.');
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildQuickActionTile(
                      icon: Icons.support_agent_rounded,
                      label: 'Help',
                      onTap: () {
                        _showSnackBar('Support feature coming soon.');
                      },
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
                      isEditable: true,
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
