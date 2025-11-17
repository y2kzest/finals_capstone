import 'package:flutter/material.dart';
import 'productdet.dart';

class ProductListPage extends StatelessWidget {
  const ProductListPage({super.key});

  @override
  Widget build(BuildContext context) {
    final products = [
      {'name': 'Dalagang bukid', 'price': '₱000'},
      {'name': 'Bangus', 'price': '₱000'},
      {'name': 'Tilapia', 'price': '₱000'},
      {'name': 'Hipon', 'price': '₱000'},
      {'name': 'Galunggong', 'price': '₱000'},
      {'name': 'Pusit', 'price': '₱000'},
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Expanded(
                    child: Text(
                      'Big & Small Fishes',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.search),
                    onPressed: () {},
                  ),
                  Stack(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.shopping_cart_outlined),
                        onPressed: () {},
                      ),
                      Positioned(
                        right: 6,
                        top: 6,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.orange,
                            shape: BoxShape.circle,
                          ),
                          child: const Text(
                            '3',
                            style: TextStyle(fontSize: 10, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.only(left: 16.0, top: 8),
              child: Row(
                children: [
                  _filterChip('Popular', true),
                  _filterChip('Low Price', false),
                  _filterChip('Small Fishes', false),
                  _filterChip('Big Fishes', false),
                ],
              ),
            ),
            const SizedBox(height: 12),

            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: GridView.builder(
                  itemCount: products.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.85,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                  ),
                  itemBuilder: (context, index) {
                    final product = products[index];
                    return GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ProductViewPage(product: product),
                          ),
                        );
                      },
                      child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          const SizedBox(height: 12),
                          const Icon(Icons.image_outlined, size: 50, color: Colors.grey),
                          const Spacer(),
                          Text(
                            product['price']!,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            product['name']!,
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Padding(
                              padding: const EdgeInsets.only(right: 12, bottom: 12),
                              child: Container(
                                height: 28,
                                width: 28,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF1A3C8C),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.add, color: Colors.white, size: 18),
                              ),
                            ),
                          )
                        ],
                      ),
                      ),
                    );
                  },
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _filterChip(String label, bool selected) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: selected ? Colors.orange : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: selected ? Colors.white : Colors.black,
        ),
      ),
    );
  }
}
