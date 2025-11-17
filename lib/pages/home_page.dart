import 'package:flutter/material.dart';
import 'cart_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1A4DBE),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Hey, *****",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Row(
                        children: [
                          Stack(
                            children: [
                              const Icon(Icons.notifications_none, color: Colors.white, size: 28),
                              Positioned(
                                right: 0,
                                top: 0,
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
                                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(width: 16),
                          GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const CartPage()),
                              );
                            },
                            child: Stack(
                              children: [
                                const Icon(Icons.shopping_cart_outlined, color: Colors.white, size: 28),
                                Positioned(
                                  right: 0,
                                  top: 0,
                                  child: Container(
                                    height: 16,
                                    width: 16,
                                    decoration: const BoxDecoration(
                                      color: Colors.orange,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Center(
                                      child: Text(
                                        "5",
                                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    decoration: InputDecoration(
                      hintText: "Search Products or store",
                      prefixIcon: const Icon(Icons.search_rounded, color: Colors.white70),
                      filled: true,
                      fillColor: const Color(0xFF173C9E),
                      hintStyle: const TextStyle(color: Colors.white70),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    style: const TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: const [
                      Row(
                        children: [
                          Text("PICK UP", style: TextStyle(color: Colors.white70, fontSize: 12)),
                          SizedBox(width: 8),
                          Icon(Icons.location_on_outlined, color: Colors.white70, size: 16),
                          Text("Juliana CSFP ▼", style: TextStyle(color: Colors.white, fontSize: 13)),
                        ],
                      ),
                      Row(
                        children: [
                          Text("WITHIN", style: TextStyle(color: Colors.white70, fontSize: 12)),
                          SizedBox(width: 8),
                          Text("1 Hour ▼", style: TextStyle(color: Colors.white, fontSize: 13)),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text("Recommended",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.grey[900])),
            const SizedBox(height: 12),
            SizedBox(
              height: 180,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: const [
                  ProductCard(
                    title: "Tilapia",
                    price: "₱000 /kg",
                    imagePath: "assets/img/tilapia.jpg",
                  ),
                  ProductCard(
                    title: "Liempo",
                    price: "₱000 /kg",
                    imagePath: "assets/img/liempo.png",
                  ),
                  ProductCard(
                    title: "Kasim",
                    price: "₱000 /kg",
                    imagePath: "assets/img/kasim.jpg",
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ProductCard extends StatelessWidget {
  final String title;
  final String price;
  final String imagePath;

  const ProductCard({
    super.key,
    required this.title,
    required this.price,
    required this.imagePath,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 140,
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.asset(
              imagePath,
              height: 80,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(height: 8),
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const Text("Shop/Store", style: TextStyle(fontSize: 12, color: Colors.grey)),
          const Spacer(),
          Text(price, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
        ],
      ),
    );
  }
}
