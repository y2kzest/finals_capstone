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
      debugPrint('Dashboard Data Fetch Error: ${e.message}');
    } catch (e) {
      debugPrint('An unexpected error occurred: $e');
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
      backgroundColor: const Color(0xFFF5F6FB),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: kPrimaryBlue))
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [kPrimaryBlue, Color(0xFF2A4BA0)],
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
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: <Widget>[
                            Text(
                              'Hey, $_userName',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            IconButton(
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.white24,
                                foregroundColor: Colors.white,
                              ),
                              icon: const Icon(Icons.logout),
                              onPressed: _logout,
                              tooltip: 'Logout',
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Container(
                          height: 50,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const TextField(
                            decoration: InputDecoration(
                              prefixIcon: Icon(
                                Icons.search,
                                color: Colors.white70,
                              ),
                              hintText: 'Search products, orders, inventory',
                              hintStyle: TextStyle(color: Colors.white70),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(
                                vertical: 15,
                              ),
                            ),
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                        const SizedBox(height: 16),
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
                            Expanded(
                              child: Text(
                                _storeName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 19,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const Icon(
                              Icons.keyboard_arrow_down,
                              color: Colors.white,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: DashboardMiniStat(
                          label: 'New Orders',
                          value: '$_newOrderCount',
                          icon: Icons.receipt_long_outlined,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: DashboardMiniStat(
                          label: 'Products',
                          value: '128',
                          icon: Icons.inventory_2_outlined,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: DashboardMiniStat(
                          label: 'Sales Today',
                          value: '₱8.2K',
                          icon: Icons.trending_up_rounded,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Quick Actions',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 10),
                  DashboardCard(
                    icon: Icons.person_outline,
                    title: 'Orders',
                    subtitle: '$_newOrderCount new orders waiting for action',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const OrdersPage()),
                      );
                    },
                  ),
                  DashboardCard(
                    icon: Icons.article_outlined,
                    title: 'Analytics',
                    subtitle: 'Track revenue, traffic, and conversion trends',
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
                    subtitle: 'Manage stock levels and product availability',
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
                    icon: Icons.add_box_outlined,
                    title: 'Upload Products',
                    subtitle: 'Add a new product and publish in seconds',
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
    );
  }
}

class DashboardMiniStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const DashboardMiniStat({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: kPrimaryBlue, size: 18),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
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
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20.0, horizontal: 15.0),
          child: Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: kPrimaryBlue.withValues(
                    alpha: 0.1,
                  ), // Used primary color for accent
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  size: 30,
                  color: kPrimaryBlue,
                ), // Used primary color for icon
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
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
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
