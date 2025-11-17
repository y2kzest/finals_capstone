import 'package:flutter/material.dart';
import 'inventory.dart';
import 'order.dart';
//import 'add.dart';
import 'analytics.dart';

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

class ShopDashboardScreen extends StatelessWidget {
  const ShopDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: Column(
        children: <Widget>[
          // --- Top Blue Section ---
          Container(
            padding: const EdgeInsets.fromLTRB(20, 50, 20, 20),
            decoration: const BoxDecoration(
              color: Color(0xFF283A97),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(30),
                bottomRight: Radius.circular(30),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // Greeting and Cart Icon
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    const Text(
                      'Hey, *****',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Stack(
                      children: <Widget>[
                        const Icon(
                          Icons.shopping_bag_outlined,
                          color: Colors.white,
                          size: 30,
                        ),
                        Positioned(
                          right: 0,
                          top: 0,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: Colors.orange,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            constraints: const BoxConstraints(
                              minWidth: 18,
                              minHeight: 18,
                            ),
                            child: const Text(
                              '3',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ],
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
                  children: const <Widget>[
                    Text(
                      'Aling Mirna Market',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Icon(Icons.keyboard_arrow_down, color: Colors.white),
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
                  subtitle: '2 new orders',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => OrdersPage(),
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
                        builder: (_) => AnalyticsReportScreen(),
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
                        builder: (_) => InventoryManagementScreen(),
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
        elevation: 1,
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
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 30, color: Colors.black87),
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
