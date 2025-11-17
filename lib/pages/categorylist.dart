import 'package:flutter/material.dart';
import 'productlist.dart'; // ✅ Import your product list page

class CategoryListPage extends StatelessWidget {
  final String category;
  final VoidCallback? onBack;

  const CategoryListPage({
    super.key,
    required this.category,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: Color(0xFF1A4DBE),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Bar
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: onBack,
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.search, color: Colors.white),
                          onPressed: () {},
                        ),
                        Stack(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.notifications_none, color: Colors.white),
                              onPressed: () {},
                            ),
                            Positioned(
                              right: 6,
                              top: 6,
                              child: Container(
                                height: 16,
                                width: 16,
                                decoration: const BoxDecoration(
                                  color: Colors.orange,
                                  shape: BoxShape.circle,
                                ),
                                child: const Center(
                                  child: Text(
                                    "3",
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  "Shop > $category",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          // Category List
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (category == "Fishes" || category == "Meats" || category == "Meats & Fishes") ...[
                  // ✅ Big & Small Fishes clickable card
                  CategoryItemCard(
                    color: Colors.amber[100]!,
                    title: "Big & Small Fishes",
                    subtitle: "Shop/Store",
                    price: "₱230/KG",
                    onTap: () {
                      // ✅ Go to productlist.dart
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const ProductListPage()),
                      );
                    },
                  ),

                  // Other cards (optional click)
                  CategoryItemCard(
                    color: Colors.red[100]!,
                    title: "Meats",
                    subtitle: "Shop/Store",
                    price: "₱345/KG",
                  ),
                ],
                if (category == "Vegetables") ...[
                  CategoryItemCard(
                    color: Colors.green[100]!,
                    title: "Fresh Vegetables",
                    subtitle: "Shop/Store",
                    price: "₱120/KG",
                  ),
                ],
                if (category == "Fruits") ...[
                  CategoryItemCard(
                    color: Colors.pink[100]!,
                    title: "Tropical Fruits",
                    subtitle: "Shop/Store",
                    price: "₱150/KG",
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------- Item Card ----------------
class CategoryItemCard extends StatelessWidget {
  final Color color;
  final String title;
  final String subtitle;
  final String price;
  final VoidCallback? onTap; // ✅ added

  const CategoryItemCard({
    super.key,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.price,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap, // ✅ make it clickable
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              height: 60,
              width: 60,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.image, color: Colors.grey),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                  Text(subtitle,
                      style: const TextStyle(color: Colors.grey, fontSize: 13)),
                  const SizedBox(height: 4),
                  Text(
                    "Starting from $price",
                    style: const TextStyle(
                      color: Color(0xFF1A4DBE),
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}
