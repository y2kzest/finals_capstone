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
      debugPrint('Profile fetch failed: ${e.message}. Attempting to create profile.');
      
      final defaultName = userEmail.split('@')[0];
      
      final newProfile = {
        'user_id': user.id,
        'email': userEmail, 
        'name': defaultName, 
      };

      try {
        await supabase
            .from('profile') 
            .insert(newProfile)
            .select() 
            .single();

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
            debugPrint('⚠️ REMINDER: Check INSERT RLS policy on the profile table in Supabase!');
            message = "Profile creation failed due to security policy. (Check Supabase RLS)";
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
    if (newValue.toString() == (currentValue?.toString() ?? '') && newValue.toString().isNotEmpty) {
      _showSnackBar("$key is already set.");
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await supabase.from('profile').update({key: newValue}).eq('user_id', userId);
      
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
  void _showDateEditDialog(String label, String key, String? currentValue) async {
    
    DateTime initialDate = DateTime.now().subtract(const Duration(days: 365 * 20));
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
            ), dialogTheme: DialogThemeData(backgroundColor: Colors.white),
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
          MaterialPageRoute(
            builder: (context) => const LoginPage(), 
          ),
          (route) => false, 
        );
      }
    } catch (e) {
      _showSnackBar('Logout failed: $e');
    }
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  // --- UI Builder Methods ---

  Widget _buildProfileHeader() {
    final String defaultName = _userEmail.split('@')[0];
    final String name = _profileData?['name'] ?? defaultName;
    final String emailDisplay = _userEmail;

    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                const CircleAvatar(
                  radius: 40,
                  backgroundColor: Colors.grey,
                  child: Icon(Icons.person, size: 50, color: Colors.white),
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
                        border: Border.all(color: Colors.grey.shade300)
                      ),
                      child: const Icon(Icons.camera_alt, size: 16, color: kDeepBlue),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 15),
            
            // 🛠️ The Expanded widget here correctly constrains the Column width.
            Expanded( 
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    emailDisplay,
                    style: const TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                  const SizedBox(height: 5),
                  
                  // Wrap is fine here as its children are not Expanded/Flexible
                  Wrap(
                    spacing: 8.0,
                    runSpacing: 4.0,
                    children: [
                      ElevatedButton(
                        onPressed: () {
                          _showSnackBar("Edit Profile functionality TBD. Try tapping the rows below!");
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kDeepBlue,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                          minimumSize: const Size(0, 24),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                        ),
                        child: const Text('Edit Profile', style: TextStyle(color: Colors.white, fontSize: 12)),
                      ),
                      
                     
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const Divider(height: 30),
      ],
    );
  }

  Widget _buildProfileRow(String label, String key, String? value, {bool isEditable = false, Function()? onTap}) {
    String displayValue = value ?? 'N/A';
    
    // Check if the value is a date string and format it for display (optional)
    if (key == 'birthday' && value != null && value.isNotEmpty) {
      try {
        final date = DateTime.parse(value);
        // Format as YYYY-MM-DD
        displayValue = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
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

    return Column(
      children: [
        GestureDetector(
          onTap: rowOnTap, 
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(label, style: const TextStyle(fontSize: 16, color: Colors.black)),
                
                // 🛠️ FIX APPLIED HERE: Outer Flexible constrains the inner Row.
                Flexible( 
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // Inner Flexible allows the Text to wrap/truncate within the allocated space
                      Flexible( 
                        child: Text(
                          displayValue,
                          textAlign: TextAlign.end,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16, 
                            fontWeight: FontWeight.w500,
                            color: displayValue == 'Set Now' ? kDeepBlue : Colors.black,
                          ),
                        ),
                      ),
                      if (rowOnTap != null) 
                        const Padding(
                          padding: EdgeInsets.only(left: 8.0),
                          child: Icon(Icons.keyboard_arrow_right, color: Colors.grey, size: 20),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (key != 'email') const Divider(height: 0),
      ],
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
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(25.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Back Button and Title
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.black),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Text(
                    'Profile',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Profile Header
              _buildProfileHeader(),

              // Profile Details Rows
              const SizedBox(height: 10),

              _buildProfileRow('Name', 'name', profile?['name'], isEditable: true),
              _buildProfileRow('Bio', 'bio', profile?['bio']),
              _buildProfileRow('Gender', 'gender', profile?['gender'], isEditable: true),
              _buildProfileRow('Birthday', 'birthday', profile?['birthday'], isEditable: true), 
              _buildProfileRow('Phone', 'phone', profile?['phone'], isEditable: true),
              _buildProfileRow('Email', 'email', _userEmail),

              const SizedBox(height: 50),

              // Log Out Button
              Center(
                child: ElevatedButton(
                  onPressed: _signOut, 
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kDeepBlue,
                    padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                  child: const Text(
                    'Log Out',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}