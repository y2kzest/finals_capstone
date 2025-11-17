import 'package:flutter/material.dart';

class ProductViewPage extends StatelessWidget {
  final Map<String, String> product;
  const ProductViewPage({super.key, required this.product});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      body: SafeArea(
        child: Column(
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
                      "Details",
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
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
                  )
                ],
              ),
            ),

            const SizedBox(height: 10),
            const Icon(Icons.image_outlined, size: 120, color: Colors.grey),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _indicator(true), _indicator(false), _indicator(false),
              ],
            ),

            const SizedBox(height: 20),

            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(30),
                    topRight: Radius.circular(30),
                  ),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product['name']!,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "${product['price']!}/KG",
                            style: const TextStyle(fontSize: 16, color: Color(0xFF1A3C8C), fontWeight: FontWeight.bold),
                          ),
                          const Text(
                            "Reg: ₱000",
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      Row(
                        children: const [
                          Icon(Icons.star, size: 18, color: Colors.orange),
                          Icon(Icons.star, size: 18, color: Colors.orange),
                          Icon(Icons.star, size: 18, color: Colors.orange),
                          Icon(Icons.star, size: 18, color: Colors.orange),
                          Icon(Icons.star_half, size: 18, color: Colors.orange),
                          SizedBox(width: 6),
                          Text("110 Reviews", style: TextStyle(color: Colors.grey, fontSize: 12)),
                        ],
                      ),
                      const SizedBox(height: 16),

                      const Text("Details", style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      const Text(
                        "***************************************\n***************************************\n***************************************",
                        style: TextStyle(color: Colors.grey),
                      ),

                      const SizedBox(height: 20),

                      ExpansionTile(
                        title: const Text("Nutritional facts"),
                        children: const [
                          Padding(
                            padding: EdgeInsets.all(8.0),
                            child: Text("Nutrition details go here..."),
                          )
                        ],
                      ),
                      ExpansionTile(
                        title: const Text("Reviews"),
                        children: const [
                          Padding(
                            padding: EdgeInsets.all(8.0),
                            child: Text("Review section..."),
                          )
                        ],
                      ),

                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {},
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(30),
                                ),
                              ),
                              child: const Text("Add To Cart", style: TextStyle(color: Color(0xFF1A3C8C))),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {},
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF1A3C8C),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(30),
                                ),
                              ),
                              child: const Text("Buy Now"),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                    ],
                  ),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _indicator(bool active) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      height: 6,
      width: active ? 20 : 8,
      decoration: BoxDecoration(
        color: active ? Colors.orange : Colors.grey.shade300,
        borderRadius: BorderRadius.circular(10),
      ),
    );
  }
}