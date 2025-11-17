import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'main.dart'; // 👈 1. IMPORT FIX: Adjust this path if 'main.dart' is in a different location (e.g., 'main.dart' if in the same folder)

// Define a consistent color for the theme (assuming it's used elsewhere)
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

  // --- Supabase Data Fetching ---
  /// Fetches the profile data from the 'signup' table based on the logged-in user's ID.
  Future<void> _fetchUserProfile() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      if (mounted) Navigator.of(context).pop();
      return;
    }

    setState(() {
      _userEmail = user.email ?? 'N/A';
    });

    try {
      // Query the 'signup' table for the user's profile
      final response = await supabase
          .from('signup') // The table name from your RLS policy
          .select()
          .eq('user_id', user.id) // IMPORTANT: Assumes 'user_id' column links to auth.users.id
          .limit(1)
          .single();

      if (mounted) {
        setState(() {
          _profileData = response;
          _isLoading = false;
        });
      }
    } on PostgrestException catch (e) {
      // This usually happens if the profile record hasn't been created yet.
      if (mounted) {
        _showSnackBar("Profile data not found. Please complete your profile.");
        setState(() {
          _isLoading = false;
        });
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
  /// Updates a single field in the 'signup' table and refreshes the UI.
  Future<void> _updateProfileField(String key, String newValue) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      _showSnackBar("Authentication error. Please log in again.");
      return;
    }
    
    // Do nothing if the new value is the same or empty (unless key is 'bio' and it's being set)
    if (newValue == (_profileData?[key] ?? '') && newValue.isNotEmpty) {
      _showSnackBar("${key} is already set to '$newValue'.");
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Update the record where user_id matches
      await supabase.from('signup').update({key: newValue}).eq('user_id', userId);
      
      // Update local state without re-fetching everything
      if (mounted) {
        setState(() {
          _profileData?[key] = newValue; // Update the local map
          _isLoading = false;
        });
        _showSnackBar("${key} updated successfully!");
      }

    } on PostgrestException catch (e) {
      if (mounted) {
        _showSnackBar("Error updating ${key}: ${e.message}");
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
    
    // Prevent editing the email as it's typically managed by Supabase Auth
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
                // Call the update function
                _updateProfileField(key, controller.text.trim());
              },
            ),
          ],
        );
      },
    );
  }

  // --- Supabase Logout Function (The FIX) ---
  Future<void> _signOut() async {
    try {
      await supabase.auth.signOut();
      if (mounted) {
        // 2. NAVIGATION FIX: Use pushAndRemoveUntil with MaterialPageRoute 
        // to go back to the explicit LoginPage defined in your main.dart.
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (context) => const LoginPage(), // Use the imported LoginPage
          ),
          (route) => false, // Clears the entire navigation stack
        );
      }
    } catch (e) {
      _showSnackBar('Logout failed: $e');
    }
  }

  void _showSnackBar(String message) {
    // Only show snackbar if context is still valid
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  // --- UI Builder Methods ---

  Widget _buildProfileHeader() {
    // Get profile data safely, providing default placeholders
    final String name = _profileData?['name'] ?? 'Guest User';
    final String emailDisplay = _profileData?['email'] ?? _userEmail; // Use auth email if signup table doesn't have it

    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Stack(
              children: [
                // Profile Picture Placeholder
                const CircleAvatar(
                  radius: 40,
                  backgroundColor: Colors.grey,
                  child: Icon(Icons.person, size: 50, color: Colors.white),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: GestureDetector(
                    onTap: () => _showSnackBar("Change profile picture TBD."), // Add action here
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
            Column(
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
                // Edit Profile Button
                ElevatedButton(
                  onPressed: () {
                    // TODO: Implement Edit Profile Navigation or full-page edit
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
        const Divider(height: 30),
      ],
    );
  }

  Widget _buildProfileRow(String label, String key, String? value, {bool isEditable = false, Function()? onTap}) {
    // Determine the value to display, using 'Set Now' for empty Bio
    String displayValue = value ?? 'N/A';
    if (key == 'bio' && (value == null || value.isEmpty)) {
      displayValue = 'Set Now';
      isEditable = true; // Force 'Set Now' to be editable
    }
    
    // Disable editing for Email which is displayed from auth
    if (key == 'email') {
      isEditable = false;
    }

    return Column(
      children: [
        // The onTap function for the GestureDetector determines the action
        GestureDetector(
          onTap: isEditable || key == 'bio' ? () => _showEditDialog(label, key, value) : onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(label, style: const TextStyle(fontSize: 16, color: Colors.black)),
                Row(
                  children: [
                    Text(
                      displayValue,
                      style: TextStyle(
                        fontSize: 16, 
                        fontWeight: FontWeight.w500,
                        // Highlight 'Set Now' in a different color
                        color: displayValue == 'Set Now' ? kDeepBlue : Colors.black,
                      ),
                    ),
                    // Show arrow if it's editable or the Bio/Gender row
                    if (isEditable || key == 'bio') 
                      const Icon(Icons.keyboard_arrow_right, color: Colors.grey, size: 20),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (key != 'email') const Divider(height: 0), // Add divider between rows
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

    // Default values if data is not present (or loading failed to find a record)
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

              // Tappable fields (assuming keys match Supabase 'signup' table columns)
              _buildProfileRow('Name', 'name', profile?['name'], isEditable: true),

              _buildProfileRow(
                'Bio',
                'bio',
                profile?['bio'],
                // isEditable is forced true inside _buildProfileRow for 'Set Now'
              ),

              // Note: Gender and Birthday might require specialized pickers in a real app,
              // but we use the general text dialog here for demonstration.
              _buildProfileRow('Gender', 'gender', profile?['gender'], isEditable: true),
              _buildProfileRow('Birthday', 'birthday', profile?['birthday'], isEditable: true),
              _buildProfileRow('Phone', 'phone', profile?['phone'], isEditable: true),

              // Email is not editable in this widget, as it comes from Supabase Auth
              _buildProfileRow('Email', 'email', _userEmail),

              const SizedBox(height: 50),

              // Log Out Button
              Center(
                child: ElevatedButton(
                  onPressed: _signOut, // Calls your existing Supabase sign-out function
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