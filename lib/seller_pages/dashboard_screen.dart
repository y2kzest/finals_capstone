import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Import local screens (These are defined as placeholders below for completeness)

// --- Placeholder Screens (To make the file runnable in a single context) ---
// In your actual project, these classes would live in their respective .dart files.
class InventoryManagementScreen extends StatelessWidget {
  const InventoryManagementScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Inventory Management')),
      body: const Center(child: Text('Inventory Management Page')),
    );
  }
}

class OrdersPage extends StatelessWidget {
  const OrdersPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Orders')),
      body: const Center(child: Text('Orders Page')),
    );
  }
}

class AnalyticsReportScreen extends StatelessWidget {
  const AnalyticsReportScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Analytics Report')),
      body: const Center(child: Text('Analytics Report Page')),
    );
  }
}

class AddProductPage extends StatelessWidget {
  const AddProductPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add New Product')),
      body: const Center(child: Text('Add New Product Page')),
    );
  }
}
// --- End Placeholder Screens ---

const Color kPrimaryBlue = Color(0xFF283A97);

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Shop Dashboard',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const ShopDashboardScreen(),
    );
  }
}

class ShopDashboardScreen extends StatefulWidget {
  const ShopDashboardScreen({super.key});

  @override
  State<ShopDashboardScreen> createState() => _ShopDashboardScreenState();
}

class _ShopDashboardScreenState extends State<ShopDashboardScreen> {
  // State variables for dynamic data
  String _userName = 'Seller';
  String _storeName = 'Aling Mirna Market'; // Kept your default name
  bool _isLoading = true;
  // Placeholder for order count (you'd fetch this dynamically)
  final int _newOrderCount = 3;

  @override
  void initState() {
    super.initState();
    _fetchSellerData();
  }

  // Fetches the seller's name and store name from Supabase profile
  Future<void> _fetchSellerData() async {
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;

    if (userId == null) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
      return;
    }

    try {
      // Fetch data from the 'seller_profiles' table (or similar table)
      final response = await supabase
          .from('seller_profiles')
          .select('full_name, store_name')
          .eq('user_id', userId)
          .single();

      if (mounted) {
        setState(() {
          // Use the first name for a friendlier greeting
          _userName = response['full_name']?.split(' ').first ?? 'Seller';
          _storeName = response['store_name'] ?? 'Aling Mirna Market';
        });
      }
    } on PostgrestException catch (e) {
      print('Dashboard Data Fetch Error: ${e.message}');
    } catch (e) {
      print('An unexpected error occurred: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // Handles user logout
  Future<void> _logout() async {
    await Supabase.instance.client.auth.signOut();
    // In a real app, this would navigate to the login screen
    if (mounted) {
      // For testing, we just pop the current route
      Navigator.of(context).pop(); 
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: kPrimaryBlue))
          : Column(
              children: <Widget>[
                // --- Top Blue Section ---
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 50, 20, 20),
                  decoration: const BoxDecoration(
                    color: kPrimaryBlue,
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(30),
                      bottomRight: Radius.circular(30),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 10,
                        offset: Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      // Greeting and Logout Button (Replaces Cart Icon)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: <Widget>[
                          Text(
                            // Dynamic greeting
                            'Hey, $_userName',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          // Logout button
                          IconButton(
                            icon: const Icon(
                              Icons.logout,
                              color: Colors.white,
                              size: 30,
                            ),
                            onPressed: _logout,
                            tooltip: 'Logout',
                          ),
                        ],
                      ),
                      const SizedBox(height: 25),

                      // Search Bar
                      Container(
                        height: 50,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: const TextField(
                          decoration: InputDecoration(
                            prefixIcon: Icon(Icons.search, color: Colors.white70),
                            hintText: 'Search Products or store',
                            hintStyle: TextStyle(color: Colors.white70),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(vertical: 15),
                          ),
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                      const SizedBox(height: 25),

                      const Text(
                        'YOUR SHOP',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          letterSpacing: 1,
                        ),
                      ),
                      Row(
                        children: <Widget>[
                          Text(
                            // Dynamic Store Name
                            _storeName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Icon(Icons.keyboard_arrow_down, color: Colors.white),
                        ],
                      ),
                    ],
                  ),
                ),

                // --- Bottom Section with Clickable Cards ---
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(20.0),
                    children: <Widget>[
                      DashboardCard(
                        icon: Icons.person_outline,
                        title: 'Orders',
                        // Dynamic subtitle
                        subtitle: '$_newOrderCount new orders',
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const OrdersPage(),
                            ),
                          );
                        },
                      ),
                      DashboardCard(
                        icon: Icons.article_outlined,
                        title: 'Analytics',
                        subtitle: '34 new sales done',
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const AnalyticsReportScreen(),
                            ),
                          );
                        },
                      ),
                      DashboardCard(
                        icon: Icons.inventory_2_outlined,
                        title: 'Inventory',
                        subtitle: 'Your Products',
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const InventoryManagementScreen(),
                            ),
                          );
                        },
                      ),
                      DashboardCard(
                        icon: Icons.add_box_outlined, // Changed icon to a better 'add' indicator
                        title: 'Upload Products',
                        subtitle: 'Click here to add a new item',
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const AddProductPage(),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

// --- Dashboard Card Widget ---
class DashboardCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const DashboardCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Card(
        margin: const EdgeInsets.only(bottom: 15.0),
        elevation: 3, // Slightly increased elevation for better shadow
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20.0, horizontal: 15.0),
          child: Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: kPrimaryBlue.withOpacity(0.1), // Used primary color for accent
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 30, color: kPrimaryBlue), // Used primary color for icon
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios, size: 20, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }
}